import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/data/missions_data.dart';
import 'package:bytequest/screens/simulation/mission_simulation_screen.dart';
import 'package:bytequest/screens/simulation/runtime/mission_evidence_gateway.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_action_reducer.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_controller.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:bytequest/services/progress_resume_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/equipment_practice_driver.dart';

Finder _key(String id) => find.byKey(ValueKey(id));

// The device exercises the production scene and Android preferences without any account or backend.
class _OfflineTransport implements MissionEvidenceTransport {
  final rows = <AcknowledgedMissionEvidenceAction>[];

  @override
  Future<void> append(MissionEvidenceAction action) async {
    expect(
        rows.any((row) => row.action.clientActionId == action.clientActionId),
        isFalse,
        reason: 'Restoring a workbench must not send an action twice.');
    rows.add(AcknowledgedMissionEvidenceAction(
      action: action,
      serverRecordId: 'device-row-${rows.length}',
      serverOrder: rows.length,
      recordedAt: action.occurredAt,
    ));
  }

  @override
  Future<List<AcknowledgedMissionEvidenceAction>>
      readAcknowledgedActions() async => List.of(rows);
}

class _Run {
  _Run(int index,
      {String mission = 'coc1_m2', this.workspace = 'assembly-bench'})
      : _definition = MissionSimulationDefinitions.byId(mission) {
    final prior = EquipmentPracticeDriver(_definition);
    for (final phase in _definition.phases.take(index)) {
      prior.complete(phase);
    }
    initial = prior.state.copyWith(
        currentPhaseId: _definition.phases[index].id,
        definitionVersion:
            MissionSimulationDefinitions.contractVersion(_definition.id));
  }

  final MissionSimulationDefinition _definition;
  final String workspace;
  late final MissionRuntimeState initial;
  final transport = _OfflineTransport();
  final userId = 'device-bench-${DateTime.now().microsecondsSinceEpoch}';
  final store = const SharedPreferencesMissionRuntimeStore();

  MissionRuntimeController controller() => MissionRuntimeController(
        userId: userId,
        initialState: initial,
        store: store,
        evidenceGateway: MissionEvidenceGateway(transport: transport),
        restoreReducer: MissionRuntimeActionReducer(_definition),
        submissionPhaseIds: {_definition.phases.last.id},
      );

  Future<void> mount(
      WidgetTester tester, MissionRuntimeController controller) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: MissionSimulationScreen(
        key: ObjectKey(controller),
        mission: MissionsData.getMissionById(_definition.id)!,
        definition: _definition,
        controller: controller,
      ),
    ));
    await _until(tester, () => _key(workspace).evaluate().isNotEmpty,
        'The live mission screen did not mount $workspace.');
  }

  Future<MissionRuntimeController> reopen(
      WidgetTester tester, MissionRuntimeController previous) async {
    final ids = transport.rows.map((row) => row.action.clientActionId).toList();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await previous.persist();
    final disk = await store.loadMissionRuntime(
        userId: userId,
        missionId: _definition.id,
        mode: MissionRuntimeMode.practice);
    expect(disk!.placements, previous.state.placements);
    expect(disk.workbenchDraft, previous.state.workbenchDraft);
    expect(disk.acceptedEvidenceIds, ids.toSet());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    final next = controller();
    await mount(tester, next);
    expect(next.state.acceptedEvidenceIds, ids.toSet());
    expect(transport.rows.map((row) => row.action.clientActionId), ids);
    return next;
  }

  Map<String, dynamic> get last => transport.rows.last.action.value;
}

Future<void> _until(
    WidgetTester tester, bool Function() condition, String reason) async {
  for (var i = 0; i < 150 && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  expect(condition(), isTrue, reason: reason);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String id) async {
  await tester.ensureVisible(_key(id));
  await tester.pumpAndSettle();
  await tester.tap(_key(id));
  await tester.pumpAndSettle();
}

Future<void> _drag(
    WidgetTester tester, String source, Offset Function() destination,
    {required PointerDeviceKind kind,
    String? ghost,
    String surface = 'assembly-bench-wiring'}) async {
  final from = _key(source);
  await tester.ensureVisible(from);
  await tester.pumpAndSettle();
  final start = tester.getCenter(from);
  final bench = tester.getRect(_key(surface));
  final lift = start.dx < bench.left && start.dy < bench.bottom
      ? const Offset(42, 0)
      : const Offset(0, -42);
  final pointer = await tester.startGesture(start, kind: kind);
  for (var i = 1; i <= 6; i++) {
    await pointer.moveTo(start + lift * (i / 6));
    await tester.pump(const Duration(milliseconds: 16));
  }
  final target = destination();
  final mid = Offset.lerp(start + lift, target, .55)!;
  await pointer.moveTo(mid);
  await tester.pump();
  if (ghost != null) expect(_key(ghost), findsOneWidget);
  final ghostAtMid = ghost == null ? null : tester.getCenter(_key(ghost));
  await pointer.moveTo(target);
  await tester.pump(const Duration(milliseconds: 16));
  if (ghostAtMid != null) {
    final relativeMovement =
        (tester.getCenter(_key(ghost!)) - ghostAtMid) - (target - mid);
    expect(relativeMovement.distance, lessThan(2),
        reason: 'The sprite must follow the pointer, not jump to a target.');
  }
  await pointer.up();
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'CPU rests where released, resumes loose, then seats only after alignment',
      (tester) async {
    final run = _Run(1);
    var controller = run.controller();
    await run.mount(tester, controller);
    await _tap(tester, 'bench-operation-open_cpu_lever');
    await _until(
        tester,
        () =>
            controller.state.equipmentState['cpu_lever'] == 'open' &&
            run.transport.rows.length == 1 &&
            controller.state.pendingEvidence.isEmpty,
        'The load plate must open first.');
    final before = run.transport.rows.length;
    Offset restingPoint() {
      final surface =
          tester.renderObject<RenderBox>(_key('assembly-bench-wiring'));
      return surface.localToGlobal(
          Offset(surface.size.width * .14, surface.size.height * .49));
    }

    late Offset released;
    await _drag(tester, 'bench-part-cpu', () => released = restingPoint(),
        kind: PointerDeviceKind.touch, ghost: 'bench-drag-ghost-cpu');
    final loose = _key('bench-loose-cpu');
    await _until(tester, () => loose.evaluate().length == 1,
        'An off-target processor must remain loose on the mat.');
    expect((tester.getCenter(loose) - released).distance, lessThan(2));
    for (var i = 0; i < 6; i++) {
      final target = released + Offset(i.isEven ? 18 : 0, 0);
      await _drag(tester, 'bench-loose-cpu', () => target,
          kind: PointerDeviceKind.touch);
      expect((tester.getCenter(loose) - target).distance, lessThan(2));
    }
    expect(controller.state.placements, isNot(contains('cpu')));
    expect(run.transport.rows, hasLength(before),
        reason: 'Putting a part on the mat does not answer an assessment.');
    final loosePose = controller.state.workbenchDraft['loose'];
    expect(loosePose, contains('cpu'));

    controller = await run.reopen(tester, controller);
    expect(loose, findsOneWidget);
    expect(controller.state.workbenchDraft['loose'], loosePose);
    expect((tester.getCenter(loose) - restingPoint()).distance, lessThan(2));
    Offset socket() => tester.getCenter(_key('bench-slot-cpu_socket'));
    await _drag(tester, 'bench-loose-cpu', socket,
        kind: PointerDeviceKind.touch);
    await _until(tester, () => run.transport.rows.length == before + 1,
        'The wrong-way attempt must reach the evidence gateway.');
    expect(run.last['runtime_action_type'], 'placement_attempted');
    expect(run.last['orientation'], '90');
    expect(run.last['simulation_valid'], false);
    expect(controller.state.placements, isNot(contains('cpu')));
    expect(loose, findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await _tap(tester, 'bench-rotate');
    }
    await _drag(tester, 'bench-loose-cpu', socket,
        kind: PointerDeviceKind.mouse);
    await _until(
        tester,
        () =>
            controller.state.placements['cpu'] == 'cpu_socket' &&
            run.transport.rows.length == before + 2 &&
            controller.state.pendingEvidence.isEmpty,
        'The correctly rotated processor must snap into its socket.');
    expect(run.last['input_method'], 'drag');
    expect(run.last['orientation'], '0');
    expect(run.last['destination_id'], 'cpu_socket');
    expect(run.last['simulation_valid'], true);
    expect(run.transport.rows, hasLength(before + 2));
    expect(loose, findsNothing);
    expect((tester.getCenter(_key('bench-placed-cpu')) - socket()).distance,
        lessThan(2));
    controller = await run.reopen(tester, controller);
    expect(controller.state.placements['cpu'], 'cpu_socket');
    expect(loose, findsNothing);
    expect(_key('bench-placed-cpu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a dragged ATX connector refuses the EPS header, then seats and restores',
      (tester) async {
    final run = _Run(3);
    var controller = run.controller();
    await run.mount(tester, controller);
    const source = 'bench-cable-atx_24pin';
    for (final (port, valid) in [
      ('board_eps8', false),
      ('board_atx24', true)
    ]) {
      final expectedCount = run.transport.rows.length + 1;
      await _drag(
          tester, source, () => tester.getCenter(_key('bench-header-$port')),
          kind: PointerDeviceKind.touch, ghost: 'bench-drag-ghost-atx_24pin');
      await _until(tester, () => run.transport.rows.length == expectedCount,
          'The port attempt was not recorded.');
      expect(run.last['runtime_action_type'], 'connection_created');
      expect(run.last['source_id'], 'atx_24pin');
      expect(run.last['destination_id'], port);
      expect(run.last['simulation_valid'], valid);
      expect(controller.state.connectedNodePairs.contains('atx_24pin>$port'),
          valid);
    }
    controller = await run.reopen(tester, controller);
    expect(
        controller.state.connectedNodePairs, contains('atx_24pin>board_atx24'));
    expect(controller.state.connectedNodePairs,
        isNot(contains('atx_24pin>board_eps8')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rear I/O records the jack the learner actually targets',
      (tester) async {
    const surface = 'physical-port-surface';
    final run = _Run(2, mission: 'coc1_m4', workspace: surface);
    var controller = run.controller();
    await run.mount(tester, controller);
    for (final (bank, valid) in [('usb_port', false), ('hdmi_port', true)]) {
      final count = run.transport.rows.length + 1;
      await _drag(tester, 'workspace-source-monitor',
          () => tester.getCenter(_key('workspace-destination-$bank')),
          kind: PointerDeviceKind.touch, surface: surface);
      await _until(
          tester,
          () =>
              run.transport.rows.length == count &&
              controller.state.pendingEvidence.isEmpty,
          'The I/O port attempt was not recorded.');
      expect(run.last['runtime_action_type'], 'connection_created');
      expect(run.last['source_id'], 'monitor');
      expect(run.last['destination_id'], bank);
      expect(run.last['simulation_valid'], valid);
      expect(
          controller.state.connectedNodePairs.contains('monitor>$bank'), valid);
    }
    controller = await run.reopen(tester, controller);
    expect(controller.state.connectedNodePairs, contains('monitor>hdmi_port'));
    expect(controller.state.connectedNodePairs,
        isNot(contains('monitor>usb_port')));
    expect(run.transport.rows, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
