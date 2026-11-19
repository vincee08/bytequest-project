import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../models/performance_model.dart';

/// Reads the learner's own performance projection and reports when it may
/// have changed. Realtime events only trigger a refetch; numbers always come
/// from the `get_my_performance()` SECURITY INVOKER RPC.
class PerformanceService {
  PerformanceService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? SupabaseConfig.client;

  /// Tables whose rows carry the learner id directly.
  static const ownRowTables = <String>[
    'practice_mission_runs',
    'practice_mission_completions',
    'practice_coc_progress',
    'learner_topic_progress',
    'learner_module_completions',
    'attempts',
    'quiz_attempts',
    'homework_submissions',
  ];

  /// Tables without a learner column; RLS limits delivery to the learner's
  /// own released attempts and results.
  static const scopedTables = <String>[
    'result_releases',
    'score_revisions',
    'criterion_results',
    'quiz_results',
    'quiz_result_finalizations',
  ];

  Future<PerformanceSnapshot> fetchMyPerformance() async {
    final response = await _client.rpc('get_my_performance');
    if (response is! Map) throw StateError('PERFORMANCE_UNAVAILABLE');
    return PerformanceSnapshot.fromJson(Map<String, dynamic>.from(response));
  }

  /// Quiz titles by attempt id, in one call to the learner's quiz list
  /// (`get_available_learner_quizzes`). Learners cannot read quiz titles
  /// directly under RLS, so `get_my_performance()` carries none.
  Future<Map<String, String>> fetchQuizTitles() async {
    final response = await _client.rpc('get_available_learner_quizzes');
    if (response is! List) throw StateError('QUIZ_TITLES_UNAVAILABLE');
    return {
      for (final entry in response.whereType<Map>())
        if (entry['attempt_id'] is String && entry['title'] is String)
          entry['attempt_id'] as String: entry['title'] as String,
    };
  }

  /// Emits whenever one of the learner's performance records changes.
  /// The channel is opened on first listen and removed when cancelled.
  Stream<void> watchChanges() {
    RealtimeChannel? channel;
    var cancelled = false;
    late final StreamController<void> controller;
    controller = StreamController<void>.broadcast(
      onListen: () async {
        cancelled = false;
        final opened = await _subscribe(controller);
        if (cancelled && opened != null) {
          await _client.removeChannel(opened);
        } else {
          channel = opened;
        }
      },
      onCancel: () async {
        cancelled = true;
        final current = channel;
        channel = null;
        if (current != null) await _client.removeChannel(current);
      },
    );
    return controller.stream;
  }

  Future<RealtimeChannel?> _subscribe(StreamController<void> controller) async {
    final session = _client.auth.currentSession;
    if (session == null) return null;
    final userId = session.user.id;
    // The JWT is required for Realtime's per-event RLS visibility check.
    await _client.realtime.setAuth(session.accessToken);
    final channel = _client.channel('learner-performance-$userId');
    void emit(PostgresChangePayload _) {
      if (!controller.isClosed) controller.add(null);
    }

    for (final table in ownRowTables) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'learner_id',
          value: userId,
        ),
        callback: emit,
      );
    }
    for (final table in scopedTables) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: emit,
      );
    }
    channel.subscribe();
    return channel;
  }
}
