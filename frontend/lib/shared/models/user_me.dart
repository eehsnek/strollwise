class UserMeModel {
  UserMeModel({
    required this.email,
    this.displayName,
    this.manualMapLat,
    this.manualMapLng,
    required this.travelerType,
    this.countryOfOrigin,
    this.cityOfOrigin,
    this.userType,
    required this.isAdmin,
    required this.acceptedResearchConsent,
  });

  final String email;
  final String? displayName;
  final double? manualMapLat;
  final double? manualMapLng;
  final String travelerType;
  final String? countryOfOrigin;
  final String? cityOfOrigin;
  final String? userType;
  final bool isAdmin;
  final bool acceptedResearchConsent;

  factory UserMeModel.fromJson(Map<String, dynamic> json) {
    return UserMeModel(
      email: (json['email'] ?? '').toString(),
      displayName: json['display_name'] as String?,
      manualMapLat: (json['manual_map_lat'] as num?)?.toDouble(),
      manualMapLng: (json['manual_map_lng'] as num?)?.toDouble(),
      travelerType: (json['traveler_type'] ?? 'mixed').toString(),
      countryOfOrigin: json['country_of_origin'] as String?,
      cityOfOrigin: json['city_of_origin'] as String?,
      userType: json['user_type'] as String?,
      isAdmin: json['is_admin'] == true,
      acceptedResearchConsent: json['accepted_research_consent'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'display_name': displayName,
      'manual_map_lat': manualMapLat,
      'manual_map_lng': manualMapLng,
      'traveler_type': travelerType,
      'country_of_origin': countryOfOrigin,
      'city_of_origin': cityOfOrigin,
      'user_type': userType,
      'is_admin': isAdmin,
      'accepted_research_consent': acceptedResearchConsent,
    };
  }
}
