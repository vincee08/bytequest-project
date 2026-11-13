import 'dart:async';
import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/core/widgets/learner_navigation_shell.dart';
import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/models/home_activity_item.dart';
import 'package:bytequest/models/assigned_activity_model.dart';
import 'package:bytequest/models/learner_notification.dart';
import 'package:bytequest/models/learner_quiz_model.dart';
import 'package:bytequest/screens/notifications/notifications_screen.dart';
import 'package:bytequest/screens/missions/class_details_screen.dart';
import 'package:bytequest/screens/quizzes/quiz_details_screen.dart';
import 'package:bytequest/services/learner_activity_navigation.dart';
import 'package:bytequest/services/learner_notification_service.dart';
import 'package:bytequest/services/learner_quiz_service.dart';
import 'package:bytequest/services/learner_realtime_coordinator.dart';
import 'package:bytequest/widgets/app_top_bar.dart';
import 'package:bytequest/widgets/bytequest_bottom_nav.dart';
import 'package:bytequest/widgets/assigned_class_activities.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'homework_deadlines_test.dart' as fixtures;

LearnerNotification notice({bool read = false, String id = 'notice'}) =>
    LearnerNotification(
        id: id,
        title: 'New Quiz Assigned',
        message: 'Hardware quiz assigned to Sample Class A.',
        createdAt: DateTime.utc(2026, 11, 13),
        isRead: read,
        activityType: 'quiz',
        activityId: 'assignment',
        classId: 'class',
        classTitle: 'Sample Class A');

class FakeNotifications extends LearnerNotificationService {
  List<LearnerNotification> rows = [notice()];
  int fetches = 0, reads = 0;
  bool failFetch = false, failRead = false;
  Completer<void>? pendingRead;
  @override
  Future<List<LearnerNotification>> fetch(
      {int limit = 50, int offset = 0, bool unreadOnly = false}) async {
    fetches++;
    if (failFetch) throw StateError('offline');
    return rows
        .where((n) => !unreadOnly || !n.isRead)
        .skip(offset)
        .take(limit)
        .toList();
  }

  @override
  Future<int> unreadCount() async => rows.where((n) => !n.isRead).length;
  @override
  Future<void> markRead(String id) async {
    reads++;
    if (failRead) throw StateError('write failed');
    await pendingRead?.future;
    rows = rows
        .map((n) => notice(read: n.id == id || n.isRead, id: n.id))
        .toList();
  }

  @override
  Future<void> markAllRead() async {
    rows = rows.map((n) => notice(read: true, id: n.id)).toList();
  }
}

class MutableQuizzes extends LearnerQuizService {
  List<LearnerQuizSummary> rows = [];
  int starts = 0;
  @override
  Future<List<LearnerQuizSummary>> getAvailableQuizzes() async => rows;
  @override
  Future<LearnerQuizAttempt> startOrResume(String assignmentId) async {
    starts++;
    throw StateError('A notification must never start an attempt');
  }
}

LearnerQuizSummary quiz(
        {String? status,
        bool available = true,
        String id = 'assignment',
        List<Map<String, String>> links = const []}) =>
    LearnerQuizSummary.fromJson({
      'assignment_id': id,
      'quiz_id': 'quiz',
      'quiz_version_id': 'version',
      'title': 'Hardware quiz $id',
      'class_id': 'class',
      'class_title': 'Sample Class A',
      'eligible_assignments': links,
      'is_available': available,
      'attempt_status': status,
      if (status != null) 'attempt_id': 'attempt',
      if (!available) 'closed_reason': 'deadline_passed',
      'due_at': '2026-11-20T15:59:00Z',
    });
Widget app(Widget child) => ChangeNotifierProvider(
    create: (_) => LearnerRealtimeCoordinator(),
    child: MaterialApp(theme: AppTheme.lightTheme, home: child));

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'sb_publishable_notification_test');
  });
  tearDownAll(() async => Supabase.instance.dispose());
  test(
      'quiz priority excludes used and closed attempts, preserves resume and result actions',
      () {
    expect(HomeActivityItem.quiz(quiz()).outstanding, true);
    expect(HomeActivityItem.quiz(quiz(status: 'in_progress')).action,
        MissionContentData.quizContinue);
    for (final status in ['submitted', 'completed'])
      expect(HomeActivityItem.quiz(quiz(status: status)).outstanding, false);
    final closed =
        HomeActivityItem.quiz(quiz(status: 'in_progress', available: false));
    expect(closed.outstanding, false);
    expect(closed.enabled, false);
    expect(closed.status, MissionContentData.quizClosedDeadline);
    expect(
        HomeActivityItem.quiz(quiz(status: 'completed', available: false))
            .action,
        MissionContentData.quizViewResult);
  });
  test('homework separates submission, grading and immutable late metadata',
      () {
    final late = HomeActivityItem.homework(fixtures.homework(late: true));
    expect(late.outstanding, true);
    expect(late.enabled, true);
    expect(late.lateness, MissionContentData.homeworkLateAllowed);
    final sent = HomeActivityItem.homework(
        fixtures.homework(submission: fixtures.submitted(late: 195300)));
    expect(sent.outstanding, false);
    expect(sent.completed, false);
    expect(sent.status, 'Submitted for Grading');
    expect(sent.lateness, 'Late by 2 days, 6 hours, 15 minutes');
    final graded = HomeActivityItem.homework(
        fixtures.homework(submission: fixtures.submitted(status: 'graded')));
    expect(graded.completed, true);
    expect(graded.action, MissionContentData.homeViewGrading);
    final list = [HomeActivityItem.quiz(quiz()), late]
      ..sort(HomeActivityItem.prioritize);
    expect(list.first, late);
  });
  test('deep links revalidate current access without starting attempts',
      () async {
    final service = MutableQuizzes()..rows = [quiz()];
    expect(await LearnerActivityNavigation.resolve(notice(), quizzes: service),
        isA<QuizDetailsScreen>());
    expect(service.starts, 0);
    service.rows = [];
    await expectLater(
        LearnerActivityNavigation.resolve(notice(), quizzes: service),
        throwsStateError);
  });
  test(
      'a second eligible class resolves to the canonical quiz and a revoked reference does not',
      () async {
    final service = MutableQuizzes()
      ..rows = [
        quiz(status: 'in_progress', links: [
          {'assignment_id': 'other-assignment', 'class_id': 'other-class'}
        ])
      ];
    final item = LearnerNotification(
        id: 'notice',
        title: 'Quiz assigned',
        message: '',
        createdAt: DateTime.utc(2026),
        isRead: false,
        activityType: 'quiz',
        activityId: 'other-assignment',
        classId: 'other-class');
    final page =
        await LearnerActivityNavigation.resolve(item, quizzes: service);
    expect(page, isA<QuizDetailsScreen>());
    expect((page as QuizDetailsScreen).quiz.attemptId, 'attempt');
    expect(service.starts, 0);
    service.rows = [quiz(status: 'in_progress')];
    await expectLater(LearnerActivityNavigation.resolve(item, quizzes: service),
        throwsStateError);
  });
  test('technical review/released states stay separate from supplementary work',
      () {
    final a = AssignedActivity.fromJson({
      'id': 'technical',
      'class_id': 'class',
      'activity_version_id': 'version',
      'assignment_type': 'assessment',
      'title': 'Technical work order',
      'classes': {'title': 'Sample Class A'}
    });
    final now = DateTime.utc(2026, 11, 13);
    expect(HomeActivityItem.technical(a, null, now).outstanding, true);
    expect(HomeActivityItem.technical(a, 'in_progress', now).outstanding, true);
    for (final state in [
      'submitted',
      'evaluated',
      'under_review',
      'finalized',
      'released'
    ]) {
      expect(HomeActivityItem.technical(a, state, now).outstanding, false);
    }
    expect(HomeActivityItem.technical(a, 'released', now).completed, true);
    expect(HomeActivityItem.technical(a, 'submitted', now).status,
        contains('Official assessment'));
  });
  testWidgets('bell announces unread count and supports keyboard activation',
      (tester) async {
    var tapped = 0;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app(Scaffold(
        body: AppTopBar(
            title: 'Learner',
            notificationCount: 3,
            onNotificationTap: () => tapped++))));
    expect(find.text('3'), findsOneWidget);
    expect(
        find.bySemanticsLabel(RegExp('Notifications, 3 unread')), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tapped, 1);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'technical notice reviews only the selected task without class counter inflation',
      (tester) async {
    final activity = AssignedActivity.fromJson({
      'id': 'technical',
      'class_id': 'class',
      'activity_version_id': 'version',
      'title': 'Cable inspection task',
      'classes': {'title': 'Sample Class A'}
    });
    await tester.pumpWidget(app(ClassDetailsScreen(
        classId: 'class',
        classTitle: 'Sample Class A',
        assignments: [activity],
        resources: const [],
        focusedAssignmentId: activity.id)));
    await tester.pumpAndSettle();
    expect(find.text(activity.title), findsOneWidget);
    expect(find.text('Open activity'), findsOneWidget);
    expect(find.text('Activities'), findsNothing);
    expect(find.textContaining('Homework Assignments'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'opening waits for persisted read status before navigating and persists on reopen',
      (tester) async {
    final service = FakeNotifications()..pendingRead = Completer<void>();
    var opened = 0;
    final screen = NotificationsScreen(
        service: service,
        resolveActivity: (_) async {
          opened++;
          return const Scaffold(body: Text('Authorized quiz destination'));
        });
    await tester.pumpWidget(app(screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text(MissionContentData.notificationsOpen));
    await tester.pump();
    expect(opened, 0);
    expect(service.reads, 1);
    service.pendingRead!.complete();
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('Authorized quiz destination'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.text('Unread (0)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app(screen));
    await tester.pumpAndSettle();
    expect(find.text('Unread (0)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('failed read never opens destination or clears unread state',
      (tester) async {
    final service = FakeNotifications()..failRead = true;
    var opened = 0;
    await tester.pumpWidget(app(NotificationsScreen(
        service: service,
        resolveActivity: (_) async {
          opened++;
          return const SizedBox();
        })));
    await tester.pumpAndSettle();
    await tester.tap(find.text(MissionContentData.notificationsOpen));
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(find.text('Unread (1)'), findsOneWidget);
    expect(
        find.text(MissionContentData.notificationsSaveFailed), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('individual and mark-all operations update unread filter',
      (tester) async {
    final service = FakeNotifications()
      ..rows = [notice(), notice(id: 'second')];
    await tester.pumpWidget(app(NotificationsScreen(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(MissionContentData.notificationsMarkRead).first);
    await tester.pumpAndSettle();
    expect(find.text('Unread (1)'), findsOneWidget);
    await tester.tap(find.text(MissionContentData.notificationsMarkAll));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unread (0)'));
    await tester.pumpAndSettle();
    expect(
        find.text(MissionContentData.notificationsUnreadEmpty), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'network retry, empty state, active polling and foreground refresh without Realtime',
      (tester) async {
    final service = FakeNotifications()..failFetch = true;
    await tester.pumpWidget(app(NotificationsScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.text(MissionContentData.notificationsFailed), findsOneWidget);
    service.failFetch = false;
    service.rows = [];
    await tester.tap(find.text(MissionContentData.notificationsRetry));
    await tester.pumpAndSettle();
    expect(find.text(MissionContentData.notificationsEmpty), findsOneWidget);
    service.rows = [notice()];
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.text('Unread (1)'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final paused = service.fetches;
    await tester.pump(const Duration(seconds: 31));
    expect(service.fetches, paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(service.fetches, greaterThan(paused));
    Supabase.instance.client.auth.stopAutoRefresh();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final width in [320.0, 375.0, 768.0, 1440.0]) {
    testWidgets(
        'separate activity sections, filters and final card clear navigation at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final quizzes = MutableQuizzes()
        ..rows = [
          quiz(),
          quiz(id: 'second', status: 'completed'),
          quiz(id: 'closed', available: false)
        ];
      final homework = fixtures.FakeHomework();
      await tester.pumpWidget(app(LearnerNavigationShell(destinations: [
        Scaffold(
            body: SafeArea(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    child: AssignedClassActivities(
                        dashboard: true,
                        quizService: quizzes,
                        homeworkService: homework)))),
        const SizedBox(),
        const SizedBox(),
        const SizedBox(),
      ])));
      await tester.pumpAndSettle();
      expect(find.text('3 quizzes · 1 homework · 0 technical'), findsOneWidget);
      expect(find.text('Assigned Quizzes (3)'), findsOneWidget);
      expect(find.text('Homework Assignments (1)'), findsOneWidget);
      expect(find.text('Technical activities (0)'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.text(MissionContentData.homeworkView), 250,
          scrollable: find.byType(Scrollable).first);
      final action = tester.getRect(find.text(MissionContentData.homeworkView));
      final nav = tester.getRect(find.byType(ByteQuestBottomNav));
      expect(action.bottom, lessThan(nav.top));
      if (width < 640) {
        await tester.scrollUntilVisible(
            find.byType(DropdownButtonFormField<int>), -300,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(find.byType(DropdownButtonFormField<int>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(MissionContentData.homeCompleted).last);
      } else {
        await tester.scrollUntilVisible(
            find.text(MissionContentData.homeCompleted), -300,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(find.text(MissionContentData.homeCompleted));
      }
      await tester.pumpAndSettle();
      expect(find.text(MissionContentData.quizViewResult), findsOneWidget);
      expect(find.text(MissionContentData.homeworkView), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('compact cards and header wrap at doubled text on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 700), textScaler: TextScaler.linear(2)),
        child: Scaffold(
            body: SingleChildScrollView(
                child: Column(children: [
          AppTopBar(title: 'Hello, Learner', onNotificationTap: () {}),
          Padding(
              padding: const EdgeInsets.all(20),
              child: AssignedClassActivities(
                  dashboard: true,
                  quizService: MutableQuizzes()..rows = [quiz()],
                  homeworkService: fixtures.FakeHomework())),
        ]))))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text(MissionContentData.homeworkView), 300,
        scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
