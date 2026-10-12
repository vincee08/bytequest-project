import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Reusable ByteQuest card surface.
///
/// Cards default to a quiet border. Elevation is reserved for featured or
/// floating content so the interface remains calm and easy to scan.
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final Color? color;
  final VoidCallback? onTap;
  final double? elevation;
  final Border? border;
  final Gradient? gradient;

  const SoftCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.color,
    this.onTap,
    this.elevation,
    this.border,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final List<BoxShadow> shadows;
    if (elevation == null || elevation == 0) {
      shadows = const [];
    } else if (elevation! < 5) {
      shadows = AppTheme.softShadow;
    } else if (elevation! < 10) {
      shadows = AppTheme.cardShadow;
    } else {
      shadows = AppTheme.elevatedShadow;
    }

    final decoration = BoxDecoration(
      color: gradient == null ? (color ?? AppTheme.cardWhite) : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(borderRadius ?? 16),
      border: border ??
          ((elevation == null || elevation == 0)
              ? Border.all(
                  color: onTap != null
                      ? AppTheme.primaryBlue
                      : AppTheme.borderLight,
                  width: onTap != null ? 1.3 : 1)
              : null),
      boxShadow: shadows,
    );

    if (onTap != null) {
      return Semantics(
        button: true,
        child: Material(
          color: Colors.transparent,
          child: Padding(
              padding: margin ?? EdgeInsets.zero,
              child: Ink(
                  decoration: decoration,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(borderRadius ?? 16),
                    child: Padding(
                        padding: padding ?? const EdgeInsets.all(16),
                        child: child),
                  ))),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: margin ?? EdgeInsets.zero,
        child: Ink(
          decoration: decoration,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}
