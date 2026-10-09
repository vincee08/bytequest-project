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
  Widget build(BuildContext context) => FutureBuilder<
          List<PracticeCocProgress>>(
      future: _progress,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ListTile(
              title: const Text(MissionContentData.practiceProgressUnavailable),
              trailing: IconButton(
                  tooltip: MissionContentData.practiceQuizRetry,
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh)));
        }
        if (!snapshot.hasData) return const LinearProgressIndicator();
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(MissionContentData.practiceProgressTitle,
                  style: AppTheme.labelLarge),
              for (final progress in snapshot.data!
                  .where((p) => widget.coc == null || p.coc == widget.coc))
                ListTile(
                  leading: Icon(progress.completed
                      ? Icons.check_circle_outline
                      : progress.unlocked
                          ? Icons.lock_open
                          : Icons.lock_outline),
                  title: Text(
                      '${progress.coc.toUpperCase()} · ${progress.completedMissions.length}/5'),
                  subtitle: Text(!progress.unlocked
                      ? MissionContentData.practiceLockedMessage
                      : progress.completed
                          ? MissionContentData.practiceQuizPassed
                          : MissionContentData.practiceQuizNotice),
                  trailing: widget.coc != null && progress.quizAvailable
                      ? IconButton(
                          tooltip: MissionContentData.practiceQuizStart,
                          onPressed: () async {
                            await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) =>
                                        PracticeQuizScreen(coc: progress.coc)));
                            if (mounted) {
                              _refresh();
                              await widget.onChanged?.call();
                            }
                          },
                          icon: const Icon(Icons.quiz_outlined))
                      : null,
                ),
            ]);
      });
}
