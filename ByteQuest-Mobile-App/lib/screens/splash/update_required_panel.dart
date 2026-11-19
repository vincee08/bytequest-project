import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../data/account_content_data.dart';

/// Keeps each action its own accessibility node inside the live-region panel,
/// so screen readers focus and announce the button separately.
class _ButtonNode extends StatelessWidget {
  const _ButtonNode({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(container: true, child: child);
}

class _GatePanel extends StatelessWidget {
  const _GatePanel({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          decoration: BoxDecoration(
            color: AppTheme.cardWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderLight),
            boxShadow: AppTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: iconColor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: AppTheme.headlineSmall.copyWith(
                          color: AppTheme.navy,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Blocking notice shown when this app is older than the server's minimum
/// supported version. The only action re-checks the server value.
class UpdateRequiredPanel extends StatelessWidget {
  const UpdateRequiredPanel({
    super.key,
    required this.currentVersion,
    required this.minimumVersion,
    required this.checking,
    required this.onCheckAgain,
  });

  final String currentVersion;
  final String minimumVersion;
  final bool checking;
  final VoidCallback onCheckAgain;

  @override
  Widget build(BuildContext context) {
    return _GatePanel(
      icon: Icons.system_update_alt,
      iconColor: AppTheme.primaryBlue,
      title: AccountContentData.updateRequiredTitle,
      children: [
        Text(
          AccountContentData.updateRequiredBody(currentVersion, minimumVersion),
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textDark),
        ),
        const SizedBox(height: 8),
        Text(
          AccountContentData.updateRequiredHint,
          style: AppTheme.bodySmall.copyWith(color: AppTheme.textMedium),
        ),
        const SizedBox(height: 20),
        _ButtonNode(
          child: AppButton.primary(
            label: AccountContentData.updateCheckAgain,
            semanticsLabel: AccountContentData.updateCheckAgainSemantics,
            icon: Icons.refresh,
            isLoading: checking,
            onPressed: onCheckAgain,
            width: double.infinity,
          ),
        ),
      ],
    );
  }
}

/// Shown when the version could not be checked (offline): the learner may
/// retry or continue, so a network problem never locks them out.
class VersionCheckFailedPanel extends StatelessWidget {
  const VersionCheckFailedPanel({
    super.key,
    required this.checking,
    required this.onRetry,
    required this.onContinue,
  });

  final bool checking;
  final VoidCallback onRetry;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return _GatePanel(
      icon: Icons.wifi_off,
      iconColor: AppTheme.warningYellow,
      title: AccountContentData.versionCheckFailedTitle,
      children: [
        Text(
          AccountContentData.versionCheckFailedBody,
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textDark),
        ),
        const SizedBox(height: 20),
        _ButtonNode(
          child: AppButton.primary(
            label: AccountContentData.versionCheckRetry,
            semanticsLabel: AccountContentData.versionCheckRetrySemantics,
            icon: Icons.refresh,
            isLoading: checking,
            onPressed: onRetry,
            width: double.infinity,
          ),
        ),
        const SizedBox(height: 8),
        _ButtonNode(
          child: AppButton.outline(
            label: AccountContentData.versionCheckContinue,
            semanticsLabel: AccountContentData.versionCheckContinueSemantics,
            onPressed: checking ? null : onContinue,
            width: double.infinity,
          ),
        ),
      ],
    );
  }
}
