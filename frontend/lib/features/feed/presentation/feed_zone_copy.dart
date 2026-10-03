import '../../../shared/models/zone.dart';

/// Short hook for feed cards — avoids repeating the full backend summary paragraph.
String feedZoneHeadline(ZoneModel zone) {
  final live = (zone.liveUpdate ?? zone.liveStatus).replaceAll('_', ' ').trim();
  final peak = zone.peakTimeLabel?.trim() ?? '';
  final liveLabel = _titleizeToken(live.isEmpty ? 'active now' : live);
  if (peak.isNotEmpty) {
    return '$liveLabel · $peak';
  }
  return liveLabel;
}

/// Optional one-line detail; returns null when the long summary adds nothing new.
String? feedZoneDetailLine(ZoneModel zone) {
  final summary = zone.summary?.trim();
  if (summary == null || summary.isEmpty) return null;
  if (summary.length <= 72) return summary;
  return '${summary.substring(0, 69)}…';
}

List<String> feedActivityChips(ZoneModel zone) {
  final fromZone = zone.topActivities
      .map((a) => _titleizeToken(a))
      .where((a) => a.isNotEmpty)
      .take(3)
      .toList();
  if (fromZone.isNotEmpty) return fromZone;

  return switch (zone.zoneType.toLowerCase()) {
    'food' || 'food_hotspot' => const ['Street food', 'Cafés', 'Dining'],
    'school' || 'student_area' => const ['Study spots', 'Campus edge', 'Budget meals'],
    'transport' || 'transport_zone' => const ['Transit', 'Pickup', 'Commute'],
    'commercial' || 'commercial_zone' => const ['Shopping', 'Offices', 'Malls'],
    'tourist' || 'tourist_hotspot' => const ['Landmarks', 'Photos', 'Visitors'],
    _ => [
        zone.travelerType,
        '${zone.reportCount} tags',
      ],
  };
}

String feedCrowdLabel(ZoneModel zone) {
  final pct = (zone.crowdLevel * 100).round();
  if (pct >= 65 || zone.liveStatus.contains('busy')) return 'Busy now';
  if (pct >= 35) return 'Active now';
  return 'Calm now';
}

bool feedShowConfidenceBadge(ZoneModel zone) => zone.confidenceScore >= 80;

String _titleizeToken(String value) {
  return value
      .replaceAll('_', ' ')
      .split(' ')
      .where((p) => p.isNotEmpty)
      .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');
}
