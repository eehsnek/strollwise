import 'zone.dart';

class ZoneLaunchContextModel {
  const ZoneLaunchContextModel({
    required this.cityActivity,
    required this.crowdLevelPercent,
    required this.localPresencePercent,
    this.peakTimeWindow,
  });

  final String cityActivity;
  final double crowdLevelPercent;
  final double localPresencePercent;
  final String? peakTimeWindow;

  factory ZoneLaunchContextModel.fromJson(Map<String, dynamic> json) {
    return ZoneLaunchContextModel(
      cityActivity: (json['city_activity'] ?? 'quiet').toString(),
      crowdLevelPercent: _asDouble(json['crowd_level_percent']),
      localPresencePercent: _asDouble(json['local_presence_percent']),
      peakTimeWindow: json['peak_time_window'] as String?,
    );
  }
}

class CurrentZoneOverviewModel {
  const CurrentZoneOverviewModel({
    required this.currentZone,
    required this.nearbyZones,
    required this.alternativeZones,
    required this.context,
  });

  final ZoneModel? currentZone;
  final List<ZoneModel> nearbyZones;
  final List<ZoneModel> alternativeZones;
  final ZoneLaunchContextModel context;

  factory CurrentZoneOverviewModel.fromJson(Map<String, dynamic> json) {
    return CurrentZoneOverviewModel(
      currentZone: json['current_zone'] is Map<String, dynamic>
          ? ZoneModel.fromJson(json['current_zone'] as Map<String, dynamic>)
          : null,
      nearbyZones: ((json['nearby_zones'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ZoneModel.fromJson)
          .toList(),
      alternativeZones: ((json['alternative_zones'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ZoneModel.fromJson)
          .toList(),
      context: ZoneLaunchContextModel.fromJson(
        (json['context'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
