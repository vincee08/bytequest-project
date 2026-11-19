import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../core/widgets/supplementary_platform_notice.dart';
import '../../data/learning_content_data.dart';
import '../../models/assigned_activity_model.dart';
import '../../models/curriculum_model.dart';
import '../../models/homework_model.dart';
import '../../models/learner_quiz_model.dart';
import '../../services/authoritative_assessment_service.dart';
import '../../services/curriculum_service.dart';
import '../../services/homework_service.dart';
import '../../services/learner_quiz_service.dart';
import '../../services/learner_realtime_coordinator.dart';
import '../learn/curriculum_widgets.dart';
import 'attempt_history_screen.dart';

/// Data sources for the Progress tab. Learning progress comes only from the
/// server curriculum projection; performance (released results, quiz scores,
/// homework) comes from the existing services and is never mixed into it.
class ProgressSources {
  const ProgressSources({
    required this.curriculum,
    required this.releasedResults,
    required this.attemptCounts,
    required this.quizzes,
    required this.quizResult,
    required this.homework,
  });

  final Future<CurriculumProjection> Function() curriculum;
  final Future<List<ReleasedAssessmentResult>> Function() releasedResults;
  final Future<Map<String, int>> Function() attemptCounts;
  final Future<List<LearnerQuizSummary>> Function() quizzes;
  final Future<LearnerQuizResult> Function(String attemptId) quizResult;
  final Future<List<HomeworkAssignment>> Function() homework;

  factory ProgressSources.live() {
    final assessment = AuthoritativeAssessmentService.instance;
    return ProgressSources(
      curriculum: () => CurriculumService().getCurriculum(),
      releasedResults: assessment.getReleasedResults,
      attemptCounts: assessment.getAttemptStatusCounts,
      quizzes: () => LearnerQuizService().getAvailableQuizzes(),
      quizResult: (attemptId) => LearnerQuizService().getResult(attemptId),
      homework: () => HomeworkService().getAssignments(),
    );
  }
}

class _QuizScore {
  const _QuizScore(this.quiz, this.result);
  final LearnerQuizSummary quiz;
  final LearnerQuizResult? result;
}

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, this.sources, this.performanceSection});

  final ProgressSources? sources;

  /// Slot for the learner "Performance" section (slice A7 adds
  /// lib/screens/progress/performance_* and passes its widget here).
  final Widget? performanceSection;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen>
    with LearnerRealtimeRefreshMixin<ProgressScreen> {
  late final ProgressSources _sources =
      widget.sources ?? ProgressSources.live();
  CurriculumProjection? _curriculum;
  List<ReleasedAssessmentResult>? _results;
  Map<String, int> _attemptCounts = const {};
  List<_QuizScore>? _quizzes;
  int _openQuizzes = 0;
  List<HomeworkAssignment>? _homework;
  bool _curriculumFailed = false,
      _resultsFailed = false,
      _quizzesFailed = false,
      _homeworkFailed = false;
  bool _loading = true, _fetching = false, _active = false;

  @override
  Set<LearnerRealtimeDomain> get realtimeDomains => const {
        LearnerRealtimeDomain.assessment,
        LearnerRealtimeDomain.progress,
        LearnerRealtimeDomain.learning,
        LearnerRealtimeDomain.quizzes,
      };

  @override
  Future<void> refreshFromRealtime() => _load();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (active && !_active && !_loading) unawaited(_load());
    _active = active;
  }

  Future<T?> _try<T>(
      Future<T> Function() load, void Function() onFailure) async {
    try {
      return await load();
    } catch (_) {
      onFailure();
      return null;
    }
  }

  Future<void> _load() async {
    if (_fetching) return;
    _fetching = true;
    var curriculumFailed = false,
        resultsFailed = false,
        quizzesFailed = false,
        homeworkFailed = false;
    final values = await Future.wait<Object?>([
      _try(_sources.curriculum, () => curriculumFailed = true),
      _try(_sources.releasedResults, () => resultsFailed = true),
      _try(_sources.attemptCounts, () {}),
      _try(_sources.quizzes, () => quizzesFailed = true),
      _try(_sources.homework, () => homeworkFailed = true),
    ]);
    final quizzes = values[3] as List<LearnerQuizSummary>?;
    List<_QuizScore>? scores;
    if (quizzes != null) {
      final completed = quizzes
          .where((quiz) =>
              quiz.state == LearnerQuizState.completed &&
              quiz.attemptId != null)
          .take(12)
          .toList(growable: false);
      scores = await Future.wait(completed.map((quiz) async => _QuizScore(quiz,
          await _try(() => _sources.quizResult(quiz.attemptId!), () {}))));
    }
    if (mounted) {
      setState(() {
        _curriculum = values[0] as CurriculumProjection? ?? _curriculum;
        _results = values[1] as List<ReleasedAssessmentResult>? ??
            (resultsFailed ? _results : const []);
        _attemptCounts = values[2] as Map<String, int>? ?? _attemptCounts;
        _quizzes = scores ?? (quizzesFailed ? _quizzes : const []);
        _openQuizzes = quizzes
                ?.where((quiz) =>
                    quiz.state == LearnerQuizState.available ||
                    quiz.state == LearnerQuizState.inProgress)
                .length ??
            _openQuizzes;
        _homework = values[4] as List<HomeworkAssignment>? ??
            (homeworkFailed ? _homework : const []);
        _curriculumFailed = curriculumFailed;
        _resultsFailed = resultsFailed;
        _quizzesFailed = quizzesFailed;
        _homeworkFailed = homeworkFailed;
        _loading = false;
      });
    }
    _fetching = false;
  }

  int get _pendingCount {
    const pending = {'submitted', 'evaluated', 'under_review', 'finalized'};
    return _attemptCounts.entries
        .where((entry) => pending.contains(entry.key))
        .fold(0, (sum, entry) => sum + entry.value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTheme.backgroundOffWhite,
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: _loading
                  ? const LearnerLoadingView(
                      label: LearningContentData.loadingCurriculum)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                        children: [
                          const LearnerPageHeader(
                            title: LearningContentData.progressTitle,
                            subtitle: LearningContentData.progressSubtitle,
                            padding: EdgeInsets.fromLTRB(0, 18, 0, 14),
                            trailing: MethodologyButton(),
                          ),
                          ..._learningSection(),
                          const SizedBox(height: 22),
                          // Performance (slice A7: lib/screens/progress/performance_*).
                          if (widget.performanceSection != null) ...[
                            const _SectionHeader(
                                LearningContentData.performanceTitle),
                            widget.performanceSection!,
                            const SizedBox(height: 22),
                          ],
                          ..._resultsSection(),
                          const SizedBox(height: 22),
                          ..._quizSection(),
                          const SizedBox(height: 22),
                          ..._homeworkSection(),
                          const SizedBox(height: 22),
                          const _MessageCard(
                              icon: Icons.stars_outlined,
                              message: LearningContentData.motivationNote),
                          const SizedBox(height: 12),
                          const SupplementaryPlatformNotice(),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      );

  List<Widget> _learningSection() {
    final data = _curriculum;
    if (data == null) {
      return [
        const _SectionHeader(LearningContentData.overallTitle),
        _MessageCard(
          icon: Icons.cloud_off_outlined,
          message: LearningContentData.curriculumUnavailable,
          actionLabel: LearningContentData.retry,
          onAction: _load,
        ),
      ];
    }
    return [
      const _SectionHeader(LearningContentData.overallTitle),
      Text(LearningContentData.overallNote,
          style: AppTheme.bodySmall.copyWith(color: AppTheme.textMedium)),
      const SizedBox(height: 10),
      if (_curriculumFailed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(LearningContentData.curriculumUnavailable,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.errorRed)),
        ),
      LearnerSurface(
        key: const ValueKey('progress-overall'),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final coc in data.cocs) ...[
            Row(children: [
              Expanded(
                child: Text(
                    '${LearningContentData.cocLabel(coc.number)} · ${coc.title}',
                    style: AppTheme.labelLarge
                        .copyWith(fontWeight: FontWeight.w700)),
              ),
              if (!coc.unlocked)
                const Icon(Icons.lock_outline_rounded,
                    size: 18, color: AppTheme.textMedium)
              else if (coc.completed)
                const Icon(Icons.check_circle_rounded,
                    size: 18, color: AppTheme.accentGreen),
            ]),
            const SizedBox(height: 6),
            CurriculumProgressSummary(
              progress: coc.progress,
              completed: coc.completed,
              semanticLabel:
                  '${LearningContentData.cocLabel(coc.number)}, ${LearningContentData.progressValue(coc.progress.done, coc.progress.total)}',
            ),
            const SizedBox(height: 12),
          ],
          const Divider(height: 8),
          const SizedBox(height: 8),
          Text(
              LearningContentData.modulesCompleted(
                  data.modulesCompleted, data.modules.length),
              style: AppTheme.bodySmall),
          Text(
              LearningContentData.topicsSummary(
                  data.topicsCompleted, data.topicsTotal),
              style: AppTheme.bodySmall),
          Text(
              LearningContentData.missionsSummary(
                  data.missionsVerified, data.missionsTotal),
              style: AppTheme.bodySmall),
          Text(LearningContentData.runsSummary(data.totalRuns),
              style: AppTheme.bodySmall),
        ]),
      ),
      const SizedBox(height: 16),
      const _SectionHeader(LearningContentData.cocBreakdownTitle),
      for (final coc in data.cocs)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            elevation: 0,
            color: AppTheme.cardWhite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.borderLight),
            ),
            child: ExpansionTile(
              key: PageStorageKey('progress-${coc.cocCode}'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              title: Text(
                  '${LearningContentData.cocLabel(coc.number)} · ${coc.title}',
                  style: AppTheme.titleMedium
                      .copyWith(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  LearningContentData.modulesCompleted(
                      coc.modulesCompleted, coc.modules.length),
                  style: AppTheme.bodySmall),
              children: [
                for (final module in coc.modules)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                              LearningContentData.moduleLabel(
                                  module.sequenceOrder, module.code),
                              style: AppTheme.labelSmall
                                  .copyWith(color: AppTheme.textMedium)),
                          Text(module.title,
                              style: AppTheme.labelLarge
                                  .copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            CurriculumStatusPill(
                              label: moduleStateLabel(module),
                              icon: !module.unlocked
                                  ? Icons.lock_outline_rounded
                                  : module.completed
                                      ? Icons.check_circle_rounded
                                      : Icons.timelapse_rounded,
                              color: module.completed
                                  ? AppTheme.accentGreen
                                  : module.unlocked
                                      ? AppTheme.primaryBlue
                                      : AppTheme.textMedium,
                            ),
                            if (module.noRequiredItems)
                              const CurriculumStatusPill(
                                  label: LearningContentData.noRequiredItems,
                                  icon: Icons.info_outline,
                                  color: AppTheme.textMedium),
                          ]),
                          if (!module.noRequiredItems) ...[
                            const SizedBox(height: 4),
                            Text(
                                LearningContentData.topicsSummary(
                                    module.topicsCompleted,
                                    module.topics.length),
                                style: AppTheme.bodySmall),
                            Text(
                                LearningContentData.missionsSummary(
                                    module.missionsVerified,
                                    module.missions.length),
                                style: AppTheme.bodySmall),
                            for (final mission in module.missions)
                              Text(
                                '${LearningContentData.missionNumber(mission.missionNumber)} · '
                                '${mission.verified ? LearningContentData.missionVerified : LearningContentData.missionNotVerified} · '
                                '${LearningContentData.missionRuns(mission.runs)}'
                                '${mission.bestSeconds == null ? '' : ' · ${LearningContentData.missionBest(LearningContentData.formatDuration(mission.bestSeconds!))}'}',
                                style: AppTheme.bodySmall
                                    .copyWith(color: AppTheme.textMedium),
                              ),
                          ],
                        ]),
                  ),
                Text(
                  coc.quiz.passed
                      ? LearningContentData.cocQuizPassed
                      : coc.quiz.eligible
                          ? LearningContentData.cocQuizReady
                          : LearningContentData.cocQuizPending(coc.number),
                  style:
                      AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _resultsSection() {
    final results = _results;
    return [
      const _SectionHeader(LearningContentData.resultsTitle),
      _AuthorityNotice(pendingCount: _pendingCount),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => const AttemptHistoryScreen())),
          icon: const Icon(Icons.history_rounded),
          label: const Text(LearningContentData.attemptHistory),
        ),
      ),
      const SizedBox(height: 10),
      if (results == null || (_resultsFailed && results.isEmpty))
        _MessageCard(
            icon: Icons.cloud_off_outlined,
            message: LearningContentData.resultsFailed,
            actionLabel: LearningContentData.retry,
            onAction: _load)
      else if (results.isEmpty)
        const _MessageCard(
            icon: Icons.verified_outlined,
            message: LearningContentData.resultsEmpty)
      else
        for (final result in results) _ResultCard(result: result),
    ];
  }

  List<Widget> _quizSection() {
    final quizzes = _quizzes;
    return [
      const _SectionHeader(LearningContentData.quizScoresTitle),
      if (quizzes == null || (_quizzesFailed && quizzes.isEmpty))
        _MessageCard(
            icon: Icons.cloud_off_outlined,
            message: LearningContentData.quizScoresFailed,
            actionLabel: LearningContentData.retry,
            onAction: _load)
      else ...[
        Text(LearningContentData.quizStatusCounts(quizzes.length, _openQuizzes),
            style: AppTheme.bodySmall),
        const SizedBox(height: 8),
        if (quizzes.isEmpty)
          const _MessageCard(
              icon: Icons.quiz_outlined,
              message: LearningContentData.quizScoresEmpty)
        else
          for (final score in quizzes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LearnerSurface(
                semanticLabel:
                    '${score.quiz.title}, ${score.result == null ? LearningContentData.quizScorePending : LearningContentData.quizScore(score.result!.correctCount, score.result!.questionCount)}',
                child: Row(children: [
                  const Icon(Icons.quiz_outlined, color: AppTheme.primaryBlue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(score.quiz.title,
                              style: AppTheme.labelLarge
                                  .copyWith(fontWeight: FontWeight.w700)),
                          Text(score.quiz.classTitle,
                              style: AppTheme.bodySmall),
                        ]),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    score.result == null
                        ? LearningContentData.quizScorePending
                        : LearningContentData.quizScore(
                            score.result!.correctCount,
                            score.result!.questionCount),
                    style: AppTheme.labelMedium
                        .copyWith(fontWeight: FontWeight.w800),
                  ),
                ]),
              ),
            ),
      ],
    ];
  }

  List<Widget> _homeworkSection() {
    final homework = _homework;
    final assigned =
        homework?.where((item) => item.submission == null).length ?? 0;
    final graded =
        homework?.where((item) => item.submission?.status == 'graded').length ??
            0;
    final submitted =
        (homework?.where((item) => item.submission != null).length ?? 0) -
            graded;
    return [
      const _SectionHeader(LearningContentData.homeworkTitle),
      if (homework == null || (_homeworkFailed && homework.isEmpty))
        _MessageCard(
            icon: Icons.cloud_off_outlined,
            message: LearningContentData.homeworkFailed,
            actionLabel: LearningContentData.retry,
            onAction: _load)
      else if (homework.isEmpty)
        const _MessageCard(
            icon: Icons.assignment_outlined,
            message: LearningContentData.homeworkEmpty)
      else ...[
        Text(LearningContentData.homeworkCounts(assigned, submitted, graded),
            style: AppTheme.bodySmall),
        const SizedBox(height: 8),
        for (final item in homework)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LearnerSurface(
              semanticLabel: '${item.title}, ${item.statusLabel}',
              child: Row(children: [
                Icon(
                    item.submission?.status == 'graded'
                        ? Icons.grading_rounded
                        : Icons.assignment_outlined,
                    color: AppTheme.primaryBlue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            style: AppTheme.labelLarge
                                .copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          [
                            item.classTitle,
                            item.statusLabel,
                            if ((item.submission?.latenessSeconds ?? 0) > 0)
                              LearningContentData.homeworkLate,
                          ].join(' · '),
                          style: AppTheme.bodySmall,
                        ),
                      ]),
                ),
                if (item.submission?.status == 'graded' &&
                    item.submission?.score != null) ...[
                  const SizedBox(width: 8),
                  Text(
                      LearningContentData.homeworkScore(
                          '${item.submission!.score}'),
                      style: AppTheme.labelMedium
                          .copyWith(fontWeight: FontWeight.w800)),
                ],
              ]),
            ),
          ),
      ],
    ];
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          header: true,
          child: Text(title,
              style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w800)),
        ),
      );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final ReleasedAssessmentResult result;

  String _readable(String value) => value
      .split('_')
      .map((part) => part.isEmpty
          ? part
          : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
      .join(' ');

  @override
  Widget build(BuildContext context) {
    final outcome = _readable(result.outcome);
    final satisfied =
        result.criteria.where((criterion) => criterion.isSatisfied).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        container: true,
        label:
            '${result.assignmentTitle}, ${LearningContentData.instructorFinal} $outcome, '
            '${LearningContentData.criteriaSatisfied(satisfied, result.criteria.length)}',
        child: LearnerSurface(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(result.assignmentTitle,
                style:
                    AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(
              [
                result.classTitle,
                if (result.cocCode != null) result.cocCode!.toUpperCase(),
                if (result.missionTitle != null) result.missionTitle!,
              ].join(' · '),
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textMedium),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              CurriculumStatusPill(
                  label: outcome,
                  icon: Icons.verified_outlined,
                  color: AppTheme.accentGreen),
              const CurriculumStatusPill(
                  label: LearningContentData.instructorFinal,
                  icon: Icons.policy_outlined),
              if (result.criteria.isNotEmpty)
                CurriculumStatusPill(
                    label: LearningContentData.criteriaSatisfied(
                        satisfied, result.criteria.length),
                    icon: Icons.fact_check_outlined),
              if (result.percentage != null)
                CurriculumStatusPill(
                    label: '${result.percentage}%',
                    icon: Icons.percent_rounded),
              CurriculumStatusPill(
                  label: LearningContentData.releasedOn(
                      DateFormat.yMMMd().format(result.releasedAt.toLocal())),
                  icon: Icons.event_available_outlined),
            ]),
            if (result.remarks?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: 10),
              Text(result.remarks!,
                  style: AppTheme.bodyMedium.copyWith(height: 1.45)),
            ],
            if (result.criteria.isNotEmpty)
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(LearningContentData.criterionFeedback,
                      style: AppTheme.labelLarge
                          .copyWith(fontWeight: FontWeight.w800)),
                  subtitle: Text(LearningContentData.criterionFeedbackDetail,
                      style: AppTheme.bodySmall),
                  children: [
                    for (final criterion in result.criteria)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                  criterion.isSatisfied
                                      ? Icons.check_circle_outline
                                      : Icons.error_outline,
                                  size: 20,
                                  color: criterion.isSatisfied
                                      ? AppTheme.accentGreen
                                      : AppTheme.warningYellow),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${criterion.code} · ${criterion.title}\n'
                                  '${criterion.isSatisfied ? LearningContentData.satisfied : LearningContentData.notSatisfied}',
                                  style: AppTheme.bodySmall,
                                ),
                              ),
                            ]),
                      ),
                  ],
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _AuthorityNotice extends StatelessWidget {
  const _AuthorityNotice({required this.pendingCount});
  final int pendingCount;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppTheme.primaryBlue, borderRadius: AppTheme.radiusLg),
        child: Row(children: [
          const Icon(Icons.policy_outlined, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                pendingCount == 0
                    ? LearningContentData.pendingNone
                    : LearningContentData.pendingCount(pendingCount),
                style: AppTheme.titleMedium
                    .copyWith(color: Colors.white, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                pendingCount == 0
                    ? LearningContentData.pendingDetailNone
                    : LearningContentData.pendingDetail,
                style: AppTheme.bodySmall.copyWith(color: Colors.white),
              ),
            ]),
          ),
        ]),
      );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard(
      {required this.icon,
      required this.message,
      this.actionLabel,
      this.onAction});
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => LearnerSurface(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: AppTheme.textMedium),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message,
                  style: AppTheme.bodyMedium
                      .copyWith(color: AppTheme.textMedium, height: 1.45)),
            ),
          ]),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel!),
              ),
            ),
          ],
        ]),
      );
}
