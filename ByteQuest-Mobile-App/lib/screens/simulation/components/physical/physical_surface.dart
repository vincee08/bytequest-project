import 'package:flutter/material.dart';

/// A mechanical feature in scene coordinates. Capture tolerance is not the accessible tap area.
@immutable
class PhysicalMount {
  const PhysicalMount(this.id, this.bounds, {Rect? capture, this.layer = 0})
      : capture = capture ?? bounds;

  final String id;
  final Rect bounds;
  final Rect capture;
  final int layer;

  Offset get snapPoint => bounds.center;

  /// Only geometrically reachable mounts compete; this never consults a rubric or a correct destination.
  static PhysicalMount? at(Offset point, Iterable<PhysicalMount> mounts) {
    PhysicalMount? best;
    for (final mount in mounts) {
      if (!mount.capture.contains(point)) continue;
      if (best == null || mount._precedes(best, point)) best = mount;
    }
    return best;
  }

  bool _precedes(PhysicalMount other, Offset point) {
    final inside = bounds.contains(point);
    if (inside != other.bounds.contains(point)) return inside;
    if (layer != other.layer) return layer > other.layer;
    final distance = (snapPoint - point).distanceSquared;
    final otherDistance = (other.snapPoint - point).distanceSquared;
    if (distance != otherDistance) return distance < otherDistance;
    final area = bounds.width * bounds.height;
    final otherArea = other.bounds.width * other.bounds.height;
    if (area != otherArea) return area < otherArea;
    return id.compareTo(other.id) < 0;
  }
}

// Two fingers can hold separate pieces with equal IDs; track the pickup, not the ID.
class _Pickup<T extends Object> {
  _Pickup(this.data);
  final T data;
}

class PhysicalDraggable<T extends Object> extends StatelessWidget {
  const PhysicalDraggable({
    super.key,
    required this.data,
    required this.child,
    required this.feedback,
    this.childWhenDragging,
    this.feedbackAnchor = const Offset(.5, .5),
    this.affinity,
    this.maxSimultaneousDrags = 1,
    this.onDragStarted,
    this.onDragEnd,
    this.onDraggableCanceled,
  }) : assert(maxSimultaneousDrags == 0 || maxSimultaneousDrags == 1);

  final T data;
  final Widget child;
  final Widget feedback;
  final Widget? childWhenDragging;
  final Offset feedbackAnchor;
  final Axis? affinity;
  final int maxSimultaneousDrags;
  final VoidCallback? onDragStarted;
  final DragEndCallback? onDragEnd;
  final DraggableCanceledCallback? onDraggableCanceled;

  @override
  Widget build(BuildContext context) => Draggable<_Pickup<T>>(
        data: _Pickup(data),
        affinity: affinity,
        maxSimultaneousDrags: maxSimultaneousDrags,
        // Keep DragTargetDetails.offset at the finger; move only the sprite, not its hit point.
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: FractionalTranslation(
          translation: -feedbackAnchor,
          child: feedback,
        ),
        childWhenDragging: childWhenDragging,
        onDragStarted: onDragStarted,
        onDragEnd: onDragEnd,
        onDraggableCanceled: onDraggableCanceled,
        child: child,
      );
}

typedef PhysicalPreview<T> = Widget Function(
    BuildContext context, T data, Offset point, PhysicalMount? mount);

class PhysicalDropSurface<T extends Object> extends StatefulWidget {
  const PhysicalDropSurface({
    super.key,
    required this.child,
    required this.mounts,
    required this.onRelease,
    this.preview,
    this.worldSize,
    this.enabled = true,
  });

  final Widget child;
  final List<PhysicalMount> Function(T data) mounts;
  final void Function(T data, Offset point, PhysicalMount? mount) onRelease;
  final PhysicalPreview<T>? preview;
  final Size? worldSize;
  final bool enabled;

  @override
  State<PhysicalDropSurface<T>> createState() => _PhysicalDropSurfaceState<T>();
}

class _PhysicalDropSurfaceState<T extends Object>
    extends State<PhysicalDropSurface<T>> {
  final _hover = ValueNotifier<({T data, Offset point})?>(null);
  _Pickup<T>? _active;

  Offset? _worldPoint(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) return null;
    final local = box.globalToLocal(global);
    if (!(Offset.zero & box.size).contains(local)) return null;
    final world = widget.worldSize;
    if (world == null) return local;
    return Offset(local.dx / box.size.width * world.width,
        local.dy / box.size.height * world.height);
  }

  void _move(DragTargetDetails<_Pickup<T>> details) {
    if (!widget.enabled || _active != details.data || widget.preview == null) {
      return;
    }
    final point = _worldPoint(details.offset);
    _hover.value = point == null ? null : (data: details.data.data, point: point);
  }

  void _leave(_Pickup<T>? pickup) {
    if (_active != pickup) return;
    _active = null;
    _hover.value = null;
  }

  @override
  void didUpdateWidget(covariant PhysicalDropSurface<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) _leave(_active);
  }

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DragTarget<_Pickup<T>>(
        hitTestBehavior: HitTestBehavior.translucent,
        onWillAcceptWithDetails: (details) {
          if (!widget.enabled || _active != null) return false;
          _active = details.data;
          return true;
        },
        onMove: _move,
        onLeave: _leave,
        onAcceptWithDetails: (details) {
          final active = _active == details.data;
          _leave(details.data);
          if (!active || !widget.enabled) return;
          final point = _worldPoint(details.offset);
          if (point != null) {
            final data = details.data.data;
            widget.onRelease(data, point,
                PhysicalMount.at(point, widget.mounts(data)));
          }
        },
        builder: (context, _, __) => Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (widget.enabled && widget.preview != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: RepaintBoundary(
                      child: ValueListenableBuilder<({T data, Offset point})?>(
                        valueListenable: _hover,
                        builder: (context, hover, _) => hover == null
                            ? const SizedBox.shrink()
                            : Stack(fit: StackFit.expand, children: [
                                widget.preview!(
                                    context,
                                    hover.data,
                                    hover.point,
                                    PhysicalMount.at(hover.point,
                                        widget.mounts(hover.data))),
                              ]),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}
