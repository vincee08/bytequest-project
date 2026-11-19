import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/models/mission_model.dart';
import 'package:bytequest/screens/simulation/mission_simulation_screen.dart';
import 'package:bytequest/screens/simulation/runtime/mission_evidence_gateway.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_action_reducer.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_controller.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:bytequest/services/progress_resume_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Fix round 1 (I3): practice saved for an earlier version of a mission is not
// restored into the new version. The learner sees a notice, the server gets a
// practice_progress_discarded marker (earlier actions stay for audit), and
// the new version starts clean. Verified completions are kept server-side
// (supabase/tests/simulation_coc1_m2_contract_rollback.sql).

class _ServerTransport implements MissionEvidenceTransport {
  _ServerTransport(this.acknowledged, {this.failWrites = false});

  final List<MissionEvidenceAction> acknowledged;
  final bool failWrites;
  final appended = <MissionEvidenceAction>[];

  @override
  Future<void> append(MissionEvidenceAction action) async {
    if (failWrites) throw StateError('offline');
    appended.add(action);
  }

  @override
  Future<List<AcknowledgedMissionEvidenceAction>>
      readAcknowledgedActions() async => [
            for (var index = 0; index < acknowledged.length; index++)
              AcknowledgedMissionEvidenceAction(
                action: acknowledged[index],
                serverRecordId: 'server-$index',
                serverOrder: index + 1,
                recordedAt: acknowledged[index].occurredAt,
              ),
          ];
}

/// The class-practice attempt transport keeps its whole timeline, markers
/// included, and returns all of it on restore (re-review N2).
class _AttemptTransport extends _ServerTransport {
  _AttemptTransport(super.acknowledged);

  @override
  Future<void> append(MissionEvidenceAction action) async {
    await super.append(action);
    acknowledged.add(action);
  }
}

MissionEvidenceAction _action(String missionId, String phaseId, String type,
        Map<String, dynamic> value,
        {String? target, String id = 'v2-1'}) =>
    MissionEvidenceAction(
      clientActionId: id,
      missionId: missionId,
      phaseId: phaseId,
      actionType: type,
      target: target,
      value: value,
      occurredAt: DateTime.utc(2026, 11, 10, 8),
    );

var _userCount = 0;

class _Harness {
  _Harness(this.definition, this.transport, {String? userId})
      : userId = userId ?? 'version-qa-${_userCount++}';

  final MissionSimulationDefinition definition;
  final _ServerTransport transport;
  final String userId;
  late final controller = MissionRuntimeController(
    userId: userId,
    initialState: MissionRuntimeState.initial(definition.id,
            definitionVersion:
                MissionSimulationDefinitions.contractVersion(definition.id))
        .copyWith(currentPhaseId: definition.phases.first.id),
    store: const SharedPreferencesMissionRuntimeStore(),
    evidenceGateway: MissionEvidenceGateway(transport: transport),
    restoreReducer: MissionRuntimeActionReducer(definition),
    submissionPhaseIds: {definition.phases.last.id},
    unstampedDefinitionVersion:
        MissionSimulationDefinitions.unstampedContractVersion(definition.id),
  );

  Future<void> saveSnapshot(MissionRuntimeState state) =>
      const SharedPreferencesMissionRuntimeStore()
          .saveMissionRuntime(userId: userId, state: state);

  Future<MissionRuntimeState?> savedSnapshot() =>
      const SharedPreferencesMissionRuntimeStore().loadMissionRuntime(
          userId: userId,
          missionId: definition.id,
          mode: MissionRuntimeMode.practice);

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
          controller: controller,
        ),
      );
}

Future<void> _pump(WidgetTester tester, _Harness harness) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(harness.app());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final coc1M2 = MissionSimulationDefinitions.byId('coc1_m2');

  test('runtime snapshots carry the definition version', () {
    final state = MissionRuntimeState.initial('coc1_m2',
        definitionVersion: 'css-assembly-20261119-v3');
    final restored = MissionRuntimeState.fromJson(state.toJson());
    expect(restored.definitionVersion, 'css-assembly-20261119-v3');
    expect(restored, state);
    expect(MissionRuntimeState.initial('coc1_m2').toJson(),
        isNot(contains('definitionVersion')));
  });

  testWidgets(
      'a COC1 M2 session saved by the earlier layout restarts on the new '
      'version with a notice', (tester) async {
    final harness = _Harness(
        coc1M2,
        _ServerTransport([
          _action('coc1_m2', 'coc1_m2_p2', 'component_drop_attempted', {
            'runtime_action_type': 'placement_attempted',
            'item_id': 'motherboard',
            'destination_id': 'motherboard_area',
            'compatible': true,
          }, target: 'motherboard_area'),
        ]));
    // The v2 snapshot: no definition version, the board shown as installed.
    await harness.saveSnapshot(MissionRuntimeState.initial('coc1_m2')
        .copyWith(
            currentPhaseId: 'coc1_m2_p3',
            placements: {'motherboard': 'motherboard_area'}));

    await _pump(tester, harness);

    expect(find.byKey(const ValueKey('mission-updated-notice')),
        findsOneWidget);
    expect(find.text(MissionContentData.missionUpdatedNotice), findsOneWidget);
    final marker = harness.transport.appended.single;
    expect(marker.actionType, 'practice_progress_discarded');
    expect(marker.value['reason'], 'definition_updated');
    expect(marker.value['definition_version'],
        MissionSimulationDefinitions.coc1M2AssemblyContractVersion);
    expect(harness.controller.state.placements, isEmpty);
    expect(harness.controller.state.currentPhaseId, 'coc1_m2_p1');
    final saved = await harness.savedSnapshot();
    expect(
        saved == null ||
            saved.definitionVersion ==
                    MissionSimulationDefinitions
                        .coc1M2AssemblyContractVersion &&
                saved.placements.isEmpty,
        isTrue,
        reason: 'the earlier snapshot is replaced by the new version');

    await tester.tap(find.byKey(const ValueKey('mission-updated-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mission-updated-notice')), findsNothing);

    // New work is stamped with the current version.
    await tester.tap(find.byKey(const ValueKey('bench-inspect-chip-cpu')));
    await tester.pumpAndSettle();
    expect(harness.transport.appended.last.value['definition_version'],
        MissionSimulationDefinitions.coc1M2AssemblyContractVersion);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a session of the current version is restored unchanged',
      (tester) async {
    const current = MissionSimulationDefinitions.coc1M2AssemblyContractVersion;
    final harness = _Harness(
        coc1M2,
        _ServerTransport([
          _action('coc1_m2', 'coc1_m2_p1', 'object_inspected', {
            'runtime_action_type': 'object_inspected',
            'definition_version': current,
          }, target: 'cpu', id: 'v3-1'),
        ]));
    await harness.saveSnapshot(
        MissionRuntimeState.initial('coc1_m2', definitionVersion: current)
            .copyWith(currentPhaseId: 'coc1_m2_p1'));

    await _pump(tester, harness);

    expect(find.byKey(const ValueKey('mission-updated-notice')), findsNothing);
    expect(harness.transport.appended, isEmpty);
    expect(harness.controller.state.acceptedEvidenceIds, contains('v3-1'));
    expect(harness.controller.state.definitionVersion, current);
  });

  testWidgets('unchanged missions keep progress saved before versions existed',
      (tester) async {
    final definition = MissionSimulationDefinitions.byId('coc1_m4');
    final harness = _Harness(
        definition,
        _ServerTransport([
          _action('coc1_m4', 'coc1_m4_p1', 'object_inspected',
              {'runtime_action_type': 'object_inspected'},
              target: definition.scene.objects.first.id),
        ]));

    await _pump(tester, harness);

    expect(find.byKey(const ValueKey('mission-updated-notice')), findsNothing);
    expect(harness.transport.appended, isEmpty);
    expect(harness.controller.state.acceptedEvidenceIds, contains('v2-1'));
  });

  test('assessment restores every recorded action, even after a discard marker',
      () async {
    const current = MissionSimulationDefinitions.coc1M2AssemblyContractVersion;
    final transport = _ServerTransport([
      _action('coc1_m2', 'coc1_m2_p1', 'object_inspected',
          {'runtime_action_type': 'object_inspected'},
          target: 'cpu', id: 'before'),
      _action('coc1_m2', 'coc1_m2_p1', 'practice_progress_discarded',
          {'reason': 'definition_updated'},
          id: 'marker'),
      _action('coc1_m2', 'coc1_m2_p1', 'object_inspected',
          {'runtime_action_type': 'object_inspected'},
          target: 'psu', id: 'after'),
    ]);
    final controller = MissionRuntimeController(
      userId: 'version-qa-assessment',
      initialState: MissionRuntimeState.initial('coc1_m2',
              mode: MissionRuntimeMode.assessment,
              assessmentAttemptId: 'attempt-qa',
              definitionVersion: current)
          .copyWith(currentPhaseId: 'coc1_m2_p1'),
      store: const SharedPreferencesMissionRuntimeStore(),
      evidenceGateway: MissionEvidenceGateway(transport: transport),
      restoreReducer: MissionRuntimeActionReducer(coc1M2),
      submissionPhaseIds: {coc1M2.phases.last.id},
      unstampedDefinitionVersion:
          MissionSimulationDefinitions.unstampedContractVersion('coc1_m2'),
    );
    await controller.restore();
    expect(controller.definitionChanged, isFalse);
    expect(controller.state.acceptedEvidenceIds,
        containsAll(['before', 'marker', 'after']),
        reason: 'a marker never hides assessment evidence');
    expect(transport.appended, isEmpty);
  });

  testWidgets('an offline restart keeps the earlier progress and offers retry',
      (tester) async {
    final harness = _Harness(
        coc1M2,
        _ServerTransport([
          _action('coc1_m2', 'coc1_m2_p2', 'component_drop_attempted', {
            'runtime_action_type': 'placement_attempted',
            'item_id': 'cpu',
            'destination_id': 'cpu_socket',
          }, target: 'cpu_socket'),
        ], failWrites: true));

    await _pump(tester, harness);

    expect(find.text(MissionContentData.missionUpdateFailed), findsOneWidget);
    expect(find.byKey(const ValueKey('mission-updated-notice')), findsNothing);
    expect(harness.controller.state.placements, isEmpty);
  });

  testWidgets(
      'unsent actions of the earlier version are sent before the restart marker',
      (tester) async {
    final harness = _Harness(coc1M2, _ServerTransport([]));
    final unsent = _action('coc1_m2', 'coc1_m2_p2', 'component_drop_attempted', {
      'runtime_action_type': 'placement_attempted',
      'item_id': 'cpu',
      'destination_id': 'cpu_socket',
    }, target: 'cpu_socket', id: 'v2-unsent');
    await harness.saveSnapshot(MissionRuntimeState.initial('coc1_m2')
        .copyWith(currentPhaseId: 'coc1_m2_p2', pendingEvidence: [unsent]));

    await _pump(tester, harness);

    expect(harness.transport.appended.map((action) => action.clientActionId),
        ['v2-unsent', harness.transport.appended.last.clientActionId]);
    expect(harness.transport.appended.last.actionType,
        'practice_progress_discarded');
    expect(find.byKey(const ValueKey('mission-updated-notice')),
        findsOneWidget);
  });

  testWidgets(
      'a class practice attempt restarted on the new version restarts only once',
      (tester) async {
    // The attempt transport returns every action, the marker included.
    final transport = _AttemptTransport([
      _action('coc1_m2', 'coc1_m2_p2', 'component_drop_attempted', {
        'runtime_action_type': 'placement_attempted',
        'item_id': 'motherboard',
        'destination_id': 'motherboard_area',
        'compatible': true,
      }, target: 'motherboard_area'),
    ]);
    final first = _Harness(coc1M2, transport);
    await _pump(tester, first);
    expect(find.byKey(const ValueKey('mission-updated-notice')),
        findsOneWidget);
    expect(transport.appended, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('mission-updated-dismiss')));
    await tester.pumpAndSettle();
    final stamped = await first.savedSnapshot();
    expect(stamped?.definitionVersion,
        MissionSimulationDefinitions.coc1M2AssemblyContractVersion,
        reason: 'the new version stamp is saved right after the restart');

    // The learner reopens the same attempt.
    await tester.pumpWidget(const SizedBox());
    final second = _Harness(coc1M2, transport, userId: first.userId);
    await _pump(tester, second);
    expect(find.byKey(const ValueKey('mission-updated-notice')), findsNothing);
    expect(transport.appended, hasLength(1),
        reason: 'no second restart marker');
    expect(second.controller.state.placements, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
