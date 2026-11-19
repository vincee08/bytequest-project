/// Learner-facing copy for the Performance section (Objective 6).
///
/// Widget files read every string from here. Outcome labels describe the
/// released result in competency terms and never use "Wrong" or "Correct".
class PerformanceContentData {
  PerformanceContentData._();

  static const sectionTitle = 'My performance';
  static const sectionSubtitle =
      'Progress, competency and released scores from your recorded work.';
  static const loadingLabel = 'Loading your performance';
  static const errorTitle = 'Performance could not be loaded';
  static const errorMessage =
      'Your records are safe. Check your connection and try again.';
  static const retryLabel = 'Try again';
  static const refreshLabel = 'Refresh my performance';
  static const emptyTitle = 'No recorded performance yet';
  static const emptyMessage =
      'Complete a practice mission, submit a quiz or homework, or wait for a released assessment result to see your performance here.';
  static const staleNotice =
      'Showing your last loaded results. They refresh automatically when you are back online.';

  static String updatedAt(String clock) => 'Updated $clock';

  // Progress
  static const progressTitle = 'Learning progress';
  static const progressDefinition =
      'Completed topics, verified practice missions and passed COC practice quizzes out of everything required.';
  static String itemsCompleted(int completed, int total) =>
      '$completed of $total required items complete';
  static String modulesCompleted(int completed, int total) =>
      total == 0 ? 'No required activities yet' : '$completed of $total modules complete';
  static String cocProgressSemantics(String coc, String percent) =>
      '$coc learning progress $percent';
  static const overallProgressSemantics = 'Overall learning progress';

  // Competency
  static const competencyTitle = 'Competency achieved';
  static const competencySubtitle =
      'Criteria from your latest released assessment result on each mission.';
  static const competencyEmpty =
      'Criterion results appear after your instructor releases an assessment result.';
  static const criterionFallback = 'Assessment criterion';
  static const achievedLabel = 'Achieved';
  static const notYetAchievedLabel = 'Not yet achieved';
  static const reviewLabel = 'Under review';
  static String competencySummary(int achieved, int total) =>
      '$achieved of $total criteria achieved';

  // Scores
  static const quizzesTitle = 'Quiz scores';
  static const quizzesEmpty = 'No submitted quiz yet.';
  static const quizFallback = 'Quiz';
  static String quizScore(int correct, int total) => '$correct of $total answers';
  static const homeworkTitle = 'Homework scores';
  static const homeworkEmpty = 'No homework submitted yet.';
  static const homeworkFallback = 'Homework';
  static const homeworkAwaiting = 'Awaiting grade';
  static const homeworkGradedNoScore = 'Graded with feedback';
  static const homeworkLate = 'Submitted late';
  static String homeworkScore(String score, String max) => '$score / $max';

  // Assessments
  static const assessmentsTitle = 'Released assessment results';
  static const assessmentsEmpty =
      'Results appear here only after your instructor releases them.';
  static const assessmentFallback = 'Assessment';
  static const competentLabel = 'Competent';
  static const notYetCompetentLabel = 'Not yet competent';
  static const pendingValidationLabel = 'Pending validation';
  static String releasedOn(String date) => 'Released $date';

  // Practice
  static const practiceTitle = 'Practice missions';
  static const missionsVerifiedLabel = 'Missions verified';
  static const runsLabel = 'Practice runs';
  static const bestTimesTitle = 'Best verified times';
  static const bestTimesEmpty = 'Verify a practice mission to record a best time.';
  static const missionFallback = 'Practice mission';

  static const noValue = '—';

  static String percent(double? value) {
    if (value == null) return noValue;
    final rounded = (value * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? '${rounded.toStringAsFixed(0)}%'
        : '${rounded.toStringAsFixed(1)}%';
  }

  static String number(double? value) {
    if (value == null) return noValue;
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

  /// 120 -> "2m 00s", 45 -> "45s", 3720 -> "1h 2m".
  static String duration(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final hours = safe ~/ 3600;
    final minutes = (safe % 3600) ~/ 60;
    final rest = safe % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${rest.toString().padLeft(2, '0')}s';
    return '${rest}s';
  }

  static String outcomeLabel(String? outcome) {
    switch (outcome) {
      case 'competent':
        return competentLabel;
      case 'not_yet_competent':
        return notYetCompetentLabel;
      case 'pending_tesda_validation':
        return pendingValidationLabel;
      default:
        return noValue;
    }
  }

  static String criterionLabel(String outcome) {
    switch (outcome) {
      case 'satisfied':
        return achievedLabel;
      case 'requires_review':
        return reviewLabel;
      default:
        return notYetAchievedLabel;
    }
  }

  static String missionCodeLabel(String? code) =>
      code == null ? noValue : code.toUpperCase().replaceAll('_', ' ');
}
