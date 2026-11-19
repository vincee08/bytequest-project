/// Learner Rewards projection returned by `public.get_learner_rewards()`.
///
/// Every value is computed and awarded by the server from real learning
/// records. Rewards are motivational only and never part of a competency
/// result, so nothing here is evaluated or recalculated on the device.
class LearnerRewards {
  const LearnerRewards({
    required this.points,
    required this.level,
    required this.showOnLeaderboard,
    required this.achievements,
    required this.recent,
    required this.leaderboard,
    required this.pointsByCategory,
  });

  final int points;
  final RewardLevel level;
  final bool showOnLeaderboard;
  final List<RewardAchievement> achievements;
  final List<RewardPointEvent> recent;
  final List<RewardLeaderboardEntry> leaderboard;
  final List<RewardPointCategory> pointsByCategory;

  factory LearnerRewards.fromJson(Map<String, dynamic> json) => LearnerRewards(
        points: _int(json['points']),
        level: RewardLevel.fromJson(_map(json['level'])),
        showOnLeaderboard: json['show_on_leaderboard'] == true,
        achievements: _list(json['achievements'], RewardAchievement.fromJson),
        recent: _list(json['recent'], RewardPointEvent.fromJson),
        leaderboard:
            _list(json['leaderboard'], RewardLeaderboardEntry.fromJson),
        pointsByCategory:
            _list(json['points_by_category'], RewardPointCategory.fromJson),
      );

  /// A learner with no awarded activity yet.
  bool get isNewLearner => points == 0 && recent.isEmpty;

  int get earnedAchievementCount =>
      achievements.where((achievement) => achievement.earned).length;

  /// Points currently configured for one award of [eventType], if active.
  int? pointsFor(String eventType) {
    for (final category in pointsByCategory) {
      if (category.eventType == eventType && category.active) {
        return category.pointsEach;
      }
    }
    return null;
  }

  LearnerRewards copyWith({bool? showOnLeaderboard}) => LearnerRewards(
        points: points,
        level: level,
        showOnLeaderboard: showOnLeaderboard ?? this.showOnLeaderboard,
        achievements: achievements,
        recent: recent,
        leaderboard: leaderboard,
        pointsByCategory: pointsByCategory,
      );
}

class RewardLevel {
  const RewardLevel({
    required this.level,
    required this.title,
    required this.minPoints,
    required this.nextLevel,
    required this.nextMinPoints,
    required this.progressPercent,
  });

  final int level;
  final String title;
  final int minPoints;
  final int? nextLevel;
  final int? nextMinPoints;
  final int progressPercent;

  factory RewardLevel.fromJson(Map<String, dynamic> json) => RewardLevel(
        level: _int(json['level'], fallback: 1),
        title: _string(json['title']),
        minPoints: _int(json['min_points']),
        nextLevel: _nullableInt(json['next_level']),
        nextMinPoints: _nullableInt(json['next_min_points']),
        progressPercent: _int(json['progress_percent']).clamp(0, 100),
      );

  bool get isTopLevel => nextLevel == null || nextMinPoints == null;

  double get progressFraction => isTopLevel ? 1 : progressPercent / 100;

  int? pointsToNextLevel(int points) {
    final target = nextMinPoints;
    if (isTopLevel || target == null) return null;
    final remaining = target - points;
    return remaining < 0 ? 0 : remaining;
  }
}

class RewardAchievement {
  const RewardAchievement({
    required this.code,
    required this.title,
    required this.description,
    required this.icon,
    required this.earnedAt,
    required this.progressCurrent,
    required this.progressTarget,
  });

  final String code;
  final String title;
  final String description;
  final String? icon;
  final DateTime? earnedAt;
  final int progressCurrent;
  final int progressTarget;

  factory RewardAchievement.fromJson(Map<String, dynamic> json) =>
      RewardAchievement(
        code: _string(json['code']),
        title: _string(json['title']),
        description: _string(json['description']),
        icon: json['icon'] as String?,
        earnedAt: _date(json['earned_at']),
        progressCurrent: _int(json['progress_current']),
        progressTarget: _int(json['progress_target'], fallback: 1),
      );

  bool get earned => earnedAt != null;

  /// Count rules above one show "n of target" while locked.
  bool get showsProgress => !earned && progressTarget > 1;
}

class RewardPointEvent {
  const RewardPointEvent({
    required this.eventType,
    required this.label,
    required this.points,
    required this.awardedAt,
    required this.sourceId,
    required this.detail,
  });

  final String eventType;
  final String label;
  final int points;
  final DateTime? awardedAt;
  final String? sourceId;
  final String? detail;

  factory RewardPointEvent.fromJson(Map<String, dynamic> json) =>
      RewardPointEvent(
        eventType: _string(json['event_type']),
        label: _string(json['label']),
        points: _int(json['points']),
        awardedAt: _date(json['awarded_at']),
        sourceId: json['source_id'] as String?,
        detail: _optionalString(json['detail']),
      );
}

class RewardLeaderboardEntry {
  const RewardLeaderboardEntry({
    required this.rank,
    required this.displayName,
    required this.points,
    required this.isMe,
  });

  final int rank;
  final String displayName;
  final int points;
  final bool isMe;

  factory RewardLeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      RewardLeaderboardEntry(
        rank: _int(json['rank'], fallback: 1),
        displayName: _string(json['display_name']),
        points: _int(json['points']),
        isMe: json['is_me'] == true,
      );
}

class RewardPointCategory {
  const RewardPointCategory({
    required this.eventType,
    required this.label,
    required this.points,
    required this.count,
    required this.pointsEach,
    required this.active,
  });

  final String eventType;
  final String label;
  final int points;
  final int count;
  final int pointsEach;
  final bool active;

  factory RewardPointCategory.fromJson(Map<String, dynamic> json) =>
      RewardPointCategory(
        eventType: _string(json['event_type']),
        label: _string(json['label']),
        points: _int(json['points']),
        count: _int(json['count']),
        pointsEach: _int(json['points_each']),
        active: json['active'] != false,
      );
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) parse) =>
    value is List
        ? value
            .whereType<Map>()
            .map((item) => parse(Map<String, dynamic>.from(item)))
            .toList(growable: false)
        : List<T>.empty();

int _int(Object? value, {int fallback = 0}) =>
    value is num ? value.round() : int.tryParse('$value') ?? fallback;

int? _nullableInt(Object? value) => value == null ? null : _int(value);

String _string(Object? value) => value is String ? value : '';

String? _optionalString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
