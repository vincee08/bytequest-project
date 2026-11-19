import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/homework_content_data.dart';
import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/models/homework_model.dart';
import 'package:bytequest/screens/homework/homework_details_screen.dart';
import 'package:bytequest/screens/homework/homework_list_screen.dart';
import 'package:bytequest/models/learner_quiz_model.dart';
import 'package:bytequest/services/homework_service.dart';
import 'package:bytequest/services/learner_quiz_service.dart';
import 'package:bytequest/services/learner_realtime_coordinator.dart';
import 'package:bytequest/widgets/assigned_class_activities.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _NoQuizzes extends LearnerQuizService {
  @override
  Future<List<LearnerQuizSummary>> getAvailableQuizzes() async => [];
}

Map<String, dynamic> _assignmentJson(
        {String id = 'hw-assembly',
        String title = 'Assembly safety report',
        String? coc = 'coc1',
        String? mission = 'coc1_m2',
        String? missionTitle = 'Install Internal Components',
        bool criteria = true}) =>
    {
      'id': id,
      'class_id': 'class',
      'title': title,
      'instructions': 'Document the assembly safety checks you performed.',
      'deadline_at': null,
      'coc_code': coc,
      'coc_title':
          coc == null ? null : 'Install and Configure Computer Systems',
      'mission_code': mission,
      'mission_title': mission == null ? null : missionTitle,
      'module_code': coc == null ? null : 'LO1.1',
      'module_title': coc == null ? null : 'Assemble computer hardware',
      'learning_objectives': criteria
          ? ['Apply ESD precautions', 'Follow the assembly order']
          : [],
      'criteria': criteria
          ? [
              {
                'id': 'safety',
                'criterion': 'Safety checks',
                'description': 'Power isolation and ESD strap',
                'max_points': 30
              },
              {'id': 'order', 'criterion': 'Assembly order', 'max_points': 20},
            ]
          : [],
      'max_score': criteria ? 50 : 100,
      'submission_requirements': criteria ? 'PDF report with photos' : null,
    };

HomeworkAssignment _assignment(
        {HomeworkSubmission? submission,
        String id = 'hw-assembly',
        String title = 'Assembly safety report',
        String? coc = 'coc1',
        String? mission = 'coc1_m2',
        String? missionTitle = 'Install Internal Components',
        bool criteria = true}) =>
    HomeworkAssignment.fromJson(
        _assignmentJson(
            id: id,
            title: title,
            coc: coc,
            mission: mission,
            missionTitle: missionTitle,
            criteria: criteria),
        classTitle: 'Sample Class A',
        serverNow: DateTime.utc(2026, 11, 19),
        submission: submission,
        files: const []);

HomeworkSubmission _submission(String evaluationStatus) =>
    HomeworkSubmission.fromJson({
      'id': 'submission',
      'answer': 'My assembly safety report.',
      'status': evaluationStatus == 'released' ? 'graded' : 'submitted',
      'evaluation_status': evaluationStatus,
      'submitted_at': '2026-11-19T01:00:00Z',
      'effective_deadline_at': null,
      'lateness_seconds': 0,
      // A defensive client ignores grade fields that arrive before release.
      'feedback': 'Clear safety checks.',
      'score': 40,
      'criterion_scores': {'safety': 25, 'order': 15},
    });

class _FakeHomework extends HomeworkService {
  _FakeHomework(this.rows);
  List<HomeworkAssignment> rows;
  bool fail = false;
  int loads = 0;
  @override
  Future<List<HomeworkAssignment>> getAssignments(
      {String? id, String? classId}) async {
    loads++;
    if (fail) throw StateError('HOMEWORK_REQUEST_FAILED');
    return id == null ? rows : rows.where((row) => row.id == id).toList();
  }
}

Future<void> _pumpLarge(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!),
      home: home));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'sb_publishable_homework_redefense_test');
  });

  test('a grade is read only after release', () {
    for (final status in ['graded', 'finalized']) {
      final evaluating = _submission(status);
      expect(evaluating.isBeingEvaluated, isTrue);
      expect(evaluating.isReleased, isFalse);
      expect(evaluating.score, isNull);
      expect(evaluating.feedback, isNull);
      expect(evaluating.criterionScores, isEmpty);
      expect(evaluating.status, 'submitted');
      expect(evaluating.statusLabel, HomeworkContentData.statusBeingEvaluated);
    }
    final released = _submission('released');
    expect(released.isReleased, isTrue);
    expect(released.score, 40);
    expect(released.feedback, 'Clear safety checks.');
    expect(released.criterionScores, {'safety': 25, 'order': 15});
    expect(released.status, 'graded');
    expect(released.statusLabel, HomeworkContentData.statusReleased);
    expect(_submission('submitted').statusLabel,
        MissionContentData.homeworkSubmitted);
  });

  test('responses from the previous API keep their meaning', () {
    final legacyGraded = HomeworkSubmission.fromJson({
      'id': 'legacy',
      'status': 'graded',
      'submitted_at': '2026-11-13T00:00:00Z',
      'feedback': 'Reviewed.',
      'score': 90,
    });
    expect(legacyGraded.isReleased, isTrue);
    expect(legacyGraded.score, 90);
    final legacySubmitted = HomeworkSubmission.fromJson({
      'id': 'legacy-submitted',
      'status': 'submitted',
      'submitted_at': '2026-11-13T00:00:00Z',
    });
    expect(legacySubmitted.evaluationStatus, 'submitted');
    final unlinked = HomeworkAssignment.fromJson(
        {
          'id': 'old',
          'class_id': 'class',
          'title': 'Network report',
          'instructions': 'Write it.',
        },
        classTitle: 'Sample Class A',
        serverNow: DateTime.utc(2026, 11, 19),
        submission: null,
        files: const []);
    expect(unlinked.maxScore, 100);
    expect(unlinked.criteria, isEmpty);
    expect(unlinked.learningObjectives, isEmpty);
    expect(unlinked.cocCode, isNull);
    expect(unlinked.competencyLine, HomeworkContentData.generalHomework);
  });

  test('assignments carry COC, mission, module, objectives and criteria', () {
    final h = _assignment();
    expect(h.cocCode, 'coc1');
    expect(h.missionCode, 'coc1_m2');
    expect(h.moduleCode, 'LO1.1');
    expect(h.learningObjectives, hasLength(2));
    expect(h.criteria.map((c) => c.maxPoints), [30, 20]);
    expect(h.maxScore, 50);
    expect(h.competencyLine, contains('COC 1 · Install and Configure'));
    expect(h.competencyLine, contains('M2 · Install Internal Components'));
    expect(h.competencyLine, contains('LO1.1 Assemble computer hardware'));
  });

  testWidgets(
      'details show competency, objectives, criteria and maximum score before submission',
      (tester) async {
    final service = _FakeHomework([_assignment()]);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: HomeworkDetailsScreen(
            assignment: service.rows.first, service: service)));
    await tester.pumpAndSettle();
    expect(find.text(HomeworkContentData.maxScore(50)), findsOneWidget);
    expect(
        find.textContaining('COC 1 · Install and Configure'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Follow the assembly order'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Apply ESD precautions'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Assembly order'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Safety checks'), findsOneWidget);
    expect(find.text(HomeworkContentData.points(30)), findsOneWidget);
    expect(
        find.bySemanticsLabel(
            HomeworkContentData.criterionSemantics('Assembly order', 20)),
        findsOneWidget);
    await tester.scrollUntilVisible(find.text('PDF report with photos'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('PDF report with photos'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an in-evaluation submission shows no score or feedback',
      (tester) async {
    final service =
        _FakeHomework([_assignment(submission: _submission('finalized'))]);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: HomeworkDetailsScreen(
            assignment: service.rows.first, service: service)));
    await tester.pumpAndSettle();
    expect(find.text(HomeworkContentData.statusBeingEvaluated), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text(HomeworkContentData.beingEvaluatedHelp), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(HomeworkContentData.beingEvaluatedHelp), findsOneWidget);
    expect(find.textContaining('Score:'), findsNothing);
    expect(find.text('Clear safety checks.'), findsNothing);
    expect(find.text(HomeworkContentData.resultTitle), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a released result shows the score out of the maximum, criteria and feedback at large text',
      (tester) async {
    final service =
        _FakeHomework([_assignment(submission: _submission('released'))]);
    await _pumpLarge(
        tester,
        HomeworkDetailsScreen(
            assignment: service.rows.first, service: service));
    expect(find.text(HomeworkContentData.statusReleased), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text(HomeworkContentData.score(40, 50)), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(HomeworkContentData.score(40, 50)), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text(HomeworkContentData.criterionScore(25, 30)), 200,
        scrollable: find.byType(Scrollable).first);
    expect(
        find.text(HomeworkContentData.criterionScore(15, 20)), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Clear safety checks.'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Clear safety checks.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('homework list filters by COC, then mission', (tester) async {
    final service = _FakeHomework([
      _assignment(),
      _assignment(
          id: 'hw-drivers',
          title: 'Driver test log',
          mission: 'coc1_m5',
          missionTitle: 'Install Drivers and Test the System'),
      _assignment(
          id: 'hw-cables',
          title: 'Cable crimping log',
          coc: 'coc2',
          mission: 'coc2_m2',
          missionTitle: 'Create Network Cables'),
      _assignment(
          id: 'hw-general',
          title: 'Study plan',
          coc: null,
          mission: null,
          criteria: false),
    ]);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: HomeworkListScreen(service: service)));
    await tester.pumpAndSettle();
    for (final title in [
      'Assembly safety report',
      'Driver test log',
      'Cable crimping log',
      'Study plan'
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.widgetWithText(ChoiceChip, HomeworkContentData.allCocs),
        findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'COC 2'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, HomeworkContentData.notLinked),
        findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, HomeworkContentData.allMissions),
        findsNothing);
    expect(tester.getSize(find.widgetWithText(ChoiceChip, 'COC 1')).height,
        greaterThanOrEqualTo(48));

    await tester.tap(find.widgetWithText(ChoiceChip, 'COC 1'));
    await tester.pumpAndSettle();
    expect(find.text('Assembly safety report'), findsOneWidget);
    expect(find.text('Driver test log'), findsOneWidget);
    expect(find.text('Cable crimping log'), findsNothing);
    expect(find.text('Study plan'), findsNothing);
    expect(find.text(HomeworkContentData.count(2, 4)), findsOneWidget);

    await tester.tap(find.widgetWithText(
        ChoiceChip, 'M5 · Install Drivers and Test the System'));
    await tester.pumpAndSettle();
    expect(find.text('Driver test log'), findsOneWidget);
    expect(find.text('Assembly safety report'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'COC 2'));
    await tester.pumpAndSettle();
    expect(find.text('Cable crimping log'), findsOneWidget);
    expect(find.text('Driver test log'), findsNothing);

    await tester
        .tap(find.widgetWithText(ChoiceChip, HomeworkContentData.notLinked));
    await tester.pumpAndSettle();
    expect(find.text('Study plan'), findsOneWidget);
    expect(find.text('Cable crimping log'), findsNothing);

    await tester
        .tap(find.widgetWithText(ChoiceChip, HomeworkContentData.allCocs));
    await tester.pumpAndSettle();
    expect(find.text(HomeworkContentData.count(4, 4)), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the homework section opens the COC and mission view',
      (tester) async {
    final service = _FakeHomework([_assignment()]);
    await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => LearnerRealtimeCoordinator(),
        child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
                body: SingleChildScrollView(
                    child: AssignedClassActivities(
                        quizService: _NoQuizzes(),
                        homeworkService: service))))));
    await tester.pumpAndSettle();
    expect(find.text('Homework Assignments (1)'), findsOneWidget);
    final entry = find.text(HomeworkContentData.listAction);
    expect(
        tester
            .getSize(
                find.ancestor(of: entry, matching: find.byType(TextButton)))
            .height,
        greaterThanOrEqualTo(48));
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(HomeworkListScreen), findsOneWidget);
    expect(find.text('Assembly safety report'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'homework list stays usable at large text and recovers from errors',
      (tester) async {
    final service = _FakeHomework([
      _assignment(submission: _submission('graded')),
      _assignment(
          id: 'hw-cables',
          title: 'Cable crimping log',
          coc: 'coc2',
          mission: 'coc2_m2',
          missionTitle: 'Create Network Cables')
    ])
      ..fail = true;
    await _pumpLarge(tester, HomeworkListScreen(service: service));
    expect(find.text(HomeworkContentData.listUnavailable), findsOneWidget);
    service.fail = false;
    await tester.ensureVisible(find.text(HomeworkContentData.retry));
    await tester.pumpAndSettle();
    await tester.tap(find.text(HomeworkContentData.retry));
    await tester.pumpAndSettle();
    expect(find.text('Assembly safety report'), findsOneWidget);
    expect(find.text(HomeworkContentData.statusBeingEvaluated), findsOneWidget);
    expect(find.textContaining('Score:'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'COC 2'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Cable crimping log'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Cable crimping log'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
