import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Copy, icons and formatting for the learner Rewards tab (Objective 2).
///
/// Rewards are motivational and server-awarded. Wording here must never
/// suggest that points, levels or rank decide competency.
class RewardsContentData {
  RewardsContentData._();

  // Page and states
  static const String title = 'Rewards';
  static const String subtitle =
      'Points and achievements from your real learning activity';
  static const String infoTooltip = 'How rewards work';
  static const String settingsTooltip = 'Settings';
  static const String loadingLabel = 'Loading your rewards';
  static const String errorTitle = 'Rewards unavailable';
  static const String errorMessage =
      'Your rewards could not be loaded. Check your connection and try again.';
  static const String retryLabel = 'Try again';
  static const String refreshFailed =
      'Rewards could not be refreshed. Showing the last loaded values.';

  // Points and level summary
  static const String totalPointsLabel = 'Total points';
  static String levelLabel(int level, String title) => 'Level $level · $title';
  static String pointsToNextLevel(int remaining, int nextLevel) =>
      '$remaining points to Level $nextLevel';
  static const String topLevelReached = 'You have reached the highest level.';
  static String levelProgressSemantics(int level, String title) =>
      'Level $level, $title, progress to the next level';
  static String summarySemantics(int points, int level, String title,
          int? remaining, int? nextLevel) =>
      remaining == null || nextLevel == null
          ? 'Total points $points. Level $level, $title. Highest level reached.'
          : 'Total points $points. Level $level, $title. '
              '$remaining points to level $nextLevel.';

  // Empty state for a new learner
  static const String emptyTitle = 'Start earning points';
  static String emptyMessage(int points) =>
      'Verify your first practice mission to earn $points points.';
  static const String emptyGenericMessage =
      'Complete a learning activity to earn your first points.';
  static const String emptySupport =
      'Completed topics, modules and COCs, submitted quizzes, on-time homework '
      'and released assessments also earn points.';

  // Achievements
  static const String achievementsTitle = 'Achievements';
  static String achievementsProgress(int earned, int total) =>
      '$earned of $total earned';
  static String earnedOn(DateTime date) => 'Earned ${formatDate(date)}';
  static const String lockedLabel = 'Locked';
  static String progressLabel(int current, int target) => '$current of $target';
  static String achievementSemantics({
    required String title,
    required String description,
    required DateTime? earnedAt,
    required int progressCurrent,
    required int progressTarget,
  }) {
    if (earnedAt != null) return '$title, earned ${formatDate(earnedAt)}';
    final progress = progressTarget > 1
        ? ', progress $progressCurrent of $progressTarget'
        : '';
    return '$title, locked. $description$progress';
  }

  // Recent points
  static const String recentTitle = 'Recent points';
  static const String recentEmpty = 'Points you earn will appear here.';
  static String pointsDelta(int points) => '+$points';
  static String recentSemantics(
          String label, String? detail, int points, DateTime? date) =>
      [
        label,
        if (detail != null) detail,
        '$points points',
        if (date != null) formatDate(date),
      ].join(', ');

  // Points by category
  static const String categoriesTitle = 'Points by category';
  static const String categoriesSupport = 'Each activity earns points once';
  static String categoryDetail(int count, int pointsEach) =>
      count == 0 ? '$pointsEach points each' : '$count × $pointsEach points';
  static const String categoryInactive = 'No longer awarded';
  static String pointsValue(int points) => '$points pts';
  static String categorySemantics(String label, int points, int count) =>
      '$label, $points points from $count ${count == 1 ? 'activity' : 'activities'}';

  // Class leaderboard
  static const String leaderboardTitle = 'Class leaderboard';
  static const String leaderboardSupport =
      'Classmates in your active classes who chose to appear';
  static const String leaderboardToggleTitle =
      'Show me on the class leaderboard';
  // The server shows "First L." names, as the info sheet says.
  static const String leaderboardToggleSubtitle =
      'Show my first name, last initial and points to classmates.';
  static const String leaderboardShown =
      'Classmates can now see your first name, last initial and points.';
  static const String leaderboardHidden =
      'You are now hidden from your classmates.';
  static const String leaderboardSaveFailed =
      'Your leaderboard choice was not saved. Check your connection and try '
      'again.';
  static const String leaderboardOnlyYou =
      'No classmates have chosen to appear yet.';
  static const String leaderboardHiddenNote =
      'Classmates cannot see your row while this is off.';
  static const String youLabel = 'You';
  static String rankLabel(int rank) => '#$rank';
  static String leaderboardSemantics(
          int rank, String name, int points, bool isMe) =>
      'Rank $rank, $name${isMe ? ', you' : ''}, $points points';

  // Separation from competency and the info sheet
  static const String separationNote =
      'Points are motivational and separate from competency results.';
  static const String infoTitle = 'How rewards work';
  static const List<String> infoParagraphs = [
    'ByteQuest awards points on the server when real activity is recorded: a '
        'verified practice mission, a completed topic, module or COC, a '
        'submitted quiz, homework submitted on time, or an assessment result '
        'released by your instructor.',
    'Each activity earns points once. Your level rises with your total points, '
        'and achievements mark milestones.',
    'Points, levels, achievements and the leaderboard are for motivation only. '
        'They are separate from competency results and never change an '
        'assessment outcome. Only results released by your instructor show '
        'competency.',
    'The class leaderboard is optional. When you turn it on, classmates in '
        'your active classes see your first name, last initial and points.',
  ];
  static const String infoClose = 'Close';

  // Rewards copy shown outside the Rewards tab (help center and profile)
  static const String helpQuestion =
      'How do points, levels and achievements work?';
  static const String helpAnswer =
      'ByteQuest awards points on the server for real activity: verified '
      'practice missions, completed topics, modules and COCs, submitted '
      'quizzes, homework submitted on time and assessment results released '
      'by your instructor. Each activity earns points once. Your total sets '
      'your level, achievements mark milestones, and the Rewards tab shows '
      'them with an optional class leaderboard. Points are motivational and '
      'separate from competency results; they never change an assessment '
      'outcome.';
  static const String profileRecordNote =
      'Open Progress for Instructor-released results. Your points, level and '
      'earned achievements are in the Rewards tab.';
  static const String profileMotivationNote =
      'Points, levels and achievements are motivational and separate from '
      'competency results. They never change an Instructor-released result.';

  // Icons
  static const IconData fallbackAchievementIcon = Icons.emoji_events_outlined;
  static const Map<String, IconData> _achievementIcons = {
    'verified': Icons.verified_outlined,
    'memory': Icons.memory_outlined,
    'military_tech': Icons.military_tech_outlined,
    'workspace_premium': Icons.workspace_premium_outlined,
    'school': Icons.school_outlined,
    'computer': Icons.computer_outlined,
    'lan': Icons.lan_outlined,
    'dns': Icons.dns_outlined,
    'build': Icons.build_outlined,
    'quiz': Icons.quiz_outlined,
    'schedule': Icons.schedule_outlined,
    'assignment_turned_in': Icons.assignment_turned_in_outlined,
  };
  static IconData achievementIcon(String? key) =>
      _achievementIcons[key] ?? fallbackAchievementIcon;

  static const Map<String, IconData> _categoryIcons = {
    'practice_mission_verified': Icons.task_alt_outlined,
    'topic_completed': Icons.menu_book_outlined,
    'module_completed': Icons.school_outlined,
    'coc_completed': Icons.workspace_premium_outlined,
    'quiz_submitted': Icons.quiz_outlined,
    'homework_submitted_on_time': Icons.assignment_outlined,
    'assessment_released': Icons.fact_check_outlined,
  };
  static IconData categoryIcon(String eventType) =>
      _categoryIcons[eventType] ?? Icons.stars_outlined;

  static String formatDate(DateTime date) =>
      DateFormat.yMMMd().format(date.toLocal());
}
