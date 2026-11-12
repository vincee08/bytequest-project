import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/mission_content_data.dart';

/// Allocates space from the safe, keyboard-adjusted body constraints. Only the
/// task panel scrolls; resizing it never reparents its fields or the canvas.
class MissionWorkspaceLayout extends StatelessWidget {
  const MissionWorkspaceLayout({
    super.key,
    required this.scene,
    required this.controls,
    required this.guidance,
    required this.actionBar,
    required this.expandedControls,
    required this.onToggleControls,
  });

  final Widget scene;
  final Widget controls;
  final Widget guidance;
  final Widget actionBar;
  final bool expandedControls;
  final VoidCallback onToggleControls;

  static bool usesSidePanel(BoxConstraints constraints) =>
      constraints.maxWidth >= 520 &&
      constraints.maxWidth > constraints.maxHeight;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = usesSidePanel(constraints);
          if (wide) {
            final panelWidth = (constraints.maxWidth * .4)
                .clamp(constraints.maxWidth < 600 ? 248.0 : 280.0, 380.0);
            return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: scene),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: panelWidth,
                    child: Column(children: [
                      guidance,
                      Expanded(child: controls),
                      actionBar,
                    ]),
                  ),
                ]);
          }
          return Column(children: [
            guidance,
            Expanded(
              child: LayoutBuilder(builder: (context, body) {
                // The primary view gives the scene roughly three quarters of
                // the working area. The explicit expansion is for forms/tools.
                final panelHeight = expandedControls
                    ? math.max(0.0,
                        body.maxHeight - math.min(176.0, body.maxHeight * .46))
                    : (body.maxHeight * .24)
                        .clamp(body.maxHeight < 400 ? 88.0 : 104.0, 184.0);
                final effectivePanelHeight =
                    math.min(panelHeight, body.maxHeight * .65);
                return Column(children: [
                  Expanded(child: scene),
                  SizedBox(
                    height: effectivePanelHeight,
                    child: Material(
                      color: AppTheme.cardWhite,
                      child: Column(children: [
                        Semantics(
                          button: true,
                          expanded: expandedControls,
                          label: expandedControls
                              ? MissionContentData.workspaceExpandScene
                              : MissionContentData.workspaceExpandControls,
                          child: InkWell(
                            key: const ValueKey('mission-controls-toggle'),
                            onTap: onToggleControls,
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 48),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: const BoxDecoration(
                                  border: Border(
                                      top: BorderSide(
                                          color: AppTheme.borderMedium))),
                              child: Row(children: [
                                const Icon(Icons.tune_rounded,
                                    size: 20, color: AppTheme.deepBlue),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(
                                        MissionContentData.controlsLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTheme.labelMedium)),
                                Icon(
                                    expandedControls
                                        ? Icons.expand_more
                                        : Icons.expand_less,
                                    color: AppTheme.deepBlue),
                              ]),
                            ),
                          ),
                        ),
                        Expanded(child: controls),
                      ]),
                    ),
                  ),
                ]);
              }),
            ),
            actionBar,
          ]);
        },
      );
}
