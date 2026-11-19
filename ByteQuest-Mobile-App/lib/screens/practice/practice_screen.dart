import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../data/learning_content_data.dart';
import '../../models/curriculum_model.dart';
import '../../services/curriculum_service.dart';
import '../../services/learner_realtime_coordinator.dart';
import '../../widgets/practice_coc_session_panel.dart';
import '../learn/curriculum_widgets.dart';
import '../learn/module_detail_screen.dart';
import '../quizzes/practice_quiz_screen.dart';
import 'practice_launch.dart';
import 'practice_mission_tile.dart';

/// Practice tab: COC -> modules -> mission tiles with lock icon and
/// prerequisite text, verified badge, runs and best time. Missions open only
/// after the server access check (`practice_mission_unlocked`).
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({
    super.key,
    this.service,
    this.accessCheck,
    this.launch,
    this.openQuiz,
    this.showSessionPanel = true,
  });

  final CurriculumService? service;
  final MissionAccessCheck? accessCheck;
  final MissionRouteLauncher? launch;
  final Future<void> Function(BuildContext context, String cocCode)? openQuiz;

  /// The COC timer panel reads the device session store; tests disable it.
  final bool showSessionPanel;

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen>
    with LearnerRealtimeRefreshMixin<PracticeScreen> {
  late final CurriculumService _service = widget.service ?? CurriculumService();
  CurriculumProjection? _data;
  String? _selected;
  String? _error;
  String? _launching;
  bool _loading = true;
  bool _fetching = false;
  bool _active = false;

  @override
  Set<LearnerRealtimeDomain> get realtimeDomains =>
      const {LearnerRealtimeDomain.learning, LearnerRealtimeDomain.progress};

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
    if (active && !_active && _data != null) unawaited(_load());
    _active = active;
  }

  Future<void> _load() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final data = await _service.getCurriculum();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
        if (_selected == null || data.coc(_selected!) == null) {
          _selected = data.currentCoc?.cocCode;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = LearningContentData.curriculumUnavailable;
          _loading = false;
        });
      }
    } finally {
      _fetching = false;
    }
  }

  Future<void> _practice(CurriculumMission mission) async {
    setState(() => _launching = mission.missionCode);
    try {
      final launched = await PracticeMissionLauncher.open(
          context, mission.missionCode,
          accessCheck: widget.accessCheck, launch: widget.launch);
      if (launched && mounted) await _load();
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
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    Widget body;
    if (_loading) {
      body = const LearnerLoadingView(
          label: LearningContentData.loadingCurriculum);
    } else if (data == null) {
      body = LearnerStateView(
        icon: Icons.cloud_off_outlined,
        title: LearningContentData.curriculumUnavailableTitle,
        message: _error ?? LearningContentData.curriculumUnavailable,
        actionLabel: LearningContentData.retry,
        onAction: _load,
      );
    } else if (data.cocs.isEmpty) {
      body = const LearnerStateView(
        icon: Icons.science_outlined,
        title: LearningContentData.curriculumEmptyTitle,
        message: LearningContentData.curriculumEmpty,
      );
    } else {
      final coc = data.coc(_selected ?? '') ?? data.cocs.first;
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            LearnerPageHeader(
              title: LearningContentData.practiceTitle,
              subtitle: LearningContentData.practiceSubtitle,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                const MethodologyButton(),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: LearningContentData.refresh,
                  onPressed: _fetching ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ]),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(_error!,
                    style:
                        AppTheme.bodySmall.copyWith(color: AppTheme.errorRed)),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: CocSelector(
                cocs: data.cocs,
                selected: coc.cocCode,
                onSelected: (code) => setState(() => _selected = code),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: LearnerSurface(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(coc.title,
                          style: AppTheme.titleLarge
                              .copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                          LearningContentData.missionsSummary(
                              coc.missions
                                  .where((mission) => mission.verified)
                                  .length,
                              coc.missions.length),
                          style: AppTheme.bodySmall),
                      const SizedBox(height: 10),
                      CurriculumProgressSummary(
                        progress: coc.progress,
                        completed: coc.completed,
                        semanticLabel: LearningContentData.progressValue(
                            coc.progress.done, coc.progress.total),
                      ),
                      if (!coc.unlocked && coc.lockReason != null) ...[
                        const SizedBox(height: 10),
                        LockReasonText(reason: coc.lockReason!),
                      ],
                    ]),
              ),
            ),
            if (coc.unlocked && widget.showSessionPanel) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(LearningContentData.practiceTimerNote,
                          style: AppTheme.bodySmall),
                      const SizedBox(height: 6),
                      PracticeCocSessionPanel(cocId: coc.cocCode),
                    ]),
              ),
            ],
            for (final module in coc.modules) ...[
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _ModuleSection(
                  coc: coc,
                  module: module,
                  launching: _launching,
                  onPractice: _practice,
                  onOpenModule: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(
                          builder: (_) => ModuleDetailScreen(
                                cocCode: coc.cocCode,
                                moduleId: module.id,
                                initial: data,
                                service: _service,
                                accessCheck: widget.accessCheck,
                                launch: widget.launch,
                                openQuiz: widget.openQuiz,
                              )))
                      .then((_) => _load()),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child:
                  CocQuizEntry(coc: coc, onOpen: () => _openQuiz(coc.cocCode)),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.backgroundOffWhite,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120), child: body),
        ),
      ),
    );
  }
}

class _ModuleSection extends StatelessWidget {
  const _ModuleSection({
    required this.coc,
    required this.module,
    required this.launching,
    required this.onPractice,
    required this.onOpenModule,
  });

  final CurriculumCoc coc;
  final CurriculumModule module;
  final String? launching;
  final ValueChanged<CurriculumMission> onPractice;
  final VoidCallback onOpenModule;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
                LearningContentData.moduleLabel(
                    module.sequenceOrder, module.code),
                style:
                    AppTheme.labelSmall.copyWith(color: AppTheme.textMedium)),
          ),
          const SizedBox(height: 2),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(module.title,
                  style: AppTheme.titleMedium
                      .copyWith(fontWeight: FontWeight.w800)),
            ),
            IconButton(
              tooltip: LearningContentData.lessonsTitle,
              onPressed: onOpenModule,
              icon: const Icon(Icons.menu_book_outlined),
            ),
          ]),
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
          // Mission tiles carry the prerequisite themselves; a module without
          // missions shows it here.
          if (!module.unlocked &&
              module.lockReason != null &&
              module.missions.isEmpty) ...[
            const SizedBox(height: 6),
            LockReasonText(reason: module.lockReason!),
          ],
          const SizedBox(height: 8),
          if (module.missions.isEmpty)
            Text(
                module.noRequiredItems
                    ? LearningContentData.noRequiredItems
                    : LearningContentData.noMissions,
                style: AppTheme.bodySmall)
          else
            for (final mission in module.missions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PracticeMissionTile(
                  mission: mission,
                  lockReason: module.lockReason,
                  busy: launching == mission.missionCode,
                  onOpen: mission.unlocked && launching == null
                      ? () => onPractice(mission)
                      : null,
                ),
              ),
        ],
      );
}
