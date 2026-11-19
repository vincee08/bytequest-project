import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_theme.dart';
import '../data/learning_content_data.dart';

/// Compact learner navigation: Home · Learn · Practice · Progress · Rewards.
/// Rewards deliberately remains separate from competency progress. Labels
/// scale down to fit narrow phones at large text sizes instead of overflowing.
class ByteQuestBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const ByteQuestBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const destinations = <(IconData, String)>[
    (Icons.home_rounded, LearningContentData.navHome),
    (Icons.menu_book_rounded, LearningContentData.navLearn),
    (Icons.science_rounded, LearningContentData.navPractice),
    (Icons.insights_rounded, LearningContentData.navProgress),
    (Icons.workspace_premium_rounded, LearningContentData.navRewards),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      child: Material(
        color: AppTheme.cardWhite,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: AppTheme.borderLight)),
        child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                for (var index = 0; index < destinations.length; index++)
                  _buildNavItem(context, index, destinations[index].$1,
                      destinations[index].$2),
              ],
            )),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    int index,
    IconData icon,
    String label,
  ) {
    final isSelected = currentIndex == index;

    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: LearningContentData.navTabSemantics(label),
        excludeSemantics: true,
        onTap: () => onTap(index),
        child: InkWell(
          onTap: () {
            if (!isSelected) HapticFeedback.selectionClick();
            onTap(index);
          },
          borderRadius: BorderRadius.circular(17),
          child: Ink(
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(17),
            ),
            child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 55),
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          color: isSelected ? Colors.white : AppTheme.textLight,
                          size: 21,
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: AppTheme.labelSmall.copyWith(
                              fontSize: 10.5,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : AppTheme.textMedium,
                            ),
                          ),
                        ),
                      ],
                    ))),
          ),
        ),
      ),
    );
  }
}
