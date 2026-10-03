import 'package:url_launcher/url_launcher.dart';

/// Opens turn-by-turn directions in the Google Maps app (or browser fallback).
class GoogleMapsLauncher {
  GoogleMapsLauncher._();

  static Future<bool> openDirections({
    required double latitude,
    required double longitude,
    required String address,
    double? originLatitude,
    double? originLongitude,
    String travelMode = 'driving',
  }) async {
    final trimmedAddress = address.trim();
    final destination = trimmedAddress.isNotEmpty
        ? trimmedAddress
        : '$latitude,$longitude';

    final query = <String, String>{
      'api': '1',
      'destination': destination,
      'travelmode': travelMode,
    };
    if (originLatitude != null && originLongitude != null) {
      query['origin'] = '$originLatitude,$originLongitude';
    }

    final httpsUri = Uri.https('www.google.com', '/maps/dir/', query);
    if (await _tryLaunch(httpsUri)) return true;

    // Coordinate fallback if the address string fails to resolve.
    if (trimmedAddress.isNotEmpty) {
      final coordQuery = Map<String, String>.from(query)
        ..['destination'] = '$latitude,$longitude';
      final coordUri = Uri.https('www.google.com', '/maps/dir/', coordQuery);
      if (await _tryLaunch(coordUri)) return true;
    }

    // Native Google Maps scheme (Android / iOS with app installed).
    final nativeUri = Uri.parse(
      'google.navigation:q=$latitude,$longitude&mode=d',
    );
    return _tryLaunch(nativeUri);
  }

  static Future<bool> _tryLaunch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

/// Human-readable destination for Google Maps search/directions.
String googleMapsDestinationAddress({
  required String displayName,
  String? placeName,
}) {
  final place = placeName?.trim();
  if (place != null && place.isNotEmpty) {
    return '$place, Cebu City, Cebu, Philippines';
  }
  final title = displayName.trim();
  if (title.isEmpty) {
    return 'Cebu City, Cebu, Philippines';
  }
  return '$title, Cebu City, Cebu, Philippines';
}
