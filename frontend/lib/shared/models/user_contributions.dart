import 'report.dart';

class UserContributionStatsModel {
  UserContributionStatsModel({
    required this.submitted,
    required this.approved,
    required this.pending,
  });

  final int submitted;
  final int approved;
  final int pending;

  factory UserContributionStatsModel.fromJson(Map<String, dynamic> json) {
    return UserContributionStatsModel(
      submitted: (json['submitted'] as num?)?.toInt() ?? 0,
      approved: (json['approved'] as num?)?.toInt() ?? 0,
      pending: (json['pending'] as num?)?.toInt() ?? 0,
    );
  }
}

class ProfileBadgeModel {
  ProfileBadgeModel({required this.key, required this.label});

  final String key;
  final String label;

  factory ProfileBadgeModel.fromJson(Map<String, dynamic> json) {
    return ProfileBadgeModel(
      key: (json['key'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
    );
  }
}

class UserContributionsModel {
  UserContributionsModel({
    required this.stats,
    required this.recentReports,
    required this.badges,
    required this.contributorLabel,
  });

  final UserContributionStatsModel stats;
  final List<ReportModel> recentReports;
  final List<ProfileBadgeModel> badges;
  final String contributorLabel;

  factory UserContributionsModel.fromJson(Map<String, dynamic> json) {
    final recent = (json['recent_reports'] as List?) ?? const [];
    return UserContributionsModel(
      stats: UserContributionStatsModel.fromJson(
        (json['stats'] as Map<String, dynamic>?) ?? const {},
      ),
      recentReports: recent
          .whereType<Map<String, dynamic>>()
          .map(ReportModel.fromJson)
          .toList(),
      badges: ((json['badges'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ProfileBadgeModel.fromJson)
          .toList(),
      contributorLabel: (json['contributor_label'] ?? '').toString(),
    );
  }
}
