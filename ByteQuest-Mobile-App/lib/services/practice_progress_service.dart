import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../core/config/supabase_config.dart';
import '../models/practice_progress_model.dart';

class PracticeProgressService {
  static const _configuredUrl = String.fromEnvironment('BQ_PRACTICE_API_URL');
  Future<List<PracticeCocProgress>> getProgress() async {
    final rows = await SupabaseConfig.client.rpc('get_practice_learning_path');
    return (rows as List)
        .map((r) =>
            PracticeCocProgress.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> requireMissionAccess(String mission) async {
    if (!RegExp(r'^coc[1-4]_m[1-5]$').hasMatch(mission)) {
      throw StateError('INVALID_MISSION');
    }
    final progress = await getProgress();
    if (!progress.any((p) => p.coc == mission.substring(0, 4) && p.unlocked)) {
      throw StateError('PRACTICE_COC_LOCKED');
    }
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
    if (session?.isExpired == true) {
      session = (await client.auth.refreshSession()).session;
    }
    if (session == null) throw StateError('AUTHENTICATION_REQUIRED');
    final response = await http
        .post(uri,
            headers: {
              'Authorization': 'Bearer ${session.accessToken}',
              'Content-Type': 'application/json'
            },
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('PRACTICE_REQUEST_FAILED');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }
}
