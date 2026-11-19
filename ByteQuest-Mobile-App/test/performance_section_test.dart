import 'dart:async';

import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/learning_content_data.dart';
import 'package:bytequest/data/performance_content_data.dart';
import 'package:bytequest/models/performance_model.dart';
import 'package:bytequest/screens/progress/performance_section.dart';
import 'package:bytequest/screens/progress/performance_widgets.dart';
import 'package:bytequest/screens/progress/progress_screen.dart';
import 'package:bytequest/services/performance_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Slice A2's Progress screen fixtures (curriculum projection, sources, host).
import 'learn_practice_progress_test.dart' as a2;

/// Shape returned by get_my_performance(), modelled on learner L1 of
/// supabase/tests/analytics_redefense_rollback.sql (criterion B is not
/// achieved here so both outcome labels are covered).
Map<String, dynamic> populatedJson({double overall = 12.5, String updatedAt = '2026-11-19T07:05:00Z'}) => {
      'progress': {
        'overall_percent': overall,
        'completed_items': 3,
        'total_items': 24,
        'cocs': [
          {'coc_code': 'coc1', 'title': 'Install and Configure Computer Systems', 'percent': 50.0, 'completed_items': 3, 'total_items': 6, 'modules_completed': 1, 'modules_total': 4},
          {'coc_code': 'coc2', 'title': 'Set-up Computer Networks', 'percent': 0, 'completed_items': 0, 'total_items': 6, 'modules_completed': 0, 'modules_total': 4},
        ],
      },
      'competency': [
        {'criterion': 'Wears the ESD wrist strap', 'code': 'A7-CRIT-A', 'mission_code': 'coc1_m2', 'mission_title': 'Install Internal Components', 'outcome': 'satisfied', 'released_at': '2026-11-16T07:00:00Z'},
        {'criterion': 'Seats the CPU in the correct orientation', 'code': 'A7-CRIT-B', 'mission_code': 'coc1_m2', 'mission_title': 'Install Internal Components', 'outcome': 'not_satisfied', 'released_at': '2026-11-16T07:00:00Z'},
      ],
      'scores': {
        'quizzes': [
          {'attempt_id': 'q1', 'percent': 100.0, 'correct_count': 2, 'question_count': 2, 'score': null, 'max_score': null, 'released': false, 'submitted_at': '2026-11-17T07:00:00Z'},
          {'attempt_id': 'q4', 'percent': 88.9, 'correct_count': 1, 'question_count': 2, 'score': 8, 'max_score': 9, 'released': true, 'submitted_at': '2026-10-05T07:00:00Z'},
        ],
        'homework': [
          {'title': 'Workstation report', 'score': 40, 'max_score': 50, 'percent': 80.0, 'released': true, 'submitted_at': '2026-11-16T07:00:00Z', 'late': false},
          {'title': 'Cable checklist', 'score': null, 'max_score': 100, 'percent': null, 'released': false, 'submitted_at': '2026-11-18T07:00:00Z', 'late': true},
        ],
      },
      'assessments': [
        {'attempt_id': 'a2', 'mission': 'coc1_m2', 'title': 'Install Internal Components', 'assignment_title': 'Assessment A', 'percent': 100.0, 'outcome': 'competent', 'released_at': '2026-11-16T07:00:00Z'},
        {'attempt_id': 'a1', 'mission': 'coc1_m2', 'title': 'Install Internal Components', 'assignment_title': 'Assessment A', 'percent': 50.0, 'outcome': 'not_yet_competent', 'released_at': '2026-11-14T07:00:00Z'},
      ],
      'practice': {
        'missions_verified': 3,
        'runs': 4,
        'best_times': [
          {'mission_code': 'coc1_m1', 'title': 'Identify Computer Parts and Tools', 'best_seconds': 120},
        ],
      },
      'summary': {
        'quiz_avg': 94.5,
        'homework_avg': 80.0,
        'homework_released': 1,
        'assessments_released': 2,
        'assessments_competent': 1,
        'criteria_total': 2,
        'criteria_achieved': 1,
      },
      'updated_at': updatedAt,
    };

Map<String, dynamic> emptyJson() => {
      'progress': {
        'overall_percent': 0,
        'completed_items': 0,
        'total_items': 24,
        'cocs': [
          {'coc_code': 'coc1', 'title': 'Install and Configure Computer Systems', 'percent': 0, 'completed_items': 0, 'total_items': 6, 'modules_completed': 0, 'modules_total': 4},
        ],
      },
      'competency': [],
      'scores': {'quizzes': [], 'homework': []},
      'assessments': [],
      'practice': {'missions_verified': 0, 'runs': 0, 'best_times': []},
      'summary': {
        'quiz_avg': null,
        'homework_avg': null,
        'homework_released': 0,
        'assessments_released': 0,
        'assessments_competent': 0,
        'criteria_total': 0,
        'criteria_achieved': 0,
      },
      'updated_at': '2026-11-19T07:05:00Z',
    };

class FakePerformanceService extends PerformanceService {
  FakePerformanceService(this.responses);

  /// Each fetch returns the next entry (the last one repeats). An Exception
  /// entry is thrown instead.
  final List<Object> responses;
  final changes = StreamController<void>.broadcast();
  int fetches = 0;
  int titleFetches = 0;
  Completer<void>? gate;

  /// Titles from the learner's quiz list; an Exception is thrown instead.
  Object quizTitles = const {'q1': 'Hardware Basics Quiz', 'q4': 'Diagnosis Essay Quiz'};

  @override
  Future<Map<String, String>> fetchQuizTitles() async {
    titleFetches++;
    final titles = quizTitles;
    if (titles is Exception) throw titles;
    return titles as Map<String, String>;
  }

  @override
  Future<PerformanceSnapshot> fetchMyPerformance() async {
    final response = responses[fetches < responses.length ? fetches : responses.length - 1];
    fetches++;
    await gate?.future;
    if (response is Exception) throw response;
    return PerformanceSnapshot.fromJson(response as Map<String, dynamic>);
  }

  @override
  Stream<void> watchChanges() => changes.stream;
}

Widget host(Widget child, {double textScale = 1}) => MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: app!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

String clock(String iso) => DateFormat('HH:mm').format(DateTime.parse(iso).toLocal());

/// Accessible label of one compact summary tile.
Finder summaryTile(String label, String value, String detail) =>
    find.bySemanticsLabel(PerformanceContentData.summarySemantics(label, value, detail));

void main() {
  testWidgets('shows a loading state, then the empty state with its update time', (tester) async {
    final service = FakePerformanceService([emptyJson()])..gate = Completer<void>();
    await tester.pumpWidget(host(PerformanceSection(service: service)));
    expect(find.bySemanticsLabel(PerformanceContentData.loadingLabel), findsOneWidget);
    service.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text(PerformanceContentData.emptyTitle), findsOneWidget);
    expect(find.text(PerformanceContentData.updatedAt(clock('2026-11-19T07:05:00Z'))), findsOneWidget);
    expect(find.text(PerformanceContentData.competencyTitle), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('populated: progress, competency, scores, released results and practice', (tester) async {
    final service = FakePerformanceService([populatedJson()]);
    await tester.pumpWidget(host(PerformanceSection(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('12.5%'), findsOneWidget);
    expect(find.text('COC1'), findsOneWidget);
    expect(find.text(PerformanceContentData.modulesCompleted(1, 4)), findsOneWidget);
    expect(find.text('Wears the ESD wrist strap'), findsOneWidget);
    expect(find.text(PerformanceContentData.achievedLabel), findsOneWidget);
    expect(find.text(PerformanceContentData.notYetAchievedLabel), findsOneWidget);
    expect(find.text(PerformanceContentData.competencySummary(1, 2)), findsOneWidget);
    expect(find.text('Hardware Basics Quiz'), findsOneWidget, reason: 'titles come from the learner quiz list in one call');
    expect(find.text('Diagnosis Essay Quiz'), findsOneWidget);
    expect(service.titleFetches, 1);
    expect(find.text(PerformanceContentData.quizPoints('8', '9', released: true)), findsOneWidget,
        reason: 'a released essay quiz shows its finalized points');
    expect(find.text(PerformanceContentData.quizScore(2, 2)), findsOneWidget,
        reason: 'a result recorded before points reports answers');
    expect(find.text(PerformanceContentData.homeworkScore('40', '50')), findsOneWidget,
        reason: 'homework is scored against its own maximum');
    expect(find.text(PerformanceContentData.homeworkDetail(80, late: false)!), findsOneWidget);
    expect(find.text(PerformanceContentData.homeworkAwaiting), findsOneWidget, reason: 'an unreleased homework score is never shown');
    expect(find.text(PerformanceContentData.homeworkLate), findsOneWidget);
    expect(find.text(PerformanceContentData.competentLabel), findsOneWidget);
    expect(find.text(PerformanceContentData.notYetCompetentLabel), findsOneWidget);
    expect(find.text('2m 00s'), findsOneWidget);
    expect(find.textContaining('Wrong'), findsNothing);
    expect(find.textContaining('Correct'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('refreshes on realtime changes and every 30 seconds while visible', (tester) async {
    final service = FakePerformanceService([
      populatedJson(),
      populatedJson(overall: 20.8, updatedAt: '2026-11-19T07:06:00Z'),
      populatedJson(overall: 25.0, updatedAt: '2026-11-19T07:07:00Z'),
    ]);
    await tester.pumpWidget(host(PerformanceSection(service: service)));
    await tester.pumpAndSettle();
    expect(service.fetches, 1);
    expect(find.text('12.5%'), findsOneWidget);

    service.changes.add(null);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(service.fetches, 2, reason: 'a realtime change triggers a refetch');
    expect(find.text('20.8%'), findsOneWidget);
    expect(find.text(PerformanceContentData.updatedAt(clock('2026-11-19T07:06:00Z'))), findsOneWidget);

    await tester.pump(PerformanceSection.pollInterval);
    await tester.pumpAndSettle();
    expect(service.fetches, 3, reason: 'polling fallback refetches every 30 seconds');
    expect(find.text('25%'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('polling pauses while the app is in the background', (tester) async {
    final service = FakePerformanceService([populatedJson()]);
    await tester.pumpWidget(host(PerformanceSection(service: service)));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(PerformanceSection.pollInterval * 2);
    service.changes.add(null);
    await tester.pump(const Duration(seconds: 1));
    expect(service.fetches, 1, reason: 'no polling or realtime refetch in the background');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(service.fetches, 2, reason: 'returning to the app refreshes once');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a hidden section defers realtime changes until it is shown again', (tester) async {
    final service = FakePerformanceService([
      populatedJson(),
      populatedJson(overall: 20.8, updatedAt: '2026-11-19T07:06:00Z'),
    ]);
    // The learner navigation shell disables tickers on tabs that are not selected.
    Widget tab({required bool selected}) =>
        host(TickerMode(enabled: selected, child: PerformanceSection(service: service)));
    await tester.pumpWidget(tab(selected: true));
    await tester.pumpAndSettle();
    expect(service.fetches, 1);

    await tester.pumpWidget(tab(selected: false));
    service.changes
      ..add(null)
      ..add(null);
    await tester.pump(const Duration(seconds: 1));
    expect(service.fetches, 1, reason: 'no refetch while another tab is selected');

    await tester.pumpWidget(tab(selected: true));
    await tester.pumpAndSettle();
    expect(service.fetches, 2, reason: 'one refetch for the changes missed while hidden');
    expect(find.text('20.8%'), findsOneWidget);

    await tester.pumpWidget(tab(selected: false));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(tab(selected: true));
    await tester.pumpAndSettle();
    expect(service.fetches, 2, reason: 'a quick tab switch without changes does not refetch');

    await tester.pumpWidget(tab(selected: false));
    await tester.pump(PerformanceSection.pollInterval * 3);
    expect(service.fetches, 2, reason: 'polling stops while hidden');
    await tester.pumpWidget(tab(selected: true));
    await tester.pumpAndSettle();
    expect(service.fetches, 3, reason: 'hidden for longer than a poll interval: refreshed when shown');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('quiz titles that cannot be read leave the fallback label, not an error', (tester) async {
    final service = FakePerformanceService([populatedJson()])..quizTitles = Exception('offline');
    await tester.pumpWidget(host(PerformanceSection(service: service)));
    await tester.pumpAndSettle();
    expect(find.text(PerformanceContentData.errorTitle), findsNothing);
    expect(find.text(PerformanceContentData.quizFallback), findsNWidgets(2));
    expect(find.text(PerformanceContentData.quizScore(2, 2)), findsOneWidget, reason: 'scores still show');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an error offers a retry that reloads the section', (tester) async {
    final service = FakePerformanceService([Exception('offline'), populatedJson()]);
    await tester.pumpWidget(host(PerformanceSection(service: service)));
    await tester.pumpAndSettle();
    expect(find.text(PerformanceContentData.errorTitle), findsOneWidget);
    await tester.tap(find.text(PerformanceContentData.retryLabel));
    await tester.pumpAndSettle();
    expect(find.text('12.5%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed refresh keeps the last loaded results visible', (tester) async {
    final service = FakePerformanceService([populatedJson(), Exception('offline')]);
    await tester.pumpWidget(host(PerformanceSection(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(PerformanceContentData.refreshLabel));
    await tester.pumpAndSettle();
    expect(find.text('12.5%'), findsOneWidget);
    expect(find.text(PerformanceContentData.staleNotice), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('large text on a narrow phone does not overflow and keeps 48dp targets', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final compact in [false, true]) {
      final service = FakePerformanceService([populatedJson()]);
      await tester.pumpWidget(host(PerformanceSection(service: service, compact: compact), textScale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final refresh = find.bySemanticsLabel(PerformanceContentData.refreshLabel);
      expect(refresh, findsOneWidget);
      final size = tester.getSize(refresh);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('reduced motion still renders progress without animation', (tester) async {
    final service = FakePerformanceService([populatedJson()]);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, app) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: app!),
      home: Scaffold(body: SingleChildScrollView(child: PerformanceSection(service: service))),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('12.5%'), findsOneWidget);
    final indicator = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator).first);
    expect(indicator.value, closeTo(0.125, 0.0001));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('compact: server averages and criterion outcomes, without repeating the Progress lists', (tester) async {
    final service = FakePerformanceService([populatedJson()]);
    await tester.pumpWidget(host(PerformanceSection(service: service, compact: true)));
    await tester.pumpAndSettle();
    expect(find.text(PerformanceContentData.sectionTitle), findsNothing, reason: 'the Progress screen supplies the header');
    expect(summaryTile(PerformanceContentData.summaryCriteriaLabel, PerformanceContentData.ofTotal(1, 2), PerformanceContentData.summaryCriteriaDetail), findsOneWidget);
    expect(summaryTile(PerformanceContentData.summaryQuizLabel, '94.5%', PerformanceContentData.quizCount(2)), findsOneWidget);
    expect(service.titleFetches, 0, reason: 'the compact section lists no quiz titles, so it never reads them');
    expect(summaryTile(PerformanceContentData.summaryHomeworkLabel, '80%', PerformanceContentData.releasedGrades(1)), findsOneWidget,
        reason: 'the released homework average is a share of each maximum score');
    expect(summaryTile(PerformanceContentData.summaryAssessmentsLabel, PerformanceContentData.ofTotal(1, 2), PerformanceContentData.summaryAssessmentsDetail), findsOneWidget);
    expect(find.text('Seats the CPU in the correct orientation'), findsOneWidget);
    expect(find.text(PerformanceContentData.notYetAchievedLabel), findsOneWidget);
    expect(find.text(PerformanceContentData.updatedAt(clock('2026-11-19T07:05:00Z'))), findsOneWidget);
    for (final duplicate in [PerformanceProgressCard, PerformanceScoresCard, PerformanceAssessmentsCard, PerformancePracticeCard]) {
      expect(find.byType(duplicate), findsNothing, reason: '$duplicate is already covered by the Progress screen');
    }
    expect(find.text(PerformanceContentData.compactEmpty), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('compact: no scored work shows dashes, never zero averages', (tester) async {
    final service = FakePerformanceService([emptyJson()]);
    await tester.pumpWidget(host(PerformanceSection(service: service, compact: true)));
    await tester.pumpAndSettle();
    const none = PerformanceContentData.noValue;
    expect(summaryTile(PerformanceContentData.summaryQuizLabel, none, PerformanceContentData.quizCount(0)), findsOneWidget);
    expect(summaryTile(PerformanceContentData.summaryHomeworkLabel, none, PerformanceContentData.releasedGrades(0)), findsOneWidget);
    expect(summaryTile(PerformanceContentData.summaryCriteriaLabel, none, PerformanceContentData.summaryCriteriaDetail), findsOneWidget);
    expect(find.text(PerformanceContentData.compactEmpty), findsOneWidget);
    expect(find.text('0%'), findsNothing);
    expect(find.text(PerformanceContentData.competencyTitle), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('model parses numbers sent as integers, decimals or strings', () {
    final snapshot = PerformanceSnapshot.fromJson({
      ...populatedJson(),
      'progress': {'overall_percent': '12.5', 'completed_items': 3.0, 'total_items': 24, 'cocs': []},
    });
    expect(snapshot.progress.overallPercent, 12.5);
    expect(snapshot.progress.completedItems, 3);
    expect(snapshot.homework.first.percent, 80);
    expect(snapshot.quizzes.last.score, 8);
    expect(snapshot.quizzes.last.released, isTrue);
    expect(snapshot.quizzes.first.score, isNull);
    expect(snapshot.quizzes.first.title, isNull, reason: 'get_my_performance carries no quiz title');
    final titled = snapshot.withQuizTitles(const {'q4': 'Diagnosis Essay Quiz'});
    expect(titled.quizzes.last.title, 'Diagnosis Essay Quiz');
    expect(titled.quizzes.first.title, isNull);
    expect(identical(snapshot.withQuizTitles(const {}), snapshot), isTrue);
    expect(snapshot.homework.last.score, isNull);
    expect(snapshot.homework.last.percent, isNull);
    expect(snapshot.summary.homeworkAvg, 80);
    expect(snapshot.summary.criteriaAchieved, 1);
    expect(snapshot.hasActivity, isTrue);
    expect(snapshot.hasScoredWork, isTrue);
    final empty = PerformanceSnapshot.fromJson(emptyJson());
    expect(empty.hasActivity, isFalse);
    expect(empty.hasScoredWork, isFalse);
    final legacy = PerformanceSnapshot.fromJson({...emptyJson()}..remove('summary'));
    expect(legacy.summary.quizAvg, isNull, reason: 'a payload without a summary parses to empty values');
    expect(legacy.summary.criteriaTotal, 0);
    expect(PerformanceContentData.percent(null), PerformanceContentData.noValue);
    expect(PerformanceContentData.duration(3720), '1h 2m');
    expect(PerformanceContentData.homeworkDetail(null, late: false), isNull);
  });

  group('inside the Progress screen', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'sb_publishable_performance_test');
    });
    tearDownAll(() async => Supabase.instance.dispose());

    testWidgets('the compact section fills the Performance slot and keeps the Progress layout', (tester) async {
      await a2.setSurface(tester, 420, 4000);
      final service = FakePerformanceService([populatedJson()]);
      await tester.pumpWidget(a2.host(ProgressScreen(
        sources: a2.progressSources(a2.FakeCurriculumService()),
        performanceSection: PerformanceSection(service: service, compact: true),
      )));
      await tester.pumpAndSettle();

      final slotHeader = find.text(LearningContentData.performanceTitle);
      final quizTile = summaryTile(PerformanceContentData.summaryQuizLabel, '94.5%', PerformanceContentData.quizCount(2));
      expect(slotHeader, findsOneWidget);
      expect(quizTile, findsOneWidget);
      expect(find.text('Wears the ESD wrist strap'), findsOneWidget);
      expect(find.text(PerformanceContentData.sectionTitle), findsNothing, reason: 'one header: the screen\'s own');
      expect(service.fetches, 1);

      double top(Finder finder) => tester.getTopLeft(finder).dy;
      expect(top(find.text(LearningContentData.overallTitle).first), lessThan(top(slotHeader)),
          reason: 'learning progress stays first');
      expect(top(slotHeader), lessThan(top(quizTile)), reason: 'the section renders under the slot header');
      expect(find.byKey(const ValueKey('methodology-button')), findsOneWidget, reason: 'the methodology info stays');

      await tester.scrollUntilVisible(find.text(LearningContentData.resultsTitle), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text(LearningContentData.resultsTitle), findsOneWidget, reason: 'released results follow the slot');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
