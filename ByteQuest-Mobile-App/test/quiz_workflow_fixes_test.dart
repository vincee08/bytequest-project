import 'package:bytequest/data/quiz_content_data.dart';
import 'package:bytequest/models/learner_quiz_model.dart';
import 'package:bytequest/screens/quizzes/quiz_taking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'quiz_redefense_flow_test.dart'
    show FakeQuizService, MemoryDraftStore, host, usePhone;

LearnerQuizAttempt attemptWith({String? instructions, bool essay = true}) =>
    LearnerQuizAttempt.fromJson({
      'attempt_id': 'attempt-9',
      'status': 'in_progress',
      'started_at': '2035-01-01T08:00:00Z',
      'server_now': '2035-01-01T08:00:00Z',
      'due_at': '2035-01-01T09:00:00Z',
      'expires_at': '2035-01-01T09:00:00Z',
      'quiz': {
        'assignment_id': 'assignment-9',
        'title': 'Cable termination check',
        'class_title': 'CSS NC II',
        'version_number': 1,
        'instructions': instructions,
      },
      'questions': [
        essay
            ? {
                'id': 'essay-9',
                'type': 'scenario_essay',
                'prompt': 'Explain how you would terminate and test the cable.',
                'options': const [],
                'order_index': 1,
                'points': 6,
                'scenario': 'A client needs a new patch cable for a workstation.',
                'max_answer_length': 10000,
                'rubric': [
                  {'id': 'C1', 'criterion': 'Procedure', 'max_points': 6},
                ],
              }
            : {
                'id': 'mc-9',
                'type': 'multiple_choice',
                'prompt': 'Which tool attaches the RJ45 plug to the cable?',
                'options': ['Crimping tool', 'Punch-down tool'],
                'order_index': 1,
                'max_answer_length': 2000,
              },
      ],
    });

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'sb_publishable_quiz_workflow_test',
    );
  });

  Future<void> open(WidgetTester tester, LearnerQuizAttempt attempt) async {
    usePhone(tester);
    await tester.pumpWidget(host(QuizTakingScreen(
      attempt: attempt,
      service: FakeQuizService(),
      draftStore: MemoryDraftStore(),
      now: () => DateTime.utc(2035, 1, 1, 8),
    )));
    await tester.pump();
  }

  testWidgets('the instructor\'s instructions stay readable during the attempt',
      (tester) async {
    await open(
        tester,
        attemptWith(
            instructions: 'Type every answer in English. No files are needed.',
            essay: false));
    final button = find.byKey(const ValueKey('quiz-instructions-button'));
    expect(button, findsOneWidget);
    expect(tester.getSize(button).shortestSide, greaterThanOrEqualTo(48));
    expect(find.byTooltip(QuizContentData.viewInstructions), findsOneWidget);
    expect(find.text('Type every answer in English. No files are needed.'),
        findsNothing);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quiz-instructions-sheet')),
        findsOneWidget);
    expect(find.text('Type every answer in English. No files are needed.'),
        findsOneWidget);
  });

  testWidgets('no instructions button when the instructor gave none',
      (tester) async {
    await open(tester, attemptWith(instructions: '   ', essay: false));
    expect(find.byKey(const ValueKey('quiz-instructions-button')),
        findsNothing);
  });

  testWidgets('an essay tells the learner that quiz answers are typed only',
      (tester) async {
    await open(tester, attemptWith());
    expect(find.byKey(const ValueKey('quiz-essay-typed-only')), findsOneWidget);
    expect(find.text(QuizContentData.essayTypedOnly), findsOneWidget);
  });
}
