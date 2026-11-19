import 'dart:convert';

import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/models/mission_model.dart';
import 'package:bytequest/screens/simulation/components/assembly/assembly_bench.dart';
import 'package:bytequest/screens/simulation/components/equipment_workspace.dart';
import 'package:bytequest/screens/simulation/components/mission_guidance_panel.dart';
import 'package:bytequest/screens/simulation/components/mission_task_status.dart';
import 'package:bytequest/screens/simulation/components/simulation_scene.dart';
import 'package:bytequest/screens/simulation/mission_simulation_screen.dart';
import 'package:bytequest/screens/simulation/runtime/mission_equipment_simulator.dart';
import 'package:bytequest/screens/simulation/runtime/mission_evidence_gateway.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_controller.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:bytequest/services/authoritative_assessment_service.dart';
import 'package:bytequest/services/progress_resume_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/export_practice_contracts.dart'
    show replayActionKinds, replayRow;
import 'support/equipment_practice_driver.dart';
import 'support/equipment_widget_driver.dart';

// Practice vs Assessment for every production mission (re-defense slice A1):
// assessment hides guidance, tutorials and compatible-slot highlights, keeps
// the equipment interactive, submits only after confirmation, and refuses a
// package published from a different definition version.
//
// Fix round 1:
// * C1: every mission's correct run is driven through the assessment-mode
//   controls. The evidence it records is exactly the exported happy path that
//   supabase/tests/simulation_assessment_all_missions_rollback.sql submits
//   through the attempt lifecycle, where every step criterion is satisfied.
// * I1: assessment text never names the expected slot, header, cable or step.

/// The evidence the server replay counts: replayed kinds only, a sequencing
/// order only once the learner confirms it, and only the configuration fields
/// of the phase's panel (the replay ignores other keys of `values`).
List<Map<String, Object?>> _countedEvidence(
    MissionSimulationDefinition definition,
    Iterable<MissionEvidenceAction> actions) {
  final rows = <Map<String, Object?>>[];
  for (final action in actions) {
    final kind = action.value['runtime_action_type'] ?? action.actionType;
    if (!replayActionKinds.contains(kind) ||
        kind == 'sequence_reordered' && action.value['confirmed'] != true) {
      continue;
    }
    final row = replayRow(action);
    if (kind == 'configuration_applied') {
      final phase =
          definition.phases.firstWhere((item) => item.id == action.phaseId);
      final equipment =
          MissionEquipmentSimulator.map(phase.presentation['equipment']);
      final panel = equipment.containsKey('configuration')
          ? MissionEquipmentSimulator.map(equipment['configuration'])
          : phase.presentation;
      final fields = MissionEquipmentSimulator.maps(panel['fields'])
          .map((field) => field['id'])
          .toSet();
      final value = Map<String, Object?>.from(row['value'] as Map);
      value['values'] = {
        for (final entry
            in MissionEquipmentSimulator.map(value['values']).entries)
          if (fields.contains(entry.key)) entry.key: entry.value,
      };
      row['value'] = value;
    }
    rows.add(row);
  }
  return rows;
}

/// Names of the COC1 M2 slots, headers and cables a step expects.
const _coc1M2Targets = [
  'DIMM_A2',
  'DIMM_B2',
  'A2',
  'B2',
  'CPU_FAN',
  'F_PANEL',
  'EPS',
  '8-pin',
  '24-pin',
  'SATA power',
  'SATA data',
  'front-panel',
  'front panel',
];

void _expectNoCoc1M2Target(String text, String reason) {
  for (final name in _coc1M2Targets) {
    final word = RegExp('(^|[^A-Za-z0-9_])${RegExp.escape(name)}(\$|[^A-Za-z0-9_])',
        caseSensitive: false);
    expect(word.hasMatch(text), isFalse, reason: '$reason names $name: $text');
  }
}

class _RecordingTransport implements MissionEvidenceTransport {
  final actions = <MissionEvidenceAction>[];

  @override
  Future<void> append(MissionEvidenceAction action) async => actions.add(action);

  @override
  Future<List<AcknowledgedMissionEvidenceAction>>
      readAcknowledgedActions() async => [];
}

String _contractVersion(String missionId) =>
    MissionSimulationDefinitions.contractVersion(missionId);

MissionRuntimeState _assessment(MissionRuntimeState state) =>
    MissionRuntimeState.fromJson({
      ...state.toJson(),
      'mode': 'assessment',
      'assessmentAttemptId': 'attempt-qa',
    });

var _harnessCount = 0;

class _Harness {
  _Harness(this.definition, {this.learnerPayload = const {}, this.phaseId});

  final MissionSimulationDefinition definition;
  final Map<String, dynamic> learnerPayload;
  final String? phaseId;
  final transport = _RecordingTransport();
  final String userId = 'assessment-qa-${_harnessCount++}';
  late final controller = MissionRuntimeController(
    userId: userId,
    // Stamped like the production controller, so recorded evidence carries
    // the contract version.
    initialState: _assessment(MissionRuntimeState.initial(definition.id,
            definitionVersion: _contractVersion(definition.id))
        .copyWith(currentPhaseId: phaseId ?? definition.phases.first.id)),
    store: const SharedPreferencesMissionRuntimeStore(),
    evidenceGateway: MissionEvidenceGateway(transport: transport),
    submissionPhaseIds: {definition.phases.last.id},
  );
  int submissions = 0;

  Widget app() => MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: MissionSimulationScreen(
          mission: Mission(
              id: definition.id,
              cocId: definition.cocId,
              missionCode: definition.id.toUpperCase(),
              missionNumber: int.parse(definition.id.substring(6)),
              title: definition.title,
              missionType: MissionType.identification,
              orderIndex: int.parse(definition.id.substring(6))),
          definition: definition,
          learnerPayload: learnerPayload,
          controller: controller,
          onSubmit: () async => submissions++,
        ),
      );
}

Future<_Harness> _pump(WidgetTester tester, _Harness harness) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(harness.app());
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('requiresAppUpdate', () {
    const current = MissionSimulationDefinitions.coc1M2AssemblyContractVersion;
    Map<String, dynamic> payload(Object? version) => {
          'mission_id': 'coc1_m2',
          'definition_version': version,
          'mode': 'assessment',
        };

    test('accepts a simulation assessment of the installed definition', () {
      expect(AuthoritativeAssessmentService.requiresAppUpdate(payload(current)),
          isFalse);
      expect(
          AuthoritativeAssessmentService.requiresAppUpdate({
            'mission_id': 'coc2_m1',
            'definition_version': 'css-sag-20261011-v2',
            'mode': 'assessment',
          }),
          isFalse);
    });

    test('refuses another, missing or unknown definition version', () {
      expect(
          AuthoritativeAssessmentService.requiresAppUpdate(
              payload('css-sag-20261011-v2')),
          isTrue);
      expect(AuthoritativeAssessmentService.requiresAppUpdate(payload(null)),
          isTrue);
      expect(
          AuthoritativeAssessmentService.requiresAppUpdate(
              {...payload(current), 'mission_id': 'coc9_m9'}),
          isTrue);
    });

    test('ignores form-based packages and non-assessment payloads', () {
      expect(
          AuthoritativeAssessmentService.requiresAppUpdate(
              {'mode': 'assessment', 'simulation_template': 'coc1_m2_enhanced'}),
          isFalse);
      expect(
          AuthoritativeAssessmentService.requiresAppUpdate(
              {'assessment_package_id': 'legacy-package'}),
          isFalse);
    });
  });

  testWidgets('a package from another definition version asks for an update',
      (tester) async {
    final definition = MissionSimulationDefinitions.byId('coc1_m2');
    final stale = await _pump(
        tester,
        _Harness(definition, learnerPayload: {
          'mission_id': 'coc1_m2',
          'definition_version': 'css-sag-20261011-v2',
          'mode': 'assessment',
        }));
    expect(find.text(MissionContentData.assessmentUpdateRequired),
        findsOneWidget);
    expect(find.byType(AssemblyBench), findsNothing);
    expect(stale.transport.actions, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await _pump(
        tester,
        _Harness(definition, learnerPayload: {
          'mission_id': 'coc1_m2',
          'definition_version':
              MissionSimulationDefinitions.coc1M2AssemblyContractVersion,
          'mode': 'assessment',
        }));
    expect(find.text(MissionContentData.assessmentUpdateRequired),
        findsNothing);
    expect(find.byType(AssemblyBench), findsOneWidget);
  });

  for (final definition in MissionSimulationDefinitions.all) {
    testWidgets(
        '${definition.id}: assessment hides guidance and submits only after '
        'confirmation', (tester) async {
      final harness = await _pump(tester, _Harness(definition));
      expect(find.byType(MissionGuidanceBar), findsNothing);
      expect(find.byKey(const ValueKey('mission-tutorial-panel')),
          findsNothing);
      expect(find.byKey(const ValueKey('assessment-bar')), findsOneWidget);

      await _tapKey(tester, 'assessment-submit');
      await _tapKey(tester, 'assessment-submit-cancel');
      expect(harness.submissions, 0);
      await _tapKey(tester, 'assessment-submit');
      await _tapKey(tester, 'assessment-submit-confirm');
      expect(harness.submissions, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final assessment in [false, true]) {
    testWidgets(
        '${assessment ? 'assessment' : 'practice'} placement '
        '${assessment ? 'stays interactive without' : 'shows'} '
        'compatible-slot highlights', (tester) async {
      final definition = MissionSimulationDefinitions.byId('coc3_m2');
      final driver = EquipmentPracticeDriver(definition);
      if (assessment) driver.state = _assessment(driver.state);
      final phase = definition.phases.first;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, refresh) => EquipmentWorkspace(
              definition: definition,
              phase: phase,
              state: driver.state,
              hotspotStates: driver.state.hotspotStates,
              enabled: true,
              saving: false,
              onCameraChanged: (_, __) {},
              onAction: (type, target, value) async {
                driver.act(phase, type, target, value);
                refresh(() {});
              },
            ),
          ),
        ),
      ));
      await _tapKey(tester, 'workspace-source-server_node');
      final highlighted = tester
          .widget<SimulationScene>(find.byType(SimulationScene))
          .hotspotStates['destination:server_node_position'];
      expect(highlighted, assessment ? isNull : HotspotVisualState.selected);

      await _tapKey(tester, 'workspace-destination-server_node_position');
      expect(driver.state.placements['server_node'], 'server_node_position');
      expect(tester.takeException(), isNull);
    });
  }

  // C1: a correct run is possible with the controls assessment mode renders,
  // and it records the evidence the server evaluation suite passes.
  for (final definition in MissionSimulationDefinitions.all) {
    testWidgets(
        '${definition.id}: a correct run through the assessment controls '
        'records the evaluated happy path', (tester) async {
      final harness = await _pump(tester, _Harness(definition));
      final plan = EquipmentPracticeDriver(definition);
      for (final phase in definition.phases) {
        plan.complete(phase);
      }
      for (var index = 0; index < definition.phases.length - 1; index++) {
        final phase = definition.phases[index];
        for (final action
            in plan.actions.where((action) => action.phaseId == phase.id)) {
          await performEquipmentAction(
              tester, phase, action, harness.controller);
          expect(tester.takeException(), isNull,
              reason: '${phase.id}/${action.actionType}');
        }
        await tapEquipmentControl(
            tester, find.byKey(const ValueKey('mission-next')));
        await tester.pumpAndSettle();
        expect(harness.controller.state.currentPhaseId,
            definition.phases[index + 1].id,
            reason: '${phase.id} can be completed in assessment mode');
      }
      final recorded = _countedEvidence(definition, harness.transport.actions);
      final expected = _countedEvidence(definition, plan.actions);
      for (var i = 0; i < recorded.length || i < expected.length; i++) {
        final actual = i < recorded.length ? recorded[i] : null;
        final wanted = i < expected.length ? expected[i] : null;
        expect(actual, wanted,
            reason: 'evidence #$i recorded ${jsonEncode(actual)} '
                'exported ${jsonEncode(wanted)}');
      }
      expect(harness.controller.state.pendingEvidence, isEmpty);
      expect(
          harness.transport.actions
              .every((action) =>
                  action.value['definition_version'] ==
                  _contractVersion(definition.id)),
          isTrue,
          reason: 'production evidence carries the contract version');
    });
  }

  // I1: assessment text states goals and symptoms, never the expected target.
  group('assessment text never names the expected target', () {
    final coc1M2 = MissionSimulationDefinitions.byId('coc1_m2');

    test('COC1 M2 task text and part descriptions are goal-level', () {
      for (final phase in coc1M2.phases.take(5)) {
        final instruction = MissionContentData.assessmentInstruction(phase.id);
        expect(instruction, isNotNull, reason: phase.id);
        _expectNoCoc1M2Target(instruction!, phase.id);
      }
      // The parts inspected on the mat in phase 1.
      final parts = MissionEquipmentSimulator.maps(
          coc1M2.phases.first.presentation['objects']);
      expect(parts, hasLength(7));
      for (final part in parts) {
        final description =
            MissionContentData.benchAssessmentInspection[part['id']];
        expect(description, isNotNull, reason: '${part['id']}');
        _expectNoCoc1M2Target(description!, '${part['id']}');
      }
    });

    test('COC1 M2 power-on readouts state symptoms only', () {
      final phase = coc1M2.phases[4];
      // Wrong DIMM pair, lever and latches open, no cables, nothing fastened:
      // every check fails.
      final state = MissionRuntimeState.fromJson({
        ...MissionRuntimeState.initial('coc1_m2')
            .copyWith(
              currentPhaseId: phase.id,
              placements: {'ram_1': 'dimm_a1', 'ram_2': 'dimm_b1'},
            )
            .toJson(),
        'mode': 'assessment',
        'assessmentAttemptId': 'attempt-qa',
      });
      final value = MissionEquipmentSimulator.describeAction(
        definition: coc1M2,
        phase: phase,
        state: state,
        actionType: 'test_completed',
        target: phase.presentation['target'] as String,
        value: const {},
      );
      final readings = MissionEquipmentSimulator.maps(
          MissionEquipmentSimulator.map(value['measured_result'])['readings']);
      expect(readings, hasLength(12));
      expect(value['simulation_feedback'], MissionContentData.assessmentTestRecorded,
          reason: 'the test line in assessment is neutral');
      for (final reading in readings) {
        expect(reading['operating'], isFalse, reason: '${reading['id']}');
        _expectNoCoc1M2Target(
            '${reading['label']}: ${reading['reading']}', '${reading['id']}');
      }
      expect(readings.map((reading) => reading['reading']),
          contains('Memory is running in single-channel mode.'));
      expect(readings.map((reading) => reading['reading']),
          contains('No boot device detected.'));
    });

    for (final index in [0, 1, 2, 3, 4]) {
      testWidgets('COC1 M2 phase ${index + 1} shows its goal-level task',
          (tester) async {
        final phase = coc1M2.phases[index];
        await _pump(tester, _Harness(coc1M2, phaseId: phase.id));
        expect(find.textContaining(phase.instruction), findsNothing);
        expect(
            find.textContaining(
                MissionContentData.assessmentInstruction(phase.id)!),
            findsOneWidget);
      });
    }

    test('test readouts of every mission are neutral in assessment', () {
      var checked = 0;
      for (final mission in MissionSimulationDefinitions.all) {
        for (final phase in mission.phases) {
          final checks = MissionEquipmentSimulator.maps(
              MissionEquipmentSimulator.map(
                  phase.presentation['equipment'])['checks']);
          if (checks.isEmpty) continue;
          final state = _assessment(MissionRuntimeState.initial(mission.id)
              .copyWith(currentPhaseId: phase.id));
          final value = MissionEquipmentSimulator.describeAction(
            definition: mission,
            phase: phase,
            state: state,
            actionType: 'test_completed',
            target: phase.presentation['target'] as String? ?? phase.id,
            value: const {},
          );
          final readings = MissionEquipmentSimulator.maps(
              MissionEquipmentSimulator.map(
                  value['measured_result'])['readings']);
          for (final reading in readings) {
            final check = checks.firstWhere((c) => c['id'] == reading['id']);
            final text = reading['reading'] as String;
            expect(text, isNot(check['fault']),
                reason: '${phase.id}/${check['id']}');
            expect(text, isNot(check['nominal']),
                reason: '${phase.id}/${check['id']}');
            final symptom = MissionContentData
                .assessmentReadingSymptoms['${phase.id}.${check['id']}'];
            expect(
                text,
                symptom != null
                    ? reading['operating'] == true
                        ? symptom.nominal
                        : symptom.fault
                    : reading['operating'] == true
                        ? MissionContentData.assessmentReadingNominal
                        : MissionContentData.assessmentReadingFault,
                reason: '${phase.id}/${check['id']}');
            checked++;
          }
        }
      }
      expect(checked, greaterThan(50));
    });

    test('tool readings in assessment state the observation only', () {
      expect(MissionContentData.assessmentToolObservations.keys.toSet(),
          MissionContentData.toolObservations.keys.toSet());
      const hints = [
        'Open its inventory',
        'Inspect individual',
        'Connect both endpoints',
        'Run the wire-map',
        'verification is still required',
        'has not yet been verified',
        'does not verify',
        'before ',
      ];
      for (final text in [
        ...MissionContentData.assessmentToolObservations.values,
        MissionContentData.assessmentToolContact,
        MissionContentData.assessmentDisconnectedToolReading,
        MissionContentData.assessmentConnectedToolReading,
      ]) {
        for (final hint in hints) {
          expect(text.contains(hint), isFalse, reason: '$text: $hint');
        }
      }
      // The simulator shows the neutral reading in assessment.
      var checked = 0;
      for (final mission in MissionSimulationDefinitions.all) {
        for (final phase in mission.phases) {
          final equipment =
              MissionEquipmentSimulator.map(phase.presentation['equipment']);
          final tools = MissionEquipmentSimulator.maps(
              equipment['tools'] ?? phase.presentation['tools']);
          final targets = MissionEquipmentSimulator.maps(
              equipment['targets'] ?? phase.presentation['targets']);
          if (tools.isEmpty || targets.isEmpty) continue;
          for (final tool in tools) {
            final target = targets.firstWhere(
                (item) =>
                    MissionEquipmentSimulator.strings(
                            tool['compatible_categories'])
                        .isEmpty ||
                    MissionEquipmentSimulator.strings(
                            tool['compatible_categories'])
                        .contains(item['category']),
                orElse: () => const {});
            if (target.isEmpty) continue;
            final value = MissionEquipmentSimulator.describeAction(
              definition: mission,
              phase: phase,
              state: _assessment(MissionRuntimeState.initial(mission.id)
                  .copyWith(currentPhaseId: phase.id)),
              actionType: 'tool_attempted',
              target: target['id'] as String,
              value: {'tool_id': tool['id']},
            );
            final observation = MissionEquipmentSimulator.map(
                value['measured_tool_result'])['observation'] as String?;
            if (observation == null) continue;
            expect(
                observation,
                tool['id'] == 'lan_cable_tester'
                    ? anyOf(
                        MissionContentData.assessmentDisconnectedToolReading,
                        MissionContentData.assessmentConnectedToolReading)
                    : MissionContentData
                            .assessmentToolObservations[tool['id']] ??
                        MissionContentData.assessmentToolContact,
                reason: '${phase.id}/${tool['id']}');
            checked++;
          }
        }
      }
      expect(checked, greaterThan(0));
    });

    test('the COC4 M3 route trace reads the finding, not a status', () {
      final mission = MissionSimulationDefinitions.byId('coc4_m3');
      final phase = mission.phases.firstWhere((item) => item.id == 'coc4_m3_p4');
      for (final applicationLogRead in [false, true]) {
        final state = _assessment(MissionRuntimeState.initial('coc4_m3')
            .copyWith(
                currentPhaseId: phase.id,
                revealedFactIds: {
                  if (applicationLogRead) 'application_log_fact',
                }));
        final value = MissionEquipmentSimulator.describeAction(
          definition: mission,
          phase: phase,
          state: state,
          actionType: 'test_completed',
          target: phase.presentation['target'] as String,
          value: const {},
        );
        final reading = MissionEquipmentSimulator.maps(
            MissionEquipmentSimulator.map(
                value['measured_result'])['readings']).single;
        expect(reading['label'], 'Route trace');
        expect(reading['reading'],
            isNot(MissionContentData.assessmentReadingNominal));
        expect(reading['reading'],
            isNot(MissionContentData.assessmentReadingFault));
        expect((reading['reading'] as String).contains('Inspect'), isFalse);
        expect((reading['reading'] as String).contains('correlate'), isFalse);
      }
    });
  });

  // Re-review N1: in assessment the boot order is an answer. Continue and
  // Confirm never depend on whether the order shown is right; Continue opens
  // only after an order is confirmed, right or wrong.
  testWidgets('assessment sequencing controls do not change with correctness',
      (tester) async {
    final definition = MissionSimulationDefinitions.byId('coc1_m3');
    final phase = definition.phases.firstWhere((item) => item.id == 'coc1_m3_p2');
    final harness = await _pump(tester, _Harness(definition, phaseId: phase.id));
    final items = MissionEquipmentSimulator.maps(phase.presentation['items']);
    String label(String id) =>
        items.firstWhere((item) => item['id'] == id)['label'] as String;
    bool continueEnabled() => tester
            .widget<FilledButton>(find.byKey(const ValueKey('mission-next')))
            .onPressed !=
        null;
    bool confirmEnabled() => tester
            .widget<ButtonStyleButton>(
                find.byKey(ValueKey('sequence-confirm-${phase.id}')))
            .onPressed !=
        null;
    List<String> order() => List<String>.from(
        harness.controller.state.sequenceOrder.isEmpty
            ? items.map((item) => item['id'] as String)
            : harness.controller.state.sequenceOrder);
    Future<void> moveUp(String id) async {
      await tapEquipmentControl(
          tester, find.byTooltip(MissionContentData.moveStep(label(id), 'up')));
      await tester.pumpAndSettle();
    }

    Future<void> arrange(List<String> wanted) async {
      for (var position = 0; position < wanted.length; position++) {
        while (order().indexOf(wanted[position]) > position) {
          await moveUp(wanted[position]);
        }
      }
    }

    Future<void> confirm() async {
      await tapEquipmentControl(
          tester, find.byKey(ValueKey('sequence-confirm-${phase.id}')));
      await tester.pumpAndSettle();
    }

    String status() => tester
        .widgetList<Text>(find.descendant(
            of: find.byType(MissionActionBar), matching: find.byType(Text)))
        .map((text) => text.data ?? '')
        .join('|');

    // Every text on screen, order-independent (the list labels move).
    List<String> screenTexts() => tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
        .toList()
      ..sort();

    const right = ['boot_media', 'select_disk', 'copy_files', 'configure_device'];
    const wrong = ['select_disk', 'boot_media', 'copy_files', 'configure_device'];

    expect(continueEnabled(), isFalse);
    expect(confirmEnabled(), isTrue);
    await arrange(wrong);
    final wrongState = (continueEnabled(), confirmEnabled(), status());
    final wrongTexts = screenTexts();
    await arrange(right);
    final rightState = (continueEnabled(), confirmEnabled(), status());
    expect(rightState, wrongState,
        reason: 'an unconfirmed right order looks like a wrong one');
    expect(screenTexts(), wrongTexts,
        reason: 'no workspace or technical message tells right from wrong');
    expect(rightState.$1, isFalse,
        reason: 'Continue needs a confirmed order');
    expect(find.text(MissionContentData.sequenceConstraintFeedback),
        findsNothing);

    await confirm();
    final confirmedRight = (continueEnabled(), status());
    expect(confirmEnabled(), isFalse,
        reason: 'the confirmed order cannot be confirmed again unchanged');
    await arrange(wrong);
    expect(continueEnabled(), isFalse,
        reason: 'moving the list again withdraws the confirmed answer');
    expect(confirmEnabled(), isTrue);
    await confirm();
    final confirmedWrong = (continueEnabled(), status());
    expect(confirmedWrong, confirmedRight,
        reason: 'a confirmed wrong order looks like a confirmed right one');
    expect(confirmedWrong.$1, isTrue);
    expect(confirmEnabled(), isFalse);

    final confirmed = harness.transport.actions
        .where((action) => action.value['confirmed'] == true)
        .map((action) => action.value['order'])
        .toList();
    expect(confirmed, [right, wrong]);
    expect(tester.takeException(), isNull);
  });
}
