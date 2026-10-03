import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/colors.dart';
import '../../../shared/maps/google_maps_launcher.dart';
import '../../../shared/models/place_recommendation.dart';
import '../../../shared/network/api_client.dart';

/// Loads curated top places for a vibe + area (no external API).
final placeRecommendationsProvider = FutureProvider.autoDispose
    .family<List<PlaceRecommendation>, PlaceRecommendationsQuery>((
  ref,
  query,
) async {
  final dio = ref.watch(dioProvider);
  try {
    final response = await dio.get<List<dynamic>>(
      '/places/recommendations',
      queryParameters: query.toQueryParams(),
    );
    final list = response.data;
    if (list == null) return const [];
    return list
        .whereType<Map>()
        .map(
          (e) => PlaceRecommendation.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList(growable: false);
  } on DioException {
    return const [];
  } on FormatException {
    return const [];
  } on TypeError {
    return const [];
  }
});

class PlaceRecommendationsQuery {
  const PlaceRecommendationsQuery({
    required this.lat,
    required this.lng,
    required this.vibe,
    required this.areaLabel,
  });

  final double lat;
  final double lng;
  final String vibe;
  final String areaLabel;

  Map<String, dynamic> toQueryParams() => {
        'lat': lat,
        'lng': lng,
        'vibe': vibe,
        'area_label': areaLabel,
        'limit': 4,
      };

  @override
  bool operator ==(Object other) {
    return other is PlaceRecommendationsQuery &&
        other.lat == lat &&
        other.lng == lng &&
        other.vibe == vibe &&
        other.areaLabel == areaLabel;
  }

  @override
  int get hashCode => Object.hash(lat, lng, vibe, areaLabel);
}

class PlacesToGoSheet extends ConsumerWidget {
  const PlacesToGoSheet({
    super.key,
    required this.vibeTitle,
    required this.vibeKey,
    required this.areaLabel,
    required this.lat,
    required this.lng,
  });

  final String vibeTitle;
  final String vibeKey;
  final String areaLabel;
  final double lat;
  final double lng;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = PlaceRecommendationsQuery(
      lat: lat,
      lng: lng,
      vibe: vibeKey,
      areaLabel: areaLabel,
    );
    final async = ref.watch(placeRecommendationsProvider(query));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                vibeTitle,
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Popular places near $areaLabel — tap one for directions in Google Maps.',
                style: const TextStyle(
                  color: AppColors.mutedText,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: async.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, _) => _EmptyState(
                    message:
                        'Could not load places. Check your connection and try again.',
                  ),
                  data: (places) {
                    if (places.isEmpty) {
                      return const _EmptyState(
                        message: 'No places found for this vibe in this area.',
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: places.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final place = places[index];
                        return _PlaceRecommendationTile(
                          place: place,
                          rank: index + 1,
                          onNavigate: () => _openNavigation(context, place),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openNavigation(
    BuildContext context,
    PlaceRecommendation place,
  ) async {
    if (place.mapsUri != null && place.mapsUri!.trim().isNotEmpty) {
      final uri = Uri.tryParse(place.mapsUri!);
      if (uri != null &&
          await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return;
      }
    }
    final opened = await GoogleMapsLauncher.openDirections(
      latitude: place.latitude,
      longitude: place.longitude,
      address: googleMapsDestinationAddress(displayName: place.name),
    );
    if (!context.mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open Google Maps. Install the app or try again.',
          ),
        ),
      );
    }
  }
}

class _PlaceRecommendationTile extends StatelessWidget {
  const _PlaceRecommendationTile({
    required this.place,
    required this.rank,
    required this.onNavigate,
  });

  final PlaceRecommendation place;
  final int rank;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final rating = place.rating;
    final reviews = place.reviewCount;
    const sourceLabel = 'Popular pick';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onNavigate,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryAction.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: AppColors.mapInk,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryText,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (rating != null)
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          if (reviews > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '($reviews)',
                              style: const TextStyle(
                                color: AppColors.mutedText,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          Text(
                            sourceLabel,
                            style: const TextStyle(
                              color: AppColors.mutedText,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Text(
                      place.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Get directions',
                      style: TextStyle(
                        color: AppColors.secondaryAction,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.navigation_rounded,
                color: AppColors.secondaryAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.mutedText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
