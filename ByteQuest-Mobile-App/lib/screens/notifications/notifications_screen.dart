import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../data/mission_content_data.dart';
import '../../models/homework_model.dart';
import '../../models/learner_notification.dart';
import '../../services/learner_notification_service.dart';
import '../../services/learner_activity_navigation.dart';
import '../../services/learner_realtime_coordinator.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.service, this.resolveActivity});
  final LearnerNotificationService? service;
  final Future<Widget> Function(LearnerNotification)? resolveActivity;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with
        LearnerRealtimeRefreshMixin<NotificationsScreen>,
        WidgetsBindingObserver {
  late final _service = widget.service ?? LearnerNotificationService();
  List<LearnerNotification> _items = [];
  bool _loading = true, _fetching = false, _busy = false, _unreadOnly = false;
  bool _more = false;
  int _unread = 0;
  String? _error;
  Timer? _poll;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  @override
  Set<LearnerRealtimeDomain> get realtimeDomains =>
      const {LearnerRealtimeDomain.notifications};
  @override
  Future<void> refreshFromRealtime() => _refresh();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_lifecycle == AppLifecycleState.resumed &&
          mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_refresh());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool more = false}) async {
    if (_fetching) return;
    _fetching = true;
    try {
      // Refresh every loaded page so polling does not discard older rows or
      // their scroll position. Each bounded request stays below API row limits.
      final pages = more ? 1 : (_items.length / 50).ceil().clamp(1, 1000000);
      final rows = <LearnerNotification>[];
      for (var page = 0; page < pages; page++) {
        final batch = await _service.fetch(
            offset: more ? _items.length : page * 50, unreadOnly: _unreadOnly);
        rows.addAll(batch);
        if (batch.length < 50) break;
      }
      final count = await _service.unreadCount();
      if (mounted) {
        setState(() {
          _items = {
            for (final n in [
              ...(more ? _items : <LearnerNotification>[]),
              ...rows
            ])
              n.id: n
          }.values.toList();
          _more = rows.isNotEmpty && rows.length % 50 == 0;
          _unread = count;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = MissionContentData.notificationsFailed);
      }
    } finally {
      _fetching = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _read({LearnerNotification? item, bool open = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (item == null) {
        await _service.markAllRead();
      } else {
        await _service.markRead(item.id);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(MissionContentData.notificationsSaveFailed)));
      }
      return;
    }
    await _refresh();
    if (open && item != null && mounted) {
      try {
        final destination = await (widget.resolveActivity ??
            LearnerActivityNavigation.resolve)(item);
        if (mounted) {
          await Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => destination));
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(error is StateError &&
                      error.message == MissionContentData.activityNoAccess
                  ? MissionContentData.activityNoAccess
                  : MissionContentData.activityOpenFailed)));
        }
      }
      if (mounted) await _refresh();
    }
    if (mounted) setState(() => _busy = false);
  }

  void _filter(bool unreadOnly) {
    if (_fetching) return;
    setState(() {
      _unreadOnly = unreadOnly;
      _items = [];
      _loading = true;
    });
    unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final visible = _items.where((n) => !_unreadOnly || !n.isRead).toList();
    return Scaffold(
      backgroundColor: AppTheme.backgroundOffWhite,
      appBar: AppBar(
          title: const Text(MissionContentData.notificationsTitle),
          actions: [
            IconButton(
                tooltip: MissionContentData.notificationsRefresh,
                onPressed: _fetching ? null : _refresh,
                icon: const Icon(Icons.refresh)),
          ]),
      body: SafeArea(
          child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ChoiceChip(
                                  label: const Text(
                                      MissionContentData.notificationsAll),
                                  selected: !_unreadOnly,
                                  onSelected: (_) => _filter(false)),
                              ChoiceChip(
                                  label: Text(
                                      '${MissionContentData.notificationsUnread} ($_unread)'),
                                  selected: _unreadOnly,
                                  onSelected: (_) => _filter(true)),
                              TextButton(
                                  onPressed: _busy || _unread == 0
                                      ? null
                                      : () => _read(),
                                  child: const Text(
                                      MissionContentData.notificationsMarkAll)),
                            ]),
                        if (_error != null) ...[
                          Text(_error!,
                              style: const TextStyle(color: AppTheme.errorRed)),
                          TextButton(
                              onPressed: _refresh,
                              child: const Text(
                                  MissionContentData.notificationsRetry)),
                        ],
                        const SizedBox(height: 12),
                        if (visible.isEmpty && _error == null)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 48),
                              child: Column(children: [
                                const Icon(Icons.notifications_none_rounded,
                                    size: 36),
                                const SizedBox(height: 12),
                                Text(
                                    _unreadOnly
                                        ? MissionContentData
                                            .notificationsUnreadEmpty
                                        : MissionContentData.notificationsEmpty,
                                    style: AppTheme.titleMedium),
                                const SizedBox(height: 8),
                                const Text(
                                    MissionContentData.notificationsEmptyHelp),
                              ])),
                        for (final n in visible)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Semantics(
                                  container: true,
                                  child: Card(
                                    margin: EdgeInsets.zero,
                                    color: n.isRead
                                        ? Colors.white
                                        : AppTheme.softBlueAccent,
                                    child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(n.title,
                                                  style: AppTheme.titleMedium),
                                              const SizedBox(height: 4),
                                              Text(n.message,
                                                  style: AppTheme.bodyMedium),
                                              const SizedBox(height: 8),
                                              Text(
                                                  [
                                                    _type(n.activityType),
                                                    if (n.classTitle != null)
                                                      n.classTitle!,
                                                    n.isRead
                                                        ? MissionContentData
                                                            .notificationsRead
                                                        : MissionContentData
                                                            .notificationsUnread
                                                  ].join(' · '),
                                                  style: AppTheme.labelMedium),
                                              Text(manilaDate(n.createdAt),
                                                  style: AppTheme.bodySmall),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    if (n.hasActivity)
                                                      OutlinedButton(
                                                          onPressed: _busy
                                                              ? null
                                                              : () => _read(
                                                                  item: n,
                                                                  open: true),
                                                          child: const Text(
                                                              MissionContentData
                                                                  .notificationsOpen)),
                                                    if (!n.isRead)
                                                      TextButton(
                                                          onPressed: _busy
                                                              ? null
                                                              : () => _read(
                                                                  item: n),
                                                          child: const Text(
                                                              MissionContentData
                                                                  .notificationsMarkRead)),
                                                  ]),
                                            ])),
                                  ))),
                        if (_more)
                          TextButton(
                              onPressed:
                                  _fetching ? null : () => _refresh(more: true),
                              child: const Text(
                                  MissionContentData.notificationsMore)),
                      ]),
                ),
        ),
      )),
    );
  }

  String _type(String? type) => switch (type) {
        'quiz' => MissionContentData.homeQuizzes,
        'homework' => MissionContentData.homeHomework,
        // A released assessment result (20261120110000) is read under
        // Progress; it has no open-activity action (see hasActivity).
        'technical' || 'technical_result' =>
          MissionContentData.technicalActivities,
        _ => MissionContentData.notificationsUpdate,
      };
}
