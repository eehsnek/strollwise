import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:h3_flutter/h3_flutter.dart';

import '../app/theme/colors.dart';
import 'models/cell.dart';
import 'models/zone.dart';

/// Green (#22C55E) ↔ blue (#3B82F6) behavioral gradient for map zones.
class TravelerGradient {
  static const Color local = Color(0xFF22C55E);
  static const Color international = Color(0xFF3B82F6);
  static const Color midpoint = Color(0xFF2FB7C8);

  static const int _localR = 34;
  static const int _localG = 197;
  static const int _localB = 94;
  static const int _intlR = 59;
  static const int _intlG = 130;
  static const int _intlB = 246;

  static double clampRatio(double ratio) => ratio.clamp(0.0, 1.0);

  static double localRatioFromPresence(double localPresencePercent) {
    if (localPresencePercent <= 0) return 0.5;
    return clampRatio(localPresencePercent / 100.0);
  }

  static double localRatioFromMix(
    String travelerMix, {
    double? localPresencePercent,
    double? localRatio,
  }) {
    if (localRatio != null && localRatio > 0) {
      return clampRatio(localRatio);
    }
    if (localPresencePercent != null && localPresencePercent > 0) {
      return localRatioFromPresence(localPresencePercent);
    }
    return switch (travelerMix.toLowerCase()) {
      'local' => 1.0,
      'international' => 0.0,
      _ => 0.5,
    };
  }

  static double localRatioForZone(ZoneModel zone) {
    final fromApi = zone.localRatio;
    if (fromApi != null) return clampRatio(fromApi);
    final catalog = ZoneCatalog.lookup(zone.displayName);
    if (catalog != null) return catalog.defaultLocalRatio;
    return localRatioFromMix(
      zone.travelerMix,
      localPresencePercent: zone.localPresencePercent,
    );
  }

  static double localRatioForCell(CellModel cell) {
    final fromApi = cell.localRatio;
    if (fromApi != null) return clampRatio(fromApi);
    return localRatioFromMix(cell.travelerMix);
  }

  static Color colorForRatio(double localRatio) {
    final t = clampRatio(localRatio);
    final r = (_localR * t + _intlR * (1 - t)).round();
    final g = (_localG * t + _intlG * (1 - t)).round();
    final b = (_localB * t + _intlB * (1 - t)).round();
    return Color.fromARGB(255, r, g, b);
  }

  static Color fillForRatio(double localRatio, {double blend = 0.72}) {
    final base = colorForRatio(localRatio);
    final b = blend.clamp(0.0, 1.0);
    return Color.lerp(Colors.white, base, b) ?? base.withValues(alpha: 0.35);
  }

  static String hexForRatio(double localRatio) {
    final c = colorForRatio(localRatio);
    final value = c.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static String fillHexForRatio(double localRatio, {double blend = 0.72}) {
    final c = fillForRatio(localRatio, blend: blend);
    final value = c.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static Color colorForZone(ZoneModel zone) {
    final hex = zone.mapColor;
    if (hex != null && hex.length >= 7) {
      return _colorFromHex(hex);
    }
    return colorForRatio(localRatioForZone(zone));
  }

  static Color fillForZone(ZoneModel zone) =>
      fillForRatio(localRatioForZone(zone));

  static Color colorForCell(CellModel cell) {
    final hex = cell.mapColor;
    if (hex != null && hex.length >= 7) {
      return _colorFromHex(hex);
    }
    return colorForRatio(localRatioForCell(cell));
  }

  static Color _colorFromHex(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length != 6) return midpoint;
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return midpoint;
    return Color(0xFF000000 | value);
  }

  static String dominanceLabel(double localRatio) {
    final t = clampRatio(localRatio);
    if (t >= 0.85) return 'Mostly local';
    if (t <= 0.15) return 'Mostly international';
    if (t >= 0.6) return 'Local-leaning mix';
    if (t <= 0.4) return 'Visitor-leaning mix';
    return 'Balanced mix';
  }
}

class ZoneCatalogEntry {
  const ZoneCatalogEntry({
    required this.zoneId,
    required this.zoneName,
    required this.city,
    required this.zoneType,
    required this.defaultLocalRatio,
    required this.centerLat,
    required this.centerLng,
    required this.radiusKm,
  });

  final String zoneId;
  final String zoneName;
  final String city;
  final String zoneType;
  final double defaultLocalRatio;
  final double centerLat;
  final double centerLng;
  final double radiusKm;

  factory ZoneCatalogEntry.fromJson(Map<String, dynamic> json) {
    final center = json['center'] as Map<String, dynamic>? ?? const {};
    return ZoneCatalogEntry(
      zoneId: (json['zone_id'] ?? '').toString(),
      zoneName: (json['zone_name'] ?? '').toString(),
      city: (json['city'] ?? '').toString(),
      zoneType: (json['zone_type'] ?? 'MIXED').toString(),
      defaultLocalRatio:
          (json['default_local_ratio'] as num?)?.toDouble() ??
          _ratioFromType((json['zone_type'] ?? 'MIXED').toString()),
      centerLat: (center['lat'] as num?)?.toDouble() ?? 0,
      centerLng: (center['lng'] as num?)?.toDouble() ?? 0,
      radiusKm: (json['radius_km'] as num?)?.toDouble() ?? 2.0,
    );
  }

  static double _ratioFromType(String zoneType) {
    switch (zoneType.toUpperCase()) {
      case 'LOCAL':
        return 1.0;
      case 'INTERNATIONAL':
        return 0.0;
      default:
        return 0.5;
    }
  }
}

class ZoneCatalog {
  ZoneCatalog._();

  static List<ZoneCatalogEntry>? _entries;

  static Future<void> ensureLoaded() async {
    if (_entries != null) return;
    final raw = await rootBundle.loadString(
      'assets/data/cebu_zone_catalog.json',
    );
    final list = jsonDecode(raw) as List<dynamic>;
    _entries = list
        .whereType<Map>()
        .map((e) => ZoneCatalogEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  static List<ZoneCatalogEntry> get entries {
    return _entries ?? const [];
  }

  static ZoneCatalogEntry? lookup(String displayName) {
    final key = displayName.toLowerCase().trim();
    for (final entry in entries) {
      final name = entry.zoneName.toLowerCase();
      if (name == key || key.contains(name) || name.contains(key)) {
        return entry;
      }
    }
    return null;
  }

  static ZoneCatalogEntry? entryForZoneId(String zoneId) {
    final id = zoneId.trim().toUpperCase();
    for (final entry in entries) {
      if (entry.zoneId.toUpperCase() == id) return entry;
    }
    return null;
  }

  static ZoneCatalogEntry? entryForZone(ZoneModel zone) {
    return entryForZoneId(zone.zoneId) ?? lookup(zone.displayName);
  }

  /// Nearest catalog zone centroid to a map point (offline / API fallback).
  static ZoneCatalogEntry? nearestEntry(double lat, double lng) {
    final list = entries;
    if (list.isEmpty) return null;
    ZoneCatalogEntry? best;
    var bestKm = double.infinity;
    for (final entry in list) {
      final km = _haversineKm(lat, lng, entry.centerLat, entry.centerLng);
      if (km < bestKm) {
        bestKm = km;
        best = entry;
      }
    }
    return best;
  }
}

const int _catalogH3Resolution = 8;

int _kRingForRadiusKm(double radiusKm) {
  if (radiusKm <= 1.6) return 2;
  if (radiusKm <= 2.0) return 3;
  if (radiusKm <= 2.6) return 4;
  if (radiusKm <= 3.2) return 5;
  if (radiusKm <= 4.2) return 6;
  return 7;
}

int _maxCellsForRadiusKm(double radiusKm) {
  if (radiusKm <= 1.6) return 15;
  if (radiusKm <= 2.0) return 25;
  if (radiusKm <= 2.6) return 35;
  if (radiusKm <= 3.2) return 45;
  if (radiusKm <= 4.2) return 60;
  return 72;
}

List<H3Index> _catalogH3CellsForEntry(H3 h3, ZoneCatalogEntry entry) {
  final seed = h3.geoToCell(
    GeoCoord(lon: entry.centerLng, lat: entry.centerLat),
    _catalogH3Resolution,
  );
  final k = _kRingForRadiusKm(entry.radiusKm);
  final disk = h3.gridDisk(seed, k);
  final within = <({double km, H3Index cell})>[];
  for (final cell in disk) {
    final geo = h3.cellToGeo(cell);
    final km = _haversineKm(
      entry.centerLat,
      entry.centerLng,
      geo.lat,
      geo.lon,
    );
    if (km <= entry.radiusKm) {
      within.add((km: km, cell: cell));
    }
  }
  if (within.isEmpty) return [seed];
  within.sort((a, b) => a.km.compareTo(b.km));
  final cap = _maxCellsForRadiusKm(entry.radiusKm);
  return within.take(cap).map((e) => e.cell).toList(growable: false);
}

List<List<List<double>>> catalogH3RingsForEntry(ZoneCatalogEntry entry) {
  final h3 = const H3Factory().load();
  final cells = _catalogH3CellsForEntry(h3, entry);
  final rings = <List<List<double>>>[];
  for (final cell in cells) {
    final boundary = h3.cellToBoundary(cell);
    if (boundary.length < 3) continue;
    final ring = boundary.map((g) => <double>[g.lon, g.lat]).toList();
    if (ring.isEmpty) continue;
    final first = ring.first;
    final last = ring.last;
    if (first[0] != last[0] || first[1] != last[1]) {
      ring.add([first[0], first[1]]);
    }
    if (ring.length >= 4) rings.add(ring);
  }
  return rings;
}

class _CatalogZonePreview {
  const _CatalogZonePreview({
    required this.reportCount,
    required this.confidenceScore,
    required this.crowdLevel,
    required this.liveStatus,
    required this.peakTimeLabel,
    required this.summary,
    required this.placeType,
  });

  final int reportCount;
  final double confidenceScore;
  final double crowdLevel;
  final String liveStatus;
  final String peakTimeLabel;
  final String summary;
  final String placeType;
}

_CatalogZonePreview _catalogPreviewFor(ZoneCatalogEntry entry) {
  final ratio = entry.defaultLocalRatio;
  final localPct = (ratio * 100).round();
  final intlPct = 100 - localPct;
  return switch (entry.zoneId) {
    'Z001' => _CatalogZonePreview(
        reportCount: 24,
        confidenceScore: 61,
        crowdLevel: 0.42,
        liveStatus: 'moderate',
        peakTimeLabel: '6AM–10AM',
        summary: 'Campus corridor · daily local movement',
        placeType: 'school',
      ),
    'Z002' => _CatalogZonePreview(
        reportCount: 19,
        confidenceScore: 58,
        crowdLevel: 0.38,
        liveStatus: 'moderate',
        peakTimeLabel: '5AM–9AM',
        summary: 'Residential south · markets and jeepney hubs',
        placeType: 'residential',
      ),
    'Z003' => _CatalogZonePreview(
        reportCount: 16,
        confidenceScore: 55,
        crowdLevel: 0.35,
        liveStatus: 'quiet_now',
        peakTimeLabel: '7AM–11AM',
        summary: 'Suburban Minglanilla · local commerce',
        placeType: 'residential',
      ),
    'Z004' => _CatalogZonePreview(
        reportCount: 18,
        confidenceScore: 57,
        crowdLevel: 0.36,
        liveStatus: 'moderate',
        peakTimeLabel: '6AM–10AM',
        summary: 'Talisay housing belt · schools and services',
        placeType: 'residential',
      ),
    'Z005' => _CatalogZonePreview(
        reportCount: 44,
        confidenceScore: 74,
        crowdLevel: 0.78,
        liveStatus: 'busy_now',
        peakTimeLabel: '10AM–8PM',
        summary: 'Resort coast · hotels and airport visitors',
        placeType: 'tourist',
      ),
    'Z006' => _CatalogZonePreview(
        reportCount: 50,
        confidenceScore: 77,
        crowdLevel: 0.82,
        liveStatus: 'busy_now',
        peakTimeLabel: '4PM–9PM',
        summary: 'Heritage core · basilica and Magellan cross foot traffic',
        placeType: 'tourist',
      ),
    'Z007' => _CatalogZonePreview(
        reportCount: 48,
        confidenceScore: 76,
        crowdLevel: 0.8,
        liveStatus: 'busy_now',
        peakTimeLabel: '11AM–10PM',
        summary: 'BPO towers · cafes and expat nightlife',
        placeType: 'commercial',
      ),
    'Z008' => _CatalogZonePreview(
        reportCount: 41,
        confidenceScore: 72,
        crowdLevel: 0.75,
        liveStatus: 'busy_now',
        peakTimeLabel: '5PM–11PM',
        summary: 'SRP belt · entertainment and waterfront visitors',
        placeType: 'tourist',
      ),
    'Z009' => _CatalogZonePreview(
        reportCount: 46,
        confidenceScore: 75,
        crowdLevel: 0.77,
        liveStatus: 'busy_now',
        peakTimeLabel: '11AM–9PM',
        summary: 'Mall district · $localPct% local / $intlPct% visitor overlap',
        placeType: 'commercial',
      ),
    'Z010' => _CatalogZonePreview(
        reportCount: 42,
        confidenceScore: 73,
        crowdLevel: 0.74,
        liveStatus: 'busy_now',
        peakTimeLabel: '4PM–9PM',
        summary: 'Fuente circle · hospitals, hotels, jeepney hub',
        placeType: 'commercial',
      ),
    'Z011' => _CatalogZonePreview(
        reportCount: 40,
        confidenceScore: 71,
        crowdLevel: 0.72,
        liveStatus: 'busy_now',
        peakTimeLabel: '10AM–9PM',
        summary: 'SM & port corridor · shopping and ferry passengers',
        placeType: 'commercial',
      ),
    'Z012' => _CatalogZonePreview(
        reportCount: 47,
        confidenceScore: 76,
        crowdLevel: 0.79,
        liveStatus: 'busy_now',
        peakTimeLabel: '5AM–12PM',
        summary: 'Carbon market · local trade with tourist curiosity',
        placeType: 'food',
      ),
    'Z013' => _CatalogZonePreview(
        reportCount: 38,
        confidenceScore: 70,
        crowdLevel: 0.68,
        liveStatus: 'moderate',
        peakTimeLabel: '8AM–10PM',
        summary: 'Lahug mix · IT Park spillover and university cafes',
        placeType: 'commercial',
      ),
    'Z014' => _CatalogZonePreview(
        reportCount: 36,
        confidenceScore: 69,
        crowdLevel: 0.66,
        liveStatus: 'moderate',
        peakTimeLabel: '7AM–9PM',
        summary: 'Escario ridge · hospitals and condo dining',
        placeType: 'commercial',
      ),
    _ => _CatalogZonePreview(
        reportCount: 22,
        confidenceScore: 58,
        crowdLevel: 0.45,
        liveStatus: 'moderate',
        peakTimeLabel: '4PM–9PM',
        summary: '${entry.zoneName} · ${entry.city}',
        placeType: entry.zoneType.toUpperCase() == 'LOCAL'
            ? 'residential'
            : entry.zoneType.toUpperCase() == 'INTERNATIONAL'
                ? 'tourist'
                : 'commercial',
      ),
  };
}

/// Offline / API-miss fallback zone with full area-intelligence card fields.
ZoneModel zoneModelFromCatalogEntry(ZoneCatalogEntry entry) {
  final ratio = entry.defaultLocalRatio;
  final travelerMix = ratio >= 0.85
      ? 'local'
      : ratio <= 0.15
          ? 'international'
          : 'mixed';
  final functionType = switch (entry.zoneType.toUpperCase()) {
    'LOCAL' => 'residential_zone',
    'INTERNATIONAL' => 'tourist_hotspot',
    _ => 'commercial_zone',
  };
  final preview = _catalogPreviewFor(entry);
  final h3Rings = catalogH3RingsForEntry(entry);
  final boundary = h3Rings.isNotEmpty ? h3Rings.first : <List<double>>[];
  final behaviorType = switch (travelerMix) {
    'local' => 'local_area',
    'international' => 'tourist_area',
    _ => 'mixed_area',
  };
  return ZoneModel(
    zoneId: entry.zoneId,
    displayName: entry.zoneName,
    behaviorType: behaviorType,
    functionType: functionType,
    travelerMix: travelerMix,
    placeName: entry.zoneName,
    placeType: preview.placeType,
    summary: preview.summary,
    liveStatus: preview.liveStatus,
    polygonGeoJson: {
      'type': 'Polygon',
      'coordinates': [boundary],
    },
    boundary: boundary,
    polygonParts: h3Rings.isEmpty
        ? const []
        : [
            for (final ring in h3Rings) [ring],
          ],
    sourceH3Rings: h3Rings,
    centroidLat: entry.centerLat,
    centroidLng: entry.centerLng,
    crowdLevel: preview.crowdLevel,
    localPresencePercent: ratio * 100,
    localRatio: ratio,
    peakTimeLabel: preview.peakTimeLabel,
    confidenceScore: preview.confidenceScore,
    priorityScore: preview.confidenceScore,
    reportCount: preview.reportCount,
    updatedAt: DateTime.now().subtract(const Duration(hours: 8)),
  );
}

/// Ensures every catalog zone can show the full Explore area card.
ZoneModel enrichZoneForAreaCard(ZoneModel zone) {
  if (zone.reportCount >= 8 && zone.confidenceScore >= 45) {
    return zone;
  }
  final entry = ZoneCatalog.entryForZone(zone);
  if (entry == null) return zone;
  final preview = zoneModelFromCatalogEntry(entry);
  return ZoneModel(
    zoneId: zone.zoneId.isNotEmpty ? zone.zoneId : preview.zoneId,
    displayName: zone.displayName.isNotEmpty ? zone.displayName : preview.displayName,
    behaviorType: zone.behaviorType.isNotEmpty ? zone.behaviorType : preview.behaviorType,
    functionType: zone.functionType ?? preview.functionType,
    travelerMix: zone.travelerMix.isNotEmpty ? zone.travelerMix : preview.travelerMix,
    placeId: zone.placeId ?? preview.placeId,
    placeName: zone.placeName ?? preview.placeName,
    placeType: zone.placeType ?? preview.placeType,
    places: zone.places.isNotEmpty ? zone.places : preview.places,
    summary: (zone.summary != null && zone.summary!.trim().isNotEmpty)
        ? zone.summary
        : preview.summary,
    liveStatus: zone.liveStatus != 'unknown' && zone.liveStatus.isNotEmpty
        ? zone.liveStatus
        : preview.liveStatus,
    polygonGeoJson: zone.polygonGeoJson,
    boundary: zone.boundary.length >= 3 ? zone.boundary : preview.boundary,
    polygonParts: zone.polygonParts.isNotEmpty ? zone.polygonParts : preview.polygonParts,
    sourceH3Rings:
        zone.sourceH3Rings.isNotEmpty ? zone.sourceH3Rings : preview.sourceH3Rings,
    centroidLat: zone.centroidLat,
    centroidLng: zone.centroidLng,
    crowdLevel: zone.crowdLevel > 0 ? zone.crowdLevel : preview.crowdLevel,
    localPresencePercent: zone.localPresencePercent > 0
        ? zone.localPresencePercent
        : preview.localPresencePercent,
    localRatio: zone.localRatio ?? preview.localRatio,
    mapColor: zone.mapColor,
    peakTimeLabel: (zone.peakTimeLabel != null && zone.peakTimeLabel!.isNotEmpty)
        ? zone.peakTimeLabel
        : preview.peakTimeLabel,
    confidenceScore: zone.confidenceScore >= 40
        ? zone.confidenceScore
        : preview.confidenceScore,
    priorityScore: zone.priorityScore > 0 ? zone.priorityScore : preview.priorityScore,
    reportCount: zone.reportCount >= 5 ? zone.reportCount : preview.reportCount,
    topActivities: zone.topActivities.isNotEmpty
        ? zone.topActivities
        : preview.topActivities,
    whyVisit: zone.whyVisit ?? preview.whyVisit,
    liveUpdate: zone.liveUpdate ?? preview.liveUpdate,
    nearbyZoneIds: zone.nearbyZoneIds.isNotEmpty
        ? zone.nearbyZoneIds
        : preview.nearbyZoneIds,
    updatedAt: zone.updatedAt ?? preview.updatedAt,
  );
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.asin(math.sqrt(a));
  return earthRadiusKm * c;
}

double _toRad(double deg) => deg * (3.141592653589793 / 180.0);

/// Gradient strip legend: green (local) → cyan → blue (international).
class TravelerBehaviorGradientLegend extends StatelessWidget {
  const TravelerBehaviorGradientLegend({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Behavior hue',
          style: TextStyle(
            color: AppColors.primaryText,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 4),
          const Text(
            'Green = local life · Blue = visitor flow · Teal = overlap',
            style: TextStyle(
              color: AppColors.mutedText,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Container(
          height: compact ? 10 : 14,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: const LinearGradient(
              colors: [
                TravelerGradient.local,
                Color(0xFF38BFA0),
                TravelerGradient.midpoint,
                Color(0xFF3696E8),
                TravelerGradient.international,
              ],
            ),
            border: Border.all(color: AppColors.border),
          ),
        ),
        const SizedBox(height: 6),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Local',
              style: TextStyle(
                color: AppColors.localAccent,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Mixed',
              style: TextStyle(
                color: AppColors.mixedAccent,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'International',
              style: TextStyle(
                color: AppColors.touristAccent,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
