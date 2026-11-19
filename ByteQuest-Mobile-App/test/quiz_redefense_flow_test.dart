import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/data/quiz_content_data.dart';
import 'package:bytequest/models/learner_quiz_model.dart';
import 'package:bytequest/screens/quizzes/quiz_result_screen.dart';
import 'package:bytequest/screens/quizzes/quiz_status_label.dart';
import 'package:bytequest/screens/quizzes/quiz_taking_screen.dart';
import 'package:bytequest/services/learner_quiz_service.dart';
import 'package:bytequest/services/learner_realtime_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeQuizService extends LearnerQuizService {
  FakeQuizService({this.result});

  final saves = <(String, String)>[];
  LearnerQuizResult? result;
  int resultCalls = 0;
  bool refuseSaves = false;

  @override
  Future<void> saveAnswer({
    required String attemptId,
    required String itemId,
    required String answer,
  }) async {
    if (refuseSaves) {
      throw const LearnerQuizClosedException('QUIZ_NOT_AVAILABLE');
    }
    saves.add((itemId, answer));
  }

  @override
  Future<LearnerQuizResult> getResult(String attemptId) async {
    resultCalls++;
    final value = result;
    if (value == null) throw StateError('QUIZ_RESULT_NOT_AVAILABLE');
    return value;
  }

  /// Offline: the screen keeps the server expiry it already has.
  @override
  Future<List<LearnerQuizSummary>> getAvailableQuizzes() async =>
      throw StateError('offline');
}

class MemoryDraftStore implements QuizEssayDraftStore {
  final drafts = <String, String>{};

  @override
  Future<String?> read(String attemptId, String itemId) async =>
      drafts['$attemptId/$itemId'];

  @override
  Future<void> write(String attemptId, String itemId, String text) async =>
      drafts['$attemptId/$itemId'] = text;

  @override
  Future<void> clear(String attemptId, String itemId) async =>
      drafts.remove('$attemptId/$itemId');
}

LearnerQuizAttempt essayAttempt({
  String? savedEssay,
  int? timeLimit,
  String expiresAt = '2035-01-01T08:30:00Z',
}) =>
    LearnerQuizAttempt.fromJson({
      'attempt_id': 'attempt-1',
      'status': 'in_progress',
      'started_at': '2035-01-01T08:00:00Z',
      'server_now': '2035-01-01T08:00:00Z',
      'due_at': '2035-01-01T09:00:00Z',
      'time_limit_minutes': timeLimit,
      'expires_at': expiresAt,
      'result_release_mode': 'instructor_release',
      'quiz': {
        'assignment_id': 'assignment-1',
        'title': 'Assembly essay check',
        'class_title': 'CSS NC II',
        'version_number': 1,
      },
      'questions': [
        {
          'id': 'essay-1',
          'code': 'ITEM-001',
          'type': 'scenario_essay',
          'prompt': 'Explain how you would install the processor safely.',
          'options': const [],
          'order_index': 1,
          'saved_answer': savedEssay,
          'points': 10,
          'scenario':
              'A client left an unassembled workstation on your bench with an anti-static mat.',
          'min_words': 10,
          'max_words': 120,
          'max_answer_length': 10000,
          'rubric': [
            {'id': 'C1', 'criterion': 'Safety', 'max_points': 4},
            {'id': 'C2', 'criterion': 'Procedure', 'max_points': 6},
          ],
        },
      ],
    });

LearnerQuizResult resultFrom(Map<String, dynamic> overrides) =>
    LearnerQuizResult.fromJson({
      'attempt_id': 'attempt-1',
      'status': 'completed',
      'title': 'Assembly essay check',
      'class_title': 'CSS NC II',
      'completed_at': '2035-01-01T08:10:00Z',
      'submitted_at': '2035-01-01T08:10:00Z',
      'question_count': 2,
      'answered_count': 1,
      ...overrides,
    });

final awaitingJson = <String, dynamic>{
  'submission_kind': 'auto_time_limit',
  'evaluation_status': 'pending',
  'result_status': 'awaiting_evaluation',
  'item_results': [
    {
      'item_id': 'mc-1',
      'type': 'multiple_choice',
      'prompt': 'Which tool prevents ESD damage?',
      'learner_answer': 'Wrist strap',
      'answered': true,
      'order_index': 1,
    },
    {
      'item_id': 'essay-1',
      'type': 'scenario_essay',
      'prompt': 'Explain how you would install the processor safely.',
      'learner_answer': null,
      'answered': false,
      'order_index': 2,
    },
  ],
};

final releasedJson = <String, dynamic>{
  'submission_kind': 'learner',
  'evaluation_status': 'released',
  'result_status': 'released',
  'correct_count': 1,
  'objective_points': 3,
  'essay_points': 9,
  'total_points': 12,
  'max_points': 13,
  'percent': 92.31,
  'released_at': '2035-01-02T09:00:00Z',
  'item_results': [
    {
      'item_id': 'mc-1',
      'type': 'multiple_choice',
      'prompt': 'Which tool prevents ESD damage?',
      'learner_answer': 'Wrist strap',
      'answered': true,
      'is_correct': true,
      'points': 3,
      'points_awarded': 3,
      'order_index': 1,
    },
    {
      'item_id': 'essay-1',
      'type': 'scenario_essay',
      'prompt': 'Explain how you would install the processor safely.',
      'learner_answer': 'Ground yourself, lift the lever, align the triangle.',
      'answered': true,
      'is_correct': null,
      'points': 10,
      'points_awarded': 9,
      'feedback': 'Complete ESD and orientation steps.',
      'rubric': [
        {
          'id': 'C1',
          'criterion': 'Safety',
          'description': 'ESD precautions before handling',
          'max_points': 4,
          'points': 4,
        },
        {
          'id': 'C2',
          'criterion': 'Procedure',
          'description': 'Lever, alignment and seating',
          'max_points': 6,
          'points': 5,
        },
      ],
      'order_index': 2,
    },
  ],
};

Widget host(Widget home, {double textScale = 1, bool reduceMotion = false}) =>
    ChangeNotifierProvider(
      create: (_) => LearnerRealtimeCoordinator(),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: home,
      ),
    );

/// Result lists are lazy; a tall view builds every item for assertions.
void usePhone(WidgetTester tester, {double height = 844}) {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'sb_publishable_quiz_redefense_test',
    );
  });

  test('summary, question and result models carry the new quiz states', () {
    final summary = LearnerQuizSummary.fromJson({
      'assignment_id': 'a',
      'quiz_version_id': 'v',
      'quiz_id': 'q',
      'title': 'Timed check',
      'class_id': 'c',
      'class_title': 'Class',
      'is_available': false,
      'attempt_id': 'attempt',
      'attempt_status': 'completed',
      'status': 'awaiting_evaluation',
      'submission_kind': 'auto_deadline',
      'evaluation_status': 'pending',
      'time_limit_minutes': 15,
      'essay_count': 1,
      'module_codes': ['LO1.1'],
    });
    expect(summary.state, LearnerQuizState.completed);
    expect(summary.isAutoSubmitted, isTrue);
    expect(summary.awaitingEvaluation, isTrue);
    expect(summary.usesInstructorRelease, isTrue);
    expect(quizStatusLabel(summary),
        '${QuizContentData.statusAutoSubmitted} · ${QuizContentData.statusAwaitingEvaluation}');
    expect(quizOpensResult(summary), isTrue);

    final question = essayAttempt().questions.single;
    expect(question.isEssay, isTrue);
    expect(question.rubric.map((c) => c.criterion), ['Safety', 'Procedure']);
    expect(question.rubric.first.description, isNull,
        reason: 'descriptors are not sent during an attempt');
    expect(question.maxAnswerLength, 10000);

    final released = resultFrom(releasedJson);
    expect(released.released, isTrue);
    expect(released.displayScore, 12);
    expect(released.displayMax, 13);
    expect(released.items.last.rubric.last.points, 5);

    final legacy = resultFrom({'correct_count': 3, 'question_count': 4});
    expect(legacy.resultStatus, 'available');
    expect(legacy.displayScore, 3);
    expect(legacy.displayMax, 4);
  });

  test('word counting and guidance strings', () {
    expect(QuizContentData.countWords('  Ground   yourself first  '), 3);
    expect(QuizContentData.countWords(''), 0);
    expect(QuizContentData.wordCountStatus(3, 10, 50),
        '3 words · below the suggested minimum');
    expect(QuizContentData.wordCountStatus(1, null, null), '1 word');
    expect(QuizContentData.wordGuidance(10, 120),
        'Suggested length: 10–120 words');
  });

  testWidgets('essay shows the scenario, live word count and autosaves',
      (tester) async {
    usePhone(tester);
    final service = FakeQuizService();
    final drafts = MemoryDraftStore();
    var now = DateTime.utc(2035, 1, 1, 8);
    await tester.pumpWidget(host(QuizTakingScreen(
      attempt: essayAttempt(),
      service: service,
      draftStore: drafts,
      now: () => now,
    )));
    await tester.pump();
    expect(find.text(QuizContentData.typeScenarioEssay.toUpperCase()),
        findsOneWidget);
    expect(find.textContaining('unassembled workstation'), findsOneWidget);
    expect(find.text(QuizContentData.rubricCriterion('Safety', 4)),
        findsOneWidget);
    expect(find.text(QuizContentData.wordGuidance(10, 120)), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('quiz-essay-field')),
        'Ground yourself before touching the CPU socket');
    await tester.pump();
    expect(find.text('7 words · below the suggested minimum'), findsOneWidget);
    expect(find.text(QuizContentData.essayUnsaved), findsOneWidget);
    expect(drafts.drafts['attempt-1/essay-1'],
        'Ground yourself before touching the CPU socket',
        reason: 'the device keeps unsaved writing');
    expect(service.saves, isEmpty, reason: 'autosave waits for a pause');

    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(service.saves.single,
        ('essay-1', 'Ground yourself before touching the CPU socket'));
    expect(find.text(QuizContentData.essaySaved), findsOneWidget);
    expect(drafts.drafts, isEmpty, reason: 'a saved draft is cleared');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unsaved essay draft is restored and saved on reopen',
      (tester) async {
    usePhone(tester);
    final service = FakeQuizService();
    final drafts = MemoryDraftStore()
      ..drafts['attempt-1/essay-1'] =
          'Draft written offline before the app closed unexpectedly';
    await tester.pumpWidget(host(QuizTakingScreen(
      attempt: essayAttempt(savedEssay: 'Older server copy'),
      service: service,
      draftStore: drafts,
      now: () => DateTime.utc(2035, 1, 1, 8),
    )));
    await tester.pump();
    await tester.pump();
    expect(find.text(QuizContentData.essayRestored), findsOneWidget);
    expect(
        find.text('Draft written offline before the app closed unexpectedly'),
        findsOneWidget);
    expect(service.saves.single.$2,
        'Draft written offline before the app closed unexpectedly');
    expect(drafts.drafts, isEmpty);
  });

  testWidgets('a matching device draft is discarded without a save',
      (tester) async {
    usePhone(tester);
    final service = FakeQuizService();
    final drafts = MemoryDraftStore()
      ..drafts['attempt-1/essay-1'] = 'Server copy';
    await tester.pumpWidget(host(QuizTakingScreen(
      attempt: essayAttempt(savedEssay: 'Server copy'),
      service: service,
      draftStore: drafts,
      now: () => DateTime.utc(2035, 1, 1, 8),
    )));
    await tester.pump();
    await tester.pump();
    expect(find.text(QuizContentData.essayRestored), findsNothing);
    expect(service.saves, isEmpty);
    expect(drafts.drafts, isEmpty);
  });

  testWidgets(
      'timed quiz counts down from the server expiry and shows the auto-submission',
      (tester) async {
    usePhone(tester);
    final service = FakeQuizService(
      result: resultFrom(awaitingJson),
    );
    var now = DateTime.utc(2035, 1, 1, 8);
    await tester.pumpWidget(host(QuizTakingScreen(
      attempt: essayAttempt(timeLimit: 2, expiresAt: '2035-01-01T08:02:00Z'),
      service: service,
      draftStore: MemoryDraftStore(),
      now: () => now,
    )));
    expect(find.text(QuizContentData.timeLeft('02:00')), findsOneWidget);
    expect(find.text(QuizContentData.timeAlmostUp), findsNothing);

    now = now.add(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(QuizContentData.timeLeft('00:59')), findsOneWidget);
    expect(find.text(QuizContentData.timeAlmostUp), findsOneWidget);

    now = now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(service.resultCalls, greaterThanOrEqualTo(1));
    expect(find.byType(QuizResultScreen), findsOneWidget);
    expect(find.text(QuizContentData.autoSubmittedTimeLimit), findsOneWidget);
    expect(find.text(QuizContentData.statusAwaitingEvaluation), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz-result-score')), findsNothing,
        reason: 'no total is shown before release');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a refused save after expiry moves to the automatic submission',
      (tester) async {
    usePhone(tester);
    final service = FakeQuizService(result: resultFrom(awaitingJson))
      ..refuseSaves = true;
    await tester.pumpWidget(host(QuizTakingScreen(
      attempt: essayAttempt(),
      service: service,
      draftStore: MemoryDraftStore(),
      now: () => DateTime.utc(2035, 1, 1, 8),
    )));
    await tester.enterText(find.byKey(const ValueKey('quiz-essay-field')),
        'Late text that the server refuses');
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(find.byType(QuizResultScreen), findsOneWidget);
    expect(find.text(QuizContentData.autoSubmittedTimeLimit), findsOneWidget);
  });

  testWidgets('awaiting evaluation hides scores and correctness',
      (tester) async {
    usePhone(tester, height: 2400);
    await tester.pumpWidget(host(QuizResultScreen(
      attemptId: 'attempt-1',
      initialResult: resultFrom({
        ...awaitingJson,
        'submission_kind': 'auto_deadline',
      }),
      service: FakeQuizService(),
    )));
    expect(find.text(QuizContentData.statusAwaitingEvaluation), findsOneWidget);
    expect(find.text(QuizContentData.autoSubmittedDeadline), findsOneWidget);
    expect(find.text(QuizContentData.answeredCount(1, 2)), findsOneWidget);
    expect(find.text(QuizContentData.itemNotAnswered), findsOneWidget);
    expect(find.text(QuizContentData.itemCorrect), findsNothing);
    expect(find.text(QuizContentData.itemNeedsReview), findsNothing);
    expect(find.byKey(const ValueKey('quiz-result-score')), findsNothing);
  });

  testWidgets('released result shows rubric points and instructor feedback',
      (tester) async {
    usePhone(tester, height: 2400);
    await tester.pumpWidget(host(QuizResultScreen(
      attemptId: 'attempt-1',
      initialResult: resultFrom(releasedJson),
      service: FakeQuizService(),
    )));
    expect(find.text(QuizContentData.resultReleased), findsOneWidget);
    expect(find.text(QuizContentData.scoreOf('12', '13')), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('quiz-feedback-essay-1')), 200);
    expect(find.text('Complete ESD and orientation steps.'), findsOneWidget);
    expect(find.text(QuizContentData.itemPoints(9, 10)), findsOneWidget);
    expect(find.text(QuizContentData.itemPoints(5, 6)), findsOneWidget);
    expect(find.text('Lever, alignment and seating'), findsOneWidget);
    expect(find.text(QuizContentData.autoSubmittedDeadline), findsNothing);
  });

  testWidgets('immediate results still show correct answers', (tester) async {
    usePhone(tester, height: 2400);
    await tester.pumpWidget(host(QuizResultScreen(
      attemptId: 'attempt-1',
      initialResult: resultFrom({
        'correct_count': 1,
        'question_count': 2,
        'item_results': [
          {
            'item_id': 'mc-1',
            'type': 'multiple_choice',
            'prompt': 'Which device routes packets?',
            'learner_answer': 'Router',
            'is_correct': true,
            'order_index': 1,
          },
          {
            'item_id': 'tf-1',
            'type': 'true_false',
            'prompt': 'A hub filters by MAC address.',
            'learner_answer': 'True',
            'is_correct': false,
            'order_index': 2,
          },
        ],
      }),
      service: FakeQuizService(),
    )));
    expect(find.text(QuizContentData.scoreOf('1', '2')), findsOneWidget);
    expect(find.text(QuizContentData.correctLabel), findsOneWidget);
    expect(find.text(QuizContentData.itemCorrect), findsOneWidget);
    expect(find.text(QuizContentData.itemNeedsReview), findsOneWidget);
  });

  for (final reduceMotion in [false, true]) {
    testWidgets(
        'large text keeps quiz screens readable (reduce motion: $reduceMotion)',
        (tester) async {
      usePhone(tester);
      await tester.pumpWidget(host(
        QuizTakingScreen(
          attempt:
              essayAttempt(timeLimit: 30, expiresAt: '2035-01-01T08:30:00Z'),
          service: FakeQuizService(),
          draftStore: MemoryDraftStore(),
          now: () => DateTime.utc(2035, 1, 1, 8),
        ),
        textScale: 2,
        reduceMotion: reduceMotion,
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text(QuizContentData.timeLeft('30:00')), findsOneWidget);

      await tester.pumpWidget(host(
        QuizResultScreen(
          attemptId: 'attempt-1',
          initialResult: resultFrom(releasedJson),
          service: FakeQuizService(),
        ),
        textScale: 2,
        reduceMotion: reduceMotion,
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(host(
        QuizResultScreen(
          attemptId: 'attempt-1',
          initialResult: resultFrom(awaitingJson),
          service: FakeQuizService(),
        ),
        textScale: 2,
        reduceMotion: reduceMotion,
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  test('legacy closed quiz labels are unchanged', () {
    final closed = LearnerQuizSummary.fromJson({
      'assignment_id': 'a',
      'quiz_version_id': 'v',
      'quiz_id': 'q',
      'title': 'Closed',
      'class_id': 'c',
      'class_title': 'Class',
      'is_available': false,
      'closed_reason': 'deadline_passed',
    });
    expect(quizStatusLabel(closed), MissionContentData.quizClosedDeadline);
  });
}
