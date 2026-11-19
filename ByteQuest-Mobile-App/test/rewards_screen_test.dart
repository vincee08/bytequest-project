import 'dart:async';

import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/rewards_content_data.dart';
import 'package:bytequest/models/rewards_model.dart';
import 'package:bytequest/screens/leaderboard/leaderboard_screen.dart';
import 'package:bytequest/services/learner_realtime_coordinator.dart';
import 'package:bytequest/services/rewards_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _achievement(
        String code, String title, String description, String icon,
        {String? earnedAt, int current = 0, int target = 1}) =>
    {
      'code': code,
      'title': title,
      'description': description,
      'icon': icon,
      'earned_at': earnedAt,
      'progress_current': current,
      'progress_target': target,
    };

/// Mirrors the shape returned by public.get_learner_rewards().
Map<String, dynamic> rewardsJson({bool empty = false, bool optedIn = false}) =>
    {
      'points': empty ? 0 : 150,
      'level': empty
          ? {
              'level': 1,
              'title': 'Trainee',
              'min_points': 0,
              'next_level': 2,
              'next_min_points': 100,
              'progress_percent': 0,
            }
          : {
              'level': 2,
              'title': 'Apprentice',
              'min_points': 100,
              'next_level': 3,
              'next_min_points': 300,
              'progress_percent': 25,
            },
      'show_on_leaderboard': optedIn,
      'achievements': [
        _achievement('first_mission', 'First Verified Mission',
            'Verify your first practice mission.', 'verified',
            earnedAt: empty ? null : '2026-04-01T04:00:00Z',
            current: empty ? 0 : 1),
        _achievement('five_missions', 'Five Missions Verified',
            'Verify five different practice missions.', 'military_tech',
            current: empty ? 0 : 3, target: 5),
        _achievement(
            'coc1_complete',
            'COC 1 Complete',
            'Complete COC 1: Install and Configure Computer Systems.',
            'not_a_known_icon'),
      ],
      'recent': empty
          ? <Map<String, dynamic>>[]
          : [
              {
                'event_type': 'practice_mission_verified',
                'label': 'Practice mission verified',
                'points': 50,
                'awarded_at': '2026-04-01T06:00:00Z',
                'source_id': 'coc1_m3',
                'detail': 'Install and Configure a Workstation OS',
              },
              {
                'event_type': 'practice_mission_verified',
                'label': 'Practice mission verified',
                'points': 50,
                'awarded_at': '2026-04-01T05:00:00Z',
                'source_id': 'coc1_m2',
                'detail': 'Install Internal Components',
              },
            ],
      'points_by_category': [
        {
          'event_type': 'practice_mission_verified',
          'label': 'Practice mission verified',
          'points': empty ? 0 : 150,
          'count': empty ? 0 : 3,
          'points_each': 50,
          'active': true,
        },
        {
          'event_type': 'topic_completed',
          'label': 'Topic completed',
          'points': 0,
          'count': 0,
          'points_each': 10,
          'active': true,
        },
      ],
      'leaderboard': empty
          ? [
              {'rank': 1, 'display_name': 'Ivy', 'points': 0, 'is_me': true}
            ]
          : [
              {
                'rank': 1,
                'display_name': 'Ben S.',
                'points': 300,
                'is_me': false
              },
              {
                'rank': 1,
                'display_name': 'Gio T.',
                'points': 300,
                'is_me': false
              },
              {
                'rank': 3,
                'display_name': 'Ana R.',
                'points': 150,
                'is_me': true
              },
            ],
    };

class FakeRewardsService extends RewardsService {
  FakeRewardsService(Map<String, dynamic> json)
      : value = LearnerRewards.fromJson(json);

  LearnerRewards value;
  Object? fetchError;
  Object? saveError;
  Completer<void>? saveGate;
  int fetches = 0;
  final List<bool> saves = [];

  @override
  Future<LearnerRewards> fetchRewards() async {
    fetches++;
    final error = fetchError;
    if (error != null) throw error;
    return value;
  }

  @override
  Future<bool> setLeaderboardVisibility(bool visible) async {
    saves.add(visible);
    final gate = saveGate;
    if (gate != null) await gate.future;
    final error = saveError;
    if (error != null) throw error;
    value = value.copyWith(showOnLeaderboard: visible);
    return visible;
  }
}

Future<void> pumpRewards(WidgetTester tester, FakeRewardsService service,
    {double textScale = 1}) async {
  await tester.pumpWidget(ChangeNotifierProvider(
    create: (_) => LearnerRealtimeCoordinator(),
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: LeaderboardScreen(service: service),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder get _scrollable => find.byType(Scrollable).first;

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'sb_publishable_rewards_test');
  });

  test('rewards model parses the server projection defensively', () {
    final value = LearnerRewards.fromJson(rewardsJson());
    expect(value.points, 150);
    expect(value.level.title, 'Apprentice');
    expect(value.level.progressFraction, closeTo(.25, .0001));
    expect(value.level.pointsToNextLevel(value.points), 150);
    expect(value.level.isTopLevel, isFalse);
    expect(value.achievements.first.earned, isTrue);
    expect(value.achievements.first.earnedAt, DateTime.utc(2026, 4, 1, 4));
    expect(value.achievements[1].earned, isFalse);
    expect(value.achievements[1].showsProgress, isTrue);
    expect(value.earnedAchievementCount, 1);
    expect(value.recent.first.detail, 'Install and Configure a Workstation OS');
    expect(value.leaderboard.where((row) => row.isMe).single.rank, 3);
    expect(value.isNewLearner, isFalse);
    expect(value.pointsFor('practice_mission_verified'), 50);
    expect(
        LearnerRewards.fromJson(rewardsJson(empty: true)).isNewLearner, isTrue);

    final sparse = LearnerRewards.fromJson({
      'points': 1500.0,
      'level': {
        'level': 6,
        'title': 'Lead Technician',
        'min_points': 1500,
        'next_level': null,
        'next_min_points': null,
        'progress_percent': 100,
      },
    });
    expect(sparse.points, 1500);
    expect(sparse.level.isTopLevel, isTrue);
    expect(sparse.level.pointsToNextLevel(sparse.points), isNull);
    expect(sparse.achievements, isEmpty);
    expect(sparse.leaderboard, isEmpty);
    expect(sparse.pointsFor('practice_mission_verified'), isNull);
    expect(sparse.copyWith(showOnLeaderboard: true).showOnLeaderboard, isTrue);
  });

  test('content data maps icons and never labels results Wrong or Correct', () {
    expect(RewardsContentData.achievementIcon('verified'),
        Icons.verified_outlined);
    expect(RewardsContentData.achievementIcon('unknown_icon'),
        RewardsContentData.fallbackAchievementIcon);
    expect(RewardsContentData.emptyMessage(50),
        'Verify your first practice mission to earn 50 points.');
    expect(RewardsContentData.leaderboardToggleSubtitle,
        'Show my first name and points to classmates.');
    final copy = [
      RewardsContentData.separationNote,
      ...RewardsContentData.infoParagraphs,
      RewardsContentData.leaderboardSaveFailed,
      RewardsContentData.errorMessage,
    ].join(' ');
    expect(copy, isNot(contains('Wrong')));
    expect(copy, isNot(contains('Correct')));
    expect(RewardsContentData.infoParagraphs.join(' '),
        contains('separate from competency results'));
  });

  testWidgets('a new learner sees a truthful empty state', (tester) async {
    final service = FakeRewardsService(rewardsJson(empty: true));
    await pumpRewards(tester, service);

    expect(find.text(RewardsContentData.emptyTitle), findsOneWidget);
    expect(find.text('Verify your first practice mission to earn 50 points.'),
        findsOneWidget);
    expect(
        find.text(RewardsContentData.levelLabel(1, 'Trainee')), findsOneWidget);
    expect(find.text(RewardsContentData.pointsToNextLevel(100, 2)),
        findsOneWidget);
    await tester.scrollUntilVisible(
        find.text(RewardsContentData.recentEmpty), 200,
        scrollable: _scrollable);
    expect(find.text(RewardsContentData.recentEmpty), findsOneWidget);
    expect(find.textContaining('Earned '), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'earned achievements show colour and date, locked ones how to earn',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final service = FakeRewardsService(rewardsJson());
    await pumpRewards(tester, service);

    await tester.scrollUntilVisible(find.text('Five Missions Verified'), 200,
        scrollable: _scrollable);
    expect(find.text('First Verified Mission'), findsOneWidget);
    expect(find.text(RewardsContentData.earnedOn(DateTime.utc(2026, 4, 1, 4))),
        findsOneWidget);
    expect(
        find.text('Verify five different practice missions.'), findsOneWidget);
    expect(find.text(RewardsContentData.progressLabel(3, 5)), findsOneWidget);
    expect(find.text(RewardsContentData.achievementsProgress(1, 3)),
        findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^First Verified Mission, earned')),
        findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Five Missions Verified, locked')),
        findsOneWidget);

    final earnedIcon =
        tester.widget<Icon>(find.byIcon(Icons.verified_outlined));
    final lockedIcon =
        tester.widget<Icon>(find.byIcon(Icons.military_tech_outlined));
    expect(earnedIcon.color, isNot(lockedIcon.color));
    expect(find.byIcon(RewardsContentData.fallbackAchievementIcon),
        findsOneWidget);
    semantics.dispose();
  });

  testWidgets('level progress shows the title, bar and points to next level',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final service = FakeRewardsService(rewardsJson());
    await pumpRewards(tester, service);

    expect(find.text('150'), findsWidgets);
    expect(find.text(RewardsContentData.levelLabel(2, 'Apprentice')),
        findsOneWidget);
    expect(find.text(RewardsContentData.pointsToNextLevel(150, 3)),
        findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('rewards-level-progress')));
    expect(bar.value, closeTo(.25, .0001));
    expect(
        find.bySemanticsLabel(
            RegExp(RewardsContentData.levelProgressSemantics(2, 'Apprentice'))),
        findsOneWidget);

    await tester.scrollUntilVisible(find.text('Gio T.'), 200,
        scrollable: _scrollable);
    expect(find.text('Ben S.'), findsOneWidget);
    expect(find.text(RewardsContentData.youLabel), findsOneWidget);
    expect(
        find.bySemanticsLabel(
            RewardsContentData.leaderboardSemantics(3, 'Ana R.', 150, true)),
        findsOneWidget);
    semantics.dispose();
  });

  testWidgets('opting in saves once and confirms only after the server does',
      (tester) async {
    final service = FakeRewardsService(rewardsJson())..saveGate = Completer();
    await pumpRewards(tester, service);
    final toggle = find.byKey(const ValueKey('rewards-leaderboard-toggle'));
    await tester.scrollUntilVisible(toggle, 200, scrollable: _scrollable);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pump();
    expect(service.saves, [true]);
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
    await tester.tap(toggle);
    await tester.pump();
    expect(service.saves, [true]);
    expect(find.text(RewardsContentData.leaderboardShown), findsNothing);

    service.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text(RewardsContentData.leaderboardShown), findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNotNull);
  });

  testWidgets('a failed opt-in keeps the previous choice and explains why',
      (tester) async {
    final service = FakeRewardsService(rewardsJson())
      ..saveError = StateError('offline');
    await pumpRewards(tester, service);
    final toggle = find.byKey(const ValueKey('rewards-leaderboard-toggle'));
    await tester.scrollUntilVisible(toggle, 200, scrollable: _scrollable);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(service.saves, [true]);
    expect(find.text(RewardsContentData.leaderboardSaveFailed), findsOneWidget);
    expect(find.text(RewardsContentData.leaderboardShown), findsNothing);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
  });

  testWidgets('load failure offers a retry that recovers', (tester) async {
    final service = FakeRewardsService(rewardsJson())
      ..fetchError = StateError('offline');
    await pumpRewards(tester, service);
    expect(find.text(RewardsContentData.errorTitle), findsOneWidget);
    expect(find.text(RewardsContentData.levelLabel(2, 'Apprentice')),
        findsNothing);

    service.fetchError = null;
    await tester.tap(find.text(RewardsContentData.retryLabel));
    await tester.pumpAndSettle();
    expect(service.fetches, 2);
    expect(find.text(RewardsContentData.levelLabel(2, 'Apprentice')),
        findsOneWidget);
  });

  testWidgets('pull to refresh reloads and keeps values when refresh fails',
      (tester) async {
    final service = FakeRewardsService(rewardsJson());
    await pumpRewards(tester, service);
    service.fetchError = StateError('offline');
    await tester.fling(_scrollable, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(service.fetches, 2);
    expect(find.text(RewardsContentData.refreshFailed), findsOneWidget);
    expect(find.text(RewardsContentData.levelLabel(2, 'Apprentice')),
        findsOneWidget);
  });

  testWidgets('the info sheet explains points are separate from competency',
      (tester) async {
    final service = FakeRewardsService(rewardsJson());
    await pumpRewards(tester, service);
    await tester.tap(find.byTooltip(RewardsContentData.infoTooltip));
    await tester.pumpAndSettle();
    expect(find.text(RewardsContentData.infoTitle), findsWidgets);
    expect(find.text(RewardsContentData.infoParagraphs[2]), findsOneWidget);
    await tester.ensureVisible(find.text(RewardsContentData.infoClose));
    await tester.pumpAndSettle();
    await tester.tap(find.text(RewardsContentData.infoClose));
    await tester.pumpAndSettle();
    expect(find.text(RewardsContentData.infoParagraphs[2]), findsNothing);
  });

  testWidgets(
      'rewards stay usable at 320 px with large text and reduced motion',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = FakeRewardsService(rewardsJson());
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => LearnerRealtimeCoordinator(),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true),
            child: child!),
        home: LeaderboardScreen(service: service),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final text in [
      'Five Missions Verified',
      'Install Internal Components',
      'Topic completed',
      'Gio T.',
      RewardsContentData.separationNote,
    ]) {
      await tester.scrollUntilVisible(find.text(text), 200,
          scrollable: _scrollable);
      expect(find.text(text), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    final toggle = find.byKey(const ValueKey('rewards-leaderboard-toggle'));
    await tester.scrollUntilVisible(toggle, -200, scrollable: _scrollable);
    expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });
}
