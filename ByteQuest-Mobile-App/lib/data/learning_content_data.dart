/// Learner strings for Learn, Practice, Progress and the Home class-work
/// shortcuts (re-defense slice A2). Kept out of widget files per AGENTS.md.
abstract final class LearningContentData {
  // Navigation
  static const navHome = 'Home';
  static const navLearn = 'Learn';
  static const navPractice = 'Practice';
  static const navProgress = 'Progress';
  static const navRewards = 'Rewards';
  static String navTabSemantics(String label) => '$label tab';

  // Shared
  static const retry = 'Try again';
  static const refresh = 'Refresh';
  static const howProgressWorks = 'How progress is calculated';
  static const close = 'Close';
  static const lockedLabel = 'Locked';
  static const completedLabel = 'Completed';
  static const inProgressLabel = 'In progress';
  static const notStartedLabel = 'Not started';
  static const newContentLabel = 'New content available';
  static const noRequiredItems = 'No required activities yet';
  static const noRequiredItemsDetail =
      'This module has no published lessons or practice missions yet. It does not block the next module.';
  static const curriculumUnavailable =
      'Your learning path could not be loaded. Check your connection and try again.';
  static const curriculumUnavailableTitle = 'Learning path unavailable';
  static const curriculumEmptyTitle = 'No curriculum yet';
  static const curriculumEmpty =
      'Published COC modules will appear here when they are available.';
  static const loadingCurriculum = 'Loading your learning path';
  static String cocLabel(int number) => 'COC $number';
  static String cocChipSemantics(int number, bool unlocked, bool completed) =>
      'COC $number, ${completed ? completedLabel : unlocked ? 'unlocked' : lockedLabel}';
  static String moduleLabel(int sequence, String code) =>
      'Module $sequence · $code';
  static String progressValue(int done, int total) =>
      '$done of $total required items';
  static String percentLabel(int percent) => '$percent%';
  static String moduleSemantics(
          int sequence, String code, String title, String state) =>
      'Module $sequence, $code $title, $state';
  static String modulesCompleted(int done, int total) =>
      '$done of $total modules complete';

  // Learn
  static const learnTitle = 'Learn';
  static const learnSubtitle =
      'COC modules, published lessons and official learning outcomes';
  static const learningPathLink = 'Assessment path';
  static const classQuizzesLink = 'Class quizzes';
  static const lessonsTitle = 'Lessons';
  static const noLessons = 'No published lessons in this module yet.';
  static const outcomesTitle = 'Official learning outcomes';
  static const outcomesSource =
      'Performance criteria from the CSS NC II Training Regulations';
  static const missionsTitle = 'Practice missions';
  static const noMissions =
      'No practice mission for this module yet. Complete its lessons to progress.';
  static const openPractice = 'Practice this mission';
  static const lockedModuleBanner = 'This module is locked';
  static const lessonCompleted = 'Lesson completed';
  static const lessonOpen = 'Open lesson';
  static String lessonSemantics(String title, bool completed) =>
      '$title, ${completed ? lessonCompleted : 'not completed'}';

  // Lesson reader
  static const markComplete = 'Mark as complete';
  static const markingComplete = 'Saving…';
  static const lessonLoadFailed =
      'This lesson could not be loaded. Check your connection and try again.';
  static const lessonCompleteFailed =
      'The lesson could not be marked complete. Try again.';
  static const lessonModuleLocked =
      'This module is still locked. Complete the previous module first.';
  static const lessonCompleteSaved = 'Lesson marked complete.';
  static const lessonLockedHint =
      'Lessons in a locked module can be read but not completed yet.';
  static const lessonEmptyBody = 'This lesson has no written content yet.';

  // COC practice quiz
  static const cocQuizTitle = 'COC practice quiz';
  static String cocQuizStart(int number) =>
      'Take the COC $number practice quiz';
  static String cocQuizReview(int number) =>
      'Review the COC $number practice quiz';
  static String cocQuizPending(int number) =>
      'Complete every module in COC $number to take its practice quiz. Passing it opens the next COC.';
  static String cocQuizLocked(int number) =>
      'Unlock COC $number to take its practice quiz.';
  static const cocQuizPassed = 'Practice quiz passed';
  static const cocQuizReady =
      'Every module is complete. Pass the practice quiz to open the next COC.';

  // Practice
  static const practiceTitle = 'Practice';
  static const practiceSubtitle =
      'Hands-on 2D missions, unlocked module by module';
  static const practiceTimerNote =
      'The COC practice timer below applies to every mission in this COC.';
  static const missionVerified = 'Verified';
  static const missionNotVerified = 'Not verified yet';
  static const missionLocked = 'Locked';
  static String missionNumber(int number) => 'Mission $number';
  static String missionRuns(int runs) => runs == 1 ? '1 run' : '$runs runs';
  static String missionBest(String duration) => 'Best $duration';
  static String missionSemantics(
          int number, String title, String state, int runs) =>
      'Mission $number, $title, $state, ${missionRuns(runs)}';
  static const missionAccessChecking = 'Checking access…';
  static const missionAccessDenied =
      'This mission is locked on the server. Complete the previous module first.';
  static const missionAccessFailed =
      'Mission access could not be confirmed. Check your connection and try again.';
  static const missionUnavailable =
      'This mission is not installed in this app version.';
  static String formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return minutes >= 60
        ? '${minutes ~/ 60} h ${minutes % 60} min'
        : '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  // Progress
  static const progressTitle = 'Progress';
  static const progressSubtitle =
      'Learning progress, missions and released results';
  static const overallTitle = 'Learning progress';
  static const overallNote =
      'Completion of required lessons, practice missions and COC practice quizzes.';
  static String topicsSummary(int done, int total) =>
      '$done of $total lessons complete';
  static String missionsSummary(int done, int total) =>
      '$done of $total practice missions verified';
  static String runsSummary(int runs) =>
      runs == 1 ? '1 practice run recorded' : '$runs practice runs recorded';
  static const cocBreakdownTitle = 'COC and module completion';
  static const resultsTitle = 'Released assessment results';
  static const resultsEmpty =
      'No final result has been released yet. Submitted work stays hidden until your Instructor reviews and releases it.';
  static const resultsFailed = 'Released results could not be loaded.';
  static const pendingNone = 'You are all caught up';
  static String pendingCount(int count) =>
      '$count ${count == 1 ? 'attempt' : 'attempts'} awaiting release';
  static const pendingDetailNone =
      'Released Instructor results will appear below.';
  static const pendingDetail =
      'Your Instructor is reviewing these submissions.';
  static const attemptHistory = 'View attempt history';
  static const instructorFinal = 'Instructor final';
  static String criteriaSatisfied(int done, int total) =>
      '$done/$total criteria satisfied';
  static String releasedOn(String date) => 'Released $date';
  static const criterionFeedback = 'Criterion feedback';
  static const criterionFeedbackDetail =
      'Review the evidence outcomes released by your Instructor.';
  static const satisfied = 'Satisfied';
  static const notSatisfied = 'Not satisfied';
  static const quizScoresTitle = 'Class quiz scores';
  static const quizScoresEmpty = 'No class quiz has been completed yet.';
  static const quizScoresFailed = 'Quiz scores could not be loaded.';
  static String quizScore(int correct, int total) => '$correct/$total correct';
  static String quizStatusCounts(int completed, int open) =>
      '$completed completed · $open open';
  static const quizScorePending = 'Score not available';
  static const homeworkTitle = 'Homework status';
  static const homeworkEmpty = 'No homework has been assigned yet.';
  static const homeworkFailed = 'Homework status could not be loaded.';
  static String homeworkCounts(int assigned, int submitted, int graded) =>
      '$assigned to do · $submitted submitted · $graded graded';
  static String homeworkScore(String score) => 'Score $score';
  static const homeworkLate = 'Late';
  static const performanceTitle = 'Performance';
  static const motivationNote =
      'Your points, level and achievements are in Rewards. They are motivational and separate from competency results.';

  // Methodology sheet
  static const methodologyTitle = 'How progress is calculated';
  static const methodologyItems = <(String, String)>[
    (
      'Lesson complete',
      'You opened the published lesson and marked it complete.'
    ),
    (
      'Mission complete',
      'The server verified your practice evidence for the mission.'
    ),
    (
      'Module complete',
      'Every published lesson and every practice mission of the module is complete. A module with no required activities does not block you.'
    ),
    (
      'COC complete',
      'Every module is complete and you passed the COC practice quiz.'
    ),
    (
      'Unlocking',
      'Module 1 of COC 1 is open. Each next module opens when the previous one is complete; the next COC opens when you pass the COC practice quiz. Unlocks are permanent.'
    ),
    (
      'Progress percentage',
      'Completed required items divided by required items (lessons, missions and the COC practice quiz). Quiz, homework and assessment scores are reported separately.'
    ),
  ];

  // Home class-work shortcuts
  static const classWorkTitle = 'Class work';
  static const classWorkSubtitle =
      'Tasks, classes, files and quizzes from your Instructors';
  static const shortcutTasks = 'Tasks';
  static const shortcutClasses = 'Classes';
  static const shortcutFiles = 'Files';
  static const shortcutQuizzes = 'Quizzes';
  static String shortcutSemantics(String label) => 'Open $label';
}
