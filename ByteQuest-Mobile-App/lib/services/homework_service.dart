import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../core/config/supabase_config.dart';
import '../models/homework_model.dart';

class HomeworkService {
  static const _configuredUrl = String.fromEnvironment('BQ_PRACTICE_API_URL');

  Uri _uri(String path, [Map<String, String>? query]) {
    final configured = _configuredUrl.isNotEmpty
        ? _configuredUrl
        : dotenv.env['PRACTICE_API_URL'] ?? '';
    final base = Uri.tryParse(configured);
    if (base == null ||
        !base.hasAuthority ||
        (base.scheme != 'https' &&
            !(base.scheme == 'http' &&
                ['localhost', '127.0.0.1', '10.0.2.2'].contains(base.host)))) {
      throw StateError('ACTIVITIES_API_NOT_CONFIGURED');
    }
    return base
        .resolve('/api/activities/$path')
        .replace(queryParameters: query);
  }

  Future<Map<String, String>> _headers() async {
    final client = SupabaseConfig.client;
    var session = client.auth.currentSession;
    if (session?.isExpired == true) {
      session = (await client.auth.refreshSession()).session;
    }
    if (session == null) throw StateError('AUTHENTICATION_REQUIRED');
    return {'Authorization': 'Bearer ${session.accessToken}'};
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode == 403 || response.statusCode == 404) {
      throw StateError('HOMEWORK_ACCESS_DENIED');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HOMEWORK_REQUEST_FAILED');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<List<HomeworkAssignment>> getAssignments(
      {String? id, String? classId}) async {
    final result = _decode(await http
        .get(
            _uri('homework', {
              if (id != null) 'id': id,
              if (classId != null) 'class': classId
            }),
            headers: await _headers())
        .timeout(const Duration(seconds: 35)));
    final classes = {
      for (final c in result['classes'] as List) c['id']: c['title'] as String
    };
    final submissions = {
      for (final s in result['submissions'] as List)
        s['assignment_id']:
            HomeworkSubmission.fromJson(Map<String, dynamic>.from(s as Map))
    };
    final files = result['files'] as List;
    return (result['homework'] as List).map((raw) {
      final h = Map<String, dynamic>.from(raw as Map);
      return HomeworkAssignment.fromJson(h,
          classTitle: classes[h['class_id']] ?? '',
          serverNow: DateTime.parse(result['server_now'] as String),
          submission: submissions[h['id']],
          files: files
              .where((f) => f['assignment_id'] == h['id'])
              .map((f) =>
                  HomeworkFile.fromJson(Map<String, dynamic>.from(f as Map)))
              .toList());
    }).toList();
  }

  Future<HomeworkSubmission> submit(
      {required String assignmentId,
      required String answer,
      required List<String> fileIds}) async {
    final response = await http
        .post(_uri('homework'),
            headers: {...await _headers(), 'Content-Type': 'application/json'},
            body: jsonEncode({
              'action': 'submit',
              'assignment_id': assignmentId,
              'answer': answer,
              'file_ids': fileIds
            }))
        .timeout(const Duration(seconds: 35));
    return HomeworkSubmission.fromJson(
        Map<String, dynamic>.from(_decode(response)['record'] as Map));
  }

  Future<HomeworkFile> upload(
      {required String assignmentId,
      required String filename,
      required Uint8List bytes}) async {
    if (bytes.isEmpty || bytes.length > 10485760) {
      throw StateError('FILE_SIZE_INVALID');
    }
    final mime = {
      'pdf': 'application/pdf',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      'txt': 'text/plain'
    }[filename.split('.').last.toLowerCase()];
    if (mime == null) throw StateError('FILE_TYPE_INVALID');
    final request = http.MultipartRequest(
        'POST', _uri('files', {'assignment': assignmentId}))
      ..headers.addAll(await _headers())
      ..files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: filename, contentType: MediaType.parse(mime)));
    final response = await http.Response.fromStream(
            await request.send().timeout(const Duration(seconds: 35)))
        .timeout(const Duration(seconds: 35));
    return HomeworkFile.fromJson(
        Map<String, dynamic>.from(_decode(response)['file'] as Map));
  }

  Future<Uri> fileUrl(String id) async {
    final result = _decode(await http
        .get(_uri('files', {'id': id}), headers: await _headers())
        .timeout(const Duration(seconds: 35)));
    return Uri.parse(result['url'] as String);
  }
}
