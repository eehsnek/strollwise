import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../../shared/models/report.dart';
import '../../../shared/models/zone.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/traveler_gradient.dart';
import '../../../shared/widgets/zone_traveler_mix_bar.dart';
import '../../../shared/zone_place_ui.dart';
import '../../../shared/zone_validation_metrics.dart';
import 'feed_zone_copy.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  static const _tealBg = Color(0xFF00628A);

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  static const _filters = [
    'Following',
    'Nearby',
    'Trending',
    'Food',
    'Crowd',
    'Safety',
  ];

  static const _backgroundRefreshInterval = Duration(seconds: 50);

  Timer? _backgroundRefresh;

  @override
  void initState() {
    super.initState();
    _backgroundRefresh = Timer.periodic(_backgroundRefreshInterval, (_) {
      if (!mounted) return;
      ref.invalidate(zoneFeedProvider);
      ref.invalidate(feedProvider);
    });
  }

  @override
  void dispose() {
    _backgroundRefresh?.cancel();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      ref.refresh(zoneFeedProvider.future),
      ref.refresh(feedProvider.future),
    ]);
  }

  void _openZoneOnExplore(ZoneModel zone) {
    ref.read(zoneValidationLiveProvider.notifier).state = null;
    final enriched = enrichZoneForAreaCard(zone);
    final focus = LatLng(enriched.centroidLat, enriched.centroidLng);
    ref.read(selectedZoneProvider.notifier).state = enriched;
    ref.read(zoneLookupLocationProvider.notifier).state = focus;
    ref.read(exploreFocusLocationProvider.notifier).state = focus;
    ref.invalidate(selectedZoneDetailProvider);
    context.go('/explore');
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(zoneFeedProvider);
    final activity = ref.watch(feedProvider);
    final selectedChip = ref.watch(zoneFeedChipProvider);
    final zoneDataNotice = ref.watch(zoneDataNoticeProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth > 720
              ? 680.0
              : constraints.maxWidth;
          return SafeArea(
            bottom: false,
            child: Center(
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FeedHeader(),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Live tags and ranked zones around Cebu',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _FeedFilterRow(
                      selectedLabel: selectedChip,
                      labels: _filters,
                      onSelected: (label) {
                        ref.read(zoneFeedChipProvider.notifier).state = label;
                      },
                    ),
                    if (zoneDataNotice != null) ...[
                      const SizedBox(height: 8),
                      _FeedCacheNotice(message: zoneDataNotice),
                    ],
                    const SizedBox(height: 8),
                    Expanded(
                      child: feed.when(
                        data: (zones) {
                          return RefreshIndicator(
                            onRefresh: _refreshAll,
                            child: zones.isEmpty
                                ? ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.only(top: 24),
                                    children: [
                                      _RecentActivityStrip(
                                        activity: activity,
                                      ),
                                      const SizedBox(height: 24),
                                      const EmptyStateCard(
                                        message:
                                            'No zones match this filter yet. Pull to refresh.',
                                      ),
                                    ],
                                  )
                                : CustomScrollView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    slivers: [
                                      SliverToBoxAdapter(
                                        child: _RecentActivityStrip(
                                          activity: activity,
                                        ),
                                      ),
                                      SliverPadding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          8,
                                          16,
                                          24,
                                        ),
                                        sliver: SliverList.separated(
                                          itemCount: zones.length,
                                          separatorBuilder: (context, index) =>
                                              const SizedBox(height: 12),
                                          itemBuilder: (context, index) {
                                            final zone = zones[index];
                                            if (index == 0) {
                                              return _FeaturedZoneFeedCard(
                                                zone: zone,
                                                seed: index,
                                                onTap: () =>
                                                    _openZoneOnExplore(zone),
                                              );
                                            }
                                            return _ZoneFeedCard(
                                              zone: zone,
                                              seed: index,
                                              onTap: () =>
                                                  _openZoneOnExplore(zone),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                          );
                        },
                        loading: LoadingSkeleton.new,
                        error: (error, _) => RefreshIndicator(
                          onRefresh: _refreshAll,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(top: 48),
                            children: [
                              EmptyStateCard(message: error.toString()),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          const Text(
            'Feed',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const Spacer(),
          _IconCircle(
            icon: Icons.explore_outlined,
            onTap: () => context.go('/explore'),
          ),
        ],
      ),
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, size: 20, color: const Color(0xFF0F172A)),
        ),
      ),
    );
  }
}

class _RecentActivityStrip extends StatelessWidget {
  const _RecentActivityStrip({required this.activity});

  final AsyncValue<List<ReportModel>> activity;

  @override
  Widget build(BuildContext context) {
    return activity.when(
      data: (reports) {
        if (reports.isEmpty) return const SizedBox.shrink();
        final recent = reports.take(12).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Recent activity',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
            SizedBox(
              height: 108,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: recent.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return _ActivityCard(report: recent[index]);
                },
              ),
            ),
            const SizedBox(height: 4),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: SizedBox(
          height: 88,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (error, stack) => const SizedBox.shrink(),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.report});

  final ReportModel report;

  @override
  Widget build(BuildContext context) {
    final label = _reportLabel(report);
    final time = _timeAgo(report.createdAt);
    final accent = _categoryColor(report.category);

    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_categoryIcon(report.category), size: 18, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _titleize(report.category),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
                height: 1.3,
              ),
            ),
          ),
          Text(
            time,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  static String _reportLabel(ReportModel report) {
    final note = report.note?.trim();
    if (note != null && note.isNotEmpty) return note;
    if (report.tags.isNotEmpty) {
      return report.tags.first.replaceAll('_', ' ');
    }
    return 'New community tag';
  }

  static IconData _categoryIcon(String category) {
    return switch (category.toLowerCase()) {
      'food' => Icons.restaurant_outlined,
      'school' => Icons.school_outlined,
      'transport' => Icons.directions_bus_outlined,
      _ => Icons.place_outlined,
    };
  }

  static Color _categoryColor(String category) {
    return switch (category.toLowerCase()) {
      'food' => const Color(0xFF34765B),
      'school' => const Color(0xFF8060E8),
      'transport' => const Color(0xFF65B9BE),
      _ => FeedScreen._tealBg,
    };
  }

  static String _titleize(String value) {
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
        .join(' ');
  }

  static String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return 'Earlier';
  }
}

class _FeedCacheNotice extends StatelessWidget {
  const _FeedCacheNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8EE),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF0A127)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.offline_bolt_rounded,
              size: 17,
              color: Color(0xFFB7791F),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedFilterRow extends StatelessWidget {
  const _FeedFilterRow({
    required this.selectedLabel,
    required this.labels,
    required this.onSelected,
  });

  final String selectedLabel;
  final List<String> labels;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            _FilterPill(
              label: labels[i],
              selected: labels[i] == selectedLabel,
              onTap: () => onSelected(labels[i]),
            ),
            if (i != labels.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    this.selected = false,
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
            color: selected ? FeedScreen._tealBg : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? FeedScreen._tealBg : const Color(0xFFE2E8F0),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : const Color(0xFF334155),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturedZoneFeedCard extends StatelessWidget {
  const _FeaturedZoneFeedCard({
    required this.zone,
    required this.seed,
    required this.onTap,
  });

  final ZoneModel zone;
  final int seed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _ZoneFeedCard.parseAccent(zone);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.14),
                Colors.white,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F172A),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(24),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                child: _ZoneFeedCardBody(
                  zone: zone,
                  seed: seed,
                  featured: true,
                  onViewMap: onTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoneFeedCard extends StatelessWidget {
  const _ZoneFeedCard({
    required this.zone,
    required this.seed,
    required this.onTap,
  });

  final ZoneModel zone;
  final int seed;
  final VoidCallback onTap;

  static Color parseAccent(ZoneModel zone) {
    var h = zone.borderColor.replaceFirst('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final accent = parseAccent(zone);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D0F172A),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: _ZoneFeedCardBody(
            zone: zone,
            seed: seed,
            accent: accent,
            onViewMap: onTap,
          ),
        ),
      ),
    );
  }
}

class _ZoneFeedCardBody extends StatefulWidget {
  const _ZoneFeedCardBody({
    required this.zone,
    required this.seed,
    required this.onViewMap,
    this.featured = false,
    this.accent,
  });

  final ZoneModel zone;
  final int seed;
  final VoidCallback onViewMap;
  final bool featured;
  final Color? accent;

  @override
  State<_ZoneFeedCardBody> createState() => _ZoneFeedCardBodyState();
}

class _ZoneFeedCardBodyState extends State<_ZoneFeedCardBody> {
  bool _showDetail = false;

  @override
  Widget build(BuildContext context) {
    final zone = widget.zone;
    final accent =
        widget.accent ?? _ZoneFeedCard.parseAccent(zone);
    final headline = feedZoneHeadline(zone);
    final detail = feedZoneDetailLine(zone);
    final chips = feedActivityChips(zone);
    final crowd = feedCrowdLabel(zone);
    final showStar = feedShowConfidenceBadge(zone);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: widget.featured ? 52 : 44,
              height: widget.featured ? 52 : 44,
              child: CustomPaint(
                painter: _MiniHexPainter(color: accent, seed: widget.seed),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    zoneDisplayTitle(zone),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                      fontSize: widget.featured ? 16 : 15,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    zoneMapSubtitle(zone),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (showStar)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '★ ${zone.confidenceScore.round()}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          headline,
          style: TextStyle(
            fontSize: widget.featured ? 14 : 13,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 10),
        ZoneTravelerMixBar(zone: zone, height: widget.featured ? 10 : 8),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: chips
              .map(
                (label) => _ActivityChip(label: label, accent: accent),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _MetaChip(icon: Icons.sensors_rounded, label: crowd),
            const SizedBox(width: 6),
            _MetaChip(
              icon: Icons.flag_outlined,
              label: '${zone.reportCount} tags',
            ),
          ],
        ),
        if (detail != null) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _showDetail = !_showDetail),
            child: Text(
              _showDetail ? detail : 'Tap for zone summary',
              maxLines: _showDetail ? 4 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _showDetail
                    ? const Color(0xFF475569)
                    : const Color(0xFF94A3B8),
                height: 1.35,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.onViewMap,
            icon: const Icon(Icons.map_outlined, size: 16),
            label: const Text('View on map'),
            style: TextButton.styleFrom(
              foregroundColor: FeedScreen._tealBg,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityChip extends StatelessWidget {
  const _ActivityChip({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF64748B)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniHexPainter extends CustomPainter {
  _MiniHexPainter({required this.color, required this.seed});

  final Color color;
  final int seed;

  void _hex(Canvas canvas, Offset center, double r, Paint fill, Paint stroke) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 3 * i - math.pi / 2;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 4.2;
    final hexWidth = r * math.sqrt(3);
    final hexHeight = r * 1.5;

    final lightFill = Paint()..color = color.withValues(alpha: 0.18);
    final lightStroke = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final mainFill = Paint()..color = color.withValues(alpha: 0.9);
    final mainStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final neighbors = [
      Offset(-hexWidth, 0),
      Offset(hexWidth, 0),
      Offset(-hexWidth / 2, -hexHeight),
      Offset(hexWidth / 2, -hexHeight),
      Offset(-hexWidth / 2, hexHeight),
      Offset(hexWidth / 2, hexHeight),
    ];
    for (final offset in neighbors) {
      _hex(canvas, center + offset, r * 0.58, lightFill, lightStroke);
    }
    _hex(canvas, center, r * 0.7, mainFill, mainStroke);
  }

  @override
  bool shouldRepaint(covariant _MiniHexPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.seed != seed;
}
