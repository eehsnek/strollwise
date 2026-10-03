class PlaceRecommendation {
  const PlaceRecommendation({
    required this.placeId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.rating,
    this.reviewCount = 0,
    this.source = 'curated',
    this.mapsUri,
  });

  final String placeId;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final double? rating;
  final int reviewCount;
  final String source;
  final String? mapsUri;

  factory PlaceRecommendation.fromJson(Map<String, dynamic> json) {
    return PlaceRecommendation(
      placeId: (json['place_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      rating: (json['rating'] as num?)?.toDouble(),
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      source: (json['source'] ?? 'curated').toString(),
      mapsUri: json['maps_uri'] as String?,
    );
  }
}
