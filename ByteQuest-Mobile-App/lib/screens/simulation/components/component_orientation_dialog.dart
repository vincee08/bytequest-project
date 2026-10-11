import 'package:flutter/material.dart';

import '../../../data/mission_content_data.dart';

/// Shared physical alignment choice for canvas and control-panel installation.
Future<String?> showComponentOrientationDialog(
    BuildContext context, List<String> orientations) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text(MissionContentData.workspaceOrientationTitle),
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(MissionContentData.workspaceOrientationHint),
        ),
        for (final value in orientations)
          SimpleDialogOption(
            key: ValueKey('workspace-orientation-$value'),
            padding: const EdgeInsets.all(16),
            onPressed: () => Navigator.of(dialogContext).pop(value),
            child: Semantics(
              button: true,
              label: value.replaceAll('_', ' '),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(value.replaceAll('_', ' ')),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
