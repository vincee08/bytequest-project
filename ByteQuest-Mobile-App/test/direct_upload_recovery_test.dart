import 'dart:convert';
import 'dart:typed_data';

import 'package:bytequest/core/config/supabase_config.dart';
import 'package:bytequest/services/auth_service.dart';
import 'package:bytequest/services/homework_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const storageOrigin = 'https://unit.supabase.co';
  const dashboardOrigin = 'https://dashboard.unit.invalid';
  const file = {
    'id': 'upload-id',
    'filename': 'report.pdf',
    'kind': 'answer',
    'size_bytes': 10485760
  };
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: storageOrigin,
        publishableKey: 'sb_publishable_unit_test_only',
        authOptions: const FlutterAuthClientOptions(autoRefreshToken: false));
    // Unit-only serialized session. No network, hosted token, or Auth Admin call.
    final payload = base64Url.encode(utf8.encode(jsonEncode({
      'exp':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
      'sub': 'unit-learner',
      'role': 'authenticated',
    })));
    await Supabase.instance.client.auth.recoverSession(jsonEncode({
      'access_token': 'unit.$payload.signature',
      'refresh_token': 'unit-refresh',
      'expires_in': 3600,
      'token_type': 'bearer',
      'user': {
        'id': 'unit-learner',
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'unit@bytequest.invalid',
        'created_at': DateTime.now().toIso8601String(),
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{}
      },
    }));
  });
  setUp(() => dotenv.testLoad(
      fileInput:
          'SUPABASE_URL=$storageOrigin\nPRACTICE_API_URL=$dashboardOrigin/api/learner/practice'));
  tearDownAll(() => Supabase.instance.dispose());

  test(
      '10 MiB homework bytes go only to Storage; retry conflict continues to metadata verification',
      () async {
    final bytes = Uint8List(10485760),
        progress = <double?>[],
        requests = <http.Request>[];
    final result = await http.runWithClient(
        () => HomeworkService().upload(
            assignmentId: 'assignment',
            filename: 'report.pdf',
            bytes: bytes,
            onProgress: progress.add),
        () => MockClient((request) async {
              requests.add(request);
              if (request.method == 'PUT') {
                expect(request.url.origin, storageOrigin);
                expect(request.headers.containsKey('authorization'), isFalse);
                expect(request.headers.containsKey('apikey'), isFalse);
                expect(request.headers['x-upsert'], 'false');
                expect(request.bodyBytes.length, bytes.length);
                return http.Response(
                    '{"statusCode":"409","code":"KeyAlreadyExists","error":"Duplicate"}',
                    400);
              }
              expect(request.url.toString(), '$dashboardOrigin/api/uploads');
              expect(request.bodyBytes.length, lessThan(8192));
              expect(
                  request.headers['authorization'], startsWith('Bearer unit.'));
              final body = jsonDecode(request.body) as Map;
              if (body['action'] == 'prepare') {
                expect(body['size'], bytes.length);
                expect(body['sha256'], sha256.convert(bytes).toString());
                return http.Response(
                    jsonEncode({
                      'upload_id': 'upload-id',
                      'signed_url':
                          '$storageOrigin/storage/v1/object/upload/sign/homework-files/scoped.pdf?token=unit-only'
                    }),
                    200);
              }
              expect(body, {'action': 'complete', 'upload_id': 'upload-id'});
              return http.Response(
                  jsonEncode({'complete': true, 'record': file}), 201);
            }));
    expect(result.id, 'upload-id');
    expect(requests.length, 3);
    expect(progress, [0, null, 0.95, 1]);
  });
  test(
      'acknowledged existing bytes resume verification without a second signed URL',
      () async {
    final requests = <String>[];
    final result = await http.runWithClient(
        () => HomeworkService().upload(
            assignmentId: 'assignment',
            filename: 'report.pdf',
            bytes: Uint8List(10)),
        () => MockClient((request) async {
              expect(request.method, 'POST');
              final action =
                  (jsonDecode(request.body) as Map)['action'] as String;
              requests.add(action);
              return http.Response(
                  jsonEncode(action == 'prepare'
                      ? {'upload_id': 'upload-id', 'uploaded': true}
                      : {'complete': true, 'record': file}),
                  200);
            }));
    expect(result.id, 'upload-id');
    expect(requests, ['prepare', 'complete']);
  });
  test('completed retry uses the original metadata without another byte upload',
      () async {
    var requests = 0;
    final result = await http.runWithClient(
        () => HomeworkService().upload(
            assignmentId: 'assignment',
            filename: 'report.pdf',
            bytes: Uint8List(10)),
        () => MockClient((request) async {
              requests++;
              expect(request.method, 'POST');
              return http.Response(
                  jsonEncode({'complete': true, 'record': file}), 200);
            }));
    expect(result.id, 'upload-id');
    expect(requests, 1);
  });
  test('untrusted signed endpoint cannot receive learner bytes or credentials',
      () async {
    var requests = 0;
    await expectLater(
        http.runWithClient(
            () => HomeworkService().upload(
                assignmentId: 'assignment',
                filename: 'report.pdf',
                bytes: Uint8List(10)),
            () => MockClient((request) async {
                  requests++;
                  return http.Response(
                      jsonEncode({
                        'upload_id': 'upload-id',
                        'signed_url':
                            'https://untrusted.invalid/storage/v1/object/upload/sign/file?token=unit-only'
                      }),
                      200);
                })),
        throwsStateError);
    expect(requests, 1);
  });
  test('oversized and unsupported homework files fail before network access',
      () async {
    await expectLater(
        HomeworkService().upload(
            assignmentId: 'assignment',
            filename: 'report.pdf',
            bytes: Uint8List(10485761)),
        throwsStateError);
    await expectLater(
        HomeworkService().upload(
            assignmentId: 'assignment',
            filename: 'report.html',
            bytes: Uint8List(10)),
        throwsStateError);
  });
  test(
      'mobile recovery uses the dashboard email endpoint with no privileged credentials',
      () async {
    expect(SupabaseConfig.recoveryUrl, '$dashboardOrigin/api/auth/recovery');
    await http.runWithClient(
        () => AuthService().resetPassword(' unit@bytequest.invalid '),
        () => MockClient((request) async {
              expect(
                  request.url.toString(), '$dashboardOrigin/api/auth/recovery');
              expect(request.headers.containsKey('authorization'), isFalse);
              expect(jsonDecode(request.body),
                  {'action': 'request', 'email': 'unit@bytequest.invalid'});
              return http.Response(
                  '{"message":"If an account exists, instructions have been sent."}',
                  200);
            }));
    await expectLater(
        http.runWithClient(
            () => AuthService().resetPassword('unit@bytequest.invalid'),
            () => MockClient((_) async => http.Response('{}', 503))),
        throwsStateError);
  });
}
