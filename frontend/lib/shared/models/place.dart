class PlaceSummary {
  const PlaceSummary({
    required this.placeId,
    required this.displayName,
    required this.placeType,
    this.reportCount = 0,
    this.confidenceScore = 0,
  });

  final String placeId;
  final String displayName;
  final String placeType;
  final int reportCount;
  final double confidenceScore;

  factory PlaceSummary.fromJson(Map<String, dynamic> json) {
    return PlaceSummary(
      placeId: (json['place_id'] ?? '').toString(),
      displayName: (json['display_name'] ?? 'Place').toString(),
      placeType: (json['place_type'] ?? 'general').toString(),
      reportCount: (json['report_count'] is num)
          ? (json['report_count'] as num).toInt()
          : 0,
      confidenceScore: json['confidence_score'] is num
          ? (json['confidence_score'] as num).toDouble()
          : 0,
    );
  }
}
