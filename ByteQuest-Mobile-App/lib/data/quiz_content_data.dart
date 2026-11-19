/// Learner-facing quiz strings (re-defense slice A3). Widgets read every
/// quiz label, state and feedback message from here.
class QuizContentData {
  QuizContentData._();

  // Question types.
  static const typeMultipleChoice = 'Multiple choice';
  static const typeTrueFalse = 'True or false';
  static const typeIdentification = 'Identification';
  static const typeScenario = 'Scenario question';
  static const typeScenarioEssay = 'Scenario essay';
  static const typeQuestion = 'Question';

  // Quiz taking.
  static String questionProgress(int index, int total) =>
      'Question $index of $total';
  static const leaveQuiz = 'Leave quiz';
  static const leaveTitle = 'Leave this quiz?';
  static const leaveMessage =
      'Answers already saved to ByteQuest will be restored when you continue.';
  static const leaveStay = 'Stay';
  static const savingAnswer = 'Saving answer';
  static String answersSaved(int count) => '$count answers saved';
  static const progressLabel = 'Quiz question progress';
  static const previous = 'Previous';
  static const next = 'Next';
  static const reviewAndSubmit = 'Review & submit';
  static const submitting = 'Submitting';
  static const answerLabel = 'Your answer';
  static const answerHint = 'Enter your answer';
  static const answerHelper = 'Your answer is saved when you continue.';
  static const answerRequired = 'Choose or enter an answer before continuing.';
  static const answerNotSaved =
      'Your answer was not saved. Check your connection and try again.';
  static const noQuestionsTitle = 'Quiz has no questions';
  static const noQuestionsMessage =
      'Ask your Instructor to review the published quiz.';
  static const optionsUnavailableTitle = 'Question unavailable';
  static const optionsUnavailableMessage =
      'This published question has no answer options.';
  static String optionSemantics(String label, bool selected) =>
      '$label${selected ? ", selected" : ""}';

  // Submission review.
  static const submitTitle = 'Submit quiz?';
  static String submitAllAnswered(int total) =>
      'You answered all $total questions. After submission, answers can no longer be changed.';
  static String submitMissing(int missing) =>
      '$missing questions still need an answer.';
  static const reviewAnswers = 'Review answers';
  static const submit = 'Submit';
  static const submitFailed =
      'The quiz was not submitted. Your saved answers remain available.';

  // Scenario essays.
  static const scenarioHeading = 'Scenario';
  static const essayLabel = 'Your essay answer';
  static const essayHint =
      'Explain your actions and reasons in complete sentences.';
  static String wordCount(int words) => words == 1 ? '1 word' : '$words words';
  static String wordGuidance(int? min, int? max) {
    if (min != null && max != null) return 'Suggested length: $min–$max words';
    if (min != null) return 'Suggested length: at least $min words';
    if (max != null) return 'Suggested length: up to $max words';
    return 'Write as much as you need to explain your answer.';
  }

  static String wordCountStatus(int words, int? min, int? max) {
    if (min != null && words < min) {
      return '${wordCount(words)} · below the suggested minimum';
    }
    if (max != null && words > max) {
      return '${wordCount(words)} · above the suggested maximum';
    }
    return wordCount(words);
  }

  static const essaySaving = 'Saving essay…';
  static const essaySaved = 'Essay saved';
  static const essayUnsaved = 'Not saved yet — saving automatically';
  static const essaySaveRetry =
      'Essay not saved. It is kept on this device and will be saved when you are back online.';
  static const essayRestored =
      'Your unsaved essay draft was restored from this device.';
  static const rubricHeading = 'Scored by your Instructor on';
  static String rubricCriterion(String name, num maxPoints) =>
      '$name · ${formatPoints(maxPoints)} pts';
  static String essayPoints(num points) =>
      'Instructor-scored · ${formatPoints(points)} points';

  // Timing.
  static String timeLimit(int minutes) => '$minutes-minute time limit';
  static String timeLeft(String clock) => 'Time left $clock';
  static String timeLeftSemantics(int minutes, int seconds) => minutes > 0
      ? '$minutes minutes $seconds seconds left'
      : '$seconds seconds left';
  static const timeAlmostUp =
      'Less than a minute left. Your saved answers will be submitted automatically.';
  static const timeUpTitle = 'Time is up';
  static const timeUpMessage =
      'Your saved answers are being submitted automatically.';
  static const timeUpChecking = 'Checking your automatic submission…';
  static const timeLimitBriefing =
      'The timer starts when you begin and keeps running if you leave the app. When time runs out, your saved answers are submitted automatically.';
  static const deadlineAutoSubmitBriefing =
      'At the deadline, saved answers are submitted automatically.';

  // Quiz states.
  static const statusAwaitingEvaluation = 'Awaiting instructor evaluation';
  static const statusResultReleased = 'Result released';
  static const statusAutoSubmitted = 'Auto-submitted';
  static const autoSubmittedDeadline = 'Auto-submitted at the deadline';
  static const autoSubmittedTimeLimit =
      'Auto-submitted when the time limit ended';
  static String autoSubmittedAt(String when) => 'Submitted automatically $when';
  static const viewSubmission = 'View submission';
  static const viewResult = 'View result';

  // Briefing.
  static const briefingTitle = 'Quiz briefing';
  static const briefingClose = 'Close quiz briefing';
  static String questionsCount(int count) => '$count questions';
  static String essaysCount(int count) =>
      count == 1 ? '1 scenario essay' : '$count scenario essays';
  static const instructions = 'Instructions';
  static const focusHeading = 'What this quiz assesses';
  static const briefingAnswersSaved =
      'Your answers are saved as you continue. The database evaluates the published answer contract only after you confirm submission. Quiz results never change competency status.';
  static const briefingInstructorRelease =
      'Your Instructor scores written answers and releases the result. Until then you will see "Awaiting instructor evaluation".';
  static const openingQuiz = 'Opening quiz…';
  static const openFailed =
      'This quiz could not be opened. Check its availability and try again.';
  static const quizTypePreAssessment = 'Pre-assessment';
  static const quizTypeFormative = 'Formative';
  static const quizTypeSummative = 'Summative';

  // Result.
  static const resultTitle = 'Quiz result';
  static const resultClose = 'Close quiz result';
  static const resultLoading = 'Loading quiz result';
  static const resultUnavailableTitle = 'Result unavailable';
  static const resultUnavailable =
      'This quiz result is not available right now.';
  static const tryAgain = 'Try again';
  static const resultCompleted = 'COMPLETED';
  static const resultReleased = 'RESULT RELEASED';
  static const resultSubmitted = 'SUBMITTED';
  static String scoreOf(String score, String max) => '$score / $max';
  static const pointsLabel = 'points';
  static const correctLabel = 'questions answered correctly';
  static String completedAt(String when) => 'Completed $when';
  static String submittedAt(String when) => 'Submitted $when';
  static String releasedAt(String when) => 'Released $when';
  static String answeredCount(int answered, int total) =>
      '$answered of $total questions answered';
  static const awaitingMessage =
      'Your Instructor is evaluating your answers. Your score and feedback appear here after the result is released.';
  static const supplementaryNotice =
      'This is a supplementary quiz result. It does not determine TESDA competency or replace an Instructor-released practical assessment.';
  static const feedbackHeading = 'Question feedback';
  static const feedbackSupporting =
      'Your answer is shown without exposing answer keys.';
  static const submittedAnswersHeading = 'Your submitted answers';
  static const submittedAnswersSupporting =
      'Scores appear after your Instructor releases the result.';
  static const itemCorrect = 'Correct';
  static const itemNeedsReview = 'Needs review';
  static const itemNotAnswered = 'Not answered';
  static const itemSubmitted = 'Submitted';
  static const notAnsweredText = 'No answer was saved for this question.';
  static String itemPoints(num awarded, num max) =>
      '${formatPoints(awarded)} / ${formatPoints(max)} pts';
  static const instructorFeedback = 'Instructor feedback';
  static const rubricScores = 'Rubric scores';
  static String resultSemantics(String title, String score, String max) =>
      '$title. $score out of $max points. Supplementary quiz result.';
  static String awaitingSemantics(String title) =>
      '$title. Awaiting instructor evaluation.';

  // List.
  static const listTitle = 'Quizzes';
  static const listSubtitle =
      'Supplementary checks assigned by your Instructor';
  static const listClose = 'Close quizzes';
  static const listLoading = 'Loading assigned quizzes';
  static const listNotice =
      'Quiz results support learning only. They do not determine TESDA competency or replace Instructor-reviewed practical assessment.';
  static const listUnavailableTitle = 'Quizzes unavailable';
  static const listUnavailable =
      'Your assigned quizzes could not be loaded. Check your connection and try again.';
  static const listEmptyTitle = 'No quizzes assigned';
  static const listEmptyMessage =
      'Published quizzes assigned through your active classes will appear here.';
  static String answeredProgress(int answered, int total) =>
      '$answered of $total answered';
  static const answerProgressLabel = 'Quiz answer progress';
  static String cardSemantics(String title, String status, int questions) =>
      '$title. $status. $questions questions.';

  static String formatPoints(num value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.001) return rounded.toInt().toString();
    return value.toStringAsFixed(1);
  }

  /// Counts words the way learners expect: runs of non-space characters.
  static int countWords(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }
}
