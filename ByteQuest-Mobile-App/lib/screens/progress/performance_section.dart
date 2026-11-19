import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../data/performance_content_data.dart';
import '../../models/performance_model.dart';
import '../../services/performance_service.dart';
import 'performance_widgets.dart';

/// Self-contained learner Performance section (Objective 6) built on
/// `get_my_performance()`: learning progress, competency per released
/// criterion, quiz and homework scores, released assessment results and
/// practice runs. It refetches on Supabase Realtime changes to the learner's
/// own rows and polls every [pollInterval] while it is visible (app in the
/// foreground and its route not covered). Mount it inside a scrollable parent.
class PerformanceSection extends StatefulWidget {
  const PerformanceSection({super.key, this.service});

  /// Injected in tests; defaults to the Supabase-backed service.
  final PerformanceService? service;

  static const pollInterval = Duration(seconds: 30);
  static const realtimeDebounce = Duration(milliseconds: 350);

  @override
  State<PerformanceSection> createState() => _PerformanceSectionState();
}

class _PerformanceSectionState extends State<PerformanceSection> with WidgetsBindingObserver {
  late final PerformanceService _service = widget.service ?? PerformanceService();
  PerformanceSnapshot? _snapshot;
  bool _loading = true;
  bool _failed = false;
  bool _foreground = true;
  bool _tickerEnabled = true;
  int _generation = 0;
  StreamSubscription<void>? _changes;
  Timer? _poll;
  Timer? _debounce;

  bool get _visible => _foreground && _tickerEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _changes = _service.watchChanges().listen((_) => _queueRefresh(), onError: (Object _) {});
    unawaited(_load(initial: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Routes covered by an opaque route disable tickers; treat that as hidden.
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _foreground;
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && !wasForeground) unawaited(_load());
    _syncPolling();
  }

  void _syncPolling() {
    if (_visible) {
      _poll ??= Timer.periodic(PerformanceSection.pollInterval, (_) => unawaited(_load()));
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  void _queueRefresh() {
    _debounce?.cancel();
    _debounce = Timer(PerformanceSection.realtimeDebounce, () => unawaited(_load()));
  }

  Future<void> _load({bool initial = false}) async {
    final generation = ++_generation;
    if (!initial && mounted) setState(() => _loading = true);
    try {
      final snapshot = await _service.fetchMyPerformance();
      if (!mounted || generation != _generation) return;
      setState(() {
        _snapshot = snapshot;
        _failed = false;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Performance load failed: $error');
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _debounce?.cancel();
    final changes = _changes;
    if (changes != null) unawaited(changes.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppTheme.simulationTransitionDuration,
      child: KeyedSubtree(
        key: ValueKey(snapshot == null ? (_loading ? 'loading' : 'error') : 'data'),
        child: snapshot == null
            ? (_loading ? const _PerformanceLoading() : _PerformanceError(onRetry: () => unawaited(_load())))
            : _PerformanceContent(
                snapshot: snapshot,
                refreshing: _loading,
                stale: _failed,
                onRefresh: () => unawaited(_load()),
              ),
      ),
    );
  }
}

class _PerformanceContent extends StatelessWidget {
  const _PerformanceContent({
    required this.snapshot,
    required this.refreshing,
    required this.stale,
    required this.onRefresh,
  });

  final PerformanceSnapshot snapshot;
  final bool refreshing;
  final bool stale;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final updated = PerformanceContentData.updatedAt(DateFormat('HH:mm').format(snapshot.updatedAt.toLocal()));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(updated: updated, refreshing: refreshing, onRefresh: onRefresh),
          if (stale) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: LearnerSurface(
                color: AppTheme.backgroundPaleBlue,
                padding: const EdgeInsets.all(12),
                child: Text(PerformanceContentData.staleNotice, style: AppTheme.bodySmall.copyWith(color: AppTheme.textDark)),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (!snapshot.hasActivity) ...[
            LearnerSurface(
              semanticLabel: '${PerformanceContentData.emptyTitle}. ${PerformanceContentData.emptyMessage}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.insights_outlined, color: AppTheme.primaryBlue),
                  const SizedBox(height: 8),
                  Text(PerformanceContentData.emptyTitle, style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(PerformanceContentData.emptyMessage, style: AppTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 12),
            PerformanceProgressCard(progress: snapshot.progress),
          ] else ...[
            PerformanceProgressCard(progress: snapshot.progress),
            const SizedBox(height: 12),
            PerformanceCompetencyCard(outcomes: snapshot.competency),
            const SizedBox(height: 12),
            PerformanceScoresCard(quizzes: snapshot.quizzes, homework: snapshot.homework),
            const SizedBox(height: 12),
            PerformanceAssessmentsCard(assessments: snapshot.assessments),
            const SizedBox(height: 12),
            PerformancePracticeCard(practice: snapshot.practice),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.updated, required this.refreshing, required this.onRefresh});

  final String updated;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(PerformanceContentData.sectionTitle, style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 3),
              Text(PerformanceContentData.sectionSubtitle, style: AppTheme.bodySmall),
              const SizedBox(height: 3),
              Semantics(
                liveRegion: true,
                child: Text(updated, style: AppTheme.captionSmall.copyWith(color: AppTheme.textMedium, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: refreshing ? null : onRefresh,
          tooltip: PerformanceContentData.refreshLabel,
          constraints: const BoxConstraints(minWidth: AppTheme.minimumTapTarget, minHeight: AppTheme.minimumTapTarget),
          icon: refreshing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: PerformanceContentData.refreshLabel),
                )
              : const Icon(Icons.refresh_rounded, semanticLabel: PerformanceContentData.refreshLabel),
        ),
      ],
    );
  }
}

class _PerformanceLoading extends StatelessWidget {
  const _PerformanceLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: PerformanceContentData.loadingLabel,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(PerformanceContentData.sectionTitle, style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              for (final height in const [132.0, 96.0, 96.0]) ...[
                Container(
                  height: height,
                  decoration: BoxDecoration(color: AppTheme.surfaceMuted, borderRadius: AppTheme.radiusLg),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PerformanceError extends StatelessWidget {
  const _PerformanceError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: LearnerSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(PerformanceContentData.errorTitle, style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 4),
            Text(PerformanceContentData.errorMessage, style: AppTheme.bodySmall),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTheme.minimumTapTarget),
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(PerformanceContentData.retryLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
