import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/mission_content_data.dart';

/// Shows a practice placement error briefly, with an accessible manual close.
Future<void> showIncorrectPlacementDialog(
  BuildContext context, {
  required String message,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _IncorrectPlacementDialog(message: message),
    );

class _IncorrectPlacementDialog extends StatefulWidget {
  const _IncorrectPlacementDialog({required this.message});

  final String message;

  @override
  State<_IncorrectPlacementDialog> createState() =>
      _IncorrectPlacementDialogState();
}

class _IncorrectPlacementDialogState extends State<_IncorrectPlacementDialog> {
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _dismissTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const ValueKey('incorrect-placement-dialog'),
        icon: const Icon(Icons.error_outline_rounded, color: AppTheme.errorRed),
        title: const Text(MissionContentData.incorrectPlacementTitle),
        content: Semantics(
          liveRegion: true,
          child: Text(widget.message),
        ),
        actions: [
          TextButton(
            key: const ValueKey('incorrect-placement-close'),
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text(MissionContentData.incorrectPlacementCloseLabel),
          ),
        ],
      );
}
