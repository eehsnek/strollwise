import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:h3_flutter/h3_flutter.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../app/theme/colors.dart';
import '../../../shared/models/cell.dart';
import '../../../shared/models/current_zone_overview.dart';
import '../../../shared/models/layer_settings.dart';
import '../../../shared/models/place_list_item.dart';
import '../../../shared/models/zone.dart';
import '../../../shared/maps/google_maps_launcher.dart';
import '../../../shared/network/api_client.dart';
import '../../../shared/map/map_viewport.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/notifications/app_notification_sheet.dart';
import '../../../shared/notifications/app_notifications.dart';
import '../../../shared/traveler_gradient.dart';
import '../../../shared/zone_place_ui.dart';
import '../../../shared/zone_validation_metrics.dart';
import 'cell_detail_sheet.dart';
import 'explore_area_insight_card.dart';
import 'explore_map_filters.dart';
import '../services/explore_place_search.dart';
import '../../zones/presentation/zone_detail_sheet.dart';

enum ExploreMapMode { discovery, zoneSelected }

enum _LocationBootstrapState {
  locating,
  permissionDenied,
  serviceDisabled,
  ready,
}

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  MapLibreMapController? _controller;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _exploreFlashClearTimer;
  bool _showMap = false;
  bool _isUpdatingViewport = false;
  bool _didBootstrapLocation = false;
  bool _didApplyCurrentZone = false;
  bool _mapStyleLoaded = false;
  bool _zoneLayersAdded = false;
  String? _zoneBelowLayerId;
  List<ZoneModel> _latestZones = const [];
  List<CellModel> _latestCells = const [];
  bool _usingManualLocation = false;
  bool _followUser = true;
  String? _lastTappedZoneId;
  int _sameZoneTapCount = 0;
  final Set<String> _enabledLayerKeys = {
    'local',
    'international',
    'mixed',
    'commercial',
    'food',
    'transport',
    'school',
    'tourist',
    'safety',
    'hotel',
  };
  _LocationBootstrapState _locationState = _LocationBootstrapState.locating;
  ExploreMapMode _mapMode = ExploreMapMode.discovery;
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<ExploreSearchHit> _searchHits = const [];
  String? _searchFeedback;
  bool _searchBusy = false;
  Timer? _searchDebounce;
  Timer? _viewportIdleDebounce;
  Timer? _zoneLookupDebounce;
  DateTime? _lastFollowCameraAt;
  LatLng? _lastFollowCameraTarget;
  LatLng? _lastZoneLookupLocation;
  ExplorePlaceSearchService? _placeSearchService;
  int _searchRequestGen = 0;
  static const _cebuCityCenter = LatLng(10.3157, 123.8854);
  static const _defaultZoom = 14.7;
  static const _cebuRegionRadiusMeters = 120000.0;
  static const _zonesSourceId = 'zones-source';
  static const _zonesFillLayerId = 'zones-fill';
  static const _zonesLineLayerId = 'zones-line';
  @override
  void initState() {
    super.initState();
    unawaited(ZoneCatalog.ensureLoaded());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _showMap = true);
        }
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final postCue = ref.read(explorePostSubmitCueProvider);
      if (postCue != null) {
        _applyPostSubmitCue(postCue);
        return;
      }
      if (_consumeExploreFocus()) return;
      final pendingGps = ref.read(explorePendingGpsCenterProvider);
      if (pendingGps) {
        ref.read(explorePendingGpsCenterProvider.notifier).state = false;
        _didBootstrapLocation = false;
        unawaited(_bootstrapCurrentLocation(force: true));
        return;
      }
      _ensureDefaultCebuViewport();
      _bootstrapCurrentLocation();
    });
  }

  bool _consumeExploreFocus() {
    final focus = ref.read(exploreFocusLocationProvider);
    if (focus == null) return false;
    ref.read(exploreFocusLocationProvider.notifier).state = null;
    ref.read(currentUserLocationProvider.notifier).state = focus;
    if (mounted) {
      setState(() {
        _usingManualLocation = true;
        _followUser = false;
        _locationState = _LocationBootstrapState.ready;
      });
    }
    unawaited(_moveCameraToLocation(focus, zoom: 15.2));
    return true;
  }

  void _applyPostSubmitCue(ExplorePostSubmitCue cue) {
    ref.read(explorePostSubmitCueProvider.notifier).state = null;
    ref.read(exploreFocusLocationProvider.notifier).state = cue.focus;
    ref.read(exploreFlashPinProvider.notifier).state = cue.focus;
    _exploreFlashClearTimer?.cancel();
    _exploreFlashClearTimer = Timer(const Duration(seconds: 14), () {
      if (!mounted) return;
      ref.read(exploreFlashPinProvider.notifier).state = null;
      final zones = ref.read(visibleZonesProvider).valueOrNull ?? _latestZones;
      unawaited(_drawZones(zones));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _consumeExploreFocus();
      await _moveCameraToLocation(cue.focus, zoom: 16.4);
      final zones = ref.read(visibleZonesProvider).valueOrNull ?? _latestZones;
      await _drawZones(zones);
    });
  }

  Future<void> _bootstrapCurrentLocation({bool force = false}) async {
    if (_didBootstrapLocation && !force) return;
    _didBootstrapLocation = true;
    if (mounted) {
      setState(() => _locationState = _LocationBootstrapState.locating);
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        final applied = await _applyServerManualLocationIfAvailable();
        if (!applied && mounted) {
          setState(
            () => _locationState = _LocationBootstrapState.serviceDisabled,
          );
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        final applied = await _applyServerManualLocationIfAvailable();
        if (!applied && mounted) {
          setState(
            () => _locationState = _LocationBootstrapState.permissionDenied,
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      final detectedLocation = LatLng(position.latitude, position.longitude);

      if (!_isWithinCebuRegion(detectedLocation)) {
        final applied = await _applyServerManualLocationIfAvailable();
        if (!applied && mounted) {
          setState(() {
            _usingManualLocation = false;
            _locationState = _LocationBootstrapState.ready;
          });
          ref.read(currentUserLocationProvider.notifier).state = _cebuCityCenter;
          await _moveCameraToLocation(_cebuCityCenter, zoom: _defaultZoom);
        }
        return;
      }

      setState(() {
        _usingManualLocation = false;
        _locationState = _LocationBootstrapState.ready;
      });
      ref.read(currentUserLocationProvider.notifier).state = detectedLocation;
      _startLiveLocationTracking();
      await _moveCameraToLocation(detectedLocation, zoom: 13.5);
    } catch (_) {
      final applied = await _applyServerManualLocationIfAvailable();
      if (!applied && mounted) {
        setState(
          () => _locationState = _LocationBootstrapState.serviceDisabled,
        );
      }
    }
  }

  /// Uses [userMeProvider] manual map coordinates when GPS is unavailable.
  Future<bool> _applyServerManualLocationIfAvailable() async {
    try {
      final token = ref.read(authTokenProvider);
      if (token == null || token == 'demo-token-local') return false;
      final me = await ref.read(userMeProvider.future);
      final lat = me?.manualMapLat;
      final lng = me?.manualMapLng;
      if (lat == null || lng == null || !mounted) return false;
      final here = LatLng(lat, lng);
      if (!_isWithinCebuRegion(here)) return false;
      ref.read(currentUserLocationProvider.notifier).state = here;
      setState(() {
        _usingManualLocation = true;
        _locationState = _LocationBootstrapState.ready;
      });
      await _moveCameraToLocation(here, zoom: 14.5);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _moveCameraToLocation(
    LatLng target, {
    double zoom = _defaultZoom,
  }) async {
    const latDelta = 0.05;
    const lngDelta = 0.05;
    final next = MapViewport(
      center: target,
      zoom: zoom,
      minLat: target.latitude - latDelta,
      minLng: target.longitude - lngDelta,
      maxLat: target.latitude + latDelta,
      maxLng: target.longitude + lngDelta,
    );
    _applyMapViewport(next, refetchData: true);
    final controller = _controller;
    if (controller != null) {
      await controller.moveCamera(CameraUpdate.newLatLngZoom(target, zoom));
    }
    _scheduleZoneLookupUpdate(target, immediate: true);
  }

  void _applyMapViewport(MapViewport next, {required bool refetchData}) {
    ref.read(mapViewportProvider.notifier).state = next;
    if (!refetchData) return;
    final dataViewport = ref.read(dataFetchViewportProvider);
    if (!mapViewportChangedSignificantly(dataViewport, next)) return;
    ref.read(dataFetchViewportProvider.notifier).state = next;
  }

  void _scheduleZoneLookupUpdate(LatLng location, {bool immediate = false}) {
    if (!latLngChangedSignificantly(_lastZoneLookupLocation, location)) {
      return;
    }
    _zoneLookupDebounce?.cancel();
    if (immediate) {
      _lastZoneLookupLocation = location;
      ref.read(zoneLookupLocationProvider.notifier).state = location;
      return;
    }
    _zoneLookupDebounce = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      _lastZoneLookupLocation = location;
      ref.read(zoneLookupLocationProvider.notifier).state = location;
    });
  }

  void _scheduleViewportRefresh() {
    _viewportIdleDebounce?.cancel();
    _viewportIdleDebounce = Timer(const Duration(milliseconds: 380), () {
      if (!mounted) return;
      unawaited(_refreshViewportZones());
    });
  }

  Future<void> _ensureDefaultCebuViewport() async {
    final currentUserLocation = ref.read(currentUserLocationProvider);
    if (currentUserLocation != null &&
        _isWithinCebuRegion(currentUserLocation)) {
      return;
    }
    ref.read(currentUserLocationProvider.notifier).state = _cebuCityCenter;
    await _moveCameraToLocation(_cebuCityCenter, zoom: _defaultZoom);
  }

  bool _isWithinCebuRegion(LatLng location) {
    final distanceMeters = Geolocator.distanceBetween(
      location.latitude,
      location.longitude,
      _cebuCityCenter.latitude,
      _cebuCityCenter.longitude,
    );
    return distanceMeters <= _cebuRegionRadiusMeters;
  }

  ExplorePlaceSearchService get _placeSearch =>
      _placeSearchService ??= ExplorePlaceSearchService(ref.read(dioProvider));

  /// GeoJSON polygon rings must be closed (first position == last position).
  List<List<double>> _closeGeoJsonLngLatRing(List<List<double>> ring) {
    if (ring.length < 3) return ring;
    final first = ring.first;
    final last = ring.last;
    if (first.length >= 2 &&
        last.length >= 2 &&
        first[0] == last[0] &&
        first[1] == last[1]) {
      return ring;
    }
    return [...ring, List<double>.from(first)];
  }

  Future<void> _drawZones(List<ZoneModel> zones) async {
    final controller = _controller;
    if (controller == null || !_mapStyleLoaded) {
      return;
    }
    _latestZones = zones;
    final cells = _latestCells;
    final layerSettings = ref.read(layerSettingsProvider);
    final selectedZone = ref.read(selectedZoneProvider);
    final selectedCell = ref.read(selectedCellProvider);
    final userLocation = ref.read(currentUserLocationProvider);
    final mapMode = _mapMode;
    final currentZoom = ref.read(mapViewportProvider).zoom;
    final showTravelerFill = layerSettings.showTravelerLayer;
    try {
      await controller.clearSymbols();
      await controller.clearCircles();
      await controller.clearLines();
    } catch (_) {
      return;
    }
    try {
      final features = <Map<String, dynamic>>[];
      // Thesis map: show catalog zone hexes whenever zones exist; skip cell grid.
      final drawZoneHexes = zones.isNotEmpty;
      final hasCellLayer = cells.isNotEmpty && !drawZoneHexes;
      if (hasCellLayer) {
        for (final cell in cells) {
          final layerKey = _cellLayerKey(cell);
          final isSelected = selectedCell?.h3Index == cell.h3Index;
          if (!_enabledLayerKeys.contains(layerKey) && !isSelected) continue;
          if (!showTravelerFill && !isSelected) continue;
          final color = _cellColor(cell);
          final closed = _closeGeoJsonLngLatRing(cell.ring);
          if (closed.length < 4) continue;
          final lifecycle = cell.reportCount >= 3
              ? 'defined'
              : cell.reportCount >= 1
              ? 'emerging'
              : 'sparse';
          features.add({
            'type': 'Feature',
            'properties': {
              'h3_index': cell.h3Index,
              'zone_type': layerKey,
              'fill': _hexFromColor(color),
              'line': _hexFromColor(color),
              'selected': isSelected,
              'lifecycle': lifecycle,
              'dashed': lifecycle == 'emerging',
              'fill_opacity': _zoneFillOpacity(
                mode: mapMode,
                selected: isSelected,
                hasSelection: selectedCell != null || selectedZone != null,
                confidenceScore: cell.confidenceScore,
                lifecycle: lifecycle,
              ),
              'line_width': _zoneLifecycleLineWidth(
                selected: isSelected,
                lifecycle: lifecycle,
              ),
              'line_opacity': _zoneLifecycleLineOpacity(lifecycle),
            },
            'geometry': {
              'type': 'Polygon',
              'coordinates': [closed],
            },
          });
        }
      } else {
        for (final zone in zones) {
          final layerKey = _zoneLayerKey(zone);
          final isSelected = selectedZone?.h3Index == zone.h3Index;
          if (!_enabledLayerKeys.contains(layerKey) && !isSelected) continue;
          final color = _streetZoneColor(zone);
          final lifecycle = _zoneLifecycleState(zone);
          if (!showTravelerFill && !isSelected) {
            continue;
          }
          for (final ring in zone.sourceH3Rings) {
            if (ring.length < 3) continue;
            final closed = _closeGeoJsonLngLatRing(ring);
            if (closed.length < 4) continue;
            features.add({
              'type': 'Feature',
              'properties': {
                'zone_id': zone.zoneId,
                'zone_type': layerKey,
                'fill': _hexFromColor(color),
                'line': _hexFromColor(color),
                'selected': isSelected,
                'lifecycle': lifecycle,
                'dashed': lifecycle == 'emerging',
                'fill_opacity': _zoneFillOpacity(
                  mode: mapMode,
                  selected: isSelected,
                  hasSelection: selectedZone != null,
                  confidenceScore: zone.confidenceScore,
                  lifecycle: lifecycle,
                ),
                'line_width': _zoneLifecycleLineWidth(
                  selected: isSelected,
                  lifecycle: lifecycle,
                ),
                'line_opacity': _zoneLifecycleLineOpacity(lifecycle),
              },
              'geometry': {
                'type': 'Polygon',
                'coordinates': [closed],
              },
            });
          }
        }
      }
      final geoJson = {'type': 'FeatureCollection', 'features': features};
      if (!_zoneLayersAdded) {
        await controller.addGeoJsonSource(_zonesSourceId, geoJson);
        final belowLayerId =
            _zoneBelowLayerId ?? await _resolveRoadLayerId(controller);
        _zoneBelowLayerId = belowLayerId;
        await controller.addFillLayer(
          _zonesSourceId,
          _zonesFillLayerId,
          FillLayerProperties(
            fillColor: ['get', 'fill'],
            fillOpacity: ['get', 'fill_opacity'],
          ),
          belowLayerId: belowLayerId,
        );
        await controller.addLineLayer(
          _zonesSourceId,
          _zonesLineLayerId,
          LineLayerProperties(
            lineColor: ['get', 'line'],
            lineWidth: ['get', 'line_width'],
            lineOpacity: ['get', 'line_opacity'],
          ),
          belowLayerId: belowLayerId,
        );
        _zoneLayersAdded = true;
      } else {
        await controller.setGeoJsonSource(_zonesSourceId, geoJson);
      }


      final labelZones = [...zones]
        ..sort((a, b) {
          final aScore = a.reportCount + a.confidenceScore;
          final bScore = b.reportCount + b.confidenceScore;
          return bScore.compareTo(aScore);
        });
      final labelLimit = currentZoom >= 13
          ? 14
          : currentZoom >= 11.5
          ? 10
          : 6;
      final labeledZoneIds = labelZones
          .take(labelLimit)
          .map((zone) => zone.h3Index)
          .toSet();
      for (final zone in zones) {
        if (zone.polygonParts.isEmpty) {
          continue;
        }
        final isSelected = selectedZone?.h3Index == zone.h3Index;
        final layerKey = _zoneLayerKey(zone);
        final layerVisible = _enabledLayerKeys.contains(layerKey);
        if (!layerVisible && !isSelected) {
          continue;
        }
        final center = _zoneCenter(zone);
        final shouldLabel =
            isSelected || labeledZoneIds.contains(zone.h3Index);
        if (shouldLabel) {
          await controller.addSymbol(
            SymbolOptions(
              geometry: center,
              textField: '${_zoneTitle(zone)}\n${_zoneIdentity(zone)}',
              textSize: isSelected
                  ? (currentZoom >= 12.5 ? 13 : 12)
                  : (currentZoom >= 12.5 ? 11.4 : 10.2),
              textColor: isSelected ? '#1F2937' : '#374151',
              textHaloColor: '#FFFFFF',
              textHaloWidth: 1.6,
              textOpacity: isSelected ? 1 : 0.90,
              textAnchor: 'center',
              textMaxWidth: 9,
              zIndex: isSelected ? 4 : 2,
            ),
          );
        }
      }
      final ownPins = ref.read(ownPendingTagPinsProvider).valueOrNull ?? [];
      for (final m in ownPins) {
        await controller.addSymbol(
          SymbolOptions(
            geometry: LatLng(m.latitude, m.longitude),
            textField: '\u{1F4CD}',
            textSize: 22,
            textAnchor: 'bottom',
            textOpacity: 0.94,
            textColor: '#0F172A',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 1.2,
            zIndex: 6,
          ),
        );
      }
      final visitPins = ref.read(ownVisitPinsProvider).valueOrNull ?? [];
      for (final pin in visitPins) {
        await controller.addSymbol(
          SymbolOptions(
            geometry: LatLng(pin.latitude, pin.longitude),
            textField: '\u{1F9F6}',
            textSize: pin.visitCount > 1 ? 20 : 18,
            textAnchor: 'bottom',
            textOpacity: 0.95,
            textColor: '#15803D',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 1.4,
            zIndex: 7,
          ),
        );
      }
      final flashPin = ref.read(exploreFlashPinProvider);
      if (flashPin != null) {
        await controller.addSymbol(
          SymbolOptions(
            geometry: flashPin,
            textField: '\u{1F4CD}',
            textSize: 26,
            textAnchor: 'bottom',
            textOpacity: 1,
            textColor: '#000000',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 1.6,
            zIndex: 9,
          ),
        );
      }
      if (userLocation != null) {
        await controller.addCircle(
          CircleOptions(
            geometry: userLocation,
            circleRadius: 7.2,
            circleColor: '#2F80ED',
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 3.0,
          ),
        );
      }
    } catch (_) {
      return;
    }
  }

  Future<String?> _resolveRoadLayerId(MapLibreMapController controller) async {
    try {
      final layers = await controller.getLayerIds();
      const preferredRoadLayers = <String>[
        'road-label',
        'road',
        'roads',
        'transportation',
      ];
      for (final preferred in preferredRoadLayers) {
        for (final raw in layers) {
          final id = raw.toString().toLowerCase();
          if (id == preferred || id.contains(preferred)) return raw.toString();
        }
      }
      for (final raw in layers) {
        final id = raw.toString().toLowerCase();
        if (id.contains('road') || id.contains('street')) return raw.toString();
      }
      for (final raw in layers) {
        final id = raw.toString().toLowerCase();
        if (id.contains('label')) return raw.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _applyBaseMapVisualTuning(
    MapLibreMapController controller,
  ) async {
    try {
      final layers = await controller.getLayerIds();
      for (final raw in layers) {
        final layerId = raw.toString();
        final id = layerId.toLowerCase();
        if (id.contains('poi') ||
            id.contains('medical') ||
            id.contains('hospital') ||
            id.contains('clinic') ||
            id.contains('pharmacy')) {
          try {
            await controller.setLayerProperties(
              layerId,
              SymbolLayerProperties(iconOpacity: 0, textOpacity: 0),
            );
          } catch (_) {}
        } else if (id.contains('transit') ||
            id.contains('rail') ||
            id.contains('station')) {
          try {
            await controller.setLayerProperties(
              layerId,
              LineLayerProperties(lineOpacity: 0.2),
            );
          } catch (_) {
            try {
              await controller.setLayerProperties(
                layerId,
                SymbolLayerProperties(iconOpacity: 0.3, textOpacity: 0.3),
              );
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  LatLng _zoneCenter(ZoneModel zone) {
    // Prefer the backend-computed centroid — it accounts for multi-part
    // zones and holes correctly. Fall back to the first outer ring's
    // average only if the centroid is missing.
    if (zone.centroidLat != 0.0 || zone.centroidLng != 0.0) {
      return LatLng(zone.centroidLat, zone.centroidLng);
    }
    if (zone.boundary.isEmpty) {
      return const LatLng(0, 0);
    }
    final lng =
        zone.boundary.map((point) => point[0]).reduce((a, b) => a + b) /
        zone.boundary.length;
    final lat =
        zone.boundary.map((point) => point[1]).reduce((a, b) => a + b) /
        zone.boundary.length;
    return LatLng(lat, lng);
  }

  ZoneModel? _findNearestZone(LatLng tap, List<ZoneModel> zones) {
    for (final zone in zones.reversed) {
      if (_tapInsideZone(tap, zone)) {
        return zone;
      }
    }

    ZoneModel? selected;
    var bestDistance = double.infinity;
    for (final zone in zones) {
      final center = _zoneCenter(zone);
      final distance = Geolocator.distanceBetween(
        tap.latitude,
        tap.longitude,
        center.latitude,
        center.longitude,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        selected = zone;
      }
    }
    return bestDistance <= 750 ? selected : null;
  }

  bool _tapInsideZone(LatLng tap, ZoneModel zone) {
    final point = [tap.longitude, tap.latitude];
    for (final ring in zone.sourceH3Rings) {
      if (_pointInRing(point, ring)) return true;
    }
    for (final part in zone.polygonParts) {
      if (part.isEmpty) continue;
      if (!_pointInRing(point, part.first)) continue;
      final inHole = part.skip(1).any((hole) => _pointInRing(point, hole));
      if (!inHole) return true;
    }
    if (zone.boundary.isNotEmpty && _pointInRing(point, zone.boundary)) {
      return true;
    }
    return false;
  }

  bool _pointInRing(List<double> point, List<List<double>> ring) {
    if (ring.length < 3) return false;
    final x = point[0];
    final y = point[1];
    var inside = false;
    var j = ring.length - 1;
    for (var i = 0; i < ring.length; i += 1) {
      final xi = ring[i][0];
      final yi = ring[i][1];
      final xj = ring[j][0];
      final yj = ring[j][1];
      final intersects =
          ((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / ((yj - yi) == 0 ? 1e-12 : yj - yi) + xi);
      if (intersects) inside = !inside;
      j = i;
    }
    return inside;
  }

  Future<void> _refreshViewportZones() async {
    final controller = _controller;
    if (controller == null || _isUpdatingViewport || !mounted) {
      return;
    }
    _isUpdatingViewport = true;
    try {
      final bounds = await controller.getVisibleRegion();
      final camera = controller.cameraPosition;
      if (!mounted) return;
      final center = camera?.target ?? ref.read(mapViewportProvider).center;
      final zoom = camera?.zoom ?? ref.read(mapViewportProvider).zoom;
      final next = MapViewport(
        center: center,
        zoom: zoom,
        minLat: bounds.southwest.latitude,
        minLng: bounds.southwest.longitude,
        maxLat: bounds.northeast.latitude,
        maxLng: bounds.northeast.longitude,
      );
      final dataViewport = ref.read(dataFetchViewportProvider);
      final shouldRefetch = mapViewportChangedSignificantly(dataViewport, next);
      ref.read(mapViewportProvider.notifier).state = next;
      if (!shouldRefetch) return;
      ref.read(dataFetchViewportProvider.notifier).state = next;
      ref.invalidate(visibleZonesProvider);
      ref.invalidate(visibleCellsProvider);
      final zones = await ref.read(visibleZonesProvider.future);
      final cells = await ref.read(visibleCellsProvider.future);
      if (mounted) {
        _latestCells = cells;
        unawaited(_drawZones(zones));
      }
    } finally {
      _isUpdatingViewport = false;
    }
  }

  void _selectZone(ZoneModel zone) {
    ref.read(zoneValidationLiveProvider.notifier).state = null;
    ref.read(selectedCellProvider.notifier).state = null;
    ref.read(mapSearchPlaceTitleProvider.notifier).state = null;
    ref.read(selectedZoneProvider.notifier).state =
        enrichZoneForAreaCard(zone);
    setState(() => _mapMode = ExploreMapMode.zoneSelected);
  }

  void _handleZoneTap(ZoneModel zone) {
    if (_lastTappedZoneId == zone.zoneId) {
      _sameZoneTapCount += 1;
    } else {
      _lastTappedZoneId = zone.zoneId;
      _sameZoneTapCount = 1;
    }
    _selectZone(zone);
    if (_sameZoneTapCount >= 3) {
      _sameZoneTapCount = 0;
      _showZoneInformation();
    }
  }

  void _showZoneInformation() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => const ZoneDetailSheet(),
    );
  }

  Future<void> _adjustZoom(double delta) async {
    final controller = _controller;
    if (controller == null) return;
    final currentZoom =
        controller.cameraPosition?.zoom ?? ref.read(mapViewportProvider).zoom;
    final nextZoom = (currentZoom + delta).clamp(7.8, 18.0).toDouble();
    await controller.animateCamera(CameraUpdate.zoomTo(nextZoom));
  }

  void _clearSelectedZone() {
    ref.read(zoneValidationLiveProvider.notifier).state = null;
    ref.read(selectedZoneProvider.notifier).state = null;
    ref.read(selectedCellProvider.notifier).state = null;
    setState(() {
      _mapMode = ExploreMapMode.discovery;
      _lastTappedZoneId = null;
      _sameZoneTapCount = 0;
    });
  }

  CellModel? _findCellAt(LatLng tap, List<CellModel> cells) {
    final point = [tap.longitude, tap.latitude];
    for (final cell in cells.reversed) {
      if (_pointInRing(point, cell.ring)) return cell;
    }
    try {
      final h3 = const H3Factory().load();
      final idx = h3.geoToCell(
        GeoCoord(lon: tap.longitude, lat: tap.latitude),
        8,
      );
      final idxStr = idx.toString();
      for (final cell in cells) {
        if (cell.h3Index == idxStr) return cell;
      }
    } catch (_) {}
    CellModel? nearest;
    var bestDistance = double.infinity;
    for (final cell in cells) {
      final distance = Geolocator.distanceBetween(
        tap.latitude,
        tap.longitude,
        cell.centroidLat,
        cell.centroidLng,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = cell;
      }
    }
    return bestDistance <= 120 ? nearest : null;
  }

  void _handleCellTap(CellModel cell) {
    ref.read(selectedCellProvider.notifier).state = cell;
    ref.read(selectedZoneProvider.notifier).state = null;
    setState(() => _mapMode = ExploreMapMode.discovery);
    unawaited(_drawZones(_latestZones));
    _showCellDetail(cell);
  }

  void _showCellDetail(CellModel cell) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => CellDetailSheet(cell: cell),
    );
  }

  Future<void> _markVisitedHere({String? label}) async {
    final token = ref.read(authTokenProvider);
    if (token == null || token == 'demo-token-local') {
      if (!mounted) return;
      pushAppNotification(
        ref,
        title: 'Sign in required',
        message: 'Log in to save private visit pins on your map.',
        kind: AppNotificationKind.warning,
      );
      return;
    }
    final controller = _controller;
    final camera = controller?.cameraPosition;
    final target = camera?.target ??
        ref.read(currentUserLocationProvider) ??
        const LatLng(10.3157, 123.8854);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(
        '/reports/my-visit-pins',
        data: {
          'latitude': target.latitude,
          'longitude': target.longitude,
          if (label != null && label.isNotEmpty) 'label': label,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      ref.invalidate(ownVisitPinsProvider);
      ref.invalidate(ownVisitHistoryProvider);
      final zones = ref.read(visibleZonesProvider).valueOrNull ?? [];
      if (mounted) {
        unawaited(_drawZones(zones));
        pushAppNotification(
          ref,
          title: 'Visit saved',
          message: label == null
              ? 'Saved to your private visit map.'
              : 'Saved visit: $label',
          kind: AppNotificationKind.success,
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data;
      final message = detail is Map && detail['detail'] != null
          ? detail['detail'].toString()
          : 'Could not save visit pin.';
      pushAppNotification(
        ref,
        title: 'Visit not saved',
        message: message,
        kind: AppNotificationKind.error,
      );
    }
  }

  Future<void> _openGoogleMapsNavigation(ZoneModel zone) async {
    final center = _zoneCenter(zone);
    final origin = ref.read(currentUserLocationProvider);
    final address = googleMapsDestinationAddress(
      displayName: zone.displayName,
      placeName: zone.placeName,
    );
    final opened = await GoogleMapsLauncher.openDirections(
      latitude: center.latitude,
      longitude: center.longitude,
      address: address,
      originLatitude: origin?.latitude,
      originLongitude: origin?.longitude,
    );
    if (!mounted) return;
    if (!opened) {
      pushAppNotification(
        ref,
        title: 'Directions',
        message: 'Could not open Google Maps. Install the app or try again.',
        kind: AppNotificationKind.warning,
      );
    }
  }

  void _startLiveLocationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            distanceFilter: 25,
          ),
        ).listen((position) async {
          if (!mounted || _usingManualLocation) return;
          final live = LatLng(position.latitude, position.longitude);
          ref.read(currentUserLocationProvider.notifier).state = live;
          _scheduleZoneLookupUpdate(live);
          if (!_followUser) {
            final zones = ref.read(visibleZonesProvider).valueOrNull ?? _latestZones;
            unawaited(_drawZones(zones));
            return;
          }
          final now = DateTime.now();
          final lastAt = _lastFollowCameraAt;
          final lastTarget = _lastFollowCameraTarget;
          final movedEnough = latLngChangedSignificantly(
            lastTarget,
            live,
            minMeters: 35,
          );
          final throttled = lastAt != null &&
              now.difference(lastAt) < const Duration(seconds: 4);
          if (!movedEnough || throttled) return;
          _lastFollowCameraAt = now;
          _lastFollowCameraTarget = live;
          final controller = _controller;
          if (controller != null) {
            await controller.moveCamera(
              CameraUpdate.newLatLngZoom(live, 13),
            );
          }
        });
  }

  @override
  void dispose() {
    _exploreFlashClearTimer?.cancel();
    _viewportIdleDebounce?.cancel();
    _zoneLookupDebounce?.cancel();
    _positionSubscription?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    final opening = !_showSearch;
    setState(() {
      _showSearch = opening;
      if (!opening) {
        _searchController.clear();
        _searchHits = const [];
        _searchFeedback = null;
        _searchBusy = false;
      }
    });
    if (opening) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    } else {
      ref.read(activeZoneFilterProvider.notifier).state = null;
    }
  }

  void _onSearchQueryChanged(String value, List<ZoneModel> zones) {
    _searchDebounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      if (mounted) {
        setState(() {
          _searchHits = const [];
          _searchFeedback = null;
          _searchBusy = false;
        });
      }
      return;
    }
    setState(() => _searchBusy = true);
    final gen = ++_searchRequestGen;
    _searchDebounce = Timer(const Duration(milliseconds: 380), () async {
      final hits = await _placeSearch.search(
        q,
        zones: zones,
        maxResults: 8,
      );
      if (!mounted || gen != _searchRequestGen) return;
      setState(() {
        _searchHits = hits;
        _searchBusy = false;
        _searchFeedback = hits.isEmpty
            ? 'No places found in Cebu for "$q".'
            : null;
      });
    });
  }

  Future<void> _submitSearch(List<ZoneModel> zones, {String? rawQuery}) async {
    final query = (rawQuery ?? _searchController.text).trim();
    if (query.isEmpty) {
      setState(() {
        _searchHits = const [];
        _searchFeedback = 'Search a mall, street, landmark, or area.';
      });
      return;
    }

    if (_searchHits.isNotEmpty) {
      await _focusSearchHit(_searchHits.first);
      return;
    }

    setState(() => _searchBusy = true);
    final hits = await _placeSearch.search(query, zones: zones);
    if (!mounted) return;
    setState(() => _searchBusy = false);
    if (hits.isEmpty) {
      setState(() {
        _searchFeedback = 'No places found in Cebu for "$query".';
        _searchHits = const [];
      });
      return;
    }
    await _focusSearchHit(hits.first);
  }

  Future<void> _focusSearchHit(ExploreSearchHit hit) async {
    ref.read(mapSearchFocusProvider.notifier).state = hit.location;
    ref.invalidate(currentZoneOverviewProvider);

    setState(() {
      _followUser = false;
      _searchFeedback = null;
      _searchHits = const [];
      _showSearch = false;
    });
    _searchFocusNode.unfocus();

    await _moveCameraToLocation(hit.location, zoom: 15.4);
    if (!mounted) return;
    await _refreshViewportZones();
    if (!mounted) return;
    await _selectZoneForMapPoint(hit.location, preferred: hit.zone);
  }

  Future<void> _selectZoneForMapPoint(
    LatLng location, {
    ZoneModel? preferred,
  }) async {
    ZoneModel? zone = preferred != null
        ? enrichZoneForAreaCard(preferred)
        : null;
    if (zone == null) {
      final zones = ref.read(visibleZonesProvider).valueOrNull ?? _latestZones;
      final nearest = _findNearestZone(location, zones);
      if (nearest != null) zone = enrichZoneForAreaCard(nearest);
    }
    if (zone == null) {
      await ZoneCatalog.ensureLoaded();
      final entry = ZoneCatalog.nearestEntry(
        location.latitude,
        location.longitude,
      );
      if (entry != null) {
        zone = zoneModelFromCatalogEntry(entry);
      }
    }
    if (zone != null) {
      _selectZone(zone);
      return;
    }
    ref.read(mapSearchPlaceTitleProvider.notifier).state = null;
    ref.read(selectedZoneProvider.notifier).state = null;
    ref.read(selectedCellProvider.notifier).state = null;
    setState(() => _mapMode = ExploreMapMode.discovery);
  }

  void _clearSearchInsight() {
    ref.read(mapSearchFocusProvider.notifier).state = null;
    ref.read(mapSearchPlaceTitleProvider.notifier).state = null;
    ref.invalidate(currentZoneOverviewProvider);
  }

  void _toggleLayerKey(String key) {
    setState(() {
      if (_enabledLayerKeys.contains(key)) {
        if (_enabledLayerKeys.length > 1) {
          _enabledLayerKeys.remove(key);
        }
      } else {
        _enabledLayerKeys.add(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<CurrentZoneOverviewModel?>>(
      currentZoneOverviewProvider,
      (prev, next) {
        if (next.isLoading) return;
        next.whenData((overview) {
          if (_didApplyCurrentZone || overview?.currentZone == null) return;
          _didApplyCurrentZone = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref.read(selectedZoneProvider.notifier).state =
                enrichZoneForAreaCard(overview!.currentZone!);
          });
        });
      },
    );
    ref.listen<LatLng?>(exploreFocusLocationProvider, (previous, next) {
      if (next == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _moveCameraToLocation(next, zoom: 15.4);
        ref.read(exploreFocusLocationProvider.notifier).state = null;
        final zones = ref.read(visibleZonesProvider).valueOrNull ?? _latestZones;
        await _drawZones(zones);
      });
    });
    ref.listen<bool>(explorePendingGpsCenterProvider, (prev, next) {
      if (next != true) return;
      ref.read(explorePendingGpsCenterProvider.notifier).state = false;
      _didBootstrapLocation = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_bootstrapCurrentLocation(force: true));
      });
    });
    ref.listen(ownPendingTagPinsProvider, (prev, next) {
      if (next.isLoading) return;
      next.whenData((_) {
        final zones = ref.read(visibleZonesProvider).valueOrNull ?? [];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_drawZones(zones));
        });
      });
    });
    ref.listen(ownVisitPinsProvider, (prev, next) {
      if (next.isLoading) return;
      next.whenData((_) {
        final zones = ref.read(visibleZonesProvider).valueOrNull ?? [];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_drawZones(zones));
        });
      });
    });

    // Do not use AsyncValue.whenData() here: it runs on every rebuild while
    // data is present and queues endless post-frame redraws (wrong build scope,
    // _dependents.isEmpty on dispose). Listen only fires when the provider
    // notifies with a new state.
    ref.listen<AsyncValue<List<ZoneModel>>>(visibleZonesProvider, (prev, next) {
      if (next.isLoading) return;
      next.whenData((zones) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_drawZones(zones));
        });
      });
    });
    ref.listen<AsyncValue<List<CellModel>>>(visibleCellsProvider, (prev, next) {
      if (next.isLoading) return;
      next.whenData((cells) {
        _latestCells = cells;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final zones = ref.read(visibleZonesProvider).valueOrNull ?? _latestZones;
          unawaited(_drawZones(zones));
        });
      });
    });
    ref.listen<AsyncValue<List<PlaceListItem>>>(visiblePlacesProvider, (
      prev,
      next,
    ) {
      if (next.isLoading) return;
      next.whenData((_) {
        final zones = ref.read(visibleZonesProvider).valueOrNull ?? [];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_drawZones(zones));
        });
      });
    });
    ref.listen<LayerSettings>(layerSettingsProvider, (prev, next) {
      if (prev == next) return;
      final zones = ref.read(visibleZonesProvider).valueOrNull ?? [];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_drawZones(zones));
      });
    });

    final zonesValue = ref.watch(visibleZonesProvider);
    ref.watch(visibleCellsProvider);
    ref.watch(selectedCellProvider);
    ref.watch(visiblePlacesProvider);
    ref.watch(layerSettingsProvider);
    ref.watch(ownPendingTagPinsProvider);
    ref.watch(ownVisitPinsProvider);
    final selectedZone = ref.watch(selectedZoneProvider);
    final searchPlaceTitle = ref.watch(mapSearchPlaceTitleProvider);
    ref.watch(currentZoneOverviewProvider);
    final zoneDataNotice = ref.watch(zoneDataNoticeProvider);
    final unreadNotifications = ref.watch(unreadNotificationCountProvider);
    final zones = zonesValue.valueOrNull ?? _latestZones;

    ref.listen<String?>(zoneDataNoticeProvider, (previous, next) {
      if (next == null || next.isEmpty || next == previous) return;
      pushAppNotification(
        ref,
        title: 'Map data',
        message: next,
        kind: AppNotificationKind.info,
      );
    });

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          return Stack(
            children: [
              if (!_showMap)
                const ColoredBox(color: Color(0xFFF1F2F4))
              else
                ExcludeSemantics(
                  excluding: true,
                  child: MapLibreMap(
                    styleString:
                        'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json',
                    initialCameraPosition: const CameraPosition(
                      target: _cebuCityCenter,
                      zoom: 14.7,
                    ),
                    minMaxZoomPreference: const MinMaxZoomPreference(7.8, 18),
                    rotateGesturesEnabled: false,
                    onMapCreated: (controller) {
                      _controller = controller;
                    },
                    onStyleLoadedCallback: () async {
                      _mapStyleLoaded = true;
                      _zoneLayersAdded = false;
                      final controller = _controller;
                      if (controller == null) return;
                      await _applyBaseMapVisualTuning(controller);
                      _zoneBelowLayerId = await _resolveRoadLayerId(controller);
                      _consumeExploreFocus();
                      final zones = ref.read(visibleZonesProvider).valueOrNull;
                      if (zones != null) {
                        unawaited(_drawZones(zones));
                      }
                    },
                    onCameraIdle: _scheduleViewportRefresh,
                    onMapClick: (point, latLng) {
                      final tap = LatLng(latLng.latitude, latLng.longitude);
                      final zones = _latestZones;
                      if (zones.isNotEmpty) {
                        final selected = _findNearestZone(tap, zones);
                        if (selected != null) {
                          _handleZoneTap(selected);
                          return;
                        }
                      }
                      final cells = _latestCells;
                      if (cells.isNotEmpty) {
                        final cell = _findCellAt(tap, cells);
                        if (cell != null) _handleCellTap(cell);
                      }
                    },
                  ),
                ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.38),
                        Colors.white.withValues(alpha: 0.07),
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.04),
                      ],
                      stops: const [0, 0.10, 0.45, 1],
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              SafeArea(
                bottom: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MapTopBar(
                      zoneCount: zonesValue.maybeWhen(
                        data: (zones) => zones.length,
                        orElse: () => null,
                      ),
                      searchExpanded: _showSearch,
                      searchController: _searchController,
                      searchFocusNode: _searchFocusNode,
                      onSearchTap: _toggleSearch,
                      onSearchClose: _toggleSearch,
                      onSearchChanged: (value) =>
                          _onSearchQueryChanged(value, zones),
                      onSearchSubmitted: () => _submitSearch(zones),
                      onNotificationTap: () =>
                          showAppNotificationSheet(context, ref),
                      showNotificationDot: unreadNotifications > 0,
                    ),
                    if (_showSearch &&
                        (_searchController.text.trim().isNotEmpty ||
                            _searchFeedback != null ||
                            _searchHits.isNotEmpty ||
                            _searchBusy)) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _SearchResultsCard(
                          hits: _searchHits,
                          feedback: _searchFeedback,
                          loading: _searchBusy,
                          onSelect: _focusSearchHit,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _LocationStatusBanner(
                      state: _locationState,
                      onRetry: () => _bootstrapCurrentLocation(force: true),
                      onOpenProfile: () => context.go('/profile'),
                    ),
                    if (zoneDataNotice != null) ...[
                      const SizedBox(height: 8),
                      _CacheNoticeBanner(message: zoneDataNotice),
                    ],
                    const SizedBox(height: 6),
                    ExploreMapFilterBar(
                      enabledLayerKeys: _enabledLayerKeys,
                      onToggleLayer: _toggleLayerKey,
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 8,
                bottom: selectedZone != null ? (compact ? 242 : 264) : 152,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _MapFab(
                      heroTag: 'zoom-in-btn',
                      icon: Icons.zoom_in_rounded,
                      onPressed: () => _adjustZoom(1),
                    ),
                    const SizedBox(height: 8),
                    _MapFab(
                      heroTag: 'zoom-out-btn',
                      icon: Icons.zoom_out_rounded,
                      onPressed: () => _adjustZoom(-1),
                    ),
                    const SizedBox(height: 8),
                    _MapFab(
                      heroTag: 'location-btn',
                      icon: _followUser
                          ? Icons.my_location_rounded
                          : Icons.location_searching_rounded,
                      onPressed: () {
                        setState(() => _followUser = true);
                        final here = ref.read(currentUserLocationProvider);
                        if (_usingManualLocation &&
                            here != null &&
                            _isWithinCebuRegion(here)) {
                          unawaited(_moveCameraToLocation(here, zoom: 14.5));
                        } else {
                          unawaited(_bootstrapCurrentLocation(force: true));
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    _MapFab(
                      heroTag: 'visit-pin-btn',
                      icon: Icons.hiking_rounded,
                      onPressed: () {
                        final zone = ref.read(selectedZoneProvider);
                        unawaited(
                          _markVisitedHere(
                            label: zone == null ? null : _zoneTitle(zone),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (searchPlaceTitle != null &&
                  searchPlaceTitle.isNotEmpty &&
                  selectedZone == null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 88,
                  child: ExploreAreaInsightCard(
                    placeTitle: searchPlaceTitle,
                    onClose: _clearSearchInsight,
                  ),
                ),
              if (selectedZone != null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 18,
                  child: zonesValue.when(
                    data: (zones) {
                      if (zones.isEmpty) {
                        final hasFilters =
                            ref.read(activeTravelerMixFilterProvider) != null ||
                            ref.read(activePlaceTypeFilterProvider) != null ||
                            ref.read(activeZoneFilterProvider) != null;
                        return _LoadingZoneCard(
                          message: hasFilters
                              ? 'No zones match these filters here. Clear filters or pan to IT Park, Colon, or Ayala.'
                              : 'No zones in this view. Pan to a tagged area or run backend seed (see README).',
                        );
                      }
                      final previewZone = selectedZone;
                      return _SelectedZoneCard(
                        zone: previewZone,
                        onClose: _clearSelectedZone,
                        onDirections: () =>
                            unawaited(_openGoogleMapsNavigation(previewZone)),
                        onDetails: () {
                          _selectZone(previewZone);
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            barrierColor: Colors.black.withValues(alpha: 0.35),
                            builder: (_) => const ZoneDetailSheet(),
                          );
                        },
                      );
                    },
                    loading: () =>
                        const _LoadingZoneCard(message: 'Loading zones...'),
                    error: (error, _) => _LoadingZoneCard(
                      message: 'Unable to load zones: ${_shortError(error)}',
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

String _shortError(Object error) {
  final msg = error.toString();
  if (msg.length <= 80) return msg;
  return '${msg.substring(0, 77)}...';
}

String _zoneTitle(ZoneModel zone) => zoneDisplayTitle(zone);

double _zoneFillOpacity({
  required ExploreMapMode mode,
  required bool selected,
  required bool hasSelection,
  required double confidenceScore,
  required String lifecycle,
}) {
  if (lifecycle == 'decaying') {
    return selected ? 0.18 : 0.12;
  }
  if (selected) {
    return 0.30;
  }
  if (hasSelection) {
    return 0.18;
  }
  if (lifecycle == 'emerging') {
    return 0.16;
  }
  if (confidenceScore >= 70) {
    return 0.30;
  }
  if (confidenceScore >= 45) {
    return 0.24;
  }
  return 0.18;
}

String _zoneLifecycleState(ZoneModel zone) {
  final live = zone.liveStatus.toLowerCase();
  if (zone.zoneType == 'emerging' ||
      zone.confidenceScore < 45 ||
      zone.reportCount < 3) {
    return 'emerging';
  }
  if ((live.contains('quiet') || live.contains('decay')) &&
      zone.confidenceScore < 65) {
    return 'decaying';
  }
  return 'defined';
}

double _zoneLifecycleLineWidth({
  required bool selected,
  required String lifecycle,
}) {
  if (selected) return 2.0;
  if (lifecycle == 'defined') return 1.5;
  if (lifecycle == 'emerging') return 1.25;
  return 1.0;
}

double _zoneLifecycleLineOpacity(String lifecycle) {
  if (lifecycle == 'defined') return 0.86;
  if (lifecycle == 'emerging') return 0.62;
  return 0.42;
}

String _cellLayerKey(CellModel cell) {
  return switch (cell.travelerMix) {
    'local' => 'local',
    'international' => 'international',
    _ => 'mixed',
  };
}

Color _cellColor(CellModel cell) => TravelerGradient.colorForCell(cell);

String _zoneLayerKey(ZoneModel zone) {
  return switch (zone.travelerMix) {
    'local' => 'local',
    'international' => 'international',
    _ => 'mixed',
  };
}

Color _streetZoneColor(ZoneModel zone) => TravelerGradient.colorForZone(zone);

String _zoneSubtitle(ZoneModel zone) {
  if (zone.reportCount >= 45) return 'Busy now';
  if (zone.confidenceScore >= 70) return 'Popular';
  return zoneMapSubtitle(zone);
}

String _zoneIdentity(ZoneModel zone) => zoneMapSubtitle(zone);

String _zoneSummary(ZoneModel zone) {
  final identity = _zoneIdentity(zone);
  if (identity == 'Food Hotspot') {
    return 'Affordable food, busy streets, easy stops';
  }
  if (identity == 'Transport Zone') {
    return 'Good access, high movement, watch peak hours';
  }
  if (identity == 'Student Area') {
    return 'Students, cafes, budget-friendly places';
  }
  if (identity == 'Commercial Zone') {
    return 'Cafes, offices, shopping, night activity';
  }
  if (identity == 'Local Area') {
    return 'Mostly locals, relaxed pace, useful nearby stops';
  }
  if (identity == 'Tourist Area') {
    return 'High activity, safe, many places to explore';
  }
  if (identity == 'Safety Concern') {
    return 'Recent reports suggest extra awareness here';
  }
  return 'Balanced mix of locals and visitors';
}

String _hexFromColor(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

_ZonePalette _zonePalette(ZoneModel zone) {
  final ratio = TravelerGradient.localRatioForZone(zone);
  return _ZonePalette(
    fill: TravelerGradient.fillForRatio(ratio),
    border: TravelerGradient.colorForRatio(ratio),
    accent: TravelerGradient.colorForRatio(ratio),
  );
}

class _ZonePalette {
  const _ZonePalette({
    required this.fill,
    required this.border,
    required this.accent,
  });

  final Color fill;
  final Color border;
  final Color accent;
}

class _LocationStatusBanner extends StatelessWidget {
  const _LocationStatusBanner({
    required this.state,
    required this.onRetry,
    required this.onOpenProfile,
  });

  final _LocationBootstrapState state;
  final VoidCallback onRetry;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    if (state == _LocationBootstrapState.ready) {
      return const SizedBox.shrink();
    }
    final (icon, message, action, onAction) = switch (state) {
      _LocationBootstrapState.locating => (
        Icons.gps_fixed_rounded,
        'Detecting your location...',
        null,
        null,
      ),
      _LocationBootstrapState.permissionDenied => (
        Icons.location_disabled_rounded,
        'Location is off. Set a map location in Profile if you prefer not to share GPS.',
        'Profile',
        onOpenProfile,
      ),
      _ => (
        Icons.location_off_rounded,
        'Location services are off. Turn on GPS or set a map location in Profile.',
        'Retry',
        onRetry,
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.mutedText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (action != null && onAction != null)
              TextButton(
                onPressed: onAction,
                child: Text(
                  action,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CacheNoticeBanner extends StatelessWidget {
  const _CacheNoticeBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8EE).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFF0A127)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.offline_bolt_rounded,
              size: 16,
              color: Color(0xFFB7791F),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapTopBar extends StatelessWidget {
  const _MapTopBar({
    required this.zoneCount,
    required this.searchExpanded,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchTap,
    required this.onSearchClose,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onNotificationTap,
    this.showNotificationDot = false,
  });

  final int? zoneCount;
  final bool searchExpanded;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final VoidCallback onSearchTap;
  final VoidCallback onSearchClose;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchSubmitted;
  final VoidCallback onNotificationTap;
  final bool showNotificationDot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'lib/app/theme/strollwiselogo.jpg',
              width: 44,
              height: 44,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: searchExpanded
                ? Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x140F172A),
                          blurRadius: 14,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: searchController,
                      focusNode: searchFocusNode,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      onChanged: onSearchChanged,
                      onSubmitted: (_) => onSearchSubmitted(),
                      decoration: InputDecoration(
                        hintText: 'Mall, street, landmark, building…',
                        hintStyle: const TextStyle(
                          color: AppColors.mutedText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: AppColors.mutedText,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppColors.mutedText,
                          ),
                          onPressed: onSearchClose,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  )
                : GestureDetector(
                    onTap: onSearchTap,
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x140F172A),
                            blurRadius: 14,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: AppColors.mutedText,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              zoneCount == null
                                  ? 'Search Cebu places…'
                                  : 'Search places & zones',
                              style: const TextStyle(
                                color: AppColors.mutedText,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          _TopIconButton(
            icon: Icons.notifications_none_rounded,
            onTap: onNotificationTap,
            showDot: showNotificationDot,
          ),
        ],
      ),
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.icon,
    required this.onTap,
    this.showDot = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(icon, color: const Color(0xFF111827), size: 22),
              ),
              if (showDot)
                Positioned(
                  top: 11,
                  right: 11,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF43F5E),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResultsCard extends StatelessWidget {
  const _SearchResultsCard({
    required this.hits,
    required this.feedback,
    required this.loading,
    required this.onSelect,
  });

  final List<ExploreSearchHit> hits;
  final String? feedback;
  final bool loading;
  final Future<void> Function(ExploreSearchHit hit) onSelect;

  @override
  Widget build(BuildContext context) {
    if (hits.isEmpty && feedback == null && !loading) {
      return const SizedBox.shrink();
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Searching Cebu…',
                    style: TextStyle(
                      color: AppColors.mutedText,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          if (feedback != null && hits.isEmpty && !loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  feedback!,
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          if (hits.isNotEmpty)
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 6),
                itemCount: hits.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final hit = hits[index];
                  final color = hit.localRatio != null
                      ? TravelerGradient.colorForRatio(hit.localRatio!)
                      : AppColors.mutedText;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      _hitIcon(hit.kind),
                      color: color,
                      size: 20,
                    ),
                    title: Text(
                      hit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      hit.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onSelect(hit),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  static IconData _hitIcon(ExploreSearchHitKind kind) {
    return switch (kind) {
      ExploreSearchHitKind.zone => Icons.hexagon_outlined,
      ExploreSearchHitKind.landmark => Icons.place_outlined,
      ExploreSearchHitKind.address => Icons.signpost_outlined,
    };
  }
}

class _SelectedZoneCard extends StatelessWidget {
  const _SelectedZoneCard({
    required this.zone,
    required this.onDetails,
    required this.onDirections,
    required this.onClose,
  });

  final ZoneModel zone;
  final VoidCallback onDetails;
  final VoidCallback onDirections;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = _zonePalette(zone);
    return GestureDetector(
      onTap: onDetails,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: palette.border.withValues(alpha: 0.45),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x260F172A),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
            BoxShadow(
              color: palette.accent.withValues(alpha: 0.16),
              blurRadius: 18,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _ZoneIconBadge(palette: palette, zone: zone),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _zoneTitle(zone),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.primaryText,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: palette.fill,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _zoneIdentity(zone),
                              style: TextStyle(
                                color: palette.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _zoneSummary(zone),
                        style: const TextStyle(
                          color: AppColors.mutedText,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Live update: ${_zoneSubtitle(zone)}',
                        style: TextStyle(
                          color: palette.accent,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                // Dismiss the selected-zone card and return to the
                // clean map + Live City Pulse state.
                _CloseButton(onPressed: onClose),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _MetricCell(
                  icon: Icons.bar_chart_rounded,
                  label: 'Activity',
                  value: _activityLabel(zone),
                  accent: AppColors.accent,
                ),
                _MetricCell(
                  icon: Icons.groups_rounded,
                  label: 'Local presence',
                  value: _localPresence(zone),
                ),
                _MetricCell(
                  icon: Icons.verified_user_outlined,
                  label: 'Best time',
                  value: _bestTimeLabel(zone),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _ValidationMiniDashboard(zone: zone, palette: palette),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onDetails,
                    child: const Text('View Details'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDirections,
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('Google Maps'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // GestureDetector with opaque behavior prevents the surrounding
    // card's onTap (which opens the detail sheet) from firing.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.border.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.close_rounded,
          size: 18,
          color: AppColors.primaryText,
        ),
      ),
    );
  }
}

String _activityLabel(ZoneModel zone) {
  if (zone.liveStatus.contains('busy') || zone.reportCount >= 35) {
    return 'Busy';
  }
  if (zone.reportCount >= 15 || zone.crowdLevel >= 0.55) {
    return 'Moderate';
  }
  return 'Light';
}

String _bestTimeLabel(ZoneModel zone) {
  final peak = zone.peakTimeLabel?.trim() ?? '';
  if (peak.isNotEmpty) return peak;
  return '4PM–9PM';
}

String _localPresence(ZoneModel zone) {
  final pct = zone.localPresencePercent > 0
      ? zone.localPresencePercent
      : TravelerGradient.localRatioForZone(zone) * 100;
  return '${pct.round()}%';
}

class _ValidationMiniDashboard extends ConsumerWidget {
  const _ValidationMiniDashboard({required this.zone, required this.palette});

  final ZoneModel zone;
  final _ZonePalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ZoneValidationMetrics.forZone(ref, zone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.fill.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, size: 15, color: palette.accent),
              const SizedBox(width: 6),
              const Text(
                'Validation dashboard',
                style: TextStyle(
                  color: AppColors.primaryText,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _ValidationPill(
                label: 'Signals',
                value: '${metrics.totalSignals}',
              ),
              _ValidationPill(
                label: 'Matching',
                value: '${metrics.matchingSignals}',
              ),
              _ValidationPill(
                label: 'Confidence',
                value: '${metrics.confidence.toStringAsFixed(0)}%',
              ),
              _ValidationPill(
                label: 'Category',
                value: metrics.topCategory,
              ),
              _ValidationPill(label: 'Updated', value: metrics.lastUpdated),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValidationPill extends StatelessWidget {
  const _ValidationPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: AppColors.secondaryText,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.icon,
    required this.label,
    required this.value,
    this.accent = AppColors.primaryText,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: AppColors.mutedText),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.mutedText,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoneIconBadge extends StatelessWidget {
  const _ZoneIconBadge({required this.palette, required this.zone});

  final _ZonePalette palette;
  final ZoneModel zone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: palette.fill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border.withValues(alpha: 0.55)),
      ),
      child: Icon(_zoneIcon(zone), color: palette.accent, size: 25),
    );
  }
}

IconData _zoneIcon(ZoneModel zone) {
  final identity = _zoneIdentity(zone);
  if (identity == 'Food Hotspot') return Icons.restaurant_rounded;
  if (identity == 'Transport Zone') return Icons.directions_bus_rounded;
  if (identity == 'Student Area') return Icons.school_rounded;
  if (identity == 'Commercial Zone') return Icons.shopping_bag_rounded;
  if (identity == 'Safety Concern') return Icons.warning_amber_rounded;
  if (identity.contains('Hotel')) return Icons.hotel_rounded;
  if (identity == 'Tourist Area') return Icons.photo_camera_rounded;
  if (identity == 'Local Area') return Icons.groups_rounded;
  return Icons.explore_rounded;
}

class _LoadingZoneCard extends StatelessWidget {
  const _LoadingZoneCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.primaryText,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MapFab extends StatelessWidget {
  const _MapFab({
    required this.heroTag,
    required this.icon,
    required this.onPressed,
  });

  final String heroTag;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: FloatingActionButton(
        heroTag: heroTag,
        elevation: 4,
        backgroundColor: Colors.white.withValues(alpha: 0.96),
        onPressed: onPressed,
        child: Icon(icon, color: const Color(0xFF2563EB), size: 22),
      ),
    );
  }
}

