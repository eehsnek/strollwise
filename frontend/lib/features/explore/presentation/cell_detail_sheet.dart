import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../app/theme/colors.dart';
import '../../../shared/models/cell.dart';
import '../../../shared/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/traveler_gradient.dart';

class CellDetailSheet extends ConsumerWidget {
  const CellDetailSheet({required this.cell, super.key});

  final CellModel cell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = cell.placeName ?? _titleFromFunction(cell.functionType);
    return DraggableScrollableSheet(
      initialChildSize: 0.36,
      minChildSize: 0.28,
      maxChildSize: 0.55,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.borderStrong,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: TravelerGradient.colorForCell(cell),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${cell.reportCount} tags · ${TravelerGradient.dominanceLabel(TravelerGradient.localRatioForCell(cell))} · ${cell.confidenceScore.round()}% confidence',
                      style: const TextStyle(
                        color: AppColors.mutedText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (cell.dominantCategory != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Top vibe: ${cell.dominantCategory}',
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  ref.read(tagSubmissionPinLocationProvider.notifier).state =
                      LatLng(cell.centroidLat, cell.centroidLng);
                  Navigator.of(context).pop();
                  context.go('/add-tag');
                },
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add tag here'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryAction,
                  foregroundColor: AppColors.mapInk,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _saveVisit(context, ref, title),
                icon: const Icon(Icons.hiking_rounded),
                label: const Text('Save to my visit map'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveVisit(
    BuildContext context,
    WidgetRef ref,
    String title,
  ) async {
    final token = ref.read(authTokenProvider);
    if (token == null || token == 'demo-token-local') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Sign in to save private visit pins on your map.'),
        ),
      );
      return;
    }
    try {
      await ref.read(dioProvider).post(
        '/reports/my-visit-pins',
        data: {
          'latitude': cell.centroidLat,
          'longitude': cell.centroidLng,
          if (title.isNotEmpty) 'label': title,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      ref.invalidate(ownVisitPinsProvider);
      ref.invalidate(ownVisitHistoryProvider);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Saved to your private visit map.'),
        ),
      );
    } on DioException catch (e) {
      if (!context.mounted) return;
      final detail = e.response?.data;
      final message = detail is Map && detail['detail'] != null
          ? detail['detail'].toString()
          : 'Could not save visit pin.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
    }
  }

  String _titleFromFunction(String functionType) {
    return functionType
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
