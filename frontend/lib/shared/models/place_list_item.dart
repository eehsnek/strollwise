import 'place.dart';

/// Viewport place from `GET /api/v1/places`.
class PlaceListItem {
  const PlaceListItem({
    required this.placeId,
    required this.displayName,
    required this.placeType,
    required this.polygonGeoJson,
    required this.centroidLat,
    required this.centroidLng,
    required this.reportCount,
    required this.confidenceScore,
    this.cellCount = 0,
    this.sourceH3Rings = const [],
  });

  final String placeId;
  final String displayName;
  final String placeType;
  final Map<String, dynamic> polygonGeoJson;
  final double centroidLat;
  final double centroidLng;
  final int reportCount;
  final double confidenceScore;
  final int cellCount;
  /// Per-cell hex outlines for map place-type overlay (Method A).
  final List<List<List<double>>> sourceH3Rings;

  PlaceSummary toSummary() => PlaceSummary(
        placeId: placeId,
        displayName: displayName,
        placeType: placeType,
        reportCount: reportCount,
        confidenceScore: confidenceScore,
      );

  factory PlaceListItem.fromJson(Map<String, dynamic> json) {
    final centroid = json['centroid'] as Map<String, dynamic>? ?? const {};
    return PlaceListItem(
      placeId: (json['place_id'] ?? '').toString(),
      displayName: (json['display_name'] ?? 'Place').toString(),
      placeType: (json['place_type'] ?? 'general').toString(),
      polygonGeoJson: (json['polygon_geojson'] as Map<String, dynamic>?) ??
          const {'type': 'Polygon', 'coordinates': []},
      centroidLat: _asDouble(centroid['lat']),
      centroidLng: _asDouble(centroid['lng']),
      reportCount: (json['report_count'] is num)
          ? (json['report_count'] as num).toInt()
          : 0,
      confidenceScore: _asDouble(json['confidence_score']),
      cellCount: (json['cell_count'] is num)
          ? (json['cell_count'] as num).toInt()
          : 0,
      sourceH3Rings: _parseSourceH3Rings(json['source_h3_rings']),
    );
  }

  static List<List<List<double>>> _parseSourceH3Rings(Object? raw) {
    if (raw is! List) return const [];
    return raw
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
        .where((ring) => ring.length >= 3)
        .toList(growable: false);
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
