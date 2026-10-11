import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/mission_content_data.dart';
import '../runtime/mission_equipment_simulator.dart';
import '../runtime/mission_runtime_models.dart';
import 'component_orientation_dialog.dart';
import 'simulation_scene.dart';
import 'tool_tray.dart';

enum _WorkspaceMode { place, connect, inspect }

/// Equipment interaction layer for the shared zoomable scene engine.
/// Actions use the existing evidence gateway and physical compatibility model.
/// Assessment and COC4 callers retain the inspection scene without drag controls.
class EquipmentWorkspace extends StatefulWidget {
  const EquipmentWorkspace({
    super.key,
    required this.definition,
    required this.phase,
    required this.state,
    required this.onAction,
    required this.onCameraChanged,
    required this.hotspotStates,
    required this.enabled,
    this.saving = false,
    this.feedback,
  });

  final MissionSimulationDefinition definition;
  final MissionPhaseDefinition phase;
  final MissionRuntimeState state;
  final MissionActionCallback onAction;
  final void Function(double scale, Offset offset) onCameraChanged;
  final Map<String, HotspotVisualState> hotspotStates;
  final bool enabled;
  final bool saving;
  final String? feedback;

  @override
  State<EquipmentWorkspace> createState() => _EquipmentWorkspaceState();
}

class _EquipmentWorkspaceState extends State<EquipmentWorkspace> {
  _WorkspaceMode? _mode;
  String? _selected;
  bool _choosingOrientation = false;

  Map<String, dynamic> get _equipment =>
      MissionEquipmentSimulator.map(widget.phase.presentation['equipment']);

  Map<String, dynamic> _panel(_WorkspaceMode mode) {
    final family = mode == _WorkspaceMode.place
        ? InteractionFamily.place
        : InteractionFamily.connect;
    if (widget.phase.resolvedInteraction == family) {
      return widget.phase.presentation;
    }
    return MissionEquipmentSimulator.map(
        _equipment[mode == _WorkspaceMode.place ? 'placement' : 'connection']);
  }

  @override
  void didUpdateWidget(covariant EquipmentWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase.id != widget.phase.id) {
      _mode = null;
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.state.mode == MissionRuntimeMode.practice &&
        !widget.definition.cocId.startsWith('coc4') &&
        widget.phase.resolvedInteraction != InteractionFamily.review;
    final modes = [
      if (interactive && _panel(_WorkspaceMode.place).isNotEmpty)
        _WorkspaceMode.place,
      if (interactive && _panel(_WorkspaceMode.connect).isNotEmpty)
        _WorkspaceMode.connect,
      _WorkspaceMode.inspect,
    ];
    final mode = modes.contains(_mode) ? _mode! : modes.first;
    final panel =
        mode == _WorkspaceMode.inspect ? <String, dynamic>{} : _panel(mode);
    final sources = MissionEquipmentSimulator.maps(
        panel[mode == _WorkspaceMode.place ? 'items' : 'sources']);
    final destinations = MissionEquipmentSimulator.maps(panel['destinations']);
    final scene = mode == _WorkspaceMode.inspect
        ? widget.definition.scene
        : _workScene(mode, sources, destinations);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (modes.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final option in modes)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Semantics(
                        button: true,
                        selected: mode == option,
                        liveRegion: widget.saving && mode == option,
                        label: widget.saving && mode == option
                            ? MissionContentData.workspaceSavingLabel
                            : _label(option),
                        child: ChoiceChip(
                          key: ValueKey('workspace-mode-${option.name}'),
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          selected: mode == option,
                          label: Text(widget.saving && mode == option
                              ? MissionContentData.workspaceSavingLabel
                              : _label(option)),
                          onSelected: widget.enabled
                              ? (_) => setState(() {
                                    _mode = option;
                                    _selected = null;
                                  })
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              SimulationScene(
                scene: scene,
                compactToolbar: mode != _WorkspaceMode.inspect,
                panEnabled: widget.enabled && mode == _WorkspaceMode.inspect,
                initialCameraScale: widget.state.cameraScale,
                initialCameraOffset: Offset(
                    widget.state.cameraOffsetX, widget.state.cameraOffsetY),
                onCameraChanged: widget.onCameraChanged,
                interactionHint: switch (mode) {
                  _WorkspaceMode.place => MissionContentData.workspaceBuildHint,
                  _WorkspaceMode.connect =>
                    MissionContentData.workspaceConnectHint,
                  _WorkspaceMode.inspect =>
                    MissionContentData.workspaceInspectHint,
                },
                hotspotStates: {
                  ...widget.hotspotStates,
                  if (mode != _WorkspaceMode.inspect)
                    for (final destination in destinations)
                      if (widget.hotspotStates[destination['id']] != null)
                        'destination:${destination['id']}':
                            widget.hotspotStates[destination['id']]!,
                  if (_selected != null)
                    _selected!: HotspotVisualState.selected,
                },
                connectedNodePairs: mode == _WorkspaceMode.inspect
                    ? widget.state.connectedNodePairs
                    : mode == _WorkspaceMode.connect
                        ? {
                            for (final pair in widget.state.connectedNodePairs)
                              '${pair.split('>').first}>destination:${pair.split('>').last}',
                          }
                        : const {},
                enabled: widget.enabled && !_choosingOrientation,
                onObjectSelected: (id) {
                  if (mode == _WorkspaceMode.inspect) {
                    unawaited(widget.onAction('object_inspected', id,
                        const {'input_method': 'scene'}));
                  } else if (id.startsWith('destination:')) {
                    if (_selected != null) {
                      unawaited(_apply(mode, _selected!,
                          id.substring('destination:'.length), sources, 'tap'));
                    }
                  } else if (sources.any((source) => source['id'] == id)) {
                    setState(() => _selected = id);
                  }
                },
                objectBuilder: mode == _WorkspaceMode.inspect
                    ? null
                    : (object, hotspot) {
                        final equipmentId =
                            object.metadata['equipmentId'] as String;
                        if (object.metadata['destination'] != true) {
                          return Semantics(
                            label: MissionContentData.workspaceDragLabel(
                                object.label),
                            child: Draggable<String>(
                              key: ValueKey('workspace-source-$equipmentId'),
                              data: equipmentId,
                              maxSimultaneousDrags:
                                  widget.enabled && !_choosingOrientation
                                      ? 1
                                      : 0,
                              feedback: Material(
                                elevation: 2,
                                borderRadius: AppTheme.radiusSm,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(object.label,
                                      style: AppTheme.labelLarge),
                                ),
                              ),
                              childWhenDragging:
                                  Opacity(opacity: .35, child: hotspot),
                              child: hotspot,
                            ),
                          );
                        }
                        return Semantics(
                          label: MissionContentData.workspaceDropLabel(
                              object.label),
                          child: DragTarget<String>(
                            key: ValueKey('workspace-destination-$equipmentId'),
                            onWillAcceptWithDetails: (details) =>
                                widget.enabled &&
                                !_choosingOrientation &&
                                sources.any(
                                    (source) => source['id'] == details.data),
                            onAcceptWithDetails: (details) => unawaited(_apply(
                                mode,
                                details.data,
                                equipmentId,
                                sources,
                                'drag')),
                            builder: (_, candidates, __) => DecoratedBox(
                              decoration: BoxDecoration(
                                border: candidates.isEmpty
                                    ? null
                                    : Border.all(
                                        color: AppTheme.primaryBlue, width: 3),
                                borderRadius: AppTheme.radiusSm,
                              ),
                              child: hotspot,
                            ),
                          ),
                        );
                      },
              ),
              if (widget.feedback != null)
                Positioned(
                  left: 8,
                  right: 8,
                  top: 56,
                  child: IgnorePointer(
                    child: Semantics(
                      liveRegion: true,
                      label: widget.feedback,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        color: AppTheme.softBlueAccent,
                        child: Text(widget.feedback!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.bodySmall),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  SimulationSceneDefinition _workScene(
      _WorkspaceMode mode,
      List<Map<String, dynamic>> sources,
      List<Map<String, dynamic>> destinations) {
    final rows = ((sources.length > destinations.length
                ? sources.length
                : destinations.length) /
            2)
        .ceil();
    final height = (.78 / rows).clamp(.12, .26).toDouble();
    SceneObjectDefinition object(
        Map<String, dynamic> data, int index, bool destination) {
      final id = data['id'] as String;
      final placed = mode == _WorkspaceMode.place && destination
          ? sources
              .where((source) => widget.state.placements[source['id']] == id)
          : const Iterable<Map<String, dynamic>>.empty();
      final installed = placed.isEmpty ? null : placed.first;
      return SceneObjectDefinition(
        id: destination ? 'destination:$id' : id,
        label: installed == null
            ? data['label'] as String
            : '${installed['label']} · ${data['label']}',
        x: (destination ? .55 : .03) + (index % 2) * .23,
        y: .09 + (index ~/ 2) * (.82 / rows),
        width: .20,
        height: height,
        hotspotType: destination ? 'port_destination' : 'device_source',
        connectionNodeIds: [id],
        initialState: installed != null
            ? HotspotVisualState.completed
            : HotspotVisualState.neutral,
        metadata: {
          'equipmentId': id,
          'destination': destination,
          'imageAsset': installed?['imageAsset'] ?? data['imageAsset'],
        },
      );
    }

    return SimulationSceneDefinition(
      id: '${widget.definition.id}_equipment_workspace',
      objects: [
        for (var i = 0; i < sources.length; i++) object(sources[i], i, false),
        for (var i = 0; i < destinations.length; i++)
          object(destinations[i], i, true),
      ],
      initialStatus: {
        'title': _label(mode),
        'prompt': mode == _WorkspaceMode.place
            ? MissionContentData.workspaceBuildHint
            : MissionContentData.workspaceConnectHint,
        'sceneKind': widget.definition.scene.initialStatus['sceneKind'],
      },
    );
  }

  Future<void> _apply(_WorkspaceMode mode, String source, String destination,
      List<Map<String, dynamic>> sources, String inputMethod) async {
    if (!widget.enabled || _choosingOrientation) return;
    final phaseId = widget.phase.id;
    String? orientation;
    if (mode == _WorkspaceMode.place) {
      final part = sources.firstWhere((item) => item['id'] == source);
      final orientations =
          MissionEquipmentSimulator.strings(part['orientations']);
      if (orientations.isNotEmpty) {
        setState(() => _choosingOrientation = true);
        orientation =
            await showComponentOrientationDialog(context, orientations);
        if (!mounted) return;
        setState(() => _choosingOrientation = false);
        if (orientation == null || widget.phase.id != phaseId) return;
      }
    }
    if (!mounted || widget.phase.id != phaseId || !widget.enabled) return;
    setState(() => _selected = null);
    await widget.onAction(
      mode == _WorkspaceMode.place
          ? 'placement_attempted'
          : 'connection_created',
      destination,
      {
        if (mode == _WorkspaceMode.place)
          'item_id': source
        else
          'source_id': source,
        'destination_id': destination,
        if (orientation != null) 'orientation': orientation,
        'input_method': inputMethod,
      },
    );
  }

  String _label(_WorkspaceMode mode) => switch (mode) {
        _WorkspaceMode.place => MissionContentData.workspaceBuildLabel,
        _WorkspaceMode.connect => MissionContentData.workspaceConnectLabel,
        _WorkspaceMode.inspect => MissionContentData.workspaceInspectLabel,
      };
}
