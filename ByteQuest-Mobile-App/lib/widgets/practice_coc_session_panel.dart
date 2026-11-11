import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/mission_content_data.dart';
import '../services/auth_service.dart';
import '../services/practice_coc_session_service.dart';

/// Shared learner-facing COC countdown. The mission screen enforces the same
/// checkpoint separately, so hiding this panel cannot extend a session.
class PracticeCocSessionPanel extends StatefulWidget {
  const PracticeCocSessionPanel(
      {super.key,
      required this.cocId,
      this.onSessionChanged,
      this.showStartControl = true,
      this.userId});

  final String cocId;
  final ValueChanged<PracticeCocSession>? onSessionChanged;
  final bool showStartControl;
  final String? userId;

  @override
  State<PracticeCocSessionPanel> createState() =>
      _PracticeCocSessionPanelState();
}

class _PracticeCocSessionPanelState extends State<PracticeCocSessionPanel>
    with WidgetsBindingObserver {
  final _service = const PracticeCocSessionService();
  PracticeCocSession? _session;
  Timer? _ticker;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  DateTime? _lastCheckpoint;
  bool _wasCurrentRoute = true;
  int _loadGeneration = 0;

  String? get _userId => widget.userId ?? AuthService().currentUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant PracticeCocSessionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cocId != widget.cocId) unawaited(_load());
  }

  Future<void> _load() async {
    if (_saving) return;
    final generation = ++_loadGeneration;
    final userId = _userId;
    if (userId == null) return;
    try {
      final session = await _service.load(userId, widget.cocId);
      if (!mounted || generation != _loadGeneration) return;
      if (mounted)
        setState(() {
          _session = session;
          _loading = false;
          _error = null;
        });
      if (mounted && session != null) widget.onSessionChanged?.call(session);
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      if (mounted)
        setState(() {
          _loading = false;
          _error = MissionContentData.practiceTimerSaveFailed;
        });
    }
  }

  void _tick() {
    if (!mounted) return;
    if (ModalRoute.isCurrentOf(context) != true) {
      _wasCurrentRoute = false;
      return;
    }
    if (!_wasCurrentRoute) {
      _wasCurrentRoute = true;
      unawaited(_load());
    }
    if (_session == null) return;
    final now = DateTime.now().toUtc();
    final session = _session!;
    setState(() => _session = session.observedAt(now));
    if (_lastCheckpoint == null ||
        now.difference(_lastCheckpoint!) >= const Duration(seconds: 15)) {
      _lastCheckpoint = now;
      final userId = _userId;
      if (userId != null) {
        unawaited(_service.checkpoint(userId, _session!).catchError((Object _) {
          if (mounted)
            setState(() => _error = MissionContentData.practiceTimerSaveFailed);
        }));
      }
    }
  }

  Future<void> _start({required bool restart}) async {
    final userId = _userId;
    if (userId == null || _saving) return;
    _loadGeneration++;
    setState(() => _saving = true);
    try {
      final session =
          await _service.start(userId, widget.cocId, restartExpired: restart);
      if (mounted)
        setState(() {
          _session = session;
          _error = null;
        });
      widget.onSessionChanged?.call(session);
    } catch (_) {
      if (mounted)
        setState(() => _error = MissionContentData.practiceTimerSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick();
    } else if (_session != null &&
        _userId != null &&
        ModalRoute.isCurrentOf(context) == true) {
      unawaited(_service.checkpoint(_userId!, _session!));
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final now = DateTime.now().toUtc();
    final expired = session?.expiredAt(now) ?? false;
    final clockChanged = session?.clockMovedBackAt(now) ?? false;
    final remaining = session?.remainingAt(now) ?? Duration.zero;
    final minutes = (remaining.inSeconds / 60).ceil();
    final warning = session == null
        ? null
        : minutes <= 1 && !expired
            ? MissionContentData.practiceTimerWarning(1)
            : minutes <= 5 && !expired
                ? MissionContentData.practiceTimerWarning(5)
                : minutes <= 10 && !expired
                    ? MissionContentData.practiceTimerWarning(10)
                    : null;
    return Semantics(
      container: true,
      liveRegion: warning != null || expired || clockChanged,
      label: clockChanged
          ? MissionContentData.practiceTimerClockChanged
          : expired
              ? MissionContentData.practiceTimerExpired
              : session == null
                  ? MissionContentData.practiceTimerNotStarted
                  : warning ??
                      '${MissionContentData.practiceTimerRemainingLabel}: ${_format(remaining)}',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.backgroundPaleBlue,
          borderRadius: AppTheme.radiusMd,
          border: Border.all(color: AppTheme.borderMedium),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(expired ? Icons.timer_off_outlined : Icons.timer_outlined,
                color: AppTheme.deepBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                session == null
                    ? MissionContentData.practiceTimerNotStarted
                    : clockChanged
                        ? MissionContentData.practiceTimerClockChanged
                        : expired
                            ? MissionContentData.practiceTimerExpired
                            : '${MissionContentData.practiceTimerRemainingLabel}: ${_format(remaining)}',
                style: AppTheme.bodySmall,
              ),
            ),
          ]),
          if (warning != null && !clockChanged) ...[
            const SizedBox(height: 6),
            Text(warning,
                style:
                    AppTheme.labelSmall.copyWith(color: AppTheme.accentOrange)),
          ],
          if (widget.showStartControl && (session == null || expired)) ...[
            const SizedBox(height: 8),
            Text(MissionContentData.practiceTimerProvisional,
                style: AppTheme.caption),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed:
                  _loading || _saving ? null : () => _start(restart: expired),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(expired
                  ? MissionContentData.practiceTimerRestart
                  : MissionContentData.practiceTimerStart),
            ),
          ],
          if (_error != null)
            Text(_error!,
                style: AppTheme.bodySmall.copyWith(color: AppTheme.errorRed)),
        ]),
      ),
    );
  }

  static String _format(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 359999);
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final rest = seconds % 60;
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}'
        : '$minutes:${rest.toString().padLeft(2, '0')}';
  }
}

class PracticeCocTimeLabel extends StatelessWidget {
  const PracticeCocTimeLabel(
      {super.key, required this.session, required this.now});

  final PracticeCocSession session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final remaining = session.remainingAt(now);
    final minutes = (remaining.inSeconds / 60).ceil();
    final compact = MediaQuery.sizeOf(context).height < 500 &&
        MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final warning = session.expiredAt(now)
        ? MissionContentData.practiceTimerExpired
        : minutes <= 1
            ? MissionContentData.practiceTimerWarning(1)
            : minutes <= 5
                ? MissionContentData.practiceTimerWarning(5)
                : minutes <= 10
                    ? MissionContentData.practiceTimerWarning(10)
                    : null;
    return Semantics(
      liveRegion: warning != null,
      label: warning ??
          '${MissionContentData.practiceTimerRemainingLabel}: ${_PracticeCocSessionPanelState._format(remaining)}',
      child: Container(
        key: const ValueKey('practice-coc-time-label'),
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: warning == null
            ? AppTheme.backgroundPaleBlue
            : AppTheme.surfaceMuted,
        child: Row(children: [
          Icon(Icons.timer_outlined,
              color:
                  warning == null ? AppTheme.deepBlue : AppTheme.accentOrange,
              size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              session.expiredAt(now)
                  ? MissionContentData.practiceTimerExpiredShort
                  : warning == null
                      ? compact
                          ? MissionContentData.practiceTimerCompactLabel
                          : MissionContentData.practiceTimerRemainingLabel
                      : MissionContentData.practiceTimerWarningShort(
                          minutes <= 1
                              ? 1
                              : minutes <= 5
                                  ? 5
                                  : 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySmall.copyWith(
                  color: warning == null
                      ? AppTheme.textDark
                      : AppTheme.accentOrange),
            ),
          ),
          const SizedBox(width: 8),
          Text(_PracticeCocSessionPanelState._format(remaining),
              style: AppTheme.labelMedium.copyWith(
                  color: warning == null
                      ? AppTheme.deepBlue
                      : AppTheme.accentOrange,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}
