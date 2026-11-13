import 'package:flutter/material.dart';
import 'dart:async';

import '../../core/theme/app_theme.dart';
import '../../core/config/supabase_config.dart';
import '../../core/widgets/learner_ui.dart';
import '../../core/widgets/learner_navigation_shell.dart';
import '../../data/missions_data.dart';
import '../../data/mission_content_data.dart';
import '../../models/practice_progress_model.dart';
import '../../services/practice_progress_service.dart';
import '../../widgets/practice_progress_panel.dart';
import '../../widgets/practice_coc_session_panel.dart';
import '../../models/assigned_activity_model.dart';
import '../../models/learning_resource_model.dart';
import '../../models/mission_model.dart';
import '../../services/authoritative_assessment_service.dart';
import '../../services/learning_resource_service.dart';
import '../../services/learner_realtime_coordinator.dart';
import '../simulation/mission_launcher.dart';
import '../courses/courses_screen.dart';
import '../quizzes/learner_quizzes_screen.dart';
import '../resources/resource_viewer_screen.dart';
import 'class_details_screen.dart';

/// Shared learning hub. Assigned content is authoritative; the retained local
/// catalog is explicitly practice-only until mapped to an approved source.
class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen>
    with
        SingleTickerProviderStateMixin,
        LearnerRealtimeRefreshMixin<MissionsScreen> {
  late final TabController _tabController;
  final _assessmentService = AuthoritativeAssessmentService.instance;
  final _resourceService = LearningResourceService();
  List<AssignedActivity> _assignments = const [];
  List<LearningResource> _resources = const [];
  Map<String, String> _enrolledClasses = const {};
  bool _loading = true;
  String? _error;
  String? _startingAssignmentId;
  List<PracticeCocProgress> _practiceProgress = const [];
  String? _practiceError;
  bool _practiceLoading = true;
  String? _selectedPracticeMissionId;
  String? _expandedPracticeMissionId;
  Future<void> _loadPracticeProgress() async {
    if (mounted) setState(() => _practiceLoading = true);
    try {
      final progress = await PracticeProgressService().getProgress();
      if (mounted)
        setState(() {
          _practiceProgress = progress;
          _practiceError = null;
          _practiceLoading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _practiceProgress = const [];
          _practiceError = MissionContentData.practiceProgressUnavailable;
          _practiceLoading = false;
        });
    }
  }

  @override
  Set<LearnerRealtimeDomain> get realtimeDomains => const {
        LearnerRealtimeDomain.classes,
        LearnerRealtimeDomain.learning,
        LearnerRealtimeDomain.resources,
      };

  @override
  Future<void> refreshFromRealtime() async {
    await Future.wait([_loadAssignments(), _loadPracticeProgress()]);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAssignments();
    unawaited(_loadPracticeProgress());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAssignments() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final values = await Future.wait([
        _assessmentService.getAssignedActivities(),
        _resourceService.getAssignedResources(),
        SupabaseConfig.client
            .from('class_memberships')
            .select('class_id,classes(id,title)')
            .eq('learner_id', SupabaseConfig.currentUserId!)
            .eq('status', 'active'),
      ]);
      if (!mounted) return;
      setState(() {
        _assignments = values[0] as List<AssignedActivity>;
        _resources = values[1] as List<LearningResource>;
        _enrolledClasses = {
          for (final row in values[2] as List)
            if (row['classes'] != null)
              row['class_id'] as String: row['classes']['title'] as String
        };
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error =
            'Assigned content could not be loaded. Check your connection and try again.';
        _loading = false;
      });
      debugPrint('Assigned activity load failed: $error');
    }
  }

  String _normalizeCode(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  Mission? _resolveLocalMission(AssignedActivity assignment) {
    final payloadCode =
        assignment.learnerPayload['local_mission_code'] as String?;
    final target = _normalizeCode(payloadCode ?? assignment.missionCode);

    for (final mission in MissionsData.getAllMissions()) {
      if (_normalizeCode(mission.missionCode) == target ||
          _normalizeCode(mission.id) == target) {
        return mission;
      }
    }
    return null;
  }

  Future<void> _launchAssigned(AssignedActivity assignment) async {
    final mission = _resolveLocalMission(assignment);
    if (mission == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This published activity has no installed mobile simulation mapping.',
          ),
        ),
      );
      return;
    }

    if (assignment.isBypassAccess) {
      await _launchPractice(mission);
      return;
    }

    setState(() => _startingAssignmentId = assignment.id);
    try {
      await _assessmentService.startAttempt(assignment);
      if (!mounted) return;
      await MissionLauncher.launch(
        context,
        mission,
        learnerPayload: assignment.learnerPayload,
      );
      if (_assessmentService.activeSession?.assignmentId == assignment.id) {
        _assessmentService.abandonLocalSession();
      }
      await _loadAssignments();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to start this assignment: $error')),
      );
    } finally {
      if (mounted) setState(() => _startingAssignmentId = null);
    }
  }

  Future<void> _launchPractice(Mission mission) async {
    _assessmentService.abandonLocalSession();
    setState(() => _selectedPracticeMissionId = mission.id);
    await MissionLauncher.launch(context, mission);
    await _loadPracticeProgress();
  }

  Future<void> _openResource(LearningResource resource) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ResourceViewerScreen(resource: resource),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundOffWhite,
      appBar: LearnerNavigationScope.maybeOf(context) == null &&
              Navigator.canPop(context)
          ? AppBar(
              leading: BackButton(onPressed: () => Navigator.pop(context)),
              title: const Text(MissionContentData.learnLabel))
          : null,
      body: SafeArea(
        child: Column(
          children: [
            LearnerPageHeader(
              title: 'Learn',
              subtitle: 'Assignments, practice missions, and class resources',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: 'Refresh assigned activities and resources',
                    button: true,
                    child: IconButton.filledTonal(
                      onPressed: _loading ? null : _loadAssignments,
                      tooltip: 'Refresh learning content',
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const CoursesScreen())),
                  icon: const Icon(Icons.route_outlined),
                  label: const Text(MissionContentData.learningPathLabel),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const LearnerQuizzesScreen())),
                  icon: const Icon(Icons.quiz_outlined),
                  label: const Text(MissionContentData.quizzesLabel),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  controller: _tabController,
                  padding: const EdgeInsets.all(4),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: AppTheme.cardWhite,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: AppTheme.softShadow,
                  ),
                  labelColor: AppTheme.primaryBlue,
                  unselectedLabelColor: AppTheme.textMedium,
                  tabs: const [
                    Tab(text: 'Tasks'),
                    Tab(text: 'Classes'),
                    Tab(text: 'Practice'),
                    Tab(text: 'Files'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAssignedTab(),
                  _buildClassesTab(),
                  _buildPracticeTab(),
                  _buildResourcesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignedTab() {
    if (_loading) {
      return const LearnerLoadingView(label: 'Loading assigned activities');
    }
    if (_error != null) {
      return _EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Assignments unavailable',
        message: _error!,
        actionLabel: 'Try again',
        onAction: _loadAssignments,
      );
    }
    if (_assignments.isEmpty) {
      return const _EmptyState(
        icon: Icons.assignment_outlined,
        title: 'No assigned or unlocked activity',
        message:
            'Your Instructor has not assigned an activity or granted practice access yet.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAssignments,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        itemCount: _assignments.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final assignment = _assignments[index];
          final isAssessment = assignment.isAssessment;
          final isBypassAccess = assignment.isBypassAccess;
          final isStarting = _startingAssignmentId == assignment.id;

          return Semantics(
            container: true,
            label:
                '${isAssessment ? "Assessment" : isBypassAccess ? "Instructor-unlocked practice" : "Practice assignment"}: ${assignment.title}',
            child: Card(
              elevation: 0,
              color: AppTheme.cardWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppTheme.borderLight),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (isAssessment
                                    ? AppTheme.accentOrange
                                    : AppTheme.primaryBlue)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isAssessment
                                ? Icons.fact_check_outlined
                                : isBypassAccess
                                    ? Icons.lock_open_rounded
                                    : Icons.school_outlined,
                            color: isAssessment
                                ? AppTheme.accentOrange
                                : AppTheme.primaryBlue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                assignment.title,
                                style: AppTheme.titleLarge.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                assignment.classTitle,
                                style: AppTheme.bodySmall.copyWith(
                                  color: AppTheme.textMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: (isAssessment
                                ? AppTheme.accentOrange
                                : AppTheme.primaryBlue)
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isAssessment
                            ? 'ASSESSMENT - RESULTS RELEASED BY INSTRUCTOR'
                            : isBypassAccess
                                ? 'INSTRUCTOR-UNLOCKED PRACTICE'
                                : 'ASSIGNED PRACTICE',
                        style: AppTheme.labelSmall.copyWith(
                          color: isAssessment
                              ? AppTheme.accentOrange
                              : AppTheme.primaryBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (assignment.instructions?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 12),
                      Text(
                        assignment.instructions!,
                        style: AppTheme.bodyMedium.copyWith(
                          color: AppTheme.textMedium,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (assignment.dueAt != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.schedule_outlined, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'Due ${MaterialLocalizations.of(context).formatMediumDate(assignment.dueAt!.toLocal())}',
                            style: AppTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: isStarting
                                ? null
                                : () => _launchAssigned(assignment),
                            icon: isStarting
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow_rounded),
                            label: Text(
                              isStarting
                                  ? 'Starting...'
                                  : 'Start ${isAssessment ? "assessment" : "practice"}',
                            ),
                          ),
                        )),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPracticeTab() {
    if (_practiceLoading) {
      return const LearnerLoadingView(
          label: MissionContentData.loadingPracticeProgressLabel);
    }
    if (_practiceError != null) {
      return _EmptyState(
          icon: Icons.cloud_off_outlined,
          title: MissionContentData.practiceProgressTitle,
          message: _practiceError!,
          actionLabel: MissionContentData.practiceQuizRetry,
          onAction: _loadPracticeProgress);
    }
    final missions = MissionsData.getAllMissions();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        Text(MissionContentData.practiceQuizNotice, style: AppTheme.bodySmall),
        const SizedBox(height: 12),
        for (var index = 1; index <= 4; index++) ...[
          _buildPracticeCocCard('coc$index', missions),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildPracticeCocCard(String cocId, List<Mission> missions) {
    final progress =
        _practiceProgress.where((item) => item.coc == cocId).firstOrNull;
    final unlocked = progress?.unlocked ?? false;
    final cocMissions =
        missions.where((mission) => mission.cocId == cocId).toList();
    final verified = progress?.completedMissions.length ?? 0;
    final selected = cocMissions
        .where((mission) => mission.id == _selectedPracticeMissionId)
        .firstOrNull;
    return Card(
      elevation: 0,
      color: AppTheme.cardWhite,
      shape: RoundedRectangleBorder(
        borderRadius: AppTheme.radiusMd,
        side: BorderSide(color: AppTheme.borderMedium),
      ),
      child: ExpansionTile(
        key: PageStorageKey('learn-$cocId'),
        initiallyExpanded: cocId == 'coc1',
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppTheme.softBlueAccent,
          foregroundColor: AppTheme.deepBlue,
          child: Text(cocId.substring(3)),
        ),
        title: Text(MissionContentData.practiceCocTitle(cocId),
            style: AppTheme.titleMedium),
        subtitle: Text(
          '${MissionContentData.practiceMissionCount(verified)}'
          '${progress?.completed == true ? ' · ${MissionContentData.practiceCocCompleteLabel}' : !unlocked ? ' · ${MissionContentData.practiceCocLockedLabel}' : ''}'
          '${selected == null ? '' : ' · ${MissionContentData.practiceMissionSelectedLabel}: ${selected.missionCode}'}',
          style: AppTheme.bodySmall,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LearnerProgressBar(
                    value: verified / 5,
                    semanticLabel:
                        MissionContentData.practiceMissionCount(verified),
                  ),
                  if (unlocked) ...[
                    const SizedBox(height: 12),
                    PracticeCocSessionPanel(cocId: cocId),
                  ],
                  for (final mission in cocMissions)
                    _buildPracticeMissionTile(
                      mission,
                      unlocked: unlocked,
                      verified:
                          progress?.completedMissions.contains(mission.id) ??
                              false,
                    ),
                  if (unlocked)
                    PracticeProgressPanel(
                        coc: cocId, onChanged: _loadPracticeProgress),
                ]),
          ),
        ],
      ),
    );
  }

  Widget _buildPracticeMissionTile(Mission mission,
      {required bool unlocked, required bool verified}) {
    final selected = mission.id == _selectedPracticeMissionId;
    final detailsOpen = mission.id == _expandedPracticeMissionId;
    return Semantics(
      button: true,
      enabled: unlocked,
      selected: selected,
      label:
          '${MissionContentData.practiceMissionNumber(mission.missionNumber)}, '
          '${mission.title}, ${verified ? MissionContentData.practiceMissionVerifiedLabel : unlocked ? MissionContentData.practiceMissionAvailableLabel : MissionContentData.practiceLockedMessage}',
      child: Card(
        elevation: 0,
        color: selected ? AppTheme.backgroundPaleBlue : AppTheme.cardWhite,
        shape: RoundedRectangleBorder(
          borderRadius: AppTheme.radiusSm,
          side: BorderSide(
              color: selected ? AppTheme.primaryBlue : AppTheme.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              key: ValueKey('learn-practice-${mission.id}'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              minVerticalPadding: 2,
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.softBlueAccent,
                foregroundColor: AppTheme.deepBlue,
                child: Text('${mission.missionNumber}'),
              ),
              title: Text(mission.title, style: AppTheme.labelLarge),
              subtitle: Text(
                '${MissionContentData.practiceMissionNumber(mission.missionNumber)}'
                '${verified ? ' · ${MissionContentData.practiceMissionVerifiedShortLabel}' : !unlocked ? ' · ${MissionContentData.practiceCocLockedLabel}' : ''}',
                style: AppTheme.bodySmall,
              ),
              trailing: IconButton(
                key: ValueKey('learn-practice-details-${mission.id}'),
                tooltip: detailsOpen
                    ? MissionContentData.practiceHideMissionDetails
                    : MissionContentData.practiceShowMissionDetails,
                onPressed: () => setState(() => _expandedPracticeMissionId =
                    detailsOpen ? null : mission.id),
                icon: Icon(detailsOpen
                    ? Icons.expand_less_rounded
                    : Icons.info_outline_rounded),
              ),
              onTap: unlocked ? () => _launchPractice(mission) : null,
            ),
            if (detailsOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Text(mission.description ?? mission.title,
                    style: AppTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassesTab() {
    if (_loading) {
      return const LearnerLoadingView(label: 'Loading learner classes');
    }
    if (_error != null) {
      return _EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Classes unavailable',
        message: _error!,
        actionLabel: 'Try again',
        onAction: _loadAssignments,
      );
    }

    final classes = <String, _LearnerClassSummary>{};
    for (final entry in _enrolledClasses.entries) {
      classes[entry.key] = _LearnerClassSummary(
          classId: entry.key,
          title: entry.value,
          assignmentCount: 0,
          resourceCount: 0);
    }
    for (final assignment in _assignments) {
      final current = classes[assignment.classId];
      classes[assignment.classId] = _LearnerClassSummary(
        classId: assignment.classId,
        title: assignment.classTitle,
        assignmentCount: (current?.assignmentCount ?? 0) + 1,
        resourceCount: current?.resourceCount ?? 0,
      );
    }
    for (final resource in _resources) {
      final current = classes[resource.classId];
      classes[resource.classId] = _LearnerClassSummary(
        classId: resource.classId,
        title: resource.classTitle,
        assignmentCount: current?.assignmentCount ?? 0,
        resourceCount: (current?.resourceCount ?? 0) + 1,
      );
    }

    if (classes.isEmpty) {
      return const _EmptyState(
        icon: Icons.groups_outlined,
        title: 'No active class content yet',
        message:
            'Classes with assigned activities or shared resources will appear here.',
      );
    }

    final entries = classes.values.toList(growable: false)
      ..sort((a, b) => a.title.compareTo(b.title));
    return RefreshIndicator(
      onRefresh: _loadAssignments,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final classroom = entries[index];
          return LearnerSurface(
            semanticLabel:
                '${classroom.title}, ${classroom.assignmentCount} tasks, ${classroom.resourceCount} files',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ClassDetailsScreen(
                  classId: classroom.classId,
                  classTitle: classroom.title,
                  assignments: _assignments,
                  resources: _resources,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundPaleBlue,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.groups_2_outlined,
                    color: AppTheme.primaryBlue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        classroom.title,
                        style: AppTheme.titleMedium.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${classroom.assignmentCount} ${classroom.assignmentCount == 1 ? "task" : "tasks"} · ${classroom.resourceCount} ${classroom.resourceCount == 1 ? "file" : "files"}',
                        style: AppTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildResourcesTab() {
    if (_loading) {
      return const LearnerLoadingView(label: 'Loading learning resources');
    }
    if (_error != null) {
      return _EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Resources unavailable',
        message: _error!,
        actionLabel: 'Try again',
        onAction: _loadAssignments,
      );
    }
    if (_resources.isEmpty) {
      return const _EmptyState(
        icon: Icons.folder_open_outlined,
        title: 'No class resources yet',
        message:
            'PDFs, images, and approved videos shared by your Instructor will appear here.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAssignments,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        itemCount: _resources.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final resource = _resources[index];
          final isVideo = resource.mimeType?.startsWith('video/') ?? false;
          return Semantics(
            container: true,
            label:
                '${isVideo ? "Video" : "Learning resource"}: ${resource.title}, shared in ${resource.classTitle}',
            child: Card(
              elevation: 0,
              color: AppTheme.cardWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: AppTheme.borderLight),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isVideo
                            ? Icons.play_circle_outline_rounded
                            : resource.mimeType == 'application/pdf'
                                ? Icons.picture_as_pdf_outlined
                                : Icons.image_outlined,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            resource.title,
                            style: AppTheme.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(resource.classTitle, style: AppTheme.bodySmall),
                          if (resource.description?.isNotEmpty ?? false) ...[
                            const SizedBox(height: 7),
                            Text(
                              resource.description!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.bodySmall.copyWith(height: 1.4),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Semantics(
                      button: true,
                      label: 'Open ${resource.title}',
                      child: IconButton.filledTonal(
                        onPressed: () => _openResource(resource),
                        tooltip: 'Open resource',
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        icon: const Icon(Icons.visibility_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LearnerClassSummary {
  final String classId;
  final String title;
  final int assignmentCount;
  final int resourceCount;

  const _LearnerClassSummary({
    required this.classId,
    required this.title,
    required this.assignmentCount,
    required this.resourceCount,
  });
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => LearnerStateView(
        icon: icon,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
      );
}
