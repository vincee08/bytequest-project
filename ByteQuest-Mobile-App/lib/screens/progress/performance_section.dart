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
/// foreground and its route not covered); changes that arrive while hidden are
/// fetched once it is visible again. Mount it inside a scrollable parent.
///
/// [compact] is the Progress screen's slot variant: no title (the screen
/// supplies the section header), only score averages and criterion outcomes,
/// because that screen already shows learning progress, practice counts,
/// released results, quiz scores and homework.
class PerformanceSection extends StatefulWidget {
  const PerformanceSection({super.key, this.service, this.compact = false});

  /// Injected in tests; defaults to the Supabase-backed service.
  final PerformanceService? service;

  final bool compact;

  static const pollInterval = Duration(seconds: 30);
  static const realtimeDebounce = Duration(milliseconds: 350);

  @override
  State<PerformanceSection> createState() => _PerformanceSectionState();
}

class _PerformanceSectionState extends State<PerformanceSection>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin<PerformanceSection> {
  late final PerformanceService _service = widget.service ?? PerformanceService();
  PerformanceSnapshot? _snapshot;
  bool _loading = true;
  bool _failed = false;
  bool _foreground = true;
  bool _tickerEnabled = true;

  /// Set by a realtime change, or once the section has been hidden for a
  /// poll interval; the section refetches when it is visible again.
  bool _refreshPending = false;
  int _generation = 0;
  StreamSubscription<void>? _changes;
  Timer? _poll;
  Timer? _hiddenTimer;
  Timer? _debounce;

  bool get _visible => _foreground && _tickerEnabled;

  /// Keeps the loaded section (and its subscription) when a lazy list such as
  /// the Progress screen scrolls it out of view.
  @override
  bool get wantKeepAlive => true;

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
    final wasVisible = _visible;
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (_visible && !wasVisible && _refreshPending) unawaited(_load());
    _syncPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _foreground;
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && !wasForeground) {
      // Realtime events can be missed in the background: refetch on return,
      // or as soon as the section is shown if its tab is not selected.
      if (_visible) {
        unawaited(_load());
      } else {
        _refreshPending = true;
      }
    }
    _syncPolling();
  }

  void _syncPolling() {
    if (_visible) {
      _hiddenTimer?.cancel();
      _hiddenTimer = null;
      _poll ??= Timer.periodic(PerformanceSection.pollInterval, (_) => unawaited(_load()));
    } else {
      _poll?.cancel();
      _poll = null;
      _hiddenTimer ??= Timer(PerformanceSection.pollInterval, () => _refreshPending = true);
    }
  }

  void _queueRefresh() {
    if (!_visible) {
      // Fetch once when the section is visible again instead of in the background.
      _refreshPending = true;
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(PerformanceSection.realtimeDebounce, () {
      if (_visible) {
        unawaited(_load());
      } else {
        _refreshPending = true;
      }
    });
  }

  Future<void> _load({bool initial = false}) async {
    _refreshPending = false;
    final generation = ++_generation;
    if (!initial && mounted) setState(() => _loading = true);
    try {
      // Only the full section lists quizzes by title; both calls run together.
      final titles = widget.compact ? null : _quizTitles();
      var snapshot = await _service.fetchMyPerformance();
      if (titles != null) snapshot = snapshot.withQuizTitles(await titles);
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

  /// Titles are labels only: when they cannot be read the rows keep their
  /// fallback label and the section still shows every score.
  Future<Map<String, String>> _quizTitles() async {
    try {
      return await _service.fetchQuizTitles();
    } catch (error) {
      debugPrint('Quiz titles unavailable: $error');
      return const {};
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _hiddenTimer?.cancel();
    _debounce?.cancel();
    final changes = _changes;
    if (changes != null) unawaited(changes.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final snapshot = _snapshot;
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppTheme.simulationTransitionDuration,
      child: KeyedSubtree(
        key: ValueKey(snapshot == null ? (_loading ? 'loading' : 'error') : 'data'),
        child: snapshot == null
            ? (_loading
                ? _PerformanceLoading(compact: widget.compact)
                : _PerformanceError(compact: widget.compact, onRetry: () => unawaited(_load())))
            : widget.compact
                ? _CompactContent(
                    snapshot: snapshot,
                    refreshing: _loading,
                    stale: _failed,
                    onRefresh: () => unawaited(_load()),
                  )
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

/// Progress-screen slot variant: summary tiles and criterion outcomes only.
class _CompactContent extends StatelessWidget {
  const _CompactContent({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(updated: updated, refreshing: refreshing, onRefresh: onRefresh, compact: true),
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
        const SizedBox(height: 10),
        PerformanceSummaryGrid(snapshot: snapshot),
        if (!snapshot.hasScoredWork) ...[
          const SizedBox(height: 10),
          Text(PerformanceContentData.compactEmpty, style: AppTheme.bodySmall.copyWith(color: AppTheme.textMedium)),
        ],
        if (snapshot.competency.isNotEmpty) ...[
          const SizedBox(height: 12),
          PerformanceCompetencyCard(outcomes: snapshot.competency),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.updated, required this.refreshing, required this.onRefresh, this.compact = false});

  final String updated;
  final bool refreshing;
  final VoidCallback onRefresh;

  /// The Progress screen supplies the section title in compact mode.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!compact) ...[
                Semantics(
                  header: true,
                  child: Text(PerformanceContentData.sectionTitle, style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 3),
              ],
              Text(compact ? PerformanceContentData.compactSubtitle : PerformanceContentData.sectionSubtitle, style: AppTheme.bodySmall),
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
  const _PerformanceLoading({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: PerformanceContentData.loadingLabel,
      liveRegion: true,
      child: Padding(
        padding: compact ? EdgeInsets.zero : const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!compact) ...[
                Text(PerformanceContentData.sectionTitle, style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
              ],
              for (final height in compact ? const [72.0, 72.0] : const [132.0, 96.0, 96.0]) ...[
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
  const _PerformanceError({required this.onRetry, this.compact = false});

  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: compact ? EdgeInsets.zero : const EdgeInsets.fromLTRB(20, 8, 20, 16),
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
