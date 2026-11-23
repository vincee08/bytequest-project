import '../screens/simulation/runtime/mission_equipment_simulator.dart';
import '../screens/simulation/runtime/mission_phase_completion_policy.dart';
import '../screens/simulation/runtime/mission_runtime_models.dart';
import 'mission_content_data.dart';
import 'mission_lab_phases.dart';

/// Phases played on the COC1 M2 assembly bench, which replaces the card
/// panels with the bench, its hotspots and its tray.
bool _isBench(MissionPhaseDefinition phase) =>
    phase.presentation['bench_steps'] is List;

/// Learner instructions for the rendered interaction, with no evaluator answers.
/// The catalog remains the source of objectives and required equipment actions.
final class MissionPhaseGuidance {
  MissionPhaseGuidance._({
    required this.interactionLabel,
    required this.summary,
    required this.steps,
    required this.hint,
    required this.progress,
    required this.remaining,
    this.benchStep,
  });

  final String interactionLabel;
  final String summary;
  final List<String> steps;
  final String hint;
  final List<String> progress;
  final String remaining;

  /// Practice on the assembly bench: the first unfinished bench step, the
  /// same step the bench header shows ("Step 6 of 9"). Null when every step
  /// is done, off the bench and in assessment (which shows no guidance).
  final String? benchStep;

  static MissionPhaseGuidance forPhase(
    MissionPhaseDefinition phase,
    MissionRuntimeState state,
  ) {
    final family = phase.resolvedInteraction;
    final presentation = phase.presentation;
    final equipment = state.mode == MissionRuntimeMode.practice
        ? MissionEquipmentSimulator.map(presentation['equipment'])
        : <String, dynamic>{};
    final placement = MissionEquipmentSimulator.map(equipment['placement']);
    final connection = MissionEquipmentSimulator.map(equipment['connection']);
    final configuration =
        MissionEquipmentSimulator.map(equipment['configuration']);
    final groups =
        MissionEquipmentSimulator.maps(equipment['selection_groups']);
    final operations = MissionEquipmentSimulator.maps(equipment['operations']);
    final hasTools = equipment['tools'] is List && equipment['targets'] is List;
    final hasPlacement = placement.isNotEmpty;
    final canDragPlacement =
        presentation['allow_drag'] != false && !phase.id.startsWith('coc4');
    final isIdentification = phase.id == 'coc1_m1_p1' ||
        phase.id == 'coc1_m1_p2' ||
        (phase.id == 'coc4_m1_p1' && family == InteractionFamily.inspect);
    final steps = <String>[];

    if (hasPlacement && family != InteractionFamily.place) {
      steps.add(MissionContentData.guidanceSupplementalPlacement);
    }
    if (connection.isNotEmpty && family != InteractionFamily.connect) {
      steps.add(MissionContentData.guidanceSupplementalConnection);
    }
    if (configuration.isNotEmpty && family != InteractionFamily.configure) {
      steps.add(MissionContentData.guidanceSupplementalConfiguration);
    }
    if (groups.isNotEmpty) {
      steps.add(MissionContentData.guidanceRoleSelection);
    }
    if (hasTools && family != InteractionFamily.tool) {
      steps.add(MissionContentData.guidanceSupplementalTool);
    }

    steps.addAll(switch (family) {
      InteractionFamily.inspect => [
          MissionContentData.guidanceInspectObjects,
          MissionContentData.guidanceReadInspection,
          MissionContentData.guidanceInspectFinish,
        ],
      InteractionFamily.select => groups.isNotEmpty
          ? [
              MissionContentData.guidanceChooseItems,
              MissionContentData.guidanceConfirmSelection,
              MissionContentData.guidanceRoleSelectionFinish,
            ]
          : [
              MissionContentData.guidanceChooseItems,
              MissionContentData.guidanceConfirmSelection,
            ],
      InteractionFamily.tool => [
          MissionContentData.guidanceChooseTool,
          MissionContentData.guidanceApplyTool,
        ],
      InteractionFamily.connect => [
          MissionContentData.guidanceChooseConnectionSource,
          MissionContentData.guidanceChooseConnectionDestination,
          MissionContentData.guidanceCheckConnection,
        ],
      InteractionFamily.configure => [
          MissionContentData.guidanceOpenConfiguration,
          MissionContentData.guidanceEnterConfiguration,
          MissionContentData.guidanceApplyConfiguration,
        ],
      InteractionFamily.sequence => [
          MissionContentData.guidanceReadSequence,
          MissionContentData.guidanceArrangeSequence,
          MissionContentData.guidanceApplySequence,
        ],
      InteractionFamily.match => [
          MissionContentData.guidanceChooseMatchSource,
          MissionContentData.guidanceChooseMatchDestination,
          MissionContentData.guidanceMatchFinish,
        ],
      InteractionFamily.place => [
          MissionContentData.guidanceChooseComponent,
          if (canDragPlacement) MissionContentData.guidanceDragComponent,
          MissionContentData.guidanceConfirmPlacement,
          MissionContentData.guidancePlaceFinish,
        ],
      InteractionFamily.troubleshoot => [
          MissionContentData.guidanceReadSymptom,
          MissionContentData.guidanceRunDiagnostic,
          MissionContentData.guidanceUseFindings,
        ],
      InteractionFamily.testRun => [
          MissionContentData.guidanceRunTest,
          MissionContentData.guidanceReadTest,
          if (presentation['requires_interpretation'] == true)
            MissionContentData.guidanceInterpretTest,
        ],
      InteractionFamily.observe => [
          MissionContentData.guidanceObserveCondition,
          MissionContentData.guidanceRecordObservation,
        ],
      InteractionFamily.decide => [
          MissionContentData.guidanceReviewEvidence,
          MissionContentData.guidanceChooseDecision,
        ],
      InteractionFamily.interpret => [
          MissionContentData.guidanceReadResult,
          MissionContentData.guidanceRecordInterpretation,
        ],
      InteractionFamily.review => [
          MissionContentData.guidanceReviewRecordedWork,
          MissionContentData.guidanceRetryEvidence,
          MissionContentData.guidanceConfirmEvidence,
        ],
    });
    if (operations.isNotEmpty && family != InteractionFamily.review) {
      steps.add(MissionContentData.guidanceEquipmentOperations);
    }
    if (_isBench(phase) && family != InteractionFamily.review) {
      // The assembly bench is worked where the parts are and from the tray
      // below it; it has none of the card panels named above.
      steps
        ..clear()
        ..addAll(switch (family) {
          InteractionFamily.inspect => [
              MissionContentData.benchGuidanceInspect,
              MissionContentData.guidanceReadInspection,
            ],
          InteractionFamily.place => [
              MissionContentData.benchGuidanceSelectPart,
              MissionContentData.benchGuidanceRotatePart,
              MissionContentData.benchGuidanceDropPart,
              MissionContentData.guidancePlaceFinish,
            ],
          InteractionFamily.connect => [
              MissionContentData.benchGuidanceSelectCable,
              MissionContentData.benchGuidanceDragCable,
              MissionContentData.guidanceCheckConnection,
            ],
          _ => [
              MissionContentData.guidanceRunTest,
              MissionContentData.guidanceReadTest,
              if (presentation['requires_interpretation'] == true)
                MissionContentData.guidanceInterpretTest,
              if (hasPlacement ||
                  connection.isNotEmpty ||
                  operations.isNotEmpty)
                MissionContentData.benchGuidanceFixFaults,
            ],
        })
        ..addAll([
          if (family == InteractionFamily.place && connection.isNotEmpty)
            MissionContentData.benchGuidanceSelectCable,
          if (operations.isNotEmpty && family != InteractionFamily.testRun)
            MissionContentData.benchGuidanceOperate,
        ]);
    }
    // A realistic lab has none of the card panels named above either.
    final lab = MissionLabPhases.panel(phase.id,
        practice: state.mode == MissionRuntimeMode.practice);
    if (lab != null) {
      steps
        ..clear()
        ..addAll(lab.steps);
    }

    final progress = <String>[];
    void addCount(
        String label, Iterable<String> ids, bool Function(String) done) {
      final required = ids.toSet();
      if (required.isEmpty) return;
      progress.add(MissionContentData.taskCount(
          label, required.where(done).length, required.length));
    }

    if (family == InteractionFamily.inspect) {
      final ids = _ids(presentation['objects']);
      addCount(
          MissionContentData.inspectionsTaskLabel,
          ids.isEmpty ? phase.availableObjectIds : ids,
          (id) =>
              state.hotspotStates[id] != null &&
              state.hotspotStates[id] != HotspotVisualState.neutral);
    }
    final requiredPlacement =
        family == InteractionFamily.place ? presentation : placement;
    addCount(MissionContentData.placementsTaskLabel,
        _ids(requiredPlacement['items']), state.placements.containsKey);
    final requiredConnection =
        family == InteractionFamily.connect ? presentation : connection;
    addCount(
        MissionContentData.connectionsTaskLabel,
        _ids(requiredConnection['sources']),
        (id) =>
            state.connectedNodePairs.any((pair) => pair.startsWith('$id>')));
    final fields = family == InteractionFamily.configure
        ? presentation['fields']
        : configuration['fields'];
    addCount(
        MissionContentData.configurationTaskLabel,
        _ids(fields),
        (id) =>
            state.configurationValues[id]?.toString().trim().isNotEmpty ==
            true);
    if (family == InteractionFamily.troubleshoot) {
      addCount(
          MissionContentData.diagnosticFindingsProgressLabel,
          _strings(presentation['required_fact_ids']),
          state.revealedFactIds.contains);
    }
    if (groups.isNotEmpty) {
      final classifications = MissionEquipmentSimulator.map(
          state.equipmentState['classifications']);
      addCount(
          MissionContentData.rolesIdentifiedProgressLabel,
          groups.map((group) => group['id']).whereType<String>(),
          (id) =>
              classifications[id] is List &&
              (classifications[id] as List).isNotEmpty);
    }
    final conditions = MissionEquipmentSimulator.maps(equipment['completion']);
    if (conditions.isNotEmpty) {
      progress.add(MissionContentData.taskCount(
          MissionContentData.workOrderChecksProgressLabel,
          conditions
              .where(
                  (item) => MissionEquipmentSimulator.conditionMet(item, state))
              .length,
          conditions.length));
    }
    if (family != InteractionFamily.review &&
        !state.interactionCompletedPhaseIds.contains(phase.id)) {
      progress.add(MissionContentData.guidanceActionPending);
    } else if (progress.isEmpty && family != InteractionFamily.review) {
      progress.add(state.interactionCompletedPhaseIds.contains(phase.id)
          ? MissionContentData.guidanceActionRecorded
          : MissionContentData.guidanceActionPending);
    }
    if (family == InteractionFamily.review) {
      progress.add(MissionContentData.practiceEvidencePreserved(
          state.acceptedEvidenceIds.length, state.pendingEvidence.length));
    }

    final ready = family == InteractionFamily.review
        ? state.pendingEvidence.isEmpty
        : MissionPhaseCompletionPolicy.canAdvance(phase, state);
    // On the bench, the power-on phase's fix parts are a repair, not an
    // inspect-and-place task: it reads as the test it is.
    final placementTask = hasPlacement && !_isBench(phase);
    String? benchStep;
    if (state.mode == MissionRuntimeMode.practice && _isBench(phase)) {
      for (final step in MissionEquipmentSimulator.maps(presentation['bench_steps'])) {
        if (!MissionEquipmentSimulator.conditionsMet(step['done'], state)) {
          benchStep = step['label'] as String?;
          break;
        }
      }
    }
    return MissionPhaseGuidance._(
      benchStep: benchStep,
      interactionLabel: lab?.label ??
          _label(family, placementTask, isIdentification, canDragPlacement),
      summary: '${phase.title}: '
          '${lab?.summary ?? _summary(phase, family, placementTask, isIdentification)}',
      steps: List.unmodifiable(steps),
      hint: lab != null
          ? MissionContentData.labGuidanceHint
          : _hint(family, isIdentification),
      progress: List.unmodifiable(progress),
      remaining: family == InteractionFamily.review
          ? (ready
              ? MissionContentData.reviewReadyLabel
              : MissionContentData.reviewPendingLabel)
          : ready
              ? MissionContentData.readyToContinueLabel
              : progress.join(' · '),
    );
  }

  static List<String> _ids(Object? value) =>
      MissionEquipmentSimulator.maps(value)
          .map((item) => item['id'])
          .whereType<String>()
          .toList(growable: false);

  static List<String> _strings(Object? value) =>
      MissionEquipmentSimulator.strings(value);

  static String _label(InteractionFamily family, bool hasPlacement,
      bool identification, bool canDragPlacement) {
    if (identification) return MissionContentData.guidanceIdentifyLabel;
    if (hasPlacement) return MissionContentData.guidanceInspectPlaceLabel;
    return switch (family) {
      InteractionFamily.inspect => MissionContentData.guidanceInspectLabel,
      InteractionFamily.select => MissionContentData.guidanceSelectLabel,
      InteractionFamily.tool => MissionContentData.guidanceToolLabel,
      InteractionFamily.connect => MissionContentData.guidanceConnectLabel,
      InteractionFamily.configure => MissionContentData.guidanceConfigureLabel,
      InteractionFamily.sequence => MissionContentData.guidanceSequenceLabel,
      InteractionFamily.match => MissionContentData.guidanceMatchLabel,
      InteractionFamily.place => canDragPlacement
          ? MissionContentData.guidancePlaceLabel
          : MissionContentData.guidanceTapPlaceLabel,
      InteractionFamily.troubleshoot =>
        MissionContentData.guidanceTroubleshootLabel,
      InteractionFamily.testRun => MissionContentData.guidanceTestLabel,
      InteractionFamily.observe => MissionContentData.guidanceObserveLabel,
      InteractionFamily.decide => MissionContentData.guidanceDecideLabel,
      InteractionFamily.interpret => MissionContentData.guidanceInterpretLabel,
      InteractionFamily.review => MissionContentData.guidanceReviewLabel,
    };
  }

  static String _summary(MissionPhaseDefinition phase, InteractionFamily family,
      bool hasPlacement, bool identification) {
    if (identification && phase.id == 'coc1_m1_p1') {
      return MissionContentData.guidanceInspectSevenSummary;
    }
    if (identification && phase.id == 'coc1_m1_p2') {
      return MissionContentData.guidanceIdentifyRoleSummary;
    }
    if (identification) return MissionContentData.guidanceInspectSummary;
    if (hasPlacement) return MissionContentData.guidanceInspectPlaceSummary;
    return switch (family) {
      InteractionFamily.inspect => MissionContentData.guidanceInspectSummary,
      InteractionFamily.select => MissionContentData.guidanceSelectSummary,
      InteractionFamily.tool => MissionContentData.guidanceToolSummary,
      InteractionFamily.connect => MissionContentData.guidanceConnectSummary,
      InteractionFamily.configure =>
        MissionContentData.guidanceConfigureSummary,
      InteractionFamily.sequence => MissionContentData.guidanceSequenceSummary,
      InteractionFamily.match => MissionContentData.guidanceMatchSummary,
      InteractionFamily.place => MissionContentData.guidancePlaceSummary,
      InteractionFamily.troubleshoot =>
        MissionContentData.guidanceTroubleshootSummary,
      InteractionFamily.testRun => MissionContentData.guidanceTestSummary,
      InteractionFamily.observe => MissionContentData.guidanceObserveSummary,
      InteractionFamily.decide => MissionContentData.guidanceDecideSummary,
      InteractionFamily.interpret =>
        MissionContentData.guidanceInterpretSummary,
      InteractionFamily.review => MissionContentData.guidanceReviewSummary,
    };
  }

  static String _hint(InteractionFamily family, bool identification) {
    if (identification) return MissionContentData.guidanceIdentificationHint;
    return switch (family) {
      InteractionFamily.place => MissionContentData.guidancePlacementHint,
      InteractionFamily.connect => MissionContentData.guidanceConnectionHint,
      InteractionFamily.configure =>
        MissionContentData.guidanceConfigurationHint,
      InteractionFamily.troubleshoot ||
      InteractionFamily.testRun =>
        MissionContentData.guidanceDiagnosticHint,
      _ => MissionContentData.guidanceGeneralHint,
    };
  }
}

/// A view of recorded runtime actions. This never writes evidence or decides
/// whether a phase can advance; the existing completion policy remains the gate.
enum MissionGuideTarget { objects, place, connect, controls, operations, next }

final class MissionGuideStep {
  const MissionGuideStep(this.text, this.completed, this.target,
      {this.controlKey, this.workspaceMode, this.objectId});

  final String text;
  final bool completed;
  final MissionGuideTarget target;

  /// Stable key of the rendered control; never an answer or screen coordinate.
  final String? controlKey;
  final String? workspaceMode;
  final String? objectId;
}

final class MissionActionGuide {
  const MissionActionGuide._(this.steps, this.ready, this.pendingEvidenceCount,
      {this.submitted = false});

  final List<MissionGuideStep> steps;
  final bool ready;
  final int pendingEvidenceCount;

  /// The review phase after the server accepted the submission. Nothing is
  /// left to do, so the guide confirms the save instead of asking the learner
  /// to return to the mission.
  final bool submitted;

  int get completedCount => steps.where((step) => step.completed).length;
  int get remainingCount => steps.length - completedCount;
  MissionGuideStep? get currentStep {
    for (final step in steps) {
      if (!step.completed) return step;
    }
    return null;
  }

  static MissionActionGuide forPhase(
    MissionPhaseDefinition phase,
    MissionRuntimeState state, {
    bool reviewReady = false,
    bool submitted = false,
  }) {
    final family = phase.resolvedInteraction;
    final saved = submitted && family == InteractionFamily.review;
    final p = phase.presentation;
    final equipment = state.mode == MissionRuntimeMode.practice
        ? MissionEquipmentSimulator.map(p['equipment'])
        : <String, dynamic>{};
    final steps = <MissionGuideStep>[];
    final bench = _isBench(phase);
    // A realistic lab replaces the standard panels of this phase.
    final lab = MissionLabPhases.guide(phase.id);
    final primaryDone = state.interactionCompletedPhaseIds.contains(phase.id);
    void add(String text, bool done, MissionGuideTarget target,
            {String? controlKey, String? workspaceMode, String? objectId}) =>
        steps.add(MissionGuideStep(text, done, target,
            controlKey: controlKey,
            workspaceMode: workspaceMode,
            objectId: objectId));
    void items(Object? raw, String Function(String) text,
        bool Function(String) done, MissionGuideTarget target,
        {String Function(String)? controlKey,
        String? workspaceMode,
        String Function(String)? objectId}) {
      for (final item in MissionEquipmentSimulator.maps(raw)) {
        final id = item['id'] as String?;
        if (id != null) {
          add(text(item['label'] as String? ?? id), done(id), target,
              controlKey: controlKey?.call(id),
              workspaceMode: workspaceMode,
              objectId: objectId?.call(id));
        }
      }
    }

    switch (family) {
      case InteractionFamily.inspect:
        final objects = MissionEquipmentSimulator.maps(p['objects']);
        items(
            objects.isEmpty
                ? [
                    for (final id in phase.availableObjectIds)
                      {'id': id, 'label': id}
                  ]
                : objects,
            bench
                ? MissionContentData.guideBenchInspect
                : MissionContentData.guideInspectItem,
            (id) =>
                state.hotspotStates[id] != null &&
                state.hotspotStates[id] != HotspotVisualState.neutral,
            MissionGuideTarget.objects,
            workspaceMode: 'inspect',
            objectId: (id) => id,
            controlKey: (id) => 'inspect-target-$id');
      case InteractionFamily.select:
        add(
            p['single_choice_on_tap'] == true
                ? MissionContentData.guideIdentify
                : MissionContentData.guideSelect,
            primaryDone,
            MissionGuideTarget.controls,
            controlKey: 'multi-select-options');
      case InteractionFamily.tool:
        add(MissionContentData.guideTool, primaryDone,
            MissionGuideTarget.controls,
            controlKey: 'tool-target-options');
      case InteractionFamily.connect:
        items(
            p['sources'],
            (label) => bench
                ? MissionContentData.guideBenchConnect(label)
                : MissionContentData.guideConnect(
                    label,
                    state.mode == MissionRuntimeMode.practice &&
                        !state.missionId.startsWith('coc4')),
            (id) =>
                state.connectedNodePairs.any((pair) => pair.startsWith('$id>')),
            MissionGuideTarget.connect,
            workspaceMode: state.mode == MissionRuntimeMode.practice &&
                    !state.missionId.startsWith('coc4')
                ? 'connect'
                : null,
            objectId: state.mode == MissionRuntimeMode.practice &&
                    !state.missionId.startsWith('coc4')
                ? (id) => id
                : null,
            controlKey: (id) => 'connection-source-$id');
      case InteractionFamily.configure:
        add(MissionContentData.guideConfigure(_labels(p['fields'])),
            primaryDone, MissionGuideTarget.controls,
            controlKey: _firstKey(p['fields'], 'configuration-field-'));
      case InteractionFamily.sequence:
        add(
            state.missionId.startsWith('coc4')
                ? MissionContentData.guideTapSequence
                : MissionContentData.guideSequence,
            primaryDone,
            MissionGuideTarget.controls,
            controlKey: _firstKey(p['items'], 'sequence-item-'));
      case InteractionFamily.match:
        items(p['sources'], MissionContentData.guideMatch,
            state.matches.containsKey, MissionGuideTarget.controls,
            controlKey: (id) => 'matching-source-$id');
      case InteractionFamily.place:
        items(
            p['items'],
            (label) => bench
                ? MissionContentData.guideBenchPlace(label)
                : MissionContentData.guidePlace(
                    label,
                    state.mode == MissionRuntimeMode.practice &&
                        p['allow_drag'] != false &&
                        !phase.id.startsWith('coc4')),
            state.placements.containsKey,
            MissionGuideTarget.place,
            workspaceMode: state.mode == MissionRuntimeMode.practice &&
                    !state.missionId.startsWith('coc4')
                ? 'place'
                : null,
            objectId: state.mode == MissionRuntimeMode.practice &&
                    !state.missionId.startsWith('coc4')
                ? (id) => id
                : null,
            controlKey: (id) => 'placement-item-$id');
      case InteractionFamily.troubleshoot:
        final facts = MissionEquipmentSimulator.strings(p['required_fact_ids']);
        if (facts.isEmpty) {
          add(MissionContentData.guideDiagnostic, primaryDone,
              MissionGuideTarget.controls,
              controlKey:
                  _firstKey(p['diagnostic_actions'], 'diagnostic-action-'));
        } else {
          for (var i = 0; i < facts.length; i++) {
            add(
                MissionContentData.guideDiagnosticFinding(i + 1),
                state.revealedFactIds.contains(facts[i]),
                MissionGuideTarget.controls,
                controlKey: _diagnosticKeyForFact(
                    p['diagnostic_actions'], facts[i], state));
          }
        }
      case InteractionFamily.testRun:
        final target = p['target'] as String? ?? phase.id;
        add(
            MissionContentData.guideTest,
            state.testStatusFor(target) == MissionTestStatus.completed,
            MissionGuideTarget.controls,
            controlKey: 'test-run-start');
        if (p['requires_interpretation'] == true) {
          add(
              MissionContentData.guideTestInterpret,
              state.interpretations[phase.id]?.toString().trim().isNotEmpty ==
                  true,
              MissionGuideTarget.controls,
              controlKey: 'test-interpretation-${phase.id}');
        }
      case InteractionFamily.observe:
        add(MissionContentData.guideObserve, primaryDone,
            MissionGuideTarget.controls,
            controlKey: 'observation-input-${phase.id}');
      case InteractionFamily.decide:
        add(MissionContentData.guideDecide, primaryDone,
            MissionGuideTarget.controls,
            controlKey: 'decision-options');
      case InteractionFamily.interpret:
        add(MissionContentData.guideInterpret, primaryDone,
            MissionGuideTarget.controls,
            controlKey: 'interpretation-input-${phase.id}');
      case InteractionFamily.review:
        if (saved) {
          add(MissionContentData.reviewSavedLabel, true,
              MissionGuideTarget.next,
              controlKey: 'mission-exit');
          break;
        }
        add(
            state.pendingEvidence.isNotEmpty
                ? MissionContentData.guideReviewPending
                : reviewReady
                    ? MissionContentData.guideReview
                    : MissionContentData.guideReviewIncomplete,
            reviewReady && state.pendingEvidence.isEmpty,
            reviewReady && state.pendingEvidence.isEmpty
                ? MissionGuideTarget.next
                : MissionGuideTarget.controls,
            controlKey: state.pendingEvidence.isNotEmpty
                ? 'retry-pending-evidence'
                : reviewReady
                    ? 'mission-next'
                    : 'review-return');
    }
    if (lab != null) {
      // Same completion as the panels the lab replaces, in the lab's words
      // and pointing at its controls.
      final done = steps.isNotEmpty && steps.every((step) => step.completed);
      steps.clear();
      add(lab.text, done, MissionGuideTarget.controls,
          controlKey: lab.controlKey);
    }
    final primaryKey = lab?.controlKey ?? _primaryControlKey(phase);

    if (family != InteractionFamily.review &&
        !primaryDone &&
        steps.every((step) => step.completed)) {
      add(MissionContentData.guideCheckRequirements, false,
          MissionGuideTarget.controls,
          controlKey: primaryKey);
    }
    for (final condition
        in MissionEquipmentSimulator.maps(equipment['completion'])) {
      final path = condition['path'] as String? ?? '';
      if (_coveredByPrimary(path, family)) continue;
      final met = MissionEquipmentSimulator.conditionMet(condition, state);
      if (lab != null) {
        final step = MissionLabPhases.condition(phase.id, path);
        add(step.text, met, MissionGuideTarget.controls,
            controlKey: step.controlKey);
        continue;
      }
      add(
          bench
              ? _benchConditionText(path, phase, equipment)
              : _conditionText(path, phase, equipment),
          met,
          _targetForPath(path),
          controlKey: _conditionControlKey(path, phase, equipment),
          workspaceMode: _conditionWorkspaceMode(path, state),
          objectId: _conditionObjectId(path, state));
    }
    if (steps.isEmpty) {
      add(MissionContentData.guideCheckRequirements, primaryDone,
          MissionGuideTarget.controls,
          controlKey: primaryKey);
    }
    final ready = family == InteractionFamily.review
        ? saved || (reviewReady && state.pendingEvidence.isEmpty)
        : MissionPhaseCompletionPolicy.canAdvance(phase, state);
    if (!ready && steps.every((step) => step.completed)) {
      add(MissionContentData.guideCheckRequirements, false,
          MissionGuideTarget.controls,
          controlKey: primaryKey);
    }
    return MissionActionGuide._(
        List.unmodifiable(steps), ready, state.pendingEvidence.length,
        submitted: saved);
  }

  static List<String> _labels(Object? raw) =>
      MissionEquipmentSimulator.maps(raw)
          .map((item) => item['label'])
          .whereType<String>()
          .toList(growable: false);

  static String? _firstKey(Object? raw, String prefix) {
    final items = MissionEquipmentSimulator.maps(raw);
    if (items.isEmpty || items.first['id'] is! String) return null;
    return '$prefix${items.first['id']}';
  }

  static String? _diagnosticKeyForFact(
      Object? raw, String factId, MissionRuntimeState state) {
    for (final action in MissionEquipmentSimulator.maps(raw)) {
      if (action['reveals_fact_id'] == factId &&
          MissionEquipmentSimulator.conditionsMet(action['requires'], state)) {
        final id = action['id'];
        return id is String ? 'diagnostic-action-$id' : null;
      }
    }
    // A prerequisite is still missing. The diagnostics section explains it.
    return 'diagnostic-actions';
  }

  static String? _primaryControlKey(MissionPhaseDefinition phase) =>
      switch (phase.resolvedInteraction) {
        InteractionFamily.select => 'multi-select-options',
        InteractionFamily.tool => 'tool-target-options',
        InteractionFamily.configure =>
          _firstKey(phase.presentation['fields'], 'configuration-field-'),
        InteractionFamily.sequence =>
          _firstKey(phase.presentation['items'], 'sequence-item-'),
        InteractionFamily.troubleshoot => 'diagnostic-actions',
        InteractionFamily.testRun => 'test-run-start',
        InteractionFamily.observe => 'observation-input-${phase.id}',
        InteractionFamily.decide => 'decision-options',
        InteractionFamily.interpret => 'interpretation-input-${phase.id}',
        InteractionFamily.review => 'mission-next',
        _ => null,
      };

  static String? _conditionControlKey(String path, MissionPhaseDefinition phase,
      Map<String, dynamic> equipment) {
    final split = path.indexOf('.');
    final kind = split < 0 ? path : path.substring(0, split);
    final id = split < 0 ? '' : path.substring(split + 1);
    return switch (kind) {
      'inspected' => 'inspect-target-$id',
      'placed' => 'placement-item-$id',
      'link' => 'connection-source-${id.split('>').first}',
      'config' => 'configuration-field-$id',
      'classification' => 'classification-$id',
      'tool' => 'tool-target-options',
      'operation' ||
      'setting' =>
        phase.resolvedInteraction == InteractionFamily.troubleshoot ||
                phase.resolvedInteraction == InteractionFamily.decide
            ? 'equipment-operations'
            : _operationKeyForPath(kind, id, equipment),
      'fact' => 'diagnostic-actions',
      'result' => 'test-run-start',
      'observation' => 'observation-input-${phase.id}',
      'interpretation' => 'interpretation-input-${phase.id}',
      'sequence' ||
      'order' =>
        _firstKey(phase.presentation['items'], 'sequence-item-'),
      _ => _primaryControlKey(phase),
    };
  }

  static String _operationKeyForPath(
      String kind, String id, Map<String, dynamic> equipment) {
    if (kind == 'operation' &&
        MissionEquipmentSimulator.maps(equipment['operations'])
            .any((item) => item['id'] == id)) {
      return 'equipment-operation-$id';
    }
    for (final operation
        in MissionEquipmentSimulator.maps(equipment['operations'])) {
      if (MissionEquipmentSimulator.map(operation['effects']).containsKey(id)) {
        return 'equipment-operation-${operation['id']}';
      }
    }
    return 'equipment-operations';
  }

  static String? _conditionWorkspaceMode(
      String path, MissionRuntimeState state) {
    if (state.mode != MissionRuntimeMode.practice ||
        state.missionId.startsWith('coc4')) return null;
    if (path.startsWith('placed.')) return 'place';
    if (path.startsWith('link.')) return 'connect';
    if (path.startsWith('inspected.')) return 'inspect';
    return null;
  }

  static String? _conditionObjectId(String path, MissionRuntimeState state) {
    if (_conditionWorkspaceMode(path, state) == null) return null;
    final split = path.indexOf('.');
    if (split < 0) return null;
    final id = path.substring(split + 1);
    return path.startsWith('link.') ? id.split('>').first : id;
  }

  static bool _coveredByPrimary(String path, InteractionFamily family) =>
      switch (family) {
        InteractionFamily.inspect => path.startsWith('inspected.'),
        InteractionFamily.select => path.startsWith('selection.'),
        InteractionFamily.connect => path.startsWith('link.'),
        InteractionFamily.configure => path.startsWith('config.'),
        InteractionFamily.sequence =>
          path.startsWith('order.') || path.startsWith('sequence.'),
        InteractionFamily.place => path.startsWith('placed.'),
        InteractionFamily.troubleshoot => path.startsWith('fact.'),
        InteractionFamily.testRun => path.startsWith('result.'),
        InteractionFamily.observe => path.startsWith('observation.'),
        InteractionFamily.interpret => path.startsWith('interpretation.'),
        _ => false,
      };

  static MissionGuideTarget _targetForPath(String path) {
    if (path.startsWith('placed.')) return MissionGuideTarget.place;
    if (path.startsWith('link.')) return MissionGuideTarget.connect;
    if (path.startsWith('inspected.')) return MissionGuideTarget.objects;
    if (path.startsWith('operation.') || path.startsWith('setting.')) {
      return MissionGuideTarget.operations;
    }
    return MissionGuideTarget.controls;
  }

  static String _conditionText(String path, MissionPhaseDefinition phase,
      Map<String, dynamic> equipment) {
    final dot = path.indexOf('.');
    final kind = dot < 0 ? path : path.substring(0, dot);
    final id = dot < 0 ? '' : path.substring(dot + 1);
    String label(Object? raw) {
      for (final item in MissionEquipmentSimulator.maps(raw)) {
        if (item['id'] == id) return item['label'] as String? ?? id;
      }
      return id.replaceAll('_', ' ');
    }

    return switch (kind) {
      'inspected' => MissionContentData.guideInspectItem(
          label(phase.presentation['objects'])),
      'placed' => MissionContentData.guidePlace(
          label(MissionEquipmentSimulator.map(equipment['placement'])['items']),
          false),
      'link' => MissionContentData.guideConnectPorts,
      'config' => MissionContentData.guideConfigure([
          label(MissionEquipmentSimulator.map(
              equipment['configuration'])['fields'])
        ]),
      'classification' =>
        MissionContentData.guideClassify(label(equipment['selection_groups'])),
      'selection' => MissionContentData.guideSelect,
      'tool' => MissionContentData.guideToolTarget(label(equipment['targets'])),
      'operation' =>
        phase.resolvedInteraction == InteractionFamily.troubleshoot ||
                phase.resolvedInteraction == InteractionFamily.decide
            ? MissionContentData.guideOperationDecision
            : MissionContentData.guideOperation(label(equipment['operations'])),
      'result' => MissionContentData.guideTest,
      'fact' => MissionContentData.guideDiagnostic,
      'observation' => MissionContentData.guideObserve,
      'interpretation' => MissionContentData.guideInterpret,
      'sequence' || 'order' => MissionContentData.guideSequence,
      'setting' =>
        phase.resolvedInteraction == InteractionFamily.troubleshoot ||
                phase.resolvedInteraction == InteractionFamily.decide
            ? MissionContentData.guideOperationDecision
            : _settingInstruction(id, equipment),
      _ => MissionContentData.guideCheckRequirements,
    };
  }

  /// Work-order checks on the assembly bench, worded for its hotspots and
  /// tray instead of the card panels.
  static String _benchConditionText(String path, MissionPhaseDefinition phase,
      Map<String, dynamic> equipment) {
    final dot = path.indexOf('.');
    final kind = dot < 0 ? path : path.substring(0, dot);
    final id = dot < 0 ? '' : path.substring(dot + 1);
    String? label(Object? raw, bool Function(Map<String, dynamic>) match) {
      for (final item in MissionEquipmentSimulator.maps(raw)) {
        if (match(item)) return item['label'] as String? ?? id;
      }
      return null;
    }

    final operation = switch (kind) {
      'operation' => label(equipment['operations'], (item) => item['id'] == id),
      'setting' => label(
          equipment['operations'],
          (item) =>
              MissionEquipmentSimulator.map(item['effects']).containsKey(id)),
      _ => null,
    };
    return switch (kind) {
      'inspected' => MissionContentData.guideBenchInspect(
          label(phase.presentation['objects'], (item) => item['id'] == id) ??
              id.replaceAll('_', ' ')),
      'placed' => MissionContentData.guideBenchPlace(label(
              MissionEquipmentSimulator.map(equipment['placement'])['items'],
              (item) => item['id'] == id) ??
          id.replaceAll('_', ' ')),
      'link' => MissionContentData.guideBenchConnectPorts,
      'operation' || 'setting' when operation != null =>
        MissionContentData.guideBenchOperation(operation),
      _ => _conditionText(path, phase, equipment),
    };
  }

  static String _settingInstruction(String id, Map<String, dynamic> equipment) {
    for (final operation
        in MissionEquipmentSimulator.maps(equipment['operations'])) {
      if (MissionEquipmentSimulator.map(operation['effects']).containsKey(id)) {
        return MissionContentData.guideOperation(
            operation['label'] as String? ?? id);
      }
    }
    return MissionContentData.guideCheckRequirements;
  }
}
