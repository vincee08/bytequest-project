import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

import '../core/config/supabase_config.dart';
import '../models/homework_model.dart';

class HomeworkService {
  static const _configuredUrl = String.fromEnvironment('BQ_PRACTICE_API_URL');

  bool _duplicateUpload(http.Response response) {
    if (response.statusCode == 409) return true;
    if (response.statusCode != 400) return false;
    try {
      final error = jsonDecode(response.body);
      return error is Map &&
          error['statusCode'].toString() == '409' &&
          (error['code'] == 'KeyAlreadyExists' ||
              error['error'] == 'Duplicate');
    } catch (_) {
      return false;
    }
  }

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
      required Uint8List bytes,
      void Function(double?)? onProgress}) async {
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
    Future<Map<String, dynamic>> action(Map<String, dynamic> body) async =>
        _decode(await http
            .post(_uri('files').replace(path: '/api/uploads'),
                headers: {
                  ...await _headers(),
                  'Content-Type': 'application/json'
                },
                body: jsonEncode(body))
            .timeout(const Duration(seconds: 150)));
    onProgress?.call(0);
    final prepared = await action({
      'action': 'prepare',
      'purpose': 'homework',
      'target_id': assignmentId,
      'filename': filename,
      'mime': mime,
      'size': bytes.length,
      'sha256': sha256.convert(bytes).toString()
    });
    if (prepared['complete'] != true) {
      if (prepared['uploaded'] != true) {
        final storage = Uri.parse(prepared['signed_url'] as String);
        final project = Uri.parse(SupabaseConfig.projectUrl);
        if (storage.origin != project.origin ||
            !storage.path.startsWith('/storage/v1/object/upload/sign/')) {
          throw StateError('UPLOAD_ENDPOINT_INVALID');
        }
        // Indeterminate progress represents the actual native network transfer;
        // verification begins only after Storage acknowledges the request.
        onProgress?.call(null);
        final response = await http
            .put(storage,
                headers: {'Content-Type': mime, 'x-upsert': 'false'},
                body: bytes)
            .timeout(const Duration(seconds: 180));
        if ((response.statusCode < 200 || response.statusCode >= 300) &&
            !_duplicateUpload(response)) {
          throw StateError('DIRECT_UPLOAD_FAILED');
        }
      }
      onProgress?.call(0.95);
      final complete = await action(
          {'action': 'complete', 'upload_id': prepared['upload_id']});
      onProgress?.call(1);
      return HomeworkFile.fromJson(
          Map<String, dynamic>.from(complete['record'] as Map));
    }
    onProgress?.call(1);
    return HomeworkFile.fromJson(
        Map<String, dynamic>.from(prepared['record'] as Map));
  }

  Future<Uri> fileUrl(String id) async {
    final result = _decode(await http
        .get(_uri('files', {'id': id}), headers: await _headers())
        .timeout(const Duration(seconds: 35)));
    return Uri.parse(result['url'] as String);
  }
}
