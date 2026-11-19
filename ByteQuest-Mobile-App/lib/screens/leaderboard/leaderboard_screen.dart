import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../data/rewards_content_data.dart';
import '../../models/rewards_model.dart';
import '../../services/learner_realtime_coordinator.dart';
import '../../services/rewards_service.dart';

/// Learner Rewards tab (Objective 2): server-awarded points, level progress,
/// achievements, recent points, points by category and an opt-in class
/// leaderboard. Everything shown comes from `get_learner_rewards()`; nothing
/// is computed or awarded on the device, and rewards never affect competency.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key, this.service});

  /// Injected by tests; the app uses the Supabase-backed default.
  final RewardsService? service;

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with LearnerRealtimeRefreshMixin<LeaderboardScreen> {
  late final RewardsService _service = widget.service ?? RewardsService();
  LearnerRewards? _rewards;
  bool _loading = true;
  bool _savingPreference = false;

  @override
  Set<LearnerRealtimeDomain> get realtimeDomains => const {
        LearnerRealtimeDomain.progress,
        LearnerRealtimeDomain.learning,
        LearnerRealtimeDomain.quizzes,
        LearnerRealtimeDomain.assessment,
      };

  @override
  Future<void> refreshFromRealtime() => _load(quiet: true);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Keeps the last loaded values when a refresh fails.
  Future<void> _load({bool quiet = false}) async {
    final hadValues = _rewards != null;
    if (!hadValues && !_loading && mounted) setState(() => _loading = true);
    try {
      final rewards = await _service.fetchRewards();
      if (!mounted) return;
      setState(() {
        _rewards = rewards;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Rewards load failed: $error');
      if (!mounted) return;
      setState(() => _loading = false);
      if (hadValues && !quiet) _showMessage(RewardsContentData.refreshFailed);
    }
  }

  /// Confirms the opt-in only after the server has saved it.
  Future<void> _setLeaderboardVisibility(bool visible) async {
    if (_rewards == null || _savingPreference) return;
    setState(() => _savingPreference = true);
    try {
      final saved = await _service.setLeaderboardVisibility(visible);
      if (!mounted) return;
      setState(() {
        _rewards = _rewards?.copyWith(showOnLeaderboard: saved);
        _savingPreference = false;
      });
      _showMessage(saved
          ? RewardsContentData.leaderboardShown
          : RewardsContentData.leaderboardHidden);
      unawaited(_load(quiet: true));
    } catch (error) {
      debugPrint('Leaderboard preference was not saved: $error');
      if (!mounted) return;
      setState(() => _savingPreference = false);
      _showMessage(RewardsContentData.leaderboardSaveFailed);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showInfo() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: AppTheme.cardWhite,
        builder: (context) => const _RewardsInfoSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final rewards = _rewards;
    return Scaffold(
      backgroundColor: AppTheme.backgroundOffWhite,
      body: SafeArea(
        child: rewards == null
            ? _loading
                ? const LearnerLoadingView(
                    label: RewardsContentData.loadingLabel)
                : LearnerStateView(
                    icon: Icons.cloud_off_outlined,
                    title: RewardsContentData.errorTitle,
                    message: RewardsContentData.errorMessage,
                    actionLabel: RewardsContentData.retryLabel,
                    onAction: _load,
                  )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  children: [
                    LearnerPageHeader(
                      title: RewardsContentData.title,
                      subtitle: RewardsContentData.subtitle,
                      padding: const EdgeInsets.fromLTRB(0, 18, 0, 16),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton.filledTonal(
                            onPressed: _showInfo,
                            tooltip: RewardsContentData.infoTooltip,
                            icon: const Icon(Icons.info_outline_rounded),
                          ),
                          const SizedBox(width: 4),
                          IconButton.filledTonal(
                            onPressed: () => Navigator.pushNamed(
                                context, AppRoutes.settings),
                            tooltip: RewardsContentData.settingsTooltip,
                            icon: const Icon(Icons.settings_outlined),
                          ),
                        ],
                      ),
                    ),
                    _RewardsSummary(rewards: rewards),
                    if (rewards.isNewLearner) ...[
                      const SizedBox(height: 12),
                      _NewLearnerCard(rewards: rewards),
                    ],
                    const SizedBox(height: 26),
                    LearnerSectionHeader(
                      title: RewardsContentData.achievementsTitle,
                      supportingText: RewardsContentData.achievementsProgress(
                        rewards.earnedAchievementCount,
                        rewards.achievements.length,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _AchievementGrid(achievements: rewards.achievements),
                    const SizedBox(height: 26),
                    const LearnerSectionHeader(
                        title: RewardsContentData.recentTitle),
                    const SizedBox(height: 12),
                    _RecentPoints(events: rewards.recent),
                    const SizedBox(height: 26),
                    const LearnerSectionHeader(
                      title: RewardsContentData.categoriesTitle,
                      supportingText: RewardsContentData.categoriesSupport,
                    ),
                    const SizedBox(height: 12),
                    _PointCategories(categories: rewards.pointsByCategory),
                    const SizedBox(height: 26),
                    const LearnerSectionHeader(
                      title: RewardsContentData.leaderboardTitle,
                      supportingText: RewardsContentData.leaderboardSupport,
                    ),
                    const SizedBox(height: 12),
                    _LeaderboardCard(
                      rewards: rewards,
                      saving: _savingPreference,
                      onChanged: _setLeaderboardVisibility,
                    ),
                    const SizedBox(height: 20),
                    _SeparationNote(onShowInfo: _showInfo),
                  ],
                ),
              ),
      ),
    );
  }
}

class _RewardsSummary extends StatelessWidget {
  const _RewardsSummary({required this.rewards});

  final LearnerRewards rewards;

  @override
  Widget build(BuildContext context) {
    final level = rewards.level;
    final remaining = level.pointsToNextLevel(rewards.points);
    final nextLevel = level.nextLevel;
    final onNavy = Colors.white.withValues(alpha: .86);
    return Semantics(
      container: true,
      label: RewardsContentData.summarySemantics(
          rewards.points, level.level, level.title, remaining, nextLevel),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.navy,
          borderRadius: AppTheme.radiusXl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    RewardsContentData.totalPointsLabel,
                    style: AppTheme.labelMedium.copyWith(color: onNavy),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${rewards.points}',
                    style: AppTheme.displayMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .12),
                      borderRadius: AppTheme.badgeRadius,
                    ),
                    child: Text(
                      RewardsContentData.levelLabel(level.level, level.title),
                      style: AppTheme.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _LevelProgressBar(
              value: level.progressFraction,
              semanticLabel: RewardsContentData.levelProgressSemantics(
                  level.level, level.title),
            ),
            const SizedBox(height: 8),
            ExcludeSemantics(
              child: Text(
                remaining == null || nextLevel == null
                    ? RewardsContentData.topLevelReached
                    : RewardsContentData.pointsToNextLevel(
                        remaining, nextLevel),
                style: AppTheme.bodySmall.copyWith(color: onNavy),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelProgressBar extends StatelessWidget {
  const _LevelProgressBar({required this.value, required this.semanticLabel});

  final double value;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final normalized = value.clamp(0.0, 1.0);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      label: semanticLabel,
      value: '${(normalized * 100).round()} percent',
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          tween: Tween(begin: 0, end: normalized),
          builder: (context, progress, _) => LinearProgressIndicator(
            key: const ValueKey('rewards-level-progress'),
            value: progress,
            minHeight: 8,
            color: AppTheme.skyBlue,
            backgroundColor: Colors.white.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _NewLearnerCard extends StatelessWidget {
  const _NewLearnerCard({required this.rewards});

  final LearnerRewards rewards;

  @override
  Widget build(BuildContext context) {
    final points = rewards.pointsFor('practice_mission_verified');
    final message = points == null
        ? RewardsContentData.emptyGenericMessage
        : RewardsContentData.emptyMessage(points);
    return LearnerSurface(
      semanticLabel: '${RewardsContentData.emptyTitle}. $message',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.backgroundPaleBlue,
                borderRadius: AppTheme.radiusSm,
              ),
              child: const Icon(Icons.flag_outlined,
                  color: AppTheme.primaryBlue, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    RewardsContentData.emptyTitle,
                    style: AppTheme.titleMedium
                        .copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(message, style: AppTheme.bodyMedium),
                  const SizedBox(height: 6),
                  Text(
                    RewardsContentData.emptySupport,
                    style:
                        AppTheme.bodySmall.copyWith(color: AppTheme.textMedium),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// True when the learner's text size leaves too little width for side-by-side
/// values at narrow screen sizes.
bool _isLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(16) > 21;

/// Shows a trailing value beside its content, or below it with large text,
/// so rows never overflow at 320 px.
class _AdaptiveValueRow extends StatelessWidget {
  const _AdaptiveValueRow({
    required this.leading,
    required this.content,
    required this.value,
  });

  final Widget leading;
  final Widget content;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final stacked = _isLargeText(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        leading,
        const SizedBox(width: 12),
        Expanded(
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [content, const SizedBox(height: 4), value],
                )
              : content,
        ),
        if (!stacked) ...[const SizedBox(width: 8), value],
      ],
    );
  }
}

class _AchievementGrid extends StatelessWidget {
  const _AchievementGrid({required this.achievements});

  final List<RewardAchievement> achievements;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 12.0;
          final largeText = _isLargeText(context);
          final width = constraints.maxWidth;
          final columns = width >= 540
              ? 3
              : width >= 260 && !largeText
                  ? 2
                  : 1;
          final tileWidth = (width - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final achievement in achievements)
                SizedBox(
                  width: tileWidth,
                  child: _AchievementTile(achievement: achievement),
                ),
            ],
          );
        },
      );
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.achievement});

  final RewardAchievement achievement;

  @override
  Widget build(BuildContext context) {
    final earned = achievement.earned;
    final earnedAt = achievement.earnedAt;
    return Semantics(
      container: true,
      label: RewardsContentData.achievementSemantics(
        title: achievement.title,
        description: achievement.description,
        earnedAt: earnedAt,
        progressCurrent: achievement.progressCurrent,
        progressTarget: achievement.progressTarget,
      ),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: earned ? AppTheme.cardWhite : AppTheme.surfaceMuted,
            borderRadius: AppTheme.radiusLg,
            border: Border.all(
              color: earned
                  ? AppTheme.primaryBlue.withValues(alpha: .35)
                  : AppTheme.borderLight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: earned
                          ? AppTheme.backgroundPaleBlue
                          : AppTheme.cardLightGray,
                      borderRadius: AppTheme.radiusSm,
                    ),
                    child: Icon(
                      RewardsContentData.achievementIcon(achievement.icon),
                      color: earned ? AppTheme.primaryBlue : AppTheme.textLight,
                      size: 22,
                    ),
                  ),
                  const Spacer(),
                  if (!earned)
                    const Icon(Icons.lock_outline_rounded,
                        color: AppTheme.textLight, size: 18),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                achievement.title,
                style: AppTheme.titleSmall.copyWith(
                  fontWeight: FontWeight.w800,
                  color: earned ? AppTheme.textDark : AppTheme.textMedium,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                earnedAt != null
                    ? RewardsContentData.earnedOn(earnedAt)
                    : achievement.description,
                style: AppTheme.bodySmall.copyWith(
                  color: earned ? AppTheme.successGreen : AppTheme.textMedium,
                  fontWeight: earned ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (achievement.showsProgress) ...[
                const SizedBox(height: 6),
                Text(
                  RewardsContentData.progressLabel(
                    achievement.progressCurrent,
                    achievement.progressTarget,
                  ),
                  style: AppTheme.labelSmall.copyWith(color: AppTheme.textDark),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentPoints extends StatelessWidget {
  const _RecentPoints({required this.events});

  final List<RewardPointEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return LearnerSurface(
        child: Text(
          RewardsContentData.recentEmpty,
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMedium),
        ),
      );
    }
    return LearnerSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < events.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            _RecentPointRow(event: events[index]),
          ],
        ],
      ),
    );
  }
}

class _RecentPointRow extends StatelessWidget {
  const _RecentPointRow({required this.event});

  final RewardPointEvent event;

  @override
  Widget build(BuildContext context) {
    final awardedAt = event.awardedAt;
    final detail = event.detail;
    return Semantics(
      container: true,
      label: RewardsContentData.recentSemantics(
          event.label, detail, event.points, awardedAt),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: _AdaptiveValueRow(
            leading: Icon(RewardsContentData.categoryIcon(event.eventType),
                color: AppTheme.primaryBlue, size: 22),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.label,
                  style:
                      AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(detail, style: AppTheme.bodySmall),
                ],
                if (awardedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    RewardsContentData.formatDate(awardedAt),
                    style: AppTheme.labelSmall
                        .copyWith(color: AppTheme.textMedium),
                  ),
                ],
              ],
            ),
            value: Text(
              RewardsContentData.pointsDelta(event.points),
              style: AppTheme.titleSmall.copyWith(
                color: AppTheme.successGreen,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PointCategories extends StatelessWidget {
  const _PointCategories({required this.categories});

  final List<RewardPointCategory> categories;

  @override
  Widget build(BuildContext context) => LearnerSurface(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var index = 0; index < categories.length; index++) ...[
              if (index > 0) const Divider(height: 1),
              _PointCategoryRow(category: categories[index]),
            ],
          ],
        ),
      );
}

class _PointCategoryRow extends StatelessWidget {
  const _PointCategoryRow({required this.category});

  final RewardPointCategory category;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: RewardsContentData.categorySemantics(
            category.label, category.points, category.count),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: _AdaptiveValueRow(
              leading: Icon(RewardsContentData.categoryIcon(category.eventType),
                  color: category.points > 0
                      ? AppTheme.primaryBlue
                      : AppTheme.textLight,
                  size: 22),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.label,
                    style: AppTheme.titleSmall
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    category.active
                        ? RewardsContentData.categoryDetail(
                            category.count, category.pointsEach)
                        : RewardsContentData.categoryInactive,
                    style: AppTheme.labelSmall
                        .copyWith(color: AppTheme.textMedium),
                  ),
                ],
              ),
              value: Text(
                RewardsContentData.pointsValue(category.points),
                style: AppTheme.titleSmall.copyWith(
                  fontWeight: FontWeight.w800,
                  color: category.points > 0
                      ? AppTheme.textDark
                      : AppTheme.textMedium,
                ),
              ),
            ),
          ),
        ),
      );
}

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({
    required this.rewards,
    required this.saving,
    required this.onChanged,
  });

  final LearnerRewards rewards;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final onlyMe = rewards.leaderboard.every((entry) => entry.isMe);
    return LearnerSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A transparent Material keeps the tile's ink visible on the surface.
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const ValueKey('rewards-leaderboard-toggle'),
              value: rewards.showOnLeaderboard,
              onChanged: saving ? null : onChanged,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              secondary: saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Icon(Icons.groups_outlined,
                      color: AppTheme.primaryBlue),
              title: Text(
                RewardsContentData.leaderboardToggleTitle,
                style:
                    AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                RewardsContentData.leaderboardToggleSubtitle,
                style: AppTheme.bodySmall,
              ),
            ),
          ),
          if (!rewards.showOnLeaderboard)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                RewardsContentData.leaderboardHiddenNote,
                style: AppTheme.labelSmall.copyWith(color: AppTheme.textMedium),
              ),
            ),
          const Divider(height: 1),
          for (final entry in rewards.leaderboard)
            _LeaderboardRow(entry: entry),
          if (onlyMe)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Text(
                RewardsContentData.leaderboardOnlyYou,
                style: AppTheme.bodySmall.copyWith(color: AppTheme.textMedium),
              ),
            ),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry});

  final RewardLeaderboardEntry entry;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: RewardsContentData.leaderboardSemantics(
            entry.rank, entry.displayName, entry.points, entry.isMe),
        child: ExcludeSemantics(
          child: Container(
            color: entry.isMe ? AppTheme.backgroundPaleBlue : null,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: _AdaptiveValueRow(
              leading: Container(
                constraints: const BoxConstraints(minWidth: 40),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: entry.isMe ? AppTheme.primaryBlue : AppTheme.cardWhite,
                  borderRadius: AppTheme.radiusXs,
                  border: Border.all(color: AppTheme.borderLight),
                ),
                child: Text(
                  RewardsContentData.rankLabel(entry.rank),
                  style: AppTheme.labelLarge.copyWith(
                    color: entry.isMe ? Colors.white : AppTheme.textDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              content: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    entry.displayName,
                    style: AppTheme.titleSmall
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (entry.isMe)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withValues(alpha: .12),
                        borderRadius: AppTheme.badgeRadius,
                      ),
                      child: Text(
                        RewardsContentData.youLabel,
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              value: Text(
                RewardsContentData.pointsValue(entry.points),
                style: AppTheme.titleSmall.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      );
}

class _SeparationNote extends StatelessWidget {
  const _SeparationNote({required this.onShowInfo});

  final VoidCallback onShowInfo;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.verified_user_outlined,
                  color: AppTheme.primaryBlue, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  RewardsContentData.separationNote,
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textDark),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: onShowInfo,
            child: const Text(RewardsContentData.infoTitle),
          ),
        ],
      );
}

class _RewardsInfoSheet extends StatelessWidget {
  const _RewardsInfoSheet();

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  RewardsContentData.infoTitle,
                  style:
                      AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 12),
              for (final paragraph in RewardsContentData.infoParagraphs) ...[
                Text(paragraph,
                    style: AppTheme.bodyMedium.copyWith(height: 1.5)),
                const SizedBox(height: 10),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(RewardsContentData.infoClose),
                ),
              ),
            ],
          ),
        ),
      );
}
