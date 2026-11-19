import '../../data/mission_content_data.dart';
import '../../data/quiz_content_data.dart';
import '../../models/learner_quiz_model.dart';

/// One learner-facing status line per quiz, derived from the server state.
String quizStatusLabel(LearnerQuizSummary quiz) {
  if (quiz.resultReleased) return QuizContentData.statusResultReleased;
  if (quiz.awaitingEvaluation) {
    return quiz.isAutoSubmitted
        ? '${QuizContentData.statusAutoSubmitted} · ${QuizContentData.statusAwaitingEvaluation}'
        : QuizContentData.statusAwaitingEvaluation;
  }
  switch (quiz.state) {
    case LearnerQuizState.completed:
    case LearnerQuizState.submitted:
      return quiz.isAutoSubmitted
          ? '${QuizContentData.statusAutoSubmitted} · ${MissionContentData.quizAttemptUsed}'
          : MissionContentData.quizAttemptUsed;
    case LearnerQuizState.inProgress:
      return MissionContentData.quizAttemptInProgress;
    case LearnerQuizState.available:
      return MissionContentData.quizAttemptAvailable;
    case LearnerQuizState.unavailable:
      return quiz.closedReason == 'deadline_passed' || quiz.status == 'closed'
          ? MissionContentData.quizClosedDeadline
          : MissionContentData.quizAttemptUnavailable;
  }
}

/// Completed attempts (including those awaiting evaluation) open the result view.
bool quizOpensResult(LearnerQuizSummary quiz) =>
    quiz.attemptId != null &&
    (quiz.state == LearnerQuizState.completed ||
        quiz.awaitingEvaluation ||
        quiz.resultReleased);

String? quizTypeLabel(String? type) => switch (type) {
      'pre_assessment' => QuizContentData.quizTypePreAssessment,
      'formative' => QuizContentData.quizTypeFormative,
      'summative' => QuizContentData.quizTypeSummative,
      _ => null,
    };
