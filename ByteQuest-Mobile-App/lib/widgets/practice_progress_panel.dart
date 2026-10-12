import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../data/mission_content_data.dart';
import '../models/practice_progress_model.dart';
import '../services/practice_progress_service.dart';
import '../screens/quizzes/practice_quiz_screen.dart';

class PracticeProgressPanel extends StatefulWidget {
  const PracticeProgressPanel({super.key, this.coc, this.onChanged});
  final String? coc;
  final Future<void> Function()? onChanged;
  @override
  State<PracticeProgressPanel> createState() => _PracticeProgressPanelState();
}

class _PracticeProgressPanelState extends State<PracticeProgressPanel> {
  late Future<List<PracticeCocProgress>> _progress =
      PracticeProgressService().getProgress();
  void _refresh() =>
      setState(() => _progress = PracticeProgressService().getProgress());
  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<PracticeCocProgress>>(
          future: _progress,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(MissionContentData.practiceProgressUnavailable),
                    OutlinedButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label:
                            const Text(MissionContentData.practiceQuizRetry)),
                  ]);
            }
            if (!snapshot.hasData) {
              return const Column(children: [
                LinearProgressIndicator(),
                SizedBox(height: 8),
                Text(MissionContentData.loadingPracticeProgressLabel),
              ]);
            }
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.coc == null)
                    Text(MissionContentData.practiceProgressTitle,
                        style: AppTheme.labelLarge),
                  for (final progress in snapshot.data!
                      .where((p) => widget.coc == null || p.coc == widget.coc))
                    PracticeCocSummary(
                      progress: progress,
                      onOpenQuiz: widget.coc != null && progress.quizAvailable
                          ? () async {
                              await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) => PracticeQuizScreen(
                                          coc: progress.coc)));
                              if (mounted) {
                                _refresh();
                                await widget.onChanged?.call();
                              }
                            }
                          : null,
                    ),
                ]);
          });
}

/// Static COC status with an explicit quiz action when server access permits it.
class PracticeCocSummary extends StatelessWidget {
  const PracticeCocSummary(
      {super.key, required this.progress, this.onOpenQuiz});
  final PracticeCocProgress progress;
  final VoidCallback? onOpenQuiz;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(
                progress.completed
                    ? Icons.check_circle_outline
                    : progress.unlocked
                        ? Icons.lock_open
                        : Icons.lock_outline,
                color: AppTheme.deepBlue),
            const SizedBox(width: 10),
            Expanded(
                child: Text(progress.coc.toUpperCase(),
                    style: AppTheme.titleMedium)),
          ]),
          const SizedBox(height: 8),
          Text(
              MissionContentData.practiceMissionCount(
                  progress.completedMissions.length),
              style: AppTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
              !progress.unlocked
                  ? MissionContentData.practiceLockedMessage
                  : progress.completed
                      ? MissionContentData.practiceQuizPassed
                      : progress.quizAvailable
                          ? MissionContentData.practiceQuizReadyLabel
                          : MissionContentData.practiceMissionsPendingLabel,
              style: AppTheme.bodySmall),
          if (onOpenQuiz != null && progress.quizAvailable) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onOpenQuiz,
              icon: const Icon(Icons.quiz_outlined),
              label: Text(progress.completed
                  ? MissionContentData.practiceQuizReviewLabel
                  : MissionContentData.practiceQuizStart),
            ),
          ],
        ],
      ));
}
