import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/homework_requirements_content_data.dart';
import 'package:bytequest/models/homework_model.dart';
import 'package:bytequest/screens/homework/homework_details_screen.dart';
import 'package:bytequest/services/homework_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

HomeworkFile _file(String id, String name, String mime) => HomeworkFile.fromJson({
      'id': id,
      'filename': name,
      'kind': 'answer',
      'submission_id': null,
      'size_bytes': 2048,
      'mime_type': mime,
    });

HomeworkAssignment _assignment(Map<String, dynamic> rule,
        {List<HomeworkFile> files = const [], String id = 'hw-rule'}) =>
    HomeworkAssignment.fromJson({
      'id': id,
      'class_id': 'class',
      'title': 'Cable photo report',
      'instructions': 'Describe the termination and attach one photo.',
      'deadline_at': null,
      ...rule,
    },
        classTitle: 'Sample Class A',
        serverNow: DateTime.utc(2026, 11, 23),
        submission: null,
        files: files);

class _FakeHomework extends HomeworkService {
  _FakeHomework(this.row);
  HomeworkAssignment row;
  Object? refusal;
  final submitted = <({String answer, List<String> files})>[];

  @override
  Future<List<HomeworkAssignment>> getAssignments(
          {String? id, String? classId}) async =>
      [row];

  @override
  Future<HomeworkSubmission> submit(
      {required String assignmentId,
      required String answer,
      required List<String> fileIds}) async {
    if (refusal != null) throw refusal!;
    submitted.add((answer: answer, files: fileIds));
    throw StateError('stop after recording');
  }
}

Future<void> _pump(WidgetTester tester, _FakeHomework service) async {
  tester.view.physicalSize = const Size(412, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: HomeworkDetailsScreen(assignment: service.row, service: service)));
  await tester.pumpAndSettle();
}

bool _reviewEnabled(WidgetTester tester) => tester
    .widget<FilledButton>(find.byKey(const ValueKey('homework-review')))
    .enabled;

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'sb_publishable_homework_rules_test');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('rules are read from the assignment and older rows keep answer-or-file', () {
    final legacy = _assignment({}).rule;
    expect(legacy.format, 'answer_or_file');
    expect([legacy.takesAnswer, legacy.takesFiles, legacy.requiredFiles], [true, true, 0]);
    final both = _assignment({
      'submission_format': 'answer_and_file',
      'required_file_count': 1,
      'accepted_file_types': 'image'
    }).rule;
    expect([both.requiresAnswer, both.requiredFiles, both.imagesOnly], [true, 1, true]);
    expect(both.allowedExtensions, HomeworkSubmissionRule.imageExtensions);
    expect(both.description,
        'Submit a written answer and at least 1 image (JPG, PNG or WEBP).');
    final fileOnly = _assignment({'submission_format': 'file', 'required_file_count': 2}).rule;
    expect([fileOnly.takesAnswer, fileOnly.requiredFiles], [false, 2]);
    final answerOnly = _assignment(
        {'submission_format': 'answer', 'accepted_file_types': 'image'}).rule;
    expect([answerOnly.takesFiles, answerOnly.imagesOnly], [false, false]);
  });

  test('the first missing part of a submission is named', () {
    final image = _file('img', 'crimp.jpg', 'image/jpeg');
    final pdf = _file('pdf', 'notes.pdf', 'application/pdf');
    const both = HomeworkSubmissionRule(
        format: 'answer_and_file', requiredFiles: 1, imagesOnly: true);
    expect(both.missing('', [image]), HomeworkRequirementsContent.missingAnswer);
    expect(both.missing('Done', []),
        HomeworkRequirementsContent.missingFiles(1, true));
    expect(both.missing('Done', [pdf]), HomeworkRequirementsContent.notImage);
    expect(both.missing('Done', [image]), isNull);
    const fileOnly = HomeworkSubmissionRule(format: 'file', requiredFiles: 2);
    expect(fileOnly.missing('typed text', [pdf]),
        HomeworkRequirementsContent.missingFiles(1, false));
    expect(fileOnly.missing('', [pdf, image]), isNull);
    const answerOnly = HomeworkSubmissionRule(format: 'answer');
    expect(answerOnly.missing(' ', []), HomeworkRequirementsContent.missingAnswer);
    expect(answerOnly.missing('Reflection', [pdf]), isNull,
        reason: 'files are ignored and never sent for answer-only homework');
    const legacy = HomeworkSubmissionRule();
    expect(legacy.missing('', []), HomeworkRequirementsContent.missingAnswerOrFile);
    expect(legacy.missing('', [pdf]), isNull);
  });

  testWidgets('answer and image: Review stays off until both are present',
      (tester) async {
    final service = _FakeHomework(_assignment({
      'submission_format': 'answer_and_file',
      'required_file_count': 1,
      'accepted_file_types': 'image'
    }));
    await _pump(tester, service);
    expect(find.text('Submit a written answer and at least 1 image (JPG, PNG or WEBP).'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('homework-answer-field')), findsOneWidget);
    expect(find.text(HomeworkRequirementsContent.addImage), findsOneWidget);
    expect(find.text(HomeworkRequirementsContent.imagesHelp), findsOneWidget);
    expect(_reviewEnabled(tester), isFalse);
    expect(find.text(HomeworkRequirementsContent.missingAnswer), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('homework-answer-field')), 'Crimped to T568B.');
    await tester.pump();
    expect(_reviewEnabled(tester), isFalse,
        reason: 'a written answer alone must not submit');
    expect(find.text(HomeworkRequirementsContent.missingFiles(1, true)),
        findsOneWidget);

    // An image already uploaded for this homework counts once selected.
    service.row = _assignment({
      'submission_format': 'answer_and_file',
      'required_file_count': 1,
      'accepted_file_types': 'image'
    }, files: [
      _file('img', 'crimp.jpg', 'image/jpeg')
    ], id: 'hw-rule-uploaded');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: HomeworkDetailsScreen(assignment: service.row, service: service)));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('homework-answer-field')), 'Crimped to T568B.');
    await tester.pump();
    expect(find.byKey(const ValueKey('homework-missing')), findsNothing);
    expect(_reviewEnabled(tester), isTrue);
  });

  testWidgets('file only hides the written answer and sends files alone',
      (tester) async {
    final service = _FakeHomework(_assignment({'submission_format': 'file'},
        files: [_file('report', 'report.pdf', 'application/pdf')], id: 'hw-file'));
    await _pump(tester, service);
    expect(find.byKey(const ValueKey('homework-answer-field')), findsNothing);
    expect(find.byKey(const ValueKey('homework-attach')), findsOneWidget);
    expect(_reviewEnabled(tester), isTrue);
    await tester.tap(find.byKey(const ValueKey('homework-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit Assignment'));
    await tester.pumpAndSettle();
    expect(service.submitted.single.answer, '');
    expect(service.submitted.single.files, ['report']);
  });

  testWidgets('written answer only hides file attachment', (tester) async {
    final service =
        _FakeHomework(_assignment({'submission_format': 'answer'}, id: 'hw-answer'));
    await _pump(tester, service);
    expect(find.byKey(const ValueKey('homework-attach')), findsNothing);
    expect(find.byKey(const ValueKey('homework-answer-field')), findsOneWidget);
    expect(find.text(HomeworkRequirementsContent.rule('answer', 0, false)),
        findsOneWidget);
  });

  testWidgets('a server refusal shows its specific reason', (tester) async {
    final service =
        _FakeHomework(_assignment({'submission_format': 'answer'}, id: 'hw-refusal'))
      ..refusal = const HomeworkRuleException(
          'This homework requires a written answer.');
    await _pump(tester, service);
    await tester.enterText(
        find.byKey(const ValueKey('homework-answer-field')), 'Reflection');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('homework-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit Assignment'));
    await tester.pumpAndSettle();
    expect(find.text('This homework requires a written answer.'), findsOneWidget);
  });
}
