import 'dart:async';

import 'progress_resume_service.dart';

/// Provisional ByteQuest practice policy. These are not TESDA or assessment
/// limits. Change the durations here when an approved practice policy exists.
abstract final class PracticeCocTimePolicy {
  static const Map<String, Duration> durations = {
    'coc1': Duration(minutes: 60),
    'coc2': Duration(minutes: 60),
    'coc3': Duration(minutes: 60),
    'coc4': Duration(minutes: 60),
  };

  static Duration forCoc(String cocId) =>
      durations[cocId] ?? (throw ArgumentError.value(cocId, 'cocId'));
}

final class PracticeCocSession {
  const PracticeCocSession({
    required this.cocId,
    required this.startedAtUtc,
    required this.deadlineUtc,
    required this.lastObservedUtc,
  });

  final String cocId;
  final DateTime startedAtUtc;
  final DateTime deadlineUtc;
  final DateTime lastObservedUtc;

  Duration remainingAt(DateTime now) {
    final remaining = deadlineUtc.difference(now.toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool expiredAt(DateTime now) => remainingAt(now) == Duration.zero;

  /// A backward wall-clock change cannot silently extend a local session.
  /// Offline clients cannot prove elapsed time after a process restart.
  bool clockMovedBackAt(DateTime now) => now
      .toUtc()
      .isBefore(lastObservedUtc.subtract(const Duration(minutes: 2)));

  PracticeCocSession observedAt(DateTime now) {
    final utc = now.toUtc();
    return PracticeCocSession(
      cocId: cocId,
      startedAtUtc: startedAtUtc,
      deadlineUtc: deadlineUtc,
      lastObservedUtc: utc.isAfter(lastObservedUtc) ? utc : lastObservedUtc,
    );
  }

  Map<String, dynamic> toCheckpoint() => {
        'version': 1,
        'cocId': cocId,
        'startedAtUtc': startedAtUtc.toIso8601String(),
        'deadlineUtc': deadlineUtc.toIso8601String(),
        'lastObservedUtc': lastObservedUtc.toIso8601String(),
      };

  static PracticeCocSession? fromCheckpoint(
      String cocId, Map<String, dynamic>? checkpoint) {
    if (checkpoint == null ||
        checkpoint['version'] != 1 ||
        checkpoint['cocId'] != cocId) return null;
    try {
      final started =
          DateTime.parse(checkpoint['startedAtUtc'] as String).toUtc();
      final deadline =
          DateTime.parse(checkpoint['deadlineUtc'] as String).toUtc();
      final observed =
          DateTime.parse(checkpoint['lastObservedUtc'] as String).toUtc();
      if (!deadline.isAfter(started) || observed.isBefore(started)) return null;
      return PracticeCocSession(
        cocId: cocId,
        startedAtUtc: started,
        deadlineUtc: deadline,
        lastObservedUtc: observed,
      );
    } catch (_) {
      return null;
    }
  }
}

/// This checkpoint controls only local practice interaction availability.
/// It never awards completion, a grade, or an assessment result.
final class PracticeCocSessionService {
  const PracticeCocSessionService();

  static final Map<String, Future<void>> _pendingCheckpoints = {};

  Future<PracticeCocSession?> load(String userId, String cocId) async {
    final checkpoint = await ProgressResumeService.loadPracticeCocSession(
      userId: userId,
      cocId: cocId,
    );
    final session = PracticeCocSession.fromCheckpoint(cocId, checkpoint);
    if (checkpoint != null && session == null) {
      throw StateError('Practice COC session checkpoint is invalid.');
    }
    return session;
  }

  Future<PracticeCocSession> start(String userId, String cocId,
      {DateTime? now, bool restartExpired = false}) async {
    final current = now?.toUtc() ?? DateTime.now().toUtc();
    final existing = await load(userId, cocId);
    if (existing != null && (!existing.expiredAt(current) || !restartExpired))
      return existing;
    final session = PracticeCocSession(
      cocId: cocId,
      startedAtUtc: current,
      deadlineUtc: current.add(PracticeCocTimePolicy.forCoc(cocId)),
      lastObservedUtc: current,
    );
    await checkpoint(userId, session);
    return await load(userId, cocId) ?? session;
  }

  Future<void> checkpoint(String userId, PracticeCocSession session) {
    final key = '$userId\u0000${session.cocId}';
    final queued = (_pendingCheckpoints[key] ?? Future<void>.value())
        .then((_) => _writeCheckpoint(userId, session));
    final tracked = queued.catchError((Object _) {});
    _pendingCheckpoints[key] = tracked;
    unawaited(tracked.then((_) {
      if (identical(_pendingCheckpoints[key], tracked)) {
        _pendingCheckpoints.remove(key);
      }
    }));
    return queued;
  }

  Future<void> _writeCheckpoint(
      String userId, PracticeCocSession session) async {
    final current = await load(userId, session.cocId);
    if (current != null && current.startedAtUtc.isAfter(session.startedAtUtc)) {
      return;
    }
    if (current != null &&
        current.startedAtUtc.isBefore(session.startedAtUtc) &&
        !current.expiredAt(session.startedAtUtc)) {
      return;
    }
    final latest = current != null &&
            current.startedAtUtc.isAtSameMomentAs(session.startedAtUtc)
        ? session.observedAt(current.lastObservedUtc)
        : session;
    final saved = await ProgressResumeService.savePracticeCocSession(
      userId: userId,
      cocId: session.cocId,
      checkpoint: latest.toCheckpoint(),
    );
    if (!saved) throw StateError('Practice COC time could not be saved.');
  }
}
