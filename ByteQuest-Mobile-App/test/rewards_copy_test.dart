import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/learning_content_data.dart';
import 'package:bytequest/data/rewards_content_data.dart';
import 'package:bytequest/models/curriculum_model.dart';
import 'package:bytequest/screens/progress/progress_screen.dart';
import 'package:bytequest/screens/settings/help_center_screen.dart';
import 'package:bytequest/services/learner_realtime_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Copy outside the Rewards tab must describe the live points, levels,
/// achievements and Rewards tab, and keep them separate from competency.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'sb_publishable_rewards_copy_test');
  });

  test('help, profile and progress copy describes the live rewards', () {
    final copy = {
      'help question': RewardsContentData.helpQuestion,
      'help answer': RewardsContentData.helpAnswer,
      'profile record note': RewardsContentData.profileRecordNote,
      'profile motivation note': RewardsContentData.profileMotivationNote,
      'progress motivation note': LearningContentData.motivationNote,
    };
    for (final entry in copy.entries) {
      for (final stale in [
        'XP',
        'unavailable',
        'Unapproved',
        'not displayed'
      ]) {
        expect(entry.value, isNot(contains(stale)),
            reason: '${entry.key} still says "$stale"');
      }
    }
    for (final text in [
      RewardsContentData.helpAnswer,
      RewardsContentData.profileRecordNote,
      LearningContentData.motivationNote,
    ]) {
      expect(text, contains('Rewards'));
    }
    for (final text in [
      RewardsContentData.helpAnswer,
      RewardsContentData.profileMotivationNote,
      LearningContentData.motivationNote,
    ]) {
      expect(text, contains('motivational'));
      expect(text, contains('separate from competency results'));
    }
  });

  testWidgets('the help center explains points, levels and achievements',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme, home: const HelpCenterScreen()));
    expect(find.textContaining('temporarily unavailable'), findsNothing);
    expect(find.textContaining('XP'), findsNothing);
    await tester.tap(find.text(RewardsContentData.helpQuestion));
    await tester.pumpAndSettle();
    expect(find.text(RewardsContentData.helpAnswer), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'achievements');
    await tester.pumpAndSettle();
    expect(find.text(RewardsContentData.helpQuestion), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Progress sends learners to Rewards for points and levels',
      (tester) async {
    final sources = ProgressSources(
      curriculum: () async => CurriculumProjection.fromJson(const {'cocs': []}),
      releasedResults: () async => const [],
      attemptCounts: () async => const {},
      quizzes: () async => const [],
      quizResult: (_) async => throw StateError('No quiz result in this test'),
      homework: () async => const [],
    );
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => LearnerRealtimeCoordinator(),
      child: MaterialApp(
          theme: AppTheme.lightTheme, home: ProgressScreen(sources: sources)),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text(LearningContentData.motivationNote), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(LearningContentData.motivationNote), findsOneWidget);
    expect(find.textContaining('XP'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
