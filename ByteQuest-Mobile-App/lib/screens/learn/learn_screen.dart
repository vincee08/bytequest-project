import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../data/learning_content_data.dart';
import '../../models/curriculum_model.dart';
import '../../services/curriculum_service.dart';
import '../../services/learner_realtime_coordinator.dart';
import '../courses/courses_screen.dart';
import '../quizzes/learner_quizzes_screen.dart';
import 'curriculum_widgets.dart';
import 'module_detail_screen.dart';

/// Learn tab: COC selector -> modules (lock/complete state, prerequisite and
/// progress) -> module detail with published lessons, official outcomes,
/// linked practice missions and the COC practice quiz.
class LearnScreen extends StatefulWidget {
  const LearnScreen(
      {super.key,
      this.service,
      this.openAssessmentPath,
      this.openClassQuizzes});

  final CurriculumService? service;

  /// Test hooks; production opens the existing screens.
  final VoidCallback? openAssessmentPath;
  final VoidCallback? openClassQuizzes;

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen>
    with LearnerRealtimeRefreshMixin<LearnScreen> {
  late final CurriculumService _service = widget.service ?? CurriculumService();
  CurriculumProjection? _data;
  String? _selected;
  String? _error;
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
    // Reload when the tab becomes visible again (practice may have unlocked a module).
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

  Future<void> _openModule(CurriculumCoc coc, CurriculumModule module) async {
    final data = _data;
    if (data == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ModuleDetailScreen(
        cocCode: coc.cocCode,
        moduleId: module.id,
        initial: data,
        service: _service,
      ),
    ));
    if (mounted) await _load();
  }

  void _openAssessmentPath() {
    final hook = widget.openAssessmentPath;
    if (hook != null) return hook();
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const CoursesScreen()));
  }

  void _openClassQuizzes() {
    final hook = widget.openClassQuizzes;
    if (hook != null) return hook();
    Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const LearnerQuizzesScreen()));
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
        icon: Icons.route_outlined,
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
            _header(),
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
              child: _CocSummaryCard(coc: coc),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('learn-assessment-path'),
                    onPressed: _openAssessmentPath,
                    icon: const Icon(Icons.route_outlined),
                    label: const Text(LearningContentData.learningPathLink),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('learn-class-quizzes'),
                    onPressed: _openClassQuizzes,
                    icon: const Icon(Icons.quiz_outlined),
                    label: const Text(LearningContentData.classQuizzesLink),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            for (final module in coc.modules)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: CurriculumModuleTile(
                    module: module, onTap: () => _openModule(coc, module)),
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

  Widget _header() => LearnerPageHeader(
        title: LearningContentData.learnTitle,
        subtitle: LearningContentData.learnSubtitle,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MethodologyButton(),
            const SizedBox(width: 4),
            IconButton.filledTonal(
              tooltip: LearningContentData.refresh,
              onPressed: _fetching ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      );
}

class _CocSummaryCard extends StatelessWidget {
  const _CocSummaryCard({required this.coc});

  final CurriculumCoc coc;

  @override
  Widget build(BuildContext context) => LearnerSurface(
        semanticLabel:
            '${LearningContentData.cocLabel(coc.number)}, ${coc.title}, '
            '${LearningContentData.progressValue(coc.progress.done, coc.progress.total)}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(LearningContentData.cocLabel(coc.number),
                style:
                    AppTheme.labelSmall.copyWith(color: AppTheme.textMedium)),
            const SizedBox(height: 2),
            Text(coc.title,
                style:
                    AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
                LearningContentData.modulesCompleted(
                    coc.modulesCompleted, coc.modules.length),
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
          ],
        ),
      );
}
