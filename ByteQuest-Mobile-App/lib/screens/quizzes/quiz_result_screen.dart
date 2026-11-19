import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../data/quiz_content_data.dart';
import '../../models/learner_quiz_model.dart';
import '../../services/learner_quiz_service.dart';
import '../../services/learner_realtime_coordinator.dart';

class QuizResultScreen extends StatefulWidget {
  const QuizResultScreen({
    super.key,
    required this.attemptId,
    this.initialResult,
    this.service,
  });

  final String attemptId;
  final LearnerQuizResult? initialResult;
  final LearnerQuizService? service;

  @override
  State<QuizResultScreen> createState() => _QuizResultScreenState();
}

class _QuizResultScreenState extends State<QuizResultScreen>
    with LearnerRealtimeRefreshMixin<QuizResultScreen> {
  late final LearnerQuizService _service =
      widget.service ?? LearnerQuizService();
  LearnerQuizResult? _result;
  String? _error;

  @override
  Set<LearnerRealtimeDomain> get realtimeDomains => const {
        LearnerRealtimeDomain.quizzes,
      };

  /// A release by the Instructor arrives as a realtime quiz event.
  @override
  Future<void> refreshFromRealtime() => _load();

  @override
  void initState() {
    super.initState();
    _result = widget.initialResult;
    if (_result == null) _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final result = await _service.getResult(widget.attemptId);
      if (mounted) setState(() => _result = result);
    } catch (error) {
      debugPrint('Quiz result load failed: $error');
      if (mounted) {
        setState(() => _error = QuizContentData.resultUnavailable);
      }
    }
  }

  static String _when(DateTime value) =>
      DateFormat.MMMd().add_jm().format(value.toLocal());

  @override
  Widget build(BuildContext context) {
    if (_result == null && _error == null) {
      return const Scaffold(
        body: SafeArea(
            child: LearnerLoadingView(label: QuizContentData.resultLoading)),
      );
    }
    if (_result == null) {
      return Scaffold(
        body: SafeArea(
          child: LearnerStateView(
            icon: Icons.schedule_rounded,
            title: QuizContentData.resultUnavailableTitle,
            message: _error!,
            actionLabel: QuizContentData.tryAgain,
            onAction: _load,
          ),
        ),
      );
    }

    final result = _result!;
    return Scaffold(
      backgroundColor: AppTheme.backgroundOffWhite,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            children: [
              LearnerPageHeader(
                title: QuizContentData.resultTitle,
                subtitle: result.classTitle,
                padding: EdgeInsets.zero,
                trailing: IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  tooltip: QuizContentData.resultClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              const SizedBox(height: 18),
              result.awaitingEvaluation
                  ? _AwaitingCard(result: result, when: _when)
                  : _ScoreCard(result: result, when: _when),
              if (result.isAutoSubmitted) ...[
                const SizedBox(height: 12),
                _AutoSubmittedBanner(result: result, when: _when),
              ],
              const SizedBox(height: 14),
              LearnerSurface(
                color: AppTheme.backgroundPaleBlue,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.verified_user_outlined,
                        color: AppTheme.primaryBlue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        QuizContentData.supplementaryNotice,
                        style: AppTheme.bodySmall
                            .copyWith(color: AppTheme.deepBlue),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              LearnerSectionHeader(
                title: result.awaitingEvaluation
                    ? QuizContentData.submittedAnswersHeading
                    : QuizContentData.feedbackHeading,
                supportingText: result.awaitingEvaluation
                    ? QuizContentData.submittedAnswersSupporting
                    : QuizContentData.feedbackSupporting,
              ),
              const SizedBox(height: 10),
              ...result.items.map((item) => _ItemCard(
                    item: item,
                    awaiting: result.awaitingEvaluation,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.result, required this.when});
  final LearnerQuizResult result;
  final String Function(DateTime) when;

  @override
  Widget build(BuildContext context) {
    final usesPoints = result.maxPoints != null;
    final score = QuizContentData.formatPoints(result.displayScore);
    final max = QuizContentData.formatPoints(result.displayMax);
    return Semantics(
      container: true,
      label: QuizContentData.resultSemantics(result.title, score, max),
      child: ExcludeSemantics(
        child: LearnerSurface(
          elevated: true,
          color: AppTheme.deepBlue,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.released
                    ? QuizContentData.resultReleased
                    : QuizContentData.resultCompleted,
                style: AppTheme.labelMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                ),
              ),
              const SizedBox(height: 10),
              Text(result.title,
                  style: AppTheme.headlineLarge.copyWith(color: Colors.white)),
              const SizedBox(height: 18),
              Text(
                QuizContentData.scoreOf(score, max),
                key: const ValueKey('quiz-result-score'),
                style: AppTheme.displaySmall.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                usesPoints
                    ? QuizContentData.pointsLabel
                    : QuizContentData.correctLabel,
                style: AppTheme.bodyMedium.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 14),
              Text(
                result.released && result.releasedAt != null
                    ? QuizContentData.releasedAt(when(result.releasedAt!))
                    : QuizContentData.completedAt(when(result.completedAt)),
                style: AppTheme.labelMedium.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AwaitingCard extends StatelessWidget {
  const _AwaitingCard({required this.result, required this.when});
  final LearnerQuizResult result;
  final String Function(DateTime) when;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: QuizContentData.awaitingSemantics(result.title),
        child: LearnerSurface(
          elevated: true,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                QuizContentData.resultSubmitted,
                style: AppTheme.labelMedium.copyWith(
                  color: AppTheme.deepBlue,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                ),
              ),
              const SizedBox(height: 10),
              Text(result.title, style: AppTheme.headlineLarge),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.hourglass_top_rounded,
                      color: AppTheme.accentPurple),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      QuizContentData.statusAwaitingEvaluation,
                      style: AppTheme.titleMedium
                          .copyWith(color: AppTheme.accentPurple),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(QuizContentData.awaitingMessage, style: AppTheme.bodyMedium),
              const SizedBox(height: 12),
              Text(
                QuizContentData.answeredCount(
                    result.answeredCount, result.questionCount),
                style: AppTheme.labelMedium,
              ),
              if (result.submittedAt != null) ...[
                const SizedBox(height: 4),
                Text(QuizContentData.submittedAt(when(result.submittedAt!)),
                    style: AppTheme.labelMedium),
              ],
            ],
          ),
        ),
      );
}

class _AutoSubmittedBanner extends StatelessWidget {
  const _AutoSubmittedBanner({required this.result, required this.when});
  final LearnerQuizResult result;
  final String Function(DateTime) when;

  @override
  Widget build(BuildContext context) {
    final title = result.submissionKind == 'auto_time_limit'
        ? QuizContentData.autoSubmittedTimeLimit
        : QuizContentData.autoSubmittedDeadline;
    final at = result.submittedAt ?? result.completedAt;
    return Semantics(
      container: true,
      label: '$title. ${QuizContentData.autoSubmittedAt(when(at))}',
      child: ExcludeSemantics(
        child: LearnerSurface(
          color: AppTheme.accentOrange.withValues(alpha: .07),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.timer_off_outlined,
                  color: AppTheme.accentOrange),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        key: const ValueKey('quiz-auto-submitted'),
                        style: AppTheme.titleMedium
                            .copyWith(color: AppTheme.accentOrange)),
                    const SizedBox(height: 2),
                    Text(QuizContentData.autoSubmittedAt(when(at)),
                        style: AppTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.awaiting});
  final LearnerQuizItemResult item;
  final bool awaiting;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = !item.answered
        ? (
            QuizContentData.itemNotAnswered,
            AppTheme.textMedium,
            Icons.remove_circle_outline_rounded
          )
        : awaiting
            ? (
                QuizContentData.itemSubmitted,
                AppTheme.primaryBlue,
                Icons.task_alt_rounded
              )
            : item.isEssay
                ? (
                    QuizContentData.itemPoints(
                        item.pointsAwarded ?? 0, item.points ?? 0),
                    AppTheme.deepBlue,
                    Icons.rate_review_outlined
                  )
                : item.isCorrect
                    ? (
                        QuizContentData.itemCorrect,
                        AppTheme.accentGreen,
                        Icons.check_circle_outline_rounded
                      )
                    : (
                        QuizContentData.itemNeedsReview,
                        AppTheme.accentOrange,
                        Icons.info_outline_rounded
                      );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LearnerSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(child: Text(item.prompt, style: AppTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: AppTheme.labelMedium.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(QuizContentData.answerLabel, style: AppTheme.labelMedium),
            const SizedBox(height: 3),
            Text(
              item.answered && item.learnerAnswer.isNotEmpty
                  ? item.learnerAnswer
                  : QuizContentData.notAnsweredText,
              style: AppTheme.bodyMedium,
            ),
            if (!awaiting && item.isEssay && item.rubric.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(QuizContentData.rubricScores,
                  style: AppTheme.labelMedium
                      .copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final criterion in item.rubric)
                _CriterionRow(criterion: criterion),
            ],
            if (!awaiting && (item.feedback?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundPaleBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(QuizContentData.instructorFeedback,
                        style: AppTheme.labelMedium
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(item.feedback!,
                        key: ValueKey('quiz-feedback-${item.itemId}'),
                        style: AppTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CriterionRow extends StatelessWidget {
  const _CriterionRow({required this.criterion});
  final LearnerQuizRubricCriterion criterion;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(criterion.criterion, style: AppTheme.bodyMedium),
                  if (criterion.description != null)
                    Text(criterion.description!, style: AppTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              QuizContentData.itemPoints(
                  criterion.points ?? 0, criterion.maxPoints),
              style: AppTheme.labelMedium.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
}
