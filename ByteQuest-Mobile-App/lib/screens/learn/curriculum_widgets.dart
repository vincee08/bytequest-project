import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../data/learning_content_data.dart';
import '../../models/curriculum_model.dart';

/// COC selector shared by Learn and Practice. Wraps on narrow screens and
/// grows with large text; every chip is a 48 dp target with a label.
class CocSelector extends StatelessWidget {
  const CocSelector(
      {super.key,
      required this.cocs,
      required this.selected,
      required this.onSelected});

  final List<CurriculumCoc> cocs;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final coc in cocs)
            Semantics(
              button: true,
              selected: coc.cocCode == selected,
              label: LearningContentData.cocChipSemantics(
                  coc.number, coc.unlocked, coc.completed),
              onTap: () => onSelected(coc.cocCode),
              excludeSemantics: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                child: ChoiceChip(
                  key: ValueKey('coc-chip-${coc.cocCode}'),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  selected: coc.cocCode == selected,
                  showCheckmark: false,
                  avatar: Icon(
                    coc.completed
                        ? Icons.check_circle_rounded
                        : coc.unlocked
                            ? Icons.lock_open_rounded
                            : Icons.lock_outline_rounded,
                    size: 18,
                    color: coc.cocCode == selected
                        ? AppTheme.primaryBlue
                        : AppTheme.textMedium,
                  ),
                  label: Text(LearningContentData.cocLabel(coc.number)),
                  onSelected: (_) => onSelected(coc.cocCode),
                ),
              ),
            ),
        ],
      );
}

/// "x of y required items · z%" with a progress bar.
class CurriculumProgressSummary extends StatelessWidget {
  const CurriculumProgressSummary(
      {super.key,
      required this.progress,
      required this.semanticLabel,
      this.completed = false});

  final CurriculumProgress progress;
  final String semanticLabel;
  final bool completed;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LearnerProgressBar(
            value: progress.total == 0 ? (completed ? 1 : 0) : progress.ratio,
            semanticLabel: semanticLabel,
            color: completed ? AppTheme.accentGreen : AppTheme.primaryBlue,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                    LearningContentData.progressValue(
                        progress.done, progress.total),
                    style: AppTheme.bodySmall
                        .copyWith(color: AppTheme.textMedium)),
              ),
              Text(LearningContentData.percentLabel(progress.percent),
                  style: AppTheme.labelMedium
                      .copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      );
}

/// A small status pill (never "Correct"/"Wrong").
class CurriculumStatusPill extends StatelessWidget {
  const CurriculumStatusPill(
      {super.key,
      required this.label,
      required this.icon,
      this.color = AppTheme.primaryBlue});

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  style: AppTheme.labelSmall
                      .copyWith(color: color, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}

/// Prerequisite text shown under every locked module, mission or COC.
class LockReasonText extends StatelessWidget {
  const LockReasonText({super.key, required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.lock_outline_rounded,
                size: 16, color: AppTheme.textMedium),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(reason,
                style: AppTheme.bodySmall.copyWith(color: AppTheme.textMedium)),
          ),
        ],
      );
}

String moduleStateLabel(CurriculumModule module) => !module.unlocked
    ? LearningContentData.lockedLabel
    : module.completed
        ? LearningContentData.completedLabel
        : module.progress.done > 0
            ? LearningContentData.inProgressLabel
            : LearningContentData.notStartedLabel;

/// Module row for the Learn list: lock/complete state, progress and prerequisite.
class CurriculumModuleTile extends StatelessWidget {
  const CurriculumModuleTile(
      {super.key, required this.module, required this.onTap});

  final CurriculumModule module;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = !module.unlocked
        ? Icons.lock_outline_rounded
        : module.completed
            ? Icons.check_circle_rounded
            : Icons.menu_book_rounded;
    final color = !module.unlocked
        ? AppTheme.textMedium
        : module.completed
            ? AppTheme.accentGreen
            : AppTheme.primaryBlue;
    return LearnerSurface(
      key: ValueKey('module-${module.code}'),
      semanticLabel: LearningContentData.moduleSemantics(module.sequenceOrder,
          module.code, module.title, moduleStateLabel(module)),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        LearningContentData.moduleLabel(
                            module.sequenceOrder, module.code),
                        style: AppTheme.labelSmall
                            .copyWith(color: AppTheme.textMedium)),
                    const SizedBox(height: 2),
                    Text(module.title,
                        style: AppTheme.titleMedium
                            .copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              CurriculumStatusPill(
                  label: moduleStateLabel(module), icon: icon, color: color),
              if (module.newContent)
                const CurriculumStatusPill(
                    label: LearningContentData.newContentLabel,
                    icon: Icons.fiber_new_outlined,
                    color: AppTheme.accentOrange),
              if (module.noRequiredItems)
                const CurriculumStatusPill(
                    label: LearningContentData.noRequiredItems,
                    icon: Icons.info_outline,
                    color: AppTheme.textMedium),
            ],
          ),
          if (!module.noRequiredItems) ...[
            const SizedBox(height: 10),
            CurriculumProgressSummary(
              progress: module.progress,
              completed: module.completed,
              semanticLabel: LearningContentData.progressValue(
                  module.progress.done, module.progress.total),
            ),
          ],
          if (!module.unlocked && module.lockReason != null) ...[
            const SizedBox(height: 10),
            LockReasonText(reason: module.lockReason!),
          ],
        ],
      ),
    );
  }
}

/// Explains the single completion methodology used by every screen.
Future<void> showProgressMethodology(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Semantics(
                header: true,
                child: Text(LearningContentData.methodologyTitle,
                    style: AppTheme.titleLarge
                        .copyWith(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 12),
              for (final (term, detail) in LearningContentData.methodologyItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(term,
                          style: AppTheme.labelLarge
                              .copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(detail,
                          style: AppTheme.bodySmall.copyWith(height: 1.45)),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text(LearningContentData.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );

/// Info button that opens the methodology sheet.
class MethodologyButton extends StatelessWidget {
  const MethodologyButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
        key: const ValueKey('methodology-button'),
        tooltip: LearningContentData.howProgressWorks,
        onPressed: () => showProgressMethodology(context),
        icon: const Icon(Icons.info_outline_rounded),
      );
}
