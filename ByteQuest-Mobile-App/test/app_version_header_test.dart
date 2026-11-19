import 'dart:convert';
import 'dart:io';

import 'package:bytequest/core/config/supabase_config.dart';
import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/account_content_data.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/data/quiz_content_data.dart';
import 'package:bytequest/models/assigned_activity_model.dart';
import 'package:bytequest/models/learner_quiz_model.dart';
import 'package:bytequest/screens/quizzes/quiz_details_screen.dart';
import 'package:bytequest/screens/settings/settings_screen.dart';
import 'package:bytequest/services/app_version_service.dart';
import 'package:bytequest/services/auth_service.dart';
import 'package:bytequest/services/authoritative_assessment_service.dart';
import 'package:bytequest/services/curriculum_service.dart';
import 'package:bytequest/services/homework_service.dart';
import 'package:bytequest/services/learner_quiz_service.dart';
import 'package:bytequest/services/practice_progress_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Final fix I5 / rest I1 (Flutter side of the client-version marker): the
// 1.2.0+ app names its version on every Supabase and dashboard API request,
// maps the server's APP_UPDATE_REQUIRED refusal to a clear message, and
// shows the installed version in Settings.
const _supabaseOrigin = 'https://unit.supabase.co';
const _dashboardOrigin = 'https://dashboard.unit.invalid';
const _refusal = {
  'code': 'P0001',
  'message':
      'APP_UPDATE_REQUIRED: Update ByteQuest to version 1.2.0 or later to take this assessment.',
  'details': null,
  'hint': null,
};

final _supabaseRequests = <http.BaseRequest>[];

http.Response _json(http.Request request, Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'});

Future<http.Response> _supabase(http.Request request) async {
  _supabaseRequests.add(request);
  return switch (request.url.path) {
    '/rest/v1/rpc/start_attempt' ||
    '/rest/v1/rpc/start_learner_quiz' =>
      _json(request, _refusal, 400),
    _ => _json(request, const []),
  };
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SupabaseConfig.initializeClient(
      url: _supabaseOrigin,
      publishableKey: 'sb_publishable_unit_test_only',
      httpClient: MockClient(_supabase),
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
    // Unit-only serialized session; no network or hosted token.
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
      fileInput: 'SUPABASE_URL=$_supabaseOrigin\n'
          'PRACTICE_API_URL=$_dashboardOrigin/api/learner/practice'));
  tearDownAll(() => Supabase.instance.dispose());

  test('the version constants equal the pubspec version and build', () {
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())!
        .group(1)!;
    expect(version, '$kAppVersion+$kAppBuildNumber');
    expect(kAppVersionHeaders, {'x-bytequest-app-version': kAppVersion});
  });

  test('every Supabase request names the app version', () async {
    _supabaseRequests.clear();
    await SupabaseConfig.client.rpc('get_learner_curriculum');
    await SupabaseConfig.client.from('app_release_config').select('value');
    expect(_supabaseRequests, hasLength(2));
    for (final request in _supabaseRequests) {
      expect(request.headers['x-bytequest-app-version'], kAppVersion,
          reason: request.url.path);
    }
  });

  test('every dashboard API request names the app version', () async {
    final requests = <http.BaseRequest>[];
    Future<http.Response> dashboard(http.Request request) async {
      requests.add(request);
      return switch (request.url.path) {
        '/api/activities/homework' => _json(request, {
            'classes': const [],
            'submissions': const [],
            'files': const [],
            'homework': const [],
            'server_now': '2026-11-19T08:00:00Z',
          }),
        _ => _json(request, const <String, dynamic>{}),
      };
    }

    final client = MockClient(dashboard);
    await http.runWithClient(() async {
      await HomeworkService().getAssignments();
      await PracticeProgressService().verifyMission('coc1_m2');
      await AuthService().resetPassword('learner@bytequest.invalid');
    }, () => client);
    await CurriculumService(httpClient: client).completeTopic('topic-1');

    expect(requests.map((request) => request.url.path), [
      '/api/activities/homework',
      '/api/learner/practice',
      '/api/auth/recovery',
      '/api/learner/curriculum',
    ]);
    for (final request in requests) {
      expect(request.headers['x-bytequest-app-version'], kAppVersion,
          reason: request.url.path);
    }
  });

  test('a refused assessment start asks the learner to update', () async {
    final assignment = AssignedActivity(
      id: 'assignment-1',
      classId: 'class-1',
      classTitle: 'CSS NC II',
      activityVersionId: 'version-1',
      rubricVersionId: 'rubric-1',
      assignmentType: 'assessment',
      title: 'Assemble the system unit',
      instructions: null,
      availableAt: null,
      dueAt: null,
      activityTitle: 'COC1 M2',
      deliveryMode: 'simulation',
      learnerPayload: {
        'mode': 'assessment',
        'mission_id': 'coc1_m2',
        'definition_version':
            MissionSimulationDefinitions.contractVersion('coc1_m2'),
      },
      missionId: 'coc1_m2',
      missionCode: 'COC1_M2',
    );
    await expectLater(
      AuthoritativeAssessmentService.instance.startAttempt(assignment),
      throwsA(isA<AssessmentUpdateRequiredException>()),
    );
    expect(AuthoritativeAssessmentService.instance.activeSession, isNull,
        reason: 'nothing is started locally either');
  });

  test('a refused quiz start asks the learner to update', () async {
    await expectLater(
      LearnerQuizService().startOrResume('assignment-1'),
      throwsA(isA<LearnerQuizUpdateRequiredException>()),
    );
    expect(isAppUpdateRequiredError(StateError('QUIZ_NOT_AVAILABLE')), isFalse);
  });

  testWidgets('the quiz screen shows the update message', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: QuizDetailsScreen(
        quiz: LearnerQuizSummary.fromJson(const {
          'assignment_id': 'assignment-1',
          'quiz_version_id': 'version-1',
          'quiz_id': 'quiz-1',
          'title': 'Scenario essay check',
          'class_id': 'class-1',
          'class_title': 'CSS NC II',
          'is_available': true,
          'essay_count': 1,
        }),
        service: _RefusingQuizService(),
      ),
    ));
    await tester.pumpAndSettle();
    final start = find.byType(FilledButton).last;
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.text(QuizContentData.updateRequired), findsOneWidget);
    expect(find.text(QuizContentData.openFailed), findsNothing);
  });

  testWidgets('Settings shows the installed version and build',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme, home: const SettingsScreen()));
    await tester.pumpAndSettle();
    final label =
        AccountContentData.appVersionLabel(kAppVersion, kAppBuildNumber);
    expect(label, 'Version 1.2.0 (build 3)');
    await tester.scrollUntilVisible(find.text(label), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(label), findsOneWidget);
    expect(find.textContaining('1.0.0'), findsNothing);
    await tester.tap(find.text('About ByteQuest'));
    await tester.pumpAndSettle();
    expect(find.text(label), findsNWidgets(2), reason: 'tile and dialog');
  });
}

final class _RefusingQuizService extends LearnerQuizService {
  @override
  Future<LearnerQuizAttempt> startOrResume(String assignmentId) async =>
      throw const LearnerQuizUpdateRequiredException();
}
