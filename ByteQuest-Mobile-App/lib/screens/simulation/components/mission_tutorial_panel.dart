import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/mission_content_data.dart';

/// Optional display-only tour. Mission actions and the practice timer remain
/// owned by the existing runtime while this panel is visible.
class MissionTutorialPanel extends StatelessWidget {
  const MissionTutorialPanel({
    super.key,
    required this.steps,
    required this.stepIndex,
    required this.onStart,
    required this.onNext,
    required this.onSkip,
    required this.timedPractice,
  });

  final List<String> steps;
  final int? stepIndex;
  final VoidCallback onStart;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final bool timedPractice;

  @override
  Widget build(BuildContext context) {
    final active = stepIndex != null;
    final finalStep = active && stepIndex == steps.length - 1;
    return Semantics(
      container: true,
      label: MissionContentData.tutorialHeading,
      child: Material(
        color: AppTheme.backgroundPaleBlue,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Icon(Icons.help_outline_rounded,
                    color: AppTheme.deepBlue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      active
                          ? '${MissionContentData.tutorialHeading} '
                              '${stepIndex! + 1}/${steps.length}'
                          : MissionContentData.tutorialInvite,
                      style: AppTheme.labelSmall,
                    ),
                    if (active) ...[
                      Text(steps[stepIndex!], style: AppTheme.bodySmall),
                      if (timedPractice)
                        Text(MissionContentData.tutorialTimer,
                            style: AppTheme.caption),
                    ],
                  ],
                )),
              ]),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                children: [
                  TextButton(
                    key: const ValueKey('mission-tutorial-skip'),
                    onPressed: onSkip,
                    style:
                        TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    child: const Text(MissionContentData.tutorialSkip),
                  ),
                  TextButton(
                    key: ValueKey(active
                        ? 'mission-tutorial-next'
                        : 'mission-tutorial-start'),
                    onPressed: active ? onNext : onStart,
                    style:
                        TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    child: Text(active
                        ? finalStep
                            ? MissionContentData.tutorialFinish
                            : MissionContentData.tutorialNext
                        : MissionContentData.tutorialStart),
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
