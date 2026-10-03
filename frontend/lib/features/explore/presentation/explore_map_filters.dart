import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/colors.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/traveler_gradient.dart';

/// Compact filter entry on Explore; full controls open in a bottom sheet.
class ExploreMapFilterBar extends ConsumerWidget {
  const ExploreMapFilterBar({
    super.key,
    required this.enabledLayerKeys,
    required this.onToggleLayer,
  });

  final Set<String> enabledLayerKeys;
  final ValueChanged<String> onToggleLayer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traveler = ref.watch(activeTravelerMixFilterProvider);
    final placeType = ref.watch(activePlaceTypeFilterProvider);
    final activeCount =
        (traveler != null ? 1 : 0) + (placeType != null ? 1 : 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Material(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _openFiltersSheet(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: activeCount > 0
                        ? AppColors.primaryAction
                        : AppColors.border,
                    width: activeCount > 0 ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.tune_rounded,
                      size: 18,
                      color: AppColors.primaryText,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      activeCount > 0 ? 'Filters ($activeCount)' : 'Filters',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (traveler != null)
                    _ActiveFilterChip(
                      label: _travelerLabel(traveler),
                      color: TravelerGradient.colorForRatio(
                        TravelerGradient.localRatioFromMix(traveler),
                      ),
                      onClear: () {
                        ref.read(activeTravelerMixFilterProvider.notifier).state =
                            null;
                      },
                    ),
                  if (placeType != null)
                    _ActiveFilterChip(
                      label: _placeLabel(placeType),
                      color: AppColors.mutedText,
                      onClear: () {
                        ref.read(activePlaceTypeFilterProvider.notifier).state =
                            null;
                      },
                    ),
                  if (activeCount == 0)
                    const Padding(
                      padding: EdgeInsets.only(left: 4, top: 8),
                      child: Text(
                        'Map colors show local ↔ visitor mix',
                        style: TextStyle(
                          color: AppColors.mutedText,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openFiltersSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ExploreFiltersSheet(
        enabledLayerKeys: enabledLayerKeys,
        onToggleLayer: onToggleLayer,
      ),
    );
  }

  static String _travelerLabel(String value) => switch (value) {
        'local' => 'Local',
        'international' => 'International',
        _ => 'Mixed',
      };

  static String _placeLabel(String value) => switch (value) {
        'school' => 'School',
        'food' => 'Food',
        'transport' => 'Transport',
        'commercial' => 'Commercial',
        _ => value,
      };
}

class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({
    required this.label,
    required this.color,
    required this.onClear,
  });

  final String label;
  final Color color;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onClear,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.close_rounded, size: 14, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExploreFiltersSheet extends ConsumerWidget {
  const _ExploreFiltersSheet({
    required this.enabledLayerKeys,
    required this.onToggleLayer,
  });

  final Set<String> enabledLayerKeys;
  final ValueChanged<String> onToggleLayer;

  static const _zoneLayerItems = <({String key, String label, Color color})>[
    (key: 'local', label: 'Local', color: AppColors.localAccent),
    (key: 'international', label: 'International', color: AppColors.touristAccent),
    (key: 'mixed', label: 'Mixed', color: AppColors.mixedAccent),
    (key: 'commercial', label: 'Commercial', color: AppColors.commercialAccent),
    (key: 'food', label: 'Food', color: AppColors.foodAccent),
    (key: 'transport', label: 'Transport', color: AppColors.transportAccent),
    (key: 'school', label: 'School', color: AppColors.studentAccent),
    (key: 'tourist', label: 'Tourist', color: AppColors.touristAccent),
    (key: 'safety', label: 'Safety', color: AppColors.safetyAccent),
    (key: 'hotel', label: 'Hotel', color: AppColors.zoneCommercial),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traveler = ref.watch(activeTravelerMixFilterProvider);
    final placeType = ref.watch(activePlaceTypeFilterProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                'Map filters',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryText,
                ),
              ),
              const Spacer(),
              if (traveler != null || placeType != null)
                TextButton(
                  onPressed: () {
                    ref.read(activeTravelerMixFilterProvider.notifier).state =
                        null;
                    ref.read(activePlaceTypeFilterProvider.notifier).state =
                        null;
                  },
                  child: const Text('Clear all'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const TravelerBehaviorGradientLegend(),
          const SizedBox(height: 16),
          const Text(
            'Who uses this area',
            style: TextStyle(
              color: AppColors.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          _FilterChipWrap(
            chips: [
              _FilterChipSpec(
                label: 'Local',
                value: 'local',
                icon: Icons.groups_rounded,
                accent: AppColors.travelerLocal,
                fill: AppColors.localFill,
              ),
              _FilterChipSpec(
                label: 'Mixed',
                value: 'mixed',
                icon: Icons.hub_outlined,
                accent: TravelerGradient.midpoint,
                fill: TravelerGradient.fillForRatio(0.5),
              ),
              _FilterChipSpec(
                label: 'International',
                value: 'international',
                icon: Icons.flight_takeoff_rounded,
                accent: AppColors.travelerInternational,
                fill: AppColors.touristFill,
              ),
            ],
            selected: traveler,
            onSelected: (value) {
              ref.read(activeTravelerMixFilterProvider.notifier).state =
                  traveler == value ? null : value;
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'What this place is',
            style: TextStyle(
              color: AppColors.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          _FilterChipWrap(
            chips: const [
              _FilterChipSpec(
                label: 'School',
                value: 'school',
                icon: Icons.school_outlined,
                accent: AppColors.zoneSchool,
                fill: Color(0xFFF0E4FF),
              ),
              _FilterChipSpec(
                label: 'Food',
                value: 'food',
                icon: Icons.restaurant_outlined,
                accent: AppColors.zoneFood,
                fill: AppColors.foodFill,
              ),
              _FilterChipSpec(
                label: 'Transport',
                value: 'transport',
                icon: Icons.directions_bus_outlined,
                accent: AppColors.zoneTransport,
                fill: AppColors.transportFill,
              ),
              _FilterChipSpec(
                label: 'Commercial',
                value: 'commercial',
                icon: Icons.business_outlined,
                accent: AppColors.zoneCommercial,
                fill: AppColors.commercialFill,
              ),
            ],
            selected: placeType,
            onSelected: (value) {
              ref.read(activePlaceTypeFilterProvider.notifier).state =
                  placeType == value ? null : value;
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'Show on map',
            style: TextStyle(
              color: AppColors.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in _zoneLayerItems)
                FilterChip(
                  selected: enabledLayerKeys.contains(item.key),
                  onSelected: (_) => onToggleLayer(item.key),
                  label: Text(item.label),
                  side: BorderSide(
                    color: enabledLayerKeys.contains(item.key)
                        ? item.color
                        : AppColors.border,
                  ),
                  selectedColor: item.color.withValues(alpha: 0.12),
                  checkmarkColor: item.color,
                  labelStyle: TextStyle(
                    color: enabledLayerKeys.contains(item.key)
                        ? item.color
                        : AppColors.secondaryText,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryAction,
                foregroundColor: AppColors.mapInk,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipSpec {
  const _FilterChipSpec({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.fill,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final Color fill;
}

class _FilterChipWrap extends StatelessWidget {
  const _FilterChipWrap({
    required this.chips,
    required this.selected,
    required this.onSelected,
  });

  final List<_FilterChipSpec> chips;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final chip in chips)
          _buildChip(chip, selected == chip.value),
      ],
    );
  }

  Widget _buildChip(_FilterChipSpec chip, bool isSelected) {
    return Material(
      color: isSelected
          ? chip.fill.withValues(alpha: 0.55)
          : AppColors.background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onSelected(chip.value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSelected ? chip.accent : AppColors.border,
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                chip.icon,
                size: 16,
                color: isSelected ? chip.accent : AppColors.secondaryText,
              ),
              const SizedBox(width: 6),
              Text(
                chip.label,
                style: TextStyle(
                  color: isSelected ? chip.accent : AppColors.primaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kept for imports that still reference the old name.
typedef ExploreMapFilters = ExploreMapFilterBar;
