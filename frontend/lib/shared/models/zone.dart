import '../traveler_gradient.dart';
import 'place.dart';

/// Mirrors the `ZoneListItem` / `ZoneDetail` schema returned by the
/// StrollWise backend (`/api/v1/zones` and `/api/v1/zones/{id}`).
///
/// The existing UI code still references older names like `h3Index`,
/// `travelerType`, `zoneType`, `reportCount`, etc., so those are kept as
/// derived getters / computed fields for compatibility.
class ZoneModel {
  ZoneModel({
    required this.zoneId,
    required this.displayName,
    required this.behaviorType,
  this.functionType,
    required this.travelerMix,
    this.placeId,
    this.placeName,
    this.placeType,
    this.places = const [],
    required this.summary,
    required this.liveStatus,
    required this.polygonGeoJson,
    required this.boundary,
    required this.polygonParts,
    required this.centroidLat,
    required this.centroidLng,
    required this.crowdLevel,
    required this.localPresencePercent,
    this.localRatio,
    this.mapColor,
    required this.peakTimeLabel,
    required this.confidenceScore,
    required this.priorityScore,
    required this.reportCount,
    this.sourceH3Rings = const [],
    this.topActivities = const [],
    this.whyVisit,
    this.liveUpdate,
    this.nearbyZoneIds = const [],
    this.updatedAt,
  });

  /// Stable UUID identifier returned by the backend.
  final String zoneId;

  final String displayName;

  /// Raw enum value: `local_area`, `tourist_area`, `mixed_area`.
  final String behaviorType;

  /// Deprecated on zones; use [placeType] for what (school, food, …).
  final String? functionType;

  /// `local`, `mixed`, or `international` — primary map classification.
  final String travelerMix;

  final String? placeId;
  final String? placeName;
  final String? placeType;
  final List<PlaceSummary> places;

  final String? summary;
  final String liveStatus;

  /// Full GeoJSON geometry (Polygon or MultiPolygon) as returned by the API.
  final Map<String, dynamic> polygonGeoJson;

  /// Outer ring of the (first) polygon as `[lng, lat]` pairs. Stable with
  /// the old `ZoneModel.boundary` shape so map-drawing code keeps working.
  final List<List<double>> boundary;

  /// Every polygon part of the merged zone, preserving both the outer ring
  /// and any holes. Structure:
  ///
  /// ```
  /// polygonParts[partIdx][ringIdx][pointIdx] == [lng, lat]
  /// ```
  ///
  /// - `ringIdx == 0` is the outer ring.
  /// - `ringIdx > 0` are holes.
  /// - For a Polygon the list has a single part; for a MultiPolygon it has
  ///   one part per disconnected cluster.
  ///
  /// This is what the map layer should render so zones are displayed
  /// exactly as the backend defined them (not as individual H3 cells).
  final List<List<List<List<double>>>> polygonParts;

  final double centroidLat;
  final double centroidLng;

  final double crowdLevel;
  final double localPresencePercent;
  final double? localRatio;
  final String? mapColor;
  final String? peakTimeLabel;

  final double confidenceScore;
  final double priorityScore;

  /// Approximate report count. The list endpoint omits the exact number,
  /// so we derive a representative value from crowd + confidence signals.
  final int reportCount;
  final List<List<List<double>>> sourceH3Rings;

  // Optional fields only populated by the detail endpoint.
  final List<String> topActivities;
  final String? whyVisit;
  final String? liveUpdate;
  final List<String> nearbyZoneIds;
  final DateTime? updatedAt;

  // --- Legacy-compat getters used throughout the UI ----------------------

  /// Legacy stable identifier. The UI uses it to compare selection state,
  /// so we expose the zone UUID here.
  String get h3Index => zoneId;

  /// Legacy label: `Local` / `International` / `Mixed`.
  String get travelerType {
    switch (travelerMix) {
      case 'local':
        return 'Local';
      case 'international':
        return 'International';
      default:
        return 'Mixed';
    }
  }

  /// What the area is (from linked place); falls back to legacy function_type.
  String get zoneType {
    if (placeType != null && placeType!.isNotEmpty) {
      return placeType!;
    }
    switch (functionType) {
      case 'food_hotspot':
        return 'food';
      case 'student_area':
        return 'school';
      case 'transport_zone':
        return 'transport';
      case 'commercial_zone':
        return 'commercial';
      case 'residential_zone':
        return 'residential';
      case 'safety_concern':
        return 'safety';
      case 'tourist_hotspot':
        return 'tourist';
      case 'busy_zone':
        return 'busy';
      case 'emerging_zone':
        return 'emerging';
      default:
        return 'mixed';
    }
  }

  /// Legacy alias so existing `zone.popularityScore` calls keep working.
  double get popularityScore => priorityScore;

  /// Default fill / border hex codes derived from the function type. The
  /// backend no longer ships `style` metadata; the frontend owns styling.
  double get behavioralLocalRatio => TravelerGradient.localRatioForZone(this);

  String get fillColor => TravelerGradient.fillHexForRatio(behavioralLocalRatio);

  String get borderColor =>
      mapColor ?? TravelerGradient.hexForRatio(behavioralLocalRatio);

  double get opacity => 0.55;

  // ----------------------------------------------------------------------

  factory ZoneModel.fromJson(Map<String, dynamic> json) {
    final centroid = json['centroid'] as Map<String, dynamic>? ?? const {};
    final polygon =
        (json['polygon_geojson'] as Map<String, dynamic>?) ??
        const {'type': 'Polygon', 'coordinates': <List<dynamic>>[]};
    final polygonParts = _extractPolygonParts(polygon);
    final boundary = polygonParts.isNotEmpty && polygonParts.first.isNotEmpty
        ? polygonParts.first.first
        : const <List<double>>[];

    final crowdLevel = _asDouble(json['crowd_level']);
    final confidence = _asDouble(json['confidence_score']);

    return ZoneModel(
      zoneId: (json['zone_id'] ?? '').toString(),
      displayName: (json['display_name'] ?? 'Unnamed zone').toString(),
      behaviorType: (json['behavior_type'] ?? 'mixed_area').toString(),
      functionType: json['function_type'] as String?,
      travelerMix: (json['traveler_mix'] ??
              _travelerMixFromBehavior(json['behavior_type']))
          .toString(),
      placeId: json['place_id']?.toString(),
      placeName: json['place_name'] as String?,
      placeType: json['place_type'] as String?,
      places: ((json['places'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => PlaceSummary.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      summary: json['summary'] as String?,
      liveStatus: (json['live_status'] ?? 'quiet_now').toString(),
      polygonGeoJson: polygon,
      boundary: boundary,
      polygonParts: polygonParts,
      centroidLat: _asDouble(centroid['lat']),
      centroidLng: _asDouble(centroid['lng']),
      crowdLevel: crowdLevel,
      localPresencePercent: _asDouble(json['local_presence_percent']),
      localRatio: (json['local_ratio'] as num?)?.toDouble(),
      mapColor: json['map_color'] as String?,
      peakTimeLabel: json['peak_time_label'] as String?,
      confidenceScore: confidence,
      priorityScore: _asDouble(json['priority_score']),
      reportCount: (json['report_count'] is num)
          ? (json['report_count'] as num).toInt()
          : _approxReports(crowdLevel, confidence),
      sourceH3Rings: ((json['source_h3_rings'] as List?) ?? const [])
          .whereType<List>()
          .map(
            (ring) => ring
                .whereType<List>()
                .map(
                  (pt) => pt
                      .whereType<num>()
                      .map((v) => v.toDouble())
                      .toList(growable: false),
                )
                .where((pt) => pt.length >= 2)
                .toList(growable: false),
          )
          .where((ring) => ring.length >= 6)
          .toList(growable: false),
      topActivities: ((json['top_activities'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      whyVisit: json['why_visit'] as String?,
      liveUpdate: json['live_update'] as String?,
      nearbyZoneIds: ((json['nearby_zone_ids'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  /// Unpacks a GeoJSON `Polygon` or `MultiPolygon` geometry into a stable
  /// `parts[ring][point] = [lng, lat]` structure. Each part is a polygon
  /// (outer ring + optional holes). Invalid/degenerate points are dropped.
  static List<List<List<List<double>>>> _extractPolygonParts(
    Map<String, dynamic> geojson,
  ) {
    final type = (geojson['type'] ?? '').toString();
    final coords = geojson['coordinates'];
    if (coords is! List || coords.isEmpty) return const [];

    final List<dynamic> polygons;
    if (type == 'Polygon') {
      polygons = [coords];
    } else if (type == 'MultiPolygon') {
      polygons = coords;
    } else {
      return const [];
    }

    final parts = <List<List<List<double>>>>[];
    for (final poly in polygons) {
      if (poly is! List || poly.isEmpty) continue;
      final rings = <List<List<double>>>[];
      for (final ring in poly) {
        if (ring is! List) continue;
        final points = ring
            .whereType<List>()
            .map(
              (pt) => pt
                  .whereType<num>()
                  .map((v) => v.toDouble())
                  .toList(growable: false),
            )
            .where((pt) => pt.length >= 2)
            .toList();
        if (points.length >= 3) rings.add(points);
      }
      if (rings.isNotEmpty) parts.add(rings);
    }
    return parts;
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static int _approxReports(double crowd, double confidence) {
    final approx = (crowd * 40) + (confidence / 2);
    return approx < 1 ? 1 : approx.round();
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static String _travelerMixFromBehavior(Object? behavior) {
    switch (behavior?.toString()) {
      case 'local_area':
        return 'local';
      case 'tourist_area':
        return 'international';
      default:
        return 'mixed';
    }
  }
}
