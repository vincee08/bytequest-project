import 'dart:convert';

import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/screens/simulation/mission_simulation_screen.dart';
import 'package:bytequest/services/practice_progress_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// QA Q2: a network failure (offline, timeout, CORS, service down) is never
// reported as a failed verification of the learner's work.
void main() {
  const dashboard = 'https://dashboard.unit.invalid';
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://unit.supabase.co',
        publishableKey: 'sb_publishable_unit_test_only',
        authOptions: const FlutterAuthClientOptions(autoRefreshToken: false));
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
        'user_metadata': <String, dynamic>{},
      },
    }));
  });
  setUp(() => dotenv.testLoad(
      fileInput: 'PRACTICE_API_URL=$dashboard/api/learner/practice'));
  tearDownAll(() => Supabase.instance.dispose());

  Future<Object?> verifyWith(MockClientHandler handler) async {
    try {
      await http.runWithClient(
          () => PracticeProgressService().verifyMission('coc1_m2'),
          () => MockClient(handler));
      return null;
    } catch (error) {
      return error;
    }
  }

  http.Response reply(http.Request request, int status) => http.Response(
      jsonEncode(status == 200
          ? {'verified': true}
          : {'error': 'The server could not verify this work.'}),
      status,
      request: request,
      headers: {'content-type': 'application/json'});

  test('no connection or a blocked request reads as unreachable', () async {
    final error = await verifyWith(
        (request) async => throw http.ClientException('XMLHttpRequest error.'));
    expect(error, isA<PracticeServiceUnreachableException>());
    expect(practiceVerifyFailureMessage(error!),
        MissionContentData.practiceVerifyUnreachable);
  });

  test('a service outage reads as unreachable', () async {
    for (final status in const [500, 502, 503]) {
      final error = await verifyWith((request) async => reply(request, status));
      expect(error, isA<PracticeServiceUnreachableException>(),
          reason: '$status');
      expect(practiceVerifyFailureMessage(error!),
          MissionContentData.practiceVerifyUnreachable);
    }
  });

  test('a refused verification keeps the verification message', () async {
    for (final status in const [403, 422]) {
      final error = await verifyWith((request) async => reply(request, status));
      expect(error, isNot(isA<PracticeServiceUnreachableException>()),
          reason: '$status');
      expect(practiceVerifyFailureMessage(error!),
          MissionContentData.practiceSubmitFailed);
    }
    expect(await verifyWith((request) async => reply(request, 200)), isNull);
  });

  test('the two messages say different things', () {
    expect(MissionContentData.practiceVerifyUnreachable,
        isNot(MissionContentData.practiceSubmitFailed));
    expect(MissionContentData.practiceVerifyUnreachable, contains('saved'));
    expect(MissionContentData.practiceVerifyUnreachable,
        isNot(contains('could not verify this work')));
  });
}
