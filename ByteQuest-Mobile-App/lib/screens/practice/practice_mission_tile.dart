import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../data/learning_content_data.dart';
import '../../models/curriculum_model.dart';
import '../learn/curriculum_widgets.dart';

/// Mission tile with lock icon and prerequisite text, verified badge, run
/// count and best verified time (all from the server projection).
class PracticeMissionTile extends StatelessWidget {
  const PracticeMissionTile({
    super.key,
    required this.mission,
    required this.onOpen,
    this.lockReason,
    this.busy = false,
  });

  final CurriculumMission mission;
  final VoidCallback? onOpen;
  final String? lockReason;
  final bool busy;

  String get _state => !mission.unlocked
      ? LearningContentData.missionLocked
      : mission.verified
          ? LearningContentData.missionVerified
          : LearningContentData.missionNotVerified;

  @override
  Widget build(BuildContext context) {
    final color = !mission.unlocked
        ? AppTheme.textMedium
        : mission.verified
            ? AppTheme.accentGreen
            : AppTheme.primaryBlue;
    return LearnerSurface(
      key: ValueKey('practice-mission-${mission.missionCode}'),
      semanticLabel: LearningContentData.missionSemantics(
          mission.missionNumber, mission.title, _state, mission.runs),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : !mission.unlocked
                        ? Icon(Icons.lock_outline_rounded, color: color)
                        : mission.verified
                            ? Icon(Icons.verified_rounded, color: color)
                            : Text('${mission.missionNumber}',
                                style: AppTheme.titleMedium.copyWith(
                                    color: color, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        LearningContentData.missionNumber(
                            mission.missionNumber),
                        style: AppTheme.labelSmall
                            .copyWith(color: AppTheme.textMedium)),
                    const SizedBox(height: 2),
                    Text(mission.title,
                        style: AppTheme.labelLarge
                            .copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              if (onOpen != null)
                const Icon(Icons.play_arrow_rounded,
                    color: AppTheme.primaryBlue),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CurriculumStatusPill(
                label: _state,
                icon: !mission.unlocked
                    ? Icons.lock_outline_rounded
                    : mission.verified
                        ? Icons.verified_rounded
                        : Icons.radio_button_unchecked_rounded,
                color: color,
              ),
              Text(LearningContentData.missionRuns(mission.runs),
                  style: AppTheme.bodySmall),
              if (mission.bestSeconds != null)
                Text(
                    LearningContentData.missionBest(
                        LearningContentData.formatDuration(
                            mission.bestSeconds!)),
                    style: AppTheme.bodySmall),
            ],
          ),
          if (!mission.unlocked && lockReason != null) ...[
            const SizedBox(height: 8),
            LockReasonText(reason: lockReason!),
          ],
        ],
      ),
    );
  }
}
