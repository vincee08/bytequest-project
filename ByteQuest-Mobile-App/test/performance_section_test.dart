import 'dart:async';

import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/performance_content_data.dart';
import 'package:bytequest/models/performance_model.dart';
import 'package:bytequest/screens/progress/performance_section.dart';
import 'package:bytequest/services/performance_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// Shape returned by get_my_performance() for the A7 rollback fixture learner
/// (supabase/tests/analytics_redefense_rollback.sql, learner L1).
Map<String, dynamic> populatedJson({double overall = 12.5, String updatedAt = '2026-11-19T07:05:00Z'}) => {
      'progress': {
        'overall_percent': overall,
        'completed_items': 3,
        'total_items': 24,
        'cocs': [
          {'coc_code': 'coc1', 'title': 'Install and Configure Computer Systems', 'percent': 50.0, 'completed_items': 3, 'total_items': 6, 'modules_completed': 1, 'modules_total': 3},
          {'coc_code': 'coc2', 'title': 'Set-up Computer Networks', 'percent': 0, 'completed_items': 0, 'total_items': 6, 'modules_completed': 0, 'modules_total': 3},
        ],
      },
      'competency': [
        {'criterion': 'Wears the ESD wrist strap', 'code': 'A7-CRIT-A', 'mission_code': 'coc1_m2', 'mission_title': 'Install Internal Components', 'outcome': 'satisfied', 'released_at': '2026-11-16T07:00:00Z'},
        {'criterion': 'Seats the CPU in the correct orientation', 'code': 'A7-CRIT-B', 'mission_code': 'coc1_m2', 'mission_title': 'Install Internal Components', 'outcome': 'not_satisfied', 'released_at': '2026-11-16T07:00:00Z'},
      ],
      'scores': {
        'quizzes': [
          {'attempt_id': 'q1', 'title': 'Hardware Basics Quiz', 'percent': 100.0, 'correct_count': 2, 'question_count': 2, 'submitted_at': '2026-11-17T07:00:00Z'},
        ],
        'homework': [
          {'title': 'Workstation report', 'score': 80, 'max_score': 100, 'released': true, 'submitted_at': '2026-11-16T07:00:00Z', 'late': false},
          {'title': 'Cable checklist', 'score': null, 'max_score': 100, 'released': false, 'submitted_at': '2026-11-18T07:00:00Z', 'late': true},
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
      'updated_at': updatedAt,
    };

Map<String, dynamic> emptyJson() => {
      'progress': {
        'overall_percent': 0,
        'completed_items': 0,
        'total_items': 24,
        'cocs': [
          {'coc_code': 'coc1', 'title': 'Install and Configure Computer Systems', 'percent': 0, 'completed_items': 0, 'total_items': 6, 'modules_completed': 0, 'modules_total': 3},
        ],
      },
      'competency': [],
      'scores': {'quizzes': [], 'homework': []},
      'assessments': [],
      'practice': {'missions_verified': 0, 'runs': 0, 'best_times': []},
      'updated_at': '2026-11-19T07:05:00Z',
    };

class FakePerformanceService extends PerformanceService {
  FakePerformanceService(this.responses);

  /// Each fetch returns the next entry (the last one repeats). An Exception
  /// entry is thrown instead.
  final List<Object> responses;
  final changes = StreamController<void>.broadcast();
  int fetches = 0;
  Completer<void>? gate;

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
    expect(find.text(PerformanceContentData.modulesCompleted(1, 3)), findsOneWidget);
    expect(find.text('Wears the ESD wrist strap'), findsOneWidget);
    expect(find.text(PerformanceContentData.achievedLabel), findsOneWidget);
    expect(find.text(PerformanceContentData.notYetAchievedLabel), findsOneWidget);
    expect(find.text(PerformanceContentData.competencySummary(1, 2)), findsOneWidget);
    expect(find.text('Hardware Basics Quiz'), findsOneWidget);
    expect(find.text(PerformanceContentData.homeworkScore('80', '100')), findsOneWidget);
    expect(find.text(PerformanceContentData.homeworkAwaiting), findsOneWidget, reason: 'an unreleased homework score is never shown');
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
    expect(service.fetches, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(service.fetches, 2, reason: 'returning to the app refreshes once');
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
    final service = FakePerformanceService([populatedJson()]);
    await tester.pumpWidget(host(PerformanceSection(service: service), textScale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final refresh = find.bySemanticsLabel(PerformanceContentData.refreshLabel);
    expect(refresh, findsOneWidget);
    final size = tester.getSize(refresh);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    await tester.pumpWidget(const SizedBox.shrink());
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

  test('model parses numbers sent as integers, decimals or strings', () {
    final snapshot = PerformanceSnapshot.fromJson({
      ...populatedJson(),
      'progress': {'overall_percent': '12.5', 'completed_items': 3.0, 'total_items': 24, 'cocs': []},
    });
    expect(snapshot.progress.overallPercent, 12.5);
    expect(snapshot.progress.completedItems, 3);
    expect(snapshot.homework.last.score, isNull);
    expect(snapshot.hasActivity, isTrue);
    expect(PerformanceSnapshot.fromJson(emptyJson()).hasActivity, isFalse);
    expect(PerformanceContentData.percent(null), PerformanceContentData.noValue);
    expect(PerformanceContentData.duration(3720), '1h 2m');
  });
}
