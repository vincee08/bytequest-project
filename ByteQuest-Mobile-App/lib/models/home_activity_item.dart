import '../data/mission_content_data.dart';
import 'assigned_activity_model.dart';
import 'homework_model.dart';
import 'learner_quiz_model.dart';

enum HomeActivityKind { quiz, homework, technical }

/// Presentation only. Starting/submitting still uses each authoritative service.
class HomeActivityItem {
  const HomeActivityItem(
      {required this.source,
      required this.kind,
      required this.id,
      required this.title,
      required this.classTitle,
      required this.deadline,
      required this.status,
      required this.action,
      required this.outstanding,
      required this.completed,
      this.enabled = true,
      this.lateness});
  final Object source;
  final HomeActivityKind kind;
  final String id, title, classTitle, status, action;
  final DateTime? deadline;
  final bool outstanding, completed, enabled;
  final String? lateness;

  factory HomeActivityItem.quiz(LearnerQuizSummary q) {
    final done = q.state == LearnerQuizState.completed;
    final used = q.state == LearnerQuizState.submitted || done;
    return HomeActivityItem(
        source: q,
        kind: HomeActivityKind.quiz,
        id: q.assignmentId,
        title: q.title,
        classTitle: q.classTitle,
        deadline: q.dueAt,
        outstanding: q.isAvailable && !used,
        completed: done,
        enabled: done || q.isAvailable && !used,
        status: done || used
            ? MissionContentData.quizAttemptUsed
            : q.closedReason == 'deadline_passed'
                ? MissionContentData.quizClosedDeadline
                : !q.isAvailable
                    ? MissionContentData.homeClosed
                    : q.state == LearnerQuizState.inProgress
                        ? MissionContentData.quizAttemptInProgress
                        : '${MissionContentData.homeOpen} · ${MissionContentData.quizOneAttempt}',
        action: done
            ? MissionContentData.quizViewResult
            : used
                ? MissionContentData.quizAttemptUsed
                : !q.isAvailable
                    ? MissionContentData.quizClosed
                    : q.state == LearnerQuizState.inProgress
                        ? MissionContentData.quizContinue
                        : MissionContentData.quizStart);
  }
  factory HomeActivityItem.homework(HomeworkAssignment h) => HomeActivityItem(
      source: h,
      kind: HomeActivityKind.homework,
      id: h.id,
      title: h.title,
      classTitle: h.classTitle,
      deadline: h.deadline,
      status: h.statusLabel,
      outstanding: h.submission == null,
      completed: h.submission?.status == 'graded',
      action: h.submission?.status == 'graded'
          ? MissionContentData.homeViewGrading
          : MissionContentData.homeworkView,
      lateness: h.submission == null && h.deadlinePassed
          ? MissionContentData.homeworkLateAllowed
          : (h.submission?.latenessSeconds ?? 0) > 0
              ? MissionContentData.homeworkLateBy(
                  latenessDuration(h.submission!.latenessSeconds))
              : null);
  factory HomeActivityItem.technical(
      AssignedActivity a, String? state, DateTime now) {
    final reviewed = const {
      'submitted',
      'evaluated',
      'under_review',
      'finalized'
    }.contains(state);
    final done = state == 'released';
    final future = a.availableAt?.isAfter(now) ?? false;
    final expired = a.dueAt != null && !now.isBefore(a.dueAt!);
    return HomeActivityItem(
        source: a,
        kind: HomeActivityKind.technical,
        id: a.id,
        title: a.title,
        classTitle: a.classTitle,
        deadline: a.dueAt,
        status:
            '${a.isAssessment ? MissionContentData.homeAssessment : MissionContentData.homePractice} · ${done ? MissionContentData.homeCompleted : reviewed ? MissionContentData.homeInReview : future ? MissionContentData.homeUpcoming : state == 'in_progress' ? MissionContentData.homeStarted : MissionContentData.homeAssigned}',
        action: MissionContentData.homeTechnicalOpen,
        outstanding: !reviewed && !done && !future && !expired,
        completed: done);
  }
  static int prioritize(HomeActivityItem a, HomeActivityItem b) {
    if (a.outstanding != b.outstanding) return a.outstanding ? -1 : 1;
    if (a.deadline == null && b.deadline != null) return 1;
    if (a.deadline != null && b.deadline == null) return -1;
    final dateOrder = a.deadline?.compareTo(b.deadline!) ?? 0;
    return dateOrder != 0 ? dateOrder : a.title.compareTo(b.title);
  }
}
