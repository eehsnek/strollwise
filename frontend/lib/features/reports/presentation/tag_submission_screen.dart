import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../app/theme/colors.dart';
import '../../../shared/location/cebu_place_geocode.dart';
import '../../../shared/models/zone.dart';
import '../../../shared/network/api_client.dart';
import '../../../shared/notifications/app_notifications.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/zone_place_ui.dart';

Future<LatLng?> _tagPickerTryCurrentGps() async {
  try {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 8),
      ),
    );
    final here = LatLng(position.latitude, position.longitude);
    return cebuPlaceWithinServiceArea(here) ? here : null;
  } catch (_) {
    return null;
  }
}

class TagSubmissionScreen extends ConsumerStatefulWidget {
  const TagSubmissionScreen({super.key});

  @override
  ConsumerState<TagSubmissionScreen> createState() =>
      _TagSubmissionScreenState();
}

class _TagSubmissionScreenState extends ConsumerState<TagSubmissionScreen> {
  static const _tagTypes = [
    _TagType(
      backendCategory: 'food',
      label: 'Food',
      icon: Icons.restaurant_outlined,
      accent: Color(0xFF34765B),
      fill: Color(0xFFF2FBF6),
      details: ['Street Food', 'Cafe', 'Restaurant', 'Late Night'],
    ),
    _TagType(
      backendCategory: 'other',
      label: 'Tourist',
      icon: Icons.photo_camera_outlined,
      accent: Color(0xFF7BA0E6),
      fill: Color(0xFFF3F7FF),
      details: ['Photo Spot', 'Landmark', 'Visitor Friendly', 'Scenic'],
    ),
    _TagType(
      backendCategory: 'other',
      label: 'Local Pick',
      icon: Icons.star_border_rounded,
      accent: Color(0xFF78BE9C),
      fill: Color(0xFFF1FBF5),
      details: ['Neighborhood Favorite', 'Budget Meal', 'Worth Detour', 'Calm'],
    ),
    _TagType(
      backendCategory: 'other',
      label: 'Residential',
      icon: Icons.home_outlined,
      accent: Color(0xFF8F73EC),
      fill: Color(0xFFF7F3FF),
      details: ['Quiet', 'Family Area', 'Mostly Locals', 'Side Streets'],
    ),
    _TagType(
      backendCategory: 'other',
      label: 'Commercial',
      icon: Icons.business_outlined,
      accent: Color(0xFFF0A127),
      fill: Color(0xFFFFF8EE),
      details: ['Mall Area', 'Offices', 'Busy', 'Open Late'],
    ),
    _TagType(
      backendCategory: 'school',
      label: 'School',
      icon: Icons.school_outlined,
      accent: Color(0xFF8060E8),
      fill: Color(0xFFF7F3FF),
      details: [
        'Study Friendly',
        'Student Budget',
        'After Class',
        'Campus Edge',
        'USPF campus',
      ],
    ),
    _TagType(
      backendCategory: 'other',
      label: 'Hotel',
      icon: Icons.hotel_outlined,
      accent: Color(0xFF69A6E8),
      fill: Color(0xFFF1F8FF),
      details: ['Near Lobby', 'Visitor Pickup', 'Quiet Stay', 'Walkable'],
    ),
    _TagType(
      backendCategory: 'transport',
      label: 'Transport',
      icon: Icons.directions_bus_outlined,
      accent: Color(0xFF65B9BE),
      fill: Color(0xFFF1FBFB),
      details: ['Near Transit', 'Pickup Point', 'Traffic', 'Easy Crossing'],
    ),
    _TagType(
      backendCategory: 'other',
      label: 'Nature',
      icon: Icons.eco_outlined,
      accent: Color(0xFF5FA864),
      fill: Color(0xFFF3FBF3),
      details: ['Shade', 'Green Space', 'Fresh Air', 'Quiet Walk'],
    ),
    _TagType(
      backendCategory: 'safety',
      label: 'Safety',
      icon: Icons.shield_outlined,
      accent: Color(0xFFE45E53),
      fill: Color(0xFFFFF3F2),
      details: ['Well Lit', 'Avoid Late', 'Police Nearby', 'Crowded Exit'],
    ),
    _TagType(
      backendCategory: 'activity',
      label: 'Activity',
      icon: Icons.directions_run_rounded,
      accent: Color(0xFFE3A128),
      fill: Color(0xFFFFF8EE),
      details: ['Nightlife', 'Great Place', 'Good for Groups', 'Live Music'],
    ),
  ];

  final noteController = TextEditingController();
  final placeSearchController = TextEditingController();

  String _selectedTypeLabel = _tagTypes.first.label;
  String _selectedVisibility = 'Anonymous';
  String _selectedDetail = _tagTypes.first.details.first;
  LatLng? _pickedLocation;
  bool _searchBusy = false;
  bool _gpsBusy = false;
  List<CebuPlaceSearchHit> _placeHits = const [];
  String? _searchFeedback;
  Timer? _searchDebounce;
  int _searchRequestGen = 0;

  @override
  void initState() {
    super.initState();
    placeSearchController.addListener(_onPlaceQueryChanged);
  }

  _TagType get _selectedType =>
      _tagTypes.firstWhere((type) => type.label == _selectedTypeLabel);

  bool get _canSubmit =>
      _pickedLocation != null &&
      (_selectedDetail.isNotEmpty || noteController.text.trim().isNotEmpty);

  void _applyLocation(LatLng location) {
    ref.read(tagSubmissionPinLocationProvider.notifier).state = location;
    setState(() => _pickedLocation = location);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    noteController.dispose();
    placeSearchController.dispose();
    super.dispose();
  }

  void _onPlaceQueryChanged() {
    _searchDebounce?.cancel();
    final query = placeSearchController.text.trim();
    if (query.length < 2) {
      setState(() {
        _placeHits = const [];
        _searchFeedback = null;
        _searchBusy = false;
      });
      return;
    }
    setState(() => _searchBusy = true);
    final gen = ++_searchRequestGen;
    _searchDebounce = Timer(const Duration(milliseconds: 380), () async {
      final hits = await searchCebuPlaces(ref.read(dioProvider), query);
      if (!mounted || gen != _searchRequestGen) return;
      setState(() {
        _placeHits = hits;
        _searchBusy = false;
        _searchFeedback = hits.isEmpty
            ? 'No places found in Cebu for "$query".'
            : null;
      });
    });
  }

  void _selectPlaceHit(CebuPlaceSearchHit hit) {
    FocusScope.of(context).unfocus();
    placeSearchController.text = hit.title;
    setState(() {
      _placeHits = const [];
      _searchFeedback = null;
    });
    _applyLocation(hit.location);
  }

  Future<void> _submit() async {
    if (_pickedLocation == null) {
      pushAppNotification(
        ref,
        title: 'Location required',
        message: 'Set a location on the map before submitting.',
        kind: AppNotificationKind.warning,
      );
      return;
    }
    if (!_canSubmit) return;

    final submitLocation = _pickedLocation!;
    final tags = <String>[
      if (_selectedDetail.isNotEmpty) _selectedDetail.toLowerCase(),
      _selectedType.label.toLowerCase(),
      _selectedVisibility.toLowerCase(),
      'exact_road_spot',
    ];

    final payload = TagSubmissionPayload(
      latitude: submitLocation.latitude,
      longitude: submitLocation.longitude,
      category: _selectedType.backendCategory,
      tags: tags,
      note: noteController.text.trim().isEmpty
          ? null
          : noteController.text.trim(),
    );

    try {
      final feedback = await ref
          .read(tagSubmissionProvider.notifier)
          .submit(payload);
      if (!mounted) return;

      final focus = LatLng(payload.latitude, payload.longitude);
      final summary = _submissionExploreSummary(feedback);
      pushAppNotification(
        ref,
        title: 'Tag submitted',
        message: summary,
        kind: AppNotificationKind.success,
      );
      ref.read(explorePostSubmitCueProvider.notifier).state =
          ExplorePostSubmitCue(focus: focus, summary: summary);
      ref.read(tagSubmissionPinLocationProvider.notifier).state = null;

      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final token = ref.read(authTokenProvider);
        if (token != null && token != 'demo-token-local') {
          ref.invalidate(userMeProvider);
          unawaited(ref.read(userContributionsProvider.notifier).refresh());
        }
        if (!mounted) return;
        context.go('/explore');
      });
    } catch (error) {
      if (!mounted) return;
      pushAppNotification(
        ref,
        title: 'Tag not submitted',
        message: _submissionErrorMessage(error),
        kind: AppNotificationKind.error,
      );
    }
  }

  String _submissionErrorMessage(Object error) {
    if (error is DioException) {
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        return 'Please log in again before submitting a tag.';
      }
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout) {
        return 'Backend is unreachable. Use Demo Login or start the backend.';
      }
      final detail = error.response?.data;
      if (detail is Map && detail['detail'] != null) {
        return detail['detail'].toString();
      }
      return 'Submission failed (${error.response?.statusCode ?? 'network'}).';
    }
    return 'Submission failed. Please try again.';
  }

  Future<void> _commitPlaceSearch() async {
    final query = placeSearchController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a street, mall, or landmark.')),
      );
      return;
    }
    if (_placeHits.isNotEmpty) {
      _selectPlaceHit(_placeHits.first);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _searchBusy = true);
    final hits = await searchCebuPlaces(ref.read(dioProvider), query);
    if (!mounted) return;
    setState(() {
      _searchBusy = false;
      _placeHits = hits;
      _searchFeedback = hits.isEmpty
          ? 'No places found in Cebu for "$query".'
          : null;
    });
    if (hits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No match in greater Cebu. Try another spelling or pick a suggestion.',
          ),
        ),
      );
      return;
    }
    _selectPlaceHit(hits.first);
  }

  Future<void> _useGps() async {
    setState(() => _gpsBusy = true);
    final live = await _tagPickerTryCurrentGps();
    if (!mounted) return;
    setState(() => _gpsBusy = false);
    if (live == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not get GPS inside Cebu. Enable location, allow the app, '
            'or search for a place instead.',
          ),
        ),
      );
      return;
    }
    _applyLocation(live);
  }

  void _useExploreMapCenter() {
    final center = ref.read(mapViewportProvider).center;
    if (!cebuPlaceWithinServiceArea(center)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Explore map center is outside the Cebu tagging area. '
            'Move the map in Explore or search here.',
          ),
        ),
      );
      return;
    }
    _applyLocation(center);
  }

  String _submissionExploreSummary(TagSubmissionFeedback feedback) {
    final thresholdLine = feedback.thresholdMet
        ? '${feedback.matchingCount}/${feedback.threshold} people — cell can form.'
        : '${feedback.matchingCount}/${feedback.threshold} people in this cell.';
    final pending = feedback.thresholdMet
        ? 'This H3 cell will publish after aggregation runs.'
        : '${feedback.remainingToThreshold} more '
              '${feedback.remainingToThreshold == 1 ? 'person' : 'people'} needed before this cell can form.';
    return 'Tag saved. H3 ${feedback.h3Index}\n'
        '$thresholdLine\n'
        '$pending\n'
        '${feedback.publicZoneUpdate}';
  }

  @override
  Widget build(BuildContext context) {
    final submissionState = ref.watch(tagSubmissionProvider);
    final selectedZone = ref.watch(selectedZoneProvider);
    final zoneFlow = ref.watch(tagFlowZoneOverviewNotifierProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final hasLocation = _pickedLocation != null;
    final ZoneModel? zone = hasLocation
        ? zoneFlow.overview?.currentZone
        : (zoneFlow.overview?.currentZone ?? selectedZone);
    final zoneRefreshing = hasLocation && zoneFlow.refreshing;
    final selectedType = _selectedType;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          ref.read(tagSubmissionPinLocationProvider.notifier).state = null;
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFB),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: const Color(0xFFF8FAFB),
          foregroundColor: AppColors.primaryText,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              ref.read(tagSubmissionPinLocationProvider.notifier).state = null;
              context.go('/explore');
            },
          ),
          title: const Text(
            'Add Tag',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
          ),
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
          children: [
            Text(
              'Set where this applies, pick a category, then submit. '
              'No map is required on this screen—use GPS, Explore’s map center, or search.',
              style: TextStyle(
                color: AppColors.mutedText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _ZoneCard(
              title: hasLocation ? 'Zone at this point' : 'Current zone',
              zone: zone,
              refreshing: zoneRefreshing,
              pendingLocation: hasLocation && zone == null,
            ),
            const SizedBox(height: 16),
            _LocationCard(
              placeSearchController: placeSearchController,
              pickedLocation: _pickedLocation,
              searchBusy: _searchBusy,
              gpsBusy: _gpsBusy,
              placeHits: _placeHits,
              searchFeedback: _searchFeedback,
              onPlaceSubmitted: _commitPlaceSearch,
              onSelectPlaceHit: _selectPlaceHit,
              onGps: _useGps,
              onExploreCenter: _useExploreMapCenter,
              onClearSearch: () {
                setState(() {
                  _placeHits = const [];
                  _searchFeedback = null;
                });
                placeSearchController.clear();
              },
              onClear: () {
                setState(() {
                  _pickedLocation = null;
                  _placeHits = const [];
                  _searchFeedback = null;
                });
                placeSearchController.clear();
                ref.read(tagSubmissionPinLocationProvider.notifier).state =
                    null;
              },
            ),
            const SizedBox(height: 20),
            const Text(
              'Category',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in _tagTypes)
                  ChoiceChip(
                    label: Text(type.label),
                    selected: type.label == _selectedTypeLabel,
                    onSelected: (selected) {
                      if (!selected) return;
                      setState(() {
                        _selectedTypeLabel = type.label;
                        if (!type.details.contains(_selectedDetail)) {
                          _selectedDetail = type.details.first;
                        }
                      });
                    },
                    selectedColor: type.fill,
                    labelStyle: TextStyle(
                      color: type.label == _selectedTypeLabel
                          ? type.accent
                          : AppColors.primaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Detail',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in selectedType.details)
                  FilterChip(
                    label: Text(d),
                    selected: d == _selectedDetail,
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedDetail = d);
                    },
                    selectedColor: selectedType.fill,
                    checkmarkColor: selectedType.accent,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: d == _selectedDetail
                          ? selectedType.accent
                          : AppColors.primaryText,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Visibility',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Anonymous', label: Text('Anonymous')),
                ButtonSegment(value: 'Public', label: Text('Public')),
              ],
              selected: {_selectedVisibility},
              onSelectionChanged: (s) {
                if (s.isEmpty) return;
                setState(() => _selectedVisibility = s.first);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: noteController,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ListenableBuilder(
              listenable: noteController,
              builder: (context, _) {
                return FilledButton.icon(
                  onPressed: submissionState.isLoading || !_canSubmit
                      ? null
                      : _submit,
                  icon: submissionState.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    submissionState.isLoading ? 'Submitting…' : 'Submit tag',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoneCard extends StatelessWidget {
  const _ZoneCard({
    required this.title,
    required this.zone,
    required this.refreshing,
    this.pendingLocation = false,
  });

  final String title;
  final ZoneModel? zone;
  final bool refreshing;
  final bool pendingLocation;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (refreshing)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              zone != null
                  ? '${zoneDisplayTitle(zone!)} · ${zoneMapSubtitle(zone!)}'
                  : pendingLocation || refreshing
                      ? 'Looking up zone for this point…'
                      : 'Zone loads after you set a location.',
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationCard extends ConsumerWidget {
  const _LocationCard({
    required this.placeSearchController,
    required this.pickedLocation,
    required this.searchBusy,
    required this.gpsBusy,
    required this.placeHits,
    required this.searchFeedback,
    required this.onPlaceSubmitted,
    required this.onSelectPlaceHit,
    required this.onGps,
    required this.onExploreCenter,
    required this.onClearSearch,
    required this.onClear,
  });

  final TextEditingController placeSearchController;
  final LatLng? pickedLocation;
  final bool searchBusy;
  final bool gpsBusy;
  final List<CebuPlaceSearchHit> placeHits;
  final String? searchFeedback;
  final Future<void> Function() onPlaceSubmitted;
  final void Function(CebuPlaceSearchHit hit) onSelectPlaceHit;
  final Future<void> Function() onGps;
  final VoidCallback onExploreCenter;
  final VoidCallback onClearSearch;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolvedPlace = pickedLocation == null
        ? null
        : ref
            .watch(
              resolvedPlaceAtPointProvider((
                lat: pickedLocation!.latitude,
                lng: pickedLocation!.longitude,
              )),
            )
            .valueOrNull;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Location',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
            const SizedBox(height: 4),
            const Text(
              'Search, use GPS, or copy the center from Explore’s map.',
              style: TextStyle(
                color: AppColors.mutedText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: placeSearchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onPlaceSubmitted(),
              decoration: InputDecoration(
                hintText: 'Mall, street, landmark, building…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searchBusy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (placeSearchController.text.trim().isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: onClearSearch,
                            )
                          : null),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (placeHits.isNotEmpty ||
                searchFeedback != null ||
                (searchBusy && placeSearchController.text.trim().length >= 2))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _TagPlaceSearchResults(
                  hits: placeHits,
                  feedback: searchFeedback,
                  loading: searchBusy,
                  onSelect: onSelectPlaceHit,
                ),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: gpsBusy ? null : () => onGps(),
              icon: gpsBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded),
              label: const Text('Use my GPS'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onExploreCenter,
              icon: const Icon(Icons.map_rounded),
              label: const Text('Use Explore map center'),
            ),
            if (pickedLocation != null) ...[
              const SizedBox(height: 12),
              if (resolvedPlace != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: placeTypeAccentColor(resolvedPlace.placeType)
                        .withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: placeTypeAccentColor(resolvedPlace.placeType)
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        placeTypeIcon(resolvedPlace.placeType),
                        size: 20,
                        color: placeTypeAccentColor(resolvedPlace.placeType),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tagging near ${resolvedPlace.displayName} '
                          '(${placeTypeLabel(resolvedPlace.placeType)})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: AppColors.primaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Text(
                  'Outside a named catalog place — tag still counts toward '
                  'the nearest cell.',
                  style: TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 8),
              SelectableText(
                '${pickedLocation!.latitude.toStringAsFixed(5)}, '
                '${pickedLocation!.longitude.toStringAsFixed(5)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Clear'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TagPlaceSearchResults extends StatelessWidget {
  const _TagPlaceSearchResults({
    required this.hits,
    required this.feedback,
    required this.loading,
    required this.onSelect,
  });

  final List<CebuPlaceSearchHit> hits;
  final String? feedback;
  final bool loading;
  final void Function(CebuPlaceSearchHit hit) onSelect;

  @override
  Widget build(BuildContext context) {
    if (hits.isEmpty && feedback == null && !loading) {
      return const SizedBox.shrink();
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading && hits.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
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
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
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
                padding: const EdgeInsets.only(bottom: 4),
                itemCount: hits.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final hit = hits[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.place_outlined,
                      size: 20,
                      color: AppColors.mutedText,
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
}

class _TagType {
  const _TagType({
    required this.backendCategory,
    required this.label,
    required this.icon,
    required this.accent,
    required this.fill,
    required this.details,
  });

  final String backendCategory;
  final String label;
  final IconData icon;
  final Color accent;
  final Color fill;
  final List<String> details;
}
