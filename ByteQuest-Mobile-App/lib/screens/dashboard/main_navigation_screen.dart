import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/config/supabase_config.dart';
import '../../services/learner_realtime_coordinator.dart';
import '../../core/widgets/learner_navigation_shell.dart';
import 'dashboard_screen.dart';
import '../missions/missions_screen.dart';
import '../progress/progress_screen.dart';
import '../leaderboard/leaderboard_screen.dart';

/// Main learner navigation. The shared shell preserves each destination's
/// state and handles main-tab Back history.
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final List<Widget> _screens = [
    const DashboardScreen(), // Home
    const MissionsScreen(), // Missions (merged Courses + Simulation)
    const ProgressScreen(), // Progress
    const LeaderboardScreen(), // Leaderboard (new)
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
