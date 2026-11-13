import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';
import '../models/learner_notification.dart';

/// All reads/writes use the current session and the existing recipient RLS.
class LearnerNotificationService {
  LearnerNotificationService({SupabaseClient? client}) : _client = client;
  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? SupabaseConfig.client;
  String get _userId =>
      client.auth.currentUser?.id ??
      (throw StateError('AUTHENTICATION_REQUIRED'));

  Future<List<LearnerNotification>> fetch(
      {int limit = 50, int offset = 0, bool unreadOnly = false}) async {
    var query = client.from('notifications').select().eq('user_id', _userId);
    if (unreadOnly) query = query.eq('is_read', false);
    final rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1);
    return rows.map(LearnerNotification.fromJson).toList(growable: false);
  }

  Future<int> unreadCount() => client
      .from('notifications')
      .count(CountOption.exact)
      .eq('user_id', _userId)
      .eq('is_read', false);

  Future<void> markRead(String id) async {
    final saved = await client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', _userId)
        .eq('id', id)
        .select('id')
        .maybeSingle();
    if (saved == null) throw StateError('NOTIFICATION_NOT_AVAILABLE');
  }

  Future<void> markAllRead() async {
    await client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', _userId)
        .eq('is_read', false);
  }
}
