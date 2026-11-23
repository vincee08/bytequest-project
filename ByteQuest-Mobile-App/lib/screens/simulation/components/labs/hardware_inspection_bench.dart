import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/mission_content_data.dart';
import '../../../../data/mission_simulation_definitions.dart';
import '../../runtime/mission_runtime_models.dart';
import '../assembly/assembly_bench_layout.dart';
import '../physical/physical_surface.dart';
import '../simulation_scene.dart';
import '../tool_tray.dart' show MissionActionCallback;

enum _Probe { lens }

abstract final class HardwareInspectionLayout {
  // The source photographs are 500px square; their transparent margins are not equipment.
  static const photos = {
    'motherboard': Rect.fromLTWH(-52, -27, 780, 780),
    'cpu': Rect.fromLTWH(666, 26, 204, 204),
    'ram': Rect.fromLTWH(858, 12, 318, 318),
    'psu': Rect.fromLTWH(643, 237, 366, 366),
    'anti_static_strap': Rect.fromLTWH(944, 396, 253, 253),
  };

  static Offset imagePoint(String image, Offset pixel) {
    final box = photos[image]!;
    return box.topLeft + pixel * (box.width / 500);
  }

  static Path _polygon(String image, List<Offset> points) => Path()
    ..addPolygon(points.map((p) => imagePoint(image, p)).toList(), true);

  static Path _boardFeature(double x, double y, double w, double h) => Path()
    ..addRect(Rect.fromPoints(imagePoint('motherboard', Offset(x, y)),
        imagePoint('motherboard', Offset(x + w, y + h))));

  static Path _strap() {
    const id = 'anti_static_strap';
    final wrist = _polygon(id, const [
      Offset(189, 101),
      Offset(212, 87),
      Offset(272, 91),
      Offset(338, 110),
      Offset(406, 141),
      Offset(439, 179),
      Offset(444, 204),
      Offset(434, 253),
      Offset(410, 269),
      Offset(363, 277),
      Offset(314, 256),
      Offset(211, 223),
      Offset(183, 186),
    ]);
    final hole = _polygon(id, const [
      Offset(248, 129),
      Offset(288, 136),
      Offset(353, 159),
      Offset(405, 190),
      Offset(414, 202),
      Offset(386, 197),
      Offset(305, 174),
    ]);
    return Path.combine(PathOperation.difference, wrist, hole)
      ..addPath(
          _polygon(id, const [
            Offset(230, 190),
            Offset(236, 210),
            Offset(162, 198),
            Offset(124, 194),
            Offset(88, 209),
            Offset(68, 232),
            Offset(69, 284),
            Offset(91, 316),
            Offset(141, 341),
            Offset(232, 365),
            Offset(319, 378),
            Offset(313, 415),
            Offset(227, 402),
            Offset(128, 371),
            Offset(83, 344),
            Offset(53, 312),
            Offset(44, 270),
            Offset(47, 238),
            Offset(63, 216),
            Offset(94, 192),
            Offset(129, 181),
            Offset(167, 183)
          ]),
          Offset.zero)
      ..addPath(
          _polygon(id, const [
            Offset(173, 347),
            Offset(206, 328),
            Offset(301, 313),
            Offset(304, 302),
            Offset(401, 319),
            Offset(397, 333),
            Offset(307, 342),
            Offset(221, 341),
            Offset(196, 355)
          ]),
          Offset.zero);
  }

  static final _outlines = <String, Path>{
    'motherboard': _polygon('motherboard', const [
      Offset(68, 38),
      Offset(428, 40),
      Offset(429, 459),
      Offset(77, 459),
      Offset(77, 270),
      Offset(60, 265)
    ]),
    'cpu': _polygon('cpu', const [
      Offset(25, 151),
      Offset(314, 72),
      Offset(481, 299),
      Offset(144, 420)
    ]),
    'ram': _polygon('ram', const [
      Offset(42, 212),
      Offset(454, 116),
      Offset(459, 245),
      Offset(55, 378)
    ]),
    'psu': _polygon('psu', const [
      Offset(37, 161),
      Offset(217, 67),
      Offset(474, 122),
      Offset(463, 282),
      Offset(311, 430),
      Offset(51, 326)
    ]),
    'anti_static_strap': _strap(),
    'cpu_socket': _boardFeature(222, 112, 87, 116),
    'dimm_slot': _boardFeature(328, 47, 49, 226)
      ..addPath(_boardFeature(365, 33, 15, 18), Offset.zero),
    'atx_power_port': _boardFeature(410, 103, 14, 92),
  };

  static final bounds = Map<String, Rect>.unmodifiable(
      _outlines.map((id, path) => MapEntry(id, path.getBounds())));
  static final mounts = List<PhysicalMount>.unmodifiable(bounds.entries.map(
      (e) => PhysicalMount(e.key, e.value,
          layer: photos.containsKey(e.key) ? 0 : 1)));
  static bool onPart(String id, Offset point) => _outlines[id]!.contains(point);
}

class HardwareInspectionBench extends StatefulWidget {
  const HardwareInspectionBench(
      {super.key,
      required this.definition,
      required this.phase,
      required this.state,
      required this.enabled,
      required this.saving,
      required this.highlightObjects,
      this.highlightObjectId,
      required this.onCameraChanged,
      required this.onAction});

  final MissionSimulationDefinition definition;
  final MissionPhaseDefinition phase;
  final MissionRuntimeState state;
  final bool enabled, saving, highlightObjects;
  final String? highlightObjectId;
  final void Function(double, Offset) onCameraChanged;
  final MissionActionCallback onAction;

  static bool supports(MissionSimulationDefinition definition,
      MissionPhaseDefinition phase, MissionRuntimeState state) {
    const version = 'css-sag-20261109-v3';
    return definition.id == 'coc1_m1' &&
        state.missionId == definition.id &&
        phase.id == 'coc1_m1_p1' &&
        phase.resolvedInteraction == InteractionFamily.inspect &&
        MissionSimulationDefinitions.contractVersion(definition.id) ==
            version &&
        (state.definitionVersion == version ||
            (state.mode == MissionRuntimeMode.practice &&
                state.definitionVersion == null)) &&
        definition.scene.objects.length ==
            HardwareInspectionLayout.bounds.length &&
        definition.scene.objects
            .every((o) => HardwareInspectionLayout.bounds.containsKey(o.id));
  }

  @override
  State<HardwareInspectionBench> createState() =>
      _HardwareInspectionBenchState();
}

class _HardwareInspectionBenchState extends State<HardwareInspectionBench> {
  String? _focused;
  bool _missed = false;
  bool get _enabled => widget.enabled && !widget.saving;
  bool get _practice => widget.state.mode == MissionRuntimeMode.practice;

  bool _seen(String id) => switch (widget.state.hotspotStates[id]) {
        HotspotVisualState.selected || HotspotVisualState.completed => true,
        _ => false,
      };

  @override
  void didUpdateWidget(covariant HardwareInspectionBench oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final id in HardwareInspectionLayout.bounds.keys) {
      if (_seen(id) &&
          oldWidget.state.hotspotStates[id] != widget.state.hotspotStates[id]) {
        _focused = id;
        _missed = false;
      }
    }
  }

  void _inspect(String id) {
    if (!_enabled) return;
    setState(() {
      _focused = id;
      _missed = false;
    });
    unawaited(widget
        .onAction('object_inspected', id, const {'input_method': 'scene'}));
  }

  void _details(String title, String text) {
    showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              scrollable: true,
              title: Text(title),
              content: Text(text),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(MissionContentData.backLabel)),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    final objects = {for (final o in widget.definition.scene.objects) o.id: o};
    final id = _focused ?? objects.keys.where(_seen).lastOrNull;
    final seen = id != null && _seen(id) && !_missed;
    final reading = seen ? MissionContentData.hardwareObservations[id] : null;
    final message = reading ??
        (_missed
            ? MissionContentData.inspectionLensMiss
            : MissionContentData.inspectionLensHint);
    final art = _InspectionArtwork(objects: objects);
    return Column(key: const ValueKey('hardware-inspection-bench'), children: [
      Expanded(
          child: SimulationScene(
        scene: widget.definition.scene,
        compactToolbar: true,
        enabled: _enabled,
        panEnabled: _enabled,
        scrollEnabled: !widget.saving,
        highlightObjects: _practice && widget.highlightObjects,
        highlightObjectId: _practice ? widget.highlightObjectId : null,
        initialCameraScale: widget.state.cameraScale,
        initialCameraOffset:
            Offset(widget.state.cameraOffsetX, widget.state.cameraOffsetY),
        onCameraChanged: widget.onCameraChanged,
        onObjectSelected: _inspect,
        hotspotStates: widget.state.hotspotStates,
        backgroundRenderer: art,
        physicalLayout: PhysicalSceneLayout(
          bounds: HardwareInspectionLayout.bounds,
          wrap: (layers) => PhysicalDropSurface<_Probe>(
            enabled: _enabled,
            worldSize: SimulationScene.logicalCanvasSize,
            mounts: (_) => HardwareInspectionLayout.mounts,
            onRelease: (_, point, mount) {
              if (mount != null &&
                  HardwareInspectionLayout.onPart(mount.id, point)) {
                _inspect(mount.id);
              } else if (mount != null &&
                  HardwareInspectionLayout.onPart('motherboard', point)) {
                _inspect('motherboard');
              } else {
                setState(() => _missed = true);
              }
            },
            preview: (context, probe, point, mount) =>
                _Loupe(point: point, art: art),
            child: layers,
          ),
        ),
        objectBuilder: (object, _) => ClipPath(
          clipper: _OutlineClipper(object.id),
          child: Semantics(
            button: true,
            enabled: _enabled,
            selected: _seen(object.id),
            label: MissionContentData.benchInspectSemantics(
                object.label, _seen(object.id)),
            child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _enabled ? () => _inspect(object.id) : null,
                  child: _seen(object.id)
                      ? Align(
                          alignment: Alignment.center,
                          child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: DecoratedBox(
                                key: ValueKey('inspection-seen-${object.id}'),
                                decoration: const BoxDecoration(
                                    color: AppTheme.navy,
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.check,
                                    size: 36, color: Colors.white),
                              )))
                      : const SizedBox.expand(),
                )),
          ),
        ),
      )),
      Material(
          color: AppTheme.backgroundPaleBlue,
          child: Row(children: [
            PhysicalDraggable<_Probe>(
              key: const ValueKey('inspection-probe'),
              data: _Probe.lens,
              maxSimultaneousDrags: _enabled ? 1 : 0,
              feedback: const IgnorePointer(
                  child: Icon(Icons.gps_fixed,
                      size: 26, color: AppTheme.primaryBlue)),
              child: IconButton(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: MissionContentData.inspectionLensLabel,
                icon: const Icon(Icons.search, color: AppTheme.deepBlue),
                onPressed: _enabled
                    ? () => _details(MissionContentData.inspectionLensLabel,
                        MissionContentData.inspectionLensHelp)
                    : null,
              ),
            ),
            Expanded(
                child: Semantics(
              liveRegion: reading != null || _missed,
              child: TextButton(
                key: const ValueKey('inspection-readout'),
                style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    alignment: Alignment.centerLeft),
                onPressed: () => _details(
                    seen
                        ? objects[id]!.label
                        : MissionContentData.inspectionLensLabel,
                    reading ?? MissionContentData.inspectionLensHelp),
                child: Text(message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySmall),
              ),
            )),
          ])),
    ]);
  }
}

class _OutlineClipper extends CustomClipper<Path> {
  const _OutlineClipper(this.id);
  final String id;
  @override
  Path getClip(Size size) => HardwareInspectionLayout._outlines[id]!
      .shift(-HardwareInspectionLayout.bounds[id]!.topLeft);
  @override
  bool shouldReclip(_OutlineClipper oldClipper) => oldClipper.id != id;
}

class _InspectionArtwork extends StatelessWidget {
  const _InspectionArtwork({required this.objects});
  final Map<String, SceneObjectDefinition> objects;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
          child: RepaintBoundary(
              child: ColoredBox(
        color: AppTheme.borderMedium,
        child: Stack(children: [
          for (final e in HardwareInspectionLayout.photos.entries)
            Positioned.fromRect(
                rect: e.value,
                child: Image.asset(
                    e.key == 'motherboard'
                        ? AssemblyBenchLayout.boardAsset
                        : objects[e.key]!.metadata['imageAsset'] as String,
                    key: ValueKey('inspection-photo-${e.key}'),
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true)),
          const Positioned.fill(child: CustomPaint(painter: _BoardMarks())),
        ]),
      )));
}

class _BoardMarks extends CustomPainter {
  const _BoardMarks();
  @override
  void paint(Canvas canvas, Size size) {
    final photo = HardwareInspectionLayout.photos['motherboard']!;
    canvas.save();
    canvas.translate(photo.left, photo.top);
    canvas.scale(photo.width / 500);
    // One retaining latch is open in this work order; the base photograph has all four closed.
    canvas.drawPath(
        Path()
          ..moveTo(366, 53)
          ..lineTo(372, 54)
          ..lineTo(380, 38)
          ..lineTo(375, 35)
          ..lineTo(369, 42)
          ..close(),
        Paint()..color = const Color(0xff9ca4ac));
    canvas.drawCircle(
        const Offset(369.5, 51), 2, Paint()..color = AppTheme.textDark);
    canvas.drawPath(
        Path()
          ..moveTo(225, 214)
          ..lineTo(233, 214)
          ..lineTo(225, 206)
          ..close(),
        Paint()..color = const Color(0xffd7b75e));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BoardMarks oldDelegate) => false;
}

class _Loupe extends StatelessWidget {
  const _Loupe({required this.point, required this.art});
  final Offset point;
  final Widget art;

  @override
  Widget build(BuildContext context) {
    const world = SimulationScene.logicalCanvasSize;
    const radius = 108.0, zoom = 2.4;
    final centre = Offset(
        point.dx.clamp(radius, world.width - radius),
        (point.dy < radius * 2 + 30
                ? point.dy + radius + 24
                : point.dy - radius - 24)
            .clamp(radius, world.height - radius));
    return Positioned.fromRect(
        rect: Rect.fromCircle(center: centre, radius: radius),
        child: ClipOval(
          key: const ValueKey('inspection-loupe'),
          child: Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: AppTheme.borderMedium),
            Positioned(
                left: radius - point.dx * zoom,
                top: radius - point.dy * zoom,
                width: world.width * zoom,
                height: world.height * zoom,
                child: FittedBox(
                    fit: BoxFit.fill,
                    child: SizedBox.fromSize(size: world, child: art))),
            DecoratedBox(
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(width: 8, color: AppTheme.navy))),
          ]),
        ));
  }
}
