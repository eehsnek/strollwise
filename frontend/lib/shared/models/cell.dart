class CellModel {
  const CellModel({
    required this.h3Index,
    required this.ring,
    required this.reportCount,
    required this.travelerMix,
    this.localRatio,
    this.mapColor,
    required this.functionType,
    required this.confidenceScore,
    required this.crowdScore,
    required this.centroidLat,
    required this.centroidLng,
    this.dominantCategory,
    this.placeId,
    this.placeName,
  });

  final String h3Index;
  final List<List<double>> ring;
  final int reportCount;
  final String travelerMix;
  final double? localRatio;
  final String? mapColor;
  final String functionType;
  final double confidenceScore;
  final double crowdScore;
  final double centroidLat;
  final double centroidLng;
  final String? dominantCategory;
  final String? placeId;
  final String? placeName;

  factory CellModel.fromJson(Map<String, dynamic> json) {
    return CellModel(
      h3Index: (json['h3_index'] ?? '').toString(),
      ring: ((json['ring'] as List?) ?? const [])
          .whereType<List>()
          .map(
            (pt) => pt
                .whereType<num>()
                .map((v) => v.toDouble())
                .toList(growable: false),
          )
          .where((pt) => pt.length >= 2)
          .toList(growable: false),
      reportCount: (json['report_count'] as num?)?.toInt() ?? 0,
      travelerMix: (json['traveler_mix'] ?? 'mixed').toString(),
      localRatio: (json['local_ratio'] as num?)?.toDouble(),
      mapColor: json['map_color'] as String?,
      functionType: (json['function_type'] ?? 'unknown').toString(),
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0,
      crowdScore: (json['crowd_score'] as num?)?.toDouble() ?? 0,
      centroidLat: (json['centroid_lat'] as num?)?.toDouble() ?? 0,
      centroidLng: (json['centroid_lng'] as num?)?.toDouble() ?? 0,
      dominantCategory: json['dominant_category'] as String?,
      placeId: json['place_id']?.toString(),
      placeName: json['place_name'] as String?,
    );
  }
}
