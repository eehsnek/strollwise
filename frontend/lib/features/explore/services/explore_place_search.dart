import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/constants/mapbox_config.dart';
import '../../../shared/models/zone.dart';
import '../../../shared/traveler_gradient.dart';

enum ExploreSearchHitKind { zone, landmark, address }

class ExploreSearchHit {
  const ExploreSearchHit({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.location,
    required this.kind,
    this.zone,
    this.localRatio,
  });

  final String id;
  final String title;
  final String subtitle;
  final LatLng location;
  final ExploreSearchHitKind kind;
  final ZoneModel? zone;
  final double? localRatio;
}

/// Cebu metro bounding box for Nominatim (west,south,east,north).
const _cebuViewbox = '123.70,10.15,124.15,10.50';

class ExplorePlaceSearchService {
  ExplorePlaceSearchService(this._dio);

  final Dio _dio;

  static const _cebuCenter = LatLng(10.3157, 123.8854);
  static const _cebuRadiusM = 120000.0;

  static final Map<String, LatLng> _landmarks = {
    'ayala': const LatLng(10.3176, 123.9053),
    'ayala center': const LatLng(10.3176, 123.9053),
    'ayala center cebu': const LatLng(10.3176, 123.9053),
    'it park': const LatLng(10.3295, 123.9067),
    'cebu it park': const LatLng(10.3295, 123.9067),
    'it park business zone': const LatLng(10.3295, 123.9067),
    'colon': const LatLng(10.2942, 123.9017),
    'colon street': const LatLng(10.2942, 123.9017),
    'colon basilica': const LatLng(10.2942, 123.9017),
    'carbon': const LatLng(10.2933, 123.8998),
    'carbon market': const LatLng(10.2933, 123.8998),
    'magellan cross': const LatLng(10.2930, 123.9029),
    'basilica': const LatLng(10.2942, 123.9022),
    'santo nino': const LatLng(10.2942, 123.9022),
    'fort san pedro': const LatLng(10.2922, 123.9058),
    'fuente': const LatLng(10.3100, 123.8916),
    'fuente osmena': const LatLng(10.3100, 123.8916),
    'fuente osmeña': const LatLng(10.3100, 123.8916),

    'ocean park': const LatLng(10.2836, 123.8789),
    'escario': const LatLng(10.3157, 123.8919),
    'escario street': const LatLng(10.3157, 123.8919),
    'capitol site': const LatLng(10.3172, 123.8958),
    'sm city': const LatLng(10.3113, 123.9180),
    'sm city cebu': const LatLng(10.3113, 123.9180),
    'srp': const LatLng(10.2836, 123.8789),
    'south road properties': const LatLng(10.2836, 123.8789),
    'lahug': const LatLng(10.3335, 123.9030),
    'talamban': const LatLng(10.3694, 123.9185),
    'pardo': const LatLng(10.2811, 123.8456),
    'minglanilla': const LatLng(10.2446, 123.7963),
    'talisay': const LatLng(10.2449, 123.8493),
    'mactan': const LatLng(10.2998, 124.0112),
    'lapu-lapu': const LatLng(10.2998, 124.0112),
    'cebu doctors': const LatLng(10.3155, 123.8965),
    'capitol': const LatLng(10.3172, 123.8958),
  };

  Future<List<ExploreSearchHit>> search(
    String rawQuery, {
    required List<ZoneModel> zones,
    int maxResults = 8,
  }) async {
    final query = rawQuery.trim();
    if (query.length < 2) return const [];

    final q = query.toLowerCase();
    final seen = <String>{};
    final hits = <ExploreSearchHit>[];

    void add(ExploreSearchHit hit) {
      if (hits.length >= maxResults) return;
      if (!seen.add(hit.id)) return;
      hits.add(hit);
    }

    for (final zone in zones) {
      if (!_matchesTerms(_haystack(zone), q)) continue;
      add(
        ExploreSearchHit(
          id: 'zone-${zone.zoneId}',
          title: zone.displayName,
          subtitle: _zoneSubtitle(zone),
          location: LatLng(zone.centroidLat, zone.centroidLng),
          kind: ExploreSearchHitKind.zone,
          zone: enrichZoneForAreaCard(zone),
          localRatio: TravelerGradient.localRatioForZone(zone),
        ),
      );
    }

    await ZoneCatalog.ensureLoaded();
    for (final entry in ZoneCatalog.entries) {
      final hay =
          '${entry.zoneName} ${entry.city} ${entry.zoneType}'.toLowerCase();
      if (!_matchesTerms(hay, q)) continue;
      add(
        ExploreSearchHit(
          id: 'catalog-${entry.zoneId}',
          title: entry.zoneName,
          subtitle: '${entry.city} · ${_mixLabel(entry.defaultLocalRatio)}',
          location: LatLng(entry.centerLat, entry.centerLng),
          kind: ExploreSearchHitKind.landmark,
          zone: enrichZoneForAreaCard(
            _zoneForCatalogEntry(entry, zones) ??
                zoneModelFromCatalogEntry(entry),
          ),
          localRatio: entry.defaultLocalRatio,
        ),
      );
    }

    for (final place in _landmarks.entries) {
      if (!_matchesTerms(place.key, q)) continue;
      final landmarkZone = _zoneForLandmark(place.key, place.value, zones);
      add(
        ExploreSearchHit(
          id: 'landmark-${place.key}',
          title: _titleCase(place.key),
          subtitle: 'Cebu landmark',
          location: place.value,
          kind: ExploreSearchHitKind.landmark,
          zone: landmarkZone != null
              ? enrichZoneForAreaCard(landmarkZone)
              : null,
        ),
      );
    }

    final remote = await _remoteGeocodeSearch(query, limit: maxResults - hits.length);
    for (final hit in remote) {
      add(hit);
    }

    return hits;
  }

  Future<List<ExploreSearchHit>> _remoteGeocodeSearch(
    String query, {
    required int limit,
  }) async {
    if (limit <= 0) return const [];
    if (MapboxConfig.isConfigured) {
      final mapbox = await _mapboxSearch(query, limit: limit);
      if (mapbox.isNotEmpty) return mapbox;
    }
    return _nominatimSearch(query, limit: limit);
  }

  Future<List<ExploreSearchHit>> _mapboxSearch(
    String query, {
    required int limit,
  }) async {
    try {
      final token = MapboxConfig.accessToken.trim();
      final encoded = Uri.encodeComponent(query);
      final response = await _dio.getUri(
        Uri.https('api.mapbox.com', '/geocoding/v5/mapbox.places/$encoded.json', {
          'access_token': token,
          'limit': limit.clamp(1, 8).toString(),
          'proximity': '${_cebuCenter.longitude},${_cebuCenter.latitude}',
          'bbox': _cebuViewbox,
          'country': 'ph',
          'types': 'poi,place,locality,neighborhood,address',
        }),
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      final features = response.data?['features'];
      if (features is! List) return const [];

      final hits = <ExploreSearchHit>[];
      for (final raw in features) {
        if (raw is! Map) continue;
        final center = raw['center'];
        if (center is! List || center.length < 2) continue;
        final lng = (center[0] as num).toDouble();
        final lat = (center[1] as num).toDouble();
        final loc = LatLng(lat, lng);
        if (!_isWithinCebuRegion(loc)) continue;

        final title = (raw['text'] ?? query).toString().trim();
        final placeName = (raw['place_name'] ?? title).toString();
        final subtitle = _mapboxSubtitle(raw, placeName);

        hits.add(
          ExploreSearchHit(
            id: 'mapbox-${lat.toStringAsFixed(5)}-${lng.toStringAsFixed(5)}',
            title: title.isEmpty ? query : title,
            subtitle: subtitle,
            location: loc,
            kind: ExploreSearchHitKind.address,
          ),
        );
      }
      return hits;
    } catch (_) {
      return const [];
    }
  }

  static String _mapboxSubtitle(Map raw, String placeName) {
    String? placeType;
    final placeTypes = raw['place_type'];
    if (placeTypes is List && placeTypes.isNotEmpty) {
      placeType = placeTypes.first.toString();
    }
    if (placeType != null && placeType.isNotEmpty) {
      return '${_titleCase(placeType)} · Mapbox';
    }
    final parts = placeName.split(',');
    if (parts.length >= 2) {
      return parts.sublist(1, parts.length.clamp(1, 3)).join(', ').trim();
    }
    return 'Place in Cebu';
  }

  Future<List<ExploreSearchHit>> _nominatimSearch(
    String query, {
    required int limit,
  }) async {
    if (limit <= 0) return const [];
    try {
      final response = await _dio.getUri(
        Uri.https('nominatim.openstreetmap.org', '/search', {
          'format': 'json',
          'limit': limit.clamp(1, 8).toString(),
          'addressdetails': '1',
          'countrycodes': 'ph',
          'viewbox': _cebuViewbox,
          'bounded': '0',
          'q': '$query, Cebu, Philippines',
        }),
        options: Options(
          headers: const {
            'User-Agent':
                'StrollWise/1.0 (Cebu place search; demo@strollwise.local)',
          },
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final results = response.data;
      if (results is! List) return const [];

      final hits = <ExploreSearchHit>[];
      for (final raw in results) {
        if (raw is! Map) continue;
        final lat = double.tryParse(raw['lat']?.toString() ?? '');
        final lng = double.tryParse(raw['lon']?.toString() ?? '');
        if (lat == null || lng == null) continue;
        final loc = LatLng(lat, lng);
        if (!_isWithinCebuRegion(loc)) continue;

        final display = (raw['display_name'] ?? query).toString();
        final parts = display.split(',');
        final title = parts.isNotEmpty ? parts.first.trim() : query;
        final subtitle = _nominatimSubtitle(raw, parts);

        hits.add(
          ExploreSearchHit(
            id: 'osm-${lat.toStringAsFixed(5)}-${lng.toStringAsFixed(5)}',
            title: title,
            subtitle: subtitle,
            location: loc,
            kind: ExploreSearchHitKind.address,
          ),
        );
      }
      return hits;
    } catch (_) {
      return const [];
    }
  }

  static String _nominatimSubtitle(Map raw, List<String> parts) {
    final type = (raw['type'] ?? raw['class'] ?? '').toString();
    final category = (raw['category'] ?? '').toString();
    if (type.isNotEmpty && category.isNotEmpty) {
      return '${_titleCase(category)} · ${_titleCase(type)}';
    }
    if (parts.length >= 2) {
      return parts.sublist(1, parts.length.clamp(1, 3)).join(', ').trim();
    }
    return 'Street or place in Cebu';
  }

  static bool _isWithinCebuRegion(LatLng location) {
    final d = Geolocator.distanceBetween(
      _cebuCenter.latitude,
      _cebuCenter.longitude,
      location.latitude,
      location.longitude,
    );
    return d <= _cebuRadiusM;
  }

  static String _haystack(ZoneModel zone) {
    return [
      zone.displayName,
      zone.placeName ?? '',
      zone.behaviorType,
      zone.travelerMix,
      zone.zoneType,
      zone.summary ?? '',
      ...zone.topActivities,
    ].join(' ').toLowerCase();
  }

  static String _zoneSubtitle(ZoneModel zone) {
    final mix = TravelerGradient.dominanceLabel(
      TravelerGradient.localRatioForZone(zone),
    );
    if (zone.reportCount > 0) {
      return '$mix · ${zone.reportCount} tags';
    }
    return mix;
  }

  static bool _matchesTerms(String haystack, String query) {
    final terms = query.split(RegExp(r'\s+')).where((t) => t.length >= 2);
    return terms.every(haystack.contains);
  }

  static String _mixLabel(double ratio) {
    return TravelerGradient.dominanceLabel(ratio);
  }

  static ZoneModel? _zoneForCatalogEntry(
    ZoneCatalogEntry entry,
    List<ZoneModel> zones,
  ) {
    for (final zone in zones) {
      if (zone.zoneId == entry.zoneId) return zone;
      if (zone.displayName.toLowerCase() == entry.zoneName.toLowerCase()) {
        return zone;
      }
    }
    return _nearestZone(
      LatLng(entry.centerLat, entry.centerLng),
      zones,
    );
  }

  static ZoneModel? _zoneForLandmark(
    String key,
    LatLng location,
    List<ZoneModel> zones,
  ) {
    final fromMap = _nearestZone(location, zones);
    if (fromMap != null) return fromMap;
    final entry =
        ZoneCatalog.lookup(key) ?? ZoneCatalog.nearestEntry(
              location.latitude,
              location.longitude,
            );
    if (entry == null) return null;
    return _zoneForCatalogEntry(entry, zones) ??
        zoneModelFromCatalogEntry(entry);
  }

  static ZoneModel? _nearestZone(LatLng location, List<ZoneModel> zones) {
    if (zones.isEmpty) return null;
    ZoneModel? selected;
    var bestDistance = double.infinity;
    for (final zone in zones) {
      final distance = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        zone.centroidLat,
        zone.centroidLng,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        selected = zone;
      }
    }
    return bestDistance <= 750 ? selected : null;
  }

  static String _titleCase(String value) {
    return value
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
