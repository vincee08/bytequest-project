import 'package:bytequest/services/practice_coc_session_service.dart';
import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/widgets/practice_coc_session_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('one COC deadline survives navigation and reload for the same learner',
      () async {
    const service = PracticeCocSessionService();
    final started = DateTime.utc(2026, 11, 9, 9);
    final first = await service.start('learner-a', 'coc1', now: started);
    expect(first.deadlineUtc, started.add(const Duration(minutes: 60)));
    final nextMission = await service.start('learner-a', 'coc1',
        now: started.add(const Duration(minutes: 20)));
    expect(nextMission.startedAtUtc, started);
    expect(nextMission.remainingAt(started.add(const Duration(minutes: 20))),
        const Duration(minutes: 40));
    final restored = await service.load('learner-a', 'coc1');
    expect(restored!.deadlineUtc, first.deadlineUtc);
    expect(await service.load('learner-a', 'coc2'), isNull);
    expect(await service.load('learner-b', 'coc1'), isNull);
  });

  test('expiry blocks at the exact deadline and restart is explicit', () async {
    const service = PracticeCocSessionService();
    final started = DateTime.utc(2026, 11, 9, 9);
    final session = await service.start('learner', 'coc4', now: started);
    final deadline = started.add(const Duration(minutes: 60));
    expect(session.expiredAt(deadline.subtract(const Duration(seconds: 1))),
        false);
    expect(session.expiredAt(deadline), true);
    expect(session.remainingAt(deadline.add(const Duration(days: 1))),
        Duration.zero);
    final unchanged = await service.start('learner', 'coc4', now: deadline);
    expect(unchanged.startedAtUtc, started);
    final restarted = await service.start('learner', 'coc4',
        now: deadline, restartExpired: true);
    expect(restarted.startedAtUtc, deadline);
    expect(restarted.deadlineUtc, deadline.add(const Duration(minutes: 60)));
  });

  test('checkpoint detects backward device clock movement after reload',
      () async {
    const service = PracticeCocSessionService();
    final started = DateTime.utc(2026, 11, 9, 9);
    final session = await service.start('learner', 'coc2', now: started);
    await service.checkpoint('learner',
        session.observedAt(started.add(const Duration(minutes: 20))));
    final restored = await service.load('learner', 'coc2');
    expect(restored!.clockMovedBackAt(started), true);
    expect(restored.clockMovedBackAt(started.add(const Duration(minutes: 20))),
        false);
  });

  test('invalid checkpoint fails closed instead of silently resetting time',
      () async {
    const service = PracticeCocSessionService();
    SharedPreferences.setMockInitialValues({
      'bq_practice_coc_session_learner_coc3': '{bad json',
    });
    await expectLater(service.start('learner', 'coc3'), throwsStateError);
  });

  test('old route checkpoint cannot replace a restarted session', () async {
    const service = PracticeCocSessionService();
    final started = DateTime.utc(2026, 11, 9, 9);
    final old = await service.start('learner', 'coc1', now: started);
    final next = await service.start('learner', 'coc1',
        now: started.add(const Duration(minutes: 61)), restartExpired: true);
    await service.checkpoint(
        'learner', old.observedAt(started.add(const Duration(minutes: 30))));
    final restored = await service.load('learner', 'coc1');
    expect(restored!.startedAtUtc, next.startedAtUtc);
    expect(restored.deadlineUtc, next.deadlineUtc);
  });

  test('two COC entry points cannot start competing deadlines', () async {
    const service = PracticeCocSessionService();
    final started = DateTime.utc(2026, 11, 9, 9);
    final entries = await Future.wait([
      service.start('learner', 'coc2', now: started),
      service.start('learner', 'coc2',
          now: started.add(const Duration(seconds: 2))),
    ]);
    expect(entries[0].deadlineUtc, entries[1].deadlineUtc);
    final persisted = await service.load('learner', 'coc2');
    expect(persisted!.deadlineUtc, entries[0].deadlineUtc);
    expect(persisted.startedAtUtc,
        anyOf(started, started.add(const Duration(seconds: 2))));
  });

  for (final size in const [Size(320, 568), Size(640, 360)]) {
    testWidgets('COC countdown stays usable at $size with large text',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MediaQuery(
                  data: MediaQueryData.fromView(tester.view)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: SafeArea(
                      child: SingleChildScrollView(
                          child: PracticeCocSessionPanel(
                              cocId: 'coc1', userId: 'layout-$size')))))));
      await tester.pumpAndSettle();
      final start = find.text(MissionContentData.practiceTimerStart);
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(
          find.textContaining(MissionContentData.practiceTimerRemainingLabel),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mission timer keeps a visible countdown and short warning',
      (tester) async {
    final now = DateTime.utc(2026, 11, 9, 9);
    final session = await const PracticeCocSessionService()
        .start('timer-label-learner', 'coc1', now: now);
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: PracticeCocTimeLabel(
              session: session, now: now.add(const Duration(minutes: 55))),
        ),
      ),
    ));
    expect(find.text(MissionContentData.practiceTimerWarningShort(5)),
        findsOneWidget);
    expect(find.text('5:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PracticeCocTimeLabel(
            session: session, now: now.add(const Duration(minutes: 61))),
      ),
    ));
    expect(find.text(MissionContentData.practiceTimerExpiredShort),
        findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);
  });
}
