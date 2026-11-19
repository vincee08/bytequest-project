import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/learner_ui.dart';
import '../data/homework_content_data.dart';
import '../data/mission_content_data.dart';
import '../models/assigned_activity_model.dart';
import '../models/home_activity_item.dart';
import '../models/homework_model.dart';
import '../models/learner_quiz_model.dart';
import '../services/homework_service.dart';
import '../services/learner_quiz_service.dart';
import '../services/learner_realtime_coordinator.dart';
import '../screens/homework/homework_details_screen.dart';
import '../screens/homework/homework_list_screen.dart';
import '../screens/quizzes/quiz_details_screen.dart';
import '../screens/quizzes/quiz_result_screen.dart';

/// Shared compact class lists and Home dashboard. Official counts stay separate.
class AssignedClassActivities extends StatefulWidget {
  const AssignedClassActivities(
      {super.key,
      this.classId,
      this.quizService,
      this.homeworkService,
      this.dashboard = false,
      this.refreshToken = 0,
      this.technical = const [],
      this.technicalStatuses = const {},
      this.onTechnicalOpen});
  final String? classId;
  final LearnerQuizService? quizService;
  final HomeworkService? homeworkService;
  final bool dashboard;
  final int refreshToken;
  final List<AssignedActivity> technical;
  final Map<String, String> technicalStatuses;
  final Future<void> Function(AssignedActivity)? onTechnicalOpen;
  @override
  State<AssignedClassActivities> createState() =>
      _AssignedClassActivitiesState();
}

class _AssignedClassActivitiesState extends State<AssignedClassActivities>
    with
        LearnerRealtimeRefreshMixin<AssignedClassActivities>,
        WidgetsBindingObserver {
  List<LearnerQuizSummary> _quizzes = [];
  List<HomeworkAssignment> _homework = [];
  bool _loading = true,
      _loadingNow = false,
      _quizError = false,
      _homeworkError = false;
  int _filter = 0;
  Timer? _poll;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  @override
  Set<LearnerRealtimeDomain> get realtimeDomains => const {
        LearnerRealtimeDomain.quizzes,
        LearnerRealtimeDomain.learning,
        LearnerRealtimeDomain.classes
      };
  @override
  Future<void> refreshFromRealtime() => _load();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_lifecycle == AppLifecycleState.resumed &&
          mounted &&
          TickerMode.valuesOf(context).enabled &&
          ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_load());
      }
    });
  }

  @override
  void didUpdateWidget(AssignedClassActivities oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loadingNow) return;
    _loadingNow = true;
    await Future.wait([
      () async {
        try {
          final data = await (widget.quizService ?? LearnerQuizService())
              .getAvailableQuizzes();
          if (mounted) {
            setState(() {
              _quizzes = data
                  .where((q) =>
                      widget.classId == null || q.classId == widget.classId)
                  .toList();
              _quizError = false;
            });
          }
        } catch (_) {
          if (mounted) {
            setState(() {
              _quizError = true;
              _quizzes = [];
            });
          }
        }
      }(),
      () async {
        try {
          final data = await (widget.homeworkService ?? HomeworkService())
              .getAssignments(classId: widget.classId);
          if (mounted) {
            setState(() {
              _homework = data;
              _homeworkError = false;
            });
          }
        } catch (_) {
          if (mounted) {
            setState(() {
              _homeworkError = true;
              _homework = [];
            });
          }
        }
      }(),
    ]);
    _loadingNow = false;
    if (mounted) setState(() => _loading = false);
  }

  List<HomeActivityItem> get _items => [
        ..._quizzes.map(HomeActivityItem.quiz),
        ..._homework.map(HomeActivityItem.homework),
        if (widget.dashboard)
          ...widget.technical.map((a) => HomeActivityItem.technical(
              a, widget.technicalStatuses[a.id], DateTime.now().toUtc())),
      ]..sort(HomeActivityItem.prioritize);
  @override
  Widget build(BuildContext context) {
    final items = _items;
    final narrow = MediaQuery.sizeOf(context).width < 640;
    final previewCount = narrow ? 2 : 3;
    final attention = items.where((a) => a.outstanding).toList();
    final shown = items
        .where((a) => switch (_filter) {
              1 => a.outstanding,
              2 => a.kind == HomeActivityKind.quiz,
              3 => a.kind == HomeActivityKind.homework,
              4 => a.kind == HomeActivityKind.technical,
              5 => a.completed,
              _ => true,
            })
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.dashboard) ...[
        LearnerSurface(
            padding: const EdgeInsets.all(14),
            color: AppTheme.softBlueAccent,
            child: Wrap(spacing: 16, runSpacing: 8, children: [
              Text(
                  MissionContentData.homeSummary(_quizzes.length,
                      _homework.length, widget.technical.length),
                  style: AppTheme.labelLarge),
              Text('${MissionContentData.homeToDo}: ${attention.length}',
                  style: AppTheme.labelLarge),
            ])),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
              child: narrow
                  ? DropdownButtonFormField<int>(
                      key: ValueKey(_filter),
                      initialValue: _filter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: MissionContentData.homeActivityView),
                      items: [
                        for (final (index, label) in _filters.indexed)
                          DropdownMenuItem(value: index, child: Text(label))
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _filter = value);
                      },
                    )
                  : Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final (index, label) in _filters.indexed)
                        ChoiceChip(
                            label: Text(label),
                            selected: _filter == index,
                            onSelected: (_) => setState(() => _filter = index)),
                    ])),
          const SizedBox(width: 8),
          IconButton(
              tooltip: MissionContentData.classActivitiesRetry,
              onPressed: _loadingNow ? null : _load,
              icon: const Icon(Icons.refresh)),
        ]),
        const SizedBox(height: 16),
      ],
      if (!widget.dashboard)
        Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
                onPressed: _loadingNow ? null : _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text(MissionContentData.classActivitiesRetry))),
      if (_loading)
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text(MissionContentData.classActivitiesLoading))
      else ...[
        if (widget.dashboard && _filter == 0) ...[
          Semantics(
              header: true,
              container: true,
              child: LearnerSectionHeader(
                  title: MissionContentData.homeAttention,
                  actionLabel:
                      attention.length > 1 ? MissionContentData.homeToDo : null,
                  onAction: attention.length > 1
                      ? () => setState(() => _filter = 1)
                      : null)),
          const SizedBox(height: 8),
          if (attention.isEmpty)
            const Text(MissionContentData.homeAttentionEmpty)
          else
            for (final item in attention.take(narrow ? 1 : 2))
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                      color: AppTheme.cardWhite,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          leading: Icon(_icon(item.kind),
                              color: AppTheme.primaryBlue),
                          title: Text(item.title, style: AppTheme.labelLarge),
                          subtitle: Text(
                              '${_name(item.kind)} · ${MissionContentData.homeworkDue(manilaDate(item.deadline))}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _open(item)))),
          const SizedBox(height: 16),
        ],
        for (final kind in HomeActivityKind.values)
          if ((kind != HomeActivityKind.technical || widget.dashboard) &&
              (_filter < 2 || _filter == 5 || _filter == kind.index + 2)) ...[
            _heading(
                '${_section(kind)} (${items.where((a) => a.kind == kind).length})'),
            if (kind == HomeActivityKind.homework && _homework.isNotEmpty)
              Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                      style:
                          TextButton.styleFrom(minimumSize: const Size(48, 48)),
                      onPressed: _openHomeworkList,
                      icon: const Icon(Icons.filter_list, size: 18),
                      label: const Text(HomeworkContentData.listAction))),
            const SizedBox(height: 10),
            if (kind == HomeActivityKind.quiz && _quizError ||
                kind == HomeActivityKind.homework && _homeworkError)
              const Text(MissionContentData.classActivitiesUnavailable)
            else if (!shown.any((a) => a.kind == kind))
              Text(_filter == 1 || _filter == 5
                  ? MissionContentData.homeNoMatch
                  : kind == HomeActivityKind.quiz
                      ? MissionContentData.quizzesEmpty
                      : kind == HomeActivityKind.homework
                          ? MissionContentData.homeworkEmpty
                          : MissionContentData.technicalEmpty)
            else
              ResponsiveActivityGrid(
                  children: (widget.dashboard && _filter == 0
                          ? shown
                              .where((a) => a.kind == kind)
                              .take(previewCount)
                          : shown.where((a) => a.kind == kind))
                      .map((a) =>
                          CompactActivityCard(item: a, onOpen: () => _open(a)))
                      .toList()),
            if (widget.dashboard &&
                _filter == 0 &&
                shown.where((a) => a.kind == kind).length > previewCount)
              TextButton(
                  onPressed: () => setState(() => _filter = kind.index + 2),
                  child: const Text(MissionContentData.homeViewAll)),
            const SizedBox(height: 20),
          ],
      ],
    ]);
  }

  static const _filters = [
    MissionContentData.homeAll,
    MissionContentData.homeToDo,
    MissionContentData.homeQuizzes,
    MissionContentData.homeHomework,
    MissionContentData.homeTechnical,
    MissionContentData.homeCompleted
  ];

  Widget _heading(String title) => Semantics(
      header: true, container: true, child: LearnerSectionHeader(title: title));
  // Homework organised by COC and mission (filter chips).
  Future<void> _openHomeworkList() async {
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => HomeworkListScreen(
                service: widget.homeworkService,
                initial: _homework,
                classId: widget.classId)));
    if (mounted) await _load();
  }
  String _section(HomeActivityKind kind) => switch (kind) {
        HomeActivityKind.quiz => MissionContentData.assignedQuizzes,
        HomeActivityKind.homework => MissionContentData.homeworkAssignments,
        HomeActivityKind.technical => MissionContentData.technicalActivities,
      };
  Future<void> _open(HomeActivityItem item) async {
    if (!item.enabled) return;
    final source = item.source;
    if (source is AssignedActivity) {
      await widget.onTechnicalOpen?.call(source);
    } else {
      await Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => source is HomeworkAssignment
                  ? HomeworkDetailsScreen(assignment: source)
                  : (source as LearnerQuizSummary).state ==
                              LearnerQuizState.completed &&
                          source.attemptId != null
                      ? QuizResultScreen(attemptId: source.attemptId!)
                      : QuizDetailsScreen(quiz: source)));
    }
    if (mounted) await _load();
  }
}

String _name(HomeActivityKind kind) => switch (kind) {
      HomeActivityKind.quiz => MissionContentData.homeQuizzes,
      HomeActivityKind.homework => MissionContentData.homeHomework,
      HomeActivityKind.technical => MissionContentData.technicalActivities,
    };
IconData _icon(HomeActivityKind kind) => switch (kind) {
      HomeActivityKind.quiz => Icons.quiz_outlined,
      HomeActivityKind.homework => Icons.assignment_outlined,
      HomeActivityKind.technical => Icons.build_outlined,
    };

class ResponsiveActivityGrid extends StatelessWidget {
  const ResponsiveActivityGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        // Intrinsic card height follows large text. No nested scrolling or clipping.
        final columns = box.maxWidth >= 960
            ? 3
            : box.maxWidth >= 640
                ? 2
                : 1;
        final width =
            ((box.maxWidth - (columns - 1) * 12) / columns).clamp(0.0, 460.0);
        return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: children
                .map((card) => SizedBox(width: width, child: card))
                .toList());
      });
}

class CompactActivityCard extends StatelessWidget {
  const CompactActivityCard(
      {super.key, required this.item, required this.onOpen});
  final HomeActivityItem item;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Semantics(
      container: true,
      child: LearnerSurface(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_icon(item.kind), size: 20, color: AppTheme.primaryBlue),
              const SizedBox(width: 8),
              Expanded(child: Text(item.title, style: AppTheme.titleMedium))
            ]),
            const SizedBox(height: 6),
            Text(item.classTitle, style: AppTheme.bodySmall),
            Text(MissionContentData.homeworkDue(manilaDate(item.deadline)),
                style: AppTheme.bodySmall),
            const SizedBox(height: 8),
            Text(item.status,
                style:
                    AppTheme.labelMedium.copyWith(color: AppTheme.primaryBlue)),
            if (item.lateness != null)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(item.lateness!, style: AppTheme.bodySmall)),
            const SizedBox(height: 10),
            OutlinedButton(
                onPressed: item.enabled ? onOpen : null,
                style:
                    OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                child: Text(item.action)),
          ])));
}
