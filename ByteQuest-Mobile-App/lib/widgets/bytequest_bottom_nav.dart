import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_theme.dart';

/// Compact learner navigation inspired by modern learning and wellbeing apps.
/// Rewards deliberately remains separate from competency progress.
class ByteQuestBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const ByteQuestBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Material(
        color: AppTheme.cardWhite,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: AppTheme.borderLight)),
        child: Padding(
            padding: const EdgeInsets.all(5),
            child: Row(
              children: [
                _buildNavItem(context, 0, Icons.home_rounded, 'Home'),
                _buildNavItem(
                  context,
                  1,
                  Icons.explore_rounded,
                  'Learn',
                ),
                _buildNavItem(
                  context,
                  2,
                  Icons.insights_rounded,
                  'Progress',
                ),
                _buildNavItem(
                  context,
                  3,
                  Icons.workspace_premium_rounded,
                  'Rewards',
                ),
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
        label: '$label tab',
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
                        const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          color: isSelected ? Colors.white : AppTheme.textLight,
                          size: 21,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          style: AppTheme.labelSmall.copyWith(
                            fontSize: 10.5,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w600,
                            color:
                                isSelected ? Colors.white : AppTheme.textMedium,
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
