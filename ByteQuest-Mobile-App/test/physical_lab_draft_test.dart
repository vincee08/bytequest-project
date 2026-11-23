import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/screens/simulation/components/labs/mission_labs.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:bytequest/services/progress_resume_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/equipment_practice_driver.dart';

Finder _key(String name) => find.byKey(ValueKey(name));

Future<void> _press(WidgetTester t, Finder control) async {
  await t.ensureVisible(control);
  await t.pumpAndSettle();
  await t.tap(control);
  await t.pumpAndSettle();
}

Future<void> _tap(WidgetTester t, String key) => _press(t, _key(key));

class _LabSession {
  _LabSession(String id, this.phaseId, {bool assessment = false})
      : definition = MissionSimulationDefinitions.byId(id) {
    phase = definition.phases.singleWhere((p) => p.id == phaseId);
    driver = EquipmentPracticeDriver(definition);
    driver.state = MissionRuntimeState.initial(
      id,
      mode: assessment
          ? MissionRuntimeMode.assessment
          : MissionRuntimeMode.practice,
      assessmentAttemptId: assessment ? 'fixture-attempt' : null,
      definitionVersion: MissionSimulationDefinitions.contractVersion(id),
    ).copyWith(currentPhaseId: phaseId);
  }

  final String phaseId;
  final MissionSimulationDefinition definition;
  late final EquipmentPracticeDriver driver;
  late final MissionPhaseDefinition phase;
  int writes = 0;

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(460, 980);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
      builder: (context, redraw) => MissionLabs.build(
        definition: definition,
        phase: phase,
        state: driver.state,
        enabled: true,
        onDraftChanged: (draft) {
          writes++;
          driver.state = driver.state.copyWith(workbenchDraft: draft);
        },
        onAction: (type, target, value) async {
          driver.act(phase, type, target, value);
          driver.state = driver.state.copyWith(acceptedEvidenceIds: {
            for (final a in driver.actions) a.clientActionId
          });
          redraw(() {});
        },
      ),
    ))));
    await t.pumpAndSettle();
  }

  Future<void> restart(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    const store = SharedPreferencesMissionRuntimeStore();
    final state = driver.state;
    expect(await store.saveMissionRuntime(userId: 'physical-qa', state: state),
        isTrue);
    driver.state = (await store.loadMissionRuntime(
        userId: 'physical-qa',
        missionId: state.missionId,
        mode: state.mode,
        assessmentAttemptId: state.assessmentAttemptId))!;
    await open(t);
  }
}

Future<void> _wire(WidgetTester t, String wire, int pin) async {
  await _tap(t, 'lab-cable-conductor-$wire');
  await _tap(t, 'lab-cable-pin-$pin');
}

Future<void> _drag(WidgetTester t, Finder source, Offset end,
    {PointerDeviceKind kind = PointerDeviceKind.touch}) async {
  final origin = t.getCenter(source);
  final g = await t.startGesture(origin, kind: kind);
  await g.moveTo(origin + const Offset(-24, -30));
  await t.pump();
  await g.moveTo(end);
  await t.pump();
  await g.up();
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'partial wires, empty channels, selection and final input survive a restart',
      (t) async {
    const wires = [
      'white_orange',
      'orange',
      'white_green',
      'blue',
      'white_blue',
      'green',
      'white_brown',
      'brown'
    ];
    final s = _LabSession('coc2_m2', 'coc2_m2_p2');
    await s.open(t);
    await _wire(t, 'blue', 4);
    await _tap(t, 'lab-cable-conductor-white_orange');
    await s.restart(t);
    expect(find.bySemanticsLabel(RegExp(r'^Pin 4 channel, holds Blue')),
        findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Pin 1 channel, empty')),
        findsOneWidget);
    await _tap(t, 'lab-cable-pin-1');
    for (final i in [1, 2, 4, 5, 6]) {
      await _wire(t, wires[i], i + 1);
    }
    await _drag(t, _key('lab-cable-conductor-brown'),
        t.getCenter(_key('lab-cable-pin-8')));
    await s.restart(t);
    expect(s.driver.actions, isEmpty);
    await _tap(t, 'lab-cable-crimp');
    expect(s.driver.actions.single.value['input_method'], 'drag');
    expect(s.driver.actions.single.value['order'], wires);
    await s.restart(t);
    expect(_key('lab-cable-reterminate'), findsOneWidget);
    expect(s.driver.actions, hasLength(1));
  });

  testWidgets(
      'a cut-off miswire stays cut; a stale draft cannot reopen a later identical crimp',
      (t) async {
    final s = _LabSession('coc2_m2', 'coc2_m2_p2', assessment: true);
    final order = [...practiceOrders[s.phaseId]!.reversed];
    await s.open(t);
    for (var i = 0; i < 8; i++) {
      await _wire(t, order[i], i + 1);
    }
    await _tap(t, 'lab-cable-crimp');
    await _tap(t, 'lab-cable-reterminate');
    await s.restart(t);
    expect(_key('lab-cable-reterminate'), findsNothing);
    expect(_key('lab-cable-reference'), findsNothing);
    await _wire(t, order[0], 1);
    final stale = s.driver.state.workbenchDraft;
    for (var i = 1; i < 8; i++) {
      await _wire(t, order[i], i + 1);
    }
    await _tap(t, 'lab-cable-crimp');
    s.driver.state = s.driver.state.copyWith(workbenchDraft: stale);
    await s.restart(t);
    expect(_key('lab-cable-reterminate'), findsOneWidget);
    expect(find.text(MissionContentData.labCableCrimped), findsOneWidget);
    expect(s.driver.actions, hasLength(2));
  });

  testWidgets(
      'a malformed wire draft, or a draft from another phase, restores nothing',
      (t) async {
    final s = _LabSession('coc2_m2', 'coc2_m2_p2');
    await s.open(t);
    await _wire(t, 'blue', 4);
    final saved = s.driver.state.workbenchDraft;
    for (final invalid in [
      {...saved, 'phase': 'coc4_m4_p1'},
      {
        ...saved,
        'pins': ['blue', 'blue', null, null, null, null, null, null]
      },
      {
        ...saved,
        'pins': [3, null, null, null, null, null, null, null]
      },
    ]) {
      s.driver.state = s.driver.state.copyWith(workbenchDraft: invalid);
      await s.restart(t);
      expect(_key('lab-cable-conductor-blue'), findsOneWidget);
      expect(s.driver.actions, isEmpty);
    }
  });

  testWidgets(
      'partial unplugging and tool choice resume; the actual removal order is preserved',
      (t) async {
    final s = _LabSession('coc4_m4', 'coc4_m4_p1', assessment: true);
    await s.open(t);
    await _press(t, find.text(MissionContentData.labPcieUnplugLabel));
    await _tap(t, 'lab-pcie-tool-esd_driver');
    await s.restart(t);
    expect(s.driver.actions, isEmpty);
    expect(find.text(MissionContentData.labPciePowerIsolated), findsWidgets);
    await _tap(t, 'lab-pcie-screw');
    await _tap(t, 'lab-pcie-lift');
    await s.restart(t);
    expect(find.bySemanticsLabel(MissionContentData.labPcieSlotVacant),
        findsOneWidget);
    await _tap(t, 'lab-pcie-inspect');
    await _press(t, find.text(MissionContentData.labPcieWearStrapLabel));
    expect(s.driver.actions.map((a) => a.actionType),
        ['tool_attempted', 'sequence_reordered']);
    expect(
        s.driver.actions.last.value['order'], ['remove', 'inspect', 'isolate']);
    expect(
        find.text(MissionContentData.labPcieProcedureOutOfOrder), findsNothing);
    await _tap(t, 'lab-pcie-restart');
    await _tap(t, 'lab-pcie-contingency');
    await s.restart(t);
    expect(find.bySemanticsLabel(MissionContentData.labPcieSlotHoldsFailed),
        findsOneWidget);
    expect(
        find.text(MissionContentData.labPcieProcedureRecorded), findsNothing);
  });

  testWidgets(
      'partial close-out restores individual panel, power and screw operations',
      (t) async {
    final s = _LabSession('coc4_m4', 'coc4_m4_p4');
    await s.open(t);
    await _tap(t, 'lab-pcie-configure');
    await _tap(t, 'lab-pcie-latch');
    await _tap(t, 'lab-pcie-tool-esd_driver');
    await _tap(t, 'lab-pcie-screw');
    await _tap(t, 'lab-pcie-panel');
    await s.restart(t);
    expect(s.driver.actions, isEmpty);
    expect(find.text(MissionContentData.labPcieClosed), findsWidgets);
    await _tap(t, 'lab-pcie-power-back');
    expect(s.driver.actions.single.value['order'],
        ['configure', 'seat', 'fasten', 'restore']);
    await s.restart(t);
    expect(find.text(MissionContentData.labPcieProcedureOutOfOrder),
        findsOneWidget);
    expect(s.driver.actions, hasLength(1));
  });

  testWidgets(
      'the loose adapter can go back to the tray, and cannot block tap placement',
      (t) async {
    final s = _LabSession('coc4_m4', 'coc4_m4_p2');
    await s.open(t);
    final board = t.getRect(_key('lab-pcie-board'));
    await _drag(
        t, _key('lab-pcie-adapter'), board.bottomRight - const Offset(6, 6));
    await _tap(t, 'lab-pcie-return');
    expect(_key('lab-pcie-loose'), findsNothing);
    expect(s.driver.actions, isEmpty);
    await _drag(
        t, _key('lab-pcie-adapter'), t.getCenter(_key('lab-pcie-slot')));
    expect(s.driver.actions.single.value['simulation_valid'], isFalse);
    await _tap(t, 'lab-pcie-rotate');
    await _tap(t, 'lab-pcie-adapter');
    await _tap(t, 'lab-pcie-slot');
    expect(s.driver.actions.last.value['input_method'], 'tap');
    expect(s.driver.state.placements['replacement_component'], 'workstation');
  });

  testWidgets(
      'a miss parks the PCIe adapter; a real rotated attempt rejects and an aligned mouse redrag seats it',
      (t) async {
    final s = _LabSession('coc4_m4', 'coc4_m4_p2', assessment: true);
    await s.open(t);
    final port = _key('lab-pcie-slot');
    final loose = _key('lab-pcie-loose');
    final board = t.getRect(_key('lab-pcie-board'));
    final start = t.getCenter(_key('lab-pcie-adapter'));
    final miss = t.getCenter(port) - const Offset(0, 21);
    expect(t.getRect(port).contains(miss), isTrue,
        reason: 'inside tap reach, outside mechanical capture');
    final gesture = await t.startGesture(start);
    await gesture.moveBy(const Offset(-24, -30));
    await t.pump();
    for (var i = 1; i <= 12; i++) {
      await gesture.moveTo(Offset.lerp(start, miss, i / 12)!);
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(s.writes, 0, reason: 'pointer frames never write checkpoints');
    await gesture.up();
    await t.pumpAndSettle();
    expect(loose, findsOneWidget);
    expect(s.driver.actions, isEmpty);
    final edge = s.driver.state.workbenchDraft['edge'] as List;
    expect(edge[1], closeTo((miss.dy - board.top) / board.height, .002));
    await s.restart(t);
    expect(loose, findsOneWidget);
    expect(find.text(MissionContentData.labPcieBracketRight), findsOneWidget);
    expect(find.text(MissionContentData.labPcieCardReversed), findsNothing);
    await _drag(t, loose, t.getCenter(port));
    expect(s.driver.actions.single.value['orientation'], 'rotated');
    expect(s.driver.actions.single.value['simulation_valid'], isFalse);
    expect(loose, findsOneWidget);
    await _tap(t, 'lab-pcie-rotate');
    await s.restart(t);
    expect(find.text(MissionContentData.labPcieBracketLeft), findsOneWidget);
    await _drag(t, loose, t.getCenter(port), kind: PointerDeviceKind.mouse);
    expect(s.driver.actions.last.value['input_method'], 'drag');
    expect(s.driver.actions.last.value['orientation'], 'aligned');
    expect(s.driver.state.placements['replacement_component'], 'workstation');
    await s.restart(t);
    expect(loose, findsNothing);
    expect(s.driver.actions, hasLength(2));
  });
}
