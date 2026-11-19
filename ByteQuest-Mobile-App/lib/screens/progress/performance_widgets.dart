import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../data/performance_content_data.dart';
import '../../models/performance_model.dart';

/// Presentational cards of the Performance section. All copy comes from
/// [PerformanceContentData]; layouts wrap instead of overflowing at large text.

class PerformanceProgressCard extends StatelessWidget {
  const PerformanceProgressCard({super.key, required this.progress});

  final PerformanceProgress progress;

  @override
  Widget build(BuildContext context) {
    final overall = PerformanceContentData.percent(progress.overallPercent);
    return LearnerSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(PerformanceContentData.progressTitle, style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 10),
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(overall, style: AppTheme.headlineMedium.copyWith(fontWeight: FontWeight.w800, color: AppTheme.navy)),
                const SizedBox(height: 4),
                Text(
                  PerformanceContentData.itemsCompleted(progress.completedItems, progress.totalItems),
                  style: AppTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          PerformanceBar(
            fraction: (progress.overallPercent ?? 0) / 100,
            semanticLabel: PerformanceContentData.overallProgressSemantics,
          ),
          const SizedBox(height: 6),
          Text(PerformanceContentData.progressDefinition, style: AppTheme.captionSmall.copyWith(color: AppTheme.textLight)),
          for (final coc in progress.cocs) ...[
            const SizedBox(height: 14),
            _CocProgressRow(coc: coc),
          ],
        ],
      ),
    );
  }
}

class _CocProgressRow extends StatelessWidget {
  const _CocProgressRow({required this.coc});

  final CocPerformance coc;

  @override
  Widget build(BuildContext context) {
    final percent = PerformanceContentData.percent(coc.percent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MergeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(coc.label, style: AppTheme.labelLarge.copyWith(fontWeight: FontWeight.w800, color: AppTheme.primaryBlue)),
                    Text(coc.title, style: AppTheme.bodySmall.copyWith(color: AppTheme.textDark)),
                    Text(
                      PerformanceContentData.modulesCompleted(coc.modulesCompleted, coc.modulesTotal),
                      style: AppTheme.captionSmall.copyWith(color: AppTheme.textLight),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(percent, style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        PerformanceBar(
          fraction: (coc.percent ?? 0) / 100,
          semanticLabel: PerformanceContentData.cocProgressSemantics(coc.label, percent),
        ),
      ],
    );
  }
}

/// Progress bar with a 200 ms transition, or none when motion is reduced.
class PerformanceBar extends StatelessWidget {
  const PerformanceBar({super.key, required this.fraction, required this.semanticLabel});

  final double fraction;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final value = fraction.clamp(0.0, 1.0).toDouble();
    Widget bar(double current) => LinearProgressIndicator(
          value: current,
          minHeight: 7,
          color: AppTheme.primaryBlue,
          backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        );
    return Semantics(
      label: semanticLabel,
      value: '${(value * 100).round()} percent',
      child: ExcludeSemantics(
        child: MediaQuery.disableAnimationsOf(context)
            ? bar(value)
            : TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value),
                duration: AppTheme.simulationTransitionDuration,
                curve: Curves.easeOutCubic,
                builder: (context, current, _) => bar(current),
              ),
      ),
    );
  }
}

class PerformanceCompetencyCard extends StatelessWidget {
  const PerformanceCompetencyCard({super.key, required this.outcomes});

  final List<CompetencyOutcome> outcomes;

  @override
  Widget build(BuildContext context) {
    final achieved = outcomes.where((item) => item.achieved).length;
    final byMission = <String, List<CompetencyOutcome>>{};
    for (final outcome in outcomes) {
      byMission.putIfAbsent(outcome.missionTitle ?? outcome.missionCode ?? '', () => []).add(outcome);
    }
    return _SectionCard(
      title: PerformanceContentData.competencyTitle,
      subtitle: outcomes.isEmpty
          ? PerformanceContentData.competencySubtitle
          : PerformanceContentData.competencySummary(achieved, outcomes.length),
      emptyText: outcomes.isEmpty ? PerformanceContentData.competencyEmpty : null,
      children: [
        for (final entry in byMission.entries) ...[
          if (entry.key.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(entry.key, style: AppTheme.labelLarge.copyWith(fontWeight: FontWeight.w700, color: AppTheme.textDark)),
            ),
          for (final outcome in entry.value) _CriterionRow(outcome: outcome),
        ],
      ],
    );
  }
}

class _CriterionRow extends StatelessWidget {
  const _CriterionRow({required this.outcome});

  final CompetencyOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final label = PerformanceContentData.criterionLabel(outcome.outcome);
    final color = outcome.achieved ? AppTheme.successGreen : AppTheme.warningYellow;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                outcome.achieved ? Icons.verified_rounded : Icons.pending_outlined,
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(outcome.criterion ?? PerformanceContentData.criterionFallback, style: AppTheme.bodyMedium.copyWith(color: AppTheme.textDark)),
                  const SizedBox(height: 4),
                  _Pill(text: label, color: color),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PerformanceScoresCard extends StatelessWidget {
  const PerformanceScoresCard({super.key, required this.quizzes, required this.homework});

  final List<QuizScore> quizzes;
  final List<HomeworkScore> homework;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: PerformanceContentData.quizzesTitle,
          emptyText: quizzes.isEmpty ? PerformanceContentData.quizzesEmpty : null,
          children: [
            for (final quiz in quizzes)
              _ValueRow(
                title: quiz.title ?? PerformanceContentData.quizFallback,
                detail: quiz.score != null && quiz.maxScore != null
                    ? PerformanceContentData.quizPoints(
                        PerformanceContentData.number(quiz.score),
                        PerformanceContentData.number(quiz.maxScore),
                        released: quiz.released,
                      )
                    : quiz.correctCount != null && quiz.questionCount != null
                        ? PerformanceContentData.quizScore(quiz.correctCount!, quiz.questionCount!)
                        : null,
                value: PerformanceContentData.percent(quiz.percent),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: PerformanceContentData.homeworkTitle,
          emptyText: homework.isEmpty ? PerformanceContentData.homeworkEmpty : null,
          children: [
            for (final item in homework)
              _ValueRow(
                title: item.title ?? PerformanceContentData.homeworkFallback,
                detail: PerformanceContentData.homeworkDetail(item.released ? item.percent : null, late: item.late),
                value: !item.released
                    ? PerformanceContentData.homeworkAwaiting
                    : item.score == null
                        ? PerformanceContentData.homeworkGradedNoScore
                        : PerformanceContentData.homeworkScore(
                            PerformanceContentData.number(item.score),
                            PerformanceContentData.number(item.maxScore),
                          ),
                muted: !item.released,
              ),
          ],
        ),
      ],
    );
  }
}

class PerformanceAssessmentsCard extends StatelessWidget {
  const PerformanceAssessmentsCard({super.key, required this.assessments});

  final List<ReleasedAssessmentScore> assessments;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.yMMMd();
    return _SectionCard(
      title: PerformanceContentData.assessmentsTitle,
      emptyText: assessments.isEmpty ? PerformanceContentData.assessmentsEmpty : null,
      children: [
        for (final result in assessments)
          MergeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(result.title ?? result.assignmentTitle ?? PerformanceContentData.assessmentFallback,
                            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textDark, fontWeight: FontWeight.w600)),
                        if (result.releasedAt != null)
                          Text(PerformanceContentData.releasedOn(dateFormat.format(result.releasedAt!.toLocal())), style: AppTheme.captionSmall),
                        const SizedBox(height: 4),
                        _Pill(
                          text: PerformanceContentData.outcomeLabel(result.outcome),
                          color: result.outcome == 'competent' ? AppTheme.successGreen : AppTheme.warningYellow,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(PerformanceContentData.percent(result.percent), style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class PerformancePracticeCard extends StatelessWidget {
  const PerformancePracticeCard({super.key, required this.practice});

  final PracticeSummary practice;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: PerformanceContentData.practiceTitle,
      children: [
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _Stat(label: PerformanceContentData.missionsVerifiedLabel, value: '${practice.missionsVerified}')),
            const SizedBox(width: 10),
            Expanded(child: _Stat(label: PerformanceContentData.runsLabel, value: '${practice.runs}')),
          ],
        ),
        const SizedBox(height: 12),
        Text(PerformanceContentData.bestTimesTitle, style: AppTheme.labelLarge.copyWith(fontWeight: FontWeight.w700, color: AppTheme.textDark)),
        if (practice.bestTimes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(PerformanceContentData.bestTimesEmpty, style: AppTheme.bodySmall),
          ),
        for (final best in practice.bestTimes)
          _ValueRow(
            title: best.title ?? PerformanceContentData.missionFallback,
            detail: PerformanceContentData.missionCodeLabel(best.missionCode),
            value: PerformanceContentData.duration(best.bestSeconds),
          ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, this.subtitle, this.emptyText, required this.children});

  final String title;
  final String? subtitle;
  final String? emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LearnerSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle!, style: AppTheme.bodySmall),
          ],
          if (emptyText != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(emptyText!, style: AppTheme.bodySmall.copyWith(color: AppTheme.textLight)),
            )
          else
            ...children,
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.title, required this.value, this.detail, this.muted = false});

  final String title;
  final String? detail;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.bodyMedium.copyWith(color: AppTheme.textDark, fontWeight: FontWeight.w600)),
                  if (detail != null) Text(detail!, style: AppTheme.captionSmall),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: AppTheme.titleSmall.copyWith(
                  fontWeight: FontWeight.w800,
                  color: muted ? AppTheme.textLight : AppTheme.textDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppTheme.backgroundPaleBlue, borderRadius: AppTheme.radiusSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.w800, color: AppTheme.navy)),
            Text(label, style: AppTheme.captionSmall.copyWith(color: AppTheme.textMedium)),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: AppTheme.captionSmall.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

/// Compact summary tiles for the Progress screen's Performance slot, computed
/// by the server (`summary` of get_my_performance). Learning progress and
/// practice counts are left to the Progress screen, which already shows them.
class PerformanceSummaryGrid extends StatelessWidget {
  const PerformanceSummaryGrid({super.key, required this.snapshot});

  final PerformanceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final summary = snapshot.summary;
    final tiles = <_SummaryTile>[
      _SummaryTile(
        label: PerformanceContentData.summaryCriteriaLabel,
        value: summary.criteriaTotal == 0
            ? PerformanceContentData.noValue
            : PerformanceContentData.ofTotal(summary.criteriaAchieved, summary.criteriaTotal),
        detail: PerformanceContentData.summaryCriteriaDetail,
      ),
      _SummaryTile(
        label: PerformanceContentData.summaryQuizLabel,
        value: PerformanceContentData.percent(summary.quizAvg),
        detail: PerformanceContentData.quizCount(snapshot.quizzes.length),
      ),
      _SummaryTile(
        label: PerformanceContentData.summaryHomeworkLabel,
        value: PerformanceContentData.percent(summary.homeworkAvg),
        detail: PerformanceContentData.releasedGrades(summary.homeworkReleased),
      ),
      _SummaryTile(
        label: PerformanceContentData.summaryAssessmentsLabel,
        value: summary.assessmentsReleased == 0
            ? PerformanceContentData.noValue
            : PerformanceContentData.ofTotal(summary.assessmentsCompetent, summary.assessmentsReleased),
        detail: PerformanceContentData.summaryAssessmentsDetail,
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      const spacing = 10.0;
      final twoColumns = constraints.maxWidth >= 340;
      final width = twoColumns ? (constraints.maxWidth - spacing) / 2 : constraints.maxWidth;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final tile in tiles) SizedBox(width: width, child: tile)],
      );
    });
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value, required this.detail});

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: PerformanceContentData.summarySemantics(label, value, detail),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.cardWhite,
            borderRadius: AppTheme.radiusMd,
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTheme.captionSmall.copyWith(color: AppTheme.textMedium, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(value, style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.w800, color: AppTheme.navy)),
              const SizedBox(height: 2),
              Text(detail, style: AppTheme.captionSmall.copyWith(color: AppTheme.textLight)),
            ],
          ),
        ),
      ),
    );
  }
}
