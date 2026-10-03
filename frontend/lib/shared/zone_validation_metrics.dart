import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/zone.dart';

/// Set after tag submit; [ZoneValidationMetrics.forZone] prefers this for the
/// matching [ZoneValidationLive.zoneId].
final zoneValidationLiveProvider = StateProvider<ZoneValidationLive?>(
  (ref) => null,
);

/// Fresh validation numbers shown right after a tag submit (before the next
/// full zone refetch paints the card).
class ZoneValidationLive {
  const ZoneValidationLive({
    required this.zoneId,
    required this.totalSignals,
    required this.matchingSignals,
    required this.confidence,
    required this.topCategory,
    required this.updatedAt,
  });

  final String zoneId;
  final int totalSignals;
  final int matchingSignals;
  final double confidence;
  final String topCategory;
  final DateTime updatedAt;
}

class ZoneValidationMetrics {
  const ZoneValidationMetrics({
    required this.totalSignals,
    required this.matchingSignals,
    required this.confidence,
    required this.topCategory,
    required this.lastUpdated,
  });

  final int totalSignals;
  final int matchingSignals;
  final double confidence;
  final String topCategory;
  final String lastUpdated;

  static ZoneValidationMetrics forZone(WidgetRef ref, ZoneModel zone) {
    final live = ref.watch(zoneValidationLiveProvider);
    if (live != null && live.zoneId == zone.zoneId) {
      return ZoneValidationMetrics(
        totalSignals: live.totalSignals,
        matchingSignals: live.matchingSignals,
        confidence: live.confidence,
        topCategory: live.topCategory,
        lastUpdated: formatLastUpdated(live.updatedAt),
      );
    }
    return ZoneValidationMetrics(
      totalSignals: zone.reportCount,
      matchingSignals: matchingSignalCount(zone),
      confidence: zone.confidenceScore,
      topCategory: topAgreedCategory(zone),
      lastUpdated: formatLastUpdated(zone.updatedAt),
    );
  }
}

int matchingSignalCount(ZoneModel zone) {
  final total = zone.reportCount < 1 ? 1 : zone.reportCount;
  return math.max(1, (total * (zone.confidenceScore / 100)).round());
}

String topAgreedCategory(ZoneModel zone) {
  final raw = (zone.placeName ?? zone.zoneType).replaceAll('_', ' ');
  return raw
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String formatLastUpdated(DateTime? updated) {
  if (updated == null) return 'Recent';
  final local = updated.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Human label for the tag the user just submitted (falls back to zone name).
String topCategoryFromSubmission({
  required List<String> tags,
  required ZoneModel zone,
}) {
  const skip = {'exact_road_spot', 'private', 'public'};
  for (final tag in tags) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty || skip.contains(trimmed)) continue;
    return trimmed
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
  return topAgreedCategory(zone);
}

ZoneModel withReportCount(ZoneModel zone, int reportCount, {DateTime? updatedAt}) {
  return ZoneModel(
    zoneId: zone.zoneId,
    displayName: zone.displayName,
    behaviorType: zone.behaviorType,
    functionType: zone.functionType,
    travelerMix: zone.travelerMix,
    placeId: zone.placeId,
    placeName: zone.placeName,
    placeType: zone.placeType,
    places: zone.places,
    summary: zone.summary,
    liveStatus: zone.liveStatus,
    polygonGeoJson: zone.polygonGeoJson,
    boundary: zone.boundary,
    polygonParts: zone.polygonParts,
    centroidLat: zone.centroidLat,
    centroidLng: zone.centroidLng,
    crowdLevel: zone.crowdLevel,
    localPresencePercent: zone.localPresencePercent,
    localRatio: zone.localRatio,
    mapColor: zone.mapColor,
    peakTimeLabel: zone.peakTimeLabel,
    confidenceScore: zone.confidenceScore,
    priorityScore: zone.priorityScore,
    reportCount: reportCount,
    sourceH3Rings: zone.sourceH3Rings,
    topActivities: zone.topActivities,
    whyVisit: zone.whyVisit,
    liveUpdate: zone.liveUpdate,
    nearbyZoneIds: zone.nearbyZoneIds,
    updatedAt: updatedAt ?? zone.updatedAt,
  );
}

ZoneValidationLive liveMetricsAfterTag({
  required ZoneModel zone,
  required int totalSignals,
  required int matchingSignals,
  required List<String> tags,
}) {
  return ZoneValidationLive(
    zoneId: zone.zoneId,
    totalSignals: totalSignals,
    matchingSignals: matchingSignals,
    confidence: zone.confidenceScore,
    topCategory: topCategoryFromSubmission(tags: tags, zone: zone),
    updatedAt: DateTime.now(),
  );
}
