import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthRetryableFetchException;
import '../core/config/app_release.dart';
import '../core/config/supabase_config.dart';
import '../models/practice_progress_model.dart';

/// ByteQuest could not be reached (offline, timed out, blocked by the
/// browser, or the service was down), so the work was not judged at all.
/// Distinct from a refused verification (HTTP 403 or 422).
class PracticeServiceUnreachableException implements Exception {
  const PracticeServiceUnreachableException(this.cause);
  final Object cause;

  @override
  String toString() => 'PracticeServiceUnreachableException($cause)';
}

class PracticeProgressService {
  static const _configuredUrl = String.fromEnvironment('BQ_PRACTICE_API_URL');
  Future<List<PracticeCocProgress>> getProgress() async {
    final rows = await SupabaseConfig.client.rpc('get_practice_learning_path');
    return (rows as List)
        .map((r) =>
            PracticeCocProgress.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Server access check before a practice mission opens. Uses the same
  /// module-level rule as the evidence gate (`practice_mission_unlocked`), so
  /// a locked module can never be started from any screen. The error code is
  /// kept for the simulation screen, which maps it to the locked message.
  Future<void> requireMissionAccess(String mission) async {
    if (!RegExp(r'^coc[1-4]_m[1-5]$').hasMatch(mission)) {
      throw StateError('INVALID_MISSION');
    }
    final learner = SupabaseConfig.currentUserId;
    if (learner == null) throw StateError('AUTHENTICATION_REQUIRED');
    final unlocked = await SupabaseConfig.client.rpc(
      'practice_mission_unlocked',
      params: {'p_mission': mission, 'p_learner': learner},
    );
    if (unlocked != true) throw StateError('PRACTICE_COC_LOCKED');
  }

  Future<void> verifyMission(String mission) async {
    await _request({'action': 'verify', 'mission': mission});
  }

  Future<PracticeQuiz> beginQuiz(String coc) async =>
      PracticeQuiz(await _request({'action': 'begin', 'coc': coc}));
  Future<PracticeQuiz> saveAnswers(String id, Map<String, int> answers) async =>
      PracticeQuiz(
          await _request({'action': 'save', 'id': id, 'answers': answers}));
  Future<PracticeQuiz> submitQuiz(String id, Map<String, int> answers) async =>
      PracticeQuiz(
          await _request({'action': 'submit', 'id': id, 'answers': answers}));
  Future<Map<String, dynamic>> _request(Map<String, dynamic> body) async {
    final configured = _configuredUrl.isNotEmpty
        ? _configuredUrl
        : dotenv.env['PRACTICE_API_URL'] ?? '';
    final uri = Uri.tryParse(configured);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                const ['localhost', '127.0.0.1', '10.0.2.2']
                    .contains(uri.host)))) {
      throw StateError('PRACTICE_API_NOT_CONFIGURED');
    }
    final client = SupabaseConfig.client;
    var session = client.auth.currentSession;
    final http.Response response;
    try {
      if (session?.isExpired == true) {
        session = (await client.auth.refreshSession()).session;
      }
      if (session == null) throw StateError('AUTHENTICATION_REQUIRED');
      response = await http
          .post(uri,
              headers: {
                ...kAppVersionHeaders,
                'Authorization': 'Bearer ${session.accessToken}',
                'Content-Type': 'application/json'
              },
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 45));
    } on TimeoutException catch (error) {
      throw PracticeServiceUnreachableException(error);
    } on http.ClientException catch (error) {
      // Includes socket errors and a browser CORS block.
      throw PracticeServiceUnreachableException(error);
    } on AuthRetryableFetchException catch (error) {
      throw PracticeServiceUnreachableException(error);
    }
    if (response.statusCode >= 500) {
      throw PracticeServiceUnreachableException(
          StateError('PRACTICE_SERVICE_${response.statusCode}'));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('PRACTICE_REQUEST_FAILED');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }
}
