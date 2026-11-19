import 'package:flutter/material.dart';
import '../../models/homework_model.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../models/learner_quiz_model.dart';
import '../../data/mission_content_data.dart';
import '../../data/quiz_content_data.dart';
import '../../services/learner_quiz_service.dart';
import 'quiz_result_screen.dart';
import 'quiz_status_label.dart';
import 'quiz_taking_screen.dart';

class QuizDetailsScreen extends StatefulWidget {
  const QuizDetailsScreen({super.key, required this.quiz, this.service});
  final LearnerQuizSummary quiz;
  final LearnerQuizService? service;

  @override
  State<QuizDetailsScreen> createState() => _QuizDetailsScreenState();
}

class _QuizDetailsScreenState extends State<QuizDetailsScreen> {
  late final LearnerQuizService _service =
      widget.service ?? LearnerQuizService();
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final quiz = widget.quiz;
    final typeLabel = quizTypeLabel(quiz.quizType);
    final canStart = quiz.isAvailable &&
        !_starting &&
        (quiz.state == LearnerQuizState.available ||
            quiz.state == LearnerQuizState.inProgress);
    return Scaffold(
      backgroundColor: AppTheme.backgroundOffWhite,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            LearnerPageHeader(
              title: QuizContentData.briefingTitle,
              subtitle: quiz.classTitle,
              padding: EdgeInsets.zero,
              trailing: IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                tooltip: QuizContentData.briefingClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            const SizedBox(height: 18),
            LearnerSurface(
              elevated: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.softBlueAccent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.quiz_outlined,
                        color: AppTheme.primaryBlue),
                  ),
                  const SizedBox(height: 16),
                  Text(quiz.title, style: AppTheme.headlineLarge),
                  const SizedBox(height: 6),
                  Text(quiz.description ?? quiz.topic,
                      style: AppTheme.bodyMedium),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      _Fact(
                        icon: Icons.format_list_numbered_rounded,
                        label:
                            QuizContentData.questionsCount(quiz.questionCount),
                      ),
                      if (quiz.cocCode != null)
                        _Fact(
                          icon: Icons.route_outlined,
                          label: [
                            quiz.cocCode!.toUpperCase(),
                            ...quiz.moduleCodes,
                          ].join(' · '),
                        ),
                      if (typeLabel != null)
                        _Fact(icon: Icons.category_outlined, label: typeLabel),
                      if (quiz.hasEssays)
                        _Fact(
                          icon: Icons.edit_note_rounded,
                          label: QuizContentData.essaysCount(quiz.essayCount),
                        ),
                      if (quiz.timeLimitMinutes != null)
                        _Fact(
                          icon: Icons.timer_outlined,
                          label:
                              QuizContentData.timeLimit(quiz.timeLimitMinutes!),
                        ),
                      if (quiz.dueAt != null)
                        _Fact(
                          icon: Icons.event_outlined,
                          label: MissionContentData.homeworkDue(
                              manilaDate(quiz.dueAt)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (quiz.focus?.isNotEmpty ?? false) ...[
              const SizedBox(height: 20),
              const LearnerSectionHeader(title: QuizContentData.focusHeading),
              const SizedBox(height: 10),
              LearnerSurface(
                  child: Text(quiz.focus!, style: AppTheme.bodyMedium)),
            ],
            if (quiz.instructions?.isNotEmpty ?? false) ...[
              const SizedBox(height: 20),
              const LearnerSectionHeader(title: QuizContentData.instructions),
              const SizedBox(height: 10),
              LearnerSurface(
                child: Text(quiz.instructions!, style: AppTheme.bodyMedium),
              ),
            ],
            const SizedBox(height: 20),
            LearnerSurface(
              color: AppTheme.backgroundPaleBlue,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    QuizContentData.briefingAnswersSaved,
                    style:
                        AppTheme.bodySmall.copyWith(color: AppTheme.deepBlue),
                  ),
                  if (quiz.timeLimitMinutes != null || quiz.dueAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      quiz.timeLimitMinutes != null
                          ? QuizContentData.timeLimitBriefing
                          : QuizContentData.deadlineAutoSubmitBriefing,
                      style:
                          AppTheme.bodySmall.copyWith(color: AppTheme.deepBlue),
                    ),
                  ],
                  if (quiz.usesInstructorRelease) ...[
                    const SizedBox(height: 8),
                    Text(
                      QuizContentData.briefingInstructorRelease,
                      style:
                          AppTheme.bodySmall.copyWith(color: AppTheme.deepBlue),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (quizOpensResult(quiz))
              FilledButton.icon(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => QuizResultScreen(
                        attemptId: quiz.attemptId!, service: _service),
                  ),
                ),
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(quiz.awaitingEvaluation
                    ? QuizContentData.viewSubmission
                    : QuizContentData.viewResult),
              )
            else
              FilledButton.icon(
                onPressed: canStart ? _start : null,
                icon: _starting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(quiz.state == LearnerQuizState.inProgress
                        ? Icons.play_arrow_rounded
                        : Icons.rocket_launch_outlined),
                label: Text(_starting
                    ? QuizContentData.openingQuiz
                    : quizStatusLabel(quiz)),
              ),
            if (quizOpensResult(quiz)) ...[
              const SizedBox(height: 10),
              Text(quizStatusLabel(quiz),
                  textAlign: TextAlign.center, style: AppTheme.labelMedium),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      final attempt = await _service.startOrResume(widget.quiz.assignmentId);
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => QuizTakingScreen(attempt: attempt, service: _service),
        ),
      );
    } catch (error) {
      debugPrint('Quiz start failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error is LearnerQuizUpdateRequiredException
                ? QuizContentData.updateRequired
                : QuizContentData.openFailed)),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: AppTheme.textMedium),
            const SizedBox(width: 6),
            Flexible(child: Text(label, style: AppTheme.labelMedium)),
          ],
        ),
      );
}
