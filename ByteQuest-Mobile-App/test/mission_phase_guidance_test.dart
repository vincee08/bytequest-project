import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/data/mission_lab_phases.dart';
import 'package:bytequest/data/mission_phase_guidance.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/screens/simulation/components/mission_guidance_panel.dart';
import 'package:bytequest/screens/simulation/runtime/mission_equipment_simulator.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:bytequest/screens/simulation/runtime/mission_phase_completion_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/equipment_practice_driver.dart';

void main() {
  test('every production phase has contextual instructions and progress', () {
    final missions = MissionSimulationDefinitions.all;
    final phases = missions.expand((mission) => mission.phases).toList();
    expect(missions.length, 20);
    // 116: COC1 M2 gained a sixth phase on the assembly bench.
    expect(phases.length, 116);
    expect(phases.map((phase) => phase.resolvedInteraction).toSet().length, 13);
    for (final mission in missions) {
      for (final phase in mission.phases) {
        final state = MissionRuntimeState.initial(mission.id)
            .copyWith(currentPhaseId: phase.id);
        final guidance = MissionPhaseGuidance.forPhase(phase, state);
        final actionGuide = MissionActionGuide.forPhase(phase, state);
        expect(guidance.interactionLabel, isNotEmpty, reason: phase.id);
        expect(guidance.summary, isNotEmpty, reason: phase.id);
        expect(guidance.steps, isNotEmpty, reason: phase.id);
        expect(guidance.steps.every((step) => step.length > 20), isTrue,
            reason: phase.id);
        expect(guidance.progress, isNotEmpty, reason: phase.id);
        expect(guidance.remaining, isNotEmpty, reason: phase.id);
        expect(guidance.steps.join(' ').contains('Complete the task'), isFalse,
            reason: phase.id);
        expect(actionGuide.steps, isNotEmpty, reason: phase.id);
        expect(actionGuide.currentStep, isNotNull, reason: phase.id);
        expect(actionGuide.ready, isFalse, reason: phase.id);
        expect(actionGuide.steps.every((step) => step.text.length > 20), isTrue,
            reason: phase.id);
        expect(actionGuide.completedCount + actionGuide.remainingCount,
            actionGuide.steps.length,
            reason: phase.id);
      }
    }
  });

  test('identification phases guide tapping without requiring dragging', () {
    for (final id in const ['coc1_m1_p1', 'coc1_m1_p2', 'coc4_m1_p1']) {
      final mission = MissionSimulationDefinitions.byId(id.substring(0, 7));
      final phase = mission.phases.firstWhere((item) => item.id == id);
      final guidance = MissionPhaseGuidance.forPhase(
          phase, MissionRuntimeState.initial(mission.id));
      final actionGuide = MissionActionGuide.forPhase(
          phase, MissionRuntimeState.initial(mission.id));
      expect(
          guidance.interactionLabel, MissionContentData.guidanceIdentifyLabel);
      expect(guidance.steps.join(' ').toLowerCase().contains('drag'), isFalse,
          reason: id);
      expect(guidance.hint, contains('No dragging is required'));
      expect(actionGuide.steps.map((step) => step.text).join(' ').toLowerCase(),
          isNot(contains('drag it')),
          reason: id);
      if (id == 'coc1_m1_p2') {
        expect(guidance.steps.join(' '), contains('Confirm selection'));
        expect(guidance.progress, contains('Roles identified: 0 of 3'));
      }
    }
    final inspect = MissionSimulationDefinitions.byId('coc1_m1').phases.first;
    final guidance = MissionPhaseGuidance.forPhase(
        inspect, MissionRuntimeState.initial('coc1_m1'));
    expect(guidance.progress, contains('Inspections: 0 of 7'));
    expect(guidance.summary, contains('seven'));
  });

  test('placement, configuration, diagnostics, and review use their controls',
      () {
    final checks = <String, String>{
      // The assembly bench: parts are dragged from its tray onto the bench.
      'coc1_m2_p2': 'Drag the part onto its place on the bench',
      'coc2_m4_p2': 'Apply configuration',
      'coc3_m3_p3': 'diagnostic action',
      'coc4_m5_p6': 'Confirm evidence',
    };
    for (final entry in checks.entries) {
      final mission =
          MissionSimulationDefinitions.byId(entry.key.substring(0, 7));
      final phase = mission.phases.firstWhere((item) => item.id == entry.key);
      final guidance = MissionPhaseGuidance.forPhase(
          phase, MissionRuntimeState.initial(mission.id));
      expect(guidance.steps.join(' '), contains(entry.value),
          reason: entry.key);
    }
    // COC4 placements on the standard panel are tap only.
    final coc4 = MissionSimulationDefinitions.all
        .where((mission) => mission.id.startsWith('coc4'))
        .expand((mission) => mission.phases)
        .where((phase) =>
            phase.resolvedInteraction == InteractionFamily.place &&
            !MissionLabPhases.owns(phase.id));
    for (final phase in coc4) {
      final tapPlacement = MissionPhaseGuidance.forPhase(
          phase, MissionRuntimeState.initial(phase.id.substring(0, 7)));
      expect(tapPlacement.interactionLabel,
          MissionContentData.guidanceTapPlaceLabel,
          reason: phase.id);
      expect(
          tapPlacement.steps.join(' ').toLowerCase().contains('drag'), isFalse,
          reason: phase.id);
    }
    // The COC4 M4 replacement adapter goes in on the service-bench lab, which
    // takes a drag onto the slot or a tap on the adapter and then the slot.
    final replacement = MissionSimulationDefinitions.byId('coc4_m4').phases[1];
    final labPlacement = MissionPhaseGuidance.forPhase(
        replacement, MissionRuntimeState.initial('coc4_m4'));
    expect(labPlacement.interactionLabel,
        MissionContentData.labGuidanceBenchLabel);
    expect(labPlacement.steps, MissionContentData.labGuidanceInstallSteps);
  });

  test('inspection progress reads actual runtime hotspot state', () {
    final phase = MissionSimulationDefinitions.byId('coc1_m1').phases.first;
    final first = (phase.presentation['objects'] as List).first as Map;
    final state = MissionRuntimeState.initial('coc1_m1').copyWith(
        hotspotStates: {first['id'] as String: HotspotVisualState.completed});
    expect(MissionPhaseGuidance.forPhase(phase, state).progress,
        contains('Inspections: 1 of 7'));
    final guide = MissionActionGuide.forPhase(phase, state);
    expect(guide.completedCount, 1);
    expect(guide.remainingCount, greaterThan(0));
    expect(guide.currentStep!.target, MissionGuideTarget.objects);
  });

  test('rejected actions do not advance guide or enable Continue', () {
    final phase = MissionSimulationDefinitions.byId('coc1_m1').phases.first;
    final initial = MissionRuntimeState.initial('coc1_m1');
    final rejected = MissionPhaseCompletionPolicy.afterAction(
      phase: phase,
      state: initial,
      emittedActionType: 'object_inspected',
      target: 'cpu',
      value: const {'simulation_valid': false},
    );
    expect(MissionActionGuide.forPhase(phase, rejected).completedCount, 0);
    expect(MissionPhaseCompletionPolicy.canAdvance(phase, rejected), isFalse);
  });

  test('guide resumes from serialized action state without assuming sync', () {
    final phase = MissionSimulationDefinitions.byId('coc1_m1').phases.first;
    final first = (phase.presentation['objects'] as List).first as Map;
    final original = MissionRuntimeState.initial('coc1_m1').copyWith(
      hotspotStates: {first['id'] as String: HotspotVisualState.completed},
    );
    final restored = MissionRuntimeState.fromJson(original.toJson());
    final guide = MissionActionGuide.forPhase(phase, restored);
    expect(guide.completedCount, 1);
    expect(guide.ready, isFalse);
    expect(restored.acceptedEvidenceIds, isEmpty);
  });

  test('review never treats queued evidence as server accepted', () {
    final mission = MissionSimulationDefinitions.byId('coc1_m1');
    final phase = mission.phases.last;
    final pending = MissionEvidenceAction(
      clientActionId: 'queued-1',
      missionId: mission.id,
      phaseId: mission.phases.first.id,
      actionType: 'object_inspected',
      value: const {'input_method': 'tap'},
      occurredAt: DateTime.utc(2026),
    );
    final state = MissionRuntimeState.initial(mission.id)
        .copyWith(pendingEvidence: [pending]);
    final guide = MissionActionGuide.forPhase(phase, state, reviewReady: true);
    expect(guide.ready, isFalse);
    expect(guide.pendingEvidenceCount, 1);
    expect(guide.currentStep, isNotNull);
    expect(state.acceptedEvidenceIds, isEmpty);
  });

  // Production QA 2026-11-20: after Confirm evidence saved the practice run,
  // the bar still said "Complete the missing task, then review again".
  testWidgets('a saved review confirms the save instead of asking to return',
      (tester) async {
    final mission = MissionSimulationDefinitions.byId('coc1_m2');
    final review = mission.phases.last;
    expect(review.resolvedInteraction, InteractionFamily.review);
    final state = MissionRuntimeState.initial(mission.id)
        .copyWith(currentPhaseId: review.id);
    // What the screen passes once the server accepted the submission:
    // reviewReady drops to false because the run can no longer be submitted.
    final saved = MissionActionGuide.forPhase(review, state,
        reviewReady: false, submitted: true);
    expect(saved.submitted, isTrue);
    expect(saved.ready, isTrue);
    expect(saved.currentStep, isNull);
    expect(saved.remainingCount, 0);
    expect(saved.steps.first.text, MissionContentData.reviewSavedLabel);
    expect(saved.steps.first.controlKey, 'mission-exit');
    expect(saved.steps.map((step) => step.text),
        isNot(contains(MissionContentData.guideReviewIncomplete)));
    // Before the save the incomplete-review guidance is unchanged.
    expect(MissionActionGuide.forPhase(review, state).currentStep?.text,
        MissionContentData.guideReviewIncomplete);
    // Only the review phase knows about the save.
    expect(
        MissionActionGuide.forPhase(mission.phases.first, state,
                submitted: true)
            .submitted,
        isFalse);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          MissionGuidanceBar(
            guidance: MissionPhaseGuidance.forPhase(review, state),
            actionGuide: saved,
            expanded: false,
            onToggle: () {},
            showHow: false,
            onShowHow: () {},
          ),
          Expanded(
            child: SingleChildScrollView(
              child: MissionGuidancePanel(
                  phase: review,
                  guidance: MissionPhaseGuidance.forPhase(review, state),
                  actionGuide: saved,
                  practice: true),
            ),
          ),
        ]),
      ),
    ));
    expect(find.text(MissionContentData.reviewSavedLabel), findsWidgets);
    expect(find.textContaining('Complete the missing task'), findsNothing);
    expect(find.text(MissionContentData.reviewReadyLabel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('guide names only controls rendered by each interaction family', () {
    final expected = <InteractionFamily, String>{
      InteractionFamily.inspect: 'Objects',
      InteractionFamily.select: 'Selection set',
      InteractionFamily.tool: 'Target',
      InteractionFamily.connect: 'Connect ports',
      InteractionFamily.configure: 'Apply configuration',
      InteractionFamily.sequence: 'Apply procedure order',
      InteractionFamily.match: 'Sources',
      InteractionFamily.place: 'Place equipment',
      InteractionFamily.troubleshoot: 'Troubleshooting diagnostics',
      InteractionFamily.testRun: 'Run test',
      InteractionFamily.observe: 'Record observation',
      InteractionFamily.decide: 'decision buttons',
      InteractionFamily.interpret: 'Record interpretation',
      InteractionFamily.review: 'Return to mission',
    };
    final phases = MissionSimulationDefinitions.all.expand((m) => m.phases);
    for (final phase in phases) {
      final guide = MissionActionGuide.forPhase(
          phase, MissionRuntimeState.initial(phase.id.substring(0, 7)));
      // A realistic lab replaces the standard panels of its phases.
      if (MissionLabPhases.guide(phase.id) case final lab?) {
        expect(guide.steps.first.text, lab.text, reason: phase.id);
        continue;
      }
      // The assembly bench renders its parts, cables and inspections in the
      // tray below the bench; its test and review keep the standard panels.
      final bench = phase.presentation['bench_steps'] is List &&
          const {
            InteractionFamily.inspect,
            InteractionFamily.place,
            InteractionFamily.connect,
          }.contains(phase.resolvedInteraction);
      final control = bench
          ? 'tray below the bench'
          : phase.resolvedInteraction == InteractionFamily.place &&
                  phase.id.startsWith('coc4')
              ? 'Components and devices'
              : expected[phase.resolvedInteraction];
      expect(guide.steps.first.text, contains(control), reason: phase.id);
    }
  });

  test('all production guidance actions name a concrete control', () {
    final generic = <String>[];
    for (final mission in MissionSimulationDefinitions.all) {
      for (final phase in mission.phases) {
        final guide = MissionActionGuide.forPhase(
            phase, MissionRuntimeState.initial(mission.id));
        if (guide.steps.any(
            (step) => step.text == MissionContentData.guideCheckRequirements)) {
          generic.add(phase.id);
        }
      }
    }
    expect(generic, isEmpty);
  });

  test('all 116 production phases resolve to rendered control identities', () {
    var count = 0;
    for (final mission in MissionSimulationDefinitions.all) {
      for (final phase in mission.phases) {
        count++;
        final state = MissionRuntimeState.initial(mission.id)
            .copyWith(currentPhaseId: phase.id);
        final guide = MissionActionGuide.forPhase(phase, state);
        final equipment =
            MissionEquipmentSimulator.map(phase.presentation['equipment']);
        final placement = MissionEquipmentSimulator.map(equipment['placement']);
        final connection =
            MissionEquipmentSimulator.map(equipment['connection']);
        final controls = <String>{
          'mission-next',
          'review-return',
          if (phase.resolvedInteraction == InteractionFamily.select)
            'multi-select-options',
          if (phase.resolvedInteraction == InteractionFamily.tool ||
              equipment['targets'] is List)
            'tool-target-options',
          if (phase.resolvedInteraction == InteractionFamily.troubleshoot)
            'diagnostic-actions',
          if (phase.resolvedInteraction == InteractionFamily.testRun)
            'test-run-start',
          if (phase.resolvedInteraction == InteractionFamily.testRun &&
              phase.presentation['requires_interpretation'] == true)
            'test-interpretation-${phase.id}',
          if (phase.resolvedInteraction == InteractionFamily.observe)
            'observation-input-${phase.id}',
          if (phase.resolvedInteraction == InteractionFamily.decide)
            'decision-options',
          if (phase.resolvedInteraction == InteractionFamily.interpret)
            'interpretation-input-${phase.id}',
          if (phase.resolvedInteraction == InteractionFamily.review)
            'retry-pending-evidence',
        };
        void addItems(Object? raw, String prefix) {
          for (final item in MissionEquipmentSimulator.maps(raw)) {
            if (item['id'] is String) controls.add('$prefix${item['id']}');
          }
        }

        addItems(phase.presentation['objects'], 'inspect-target-');
        addItems(
            phase.presentation['sources'],
            phase.resolvedInteraction == InteractionFamily.match
                ? 'matching-source-'
                : 'connection-source-');
        addItems(
            phase.presentation['items'],
            phase.resolvedInteraction == InteractionFamily.sequence
                ? 'sequence-item-'
                : 'placement-item-');
        addItems(phase.presentation['fields'], 'configuration-field-');
        addItems(
            phase.presentation['diagnostic_actions'], 'diagnostic-action-');
        addItems(placement['items'], 'placement-item-');
        addItems(connection['sources'], 'connection-source-');
        addItems(
            MissionEquipmentSimulator.map(equipment['configuration'])['fields'],
            'configuration-field-');
        addItems(equipment['selection_groups'], 'classification-');
        final operations =
            MissionEquipmentSimulator.maps(equipment['operations']);
        if (operations.isNotEmpty) controls.add('equipment-operations');
        addItems(operations, 'equipment-operation-');
        for (final id in phase.availableObjectIds) {
          controls.add('inspect-target-$id');
        }
        final sceneIds =
            mission.scene.objects.map((object) => object.id).toSet();
        final placedIds = MissionEquipmentSimulator.maps(
                phase.resolvedInteraction == InteractionFamily.place
                    ? phase.presentation['items']
                    : placement['items'])
            .map((item) => item['id'])
            .toSet();
        final connectedIds = MissionEquipmentSimulator.maps(
                phase.resolvedInteraction == InteractionFamily.connect
                    ? phase.presentation['sources']
                    : connection['sources'])
            .map((item) => item['id'])
            .toSet();
        if (MissionLabPhases.owns(phase.id)) {
          // The lab's own controls; mission_labs_test pumps each lab and
          // finds every key its guide names.
          for (final step in guide.steps) {
            expect(step.controlKey, startsWith('lab-'),
                reason: '${phase.id}: ${step.text}');
            expect(step.objectId, isNull, reason: phase.id);
          }
          continue;
        }
        for (final step in guide.steps) {
          expect(step.controlKey != null || step.objectId != null, isTrue,
              reason: '${phase.id}: ${step.text}');
          if (step.controlKey case final key?) {
            expect(controls.contains(key), isTrue, reason: '${phase.id}: $key');
          }
          if (step.objectId case final id?) {
            final valid = switch (step.workspaceMode) {
              'inspect' => sceneIds.contains(id),
              'place' => placedIds.contains(id),
              'connect' => connectedIds.contains(id),
              _ => false,
            };
            expect(valid, isTrue, reason: '${phase.id}: $id');
          }
        }
      }
    }
    expect(count, 116);
  });

  // Polish round P5: the bench has hotspots and a tray, not card panels.
  test('assembly bench guidance names the bench controls, not card panels',
      () {
    const panels = [
      'Operate the equipment',
      'Equipment operations',
      'Place equipment',
      'Components and devices',
      'Install selected component',
      'Connect ports',
      'Inspection targets',
      'Tap Objects',
    ];
    final mission = MissionSimulationDefinitions.byId('coc1_m2');
    var benchPhases = 0;
    for (final phase in mission.phases) {
      if (phase.presentation['bench_steps'] is! List) continue;
      benchPhases++;
      final state =
          MissionRuntimeState.initial(mission.id).copyWith(currentPhaseId: phase.id);
      final texts = [
        ...MissionPhaseGuidance.forPhase(phase, state).steps,
        ...MissionActionGuide.forPhase(phase, state).steps.map((s) => s.text),
      ];
      for (final text in texts) {
        for (final panel in panels) {
          expect(text, isNot(contains(panel)), reason: '${phase.id}: $text');
        }
      }
      expect(texts.join(' '), contains('bench'), reason: phase.id);
    }
    expect(benchPhases, 5);

    // After the inspections, the next action is the wrist strap: a hotspot
    // on the bench or its button in the tray.
    final inspect = mission.phases.first;
    final inspected = MissionRuntimeState.initial(mission.id).copyWith(
      currentPhaseId: inspect.id,
      interactionCompletedPhaseIds: {inspect.id},
      hotspotStates: {
        for (final object in MissionEquipmentSimulator.maps(
            inspect.presentation['objects']))
          object['id'] as String: HotspotVisualState.completed,
      },
    );
    expect(MissionActionGuide.forPhase(inspect, inspected).currentStep?.text,
        MissionContentData.guideBenchOperation('Wear the anti-static wrist strap'));
  });

  test('graded decisions do not name the required correction button', () {
    var checked = 0;
    for (final mission in MissionSimulationDefinitions.all) {
      for (final phase in mission.phases) {
        if (phase.resolvedInteraction != InteractionFamily.decide &&
            phase.resolvedInteraction != InteractionFamily.troubleshoot) {
          continue;
        }
        final equipment =
            MissionEquipmentSimulator.map(phase.presentation['equipment']);
        final operations =
            MissionEquipmentSimulator.maps(equipment['operations']);
        final guide = MissionActionGuide.forPhase(
            phase, MissionRuntimeState.initial(mission.id));
        final directions = guide.steps.map((step) => step.text).join(' ');
        for (final condition
            in MissionEquipmentSimulator.maps(equipment['completion'])) {
          final path = condition['path'] as String? ?? '';
          if (!path.startsWith('operation.') && !path.startsWith('setting.')) {
            continue;
          }
          final id = path.substring(path.indexOf('.') + 1);
          for (final operation in operations) {
            final required = path.startsWith('operation.')
                ? operation['id'] == id
                : MissionEquipmentSimulator.map(operation['effects'])
                    .containsKey(id);
            if (!required) continue;
            expect(directions, isNot(contains(operation['label'] as String)),
                reason: phase.id);
            checked++;
          }
        }
      }
    }
    expect(checked, greaterThan(0));
  });

  for (final size in const [Size(320, 568), Size(412, 915), Size(800, 360)]) {
    testWidgets('guidance panel fits $size and exposes instructions',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final phase = MissionSimulationDefinitions.byId('coc1_m2').phases[1];
      final guidance = MissionPhaseGuidance.forPhase(
          phase, MissionRuntimeState.initial('coc1_m2'));
      final actionGuide = MissionActionGuide.forPhase(
          phase, MissionRuntimeState.initial('coc1_m2'));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Column(children: [
              MissionGuidanceBar(
                  guidance: guidance,
                  actionGuide: actionGuide,
                  expanded: true,
                  onToggle: () {},
                  showHow: false,
                  onShowHow: () {}),
              Expanded(
                child: SingleChildScrollView(
                  child: MissionGuidancePanel(
                      phase: phase,
                      guidance: guidance,
                      actionGuide: actionGuide,
                      practice: true),
                ),
              ),
            ]),
          ),
        ),
      ));
      expect(find.text(MissionContentData.guideNextHeading), findsOneWidget);
      expect(find.byKey(const ValueKey('mission-show-me-how')), findsOneWidget);
      // COC1 M2 runs on the assembly bench: its tray, not a card panel.
      expect(find.textContaining('tray below the bench'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact Show me how is separate from expand and stays tappable',
      (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final phase = MissionSimulationDefinitions.byId('coc1_m1').phases.first;
    final state = MissionRuntimeState.initial('coc1_m1');
    var toggles = 0;
    var highlights = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MissionGuidanceBar(
          guidance: MissionPhaseGuidance.forPhase(phase, state),
          actionGuide: MissionActionGuide.forPhase(phase, state),
          expanded: false,
          showHow: false,
          onToggle: () => toggles++,
          onShowHow: () => highlights++,
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('mission-show-me-how')));
    expect(highlights, 1);
    expect(toggles, 0);
    expect(tester.takeException(), isNull);
  });

  // QA Q3: on the bench the guidance bar names the bench step the header
  // shows, never "All required actions completed" while a step is pending.
  group('bench guidance bar follows the bench steps', () {
    final mission = MissionSimulationDefinitions.byId('coc1_m2');
    final p2 = mission.phases[1];

    MissionRuntimeState beforeLatches() {
      final driver = EquipmentPracticeDriver(mission)..complete(mission.phases[0]);
      final script = practiceScripts[p2.id]!;
      for (final step in script.take(script.length - 1)) {
        driver.act(p2, step.$1, step.$2, step.$3);
      }
      return driver.state.copyWith(currentPhaseId: p2.id);
    }

    test('practice names the pending bench step; assessment none', () {
      final initial =
          MissionRuntimeState.initial(mission.id).copyWith(currentPhaseId: p2.id);
      expect(MissionPhaseGuidance.forPhase(p2, initial).benchStep,
          'Open the CPU socket load lever');
      final state = beforeLatches();
      expect(MissionPhaseGuidance.forPhase(p2, state).benchStep,
          'Press each module down until the latches lock');
      final assessment = MissionRuntimeState.fromJson({
        ...state.toJson(),
        'mode': 'assessment',
        'assessmentAttemptId': 'attempt-q3',
      });
      expect(MissionPhaseGuidance.forPhase(p2, assessment).benchStep, isNull);
      final other = MissionSimulationDefinitions.byId('coc1_m1');
      expect(
          MissionPhaseGuidance.forPhase(
                  other.phases.first,
                  MissionRuntimeState.initial(other.id)
                      .copyWith(currentPhaseId: other.phases.first.id))
              .benchStep,
          isNull,
          reason: 'only the assembly bench has bench steps');
    });

    testWidgets('the bar shows the latch step, not Continue', (tester) async {
      final state = beforeLatches();
      expect(MissionPhaseCompletionPolicy.canAdvance(p2, state), isTrue,
          reason: 'the required parts are placed');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MissionGuidanceBar(
            guidance: MissionPhaseGuidance.forPhase(p2, state),
            actionGuide: MissionActionGuide.forPhase(p2, state),
            expanded: false,
            onToggle: () {},
            showHow: false,
            onShowHow: () {},
          ),
        ),
      ));
      expect(find.text('Press each module down until the latches lock'),
          findsOneWidget);
      expect(find.text(MissionContentData.guideReadyToContinue), findsNothing);
    });
  });

  // QA Q4: the Run test hint fits both layouts (below the workspace in
  // portrait, in the side panel in landscape).
  test('the run-test guidance is layout neutral', () {
    expect(MissionContentData.guideTest, contains('Run test'));
    expect(MissionContentData.guideTest.toLowerCase(), isNot(contains('below')));
    expect(MissionContentData.guideTest.toLowerCase(), isNot(contains('scroll')));
  });
}
