import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../runtime/mission_runtime_models.dart';

/// Presentation-only control for a scene object.
///
/// The scene owns coordinate mapping and runtime transitions. This widget only
/// exposes a dependable touch target and renders the supplied visual state.
class HotspotWidget extends StatelessWidget {
  final SceneObjectDefinition object;
  final HotspotVisualState state;
  final bool enabled;
  final VoidCallback onPressed;
  final IconData? icon;

  /// Counteracts the logical-canvas transform so content stays legible in dp.
  final double visualScale;

  const HotspotWidget({
    super.key,
    required this.object,
    required this.state,
    required this.enabled,
    required this.onPressed,
    this.icon,
    this.visualScale = 1,
  });

  static const double minimumTapExtent = 48;

  @override
  Widget build(BuildContext context) {
    final colors = _colorsFor(state);
    final foreground = enabled ? colors.foreground : AppTheme.textLight;
    final actionLabel = object.metadata['actionLabel'] as String?;
    final completedLabel = object.metadata['completedLabel'] as String?;
    final imageAsset = object.metadata['imageAsset'];
    final imagePath =
        imageAsset is String && imageAsset.isNotEmpty ? imageAsset : null;
    final transitionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppTheme.simulationTransitionDuration;
    return Semantics(
      key: key ?? ValueKey('hotspot-${object.id}'),
      button: true,
      enabled: enabled,
      selected: state == HotspotVisualState.selected ||
          state == HotspotVisualState.completed,
      label: '${object.label}, ${state.name}',
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: Tooltip(
        message: '${object.label}, ${state.name}',
        child: AnimatedContainer(
          clipBehavior: Clip.antiAlias,
          duration: transitionDuration,
          constraints: const BoxConstraints(
            minWidth: minimumTapExtent,
            minHeight: minimumTapExtent,
          ),
          decoration: BoxDecoration(
            color: enabled
                ? (state == HotspotVisualState.neutral &&
                        object.metadata['destination'] == false
                    ? AppTheme.backgroundPaleBlue
                    : colors.background)
                : AppTheme.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: enabled ? colors.foreground : AppTheme.borderMedium,
                width: 2),
          ),
          alignment: Alignment.center,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: EdgeInsets.all(4 * visualScale),
                    child: LayoutBuilder(builder: (context, constraints) {
                      final textScaler = MediaQuery.textScalerOf(context);
                      final lineHeight =
                          textScaler.scale(12 * visualScale) * 1.15;
                      final lines = (constraints.maxHeight / lineHeight)
                          .floor()
                          .clamp(1, 2);
                      final labelHeight =
                          math.min(constraints.maxHeight, lineHeight * lines);
                      final gap = 4 * visualScale;
                      final artworkHeight = 24 * visualScale;
                      final showArtwork = !(imagePath == null &&
                              completedLabel != null &&
                              state == HotspotVisualState.completed) &&
                          constraints.maxHeight >=
                              labelHeight + gap + artworkHeight;
                      final hintHeight =
                          textScaler.scale(10 * visualScale) * 1.15;
                      final showHint = actionLabel != null &&
                          constraints.maxHeight >=
                              labelHeight +
                                  gap +
                                  (showArtwork ? artworkHeight + gap : 0) +
                                  hintHeight;
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (showArtwork) ...[
                            Expanded(
                                child: imagePath != null
                                    ? Stack(fit: StackFit.expand, children: [
                                        Image.asset(imagePath,
                                            key: ValueKey(
                                                'hotspot-image-${object.id}'),
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) => Icon(
                                                Icons.broken_image_outlined,
                                                color: AppTheme.errorRed,
                                                size: artworkHeight)),
                                        if (state != HotspotVisualState.neutral)
                                          Positioned(
                                              top: 0,
                                              right: 0,
                                              child: Icon(
                                                  _stateIcon(state,
                                                      Icons.check_rounded),
                                                  color: foreground,
                                                  size: 16 * visualScale)),
                                      ])
                                    : Center(
                                        child: AnimatedScale(
                                        duration: transitionDuration,
                                        curve: Curves.easeOutCubic,
                                        scale:
                                            state == HotspotVisualState.neutral
                                                ? .92
                                                : 1,
                                        child: AnimatedSwitcher(
                                          duration: transitionDuration,
                                          switchInCurve: Curves.easeOutCubic,
                                          switchOutCurve: Curves.easeInCubic,
                                          child: Icon(
                                            _stateIcon(
                                                state,
                                                icon ??
                                                    _iconFor(
                                                        object.hotspotType)),
                                            key: ValueKey(state),
                                            color: foreground,
                                            size: artworkHeight,
                                          ),
                                        ),
                                      ))),
                            SizedBox(height: gap),
                          ],
                          SizedBox(
                            height: labelHeight,
                            child: Center(
                                child: Text(
                              object.label,
                              textAlign: TextAlign.center,
                              maxLines: lines,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12 * visualScale,
                                  color: foreground,
                                  height: 1.15),
                            )),
                          ),
                          if (showHint) ...[
                            SizedBox(height: gap),
                            SizedBox(
                                height: hintHeight,
                                child: Text(
                                    state == HotspotVisualState.completed
                                        ? completedLabel ?? actionLabel
                                        : actionLabel,
                                    style: TextStyle(
                                        fontSize: 10 * visualScale,
                                        color: foreground,
                                        height: 1.15),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                          ],
                        ],
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

({Color background, Color foreground}) _colorsFor(HotspotVisualState state) =>
    switch (state) {
      HotspotVisualState.neutral => (
          background: Colors.white,
          foreground: AppTheme.deepBlue,
        ),
      HotspotVisualState.selected => (
          background: AppTheme.softBlueAccent,
          foreground: AppTheme.primaryBlue,
        ),
      HotspotVisualState.completed => (
          background: AppTheme.primaryBlue,
          foreground: Colors.white,
        ),
      HotspotVisualState.error => (
          background: const Color(0xFFFFECEE),
          foreground: AppTheme.errorRed,
        ),
    };

IconData _stateIcon(HotspotVisualState state, IconData neutralIcon) =>
    switch (state) {
      HotspotVisualState.neutral => neutralIcon,
      HotspotVisualState.selected => Icons.radio_button_checked_rounded,
      HotspotVisualState.completed => Icons.check_rounded,
      HotspotVisualState.error => Icons.priority_high_rounded,
    };

IconData _iconFor(String type) {
  final normalized = type.toLowerCase();
  if (normalized.contains('port') || normalized.contains('connect')) {
    return Icons.cable_outlined;
  }
  if (normalized.contains('tool')) return Icons.handyman_outlined;
  if (normalized.contains('server')) return Icons.dns_outlined;
  if (normalized.contains('device')) return Icons.memory_outlined;
  return Icons.search_rounded;
}
