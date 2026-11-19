import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/learning_content_data.dart';

/// Where each Home shortcut leads. Tasks, Classes and Files open the class
/// work screen at that tab; Quizzes opens the class quiz list.
enum ClassWorkDestination {
  tasks(LearningContentData.shortcutTasks, Icons.assignment_outlined, 0),
  classes(LearningContentData.shortcutClasses, Icons.groups_2_outlined, 1),
  files(LearningContentData.shortcutFiles, Icons.folder_open_outlined, 2),
  quizzes(LearningContentData.shortcutQuizzes, Icons.quiz_outlined, null);

  const ClassWorkDestination(this.label, this.icon, this.classWorkTab);

  final String label;
  final IconData icon;

  /// Tab index in the class work screen, or null for the quiz list.
  final int? classWorkTab;
}

/// Keeps every class feature reachable from Home after Learn became the
/// curriculum view.
class HomeClassWorkLinks extends StatelessWidget {
  const HomeClassWorkLinks({super.key, required this.onOpen});

  final ValueChanged<ClassWorkDestination> onOpen;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(LearningContentData.classWorkTitle,
                style:
                    AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          Text(LearningContentData.classWorkSubtitle,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textMedium)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final destination in ClassWorkDestination.values)
                Semantics(
                  button: true,
                  label:
                      LearningContentData.shortcutSemantics(destination.label),
                  excludeSemantics: true,
                  onTap: () => onOpen(destination),
                  child: FilledButton.tonalIcon(
                    key: ValueKey('home-shortcut-${destination.name}'),
                    style:
                        FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: () => onOpen(destination),
                    icon: Icon(destination.icon),
                    label: Text(destination.label),
                  ),
                ),
            ],
          ),
        ],
      );
}
