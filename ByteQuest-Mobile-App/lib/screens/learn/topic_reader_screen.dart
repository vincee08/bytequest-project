import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../data/learning_content_data.dart';
import '../../models/curriculum_model.dart';
import '../../services/curriculum_service.dart';
import 'curriculum_widgets.dart';
import 'lesson_markdown.dart';

/// Reads the published revision of a lesson and records completion through
/// the server. Pops with the refreshed projection after a completion.
class TopicReaderScreen extends StatefulWidget {
  const TopicReaderScreen({
    super.key,
    required this.topic,
    required this.moduleUnlocked,
    this.lockReason,
    this.service,
  });

  final CurriculumTopic topic;
  final bool moduleUnlocked;
  final String? lockReason;
  final CurriculumService? service;

  @override
  State<TopicReaderScreen> createState() => _TopicReaderScreenState();
}

class _TopicReaderScreenState extends State<TopicReaderScreen> {
  late final CurriculumService _service = widget.service ?? CurriculumService();
  late Future<CurriculumLesson> _lesson =
      _service.getLesson(widget.topic.revisionId);
  late bool _completed = widget.topic.completed;
  bool _saving = false;
  CurriculumProjection? _refreshed;

  Future<void> _complete() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      _refreshed = await _service.completeTopic(widget.topic.id);
      if (!mounted) return;
      setState(() => _completed = true);
      messenger?.showSnackBar(const SnackBar(
          content: Text(LearningContentData.lessonCompleteSaved)));
    } on CurriculumException catch (error) {
      messenger?.showSnackBar(SnackBar(
          content: Text(error.failure == CurriculumFailure.moduleLocked
              ? LearningContentData.lessonModuleLocked
              : LearningContentData.lessonCompleteFailed)));
    } catch (_) {
      messenger?.showSnackBar(const SnackBar(
          content: Text(LearningContentData.lessonCompleteFailed)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<CurriculumProjection?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.of(context).pop(_refreshed);
        },
        child: Scaffold(
          backgroundColor: AppTheme.backgroundOffWhite,
          appBar: AppBar(
              title: Text(widget.topic.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: FutureBuilder<CurriculumLesson>(
                    future: _lesson,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return LearnerStateView(
                          icon: Icons.cloud_off_outlined,
                          title: widget.topic.title,
                          message: LearningContentData.lessonLoadFailed,
                          actionLabel: LearningContentData.retry,
                          onAction: () => setState(() => _lesson =
                              _service.getLesson(widget.topic.revisionId)),
                        );
                      }
                      final lesson = snapshot.data;
                      if (lesson == null) {
                        return const LearnerLoadingView(
                            label: LearningContentData.lessonOpen);
                      }
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        children: [
                          Semantics(
                            header: true,
                            child: Text(lesson.title,
                                style: AppTheme.headlineSmall
                                    .copyWith(fontWeight: FontWeight.w800)),
                          ),
                          if (lesson.summary != null) ...[
                            const SizedBox(height: 6),
                            Text(lesson.summary!,
                                style: AppTheme.bodyMedium
                                    .copyWith(color: AppTheme.textMedium)),
                          ],
                          const SizedBox(height: 16),
                          if (lesson.bodyMarkdown.trim().isEmpty)
                            const Text(LearningContentData.lessonEmptyBody)
                          else
                            LessonMarkdown(source: lesson.bodyMarkdown),
                        ],
                      );
                    },
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  decoration: const BoxDecoration(
                    color: AppTheme.cardWhite,
                    border:
                        Border(top: BorderSide(color: AppTheme.borderLight)),
                  ),
                  child: !widget.moduleUnlocked
                      ? LockReasonText(
                          reason: widget.lockReason ??
                              LearningContentData.lessonLockedHint)
                      : _completed
                          ? const Align(
                              alignment: Alignment.centerLeft,
                              child: CurriculumStatusPill(
                                  label: LearningContentData.lessonCompleted,
                                  icon: Icons.check_circle_rounded,
                                  color: AppTheme.accentGreen),
                            )
                          : ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: FilledButton.icon(
                                key: const ValueKey('mark-topic-complete'),
                                onPressed: _saving ? null : _complete,
                                icon: _saving
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Icon(Icons.check_rounded),
                                label: Text(_saving
                                    ? LearningContentData.markingComplete
                                    : LearningContentData.markComplete),
                              ),
                            ),
                ),
              ],
            ),
          ),
        ),
      );
}
