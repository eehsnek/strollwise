import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class MapViewport {
  const MapViewport({
    required this.center,
    required this.zoom,
    required this.minLat,
    required this.minLng,
    required this.maxLat,
    required this.maxLng,
  });

  final LatLng center;
  final double zoom;
  final double minLat;
  final double minLng;
  final double maxLat;
  final double maxLng;

  MapViewport copyWith({
    LatLng? center,
    double? zoom,
    double? minLat,
    double? minLng,
    double? maxLat,
    double? maxLng,
  }) {
    return MapViewport(
      center: center ?? this.center,
      zoom: zoom ?? this.zoom,
      minLat: minLat ?? this.minLat,
      minLng: minLng ?? this.minLng,
      maxLat: maxLat ?? this.maxLat,
      maxLng: maxLng ?? this.maxLng,
    );
  }

  /// Legacy helper kept for any remaining call sites that expect a single
  /// `minLng,minLat,maxLng,maxLat` string.
  String get bbox => '$minLng,$minLat,$maxLng,$maxLat';
}

/// True when the map bbox or zoom changed enough to warrant refetching zones/cells.
bool mapViewportChangedSignificantly(MapViewport previous, MapViewport next) {
  final prevLatSpan = (previous.maxLat - previous.minLat).abs();
  final prevLngSpan = (previous.maxLng - previous.minLng).abs();
  final nextLatSpan = (next.maxLat - next.minLat).abs();
  final nextLngSpan = (next.maxLng - next.minLng).abs();

  final latSpanDelta = (nextLatSpan - prevLatSpan).abs();
  final lngSpanDelta = (nextLngSpan - prevLngSpan).abs();
  const spanThreshold = 0.0008;

  if (latSpanDelta > spanThreshold || lngSpanDelta > spanThreshold) {
    return true;
  }

  if ((next.zoom - previous.zoom).abs() >= 0.35) {
    return true;
  }

  final centerMoveMeters = Geolocator.distanceBetween(
    previous.center.latitude,
    previous.center.longitude,
    next.center.latitude,
    next.center.longitude,
  );
  if (centerMoveMeters >= 120) {
    return true;
  }

  const edgeThresholdDegrees = 0.0012;
  if ((next.minLat - previous.minLat).abs() > edgeThresholdDegrees ||
      (next.maxLat - previous.maxLat).abs() > edgeThresholdDegrees ||
      (next.minLng - previous.minLng).abs() > edgeThresholdDegrees ||
      (next.maxLng - previous.maxLng).abs() > edgeThresholdDegrees) {
    return true;
  }

  return false;
}

bool latLngChangedSignificantly(LatLng? previous, LatLng next,
    {double minMeters = 40}) {
  if (previous == null) return true;
  final meters = Geolocator.distanceBetween(
    previous.latitude,
    previous.longitude,
    next.latitude,
    next.longitude,
  );
  return meters >= minMeters;
}
