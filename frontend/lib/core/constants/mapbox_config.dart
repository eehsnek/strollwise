/// Mapbox access token and style for MapLibre basemaps.
///
/// Set at build/run time:
/// `flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk....`
class MapboxConfig {
  static const accessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '',
  );

  /// Mapbox GL style id (username/style). Override with dart-define if needed.
  static const styleId = String.fromEnvironment(
    'MAPBOX_STYLE',
    defaultValue: 'mapbox/streets-v12',
  );

  static const _cartoFallback =
      'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json';

  static bool get isConfigured =>
      accessToken.trim().isNotEmpty && !accessToken.contains('your_');

  /// Style URL for [MapLibreMap.styleString].
  static String get mapStyleUrl {
    if (!isConfigured) return _cartoFallback;
    final token = Uri.encodeComponent(accessToken.trim());
    final style = styleId.trim();
    return 'https://api.mapbox.com/styles/v1/$style?access_token=$token';
  }
}
