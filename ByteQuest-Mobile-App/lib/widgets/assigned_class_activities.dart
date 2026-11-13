import 'dart:async';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/learner_ui.dart';
import '../data/mission_content_data.dart';
import '../models/homework_model.dart';
import '../models/learner_quiz_model.dart';
import '../services/homework_service.dart';
import '../services/learner_quiz_service.dart';
import '../services/learner_realtime_coordinator.dart';
import '../screens/homework/homework_details_screen.dart';
import '../screens/quizzes/quiz_details_screen.dart';
import '../screens/quizzes/quiz_result_screen.dart';

/// Separate supplementary lists. Never changes official assessment counters.
class AssignedClassActivities extends StatefulWidget {
  const AssignedClassActivities(
      {super.key, this.classId, this.quizService, this.homeworkService});
  final String? classId;
  final LearnerQuizService? quizService;
  final HomeworkService? homeworkService;
  @override
  State<AssignedClassActivities> createState() =>
      _AssignedClassActivitiesState();
}

class _AssignedClassActivitiesState extends State<AssignedClassActivities>
    with
        LearnerRealtimeRefreshMixin<AssignedClassActivities>,
        WidgetsBindingObserver {
  List<LearnerQuizSummary> _quizzes = [];
  List<HomeworkAssignment> _homework = [];
  bool _loading = true;
  bool _loadingNow = false;
  bool _quizError = false;
  bool _homeworkError = false;
  Timer? _poll;
  @override
  Set<LearnerRealtimeDomain> get realtimeDomains => const {
        LearnerRealtimeDomain.quizzes,
        LearnerRealtimeDomain.learning,
        LearnerRealtimeDomain.classes
      };
  @override
  Future<void> refreshFromRealtime() => _load();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted &&
          TickerMode.valuesOf(context).enabled &&
          ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_load());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loadingNow) return;
    _loadingNow = true;
    await Future.wait([
      () async {
        try {
          final data = await (widget.quizService ?? LearnerQuizService())
              .getAvailableQuizzes();
          if (mounted) {
            setState(() {
              _quizzes = data
                  .where((q) =>
                      widget.classId == null || q.classId == widget.classId)
                  .toList();
              _quizError = false;
            });
          }
        } catch (_) {
          if (mounted) setState(() => _quizError = true);
        }
      }(),
      () async {
        try {
          final data = await (widget.homeworkService ?? HomeworkService())
              .getAssignments(classId: widget.classId);
          if (mounted) {
            setState(() {
              _homework = data;
              _homeworkError = false;
            });
          }
        } catch (_) {
          if (mounted) setState(() => _homeworkError = true);
        }
      }(),
    ]);
    _loadingNow = false;
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
                onPressed: _loadingNow ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text(MissionContentData.classActivitiesRetry))),
        if (_loading)
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text(MissionContentData.classActivitiesLoading))
        else ...[
          Semantics(
              header: true,
              container: true,
              child: LearnerSectionHeader(
                  title:
                      '${MissionContentData.assignedQuizzes} (${_quizzes.length})')),
          const SizedBox(height: 10),
          if (_quizError)
            const Text(MissionContentData.classActivitiesUnavailable)
          else if (_quizzes.isEmpty)
            const Text(MissionContentData.quizzesEmpty)
          else
            ..._quizzes.map(_quizCard),
          const SizedBox(height: 22),
          Semantics(
              header: true,
              container: true,
              child: LearnerSectionHeader(
                  title:
                      '${MissionContentData.homeworkAssignments} (${_homework.length})')),
          const SizedBox(height: 10),
          if (_homeworkError)
            const Text(MissionContentData.classActivitiesUnavailable)
          else if (_homework.isEmpty)
            const Text(MissionContentData.homeworkEmpty)
          else
            ..._homework.map(_homeworkCard),
        ],
      ]);

  Widget _quizCard(LearnerQuizSummary q) {
    final completed = q.state == LearnerQuizState.completed;
    final submitted = q.state == LearnerQuizState.submitted;
    final label = completed
        ? MissionContentData.quizViewResult
        : submitted
            ? MissionContentData.quizAttemptUsed
            : !q.isAvailable
                ? MissionContentData.quizClosed
                : q.state == LearnerQuizState.inProgress
                    ? MissionContentData.quizContinue
                    : MissionContentData.quizStart;
    return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Semantics(
            container: true,
            child: LearnerSurface(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(q.title, style: AppTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(q.classTitle),
                  Text(MissionContentData.homeworkDue(manilaDate(q.dueAt)),
                      style: AppTheme.bodySmall),
                  Text(q.closedReason == 'deadline_passed' && !completed
                      ? MissionContentData.quizClosedDeadline
                      : q.state == LearnerQuizState.inProgress
                          ? MissionContentData.quizAttemptInProgress
                          : completed
                              ? MissionContentData.quizAttemptUsed
                              : MissionContentData.quizOneAttempt),
                  const SizedBox(height: 8),
                  FilledButton(
                      onPressed: submitted || (!completed && !q.isAvailable)
                          ? null
                          : () async {
                              await Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                      builder: (_) =>
                                          completed && q.attemptId != null
                                              ? QuizResultScreen(
                                                  attemptId: q.attemptId!)
                                              : QuizDetailsScreen(quiz: q)));
                              if (mounted) await _load();
                            },
                      child: Text(label)),
                ]))));
  }

  Widget _homeworkCard(HomeworkAssignment h) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
          container: true,
          child: LearnerSurface(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(h.title, style: AppTheme.titleMedium),
                const SizedBox(height: 4),
                Text(h.classTitle),
                Text(MissionContentData.homeworkDue(manilaDate(h.deadline)),
                    style: AppTheme.bodySmall),
                Text(h.statusLabel),
                if (h.submission == null && h.deadlinePassed)
                  const Text(MissionContentData.homeworkLateAllowed),
                if ((h.submission?.latenessSeconds ?? 0) > 0)
                  Text(MissionContentData.homeworkLateBy(
                      latenessDuration(h.submission!.latenessSeconds))),
                const SizedBox(height: 8),
                OutlinedButton(
                    onPressed: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) =>
                                  HomeworkDetailsScreen(assignment: h)));
                      if (mounted) await _load();
                    },
                    child: const Text(MissionContentData.homeworkView)),
              ]))));
}
