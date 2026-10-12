import 'dart:async';

import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/core/widgets/app_button.dart';
import 'package:bytequest/core/widgets/learner_navigation_shell.dart';
import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/models/profile_model.dart';
import 'package:bytequest/screens/auth/login_screen.dart';
import 'package:bytequest/screens/auth/forgot_password_screen.dart';
import 'package:bytequest/screens/auth/signup_screen.dart';
import 'package:bytequest/screens/settings/change_password_screen.dart';
import 'package:bytequest/screens/settings/help_center_screen.dart';
import 'package:bytequest/screens/settings/terms_privacy_screen.dart';
import 'package:bytequest/screens/settings/edit_profile_screen.dart';
import 'package:bytequest/screens/simulation/components/mission_task_status.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:bytequest/services/auth_service.dart';
import 'package:bytequest/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:bytequest/widgets/app_top_bar.dart';
import 'package:bytequest/widgets/bytequest_bottom_nav.dart';
import 'package:bytequest/widgets/practice_progress_panel.dart';
import 'package:bytequest/models/practice_progress_model.dart';

void main() {
  testWidgets(
      'practice progress explains the next task and exposes only available quizzes',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opens = 0;
    for (final count in [1, 5]) {
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
              data: const MediaQueryData(
                  size: Size(320, 568), textScaler: TextScaler.linear(2)),
              child: Scaffold(
                  body: ListView(padding: const EdgeInsets.all(16), children: [
                PracticeCocSummary(
                  progress: PracticeCocProgress(
                      coc: 'coc1',
                      unlocked: true,
                      completed: false,
                      completedMissions: {
                        for (var i = 1; i <= count; i++) 'coc1_m$i'
                      }),
                  onOpenQuiz: () => opens++,
                )
              ])))));
      await tester.pumpAndSettle();
      expect(find.text(MissionContentData.practiceMissionCount(count)),
          findsOneWidget);
      if (count == 1) {
        expect(find.text(MissionContentData.practiceMissionsPendingLabel),
            findsOneWidget);
        expect(find.byType(OutlinedButton), findsNothing);
      } else {
        expect(find.text(MissionContentData.practiceQuizReadyLabel),
            findsOneWidget);
        final quiz = find.text(MissionContentData.practiceQuizStart);
        await tester.ensureVisible(quiz);
        await tester.pumpAndSettle();
        await tester.tap(quiz);
        expect(opens, 1);
      }
      expect(tester.takeException(), isNull);
    }
  });

  test('small status text and button labels meet AA contrast on white', () {
    for (final color in [
      AppTheme.primaryBlue,
      AppTheme.errorRed,
      AppTheme.accentGreen,
      AppTheme.textMedium,
      AppTheme.textLight
    ]) {
      final contrast = (Colors.white.computeLuminance() + .05) /
          (color.computeLuminance() + .05);
      expect(contrast, greaterThanOrEqualTo(4.5), reason: '$color');
    }
  });

  testWidgets('navigation and labeled settings fit at 2x text on a small phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var settings = 0;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: const MediaQueryData(
              size: Size(320, 568), textScaler: TextScaler.linear(2)),
          child: Scaffold(
              body: ListView(children: [
                AppTopBar(
                    title: 'Hello, Learner',
                    onNotificationTap: () {},
                    onSettingsTap: () => settings++)
              ]),
              bottomNavigationBar:
                  ByteQuestBottomNav(currentIndex: 0, onTap: (_) {})),
        )));
    await tester.tap(find.text(MissionContentData.settingsLabel));
    expect(settings, 1);
    expect(tester.takeException(), isNull);
    for (final label in ['Home', 'Learn', 'Progress', 'Rewards']) {
      expect(find.text(label), findsOneWidget);
    }
  });
  test('preparing COC1 M2 still identifies all six pending inspections', () {
    final phase = MissionSimulationDefinitions.byId('coc1_m2').phases.first;
    final state = MissionRuntimeState.initial('coc1_m2').copyWith(placements: {
      'esd_mat': 'esd_mat_position',
      'service_chassis': 'service_chassis_position',
    });
    expect(missionPendingTasks(phase, state), ['Inspections: 0 of 6']);
  });

  test('COC1 M2 phase three explains both connections and procedure', () {
    final phase = MissionSimulationDefinitions.byId('coc1_m2').phases[2];
    expect(missionPendingTasks(phase, MissionRuntimeState.initial('coc1_m2')),
        ['Connections: 0 of 2', MissionContentData.sequencePendingLabel]);
    final connected = MissionRuntimeState.initial('coc1_m2')
        .copyWith(connectedNodePairs: {'atx>board_power', 'sata>storage_data'});
    expect(missionPendingTasks(phase, connected),
        [MissionContentData.sequencePendingLabel]);
  });

  test('assessment status excludes practice preparation requirements', () {
    final phase = MissionSimulationDefinitions.byId('coc1_m2').phases.first;
    final state = MissionRuntimeState.initial('coc1_m2',
        mode: MissionRuntimeMode.assessment,
        assessmentAttemptId: 'assessment-qa');
    expect(missionPendingTasks(phase, state), ['Inspections: 0 of 6']);
  });

  testWidgets(
      'main navigation preserves entries and system back returns to the previous tab',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: LearnerNavigationShell(destinations: [
          Builder(
              builder: (context) => Center(
                  child: FilledButton(
                      onPressed: () => LearnerNavigationScope.maybeOf(context)!
                          .selectDestination(1),
                      child: const Text('Open learning')))),
          const TextField(key: ValueKey('saved-entry')),
          const Center(child: Text('Progress body')),
          const Center(child: Text('Rewards body')),
        ])));
    await tester.tap(find.text('Open learning'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('saved-entry')), 'Keep this draft');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.tap(find.text('Progress'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Keep this draft'), findsOneWidget);
    expect(find.text('Progress body'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open learning'), findsOneWidget);
  });

  testWidgets(
      'loading button retains its label, blocks repeated taps and grows for large text',
      (tester) async {
    var presses = 0;
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const label = 'Save this installation configuration';
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: const MediaQueryData(
              size: Size(320, 568), textScaler: TextScaler.linear(2)),
          child: Scaffold(
              body: AppButton.primary(
                  label: label,
                  width: double.infinity,
                  isLoading: true,
                  onPressed: () => presses++)),
        )));
    expect(find.text(label), findsOneWidget);
    await tester.tap(find.text(label));
    expect(presses, 0);
    expect(tester.getSize(find.byType(AppButton)).height, greaterThan(56));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign-up Terms action opens a real route and retains the name',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: const SignupScreen(),
        routes: {
          '/terms-privacy': (_) =>
              Scaffold(appBar: AppBar(title: const Text('Terms test page')))
        }));
    final name = find.byType(TextFormField).first;
    await tester.enterText(name, 'Learner draft');
    final terms = find.text(MissionContentData.termsLinkLabel);
    await tester.ensureVisible(terms);
    await tester.tap(terms);
    await tester.pumpAndSettle();
    expect(find.text('Terms test page'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextFormField>(name).controller!.text, 'Learner draft');
  });

  for (final screen in const [
    LoginScreen(),
    SignupScreen(),
    ForgotPasswordScreen(),
    ChangePasswordScreen(),
    HelpCenterScreen(),
    TermsPrivacyScreen()
  ]) {
    testWidgets(
        '${screen.runtimeType} fits a small screen with large text and keyboard',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
              data: const MediaQueryData(
                  size: Size(320, 568),
                  viewInsets: EdgeInsets.only(bottom: 220),
                  textScaler: TextScaler.linear(2)),
              child: screen)));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'profile save failure preserves the form and retry prevents duplicate saves',
      (tester) async {
    final profiles = _Profiles();
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<AuthService>.value(value: _Auth()),
          Provider<ProfileService>.value(value: profiles),
        ],
        child: MaterialApp(
            theme: AppTheme.lightTheme, home: const EditProfileScreen())));
    await tester.pumpAndSettle();
    final name = find.byType(TextFormField).first;
    await tester.enterText(name, 'Changed learner name');
    final save = find.text('Save Changes');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byType(Form), findsOneWidget);
    expect(find.text(MissionContentData.profileSaveFailed), findsOneWidget);
    expect(tester.widget<TextFormField>(name).controller!.text,
        'Changed learner name');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    await tester.tap(save);
    expect(profiles.writes, 2);
    profiles.retry.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.byType(Form), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Auth implements AuthService {
  @override
  String get currentUserId => 'ux-test-user';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profiles implements ProfileService {
  int writes = 0;
  final retry = Completer<void>();
  @override
  Future<ProfileModel?> getProfileByUserId(String userId) async => ProfileModel(
      id: 'ux-profile',
      userId: userId,
      fullName: 'Learner',
      email: 'learner@example.test',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026));
  @override
  Future<void> updateProfile(
      String userId, Map<String, dynamic> updates) async {
    writes++;
    if (writes == 1) throw StateError('offline');
    await retry.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
