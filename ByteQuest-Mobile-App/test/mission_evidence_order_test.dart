import 'package:bytequest/screens/simulation/runtime/mission_evidence_gateway.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_controller.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:bytequest/services/progress_resume_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Final fix I1: the server replays evidence in insertion order (assessment
// by sequence_number, practice runs by id), so a write that fails must be
// retried before anything newer is sent, and a lost response must never
// duplicate an action, also across pause and resume.
void main() {
  test('a failed first write is retried first: nothing newer overtakes it',
      () async {
    final server = _Server()..failNextAppends = 1;
    final harness = _Harness(server);

    await expectLater(harness.dispatch('open-lever'), throwsStateError);
    expect(server.log, isEmpty);
    expect(harness.controller.failedPendingEvidence.map((a) => a.target),
        ['open-lever']);

    await harness.dispatch('seat-cpu');

    expect(server.log, ['open-lever', 'seat-cpu'],
        reason: 'the server sees the lever open before the CPU is seated');
    expect(harness.controller.state.pendingEvidence, isEmpty);
    expect(harness.controller.failedPendingEvidence, isEmpty);
    expect(harness.controller.canSubmit, isTrue);
  });

  test('while the older write keeps failing, newer actions are held back',
      () async {
    final server = _Server()..failNextAppends = 3;
    final harness = _Harness(server);

    await expectLater(harness.dispatch('open-lever'), throwsStateError);
    await expectLater(harness.dispatch('seat-cpu'), throwsStateError);
    await expectLater(harness.dispatch('close-lever'), throwsStateError);

    expect(server.appendAttempts, ['open-lever', 'open-lever', 'open-lever'],
        reason: 'only the oldest pending action is ever attempted');
    expect(server.log, isEmpty);
    expect(harness.controller.state.pendingEvidence.map((a) => a.target),
        ['open-lever', 'seat-cpu', 'close-lever']);
    expect(harness.controller.canSubmit, isFalse);

    await harness.controller.flushPending();

    expect(server.log, ['open-lever', 'seat-cpu', 'close-lever']);
    expect(harness.controller.state.pendingEvidence, isEmpty);
  });

  test('a write stops at the first failure and keeps what was acknowledged',
      () async {
    final server = _Server()..failNextAppends = 1;
    final harness = _Harness(server);
    await expectLater(harness.dispatch('open-lever'), throwsStateError);
    // The retry of the oldest action succeeds, then the network drops again.
    server.failAfterAppends = 1;
    await expectLater(harness.dispatch('seat-cpu'), throwsStateError);

    expect(server.log, ['open-lever']);
    expect(harness.controller.state.acceptedEvidenceIds,
        contains(harness.idOf('open-lever')));
    expect(harness.controller.state.pendingEvidence.map((a) => a.target),
        ['seat-cpu']);
    expect(harness.controller.failedPendingEvidence.map((a) => a.target),
        ['seat-cpu']);

    await harness.dispatch('close-lever');
    expect(server.log, ['open-lever', 'seat-cpu', 'close-lever']);
  });

  test('a lost response is never duplicated, also across pause and resume',
      () async {
    final server = _Server()..loseNextAcks = 1;
    final store = _MemoryStore();
    final first = _Harness(server, store: store);

    // The server stores the action but the response never arrives.
    await expectLater(first.dispatch('open-lever'), throwsStateError);
    expect(server.log, ['open-lever']);
    await first.dispatch('seat-cpu');
    expect(server.log, ['open-lever', 'seat-cpu'],
        reason: 'the acknowledged action is not sent again');

    // Another write loses its response; the app is paused and resumed.
    server.loseNextAcks = 1;
    await expectLater(first.dispatch('close-lever'), throwsStateError);
    await first.controller.persist();
    final resumed = _Harness(server, store: store, idOffset: 100);
    await resumed.controller.restore();

    expect(server.log, ['open-lever', 'seat-cpu', 'close-lever'],
        reason: 'resume reconciles with the server, so nothing repeats');
    expect(resumed.controller.state.pendingEvidence, isEmpty);
    expect(resumed.controller.state.acceptedEvidenceIds, hasLength(3));

    await resumed.dispatch('apply-compound');
    expect(server.log,
        ['open-lever', 'seat-cpu', 'close-lever', 'apply-compound']);
  });

  test('evidence pending at pause is sent first, in order, on resume',
      () async {
    final server = _Server()..failNextAppends = 2;
    final store = _MemoryStore();
    final first = _Harness(server, store: store);
    await expectLater(first.dispatch('open-lever'), throwsStateError);
    await expectLater(first.dispatch('seat-cpu'), throwsStateError);
    await first.controller.persist();

    final resumed = _Harness(server, store: store, idOffset: 100);
    await resumed.controller.restore();
    await resumed.dispatch('close-lever');

    expect(server.log, ['open-lever', 'seat-cpu', 'close-lever']);
  });

  test('order follows the actions even when the device clock steps back',
      () async {
    final server = _Server()..failNextAppends = 1;
    final harness = _Harness(server, clockStep: const Duration(minutes: -3));
    await expectLater(harness.dispatch('open-lever'), throwsStateError);
    await harness.dispatch('seat-cpu');
    expect(server.log, ['open-lever', 'seat-cpu']);
  });
}

final class _Harness {
  _Harness(
    this.server, {
    _MemoryStore? store,
    int idOffset = 0,
    Duration clockStep = const Duration(seconds: 1),
  }) : _id = idOffset {
    var time = DateTime.utc(2026, 11, 19, 8);
    controller = MissionRuntimeController(
      userId: 'learner-order',
      initialState: MissionRuntimeState.initial('coc1_m2')
          .copyWith(currentPhaseId: 'coc1_m2_p2'),
      store: store ?? _MemoryStore(),
      evidenceGateway: MissionEvidenceGateway(transport: server),
      submissionPhaseIds: const {'coc1_m2_p2'},
      clientActionIdFactory: () => 'action-${_id++}',
      clock: () => time = time.add(clockStep),
    );
  }

  final _Server server;
  int _id;
  late final MissionRuntimeController controller;

  Future<MissionEvidenceAction> dispatch(String target) => controller.dispatch(
        phaseId: 'coc1_m2_p2',
        actionType: 'equipment_operation',
        target: target,
        transition: (state) => state,
      );

  String idOf(String target) => server.byTarget[target]!;
}

/// An append-only server timeline keyed by client action id.
final class _Server implements MissionEvidenceTransport {
  final log = <String>[];
  final appendAttempts = <String>[];
  final byTarget = <String, String>{};
  final _records = <MissionEvidenceAction>[];

  /// Appends that fail before reaching the server.
  int failNextAppends = 0;

  /// Appends that succeed, after which the next one fails.
  int? failAfterAppends;

  /// Appends stored on the server whose response is lost.
  int loseNextAcks = 0;

  @override
  Future<void> append(MissionEvidenceAction action) async {
    appendAttempts.add(action.target!);
    if (failNextAppends > 0) {
      failNextAppends--;
      throw StateError('offline');
    }
    if (failAfterAppends case final remaining?) {
      if (remaining == 0) {
        failAfterAppends = null;
        throw StateError('offline');
      }
      failAfterAppends = remaining - 1;
    }
    if (_records.any((r) => r.clientActionId == action.clientActionId)) {
      throw StateError('duplicate ${action.clientActionId}');
    }
    _records.add(action);
    log.add(action.target!);
    byTarget[action.target!] = action.clientActionId;
    if (loseNextAcks > 0) {
      loseNextAcks--;
      throw StateError('response lost');
    }
  }

  @override
  Future<List<AcknowledgedMissionEvidenceAction>>
      readAcknowledgedActions() async => [
            for (final (index, action) in _records.indexed)
              AcknowledgedMissionEvidenceAction(
                action: action,
                serverRecordId: 'row-$index',
                serverOrder: index + 1,
                recordedAt: action.occurredAt,
              ),
          ];
}

final class _MemoryStore implements MissionRuntimeStore {
  MissionRuntimeState? saved;

  @override
  Future<bool> clearMissionRuntime({
    required String userId,
    required String missionId,
    required MissionRuntimeMode mode,
    String? assessmentAttemptId,
  }) async {
    saved = null;
    return true;
  }

  @override
  Future<MissionRuntimeState?> loadMissionRuntime({
    required String userId,
    required String missionId,
    required MissionRuntimeMode mode,
    String? assessmentAttemptId,
  }) async =>
      saved;

  @override
  Future<bool> saveMissionRuntime({
    required String userId,
    required MissionRuntimeState state,
  }) async {
    saved = MissionRuntimeState.fromJson(state.toJson());
    return true;
  }
}
