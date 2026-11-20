import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/mission_content_data.dart';
import '../../../data/mission_phase_guidance.dart';
import '../runtime/mission_runtime_models.dart';

/// Pinned, compact instruction entry point above the equipment workspace.
class MissionGuidanceBar extends StatelessWidget {
  const MissionGuidanceBar({
    super.key,
    required this.guidance,
    required this.actionGuide,
    required this.expanded,
    required this.onToggle,
    required this.showHow,
    required this.onShowHow,
    this.onReplayTutorial,
    this.tutorialFirstUse = false,
  });

  final MissionPhaseGuidance guidance;
  final MissionActionGuide actionGuide;
  final bool expanded;
  final VoidCallback onToggle;
  final bool showHow;
  final VoidCallback onShowHow;
  final VoidCallback? onReplayTutorial;
  final bool tutorialFirstUse;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact =
        size.height < 500 || MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final current = actionGuide.currentStep;
    // On the bench the bar names the same pending step as the bench header,
    // so the two never disagree (practice only; assessment has no bar).
    final currentText = guidance.benchStep ??
        current?.text ??
        (actionGuide.submitted
            ? MissionContentData.reviewSavedLabel
            : guidance.interactionLabel ==
                    MissionContentData.guidanceReviewLabel
                ? MissionContentData.reviewReadyLabel
                : MissionContentData.guideReadyToContinue);
    return Material(
      key: const ValueKey('mission-guidance-bar'),
      color: AppTheme.cardWhite,
      child: Row(children: [
        Expanded(
            child: InkWell(
          key: const ValueKey('mission-guidance-toggle'),
          onTap: onToggle,
          child: Semantics(
            button: true,
            expanded: expanded,
            label: '${MissionContentData.guidanceHeading}. '
                '${guidance.interactionLabel}. $currentText. '
                '${expanded ? MissionContentData.guidanceHideSteps : MissionContentData.guidanceShowSteps}',
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.borderLight)),
              ),
              child: Row(children: [
                Icon(_icon(guidance.interactionLabel),
                    color: AppTheme.deepBlue, size: 21),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(currentText,
                          maxLines: compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodySmall
                              .copyWith(color: AppTheme.deepBlue)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppTheme.deepBlue),
              ]),
            ),
          ),
        )),
        IconButton(
          key: const ValueKey('mission-show-me-how'),
          tooltip: showHow
              ? MissionContentData.guideHideHighlight
              : MissionContentData.guideShowMeHow,
          onPressed: onShowHow,
          icon: Icon(showHow
              ? Icons.visibility_off_outlined
              : Icons.ads_click_rounded),
        ),
        if (onReplayTutorial != null)
          IconButton(
            key: const ValueKey('mission-replay-tutorial'),
            tooltip: tutorialFirstUse
                ? MissionContentData.tutorialStart
                : MissionContentData.tutorialReplay,
            onPressed: onReplayTutorial,
            icon: const Icon(Icons.school_outlined),
          ),
      ]),
    );
  }

  static IconData _icon(String label) => switch (label) {
        MissionContentData.guidancePlaceLabel ||
        MissionContentData.guidanceTapPlaceLabel ||
        MissionContentData.guidanceInspectPlaceLabel =>
          Icons.open_with_rounded,
        MissionContentData.guidanceConnectLabel => Icons.cable_rounded,
        MissionContentData.guidanceConfigureLabel => Icons.tune_rounded,
        MissionContentData.guidanceTroubleshootLabel => Icons.build_outlined,
        MissionContentData.guidanceTestLabel => Icons.science_outlined,
        MissionContentData.guidanceReviewLabel => Icons.fact_check_outlined,
        _ => Icons.touch_app_outlined,
      };
}

/// Expanded directions sit with the task controls, outside the scene hit area.
class MissionGuidancePanel extends StatelessWidget {
  const MissionGuidancePanel({
    super.key,
    required this.phase,
    required this.guidance,
    required this.actionGuide,
    required this.practice,
  });

  final MissionPhaseDefinition phase;
  final MissionPhaseGuidance guidance;
  final MissionActionGuide actionGuide;
  final bool practice;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: '${MissionContentData.guidanceHeading}. ${phase.title}',
        child: Container(
          key: ValueKey('mission-guidance-panel-${phase.id}'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.cardWhite,
            borderRadius: AppTheme.radiusSm,
            border: Border.all(color: AppTheme.borderMedium),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(MissionContentData.guideNextHeading,
                  style: AppTheme.labelLarge),
              const SizedBox(height: 4),
              Text(phase.title, style: AppTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                  '${MissionContentData.guidanceObjectiveLabel}: '
                  '${phase.instruction}',
                  style: AppTheme.bodySmall),
              const SizedBox(height: 10),
              Text(
                  MissionContentData.guideActionCount(
                      actionGuide.completedCount, actionGuide.steps.length),
                  style: AppTheme.labelMedium),
              const SizedBox(height: 8),
              for (var index = 0; index < actionGuide.steps.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Container(
                    decoration: BoxDecoration(
                      color:
                          actionGuide.steps[index] == actionGuide.currentStep &&
                                  !actionGuide.ready
                              ? AppTheme.softBlueAccent
                              : null,
                      borderRadius: AppTheme.radiusSm,
                    ),
                    padding: const EdgeInsets.all(5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTheme.softBlueAccent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: actionGuide.steps[index].completed
                              ? const Icon(Icons.check_rounded,
                                  size: 18, color: AppTheme.deepBlue)
                              : Text('${index + 1}',
                                  style: AppTheme.labelSmall
                                      .copyWith(color: AppTheme.deepBlue)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(actionGuide.steps[index].text,
                              style: AppTheme.bodySmall),
                        ),
                      ],
                    ),
                  ),
                ),
              if (practice) ...[
                const SizedBox(height: 4),
                Text(
                    '${MissionContentData.guidanceHintLabel}: '
                    '${guidance.hint}',
                    style: AppTheme.bodySmall),
              ],
              const Divider(height: 20),
              Text(MissionContentData.guidanceProgressLabel,
                  style: AppTheme.labelMedium),
              const SizedBox(height: 4),
              for (final item in guidance.progress)
                Text(item, style: AppTheme.bodySmall),
              const SizedBox(height: 5),
              if (actionGuide.pendingEvidenceCount > 0)
                Text(MissionContentData.guideWaitingForSync,
                    style: AppTheme.bodySmall),
              Text(
                  actionGuide.submitted
                      ? MissionContentData.reviewSavedLabel
                      : actionGuide.ready
                          ? phase.resolvedInteraction ==
                                  InteractionFamily.review
                              ? MissionContentData.reviewReadyLabel
                              : MissionContentData.guideReadyToContinue
                          : MissionContentData.guideRemaining(
                              actionGuide.remainingCount),
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.deepBlue)),
            ],
          ),
        ),
      );
}
