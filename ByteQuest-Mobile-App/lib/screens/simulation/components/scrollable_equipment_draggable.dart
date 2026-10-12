import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keeps offscreen destinations reachable in the workspace and mission controls.
class ScrollableEquipmentDraggable extends StatefulWidget {
  const ScrollableEquipmentDraggable({
    super.key,
    required this.data,
    required this.feedback,
    required this.child,
    this.childWhenDragging,
    this.enabled = true,
  });

  final String data;
  final Widget feedback;
  final Widget child;
  final Widget? childWhenDragging;
  final bool enabled;

  @override
  State<ScrollableEquipmentDraggable> createState() =>
      _ScrollableEquipmentDraggableState();
}

class _ScrollableEquipmentDraggableState
    extends State<ScrollableEquipmentDraggable> {
  Timer? _scrollTimer;
  Offset? _dragPosition;

  @override
  void didUpdateWidget(covariant ScrollableEquipmentDraggable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _stopScrolling();
  }

  @override
  void dispose() {
    _stopScrolling();
    super.dispose();
  }

  void _stopScrolling() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _dragPosition = null;
  }

  void _updateDrag(DragUpdateDetails details) {
    _dragPosition = details.globalPosition;
    _scrollTimer ??= Timer.periodic(
        const Duration(milliseconds: 30), (_) => _scrollAtEdge());
  }

  void _scrollAtEdge() {
    if (!mounted || !widget.enabled || _dragPosition == null) return;
    final scrollable = Scrollable.maybeOf(context);
    final viewport = scrollable?.context.findRenderObject();
    if (scrollable == null || viewport is! RenderBox || !viewport.hasSize) {
      return;
    }
    final position = scrollable.position;
    if (!position.hasContentDimensions ||
        position.axisDirection != AxisDirection.down) {
      return;
    }
    final local = viewport.globalToLocal(_dragPosition!);
    if (local.dx < 0 || local.dx > viewport.size.width) return;
    final edge = math.min(48.0, viewport.size.height / 3);
    if (edge <= 0) return;
    final velocity = local.dy < edge
        ? -((edge - local.dy) / edge).clamp(0.0, 1.0)
        : local.dy > viewport.size.height - edge
            ? ((local.dy - viewport.size.height + edge) / edge).clamp(0.0, 1.0)
            : 0.0;
    final next = (position.pixels + velocity * 9)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (next != position.pixels) position.jumpTo(next);
  }

  @override
  Widget build(BuildContext context) => Draggable<String>(
        data: widget.data,
        maxSimultaneousDrags: widget.enabled ? 1 : 0,
        feedback: widget.feedback,
        onDragUpdate: _updateDrag,
        onDragEnd: (_) => _stopScrolling(),
        child: widget.child,
        childWhenDragging: widget.childWhenDragging,
      );
}
