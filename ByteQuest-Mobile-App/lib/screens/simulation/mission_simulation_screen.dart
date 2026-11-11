import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/simulation_fullscreen_button.dart';
import '../../data/mission_content_data.dart';
import '../../data/mission_phase_guidance.dart';
import '../../models/mission_model.dart';
import '../../services/auth_service.dart';
import '../../services/authoritative_assessment_service.dart';
import '../../services/practice_mission_evidence_service.dart';
import '../../services/progress_resume_service.dart';
import '../../services/practice_progress_service.dart';
import '../../services/practice_coc_session_service.dart';
import '../../widgets/practice_coc_session_panel.dart';
import 'components/equipment_operations.dart';
import 'components/equipment_workspace.dart';
import 'components/incorrect_placement_dialog.dart';
import 'components/mission_task_status.dart';
import 'components/mission_guidance_panel.dart';
import 'components/mission_tutorial_panel.dart';
import 'interactions/mission_interactions.dart';
import 'runtime/mission_evidence_gateway.dart';
import 'runtime/mission_phase_completion_policy.dart';
import 'runtime/mission_runtime_action_reducer.dart';
import 'runtime/mission_runtime_controller.dart';
import 'runtime/mission_runtime_models.dart';
import 'runtime/mission_equipment_simulator.dart';

typedef MissionSubmitCallback = Future<void> Function();

enum _MissionExitChoice { continueMission, saveAndExit, discardProgress }

abstract interface class MissionOrientationCoordinator {
  Future<void> restoreSupportedOrientations();
}

final class SystemMissionOrientationCoordinator
    implements MissionOrientationCoordinator {
  const SystemMissionOrientationCoordinator();

  @override
  Future<void> restoreSupportedOrientations() =>
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
}

/// Lifecycle-owning shell for catalog-backed practice and assessment missions.
class MissionSimulationScreen extends StatefulWidget {
  const MissionSimulationScreen({
    super.key,
    required this.mission,
    required this.definition,
    this.learnerPayload = const {},
    this.controller,
    this.orientationCoordinator = const SystemMissionOrientationCoordinator(),
    this.onSubmit,
    this.timedPractice = false,
    this.practiceUserId,
  });

  final Mission mission;
  final MissionSimulationDefinition definition;
  final Map<String, dynamic> learnerPayload;
  final MissionRuntimeController? controller;
  final MissionOrientationCoordinator orientationCoordinator;
  final MissionSubmitCallback? onSubmit;

  /// Enabled by the production catalog practice route only. Assessment and
  /// injected test controllers retain their existing evidence lifecycle.
  final bool timedPractice;
  final String? practiceUserId;

  @override
  State<MissionSimulationScreen> createState() =>
      _MissionSimulationScreenState();
}

class _MissionSimulationScreenState extends State<MissionSimulationScreen>
    with WidgetsBindingObserver {
  PracticeMissionEvidenceService? _practiceEvidenceService;
  late final MissionRuntimeController _controller =
      widget.controller ?? _createController();
  late final MissionRuntimeState _initialState;
  MissionRuntimeTransition? _pendingInteractionTransition;
  var _restoring = true;
  var _writing = false;
  var _submitting = false;
  var _retryingEvidence = false;
  var _submitted = false;
  var _leaving = false;
  var _allowPop = false;
  var _accessVerified = false;
  String? _restoreFailure;
  String? _technicalFeedback;
  String? _workspaceFeedback;
  bool _lastActionRejected = false;
  bool _tutorialInvite = false;
  int? _tutorialStep;
  final ScrollController _controlsScrollController = ScrollController();
  bool _showGuidance = false;
  bool _showHow = false;
  String? _workspaceMode;
  String? _workspaceModePhaseId;
  OverlayEntry? _guideOutline;
  Rect? _guideOutlineRect;
  String? _guideOutlineKey;
  final GlobalKey _interactionGuideKey = GlobalKey();
  final GlobalKey _operationsGuideKey = GlobalKey();
  final _cocSessionService = const PracticeCocSessionService();
  PracticeCocSession? _cocSession;
  Timer? _cocTicker;
  DateTime? _lastCocCheckpoint;

  MissionRuntimeState get _state => _controller.state;
  String? get _tutorialUserId =>
      widget.practiceUserId ??
      (widget.controller == null ? AuthService().currentUserId : null);

  MissionRuntimeController _createController() {
    final assessment = AuthoritativeAssessmentService.instance;
    final firstPhaseId = widget.definition.phases.first.id;
    final userId = widget.practiceUserId ?? AuthService().currentUserId;
    if (userId == null) {
      throw StateError('An authenticated learner is required.');
    }
    final activeSession = assessment.activeSession;
    final isAssessment = activeSession?.isAssessment == true;
    final MissionEvidenceTransport evidenceTransport;
    if (activeSession == null) {
      final practiceService =
          PracticeMissionEvidenceService(missionId: widget.definition.id);
      _practiceEvidenceService = practiceService;
      evidenceTransport = practiceService;
    } else {
      evidenceTransport = assessment;
    }
    return MissionRuntimeController(
      userId: userId,
      initialState: MissionRuntimeState.initial(
        widget.definition.id,
        mode: isAssessment
            ? MissionRuntimeMode.assessment
            : MissionRuntimeMode.practice,
        assessmentAttemptId: isAssessment ? activeSession!.attemptId : null,
      ).copyWith(currentPhaseId: firstPhaseId),
      store: const SharedPreferencesMissionRuntimeStore(),
      evidenceGateway: MissionEvidenceGateway(transport: evidenceTransport),
      restoreReducer: MissionRuntimeActionReducer(widget.definition),
      submissionPhaseIds: {widget.definition.phases.last.id},
    );
  }

  @override
  void initState() {
    super.initState();
    _initialState = _controller.state;
    WidgetsBinding.instance.addObserver(this);
    _controlsScrollController.addListener(_refreshGuideOutline);
    unawaited(_restore());
    if (widget.timedPractice) {
      _cocTicker =
          Timer.periodic(const Duration(seconds: 1), (_) => _tickCoc());
    }
  }

  bool get _usesCocTimer =>
      widget.timedPractice && _state.mode == MissionRuntimeMode.practice;

  bool get _cocTimeBlocked {
    if (!_usesCocTimer) return false;
    final session = _cocSession;
    final now = DateTime.now().toUtc();
    return session == null ||
        session.expiredAt(now) ||
        session.clockMovedBackAt(now);
  }

  void _tickCoc() {
    if (!mounted || !_usesCocTimer || _cocSession == null) return;
    final now = DateTime.now().toUtc();
    final session = _cocSession!;
    setState(() => _cocSession = session.observedAt(now));
    if (_lastCocCheckpoint == null ||
        now.difference(_lastCocCheckpoint!) >= const Duration(seconds: 15)) {
      _lastCocCheckpoint = now;
      unawaited(_saveCocCheckpoint());
    }
  }

  Future<void> _saveCocCheckpoint() async {
    if (!_usesCocTimer) return;
    final userId = widget.practiceUserId ?? AuthService().currentUserId;
    final session = _cocSession;
    if (userId == null || session == null) return;
    try {
      await _cocSessionService.checkpoint(userId, session);
    } catch (_) {
      if (mounted)
        setState(() =>
            _technicalFeedback = MissionContentData.practiceTimerSaveFailed);
    }
  }

  Future<void> _restore() async {
    try {
      if (widget.controller == null &&
          _state.mode == MissionRuntimeMode.practice) {
        await PracticeProgressService().requireMissionAccess(widget.mission.id);
      }
      _accessVerified = true;
      await _controller.restore();
      if (_state.mode == MissionRuntimeMode.practice) {
        final userId = _tutorialUserId;
        if (userId != null) {
          try {
            _tutorialInvite =
                !await ProgressResumeService.missionTutorialSeen(userId);
          } catch (_) {
            _tutorialInvite = false;
          }
        }
      }
      if (_usesCocTimer) {
        final userId = widget.practiceUserId ?? AuthService().currentUserId;
        if (userId != null) {
          _cocSession =
              await _cocSessionService.load(userId, widget.definition.cocId);
        }
      }
      if (!_hasKnownPhase(_state.currentPhaseId)) {
        _restoreFailure =
            'Saved progress references a mission phase that is no longer '
            'available.';
      }
    } catch (error) {
      _restoreFailure = _accessVerified
          ? 'Saved progress could not be restored for this mission session.'
          : error is StateError && error.message == 'PRACTICE_COC_LOCKED'
              ? MissionContentData.practiceLockedMessage
              : MissionContentData.practiceProgressUnavailable;
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _retryRestore() async {
    setState(() {
      _restoring = true;
      _restoreFailure = null;
    });
    await _restore();
  }

  Future<void> _resetSavedProgress() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text(MissionContentData.resetProgressTitle),
              content: const Text(MissionContentData.resetProgressMessage),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text(MissionContentData.cancelExitLabel)),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.errorRed),
                    child: const Text(MissionContentData.discardProgressLabel)),
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() => _restoring = true);
    try {
      if (!_accessVerified) {
        await PracticeProgressService().requireMissionAccess(widget.mission.id);
        _accessVerified = true;
      }
      await _controller.reset(_initialState);
      _restoreFailure = null;
      _technicalFeedback = null;
      _workspaceFeedback = null;
      _submitted = false;
    } catch (_) {
      _restoreFailure =
          'Saved progress could not be reset. Retry or return to the mission '
          'list.';
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_persistForLifecycle());
      unawaited(_saveCocCheckpoint());
    } else if (state == AppLifecycleState.resumed) {
      _tickCoc();
    }
  }

  Future<bool> _persistForLifecycle() async {
    try {
      await _controller.persist();
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _technicalFeedback =
              'Progress could not be saved. Keep the mission open and retry.';
        });
      }
      return false;
    }
  }

  @override
  void dispose() {
    _clearGuideOutline();
    _cocTicker?.cancel();
    _controlsScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.orientationCoordinator.restoreSupportedOrientations());
    super.dispose();
  }

  void _clearGuideOutline() {
    _guideOutlineKey = null;
    _guideOutlineRect = null;
    _guideOutline?.remove();
    _guideOutline?.dispose();
    _guideOutline = null;
  }

  List<String> _tutorialSteps() {
    final phases = widget.definition.phases;
    final hasEquipmentTab = !widget.definition.cocId.startsWith('coc4') &&
        phases.any((phase) {
          final equipment =
              MissionEquipmentSimulator.map(phase.presentation['equipment']);
          return equipment['placement'] is Map ||
              equipment['connection'] is Map ||
              phase.resolvedInteraction == InteractionFamily.place ||
              phase.resolvedInteraction == InteractionFamily.connect;
        });
    final hasIdentification = phases
        .any((phase) => phase.resolvedInteraction == InteractionFamily.select);
    final hasPlacement = !widget.definition.cocId.startsWith('coc4') &&
        phases.any((phase) {
          final equipment =
              MissionEquipmentSimulator.map(phase.presentation['equipment']);
          return equipment['placement'] is Map ||
              phase.resolvedInteraction == InteractionFamily.place;
        });
    return [
      MissionContentData.tutorialWorkspace,
      MissionContentData.tutorialInstructions,
      if (hasEquipmentTab) MissionContentData.tutorialEquipment,
      if (hasIdentification) MissionContentData.tutorialIdentification,
      if (hasPlacement) MissionContentData.tutorialPlacement,
      MissionContentData.tutorialProgress,
      MissionContentData.tutorialContinue,
    ];
  }

  void _startTutorial() {
    setState(() {
      _tutorialInvite = false;
      _tutorialStep = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final panel = _findGuideControl('mission-tutorial-panel');
      if (panel != null) {
        unawaited(Scrollable.ensureVisible(panel,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : AppTheme.simulationTransitionDuration,
            alignment: .1));
      }
    });
  }

  void _nextTutorialStep() {
    final current = _tutorialStep;
    if (current == null) return;
    if (current + 1 >= _tutorialSteps().length) {
      unawaited(_dismissTutorial());
    } else {
      setState(() => _tutorialStep = current + 1);
    }
  }

  Future<void> _dismissTutorial() async {
    setState(() {
      _tutorialInvite = false;
      _tutorialStep = null;
    });
    final userId = _tutorialUserId;
    if (userId != null) {
      try {
        await ProgressResumeService.markMissionTutorialSeen(userId);
      } catch (_) {
        // A display preference must never block mission interaction.
      }
    }
  }

  void _refreshGuideOutline() {
    if (_guideOutlineKey == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showHow) _paintGuideOutline();
    });
  }

  BuildContext? _findGuideControl(String key) {
    BuildContext? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget.key == ValueKey(key)) {
        found = element;
        return;
      }
      element.visitChildElements(visit);
    }

    (context as Element).visitChildElements(visit);
    return found;
  }

  Future<void> _locateCurrentAction() async {
    if (!mounted || !_showHow || _restoring) return;
    final phase = widget.definition.phases[_phaseIndex];
    final guide = MissionActionGuide.forPhase(phase, _state,
        reviewReady: _controller.canSubmit &&
            MissionEquipmentSimulator.readyForReview(
                widget.definition, _state) &&
            !_submitted);
    final step = guide.currentStep;
    final mode = _workspaceModePhaseId == phase.id ? _workspaceMode : null;
    final oldKey = _guideOutlineKey;
    final String? nextKey;
    if (step?.workspaceMode != null && mode != step!.workspaceMode) {
      nextKey = 'workspace-mode-${step.workspaceMode}';
    } else if (step?.objectId != null && mode == step!.workspaceMode) {
      _clearGuideOutline();
      return; // SimulationScene owns object focus and its outline.
    } else {
      nextKey = step?.controlKey ?? 'mission-next';
    }
    if (oldKey != nextKey) _clearGuideOutline();
    _guideOutlineKey = nextKey;
    final target = _findGuideControl(_guideOutlineKey!);
    if (target == null) {
      _clearGuideOutline();
      return; // A missing widget must never cause an unrelated highlight.
    }
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppTheme.simulationTransitionDuration;
    await Scrollable.ensureVisible(target, duration: motion, alignment: .35);
    if (!mounted || !_showHow) return;
    _paintGuideOutline();
  }

  void _paintGuideOutline() {
    final key = _guideOutlineKey;
    if (key == null) return;
    final target = _findGuideControl(key);
    final overlay = Overlay.of(context);
    final box = target?.findRenderObject();
    final overlayBox = overlay.context.findRenderObject();
    if (box is! RenderBox ||
        overlayBox is! RenderBox ||
        !box.hasSize ||
        !overlayBox.hasSize) return;
    Rect rect = box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
    final scrollable = Scrollable.maybeOf(target!);
    final scrollBox = scrollable?.context.findRenderObject();
    if (scrollBox is RenderBox && scrollBox.hasSize) {
      final viewport =
          scrollBox.localToGlobal(Offset.zero, ancestor: overlayBox) &
              scrollBox.size;
      rect = rect.intersect(viewport);
    }
    rect = rect.intersect(Offset.zero & overlayBox.size);
    _guideOutlineRect = rect.isEmpty ? null : rect.inflate(3);
    _guideOutline ??= OverlayEntry(builder: (_) {
      final bounds = _guideOutlineRect;
      if (bounds == null) return const SizedBox.shrink();
      return Positioned.fromRect(
        rect: bounds,
        child: IgnorePointer(
          key: const ValueKey('mission-guide-outline'),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.primaryBlue, width: 3),
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
      );
    });
    if (_guideOutline!.mounted) {
      _guideOutline!.markNeedsBuild();
    } else {
      overlay.insert(_guideOutline!);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_leave());
        },
        child: _buildScreen(context),
      );

  Widget _buildScreen(BuildContext context) {
    if (_restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_restoreFailure case final failure?) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundLight,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: TechnicalUnavailableState(
                phaseTitle: widget.definition.title,
                message: failure,
                onRetry: () => unawaited(_retryRestore()),
                onReset: _accessVerified
                    ? () => unawaited(_resetSavedProgress())
                    : null,
              ),
            ),
          ),
        ),
      );
    }

    if (_cocTimeBlocked) {
      final now = DateTime.now().toUtc();
      final session = _cocSession;
      return Scaffold(
        backgroundColor: AppTheme.backgroundLight,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(widget.definition.title, style: AppTheme.titleLarge),
                const SizedBox(height: 16),
                if (session != null && session.clockMovedBackAt(now))
                  Text(MissionContentData.practiceTimerClockChanged,
                      style: AppTheme.bodyMedium),
                PracticeCocSessionPanel(
                  key: ValueKey(
                      'mission-coc-session-${widget.definition.cocId}'),
                  cocId: widget.definition.cocId,
                  userId: widget.practiceUserId,
                  onSessionChanged: (value) =>
                      setState(() => _cocSession = value),
                ),
                const SizedBox(height: 12),
                Text(
                    MissionContentData.practiceEvidencePreserved(
                        _state.acceptedEvidenceIds.length,
                        _state.pendingEvidence.length),
                    style: AppTheme.bodySmall),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_leave()),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text(MissionContentData.backLabel),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    final phaseIndex = _phaseIndex;
    final phase = widget.definition.phases[phaseIndex];
    final guidance = MissionPhaseGuidance.forPhase(phase, _state);
    final actionGuide = MissionActionGuide.forPhase(phase, _state,
        reviewReady: _controller.canSubmit &&
            MissionEquipmentSimulator.readyForReview(
                widget.definition, _state) &&
            !_submitted);
    final currentStep = actionGuide.currentStep;
    final activeWorkspaceMode =
        _workspaceModePhaseId == phase.id ? _workspaceMode : null;
    final viewport = MediaQuery.sizeOf(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final wide = viewport.width >= 720 ||
        (viewport.width >= 600 && viewport.width > viewport.height);
    final scene = EquipmentWorkspace(
      definition: widget.definition,
      phase: phase,
      state: _state,
      onAction: (type, target, value) =>
          _recordAction(phase, type, target, value),
      onCameraChanged: (scale, offset) => unawaited(_controller
          .updateCamera(scale, offset.dx, offset.dy)
          .catchError((Object error) {
        if (mounted)
          setState(() => _technicalFeedback =
              MissionContentData.saveProgressFailedMessage);
      })),
      hotspotStates: _equipmentHotspots(),
      saving: _writing,
      feedback: _workspaceFeedback,
      highlightTarget: _showHow ? actionGuide.currentStep?.target : null,
      highlightObjectId: _showHow &&
              currentStep?.workspaceMode != null &&
              activeWorkspaceMode == currentStep!.workspaceMode
          ? currentStep.objectId
          : null,
      onModeChanged: (mode) {
        if (_workspaceModePhaseId == phase.id && _workspaceMode == mode) return;
        setState(() {
          _workspaceModePhaseId = phase.id;
          _workspaceMode = mode;
        });
        if (_showHow) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_locateCurrentAction());
          });
        }
      },
      enabled: !_writing &&
          !_submitting &&
          !_submitted &&
          phase.primaryInteraction != InteractionFamily.review,
    );

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            _MissionHeader(
              title: widget.definition.title,
              environment: widget.definition.environmentLabel,
              phaseTitle: phase.title,
              phaseIndex: phaseIndex,
              phaseCount: widget.definition.phases.length,
              onBack: () => unawaited(_leave()),
            ),
            if (_usesCocTimer && _cocSession != null)
              PracticeCocTimeLabel(
                  session: _cocSession!, now: DateTime.now().toUtc()),
            MissionGuidanceBar(
              guidance: guidance,
              actionGuide: actionGuide,
              expanded: _showGuidance,
              showHow: _showHow,
              onShowHow: () {
                setState(() {
                  _showHow = !_showHow;
                  if (_showHow) _showGuidance = true;
                });
                if (_showHow) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) unawaited(_locateCurrentAction());
                  });
                } else {
                  _clearGuideOutline();
                }
              },
              onReplayTutorial: _state.mode == MissionRuntimeMode.practice
                  ? _startTutorial
                  : null,
              tutorialFirstUse: _tutorialInvite,
              onToggle: () {
                setState(() => _showGuidance = !_showGuidance);
                if (_showGuidance && _controlsScrollController.hasClients) {
                  _controlsScrollController.animateTo(0,
                      duration: AppTheme.simulationTransitionDuration,
                      curve: Curves.easeOut);
                }
              },
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (largeText) {
                    return _buildControls(phase, phaseIndex,
                        leading: SizedBox(height: 400, child: scene));
                  }
                  final controls = KeyedSubtree(
                    key: ValueKey('mission-controls-phase-${phase.id}'),
                    child: _buildControls(phase, phaseIndex),
                  );
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: scene),
                        const VerticalDivider(width: 1),
                        Expanded(
                            flex: 2,
                            child: Column(children: [
                              Expanded(child: controls),
                              _buildActionBar(phase, phaseIndex),
                            ])),
                      ],
                    );
                  }
                  final sceneHeight = (constraints.maxHeight * .56)
                      .clamp(constraints.maxHeight > 260 ? 210.0 : 0.0, 420.0)
                      .toDouble();
                  return Column(
                    children: [
                      SizedBox(height: sceneHeight, child: scene),
                      const Divider(height: 1),
                      Expanded(child: controls),
                    ],
                  );
                },
              ),
            ),
            if (!wide || largeText) _buildActionBar(phase, phaseIndex),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(MissionPhaseDefinition phase, int phaseIndex,
      {Widget? leading}) {
    return Scrollbar(
        controller: _controlsScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _controlsScrollController,
          key: const ValueKey('mission-controls-scroll'),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (leading != null) ...[leading, const SizedBox(height: 12)],
              if (_state.mode == MissionRuntimeMode.practice &&
                  (_tutorialInvite || _tutorialStep != null)) ...[
                MissionTutorialPanel(
                  key: const ValueKey('mission-tutorial-panel'),
                  steps: _tutorialSteps(),
                  stepIndex: _tutorialStep,
                  onStart: _startTutorial,
                  onNext: _nextTutorialStep,
                  onSkip: () => unawaited(_dismissTutorial()),
                  timedPractice: _usesCocTimer,
                ),
                const SizedBox(height: 12),
              ],
              if (_showGuidance) ...[
                MissionGuidancePanel(
                  phase: phase,
                  guidance: MissionPhaseGuidance.forPhase(phase, _state),
                  actionGuide: MissionActionGuide.forPhase(phase, _state,
                      reviewReady: _controller.canSubmit &&
                          MissionEquipmentSimulator.readyForReview(
                              widget.definition, _state) &&
                          !_submitted),
                  practice: _state.mode == MissionRuntimeMode.practice,
                ),
                const SizedBox(height: 12),
              ],
              Text(MissionContentData.controlsScrollHint,
                  style: AppTheme.caption),
              const SizedBox(height: 8),
              if (phaseIndex == 0) ...[
                Text(widget.definition.scenario, style: AppTheme.bodyMedium),
                const SizedBox(height: 12),
              ],
              if (_state.mode == MissionRuntimeMode.practice)
                ExpansionTile(
                    title: const Text(MissionContentData.practiceHintLabel),
                    children: [
                      Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(widget.definition.practiceGuidance))
                    ]),
              if (phaseIndex > 0)
                PopupMenuButton<String>(
                  tooltip: MissionContentData.revisePhaseLabel,
                  enabled: !_writing && !_submitting && !_submitted,
                  onSelected: (id) => unawaited(_revisitPhase(id)),
                  itemBuilder: (_) => [
                    for (final previous
                        in widget.definition.phases.take(phaseIndex))
                      PopupMenuItem(
                          value: previous.id, child: Text(previous.title))
                  ],
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.primaryBlue),
                        borderRadius: AppTheme.radiusSm),
                    child: const ListTile(
                        leading: Icon(Icons.history),
                        title: Text(MissionContentData.revisePhaseLabel),
                        trailing: Icon(Icons.expand_more)),
                  ),
                ),
              if (!_showGuidance) ...[
                Text(phase.title, style: AppTheme.titleMedium),
                const SizedBox(height: 6),
                Text(phase.instruction, style: AppTheme.bodyMedium),
                const SizedBox(height: 12),
              ],
              Container(
                key: _interactionGuideKey,
                decoration: _showHow &&
                        MissionActionGuide.forPhase(phase, _state)
                                .currentStep
                                ?.target ==
                            MissionGuideTarget.controls
                    ? BoxDecoration(
                        border:
                            Border.all(color: AppTheme.primaryBlue, width: 2),
                        borderRadius: AppTheme.radiusSm)
                    : null,
                child: MissionPhaseInteraction(
                  key: ValueKey('mission-interaction-${phase.id}'),
                  phase: phase,
                  state: _state,
                  enabled: !_writing && !_submitting && !_submitted,
                  onAction: (actionType, target, value) =>
                      _recordAction(phase, actionType, target, value),
                  onRuntimeTransition: (transition) {
                    _pendingInteractionTransition = transition;
                  },
                  completedPhaseTitles: widget.definition.phases
                      .where(
                          (item) => _state.completedPhaseIds.contains(item.id))
                      .map((item) => item.title)
                      .toList(growable: false),
                  authoritativeEvidenceCount: _state.acceptedEvidenceIds.length,
                  pendingEvidenceCount: _state.pendingEvidence.length,
                  failedEvidenceCount: _controller.failedPendingEvidence.length,
                  canSubmit: _controller.canSubmit &&
                      MissionEquipmentSimulator.readyForReview(
                          widget.definition, _state) &&
                      !_submitting &&
                      !_submitted &&
                      !_retryingEvidence,
                  retryingPendingEvidence: _retryingEvidence,
                  showReviewConfirmButton: false,
                  returnLabel: widget.definition.reviewMetadata['returnLabel']
                          as String? ??
                      'Return to mission',
                  confirmLabel: widget.definition.reviewMetadata['confirmLabel']
                          as String? ??
                      'Confirm evidence',
                  onReturnFromReview: () => unawaited(_returnFromReview()),
                  onConfirmReview: () => unawaited(_confirmSubmission()),
                  onRetryPendingEvidence: () =>
                      unawaited(_retryPendingEvidence()),
                ),
              ),
              Container(
                key: _operationsGuideKey,
                decoration: _showHow &&
                        MissionActionGuide.forPhase(phase, _state)
                                .currentStep
                                ?.target ==
                            MissionGuideTarget.operations
                    ? BoxDecoration(
                        border:
                            Border.all(color: AppTheme.primaryBlue, width: 2),
                        borderRadius: AppTheme.radiusSm)
                    : null,
                child: EquipmentOperations(
                    phase: phase,
                    state: _state,
                    enabled: !_writing && !_submitting && !_submitted,
                    onAction: (type, target, value) =>
                        _recordAction(phase, type, target, value)),
              ),
              if (_technicalFeedback case final feedback?) ...[
                const SizedBox(height: 14),
                Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundPaleBlue,
                      borderRadius: AppTheme.radiusSm,
                    ),
                    child: Text(feedback, style: AppTheme.bodySmall),
                  ),
                ),
              ],
            ],
          ),
        ));
  }

  Widget _buildActionBar(MissionPhaseDefinition phase, int phaseIndex) {
    final guide = MissionActionGuide.forPhase(phase, _state,
        reviewReady: _controller.canSubmit &&
            MissionEquipmentSimulator.readyForReview(
                widget.definition, _state) &&
            !_submitted);
    if (phase.primaryInteraction == InteractionFamily.review) {
      final equipmentReady =
          MissionEquipmentSimulator.readyForReview(widget.definition, _state);
      final canConfirm = _controller.canSubmit && equipmentReady && !_submitted;
      return MissionActionBar(
        status: _submitted
            ? MissionContentData.reviewSavedLabel
            : _state.pendingEvidence.isNotEmpty
                ? MissionContentData.guideReviewSyncStatus(
                    _state.pendingEvidence.length,
                    _controller.failedPendingEvidence.length)
                : equipmentReady
                    ? MissionContentData.reviewReadyLabel
                    : MissionContentData.guideReviewIncomplete,
        label: widget.definition.reviewMetadata['confirmLabel'] as String? ??
            MissionContentData.confirmEvidenceLabel,
        saving: _writing || _submitting || _retryingEvidence,
        complete: _submitted,
        highlighted: _showHow && canConfirm,
        onContinue: canConfirm ? () => unawaited(_confirmSubmission()) : null,
      );
    }
    final ready = MissionPhaseCompletionPolicy.canAdvance(phase, _state);
    final status = ready
        ? MissionContentData.readyToContinueLabel
        : _lastActionRejected
            ? MissionContentData.guideRejected(
                guide.completedCount,
                guide.steps.length,
                guide.currentStep?.text ??
                    MissionContentData.guideCheckRequirements)
            : MissionContentData.guideBlocked(
                guide.completedCount,
                guide.steps.length,
                guide.currentStep?.text ??
                    MissionContentData.guideCheckRequirements);
    return MissionActionBar(
      status: status,
      saving: _writing,
      highlighted: _showHow && ready,
      label: phaseIndex == widget.definition.phases.length - 2
          ? MissionContentData.reviewEvidenceLabel
          : MissionContentData.continueLabel,
      onContinue: ready && !_submitting && !_submitted
          ? () => unawaited(_advance(phaseIndex))
          : null,
    );
  }

  Map<String, HotspotVisualState> _equipmentHotspots() {
    final visual = {
      ..._state.hotspotStates,
      for (final part in _state.placements.keys)
        part: HotspotVisualState.completed
    };
    final running = _state.equipmentState['service_running'];
    if (running is bool) {
      visual['service_console'] =
          running ? HotspotVisualState.completed : HotspotVisualState.error;
      visual['status_monitor'] = visual['service_console']!;
    }
    final results =
        MissionEquipmentSimulator.map(_state.equipmentState['results']);
    if (results.isNotEmpty && widget.definition.scene.objects.isNotEmpty) {
      final latest = MissionEquipmentSimulator.map(results.values.last);
      final fresh = latest['input_revision'] ==
          (_state.equipmentState['input_revision'] ?? 0);
      visual[widget.definition.scene.objects.first.id] = !fresh
          ? HotspotVisualState.selected
          : latest['operating'] == true
              ? HotspotVisualState.completed
              : HotspotVisualState.error;
    }
    return visual;
  }

  int get _phaseIndex {
    final phaseId = _state.currentPhaseId;
    final index = widget.definition.phases.indexWhere(
      (phase) => phase.id == phaseId,
    );
    if (index < 0) {
      throw StateError('The active mission phase is not in the catalog.');
    }
    return index;
  }

  bool _hasKnownPhase(String? phaseId) =>
      widget.definition.phases.any((phase) => phase.id == phaseId);

  Future<void> _recordAction(
    MissionPhaseDefinition phase,
    String emittedActionType,
    String? target,
    Map<String, dynamic> value,
  ) async {
    if (_cocTimeBlocked) {
      _pendingInteractionTransition = null;
      return;
    }
    if (_writing) return;
    final queuedTransition = _pendingInteractionTransition;
    _pendingInteractionTransition = null;
    final actionValue = MissionEquipmentSimulator.describeAction(
      definition: widget.definition,
      phase: phase,
      state: _state,
      actionType: emittedActionType,
      target: target,
      value: value,
    );
    final wrongSlot = _state.mode == MissionRuntimeMode.practice &&
        emittedActionType == 'placement_attempted' &&
        ((actionValue['simulation_valid'] == false &&
                actionValue['simulation_feedback'] ==
                    MissionContentData.incompatiblePlacementFeedback) ||
            (actionValue['simulation_valid'] == null &&
                actionValue['compatible'] == false));
    setState(() {
      _writing = true;
      _lastActionRejected = actionValue['simulation_valid'] == false ||
          actionValue['compatible'] == false;
      _workspaceFeedback =
          !wrongSlot && actionValue['simulation_valid'] == false
              ? actionValue['simulation_feedback'] as String?
              : null;
      if (wrongSlot) _technicalFeedback = null;
    });
    if (wrongSlot) {
      final equipment =
          MissionEquipmentSimulator.map(phase.presentation['equipment']);
      final placement = MissionEquipmentSimulator.map(equipment['placement']);
      final part = MissionEquipmentSimulator.item(
          placement['items'] ?? phase.presentation['items'], value['item_id']);
      final slot = MissionEquipmentSimulator.item(
          placement['destinations'] ?? phase.presentation['destinations'],
          value['destination_id']);
      unawaited(showIncorrectPlacementDialog(
        context,
        message: MissionContentData.incorrectPlacementMessage(
          actionValue['simulation_feedback'] as String? ??
              MissionContentData.incompatiblePlacementFeedback,
          part['label'] as String?,
          slot['label'] as String?,
        ),
      ));
    }
    try {
      await _controller.dispatch(
        phaseId: phase.id,
        actionType: _adaptActionType(phase, emittedActionType),
        target: target,
        value: {...actionValue, 'runtime_action_type': emittedActionType},
        transition: (state) {
          final interactionTransition =
              (actionValue.containsKey('equipment_snapshot')
                      ? null
                      : queuedTransition) ??
                  (runtime) => MissionRuntimeActionReducer.transitionForAction(
                        runtime,
                        emittedActionType,
                        target,
                        actionValue,
                      );
          final transitioned = interactionTransition(state);
          return MissionPhaseCompletionPolicy.afterAction(
            phase: phase,
            state: transitioned,
            emittedActionType: emittedActionType,
            target: target,
            value: actionValue,
          );
        },
      );
      if (wrongSlot) {
        _technicalFeedback = null;
      } else if (actionValue['simulation_feedback'] is String) {
        _technicalFeedback = actionValue['simulation_feedback'] as String;
      } else if (phase.feedbackIds.isNotEmpty) {
        _technicalFeedback =
            widget.definition.feedbackCatalog[phase.feedbackIds.first];
      } else {
        _technicalFeedback = 'Technical evidence recorded.';
      }
    } catch (_) {
      _showActionError(MissionContentData.technicalEvidenceSyncFailed,
          onRetry: _state.pendingEvidence.isNotEmpty
              ? () => unawaited(_retryPendingEvidence())
              : null);
    } finally {
      if (mounted) {
        setState(() => _writing = false);
        if (_showHow) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_locateCurrentAction());
          });
        }
      }
    }
  }

  String _adaptActionType(
    MissionPhaseDefinition phase,
    String emittedActionType,
  ) {
    if (emittedActionType == 'equipment_operation') return emittedActionType;
    if (phase.resolvedInteraction == InteractionFamily.testRun) {
      if (emittedActionType != 'test_completed') return emittedActionType;
      final evidenceType = phase.presentation['evidenceActionType'];
      if (evidenceType is String && evidenceType.isNotEmpty) {
        return evidenceType;
      }
    }
    final protectedType = phase.presentation['action_type'];
    if (protectedType is String && protectedType.isNotEmpty) {
      return protectedType;
    }
    final configuredType = phase.presentation['actionType'];
    if (configuredType is String && configuredType.isNotEmpty) {
      return configuredType;
    }
    return emittedActionType;
  }

  Future<void> _advance(int phaseIndex) async {
    if (_writing ||
        _cocTimeBlocked ||
        phaseIndex >= widget.definition.phases.length - 1) return;
    final current = widget.definition.phases[phaseIndex];
    if (!MissionPhaseCompletionPolicy.canAdvance(current, _state)) return;
    final next = widget.definition.phases[phaseIndex + 1];
    setState(() {
      _writing = true;
      _workspaceFeedback = null;
    });
    try {
      await _controller.dispatch(
        phaseId: current.id,
        actionType: 'phase_completed',
        target: next.id,
        value: const {'input_method': 'button'},
        transition: (state) => state.copyWith(
          currentPhaseId: next.id,
          completedPhaseIds: {...state.completedPhaseIds, current.id},
        ),
      );
      _technicalFeedback = null;
      if (_controlsScrollController.hasClients)
        _controlsScrollController.jumpTo(0);
    } catch (_) {
      _showActionError(MissionContentData.phaseSaveFailed,
          onRetry: () => unawaited(_advance(phaseIndex)));
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _returnFromReview() async {
    final reviewIndex = _phaseIndex;
    if (_writing || _cocTimeBlocked || reviewIndex == 0) return;
    final previous = widget.definition.phases[reviewIndex - 1];
    final review = widget.definition.phases[reviewIndex];
    setState(() => _writing = true);
    try {
      await _controller.dispatch(
        phaseId: review.id,
        actionType: 'review_returned',
        target: previous.id,
        value: const {'input_method': 'button'},
        transition: (state) => state.copyWith(currentPhaseId: previous.id),
      );
    } catch (_) {
      _showActionError(MissionContentData.reviewSaveFailed,
          onRetry: () => unawaited(_returnFromReview()));
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _revisitPhase(String destination) async {
    if (_writing || _cocTimeBlocked || !_hasKnownPhase(destination)) return;
    final phase = widget.definition.phases[_phaseIndex];
    setState(() {
      _writing = true;
      _workspaceFeedback = null;
    });
    try {
      await _controller.dispatch(
          phaseId: phase.id,
          actionType: 'review_returned',
          target: destination,
          value: const {'input_method': 'phase_menu'},
          transition: (state) => state.copyWith(currentPhaseId: destination));
      _technicalFeedback = null;
    } catch (_) {
      _showActionError(MissionContentData.saveProgressFailedMessage,
          onRetry: () => unawaited(_revisitPhase(destination)));
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _confirmSubmission() async {
    if (_submitting ||
        _submitted ||
        _cocTimeBlocked ||
        !_controller.canSubmit ||
        !MissionEquipmentSimulator.readyForReview(widget.definition, _state))
      return;
    setState(() => _submitting = true);
    try {
      if (widget.onSubmit case final callback?) {
        await callback();
      } else if (_state.mode == MissionRuntimeMode.practice) {
        // Practice evidence has already been persisted locally and synced by
        // the runtime gateway. Confirming review must never create an
        // authoritative result or award competency.
        await _controller.persist();
        if (_practiceEvidenceService != null) {
          await PracticeProgressService().verifyMission(widget.mission.id);
        }
      } else {
        await _submitAuthoritatively();
      }
      _submitted = true;
      _technicalFeedback = _state.mode == MissionRuntimeMode.practice
          ? MissionContentData.practiceSavedMessage
          : 'Evidence submitted for authoritative evaluation and review.';
    } catch (_) {
      _showActionError(
          _state.mode == MissionRuntimeMode.practice
              ? MissionContentData.practiceSubmitFailed
              : MissionContentData.assessmentSubmitFailed,
          onRetry: () => unawaited(_confirmSubmission()));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showActionError(String message, {VoidCallback? onRetry}) {
    _technicalFeedback = message;
    if (!mounted) return;
    final phaseId = _state.currentPhaseId;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      content: Text(message),
      action: onRetry == null
          ? null
          : SnackBarAction(
              label: MissionContentData.retryActionLabel,
              onPressed: () {
                if (mounted &&
                    !_writing &&
                    !_submitting &&
                    !_retryingEvidence &&
                    _state.currentPhaseId == phaseId) {
                  if (_state.pendingEvidence.isNotEmpty) {
                    unawaited(_retryPendingEvidence());
                  } else {
                    onRetry();
                  }
                }
              }),
    ));
  }

  Future<void> _retryPendingEvidence() async {
    if (_retryingEvidence || _state.pendingEvidence.isEmpty) return;
    setState(() {
      _retryingEvidence = true;
      _technicalFeedback = MissionContentData.retryingPendingEvidenceFeedback;
    });
    late final String feedback;
    try {
      await _controller.flushPending();
      feedback = _state.pendingEvidence.isEmpty
          ? MissionContentData.pendingEvidenceSynchronizedFeedback
          : MissionContentData.pendingEvidenceRetryFailedFeedback;
    } catch (_) {
      feedback = MissionContentData.pendingEvidenceRetryFailedFeedback;
    } finally {
      if (mounted) {
        setState(() {
          _retryingEvidence = false;
          _technicalFeedback = feedback;
        });
      }
    }
  }

  Future<void> _submitAuthoritatively() async {
    final assessment = AuthoritativeAssessmentService.instance;
    if (assessment.activeSession == null) {
      throw StateError('No authoritative attempt is active.');
    }
    await assessment.submitAttempt(
      finalEvidence: {
        'mission_id': widget.definition.id,
        'runtime_schema_version': MissionRuntimeState.schemaVersion,
      },
    );
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    final choice = await showDialog<_MissionExitChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(MissionContentData.runtimeExitMissionTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _state.mode == MissionRuntimeMode.practice
                  ? MissionContentData.runtimeExitMissionMessage
                  : MissionContentData.exitMissionMessage,
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(_MissionExitChoice.continueMission),
              child: const Text(MissionContentData.continueMissionLabel),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(_MissionExitChoice.saveAndExit),
              child: const Text(MissionContentData.confirmExitLabel),
            ),
            if (_state.mode == MissionRuntimeMode.practice) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(dialogContext)
                    .pop(_MissionExitChoice.discardProgress),
                style: TextButton.styleFrom(foregroundColor: AppTheme.errorRed),
                child: const Text(MissionContentData.discardProgressLabel),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == null || choice == _MissionExitChoice.continueMission) {
      setState(() => _leaving = false);
      return;
    }

    if (choice == _MissionExitChoice.discardProgress) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: const Text(MissionContentData.discardProgressTitle),
                content: const Text(MissionContentData.discardProgressMessage),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text(MissionContentData.cancelExitLabel)),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.errorRed),
                      child:
                          const Text(MissionContentData.discardProgressLabel)),
                ],
              ));
      if (!mounted) return;
      if (confirmed != true) {
        setState(() => _leaving = false);
        return;
      }
      try {
        await _practiceEvidenceService?.markProgressDiscarded(
          phaseId: _state.currentPhaseId ?? widget.definition.phases.first.id,
        );
        await _controller.reset(_initialState);
      } catch (_) {
        if (mounted) {
          setState(() {
            _leaving = false;
            _technicalFeedback =
                MissionContentData.discardProgressFailedMessage;
          });
        }
        return;
      }
    } else {
      final saved = await _persistForLifecycle();
      if (!mounted) return;
      if (!saved) {
        setState(() => _leaving = false);
        return;
      }
    }

    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await Navigator.of(context).maybePop();
  }
}

/// Maps catalog interaction declarations to the fourteen runtime components.
/// Unknown component names and structurally incomplete declarations render a
/// technical unavailable state rather than an inert control or exception.
class MissionPhaseInteraction extends StatelessWidget {
  const MissionPhaseInteraction({
    super.key,
    required this.phase,
    required this.state,
    required this.onAction,
    required this.onRuntimeTransition,
    required this.onReturnFromReview,
    required this.onConfirmReview,
    this.completedPhaseTitles = const [],
    this.authoritativeEvidenceCount = 0,
    this.pendingEvidenceCount = 0,
    this.failedEvidenceCount = 0,
    this.canSubmit = false,
    this.retryingPendingEvidence = false,
    this.showReviewConfirmButton = true,
    this.returnLabel = 'Return',
    this.confirmLabel = 'Confirm submission',
    this.enabled = true,
    this.onRetryPendingEvidence,
  });

  final MissionPhaseDefinition phase;
  final MissionRuntimeState state;
  final MissionActionCallback onAction;
  final ScenarioRuntimeTransitionCallback onRuntimeTransition;
  final VoidCallback onReturnFromReview;
  final VoidCallback onConfirmReview;
  final List<String> completedPhaseTitles;
  final int authoritativeEvidenceCount;
  final int pendingEvidenceCount;
  final int failedEvidenceCount;
  final bool canSubmit;
  final bool retryingPendingEvidence;
  final bool showReviewConfirmButton;
  final String returnLabel;
  final String confirmLabel;
  final bool enabled;
  final VoidCallback? onRetryPendingEvidence;

  @override
  Widget build(BuildContext context) {
    try {
      return _buildComponent(phase.resolvedInteraction);
    } catch (_) {
      return TechnicalUnavailableState(phaseTitle: phase.title);
    }
  }

  Widget _buildComponent(InteractionFamily component) {
    final adaptedPhase = _adaptedPhase(component);
    if (!_hasRequiredInputs(component, adaptedPhase)) {
      return TechnicalUnavailableState(phaseTitle: phase.title);
    }
    return switch (component) {
      InteractionFamily.inspect => TapInspectInteraction(
          phase: adaptedPhase,
          state: state,
          onAction: onAction,
          enabled: enabled,
        ),
      InteractionFamily.select => MultiSelectInteraction(
          phase: adaptedPhase,
          state: state,
          onAction: onAction,
          enabled: enabled,
        ),
      InteractionFamily.tool => ToolSelectionInteraction(
          phase: adaptedPhase,
          state: state,
          onAction: onAction,
          enabled: enabled,
        ),
      InteractionFamily.connect => ConnectionInteraction(
          phase: adaptedPhase,
          state: state,
          onAction: onAction,
          enabled: enabled,
        ),
      InteractionFamily.configure => ConfigurationPanel(
          phase: adaptedPhase,
          state: state,
          onAction: onAction,
          enabled: enabled,
        ),
      InteractionFamily.sequence => SequencingInteraction(
          phase: adaptedPhase,
          state: state,
          onAction: onAction,
          enabled: enabled,
        ),
      InteractionFamily.match => MatchingInteraction(
          phase: adaptedPhase,
          state: state,
          onAction: onAction,
          enabled: enabled,
        ),
      InteractionFamily.place => ControlledPlacementInteraction(
          phase: adaptedPhase,
          state: state,
          onAction: onAction,
          enabled: enabled,
        ),
      InteractionFamily.troubleshoot => TroubleshootingBranchInteraction(
          phase: adaptedPhase,
          state: state,
          onAction: onAction,
          enabled: enabled,
        ),
      InteractionFamily.testRun => TestRunInteraction(
          phase: adaptedPhase,
          state: state,
          onAction: onAction,
          enabled: enabled,
        ),
      InteractionFamily.observe => ObservationInteraction(
          phase: adaptedPhase,
          state: state,
          onAction: onAction,
          enabled: enabled,
        ),
      InteractionFamily.decide => ScenarioDecisionInteraction(
          phase: adaptedPhase,
          state: state,
          onAction: onAction,
          onRuntimeTransition: onRuntimeTransition,
          enabled: enabled,
        ),
      InteractionFamily.interpret => ResultInterpretationInteraction(
          phase: adaptedPhase,
          state: state,
          onAction: onAction,
          enabled: enabled,
        ),
      InteractionFamily.review => EvidenceReviewPanel(
          completedPhaseTitles: completedPhaseTitles,
          authoritativeEvidenceCount: authoritativeEvidenceCount,
          pendingEvidenceCount: pendingEvidenceCount,
          failedEvidenceCount: failedEvidenceCount,
          canSubmit: canSubmit,
          onReturn: onReturnFromReview,
          onConfirm: onConfirmReview,
          onRetryPending: onRetryPendingEvidence,
          retryingPending: retryingPendingEvidence,
          showConfirmButton: showReviewConfirmButton,
          returnLabel: returnLabel,
          confirmLabel: confirmLabel,
        ),
    };
  }

  MissionPhaseDefinition _adaptedPhase(InteractionFamily component) {
    if (component != InteractionFamily.sequence) return phase;
    if (_nonEmptyList(phase.presentation['items'])) return phase;
    final rawItems = phase.presentation['conductors'];
    final items = _nonEmptyList(rawItems)
        ? rawItems
        : [
            for (final id in phase.availableObjectIds)
              {'id': id, 'label': _labelForId(id)},
          ];
    return MissionPhaseDefinition(
      id: phase.id,
      title: phase.title,
      instruction: phase.instruction,
      primaryInteraction: phase.primaryInteraction,
      supportingInteractions: phase.supportingInteractions,
      availableObjectIds: phase.availableObjectIds,
      feedbackIds: phase.feedbackIds,
      presentation: {...phase.presentation, 'items': items},
    );
  }

  bool _hasRequiredInputs(
    InteractionFamily component,
    MissionPhaseDefinition candidate,
  ) {
    final data = candidate.presentation;
    return switch (component) {
      InteractionFamily.inspect ||
      InteractionFamily.select =>
        candidate.availableObjectIds.isNotEmpty ||
            _nonEmptyList(data['objects']) ||
            _nonEmptyList(data['options']),
      InteractionFamily.tool =>
        _nonEmptyList(data['targets']) && _nonEmptyList(data['tools']),
      InteractionFamily.connect ||
      InteractionFamily.match =>
        _nonEmptyList(data['sources']) && _nonEmptyList(data['destinations']),
      InteractionFamily.configure => _nonEmptyList(data['fields']),
      InteractionFamily.sequence => _nonEmptyList(data['items']),
      InteractionFamily.place =>
        _nonEmptyList(data['items']) && _nonEmptyList(data['destinations']),
      InteractionFamily.troubleshoot => _nonEmptyList(
          data['diagnostic_actions'],
        ),
      InteractionFamily.decide => _nonEmptyList(data['choices']),
      InteractionFamily.testRun ||
      InteractionFamily.observe ||
      InteractionFamily.interpret ||
      InteractionFamily.review =>
        true,
    };
  }

  bool _nonEmptyList(dynamic value) => value is List && value.isNotEmpty;

  String _labelForId(String id) => id
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

class TechnicalUnavailableState extends StatelessWidget {
  const TechnicalUnavailableState({
    super.key,
    required this.phaseTitle,
    this.message,
    this.onRetry,
    this.onReset,
  });

  final String phaseTitle;
  final String? message;
  final VoidCallback? onRetry;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: '$phaseTitle is not available',
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceMuted,
            borderRadius: AppTheme.radiusSm,
            border: Border.all(color: AppTheme.borderMedium),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.build_circle_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message ??
                          'This technical interaction is not available. '
                              'Return to the mission list or contact your '
                              'Instructor.',
                    ),
                    if (onRetry != null || onReset != null) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (onRetry != null)
                            OutlinedButton(
                              onPressed: onRetry,
                              child: const Text('Retry restore'),
                            ),
                          if (onReset != null)
                            FilledButton(
                              onPressed: onReset,
                              child: const Text('Reset saved progress'),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _MissionHeader extends StatelessWidget {
  const _MissionHeader({
    required this.title,
    required this.environment,
    required this.phaseTitle,
    required this.phaseIndex,
    required this.phaseCount,
    required this.onBack,
  });

  final String title;
  final String environment;
  final String phaseTitle;
  final int phaseIndex;
  final int phaseCount;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('mission-header'),
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: AppTheme.borderLight)),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: MissionContentData.exitMissionTooltip,
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.titleSmall,
                  ),
                  Text(
                    MissionContentData.phasePosition(
                        phaseIndex + 1, phaseCount, phaseTitle),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const SimulationFullscreenButton(),
            const SizedBox(width: 4),
            Semantics(
              label: 'Phase ${phaseIndex + 1} of $phaseCount',
              child: Text(
                '${phaseIndex + 1}/$phaseCount',
                style: AppTheme.labelLarge,
              ),
            ),
          ],
        ),
      );
}
