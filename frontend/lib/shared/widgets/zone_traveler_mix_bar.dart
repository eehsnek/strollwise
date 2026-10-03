import 'package:flutter/material.dart';

import '../models/zone.dart';
import '../traveler_gradient.dart';

/// Compact local ↔ visitor mix strip for cards and feed rows.
class ZoneTravelerMixBar extends StatelessWidget {
  const ZoneTravelerMixBar({
    required this.zone,
    this.height = 8,
    super.key,
  });

  final ZoneModel zone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final localRatio = TravelerGradient.localRatioForZone(zone);
    final localPct = (localRatio * 100).round().clamp(0, 100);
    final intlPct = 100 - localPct;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                if (localPct > 0)
                  Expanded(
                    flex: localPct,
                    child: const ColoredBox(color: TravelerGradient.local),
                  ),
                if (intlPct > 0)
                  Expanded(
                    flex: intlPct,
                    child: const ColoredBox(color: TravelerGradient.international),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Locals $localPct%',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Visitors $intlPct%',
              style: const TextStyle(
                fontSize: 11,
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
