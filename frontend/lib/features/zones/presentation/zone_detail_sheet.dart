import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../app/theme/colors.dart';
import '../../../shared/models/zone.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/traveler_gradient.dart';
import '../../../shared/zone_validation_metrics.dart';

class ZoneDetailSheet extends ConsumerWidget {
  const ZoneDetailSheet({super.key});

  static const _tealBg = AppColors.mapInk;
  static const _chipBg = Color(0xFFE0F2FE);
  static const _chipText = AppColors.lagoon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(selectedZoneDetailProvider);
    final zone = detailAsync.valueOrNull ?? ref.watch(selectedZoneProvider);
    if (zone == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('No zone selected')),
      );
    }

    if (detailAsync.isLoading && detailAsync.valueOrNull == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Container(
            color: _tealBg,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverToBoxAdapter(child: _ZoneHero(zone: zone)),
                SliverToBoxAdapter(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
                    child: _ZoneBody(zone: zone),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ZoneHero extends StatelessWidget {
  const _ZoneHero({required this.zone});

  final ZoneModel zone;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _HeroIconButton(
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                Text(
                  zone.travelerType,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: 0.2,
                  ),
                ),
                const _HeroIconButton(icon: Icons.bookmark_border_rounded),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 190,
              child: _HexCluster(
                travelerColor: _colorFromHex(zone.fillColor),
                borderColor: _colorFromHex(zone.borderColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _colorFromHex(String hex) {
  final normalized = hex.replaceAll('#', '');
  if (normalized.length != 6) return const Color(0xFFFED64A);
  return Color(int.parse('FF$normalized', radix: 16));
}

class _HeroIconButton extends StatelessWidget {
  const _HeroIconButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _HexCluster extends StatelessWidget {
  const _HexCluster({required this.travelerColor, required this.borderColor});

  final Color travelerColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, 360.0);
        return Center(
          child: SizedBox(
            width: size,
            height: 190,
            child: CustomPaint(
              painter: _HexClusterPainter(
                selectedFill: travelerColor.withValues(alpha: 0.82),
                selectedBorder: borderColor,
                neighborFill: travelerColor.withValues(alpha: 0.16),
                neighborBorder: borderColor.withValues(alpha: 0.32),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HexClusterPainter extends CustomPainter {
  _HexClusterPainter({
    required this.selectedFill,
    required this.selectedBorder,
    required this.neighborFill,
    required this.neighborBorder,
  });

  final Color selectedFill;
  final Color selectedBorder;
  final Color neighborFill;
  final Color neighborBorder;

  void _drawHex(
    Canvas canvas,
    Offset center,
    double radius,
    Color fill,
    Color border, {
    double strokeWidth = 2.2,
  }) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 3 * i - math.pi / 2;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 5.6;
    final hexWidth = radius * math.sqrt(3);
    final hexHeight = radius * 1.5;

    final selectedCoord = (0, 0);
    final neighborCoords = <(int, int)>{
      (-1, 0),
      (1, 0),
      (0, -1),
      (0, 1),
      (-1, 1),
      (1, -1),
      (-2, 0),
      (2, 0),
      (-1, -1),
      (1, 1),
      (-2, 1),
      (2, -1),
    };

    Offset axialToPixel(int q, int r) {
      final dx = hexWidth * (q + r / 2);
      final dy = hexHeight * r;
      return Offset(center.dx + dx, center.dy + dy);
    }

    for (final (q, r) in neighborCoords) {
      _drawHex(
        canvas,
        axialToPixel(q, r),
        radius,
        neighborFill,
        neighborBorder,
        strokeWidth: 1.6,
      );
    }
    _drawHex(
      canvas,
      axialToPixel(selectedCoord.$1, selectedCoord.$2),
      radius * 1.02,
      selectedFill,
      selectedBorder,
      strokeWidth: 3.2,
    );
  }

  @override
  bool shouldRepaint(covariant _HexClusterPainter oldDelegate) =>
      oldDelegate.selectedFill != selectedFill ||
      oldDelegate.selectedBorder != selectedBorder;
}

class _ZoneBody extends ConsumerWidget {
  const _ZoneBody({required this.zone});

  final ZoneModel zone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final validation = ZoneValidationMetrics.forZone(ref, zone);
    final overview = ref.watch(currentZoneOverviewProvider).valueOrNull;
    final alternatives = _alternativeZoneList(
      zone,
      overview?.alternativeZones ?? const <ZoneModel>[],
    );
    final nearbyHotspots = _nearbyHotspotZones(
      zone,
      overview?.nearbyZones ?? const <ZoneModel>[],
    );
    final activityChips = _activityChips(zone);
    void openZone(ZoneModel candidate) =>
        _openRelatedZone(context, ref, candidate);
    final intelligence = _zoneIntelligenceCopy(zone);
    final lat = zone.boundary.isNotEmpty
        ? zone.boundary.map((p) => p[1]).reduce((a, b) => a + b) /
              zone.boundary.length
        : 0.0;
    final lng = zone.boundary.isNotEmpty
        ? zone.boundary.map((p) => p[0]).reduce((a, b) => a + b) /
              zone.boundary.length
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    zone.displayName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${lat.toStringAsFixed(4)}°N, ${lng.toStringAsFixed(4)}°E',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _colorFromHex(zone.borderColor).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${validation.totalSignals}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryText,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _InfoChip(
              icon: Icons.calendar_month_outlined,
              label: _crowdLabel(zone),
            ),
            const SizedBox(width: 10),
            _InfoChip(
              icon: Icons.folder_outlined,
              label: '${zone.popularityScore.toStringAsFixed(0)}%',
            ),
            const SizedBox(width: 10),
            _InfoIconChip(icon: Icons.notifications_none_rounded),
          ],
        ),
        if (zone.places.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionHeading(title: 'Places here'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: zone.places
                .map(
                  (place) => Chip(
                    label: Text('${place.displayName} · ${_titleize(place.placeType)}'),
                    backgroundColor: const Color(0xFFF1F5F9),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 20),
        _SectionHeading(title: 'Traveler mix'),
        const SizedBox(height: 8),
        _TravelerMixBar(zone: zone),
        const SizedBox(height: 20),
        _SectionHeading(title: 'Validation Dashboard'),
        const SizedBox(height: 10),
        _ZoneValidationDashboard(zone: zone),
        const SizedBox(height: 20),
        _SectionHeading(title: 'About this Zone'),
        const SizedBox(height: 8),
        Text(
          intelligence,
          style: const TextStyle(
            height: 1.4,
            color: Color(0xFF334155),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 20),
        _SectionHeading(title: 'Local vs Tourist Insight'),
        const SizedBox(height: 10),
        _LocalTouristInsightPanel(
          localsKnow: _localsKnow(zone),
          touristsMiss: _touristsMiss(zone),
          bestTime: zone.peakTimeLabel ?? 'Varies by day',
          safetyContext: _safetyContext(zone),
        ),
        const SizedBox(height: 20),
        _SectionHeading(title: 'Top Activities'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: activityChips
              .map((chip) => _IconLabel(icon: chip.$1, label: chip.$2))
              .toList(),
        ),
        const SizedBox(height: 20),
        _SectionHeading(title: 'Hotspots Nearby'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: nearbyHotspots
              .map(
                (candidate) => _ZoneLinkChip(
                  icon: _iconForZoneType(candidate.zoneType),
                  label: _titleize(candidate.displayName),
                  onTap: () => openZone(candidate),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        if (alternatives.isNotEmpty) ...[
          _SectionHeading(title: 'Nearby Alternatives'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: alternatives
                .map(
                  (candidate) => _ZoneLinkChip(
                    icon: Icons.alt_route_rounded,
                    label: _titleize(candidate.displayName),
                    onTap: () => openZone(candidate),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
        ],
        _SectionHeading(title: 'Transport'),
        const SizedBox(height: 10),
        const Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _IconLabel(icon: Icons.directions_bus_outlined, label: 'Bus'),
            _IconLabel(icon: Icons.local_taxi_outlined, label: 'Taxi'),
            _IconLabel(icon: Icons.local_parking_outlined, label: 'Parking'),
          ],
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 56,
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: ZoneDetailSheet._tealBg,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  icon: const Icon(Icons.near_me_outlined, size: 20),
                  label: const Text('Explore Zone'),
                  onPressed: () {
                    final router = GoRouter.of(context);
                    ref.read(selectedZoneProvider.notifier).state = zone;
                    Navigator.of(context).maybePop();
                    router.go(
                      '/trends?zoneId=${Uri.encodeComponent(zone.zoneId)}',
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.notifications_active_outlined,
                    color: Color(0xFF0F172A),
                  ),
                  onPressed: () {},
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _crowdLabel(ZoneModel zone) {
    if (zone.reportCount >= 40) return 'High crowd';
    if (zone.reportCount >= 20) return 'Moderate';
    return 'Quiet';
  }

  String _zoneIntelligenceCopy(ZoneModel zone) {
    final traveler = zone.travelerType.toLowerCase();
    final confidence = zone.confidenceScore.toStringAsFixed(0);
    final peak = zone.peakTimeLabel ?? 'variable peak times';
    final summary = zone.summary?.trim();
    if (summary != null && summary.isNotEmpty) {
      return '$summary This area is currently read as $traveler behavior with $confidence% confidence and $peak activity.';
    }
    final behavior = switch (zone.zoneType) {
      'food' || 'food_hotspot' =>
        'food behavior, dining movement, and activity combinations',
      'school' || 'student_area' =>
        'student movement, study hubs, budget meals, and campus-edge activity',
      'transport' || 'transport_zone' =>
        'commute pressure, pickup movement, food stops, and local errands',
      'commercial' || 'commercial_zone' =>
        'shopping, work, dining, and visible commercial movement',
      'tourist' || 'tourist_hotspot' =>
        'visitor movement, sightseeing, accessible food, and photo-stop behavior',
      _ => 'local movement, activity patterns, and zone-level behavior',
    };
    return 'This zone shows $traveler $behavior. Confidence is $confidence% based on recent community tags, with $peak activity.';
  }

  String _localsKnow(ZoneModel zone) {
    switch (zone.zoneType) {
      case 'food':
      case 'food_hotspot':
        return 'Local tags point to budget meals, repeat vendors, and side-street food movement.';
      case 'school':
      case 'student_area':
        return 'Students use this area for study stops, budget food, and campus-edge errands.';
      case 'transport':
      case 'transport_zone':
        return 'Locals treat this as a pickup, transfer, and quick-errand zone.';
      case 'commercial':
      case 'commercial_zone':
        return 'Local activity clusters around work breaks, shopping shortcuts, and evening dining.';
      case 'safety':
      case 'safety_concern':
        return 'Community tags suggest extra awareness around timing, lighting, and crowd conditions.';
      default:
        return 'Local contributions describe practical movement patterns, not just named places.';
    }
  }

  String _touristsMiss(ZoneModel zone) {
    switch (zone.zoneType) {
      case 'food':
      case 'food_hotspot':
        return 'Visitors may only see the landmark, while locals know when food activity is strongest.';
      case 'school':
      case 'student_area':
        return 'Tourists may miss that this is mostly student-paced and budget-oriented.';
      case 'transport':
      case 'transport_zone':
        return 'Visitors may underestimate transfer time, traffic pressure, and pickup behavior.';
      case 'commercial':
      case 'commercial_zone':
        return 'Tourists may miss quieter local routes behind malls and office clusters.';
      case 'safety':
      case 'safety_concern':
        return 'Visitors may not know which times or exits need extra caution.';
      default:
        return 'Tourists may miss local routines, shortcuts, and timing patterns behind the zone.';
    }
  }

  String _safetyContext(ZoneModel zone) {
    if (zone.zoneType == 'safety' ||
        zone.functionType == 'safety_concern' ||
        zone.liveStatus == 'caution_now') {
      return 'Recent safety-related signals are present. Stay in visible public areas and check current conditions.';
    }
    if (zone.crowdLevel >= 0.75) {
      return 'High activity can mean crowds, traffic, and slower movement. Keep belongings secure.';
    }
    return 'No strong safety warning in the current signals; still use normal city awareness.';
  }

  List<(IconData, String)> _activityChips(ZoneModel zone) {
    final source = zone.topActivities.isNotEmpty
        ? zone.topActivities
        : const ['sightseeing', 'shopping', 'dining', 'nightlife'];
    return source.take(6).map((activity) {
      final normalized = activity.toLowerCase();
      if (normalized.contains('food') ||
          normalized.contains('dining') ||
          normalized.contains('cafe')) {
        return (Icons.restaurant_outlined, 'Dining');
      }
      if (normalized.contains('night')) {
        return (Icons.nightlife_outlined, 'Nightlife');
      }
      if (normalized.contains('shop') || normalized.contains('market')) {
        return (Icons.shopping_bag_outlined, 'Shopping');
      }
      if (normalized.contains('transport') || normalized.contains('traffic')) {
        return (Icons.directions_bus_outlined, 'Transit');
      }
      if (normalized.contains('school') || normalized.contains('study')) {
        return (Icons.school_outlined, 'Student Spots');
      }
      if (normalized.contains('safety') || normalized.contains('issue')) {
        return (Icons.warning_amber_rounded, 'Safety Watch');
      }
      return (Icons.landscape, _titleize(activity));
    }).toList();
  }

  static const _hotspotFallbackNames = [
    'Escario',
    'Ayala Center Cebu',
    'Carbon Market Area',
    'Colon Basilica Heritage Zone',
  ];

  static const _alternativeFallbackNames = [
    'IT Park Business Zone',
    'Carbon Market Area',
    'Escario',
  ];

  void _openRelatedZone(
    BuildContext context,
    WidgetRef ref,
    ZoneModel candidate,
  ) {
    ref.read(zoneValidationLiveProvider.notifier).state = null;
    final enriched = enrichZoneForAreaCard(candidate);
    final focus = LatLng(enriched.centroidLat, enriched.centroidLng);
    ref.read(selectedZoneProvider.notifier).state = enriched;
    ref.read(zoneLookupLocationProvider.notifier).state = focus;
    ref.read(exploreFocusLocationProvider.notifier).state = focus;
    ref.invalidate(currentZoneOverviewProvider);
    ref.invalidate(selectedZoneDetailProvider);
  }

  List<ZoneModel> _nearbyHotspotZones(ZoneModel zone, List<ZoneModel> nearby) {
    final fromApi =
        nearby.where((z) => z.zoneId != zone.zoneId).take(4).toList();
    if (fromApi.isNotEmpty) return fromApi;
    return _zonesFromCatalogNames(_hotspotFallbackNames, excludeZoneId: zone.zoneId);
  }

  List<ZoneModel> _alternativeZoneList(
    ZoneModel zone,
    List<ZoneModel> alternatives,
  ) {
    final fromApi =
        alternatives.where((z) => z.zoneId != zone.zoneId).take(4).toList();
    if (fromApi.isNotEmpty) return fromApi;
    return _zonesFromCatalogNames(
      _alternativeFallbackNames,
      excludeZoneId: zone.zoneId,
    );
  }

  List<ZoneModel> _zonesFromCatalogNames(
    List<String> names, {
    required String excludeZoneId,
  }) {
    final out = <ZoneModel>[];
    final seen = <String>{};
    for (final name in names) {
      final entry = ZoneCatalog.lookup(name);
      if (entry == null) continue;
      final model = enrichZoneForAreaCard(zoneModelFromCatalogEntry(entry));
      if (model.zoneId == excludeZoneId || seen.contains(model.zoneId)) {
        continue;
      }
      seen.add(model.zoneId);
      out.add(model);
    }
    return out;
  }

  IconData _iconForZoneType(String zoneType) {
    final type = zoneType.toLowerCase();
    if (type.contains('food')) return Icons.restaurant_outlined;
    if (type.contains('school') || type.contains('student')) {
      return Icons.school_outlined;
    }
    if (type.contains('transport')) return Icons.directions_bus_outlined;
    if (type.contains('commercial')) return Icons.storefront_outlined;
    if (type.contains('safety')) return Icons.warning_amber_rounded;
    return Icons.location_on_outlined;
  }

  String _titleize(String value) {
    final text = value.trim();
    if (text.isEmpty) return 'Hotspot';
    final normalized = text
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    return normalized
        .split(' ')
        .map((part) {
          if (part.isEmpty) return part;
          return '${part[0].toUpperCase()}${part.substring(1)}';
        })
        .join(' ');
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: Color(0xFF0F172A),
      ),
    );
  }
}

class _ZoneValidationDashboard extends ConsumerWidget {
  const _ZoneValidationDashboard({required this.zone});

  final ZoneModel zone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ZoneValidationMetrics.forZone(ref, zone);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _ValidationTile(
                label: 'Total signals',
                value: '${metrics.totalSignals}',
                icon: Icons.tag_rounded,
              ),
              const SizedBox(width: 10),
              _ValidationTile(
                label: 'Matching',
                value: '${metrics.matchingSignals}',
                icon: Icons.how_to_reg_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _ValidationTile(
                label: 'Confidence',
                value: '${metrics.confidence.toStringAsFixed(0)}%',
                icon: Icons.verified_user_outlined,
              ),
              const SizedBox(width: 10),
              _ValidationTile(
                label: 'Updated',
                value: metrics.lastUpdated,
                icon: Icons.schedule_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.rule_folder_outlined,
                  size: 18,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Top agreed category: ${metrics.topCategory}',
                    style: const TextStyle(
                      color: Color(0xFF334155),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ValidationTile extends StatelessWidget {
  const _ValidationTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: AppColors.accent),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalTouristInsightPanel extends StatelessWidget {
  const _LocalTouristInsightPanel({
    required this.localsKnow,
    required this.touristsMiss,
    required this.bestTime,
    required this.safetyContext,
  });

  final String localsKnow;
  final String touristsMiss;
  final String bestTime;
  final String safetyContext;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _InsightRow(
          icon: Icons.groups_rounded,
          title: 'What locals know',
          body: localsKnow,
          color: AppColors.localAccent,
        ),
        const SizedBox(height: 10),
        _InsightRow(
          icon: Icons.travel_explore_rounded,
          title: 'What tourists usually miss',
          body: touristsMiss,
          color: AppColors.touristAccent,
        ),
        const SizedBox(height: 10),
        _InsightRow(
          icon: Icons.access_time_rounded,
          title: 'Best time to visit',
          body: bestTime,
          color: AppColors.accent,
        ),
        const SizedBox(height: 10),
        _InsightRow(
          icon: Icons.shield_outlined,
          title: 'Safety/context note',
          body: safetyContext,
          color: AppColors.safetyAccent,
        ),
      ],
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: ZoneDetailSheet._chipBg,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: ZoneDetailSheet._chipText),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: ZoneDetailSheet._chipText,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoIconChip extends StatelessWidget {
  const _InfoIconChip({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: ZoneDetailSheet._chipBg,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.notifications_none_rounded,
        size: 18,
        color: ZoneDetailSheet._chipText,
      ),
    );
  }
}

class _TravelerMixBar extends StatelessWidget {
  const _TravelerMixBar({required this.zone});

  final ZoneModel zone;

  @override
  Widget build(BuildContext context) {
    final locals = switch (zone.travelerType.toLowerCase()) {
      'local' => 0.78,
      'international' => 0.18,
      _ => 0.52,
    };
    final intl = 1 - locals;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                Expanded(
                  flex: (locals * 100).round(),
                  child: Container(color: const Color(0xFF22C55E)),
                ),
                Expanded(
                  flex: (intl * 100).round(),
                  child: Container(color: const Color(0xFF3B82F6)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Locals ${(locals * 100).round()}%',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'International ${(intl * 100).round()}%',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _IconLabel extends StatelessWidget {
  const _IconLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF0F172A)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoneLinkChip extends StatelessWidget {
  const _ZoneLinkChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: AppColors.accent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Color(0xFF64748B),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
