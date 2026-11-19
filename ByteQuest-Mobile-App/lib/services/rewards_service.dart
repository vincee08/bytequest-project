import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../models/rewards_model.dart';

/// Reads the learner Rewards projection and saves the leaderboard opt-in.
///
/// Points, levels and achievements are awarded only by the server; this
/// service never writes them. The single client write is the learner's own
/// `profiles.show_on_leaderboard` preference, which existing RLS limits to the
/// learner's own row.
class RewardsService {
  RewardsService({SupabaseClient? client}) : _client = client;

  static const _timeout = Duration(seconds: 20);

  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? SupabaseConfig.client;

  Future<LearnerRewards> fetchRewards() async {
    final result = await client.rpc('get_learner_rewards').timeout(_timeout);
    if (result is! Map) throw StateError('REWARDS_UNAVAILABLE');
    return LearnerRewards.fromJson(Map<String, dynamic>.from(result));
  }

  /// Returns the persisted preference; throws unless the server confirms it.
  Future<bool> setLeaderboardVisibility(bool visible) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('AUTHENTICATION_REQUIRED');
    final saved = await client
        .from('profiles')
        .update({'show_on_leaderboard': visible})
        .eq('user_id', userId)
        .select('show_on_leaderboard')
        .maybeSingle()
        .timeout(_timeout);
    if (saved == null || saved['show_on_leaderboard'] != visible) {
      throw StateError('LEADERBOARD_PREFERENCE_NOT_SAVED');
    }
    return visible;
  }
}
