import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/colors.dart';
import '../../../shared/providers/app_providers.dart';

class LayersScreen extends ConsumerWidget {
  const LayersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(layerSettingsProvider);
    final notifier = ref.read(layerSettingsProvider.notifier);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE0F2FE), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            children: [
              const _Header(),
              const SizedBox(height: 18),
              _LayerTile(
                icon: Icons.people_alt_outlined,
                title: 'Traveler layer',
                subtitle: 'Fill color: local, international, or mixed',
                color: AppColors.travelerInternational,
                value: settings.showTravelerLayer,
                onChanged: (value) => notifier.state = settings.copyWith(
                  showTravelerLayer: value,
                ),
              ),
              _LayerTile(
                icon: Icons.category_outlined,
                title: 'Place type overlay',
                subtitle:
                    'Hex outlines from tagged cells (school, food, commercial)',
                color: AppColors.accent,
                value: settings.showFunctionalOverlay,
                onChanged: (value) => notifier.state = settings.copyWith(
                  showFunctionalOverlay: value,
                ),
              ),
              _LayerTile(
                icon: Icons.local_fire_department_outlined,
                title: 'Heatmap',
                subtitle: 'Density preview for recent activity',
                color: AppColors.alert,
                value: settings.showHeatmap,
                onChanged: (value) =>
                    notifier.state = settings.copyWith(showHeatmap: value),
              ),
              _LayerTile(
                icon: Icons.traffic_outlined,
                title: 'Traffic',
                subtitle: 'Mobility pressure placeholder',
                color: AppColors.zoneTransport,
                value: settings.showTraffic,
                onChanged: (value) =>
                    notifier.state = settings.copyWith(showTraffic: value),
              ),
              _LayerTile(
                icon: Icons.forum_outlined,
                title: 'Feed markers',
                subtitle: 'Community report hints inside visible hexes',
                color: AppColors.travelerMixed,
                value: settings.showFeedMarkers,
                onChanged: (value) =>
                    notifier.state = settings.copyWith(showFeedMarkers: value),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Layer opacity',
                          style: TextStyle(
                            color: AppColors.primaryText,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${(settings.opacity * 100).round()}%',
                          style: const TextStyle(
                            color: AppColors.primaryAction,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Slider(
                      value: settings.opacity,
                      min: 0.1,
                      max: 1,
                      divisions: 9,
                      onChanged: (value) =>
                          notifier.state = settings.copyWith(opacity: value),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.mapInk,
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.layers_rounded, color: Colors.white, size: 32),
          SizedBox(height: 16),
          Text(
            'Layer Stack',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Fill color = who (local / mixed / international). Outlines = what (school, food, transport).',
            style: TextStyle(
              color: Color(0xFFBAE6FD),
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LayerTile extends StatelessWidget {
  const _LayerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: value ? color.withValues(alpha: 0.36) : AppColors.border,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: value ? 0.16 : 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
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
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
