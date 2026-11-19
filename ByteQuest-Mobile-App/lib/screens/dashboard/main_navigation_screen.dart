import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/config/supabase_config.dart';
import '../../services/learner_realtime_coordinator.dart';
import '../../core/widgets/learner_navigation_shell.dart';
import 'dashboard_screen.dart';
import '../learn/learn_screen.dart';
import '../practice/practice_screen.dart';
import '../progress/progress_screen.dart';
import '../leaderboard/leaderboard_screen.dart';

/// Main learner navigation: Home · Learn · Practice · Progress · Rewards.
/// The shared shell preserves each destination's state and handles main-tab
/// Back history. Order must match ByteQuestBottomNav.destinations.
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final List<Widget> _screens = [
    const DashboardScreen(), // Home: to-do, notifications, class work shortcuts
    const LearnScreen(), // Learn: COC -> module lessons and outcomes
    const PracticeScreen(), // Practice: module-gated 2D missions
    const ProgressScreen(), // Progress: one learning projection + released results
    const LeaderboardScreen(), // Rewards (slice A6)
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (mounted && userId != null) {
        context.read<LearnerRealtimeCoordinator>().start(userId);
      }
    });
  }

  @override
  void dispose() {
    context.read<LearnerRealtimeCoordinator>().stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LearnerNavigationShell(destinations: _screens);
}
