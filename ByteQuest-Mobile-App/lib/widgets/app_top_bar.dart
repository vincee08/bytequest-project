import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../data/mission_content_data.dart';

/// Reusable top bar with title, notification icon, and settings icon
class AppTopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onSettingsTap;
  final int notificationCount;
  final bool showIcons;
  final String? avatarLabel;

  const AppTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onNotificationTap,
    this.onSettingsTap,
    this.notificationCount = 0,
    this.showIcons = true,
    this.avatarLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: LayoutBuilder(builder: (context, constraints) {
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTheme.headlineLarge.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.35,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textMedium,
                ),
              ),
            ],
          ],
        );
        final actions = Wrap(
            spacing: 4,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (showIcons) ...[
                Semantics(
                  button: true,
                  label: notificationCount == 0
                      ? 'Notifications, none unread'
                      : 'Notifications, $notificationCount unread',
                  child: IconButton.filledTonal(
                    onPressed: onNotificationTap,
                    tooltip: 'Notifications',
                    icon: Badge(
                      isLabelVisible: notificationCount > 0,
                      label: Text(
                          notificationCount > 9 ? '9+' : '$notificationCount'),
                      child: const Icon(Icons.notifications_none_rounded,
                          size: 21),
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: avatarLabel == null
                      ? 'Open learner settings'
                      : 'Open settings for $avatarLabel',
                  child: OutlinedButton.icon(
                    onPressed: onSettingsTap,
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    label: const Text(MissionContentData.settingsLabel),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10)),
                  ),
                ),
              ],
            ]);
        if (MediaQuery.textScalerOf(context).scale(1) > 1.4 ||
            constraints.maxWidth < 300) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                if (showIcons) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: actions)
                ],
              ]);
        }
        return Row(children: [
          Expanded(child: heading),
          if (showIcons) ...[const SizedBox(width: 8), actions]
        ]);
      }),
    );
  }
}
