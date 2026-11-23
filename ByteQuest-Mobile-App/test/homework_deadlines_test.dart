import 'dart:async';
import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/homework_content_data.dart';
import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/models/homework_model.dart';
import 'package:bytequest/models/learner_quiz_model.dart';
import 'package:bytequest/screens/homework/homework_details_screen.dart';
import 'package:bytequest/screens/quizzes/quiz_taking_screen.dart';
import 'package:bytequest/services/homework_service.dart';
import 'package:bytequest/services/learner_quiz_service.dart';
import 'package:bytequest/services/learner_realtime_coordinator.dart';
import 'package:bytequest/widgets/assigned_class_activities.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

HomeworkAssignment homework(
        {bool late = false, HomeworkSubmission? submission}) =>
    HomeworkAssignment.fromJson(
        {
          'id': 'homework',
          'class_id': 'class',
          'title': 'Network inspection report',
          'instructions':
              'Inspect your home network outside ByteQuest and write a report.',
          'deadline_at': late ? '2026-11-11T00:00:00Z' : null,
        },
        classTitle: 'Sample Class A',
        serverNow: DateTime.utc(2026, 11, 13),
        submission: submission,
        files: []);

HomeworkSubmission submitted({String status = 'submitted', num late = 0}) =>
    HomeworkSubmission.fromJson({
      'id': 'submission',
      'answer': 'My network report.',
      'status': status,
      'submitted_at': '2026-11-13T00:00:00Z',
      'effective_deadline_at': '2026-11-11T00:00:00Z',
      'lateness_seconds': late,
      'feedback': status == 'graded' ? 'Inspection reviewed.' : null,
    });

class FakeHomework extends HomeworkService {
  HomeworkAssignment value = homework(late: true);
  final Completer<HomeworkSubmission> result = Completer<HomeworkSubmission>();
  int writes = 0;
  @override
  Future<List<HomeworkAssignment>> getAssignments(
          {String? id, String? classId}) async =>
      [value];
  @override
  Future<HomeworkSubmission> submit(
      {required String assignmentId,
      required String answer,
      required List<String> fileIds}) async {
    writes++;
    final saved = await result.future;
    value = homework(late: true, submission: saved);
    return saved;
  }
}

class FakeQuizzes extends LearnerQuizService {
  @override
  Future<List<LearnerQuizSummary>> getAvailableQuizzes() async => [
        LearnerQuizSummary.fromJson({
          'assignment_id': 'assignment',
          'quiz_version_id': 'version',
          'quiz_id': 'quiz',
          'title': 'Published networking quiz',
          'class_id': 'class',
          'class_title': 'Sample Class A',
          'is_available': true,
          'question_count': 3,
        })
      ];
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'sb_publishable_homework_test');
  });
  test('lateness formatter and explicit Manila display', () {
    expect(latenessDuration(1500), '25 minutes');
    expect(latenessDuration(11400), '3 hours, 10 minutes');
    expect(latenessDuration(100800), '1 day, 4 hours');
    expect(latenessDuration(195300), '2 days, 6 hours, 15 minutes');
    expect(latenessDuration(0.5), 'Less than 1 minute');
    expect(manilaDate(DateTime.utc(2026, 11, 13, 8, 30)), contains('4:30 PM'));
    expect(manilaDate(null), MissionContentData.homeworkNoDeadline);
  });
  test('homework lateness is separate from submitted/graded lifecycle', () {
    expect(homework(late: true).deadlinePassed, isTrue);
    expect(homework().deadlinePassed, isFalse);
    expect(homework().statusLabel, MissionContentData.homeworkAssigned);
    expect(homework(submission: submitted(late: 195300)).statusLabel,
        MissionContentData.homeworkSubmitted);
    expect(
        homework(submission: submitted(status: 'graded', late: 195300))
            .statusLabel,
        HomeworkContentData.statusReleased);
    expect(submitted(status: 'graded').score, isNull);
  });
  testWidgets(
      'Home/class panel exposes separate assigned quiz and homework sections',
      (tester) async {
    final service = FakeHomework();
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => LearnerRealtimeCoordinator(),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
            body: SingleChildScrollView(
                child: AssignedClassActivities(
                    quizService: FakeQuizzes(), homeworkService: service))),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Assigned Quizzes (1)'), findsOneWidget);
    expect(find.text('Homework Assignments (1)'), findsOneWidget);
    expect(find.text('Published networking quiz'), findsOneWidget);
    expect(find.text('Network inspection report'), findsOneWidget);
    expect(find.text(MissionContentData.quizStart), findsOneWidget);
    expect(find.text(MissionContentData.homeworkView), findsOneWidget);
    expect(find.textContaining('AI Generated'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'late homework confirms only persisted submission and prevents duplicate writes',
      (tester) async {
    final service = FakeHomework();
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: HomeworkDetailsScreen(
            assignment: service.value, service: service)));
    await tester.pumpAndSettle();
    expect(find.text(MissionContentData.homeworkLateAllowed), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(TextField), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.byType(TextField), 'My network report.');
    tester.testTextInput.hide();
    // Review submission enables once the submission meets the homework rule.
    await tester.pump();
    await tester.scrollUntilVisible(
        find.text(MissionContentData.homeworkReview), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text(MissionContentData.homeworkReview));
    await tester.pumpAndSettle();
    await tester.tap(find.text(MissionContentData.homeworkSubmit));
    await tester.pump();
    expect(service.writes, 1);
    expect(find.text(MissionContentData.homeworkSubmitted), findsNothing);
    service.result.complete(submitted(late: 195300));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text(MissionContentData.homeworkSubmitted), -200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(MissionContentData.homeworkSubmitted), findsOneWidget);
    expect(find.text('Late by 2 days, 6 hours, 15 minutes'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(service.writes, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'failed submission preserves answer and never claims Submitted for Grading',
      (tester) async {
    final service = FakeHomework();
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: HomeworkDetailsScreen(
            assignment: service.value, service: service)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(TextField), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(
        find.byType(TextField), 'Preserve this written report.');
    tester.testTextInput.hide();
    await tester.pump();
    await tester.scrollUntilVisible(
        find.text(MissionContentData.homeworkReview), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text(MissionContentData.homeworkReview));
    await tester.pumpAndSettle();
    await tester.tap(find.text(MissionContentData.homeworkSubmit));
    await tester.pump();
    service.result.completeError(StateError('QA persistence failure'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text(MissionContentData.homeworkFailed), -200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(MissionContentData.homeworkSubmitted), findsNothing);
    expect(find.text(MissionContentData.homeworkFailed), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Preserve this written report.');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'graded late homework shows feedback without submission controls at large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeHomework()
      ..value = homework(
          late: true, submission: submitted(status: 'graded', late: 195300));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: HomeworkDetailsScreen(
            assignment: service.value, service: service)));
    await tester.pumpAndSettle();
    expect(find.text(HomeworkContentData.statusReleased), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.scrollUntilVisible(find.text('Inspection reviewed.'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Inspection reviewed.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'quiz disables answering and submission at server-calibrated expiry',
      (tester) async {
    final attempt = LearnerQuizAttempt.fromJson({
      'attempt_id': 'attempt',
      'started_at': '2035-01-01T00:00:00Z',
      'server_now': '2035-01-01T00:00:00Z',
      'due_at': '2035-01-01T00:00:02Z',
      'quiz': {'assignment_id': 'assignment', 'title': 'Deadline quiz'},
      'questions': [
        {
          'id': 'item',
          'type': 'identification',
          'prompt': 'Name the routing device.'
        }
      ],
    });
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme, home: QuizTakingScreen(attempt: attempt)));
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text(MissionContentData.quizClosedDeadline), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
