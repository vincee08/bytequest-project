import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../data/learning_content_data.dart';
import '../../models/curriculum_model.dart';
import '../../services/curriculum_service.dart';
import '../practice/practice_launch.dart';
import '../practice/practice_mission_tile.dart';
import '../quizzes/practice_quiz_screen.dart';
import 'curriculum_widgets.dart';
import 'topic_reader_screen.dart';

/// One module: published lessons, official learning outcomes, linked practice
/// missions and the COC practice quiz entry. Locked modules stay readable but
/// nothing can be completed or started until the server unlocks them.
class ModuleDetailScreen extends StatefulWidget {
  const ModuleDetailScreen({
    super.key,
    required this.cocCode,
    required this.moduleId,
    required this.initial,
    this.service,
    this.accessCheck,
    this.launch,
    this.openQuiz,
  });

  final String cocCode;
  final String moduleId;
  final CurriculumProjection initial;
  final CurriculumService? service;
  final MissionAccessCheck? accessCheck;
  final MissionRouteLauncher? launch;
  final Future<void> Function(BuildContext context, String cocCode)? openQuiz;

  @override
  State<ModuleDetailScreen> createState() => _ModuleDetailScreenState();
}

class _ModuleDetailScreenState extends State<ModuleDetailScreen> {
  late final CurriculumService _service = widget.service ?? CurriculumService();
  late CurriculumProjection _data = widget.initial;
  String? _launching;

  CurriculumCoc? get _coc => _data.coc(widget.cocCode);
  CurriculumModule? get _module {
    for (final module in _coc?.modules ?? const <CurriculumModule>[]) {
      if (module.id == widget.moduleId) return module;
    }
    return null;
  }

  Future<void> _reload() async {
    try {
      final data = await _service.getCurriculum();
      if (mounted) setState(() => _data = data);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
            content: Text(LearningContentData.curriculumUnavailable)));
      }
    }
  }

  Future<void> _openTopic(
      CurriculumModule module, CurriculumTopic topic) async {
    final refreshed = await Navigator.of(context)
        .push<CurriculumProjection?>(MaterialPageRoute(
      builder: (_) => TopicReaderScreen(
        topic: topic,
        moduleUnlocked: module.unlocked,
        lockReason: module.lockReason,
        service: _service,
      ),
    ));
    if (!mounted) return;
    if (refreshed != null) {
      setState(() => _data = refreshed);
    } else {
      await _reload();
    }
  }

  Future<void> _practice(CurriculumMission mission) async {
    setState(() => _launching = mission.missionCode);
    try {
      final launched = await PracticeMissionLauncher.open(
          context, mission.missionCode,
          accessCheck: widget.accessCheck, launch: widget.launch);
      if (launched && mounted) await _reload();
    } finally {
      if (mounted) setState(() => _launching = null);
    }
  }

  Future<void> _openQuiz(String cocCode) async {
    final hook = widget.openQuiz;
    if (hook != null) {
      await hook(context, cocCode);
    } else {
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PracticeQuizScreen(coc: cocCode)));
    }
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final coc = _coc;
    final module = _module;
    if (coc == null || module == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const LearnerStateView(
          icon: Icons.route_outlined,
          title: LearningContentData.curriculumUnavailableTitle,
          message: LearningContentData.curriculumUnavailable,
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.backgroundOffWhite,
      appBar: AppBar(
          title: Text(LearningContentData.moduleLabel(
              module.sequenceOrder, module.code))),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Semantics(
                header: true,
                child: Text(module.title,
                    style: AppTheme.headlineSmall
                        .copyWith(fontWeight: FontWeight.w800)),
              ),
              if (module.sourceReference != null) ...[
                const SizedBox(height: 4),
                Text(module.sourceReference!,
                    style: AppTheme.labelSmall
                        .copyWith(color: AppTheme.textMedium)),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                CurriculumStatusPill(
                  label: moduleStateLabel(module),
                  icon: module.unlocked
                      ? Icons.lock_open_rounded
                      : Icons.lock_outline_rounded,
                  color: module.completed
                      ? AppTheme.accentGreen
                      : module.unlocked
                          ? AppTheme.primaryBlue
                          : AppTheme.textMedium,
                ),
                if (module.newContent)
                  const CurriculumStatusPill(
                      label: LearningContentData.newContentLabel,
                      icon: Icons.fiber_new_outlined,
                      color: AppTheme.accentOrange),
              ]),
              if (!module.unlocked) ...[
                const SizedBox(height: 12),
                LearnerSurface(
                  color: AppTheme.backgroundPaleBlue,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(LearningContentData.lockedModuleBanner,
                            style: AppTheme.labelLarge
                                .copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        LockReasonText(
                            reason: module.lockReason ??
                                LearningContentData.lessonLockedHint),
                      ]),
                ),
              ],
              const SizedBox(height: 12),
              if (module.noRequiredItems)
                const LearnerSurface(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(LearningContentData.noRequiredItems),
                        SizedBox(height: 4),
                        Text(LearningContentData.noRequiredItemsDetail),
                      ]),
                )
              else
                CurriculumProgressSummary(
                  progress: module.progress,
                  completed: module.completed,
                  semanticLabel: LearningContentData.progressValue(
                      module.progress.done, module.progress.total),
                ),
              const SizedBox(height: 20),
              const _SectionTitle(LearningContentData.lessonsTitle),
              if (module.topics.isEmpty)
                const Text(LearningContentData.noLessons)
              else
                for (final topic in module.topics)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _TopicTile(
                        topic: topic, onTap: () => _openTopic(module, topic)),
                  ),
              const SizedBox(height: 20),
              const _SectionTitle(LearningContentData.missionsTitle),
              if (module.missions.isEmpty)
                const Text(LearningContentData.noMissions)
              else
                for (final mission in module.missions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PracticeMissionTile(
                      mission: mission,
                      lockReason: module.lockReason,
                      busy: _launching == mission.missionCode,
                      onOpen: mission.unlocked && _launching == null
                          ? () => _practice(mission)
                          : null,
                    ),
                  ),
              const SizedBox(height: 20),
              const _SectionTitle(LearningContentData.outcomesTitle),
              Text(LearningContentData.outcomesSource,
                  style:
                      AppTheme.labelSmall.copyWith(color: AppTheme.textMedium)),
              const SizedBox(height: 8),
              for (final outcome in module.outcomes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 40,
                          child: Text(outcome.code,
                              style: AppTheme.labelMedium
                                  .copyWith(fontWeight: FontWeight.w800)),
                        ),
                        Expanded(
                            child: Text(outcome.statement,
                                style:
                                    AppTheme.bodySmall.copyWith(height: 1.45))),
                      ]),
                ),
              const SizedBox(height: 20),
              CocQuizEntry(coc: coc, onOpen: () => _openQuiz(coc.cocCode)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          header: true,
          child: Text(text,
              style:
                  AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w800)),
        ),
      );
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.topic, required this.onTap});

  final CurriculumTopic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => LearnerSurface(
        key: ValueKey('topic-${topic.id}'),
        semanticLabel:
            LearningContentData.lessonSemantics(topic.title, topic.completed),
        onTap: onTap,
        child: Row(children: [
          Icon(
              topic.completed
                  ? Icons.check_circle_rounded
                  : Icons.article_outlined,
              color: topic.completed
                  ? AppTheme.accentGreen
                  : AppTheme.primaryBlue),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(topic.title,
                  style: AppTheme.labelLarge
                      .copyWith(fontWeight: FontWeight.w700)),
              if (topic.summary != null) ...[
                const SizedBox(height: 2),
                Text(topic.summary!,
                    style: AppTheme.bodySmall,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 4),
              Text(
                  topic.completed
                      ? LearningContentData.lessonCompleted
                      : LearningContentData.lessonOpen,
                  style:
                      AppTheme.labelSmall.copyWith(color: AppTheme.textMedium)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppTheme.textMedium),
        ]),
      );
}

/// COC practice quiz entry, driven by the server's eligibility flag.
class CocQuizEntry extends StatelessWidget {
  const CocQuizEntry({super.key, required this.coc, required this.onOpen});

  final CurriculumCoc coc;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final canOpen = coc.quiz.passed || coc.quiz.eligible;
    return LearnerSurface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          header: true,
          child: Text(LearningContentData.cocQuizTitle,
              style:
                  AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 6),
        Text(
          coc.quiz.passed
              ? LearningContentData.cocQuizPassed
              : !coc.unlocked
                  ? LearningContentData.cocQuizLocked(coc.number)
                  : coc.quiz.eligible
                      ? LearningContentData.cocQuizReady
                      : LearningContentData.cocQuizPending(coc.number),
          style: AppTheme.bodySmall,
        ),
        if (canOpen) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: FilledButton.icon(
              key: ValueKey('coc-quiz-${coc.cocCode}'),
              onPressed: onOpen,
              icon: const Icon(Icons.quiz_outlined),
              label: Text(coc.quiz.passed
                  ? LearningContentData.cocQuizReview(coc.number)
                  : LearningContentData.cocQuizStart(coc.number)),
            ),
          ),
        ],
      ]),
    );
  }
}
