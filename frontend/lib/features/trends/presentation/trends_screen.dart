import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../app/theme/colors.dart';
import '../../../shared/models/zone.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/traveler_gradient.dart';
import '../../../shared/zone_place_ui.dart';
import 'places_to_go_sheet.dart';

enum _TrendsSection { forYou, browse, routes }

enum _TrendVibeFilter { all, food, night, nature, budget, student }

class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({this.zoneId, super.key});

  final String? zoneId;

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  _TrendsSection _section = _TrendsSection.forYou;
  _TrendVibeFilter _filter = _TrendVibeFilter.all;

  @override
  Widget build(BuildContext context) {
    final selectedZone = ref.watch(selectedZoneProvider);
    final feedAsync = ref.watch(zoneFeedProvider);
    final feedZones = feedAsync.valueOrNull ?? const <ZoneModel>[];
    final zone = _resolveZone(selectedZone, feedZones, widget.zoneId);
    final intelligence =
        zone == null ? null : _ZoneIntelligence.fromZone(zone);
    final hotZones = _hotZonesFromFeed(feedZones);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(zoneFeedProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              _Hero(
                zone: zone,
                intelligence: intelligence,
                onExploreTap: () => context.go('/explore'),
              ),
              const SizedBox(height: 12),
              _TrendsSectionBar(
                section: _section,
                onChanged: (value) => setState(() => _section = value),
              ),
              if (_section != _TrendsSection.forYou) ...[
                const SizedBox(height: 10),
                _TrendsVibeFilterRow(
                  filter: _filter,
                  onChanged: (value) => setState(() => _filter = value),
                ),
              ],
              const SizedBox(height: 12),
              ..._sectionChildren(
                context: context,
                zone: zone,
                intelligence: intelligence,
                hotZones: hotZones,
                feedLoading: feedAsync.isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sectionChildren({
    required BuildContext context,
    required ZoneModel? zone,
    required _ZoneIntelligence? intelligence,
    required List<ZoneModel> hotZones,
    required bool feedLoading,
  }) {
    switch (_section) {
      case _TrendsSection.forYou:
        return _forYouChildren(
          context: context,
          zone: zone,
          intelligence: intelligence,
          hotZones: hotZones,
          feedLoading: feedLoading,
        );
      case _TrendsSection.browse:
        return [
          _SectionCard(
            title: 'Browse by vibe',
            subtitle:
                'Pick a mood — we’ll suggest popular places to visit nearby.',
            child: _TrendCategoryGrid(
              filter: _filter,
              onTrendTap: (item) => _showPlacesToGo(context, item, zone),
            ),
          ),
        ];
      case _TrendsSection.routes:
        return [
          _SectionCard(
            title: 'Curated routes',
            subtitle:
                'Paths locals and travelers actually take — open any stop on the map.',
            child: _RouteCardList(
              filter: _filter,
              onStartRoute: (route) =>
                  _previewExplore(context, route.stops.first),
              onStopTap: (stop) => _previewExplore(context, stop),
            ),
          ),
        ];
    }
  }

  List<Widget> _forYouChildren({
    required BuildContext context,
    required ZoneModel? zone,
    required _ZoneIntelligence? intelligence,
    required List<ZoneModel> hotZones,
    required bool feedLoading,
  }) {
    final children = <Widget>[];

    if (intelligence != null && zone != null) {
      children.addAll([
        _ZoneSignalCard(zone: zone, intelligence: intelligence),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Trending near ${_compactZoneLabel(zone.displayName)}',
          subtitle:
              '${intelligence.zoneType} · ${intelligence.travelerMix} · ${intelligence.peakTime} peak',
          child: _TrendWrap(
            items: intelligence.trends,
            onTap: (trend) => _previewExplore(context, trend),
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Suggested for this zone',
          subtitle: intelligence.routeName,
          child: _RouteTimeline(
            stops: intelligence.routeStops,
            activities: intelligence.routeActivities,
            onStopTap: (stop) => _previewExplore(context, stop),
            onStartRoute: () => _previewExplore(
              context,
              intelligence.routeStops.first,
            ),
          ),
        ),
        const SizedBox(height: 12),
      ]);
    } else {
      children.addAll([
        _SectionCard(
          title: 'What’s active in Cebu',
          subtitle: feedLoading
              ? 'Loading live zone signals…'
              : 'Tap a hot zone to personalize trends, or pick a vibe below.',
          child: _CityPulseStrip(
            zones: hotZones,
            loading: feedLoading,
            onZoneTap: (z) {
              ref.read(selectedZoneProvider.notifier).state = z;
              setState(() => _section = _TrendsSection.forYou);
            },
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Quick vibes',
          subtitle: 'Top-rated places to visit by mood.',
          child: _TrendCategoryGrid(
            filter: _TrendVibeFilter.all,
            maxItems: 6,
            onTrendTap: (item) => _showPlacesToGo(context, item, zone),
          ),
        ),
        const SizedBox(height: 12),
      ]);
    }

    children.add(
      _CebuReferencePanel(
        onAreaTap: (area) => _previewExplore(context, area),
        onTrendTap: (trend) => _previewExplore(context, trend),
      ),
    );
    return children;
  }

  void _showPlacesToGo(
    BuildContext context,
    _TrendCategoryItem item,
    ZoneModel? zone,
  ) {
    final center = zone != null
        ? LatLng(zone.centroidLat, zone.centroidLng)
        : _locationForLabel(item.exploreLabel);
    final areaLabel = zone != null
        ? zoneDisplayTitle(zone)
        : _cleanPlaceLabel(item.exploreLabel);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => PlacesToGoSheet(
        vibeTitle: item.title,
        vibeKey: item.vibeKey,
        areaLabel: areaLabel,
        lat: center.latitude,
        lng: center.longitude,
      ),
    );
  }

  void _previewExplore(BuildContext context, String label) {
    final cleaned = _cleanPlaceLabel(label);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cleaned,
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'We’ll focus the Explore map near this area so you can see matching zones and tags.',
                style: const TextStyle(
                  color: AppColors.mutedText,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _openExploreAt(context, label);
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Open in Explore'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryAction,
                    foregroundColor: AppColors.mapInk,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openExploreAt(BuildContext context, String label) {
    final target = _locationForLabel(label);
    ref.read(selectedZoneProvider.notifier).state = null;
    ref.read(currentUserLocationProvider.notifier).state = target;
    ref.read(exploreFocusLocationProvider.notifier).state = target;
    context.go('/explore');
  }

  ZoneModel? _resolveZone(
    ZoneModel? selected,
    List<ZoneModel> feedZones,
    String? id,
  ) {
    if (id != null && selected?.zoneId == id) return selected;
    if (id != null) {
      for (final zone in feedZones) {
        if (zone.zoneId == id) return zone;
      }
    }
    return selected;
  }

  List<ZoneModel> _hotZonesFromFeed(List<ZoneModel> zones) {
    final sorted = [...zones]
      ..sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
    return sorted.take(4).toList();
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.zone,
    required this.intelligence,
    required this.onExploreTap,
  });

  final ZoneModel? zone;
  final _ZoneIntelligence? intelligence;
  final VoidCallback onExploreTap;

  @override
  Widget build(BuildContext context) {
    final intel = intelligence;
    final title = zone == null
        ? 'What’s trending in Cebu'
        : _compactZoneLabel(zone!.displayName);
    final subtitle = intel == null
        ? 'Discover vibes, curated routes, and live zone behavior — then jump to the map.'
        : '${intel.zoneType} · ${intel.travelerMix} · ${intel.peakTime} peak';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.mapInk,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.trending_up_rounded,
                color: Colors.white,
                size: 30,
              ),
              const Spacer(),
              if (zone != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${zone!.confidenceScore.round()}% confidence',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 27,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFFBAE6FD),
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (zone == null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onExploreTap,
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Pick a zone on Explore'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrendsSectionBar extends StatelessWidget {
  const _TrendsSectionBar({
    required this.section,
    required this.onChanged,
  });

  final _TrendsSection section;
  final ValueChanged<_TrendsSection> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_TrendsSection>(
      segments: const [
        ButtonSegment(
          value: _TrendsSection.forYou,
          label: Text('For you'),
          icon: Icon(Icons.person_outline_rounded, size: 18),
        ),
        ButtonSegment(
          value: _TrendsSection.browse,
          label: Text('Vibes'),
          icon: Icon(Icons.grid_view_rounded, size: 18),
        ),
        ButtonSegment(
          value: _TrendsSection.routes,
          label: Text('Routes'),
          icon: Icon(Icons.route_outlined, size: 18),
        ),
      ],
      selected: {section},
      onSelectionChanged: (values) => onChanged(values.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.mapInk;
          }
          return AppColors.mutedText;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.accent.withValues(alpha: 0.55);
          }
          return Colors.white;
        }),
      ),
    );
  }
}

class _TrendsVibeFilterRow extends StatelessWidget {
  const _TrendsVibeFilterRow({
    required this.filter,
    required this.onChanged,
  });

  final _TrendVibeFilter filter;
  final ValueChanged<_TrendVibeFilter> onChanged;

  static const _labels = {
    _TrendVibeFilter.all: 'All',
    _TrendVibeFilter.food: 'Food',
    _TrendVibeFilter.night: 'Night',
    _TrendVibeFilter.nature: 'Nature',
    _TrendVibeFilter.budget: 'Budget',
    _TrendVibeFilter.student: 'Student',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final entry in _labels.entries) ...[
            _TrendFilterChip(
              label: entry.value,
              selected: filter == entry.key,
              onTap: () => onChanged(entry.key),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _TrendFilterChip extends StatelessWidget {
  const _TrendFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.mapInk : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.mapInk : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.primaryText,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _CityPulseStrip extends StatelessWidget {
  const _CityPulseStrip({
    required this.zones,
    required this.loading,
    required this.onZoneTap,
  });

  final List<ZoneModel> zones;
  final bool loading;
  final ValueChanged<ZoneModel> onZoneTap;

  @override
  Widget build(BuildContext context) {
    if (loading && zones.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (zones.isEmpty) {
      return const Text(
        'No live zones yet. Pull to refresh or add a tag on Explore.',
        style: TextStyle(
          color: AppColors.mutedText,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      );
    }
    return Column(
      children: [
        for (final zone in zones)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onZoneTap(zone),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _compactZoneLabel(zone.displayName),
                            style: const TextStyle(
                              color: AppColors.primaryText,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${travelerMixTrendLabel(zone.travelerMix)} · ${zone.reportCount} tags',
                            style: const TextStyle(
                              color: AppColors.mutedText,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryAction.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${zone.confidenceScore.round()}%',
                        style: const TextStyle(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.primaryAction,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CebuReferencePanel extends StatefulWidget {
  const _CebuReferencePanel({
    required this.onAreaTap,
    required this.onTrendTap,
  });

  final ValueChanged<String> onAreaTap;
  final ValueChanged<String> onTrendTap;

  @override
  State<_CebuReferencePanel> createState() => _CebuReferencePanelState();
}

class _CebuReferencePanelState extends State<_CebuReferencePanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'More about Cebu',
                          style: TextStyle(
                            color: AppColors.primaryText,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Behavior map, food zones, and reference trends',
                          style: TextStyle(
                            color: AppColors.mutedText,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.mutedText,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  _SectionCard(
                    title: 'How Cebu areas feel',
                    subtitle:
                        'Grouped by zone behavior, not just place category.',
                    child: _AreaIntelligenceTable(
                      maxRows: 4,
                      onAreaTap: widget.onAreaTap,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FoodBehaviorCard(onTrendTap: widget.onTrendTap),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.mutedText,
              height: 1.35,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ZoneSignalCard extends StatelessWidget {
  const _ZoneSignalCard({required this.zone, required this.intelligence});

  final ZoneModel zone;
  final _ZoneIntelligence intelligence;

  @override
  Widget build(BuildContext context) {
    final crowdPercent = (zone.crowdLevel * 100).clamp(0, 100).round();
    return _SectionCard(
      title: 'Selected Zone Signal',
      subtitle: 'Why StrollWise is recommending this area behavior right now.',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _Pill(icon: Icons.place_outlined, label: intelligence.zoneType),
          _Pill(
            icon: Icons.people_alt_outlined,
            label: intelligence.travelerMix,
          ),
          _Pill(
            icon: Icons.schedule_outlined,
            label: '${intelligence.peakTime} peak',
          ),
          _Pill(
            icon: Icons.bubble_chart_outlined,
            label: '$crowdPercent% activity',
          ),
          _Pill(
            icon: Icons.verified_outlined,
            label: '${zone.confidenceScore.round()}% confidence',
          ),
          _Pill(icon: Icons.flag_outlined, label: '${zone.reportCount} tags'),
        ],
      ),
    );
  }
}

class _TrendWrap extends StatelessWidget {
  const _TrendWrap({required this.items, this.onTap});

  final List<String> items;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          _Pill(
            icon: _iconForTrend(item),
            label: item,
            onTap: onTap == null ? null : () => onTap!(item),
          ),
      ],
    );
  }
}

class _RouteTimeline extends StatelessWidget {
  const _RouteTimeline({
    required this.stops,
    required this.activities,
    required this.onStopTap,
    this.onStartRoute,
  });

  final List<String> stops;
  final List<String> activities;
  final ValueChanged<String> onStopTap;
  final VoidCallback? onStartRoute;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < stops.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == stops.length - 1 ? 0 : 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onStopTap(stops[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: AppColors.accent.withValues(alpha: 0.22),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: AppColors.mapInk,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        stops[i],
                        style: const TextStyle(
                          color: AppColors.primaryText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.map_outlined,
                      size: 16,
                      color: AppColors.primaryAction,
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        _TrendWrap(items: activities),
        if (onStartRoute != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onStartRoute,
              icon: const Icon(Icons.route_outlined, size: 18),
              label: const Text('Start route on map'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryAction,
                foregroundColor: AppColors.mapInk,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AreaIntelligenceTable extends StatelessWidget {
  const _AreaIntelligenceTable({
    required this.onAreaTap,
    this.maxRows,
  });

  final ValueChanged<String> onAreaTap;
  final int? maxRows;

  static const rows = [
    _AreaRow(
      'IT Park',
      'Commercial / Food',
      'Sugbo Mercado, cafes, coworking',
      'Mixed',
      'food, work, nightlife, study',
      'Night',
    ),
    _AreaRow(
      'Colon',
      'Historical / Commercial',
      'Carbon, Basilica, street food',
      'Local-heavy',
      'heritage, shopping, food',
      'Day',
    ),
    _AreaRow(
      'Mactan Resort Area',
      'Tourist / Hotel',
      'resorts, beach clubs',
      'Tourist-heavy',
      'beach, diving, nightlife',
      'Afternoon',
    ),
    _AreaRow(
      'Busay',
      'Nature / Tourist',
      'Tops, Temple of Leah',
      'Tourist-heavy',
      'sightseeing, coffee, mountain drive',
      'Sunset',
    ),
    _AreaRow(
      'Fuente',
      'Transport / Food',
      'Robinsons, Larsian',
      'Local-heavy',
      'commute, food, shopping',
      'Evening',
    ),
    _AreaRow(
      'Cebu Taoist Temple',
      'Cultural / Viewpoint',
      'Beverly Hills, city views',
      'Tourist-heavy',
      'sightseeing, photo stops, quiet walk',
      'Day',
    ),
    _AreaRow(
      'Sirao Flower Garden',
      'Nature / Photo Spot',
      'flower gardens, mountain road',
      'Tourist-heavy',
      'photo stop, weekend drive, sightseeing',
      'Afternoon',
    ),
    _AreaRow(
      'South Bus Terminal',
      'Transit / Budget',
      'bus terminal, cheap eats',
      'Local-heavy',
      'commute, budget travel, local food',
      'Morning',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final visible = maxRows == null ? rows : rows.take(maxRows!).toList();
    return Column(
      children: [
        for (final row in visible)
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => onAreaTap(row.area),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 48,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: _travelerAccent(row.travelerMix),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                row.area,
                                style: const TextStyle(
                                  color: AppColors.primaryText,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Text(
                              row.peakTime,
                              style: const TextStyle(
                                color: AppColors.primaryAction,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.map_outlined,
                              size: 16,
                              color: AppColors.primaryAction,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${row.zoneType} · ${row.travelerMix}',
                          style: const TextStyle(
                            color: AppColors.mutedText,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          row.hotspots,
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          row.activities,
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _FoodBehaviorCard extends StatelessWidget {
  const _FoodBehaviorCard({required this.onTrendTap});

  final ValueChanged<String> onTrendTap;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Food Behavior Split',
      subtitle:
          'Local eats vs tourist-facing spots — each ranks differently on the map.',
      child: Column(
        children: [
          _BehaviorColumn(
            title: 'Local Food Zones',
            description: 'Cheaper, practical, authentic, street-oriented.',
            items: const [
              'Larsian',
              'Carbon night food',
              'Pungko-pungko areas',
              'Carinderias',
              'Barbecue streets',
              'Wet market food',
            ],
            onItemTap: onTrendTap,
          ),
          const SizedBox(height: 12),
          _BehaviorColumn(
            title: 'International / Tourist Food Zones',
            description:
                'Visible, safe-looking, aesthetic, accessible, highly rated online.',
            items: const [
              'Rooftop restaurants',
              'Cafes',
              'Aesthetic restaurants',
              'Resorts',
              'Buffet areas',
              'Seafood restaurants',
            ],
            onItemTap: onTrendTap,
          ),
        ],
      ),
    );
  }
}

class _BehaviorColumn extends StatelessWidget {
  const _BehaviorColumn({
    required this.title,
    required this.description,
    required this.items,
    this.onItemTap,
  });

  final String title;
  final String description;
  final List<String> items;
  final ValueChanged<String>? onItemTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(
              color: AppColors.mutedText,
              height: 1.35,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          _TrendWrap(items: items, onTap: onItemTap),
        ],
      ),
    );
  }
}

class _TrendCategoryItem {
  const _TrendCategoryItem({
    required this.title,
    required this.subtitle,
    required this.exploreLabel,
    required this.vibeKey,
    required this.icon,
    required this.fill,
    required this.accent,
    required this.filter,
  });

  final String title;
  final String subtitle;
  final String exploreLabel;
  /// API vibe key: food | cafe | nightlife | tourist | nature | budget
  final String vibeKey;
  final IconData icon;
  final Color fill;
  final Color accent;
  final _TrendVibeFilter filter;
}

class _TrendCategoryGrid extends StatelessWidget {
  const _TrendCategoryGrid({
    required this.filter,
    required this.onTrendTap,
    this.maxItems,
  });

  final _TrendVibeFilter filter;
  final ValueChanged<_TrendCategoryItem> onTrendTap;
  final int? maxItems;

  static const _catalog = [
    _TrendCategoryItem(
      title: 'Food crawl',
      subtitle: 'Street eats & late bites',
      exploreLabel: 'Food Crawl Trends',
      vibeKey: 'food',
      icon: Icons.restaurant_outlined,
      fill: AppColors.foodFill,
      accent: AppColors.foodAccent,
      filter: _TrendVibeFilter.food,
    ),
    _TrendCategoryItem(
      title: 'Cafes & study',
      subtitle: 'Work-friendly corners',
      exploreLabel: 'Cafe and Study Trends',
      vibeKey: 'cafe',
      icon: Icons.local_cafe_outlined,
      fill: AppColors.studentFill,
      accent: AppColors.studentAccent,
      filter: _TrendVibeFilter.student,
    ),
    _TrendCategoryItem(
      title: 'Nightlife',
      subtitle: 'After-dark social zones',
      exploreLabel: 'Nightlife Trends',
      vibeKey: 'nightlife',
      icon: Icons.nightlife_outlined,
      fill: AppColors.commercialFill,
      accent: AppColors.commercialAccent,
      filter: _TrendVibeFilter.night,
    ),
    _TrendCategoryItem(
      title: 'Heritage walk',
      subtitle: 'History & culture',
      exploreLabel: 'Heritage Walk Trends',
      vibeKey: 'tourist',
      icon: Icons.museum_outlined,
      fill: AppColors.localFill,
      accent: AppColors.localAccent,
      filter: _TrendVibeFilter.all,
    ),
    _TrendCategoryItem(
      title: 'Nature escape',
      subtitle: 'Mountains & views',
      exploreLabel: 'Nature Escape Trends',
      vibeKey: 'nature',
      icon: Icons.landscape_outlined,
      fill: AppColors.touristFill,
      accent: AppColors.touristAccent,
      filter: _TrendVibeFilter.nature,
    ),
    _TrendCategoryItem(
      title: 'Student life',
      subtitle: 'Campus & budget hubs',
      exploreLabel: 'Student Activity Trends',
      vibeKey: 'cafe',
      icon: Icons.school_outlined,
      fill: AppColors.studentFill,
      accent: AppColors.studentAccent,
      filter: _TrendVibeFilter.student,
    ),
    _TrendCategoryItem(
      title: 'Weekend local',
      subtitle: 'Where locals go',
      exploreLabel: 'Weekend Local Trends',
      vibeKey: 'food',
      icon: Icons.weekend_outlined,
      fill: AppColors.localFill,
      accent: AppColors.localAccent,
      filter: _TrendVibeFilter.all,
    ),
    _TrendCategoryItem(
      title: 'Budget travel',
      subtitle: 'Cheap stays & eats',
      exploreLabel: 'Budget Traveler Trends',
      vibeKey: 'budget',
      icon: Icons.savings_outlined,
      fill: AppColors.transportFill,
      accent: AppColors.transportAccent,
      filter: _TrendVibeFilter.budget,
    ),
    _TrendCategoryItem(
      title: 'Digital nomad',
      subtitle: 'Wi‑Fi & coworking',
      exploreLabel: 'Digital Nomad Trends',
      vibeKey: 'cafe',
      icon: Icons.laptop_mac_outlined,
      fill: AppColors.mixedFill,
      accent: AppColors.mixedAccent,
      filter: _TrendVibeFilter.student,
    ),
    _TrendCategoryItem(
      title: 'Transit',
      subtitle: 'Commute corridors',
      exploreLabel: 'Commute and Transit Trends',
      vibeKey: 'tourist',
      icon: Icons.directions_bus_outlined,
      fill: AppColors.transportFill,
      accent: AppColors.transportAccent,
      filter: _TrendVibeFilter.budget,
    ),
    _TrendCategoryItem(
      title: 'Shopping',
      subtitle: 'Markets & malls',
      exploreLabel: 'Shopping Trends',
      vibeKey: 'tourist',
      icon: Icons.shopping_bag_outlined,
      fill: AppColors.commercialFill,
      accent: AppColors.commercialAccent,
      filter: _TrendVibeFilter.all,
    ),
    _TrendCategoryItem(
      title: 'Wellness',
      subtitle: 'Slow & recharge',
      exploreLabel: 'Wellness and Relaxation Trends',
      vibeKey: 'nature',
      icon: Icons.spa_outlined,
      fill: AppColors.touristFill,
      accent: AppColors.touristAccent,
      filter: _TrendVibeFilter.nature,
    ),
    _TrendCategoryItem(
      title: 'Family day',
      subtitle: 'Kid-friendly outings',
      exploreLabel: 'Family Activity Trends',
      vibeKey: 'tourist',
      icon: Icons.family_restroom_outlined,
      fill: AppColors.hotelFill,
      accent: AppColors.hotelAccent,
      filter: _TrendVibeFilter.all,
    ),
    _TrendCategoryItem(
      title: 'Adventure',
      subtitle: 'Active & outdoor',
      exploreLabel: 'Adventure Trends',
      vibeKey: 'nature',
      icon: Icons.terrain_outlined,
      fill: AppColors.touristFill,
      accent: AppColors.touristAccent,
      filter: _TrendVibeFilter.nature,
    ),
    _TrendCategoryItem(
      title: 'Hidden spots',
      subtitle: 'Off-guide finds',
      exploreLabel: 'Hidden Local Spots',
      vibeKey: 'food',
      icon: Icons.explore_outlined,
      fill: AppColors.mixedFill,
      accent: AppColors.mixedAccent,
      filter: _TrendVibeFilter.all,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final items = _catalog
        .where((item) => _matchesVibeFilter(item.filter, filter))
        .toList();
    final visible = maxItems == null ? items : items.take(maxItems!).toList();

    if (visible.isEmpty) {
      return const Text(
        'No vibes match this filter. Try another chip above.',
        style: TextStyle(
          color: AppColors.mutedText,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final item in visible)
              SizedBox(
                width: width,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => onTrendTap(item),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: item.fill,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: item.accent.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(item.icon, color: item.accent, size: 22),
                          const SizedBox(height: 8),
                          Text(
                            item.title,
                            style: TextStyle(
                              color: item.accent,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.subtitle,
                            style: const TextStyle(
                              color: AppColors.secondaryText,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RouteCardList extends StatelessWidget {
  const _RouteCardList({
    required this.filter,
    required this.onStartRoute,
    required this.onStopTap,
  });

  final _TrendVibeFilter filter;
  final ValueChanged<_Itinerary> onStartRoute;
  final ValueChanged<String> onStopTap;

  static const _routes = [
    _Itinerary(
      'Historical Cebu Trail',
      '~3 hrs',
      'Heritage',
      _TrendVibeFilter.all,
      ['Basilica', 'Magellan’s Cross', 'Fort San Pedro', 'Colon food stop'],
      ['heritage walk', 'museum', 'local food'],
    ),
    _Itinerary(
      'Nightlife + Food Route',
      '~4 hrs',
      'Night',
      _TrendVibeFilter.night,
      ['IT Park', 'Sugbo Mercado', 'Streetscape', 'rooftop bars'],
      ['food crawl', 'nightlife', 'social hangout'],
    ),
    _Itinerary(
      'Local Student Route',
      '~2.5 hrs',
      'Student',
      _TrendVibeFilter.student,
      ['USC Talamban', 'cafes', 'study hubs', 'cheap food areas'],
      ['study', 'budget meals', 'coworking'],
    ),
    _Itinerary(
      'Nature + Relaxation Route',
      '~4 hrs',
      'Nature',
      _TrendVibeFilter.nature,
      ['Busay', 'Temple of Leah', 'Tops', 'mountain cafes'],
      ['sightseeing', 'coffee', 'sunset drive'],
    ),
    _Itinerary(
      'Weekend Family Route',
      '~3 hrs',
      'Family',
      _TrendVibeFilter.all,
      ['Ocean Park', 'IL Corso', 'SRP'],
      ['family bonding', 'dining', 'walking'],
    ),
    _Itinerary(
      'Budget Backpacker Route',
      '~5 hrs',
      'Budget',
      _TrendVibeFilter.budget,
      ['South Bus Terminal', 'Colon', 'cheap inns', 'local eateries'],
      ['budget travel', 'local exploration'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final routes =
        _routes.where((r) => _matchesVibeFilter(r.filter, filter)).toList();

    if (routes.isEmpty) {
      return const Text(
        'No routes match this filter. Try another vibe.',
        style: TextStyle(
          color: AppColors.mutedText,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Column(
      children: [
        for (final route in routes)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RouteCard(
              route: route,
              onStartRoute: () => onStartRoute(route),
              onStopTap: onStopTap,
            ),
          ),
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.route,
    required this.onStartRoute,
    required this.onStopTap,
  });

  final _Itinerary route;
  final VoidCallback onStartRoute;
  final ValueChanged<String> onStopTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.mapInk.withValues(alpha: 0.04),
            AppColors.secondaryAction.withValues(alpha: 0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  route.title,
                  style: const TextStyle(
                    color: AppColors.primaryText,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              _RouteMetaChip(label: route.duration),
              const SizedBox(width: 6),
              _RouteMetaChip(label: route.vibe),
            ],
          ),
          const SizedBox(height: 12),
          _RouteTimeline(
            stops: route.stops,
            activities: route.activities,
            onStopTap: onStopTap,
            onStartRoute: onStartRoute,
          ),
        ],
      ),
    );
  }
}

class _RouteMetaChip extends StatelessWidget {
  const _RouteMetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.mutedText,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.72;
    final chip = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.mapInk),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              softWrap: true,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 5),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 13,
              color: AppColors.primaryAction,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: chip,
    );
  }
}

String _compactZoneLabel(String displayName) {
  final normalized = displayName.trim();
  final lower = normalized.toLowerCase();

  if (lower.contains('usc main')) {
    return 'USC Main';
  }
  if (lower.contains('usc talamban')) {
    return 'USC Talamban';
  }
  if (lower.contains('it park')) {
    return 'IT Park';
  }
  if (lower.contains('ayala')) {
    return 'Ayala';
  }
  if (lower.contains('colon')) {
    return 'Colon';
  }
  if (lower.contains('carbon')) {
    return 'Carbon Market';
  }
  if (lower.contains('busay')) {
    return 'Busay';
  }
  if (lower.contains('mactan')) {
    return 'Mactan';
  }
  if (lower.contains('fuente')) {
    return 'Fuente';
  }
  if (lower.contains('pier')) {
    return 'Pier Area';
  }
  if (lower.contains('sirao')) {
    return 'Sirao';
  }

  return normalized
      .replaceAll(RegExp(r'\bzone\b', caseSensitive: false), '')
      .replaceAll(
        RegExp(
          r'\b(student|activity|commercial|local|food|shopping|transit|safety|nature|sunset|resort|beach|neighborhood|market)\b',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+\+\s+'), ' ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
}

class _ZoneIntelligence {
  const _ZoneIntelligence({
    required this.zoneType,
    required this.travelerMix,
    required this.peakTime,
    required this.trends,
    required this.routeName,
    required this.routeStops,
    required this.routeActivities,
  });

  final String zoneType;
  final String travelerMix;
  final String peakTime;
  final List<String> trends;
  final String routeName;
  final List<String> routeStops;
  final List<String> routeActivities;

  factory _ZoneIntelligence.fromZone(ZoneModel zone) {
    final name = zone.displayName.toLowerCase();
    final function = zone.zoneType;
    final travelerMix = travelerMixTrendLabel(zone.travelerMix);

    if (name.contains('colon') || name.contains('basilica')) {
      return const _ZoneIntelligence(
        zoneType: 'Historical / Commercial',
        travelerMix: 'Local-heavy',
        peakTime: 'Day',
        trends: [
          'Heritage Walk Trends',
          'Shopping Trends',
          'Local Food Zones',
          'Budget Traveler Trends',
        ],
        routeName: 'Historical Cebu Trail',
        routeStops: [
          'Basilica',
          'Magellan’s Cross',
          'Fort San Pedro',
          'Colon food stop',
        ],
        routeActivities: ['heritage walk', 'museum', 'local food'],
      );
    }
    if (name.contains('busay') ||
        name.contains('tops') ||
        name.contains('leah')) {
      return const _ZoneIntelligence(
        zoneType: 'Nature / Tourist',
        travelerMix: 'Tourist-heavy',
        peakTime: 'Sunset',
        trends: [
          'Nature Escape Trends',
          'Cafe and Study Trends',
          'Wellness and Relaxation Trends',
          'Hidden Local Spots',
        ],
        routeName: 'Nature + Relaxation Route',
        routeStops: ['Busay', 'Temple of Leah', 'Tops', 'mountain cafes'],
        routeActivities: ['sightseeing', 'coffee', 'sunset drive'],
      );
    }
    if (name.contains('mactan') || name.contains('resort')) {
      return const _ZoneIntelligence(
        zoneType: 'Tourist / Hotel',
        travelerMix: 'Tourist-heavy',
        peakTime: 'Afternoon',
        trends: [
          'Wellness and Relaxation Trends',
          'Adventure Trends',
          'Nightlife Trends',
          'International / Tourist Food Zones',
        ],
        routeName: 'Mactan Resort Day',
        routeStops: [
          'resorts',
          'beach clubs',
          'seafood restaurants',
          'nightlife',
        ],
        routeActivities: ['beach', 'diving', 'nightlife'],
      );
    }
    if (name.contains('fuente') || function == 'transport_zone') {
      return const _ZoneIntelligence(
        zoneType: 'Transport / Food',
        travelerMix: 'Local-heavy',
        peakTime: 'Evening',
        trends: [
          'Commute and Transit Trends',
          'Food Crawl Trends',
          'Shopping Trends',
          'Weekend Local Trends',
        ],
        routeName: 'Fuente Food + Transit Loop',
        routeStops: [
          'Robinsons',
          'Larsian',
          'commute corridors',
          'shopping streets',
        ],
        routeActivities: ['commute', 'food', 'shopping'],
      );
    }
    if (function == 'student_area' || name.contains('usc')) {
      return const _ZoneIntelligence(
        zoneType: 'Student / Budget',
        travelerMix: 'Local-heavy',
        peakTime: 'Afternoon',
        trends: [
          'Student Activity Trends',
          'Cafe and Study Trends',
          'Budget Traveler Trends',
          'Hidden Local Spots',
        ],
        routeName: 'Local Student Route',
        routeStops: ['USC Talamban', 'cafes', 'study hubs', 'cheap food areas'],
        routeActivities: ['study', 'budget meals', 'coworking'],
      );
    }
    if (function == 'food_hotspot') {
      return _ZoneIntelligence(
        zoneType: 'Food / Social',
        travelerMix: travelerMix,
        peakTime: zone.peakTimeLabel ?? 'Evening',
        trends: const [
          'Food Crawl Trends',
          'Weekend Local Trends',
          'Hidden Local Spots',
          'Local Food Zones',
        ],
        routeName: 'Food Crawl Route',
        routeStops: const [
          'main food cluster',
          'side-street stalls',
          'cafes',
          'late-night stop',
        ],
        routeActivities: const [
          'food crawl',
          'local exploration',
          'social hangout',
        ],
      );
    }
    return _ZoneIntelligence(
      zoneType: _titleize(function.replaceAll('_', ' / ')),
      travelerMix: travelerMix,
      peakTime: zone.peakTimeLabel ?? 'Variable',
      trends: const [
        'Weekend Local Trends',
        'Shopping Trends',
        'Cafe and Study Trends',
        'Hidden Local Spots',
      ],
      routeName: 'Zone Experience Route',
      routeStops: const [
        'area center',
        'nearby activity cluster',
        'food stop',
        'walkable edge',
      ],
      routeActivities: const ['local exploration', 'walking', 'dining'],
    );
  }
}

class _AreaRow {
  const _AreaRow(
    this.area,
    this.zoneType,
    this.hotspots,
    this.travelerMix,
    this.activities,
    this.peakTime,
  );

  final String area;
  final String zoneType;
  final String hotspots;
  final String travelerMix;
  final String activities;
  final String peakTime;
}

class _Itinerary {
  const _Itinerary(
    this.title,
    this.duration,
    this.vibe,
    this.filter,
    this.stops,
    this.activities,
  );

  final String title;
  final String duration;
  final String vibe;
  final _TrendVibeFilter filter;
  final List<String> stops;
  final List<String> activities;
}

bool _matchesVibeFilter(_TrendVibeFilter itemFilter, _TrendVibeFilter active) {
  if (active == _TrendVibeFilter.all) return true;
  return itemFilter == active;
}

Color _travelerAccent(String travelerMix, {double? localPresencePercent}) {
  final ratio = TravelerGradient.localRatioFromMix(
    travelerMix,
    localPresencePercent: localPresencePercent,
  );
  return TravelerGradient.colorForRatio(ratio);
}

LatLng _locationForLabel(String label) {
  final key = label.toLowerCase();
  if (key.contains('it park') ||
      key.contains('sugbo') ||
      key.contains('nightlife') ||
      key.contains('digital nomad')) {
    return const LatLng(10.3306, 123.9056);
  }
  if (key.contains('colon') ||
      key.contains('carbon') ||
      key.contains('heritage') ||
      key.contains('basilica') ||
      key.contains('magellan')) {
    return const LatLng(10.2968, 123.9015);
  }
  if (key.contains('fort san pedro') || key.contains('museum')) {
    return const LatLng(10.2927, 123.9058);
  }
  if (key.contains('busay') ||
      key.contains('tops') ||
      key.contains('temple of leah') ||
      key.contains('nature') ||
      key.contains('sunset') ||
      key.contains('mountain')) {
    return const LatLng(10.3700, 123.8780);
  }
  if (key.contains('sirao') || key.contains('flower')) {
    return const LatLng(10.3940, 123.8680);
  }
  if (key.contains('taoist')) {
    return const LatLng(10.3410, 123.8885);
  }
  if (key.contains('mactan') ||
      key.contains('resort') ||
      key.contains('beach') ||
      key.contains('diving')) {
    return const LatLng(10.2983, 124.0155);
  }
  if (key.contains('fuente') ||
      key.contains('larsian') ||
      key.contains('robinsons')) {
    return const LatLng(10.3105, 123.8921);
  }
  if (key.contains('usc') ||
      key.contains('student') ||
      key.contains('talamban') ||
      key.contains('study')) {
    return const LatLng(10.3545, 123.9139);
  }
  if (key.contains('ocean park') ||
      key.contains('il corso') ||
      key.contains('srp') ||
      key.contains('family')) {
    return const LatLng(10.2665, 123.8812);
  }
  if (key.contains('south bus') ||
      key.contains('budget') ||
      key.contains('backpacker') ||
      key.contains('transit') ||
      key.contains('commute')) {
    return const LatLng(10.3001, 123.8931);
  }
  if (key.contains('shopping')) {
    return const LatLng(10.3181, 123.9056);
  }
  if (key.contains('wellness') || key.contains('relaxation')) {
    return const LatLng(10.2983, 124.0155);
  }
  return const LatLng(10.3157, 123.8854);
}

String _cleanPlaceLabel(String label) {
  return label.replaceAll('Trends', '').replaceAll('Route', '').trim();
}

IconData _iconForTrend(String trend) {
  final t = trend.toLowerCase();
  if (t.contains('food') || t.contains('dining') || t.contains('carinderia')) {
    return Icons.restaurant_outlined;
  }
  if (t.contains('cafe') || t.contains('study') || t.contains('nomad')) {
    return Icons.local_cafe_outlined;
  }
  if (t.contains('night')) {
    return Icons.nightlife_outlined;
  }
  if (t.contains('heritage') || t.contains('historical')) {
    return Icons.museum_outlined;
  }
  if (t.contains('nature') || t.contains('adventure') || t.contains('beach')) {
    return Icons.landscape_outlined;
  }
  if (t.contains('student')) {
    return Icons.school_outlined;
  }
  if (t.contains('transit') || t.contains('commute')) {
    return Icons.directions_bus_outlined;
  }
  if (t.contains('shopping') || t.contains('market')) {
    return Icons.shopping_bag_outlined;
  }
  if (t.contains('family')) {
    return Icons.family_restroom_outlined;
  }
  if (t.contains('wellness') || t.contains('relaxation')) {
    return Icons.spa_outlined;
  }
  return Icons.explore_outlined;
}

String _titleize(String value) {
  return value
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}
