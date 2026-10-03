import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../app/theme/colors.dart';
import '../../../shared/models/zone.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/traveler_gradient.dart';
import '../../../shared/zone_place_ui.dart';

class ExploreAreaInsightCard extends ConsumerWidget {
  const ExploreAreaInsightCard({
    required this.placeTitle,
    required this.onClose,
    super.key,
  });

  final String placeTitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(currentZoneOverviewProvider);
    final focus = ref.watch(mapSearchFocusProvider);

    return overview.when(
      loading: () => _Shell(
        onClose: onClose,
        child: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Reading area behavior near $placeTitle…',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.secondaryText,
                ),
              ),
            ),
          ],
        ),
      ),
      error: (_, _) => _buildContent(ref, focus, placeTitle, null, onClose),
      data: (data) => _buildContent(
        ref,
        focus,
        placeTitle,
        data?.currentZone,
        onClose,
      ),
    );
  }

  Widget _buildContent(
    WidgetRef ref,
    LatLng? focus,
    String placeTitle,
    ZoneModel? zone,
    VoidCallback onClose,
  ) {
    final ratio = zone != null
        ? TravelerGradient.localRatioForZone(zone)
        : (focus != null
            ? ZoneCatalog.lookup(placeTitle)?.defaultLocalRatio ?? 0.5
            : 0.5);
    final color = TravelerGradient.colorForRatio(ratio);
    final title = zone != null ? zoneDisplayTitle(zone) : placeTitle;
    final subtitle = zone != null
        ? '${TravelerGradient.dominanceLabel(ratio)} · ${zoneMapSubtitle(zone)}'
        : TravelerGradient.dominanceLabel(ratio);

    return _Shell(
      onClose: onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.mutedText,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          if (zone != null && zone.summary != null && zone.summary!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                zone.summary!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else if (zone == null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'No tagged zone here yet. Pan around or add a tag to build area intelligence.',
                style: TextStyle(
                  color: AppColors.mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.onClose, required this.child});

  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: child),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 20),
            color: AppColors.mutedText,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
