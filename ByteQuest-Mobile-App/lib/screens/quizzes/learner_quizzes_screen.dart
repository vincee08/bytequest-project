import 'package:flutter/material.dart';
import '../../models/homework_model.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../models/learner_quiz_model.dart';
import '../../data/mission_content_data.dart';
import '../../data/quiz_content_data.dart';
import '../../services/learner_quiz_service.dart';
import '../../services/learner_realtime_coordinator.dart';
import 'quiz_details_screen.dart';
import 'quiz_result_screen.dart';
import 'quiz_status_label.dart';

class LearnerQuizzesScreen extends StatefulWidget {
  const LearnerQuizzesScreen({super.key, this.service});
  final LearnerQuizService? service;

  @override
  State<LearnerQuizzesScreen> createState() => _LearnerQuizzesScreenState();
}

class _LearnerQuizzesScreenState extends State<LearnerQuizzesScreen>
    with LearnerRealtimeRefreshMixin<LearnerQuizzesScreen> {
  late final LearnerQuizService _service =
      widget.service ?? LearnerQuizService();
  List<LearnerQuizSummary> _quizzes = const [];
  bool _loading = true;
  String? _error;

  @override
  Set<LearnerRealtimeDomain> get realtimeDomains => const {
        LearnerRealtimeDomain.quizzes,
      };

  @override
  Future<void> refreshFromRealtime() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final quizzes = await _service.getAvailableQuizzes();
      if (!mounted) return;
      setState(() {
        _quizzes = quizzes;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Learner quiz list failed: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = QuizContentData.listUnavailable;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTheme.backgroundOffWhite,
        body: SafeArea(
          child: _loading
              ? const LearnerLoadingView(label: QuizContentData.listLoading)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                    children: [
                      LearnerPageHeader(
                        title: QuizContentData.listTitle,
                        subtitle: QuizContentData.listSubtitle,
                        padding: EdgeInsets.zero,
                        trailing: IconButton.filledTonal(
                          onPressed: () => Navigator.pop(context),
                          tooltip: QuizContentData.listClose,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      LearnerSurface(
                        color: AppTheme.backgroundPaleBlue,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                color: AppTheme.primaryBlue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                QuizContentData.listNotice,
                                style: AppTheme.bodySmall.copyWith(
                                  color: AppTheme.deepBlue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_error != null)
                        LearnerStateView(
                          icon: Icons.cloud_off_outlined,
                          title: QuizContentData.listUnavailableTitle,
                          message: _error!,
                          actionLabel: QuizContentData.tryAgain,
                          onAction: _load,
                        )
                      else if (_quizzes.isEmpty)
                        const LearnerStateView(
                          icon: Icons.quiz_outlined,
                          title: QuizContentData.listEmptyTitle,
                          message: QuizContentData.listEmptyMessage,
                        )
                      else
                        ..._quizzes.map(_buildQuizCard),
                    ],
                  ),
                ),
        ),
      );

  Widget _buildQuizCard(LearnerQuizSummary quiz) {
    final state = quiz.state;
    final color = _stateColor(quiz);
    final status = quizStatusLabel(quiz);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LearnerSurface(
        onTap: () => _open(quiz),
        semanticLabel: QuizContentData.cardSemantics(
            quiz.title, status, quiz.questionCount),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                      quiz.isAutoSubmitted
                          ? Icons.timer_off_outlined
                          : Icons.quiz_outlined,
                      color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(quiz.title, style: AppTheme.titleMedium),
                      const SizedBox(height: 3),
                      Text('${quiz.classTitle} · ${quiz.topic}',
                          style: AppTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _QuizStatus(label: status, color: color),
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Meta(
                  icon: Icons.format_list_numbered_rounded,
                  label: QuizContentData.questionsCount(quiz.questionCount),
                ),
                if (quiz.timeLimitMinutes != null)
                  _Meta(
                    icon: Icons.timer_outlined,
                    label: QuizContentData.timeLimit(quiz.timeLimitMinutes!),
                  ),
                if (quiz.dueAt != null)
                  _Meta(
                    icon: Icons.event_outlined,
                    label:
                        MissionContentData.homeworkDue(manilaDate(quiz.dueAt)),
                  ),
              ],
            ),
            if (state == LearnerQuizState.inProgress) ...[
              const SizedBox(height: 12),
              LearnerProgressBar(
                value: quiz.questionCount == 0
                    ? 0
                    : quiz.answeredCount / quiz.questionCount,
                semanticLabel: QuizContentData.answerProgressLabel,
              ),
              const SizedBox(height: 6),
              Text(
                  QuizContentData.answeredProgress(
                      quiz.answeredCount, quiz.questionCount),
                  style: AppTheme.labelSmall),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _open(LearnerQuizSummary quiz) async {
    if (quizOpensResult(quiz)) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              QuizResultScreen(attemptId: quiz.attemptId!, service: _service),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => QuizDetailsScreen(quiz: quiz, service: _service)),
      );
    }
    if (mounted) await _load();
  }

  Color _stateColor(LearnerQuizSummary quiz) {
    if (quiz.resultReleased) return AppTheme.accentGreen;
    if (quiz.awaitingEvaluation) return AppTheme.accentPurple;
    return switch (quiz.state) {
      LearnerQuizState.available => AppTheme.primaryBlue,
      LearnerQuizState.inProgress => AppTheme.accentOrange,
      LearnerQuizState.submitted => AppTheme.accentPurple,
      LearnerQuizState.completed => AppTheme.accentGreen,
      LearnerQuizState.unavailable => AppTheme.textMedium,
    };
  }
}

class _QuizStatus extends StatelessWidget {
  const _QuizStatus({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: AppTheme.labelSmall.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppTheme.textMedium),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                style: AppTheme.labelMedium, overflow: TextOverflow.ellipsis),
          ),
        ],
      );
}
