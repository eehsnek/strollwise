class PlaceTagMarker {
  const PlaceTagMarker({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.validated,
  });

  final String id;
  final double latitude;
  final double longitude;

  /// True when the report is approved (`visible`); false while `pending`.
  final bool validated;

  factory PlaceTagMarker.fromJson(Map<String, dynamic> json) {
    return PlaceTagMarker(
      id: json['id']?.toString() ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      validated: json['validated'] as bool? ?? false,
    );
  }
}
