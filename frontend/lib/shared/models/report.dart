class ReportModel {
  ReportModel({
    required this.id,
    required this.h3Index,
    required this.category,
    required this.tags,
    required this.note,
    required this.createdAt,
    this.imageUrl,
    this.visibilityStatus,
  });

  final String id;
  final String h3Index;
  final String category;
  final List<String> tags;
  final String? note;
  final DateTime createdAt;
  final String? imageUrl;

  /// Backend `visibility_status` when present (e.g. own profile); otherwise null.
  final String? visibilityStatus;

  bool get isApprovedVisible =>
      (visibilityStatus ?? 'visible').toLowerCase() == 'visible';

  factory ReportModel.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final idStr = rawId == null ? '' : rawId.toString();
    final tagsList = (json['tags_json'] as List?) ?? (json['tags'] as List?) ?? const [];
    return ReportModel(
      id: idStr,
      h3Index: (json['h3_index'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      tags: tagsList.map((e) => e.toString()).toList(),
      note: json['note_text'] as String?,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      imageUrl: json['image_url'] as String?,
      visibilityStatus: json['visibility_status'] as String?,
    );
  }
}
