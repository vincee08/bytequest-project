import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/data/missions_data.dart';
import 'package:bytequest/screens/simulation/mission_simulation_screen.dart';
import 'package:bytequest/screens/simulation/runtime/mission_evidence_gateway.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_action_reducer.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_controller.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:bytequest/services/progress_resume_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _OfflineTimeline implements MissionEvidenceTransport {
  final rows = <AcknowledgedMissionEvidenceAction>[];
  @override
  Future<void> append(MissionEvidenceAction action) async {
    expect(rows.any((r) => r.action.clientActionId == action.clientActionId),
        isFalse);
    rows.add(AcknowledgedMissionEvidenceAction(
        action: action,
        serverOrder: rows.length,
        serverRecordId: 'local-row-${rows.length}',
        recordedAt: action.occurredAt));
  }

  @override
  Future<List<AcknowledgedMissionEvidenceAction>>
      readAcknowledgedActions() async => List.of(rows);
}

Finder _key(String id) => find.byKey(ValueKey(id));
Future<void> _until(
    WidgetTester t, bool Function() check, String reason) async {
  for (var i = 0; i < 120 && !check(); i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  expect(check(), isTrue, reason: reason);
  await t.pumpAndSettle();
}

Future<void> exerciseHardwareInspection(WidgetTester t) async {
  final timeline = _OfflineTimeline();
  final def = MissionSimulationDefinitions.byId('coc1_m1');
  final run = 'local-inspection-${DateTime.now().microsecondsSinceEpoch}';
  Future<MissionRuntimeController> openScreen() async {
    final controller = MissionRuntimeController(
        userId: run,
        initialState: MissionRuntimeState.initial(def.id,
                definitionVersion:
                    MissionSimulationDefinitions.contractVersion(def.id))
            .copyWith(currentPhaseId: def.phases.first.id),
        store: const SharedPreferencesMissionRuntimeStore(),
        evidenceGateway: MissionEvidenceGateway(transport: timeline),
        restoreReducer: MissionRuntimeActionReducer(def),
        submissionPhaseIds: {def.phases.last.id});
    await t.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: MissionSimulationScreen(
            mission: MissionsData.getMissionById(def.id)!,
            definition: def,
            controller: controller)));
    await _until(t, () => _key('inspection-probe').evaluate().isNotEmpty,
        'The live mission must open its photo inspection bench.');
    return controller;
  }

  var controller = await openScreen();
  expect(timeline.rows, isEmpty);
  Future<TestGesture> liftTo(Offset end) async {
    final g = await t.startGesture(t.getCenter(_key('inspection-probe')));
    await g.moveBy(const Offset(0, -30));
    await t.pump();
    await g.moveTo(end);
    await t.pump(const Duration(milliseconds: 32));
    expect(_key('inspection-loupe'), findsOneWidget);
    return g;
  }

  Offset target(String id) => t.getCenter(_key('simulation-object-$id'));
  await t.tap(_key('simulation-zoom-in'));
  await t.pumpAndSettle();
  final probe = await liftTo(target('cpu_socket'));
  await probe.moveTo(target('dimm_slot'));
  await t.pump();
  expect(timeline.rows, isEmpty);
  await probe.up();
  await _until(t, () => _key('inspection-seen-dimm_slot').evaluate().isNotEmpty,
      'The DIMM bank, not the underlying board, should be inspected.');
  expect(timeline.rows.single.action.target, 'dimm_slot');
  expect(timeline.rows.single.action.value['runtime_action_type'],
      'object_inspected');
  expect(timeline.rows.single.action.value['input_method'], 'scene');
  await t.tap(_key('simulation-fit-view'));
  await t.pumpAndSettle();
  final world = t.renderObject<RenderBox>(
      find.byKey(const Key('simulation-logical-workspace')));
  await (await liftTo(world.localToGlobal(const Offset(1180, 680)))).up();
  await t.pumpAndSettle();
  expect(find.text(MissionContentData.inspectionLensMiss), findsOneWidget);
  await (await liftTo(target('atx_power_port'))).cancel();
  await t.pumpAndSettle();
  expect(timeline.rows, hasLength(1));

  await controller.persist();
  await t.pumpWidget(const SizedBox.shrink());
  controller = await openScreen();
  expect(timeline.rows, hasLength(1));
  expect(_key('inspection-seen-dimm_slot'), findsOneWidget);
  await t.tap(_key('simulation-objects-button'));
  await t.pumpAndSettle();
  final socket = _key('object-list-cpu_socket');
  await t.scrollUntilVisible(socket.hitTestable(), 70,
      scrollable: find.descendant(
          of: find.byType(BottomSheet), matching: find.byType(Scrollable)));
  await t.pumpAndSettle();
  await t.tap(socket);
  await t.pumpAndSettle();
  for (final id in ['motherboard', 'cpu', 'ram', 'psu']) {
    await t.tapAt(target(id));
    await _until(t, () => _key('inspection-seen-$id').evaluate().isNotEmpty,
        '$id must respond to the touch on its photograph.');
  }
  final header = _key('inspect-target-atx_power_port');
  await t.ensureVisible(header);
  await t.tap(header);
  await _until(
      t,
      () => controller.state.interactionCompletedPhaseIds
          .contains(def.phases.first.id),
      'Seven inspections should enable Continue.');
  expect(timeline.rows, hasLength(7));
  expect(timeline.rows.last.action.value['input_method'], 'tap');
  expect(controller.state.placements, isEmpty);
  await t.tap(_key('mission-next'));
  await _until(t, () => controller.state.currentPhaseId == def.phases[1].id,
      'Continue must open the existing safe-set phase.');
  expect(_key('hardware-inspection-bench'), findsNothing);
  expect(t.takeException(), isNull);
}
