import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_release.dart';
import '../core/config/supabase_config.dart';
import '../models/curriculum_model.dart';

enum CurriculumFailure { moduleLocked, notPublished, notConfigured, failed }

class CurriculumException implements Exception {
  const CurriculumException(this.failure);
  final CurriculumFailure failure;

  @override
  String toString() => 'CurriculumException($failure)';
}

/// Learner curriculum access. Reads use the learner's own Supabase session
/// (the projection is a SECURITY INVOKER function under RLS); topic completion
/// goes through the authenticated dashboard route because the workflow
/// function is service-only. Nothing is computed or unlocked locally.
class CurriculumService {
  CurriculumService({SupabaseClient? client, http.Client? httpClient})
      : _clientOverride = client,
        _http = httpClient;

  static const _configuredUrl = String.fromEnvironment('BQ_PRACTICE_API_URL');
  final SupabaseClient? _clientOverride;
  final http.Client? _http;

  SupabaseClient get _client => _clientOverride ?? SupabaseConfig.client;

  Future<CurriculumProjection> getCurriculum() async {
    final response = await _client.rpc('get_learner_curriculum');
    return CurriculumProjection.fromJson(response);
  }

  /// Learners can read only published revisions (RLS); drafts never load.
  Future<CurriculumLesson> getLesson(String revisionId) async {
    final row = await _client
        .from('curriculum_topic_revisions')
        .select('id,title,summary,body_markdown')
        .eq('id', revisionId)
        .eq('status', 'published')
        .maybeSingle();
    if (row == null) {
      throw const CurriculumException(CurriculumFailure.notPublished);
    }
    return CurriculumLesson.fromJson(Map<String, dynamic>.from(row));
  }

  /// Records completion of a published topic in an unlocked module. Returns
  /// the refreshed projection when the server includes it.
  Future<CurriculumProjection?> completeTopic(String topicId) async {
    final configured = _configuredUrl.isNotEmpty
        ? _configuredUrl
        : dotenv.env['PRACTICE_API_URL'] ?? '';
    final base = Uri.tryParse(configured);
    if (base == null ||
        !base.hasAuthority ||
        (base.scheme != 'https' &&
            !(base.scheme == 'http' &&
                const ['localhost', '127.0.0.1', '10.0.2.2']
                    .contains(base.host)))) {
      throw const CurriculumException(CurriculumFailure.notConfigured);
    }
    var session = _client.auth.currentSession;
    if (session?.isExpired == true) {
      session = (await _client.auth.refreshSession()).session;
    }
    if (session == null) {
      throw const CurriculumException(CurriculumFailure.failed);
    }
    final uri = base.resolve('/api/learner/curriculum');
    final headers = {
      ...kAppVersionHeaders,
      'Authorization': 'Bearer ${session.accessToken}',
      'Content-Type': 'application/json',
    };
    final body = jsonEncode({'action': 'complete_topic', 'topic_id': topicId});
    final client = _http;
    final response = await (client != null
            ? client.post(uri, headers: headers, body: body)
            : http.post(uri, headers: headers, body: body))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 403) {
      throw const CurriculumException(CurriculumFailure.moduleLocked);
    }
    if (response.statusCode == 404) {
      throw const CurriculumException(CurriculumFailure.notPublished);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const CurriculumException(CurriculumFailure.failed);
    }
    final decoded = jsonDecode(response.body);
    final curriculum = decoded is Map ? decoded['curriculum'] : null;
    return curriculum == null
        ? null
        : CurriculumProjection.fromJson(curriculum);
  }
}
