class VisitPinModel {
  const VisitPinModel({
    required this.id,
    required this.h3Index,
    required this.latitude,
    required this.longitude,
    required this.visitCount,
    required this.lastVisitedAt,
    required this.firstVisitedAt,
    this.label,
    this.note,
    this.source = 'manual',
  });

  final String id;
  final String h3Index;
  final double latitude;
  final double longitude;
  final int visitCount;
  final DateTime lastVisitedAt;
  final DateTime firstVisitedAt;
  final String? label;
  final String? note;
  final String source;

  factory VisitPinModel.fromJson(Map<String, dynamic> json) {
    return VisitPinModel(
      id: (json['id'] ?? '').toString(),
      h3Index: (json['h3_index'] ?? '').toString(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      visitCount: (json['visit_count'] as num?)?.toInt() ?? 1,
      lastVisitedAt: DateTime.parse(
        (json['last_visited_at'] ?? DateTime.now().toIso8601String()).toString(),
      ),
      firstVisitedAt: DateTime.parse(
        (json['first_visited_at'] ?? DateTime.now().toIso8601String()).toString(),
      ),
      label: json['label'] as String?,
      note: json['note'] as String?,
      source: (json['source'] ?? 'manual').toString(),
    );
  }
}
