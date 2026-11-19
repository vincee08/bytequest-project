import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../core/widgets/supplementary_platform_notice.dart';
import '../../data/mission_content_data.dart';
import '../../models/assigned_activity_model.dart';
import '../../models/profile_model.dart';
import '../../models/learner_notification.dart';
import '../../services/auth_service.dart';
import '../../services/authoritative_assessment_service.dart';
import '../../services/profile_service.dart';
import '../../services/learner_notification_service.dart';
import '../../services/learner_activity_navigation.dart';
import '../../services/learner_realtime_coordinator.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/assigned_class_activities.dart';
import '../missions/missions_screen.dart';
import '../notifications/notifications_screen.dart';
import '../quizzes/learner_quizzes_screen.dart';
import '../settings/settings_screen.dart';
import 'home_class_work_links.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with LearnerRealtimeRefreshMixin<DashboardScreen>, WidgetsBindingObserver {
  final _assessment = AuthoritativeAssessmentService.instance;
  final _notifications = LearnerNotificationService();
  ProfileModel? _profile;
  List<AssignedActivity> _assignments = const [];
  List<ReleasedAssessmentResult> _results = const [];
  Map<String, String> _statuses = const {};
  int _unread = 0, _ticks = 0, _refreshToken = 0;
  bool _loading = true, _fetching = false, _active = false;
  String? _error;
  Timer? _poll;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  @override
  Set<LearnerRealtimeDomain> get realtimeDomains => const {
        LearnerRealtimeDomain.account,
        LearnerRealtimeDomain.learning,
        LearnerRealtimeDomain.assessment,
        LearnerRealtimeDomain.notifications,
        LearnerRealtimeDomain.classes,
      };
  @override
  Future<void> refreshFromRealtime() => _loadDashboard();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          _lifecycle == AppLifecycleState.resumed &&
          TickerMode.valuesOf(context).enabled &&
          ModalRoute.of(context)?.isCurrent == true) {
        _ticks++;
        unawaited(_ticks.isEven ? _loadDashboard() : _loadUnread());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (active && !_active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadDashboard());
      });
    }
    _active = active;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) unawaited(_loadDashboard());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadUnread() async {
    try {
      final count = await _notifications.unreadCount();
      if (mounted) setState(() => _unread = count);
    } catch (_) {
      /* Keep the last known count; Notification Center offers retry. */
    }
  }

  Future<void> _loadDashboard() async {
    if (_fetching || !mounted) return;
    _fetching = true;
    await _loadUnread();
    if (!mounted) {
      _fetching = false;
      return;
    }
    try {
      final userId = context.read<AuthService>().currentUserId;
      if (userId == null) throw StateError('AUTHENTICATION_REQUIRED');
      final values = await Future.wait<dynamic>([
        context.read<ProfileService>().getProfileByUserId(userId),
        _assessment.getAssignedActivities(),
        _assessment.getReleasedResults(),
        _assessment.getAssignmentStatuses(),
      ]);
      if (mounted) {
        setState(() {
          _profile = values[0] as ProfileModel?;
          _assignments = values[1] as List<AssignedActivity>;
          _results = values[2] as List<ReleasedAssessmentResult>;
          _statuses = values[3] as Map<String, String>;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = MissionContentData.homeFailed);
    } finally {
      _fetching = false;
      if (mounted)
        setState(() {
          _loading = false;
          _refreshToken++;
        });
    }
  }

  String get _firstName {
    final name = _profile?.fullName.trim() ?? '';
    return name.isEmpty
        ? MissionContentData.homeLearner
        : name.split(RegExp(r'\s+')).first;
  }

  Future<void> _openClassWork(ClassWorkDestination destination) async {
    final tab = destination.classWorkTab;
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => tab == null
                ? const LearnerQuizzesScreen()
                : MissionsScreen(initialTab: tab)));
    if (mounted) await _loadDashboard();
  }

  Future<void> _openTechnical(AssignedActivity a) async {
    try {
      final page = await LearnerActivityNavigation.resolve(LearnerNotification(
          id: a.id,
          title: a.title,
          message: '',
          createdAt: DateTime.now(),
          isRead: true,
          activityType: 'technical',
          activityId: a.id,
          classId: a.classId));
      if (mounted) {
        await Navigator.push(
            context, MaterialPageRoute<void>(builder: (_) => page));
      }
      if (mounted) await _loadDashboard();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(MissionContentData.activityNoAccess)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTheme.backgroundOffWhite,
        body: SafeArea(
            child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: _loading
                ? const LearnerLoadingView(
                    label: MissionContentData.homeLoading)
                : RefreshIndicator(
                    onRefresh: _loadDashboard,
                    child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        // The shell reserves bottom navigation height; leave comfortable
                        // scroll clearance for standalone routes and device gesture insets.
                        padding: const EdgeInsets.only(bottom: 32),
                        children: [
                          AppTopBar(
                              title:
                                  '${MissionContentData.homeGreeting}, $_firstName',
                              subtitle: MissionContentData.homeSubtitle,
                              notificationCount: _unread,
                              avatarLabel: _firstName,
                              onNotificationTap: () async {
                                await Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const NotificationsScreen()));
                                if (mounted) await _loadDashboard();
                              },
                              onSettingsTap: () async {
                                await Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const SettingsScreen()));
                                if (mounted) await _loadDashboard();
                              }),
                          if (_error != null)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Text(_error!)),
                          Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 0, 20, 16),
                              child: HomeClassWorkLinks(
                                  onOpen: _openClassWork)),
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: AssignedClassActivities(
                                  dashboard: true,
                                  refreshToken: _refreshToken,
                                  technical: _assignments,
                                  technicalStatuses: _statuses,
                                  onTechnicalOpen: _openTechnical)),
                          if (_results.isNotEmpty)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  title: Text(
                                      '${MissionContentData.homeReleased} (${_results.length})'),
                                  children: [
                                    for (final result in _results.take(5))
                                      ListTile(
                                        title: Text(result.assignmentTitle),
                                        subtitle: Text(
                                            '${result.classTitle} · ${result.outcome.replaceAll('_', ' ')}'),
                                        trailing: result.percentage == null
                                            ? null
                                            : Text('${result.percentage}%'),
                                      )
                                  ],
                                )),
                          const Padding(
                              padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                              child: SupplementaryPlatformNotice()),
                        ])),
          ),
        )),
      );
}
