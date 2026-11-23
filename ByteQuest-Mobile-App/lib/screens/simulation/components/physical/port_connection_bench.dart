import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/mission_content_data.dart';
import '../../runtime/mission_runtime_models.dart';
import '../simulation_scene.dart';
import 'physical_surface.dart';
import 'port_bench_layout.dart';
import 'port_bench_painter.dart';

class PortConnectionBench extends StatefulWidget {
  const PortConnectionBench(
      {super.key,
      required this.layout,
      required this.phase,
      required this.state,
      required this.sources,
      required this.destinations,
      required this.enabled,
      required this.saving,
      required this.onCameraChanged,
      required this.onConnect,
      required this.onHint,
      this.onDraftChanged,
      this.highlightObjectId});
  final PortBenchLayout layout;
  final MissionPhaseDefinition phase;
  final MissionRuntimeState state;
  final List<Map<String, dynamic>> sources, destinations;
  final bool enabled, saving;
  final Future<void> Function(String source, String destination, String method)
      onConnect;
  final ValueChanged<String?> onHint;
  final ValueChanged<Map<String, dynamic>>? onDraftChanged;
  final void Function(double, Offset) onCameraChanged;
  final String? highlightObjectId;

  @override
  State<PortConnectionBench> createState() => _PortConnectionBenchState();
}

final class _PlugDrag {
  const _PlugDrag(this.source);
  final String source;
}

class _PortConnectionBenchState extends State<PortConnectionBench> {
  String? _selected, _dragging, _dragHandle;
  final Map<String, int> _localJacks = {};
  bool _busy = false;

  PortBenchLayout get _layout => widget.layout;
  Iterable<PhysicalMount> get _mounts sync* {
    for (final bank in _layout.banks.entries) {
      for (var i = 0; i < bank.value.sockets.length; i++) {
        yield _layout.mount(bank.key, i);
      }
    }
  }

  // Older snapshots describe only the logical bank. Reserve known physical choices first, then fill free jacks.
  Map<String, int> _occupied() {
    final remembered = widget.state.workbenchDraft['port_jacks'];
    final restored = <String, int>{};
    for (final bank in _layout.banks.entries) {
      final pairs = widget.state.connectedNodePairs
          .where((pair) =>
              pair.endsWith('>${bank.key}') &&
              _layout.leads.containsKey(pair.split('>').first))
          .toList()
        ..sort();
      final free = {for (var i = 0; i < bank.value.sockets.length; i++) i};
      for (final pair in pairs) {
        final choice =
            _localJacks[pair] ?? (remembered is Map ? remembered[pair] : null);
        if (choice is int && free.remove(choice)) restored[pair] = choice;
      }
      for (final pair in pairs.where((p) => !restored.containsKey(p))) {
        if (free.isEmpty) break;
        restored[pair] = free.first;
        free.remove(restored[pair]);
      }
    }
    return restored;
  }

  void _saveJacks() => widget.onDraftChanged?.call({
        ...widget.state.workbenchDraft,
        'port_jacks': _occupied(),
      });

  bool get _enabled => widget.enabled && !widget.saving && !_busy;

  void _select(String id) {
    if (!_enabled) return;
    setState(() => _selected = _selected == id ? null : id);
    widget.onHint(
        _selected == null ? null : MissionContentData.portBenchChooseJack);
  }

  Future<void> _seat(
      String source, String bank, int jack, String method) async {
    if (!_enabled) return;
    final pair = '$source>$bank';
    final occupied = _occupied();
    if (occupied.entries.any(
        (e) => e.key.endsWith('>$bank') && e.value == jack && e.key != pair)) {
      widget.onHint(MissionContentData.portBenchOccupied);
      return;
    }
    final already = widget.state.connectedNodePairs.contains(pair);
    if (already && occupied[pair] == jack) {
      widget.onHint(MissionContentData.workspaceAlreadyConnected);
      return;
    }
    setState(() {
      _selected = null;
      _busy = true;
      _localJacks[pair] = jack;
    });
    try {
      if (already) {
        widget.onHint(null);
        _saveJacks();
      } else {
        await widget.onConnect(source, bank, method);
        // The parent publishes the reducer's accepted pairs on the next build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (widget.state.connectedNodePairs.contains(pair)) {
            _saveJacks();
          } else {
            _localJacks.remove(pair);
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    final items = {
      for (final d in [...widget.destinations, ...widget.sources])
        d['id'] as String: d
    };
    String label(String id) => items[id]!['label'] as String;
    final occupied = _occupied();
    final linkedBank = {
      for (final p in occupied.keys) p.split('>').first: p.split('>').last
    };
    final leads = <String, PortLeadPose>{};
    final rects = <String, Rect>{};
    final objects = <SceneObjectDefinition>[];
    final jackInfo = <String, ({String bank, int index, String? occupant})>{};
    final canonical = <String, int>{};
    final status = <String, HotspotVisualState>{};
    final names = <String, String>{};
    void object(String id, String text, Rect rect, {required bool jack}) {
      rects[id] = PortBenchLayout.world(rect);
      objects.add(SceneObjectDefinition(
          id: id,
          label: text,
          x: rect.left / 360,
          y: rect.top / 216,
          width: rect.width / 360,
          height: rect.height / 216,
          hotspotType: jack ? 'port_destination' : 'device_source'));
    }

    for (final e in layout.leads.entries) {
      final bank = linkedBank[e.key];
      final tip = bank == null
          ? e.value.tip
          : layout.banks[bank]!.sockets[occupied['${e.key}>$bank']!];
      if (_dragging != e.key) {
        leads[e.key] = (
          root: e.value.root,
          tip: tip,
          shape: e.value.shape,
          seated: bank != null
        );
      }
      names[e.key] = MissionContentData.portPlugStatus(
          label(e.key), bank == null ? null : label(bank));
      object(e.key, label(e.key), e.value.reach, jack: false);
      status[e.key] = _selected == e.key
          ? HotspotVisualState.selected
          : bank != null
              ? HotspotVisualState.completed
              : HotspotVisualState.neutral;
    }
    for (final entry in layout.banks.entries) {
      for (var i = 0; i < entry.value.sockets.length; i++) {
        final id = '${entry.key}:$i';
        final occupant = occupied.entries
            .where((e) => e.key.endsWith('>${entry.key}') && e.value == i)
            .firstOrNull
            ?.key
            .split('>')
            .first;
        final bankLabel = entry.value.sockets.length > 1
            ? MissionContentData.portJack(label(entry.key), i + 1)
            : label(entry.key);
        names[id] = MissionContentData.portJackStatus(
            bankLabel, occupant == null ? null : label(occupant));
        jackInfo[id] = (bank: entry.key, index: i, occupant: occupant);
        status[id] = occupant == null
            ? HotspotVisualState.neutral
            : HotspotVisualState.completed;
        if (occupant == null) canonical.putIfAbsent(entry.key, () => i);
        // Tight hardware hit area; the toolbar's Objects picker offers a full ListTile for each jack.
        final mount = layout.mount(entry.key, i);
        final center = mount.snapPoint;
        final sockets = entry.value.sockets;
        final left =
            i == 0 ? mount.capture.left : (sockets[i - 1].dx + center.dx) / 2;
        final right = i + 1 == sockets.length
            ? mount.capture.right
            : (sockets[i + 1].dx + center.dx) / 2;
        final reach =
            Rect.fromLTRB(left, mount.capture.top, right, mount.capture.bottom);
        object(id, bankLabel, reach, jack: true);
      }
      canonical.putIfAbsent(entry.key, () => 0);
    }
    void activate(String id) {
      if (!_enabled) return;
      final jack = jackInfo[id];
      if (jack == null) {
        _select(id);
      } else if (_selected case final source?) {
        unawaited(_seat(source, jack.bank, jack.index, 'tap'));
      } else if (jack.occupant case final occupant?) {
        _select(occupant);
      } else {
        widget.onHint(MissionContentData.portBenchChoosePlug);
      }
    }

    return SimulationScene(
      key: ValueKey('workspace-scene-connect-${widget.phase.id}'),
      scene: SimulationSceneDefinition(
          id: '${widget.phase.id}_ports',
          objects: objects,
          initialStatus: {
            'title': layout.title,
            'prompt': MissionContentData.workspaceConnectHint
          }),
      compactToolbar: true,
      interactionHint: MissionContentData.workspaceConnectHint,
      enabled: _enabled,
      panEnabled: _enabled && _dragging == null,
      scrollEnabled: !widget.saving && _dragging == null,
      initialCameraScale: widget.state.cameraScale,
      initialCameraOffset:
          Offset(widget.state.cameraOffsetX, widget.state.cameraOffsetY),
      onCameraChanged: widget.onCameraChanged,
      hotspotStates: status,
      highlightObjectId: widget.highlightObjectId,
      physicalLayout: PhysicalSceneLayout(
          bounds: rects,
          wrap: (layers) => PhysicalDropSurface<_PlugDrag>(
                key: const ValueKey('physical-port-surface'),
                enabled: _enabled,
                worldSize: PortBenchLayout.drawing,
                mounts: (_) => _mounts.toList(growable: false),
                onRelease: (drag, point, mount) {
                  final target = jackInfo[mount?.id];
                  if (target == null) {
                    widget.onHint(MissionContentData.portBenchMiss);
                    return;
                  }
                  unawaited(
                      _seat(drag.source, target.bank, target.index, 'drag'));
                },
                preview: (_, drag, point, mount) {
                  final lead = layout.leads[drag.source]!;
                  return CustomPaint(
                      key: const ValueKey('physical-port-live-lead'),
                      painter: PortCablePainter({
                        drag.source: (
                          root: lead.root,
                          tip: point,
                          shape: lead.shape,
                          seated: false
                        )
                      }, hover: mount?.snapPoint));
                },
                child: layers,
              )),
      backgroundRenderer: Stack(fit: StackFit.expand, children: [
        CustomPaint(painter: PortPlatePainter(layout)),
        for (final device in layout.devices) ...[
          Positioned.fromRect(
              rect: PortBenchLayout.world(device.photo),
              child: ExcludeSemantics(
                  child: Image.asset(
                      items[device.id]?['imageAsset'] as String? ??
                          'assets/COC1/Mission 3/System Unit.png',
                      fit: BoxFit.contain))),
          _legend(device.name, label(device.id)),
        ],
        for (final plate in layout.plates)
          _legend(
              Rect.fromLTWH(plate.body.left + 7, plate.body.top + 1.5,
                  plate.body.width - 14, 12),
              plate.legend),
        if (layout.banks.containsKey('hdmi_port'))
          for (final bank in layout.banks.entries)
            _legend(
                Rect.fromCenter(
                    center: Offset(282, bank.value.sockets.first.dy + 15),
                    width: 97,
                    height: 13),
                label(bank.key).toUpperCase()),
        Positioned.fill(
            child: IgnorePointer(
                child: CustomPaint(
                    key: const ValueKey('physical-port-cables'),
                    painter: PortCablePainter(leads)))),
      ]),
      onObjectSelected: activate,
      objectBuilder: (object, _) {
        final id = object.id;
        final source = layout.leads[id];
        final jack = jackInfo[id];
        final enabled = _enabled;
        final key = source != null
            ? 'workspace-source-$id'
            : canonical[jack!.bank] == jack.index
                ? 'workspace-destination-${jack.bank}'
                : 'workspace-jack-$id';
        final pickup = source == null ? jack?.occupant : id;
        final active = enabled && (pickup != null || _selected != null);
        final tap = active ? () => activate(id) : null;
        final target = Semantics(
            key: ValueKey(key),
            button: true,
            enabled: active,
            selected: source != null && _selected == id,
            label: names[id],
            excludeSemantics: true,
            onTap: tap,
            child: InkWell(
                onTap: tap,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        border: source != null && _selected == id
                            ? Border.all(color: AppTheme.primaryBlue, width: 3)
                            : null,
                        borderRadius: BorderRadius.circular(10)),
                    child: const SizedBox.expand())));
        if (pickup == null) return target;
        return PhysicalDraggable<_PlugDrag>(
            data: _PlugDrag(pickup),
            maxSimultaneousDrags:
                enabled && (_dragHandle == null || _dragHandle == id) ? 1 : 0,
            onDragStarted: () {
              setState(() {
                _dragging = pickup;
                _dragHandle = id;
              });
            },
            onDragEnd: (_) {
              if (!mounted) return;
              setState(() {
                _dragging = null;
                _dragHandle = null;
              });
            },
            onDraggableCanceled: (_, __) {
              if (mounted && widget.enabled) {
                widget.onHint(MissionContentData.portBenchMiss);
              }
            },
            feedback: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                    width: 42,
                    height: 40,
                    child: CustomPaint(
                        painter:
                            PortPlugPainter(layout.leads[pickup]!.shape)))),
            child: target);
      },
    );
  }

  Widget _legend(Rect box, String text) => Positioned.fromRect(
      rect: PortBenchLayout.world(box),
      child: ExcludeSemantics(
          child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(text,
                  maxLines: 1,
                  style: AppTheme.labelLarge.copyWith(
                      fontSize: 34, height: 1.1, color: AppTheme.navy)))));
}
