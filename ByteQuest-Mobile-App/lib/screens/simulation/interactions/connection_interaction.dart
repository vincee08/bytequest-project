import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/mission_content_data.dart';
import '../components/tool_tray.dart';
import '../runtime/mission_runtime_models.dart';
import '../templates/authoritative_mission_contract.dart';
import 'multi_select_interaction.dart';

class ConnectionInteraction extends StatefulWidget {
  const ConnectionInteraction({
    super.key,
    required this.phase,
    required this.state,
    required this.onAction,
    this.enabled = true,
  });

  final MissionPhaseDefinition phase;
  final MissionRuntimeState state;
  final MissionActionCallback onAction;
  final bool enabled;

  @override
  State<ConnectionInteraction> createState() => _ConnectionInteractionState();
}

class _ConnectionInteractionState extends State<ConnectionInteraction> {
  String? _sourceId;
  bool _reviewingCompletedControls = false;

  @override
  void didUpdateWidget(covariant ConnectionInteraction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase.id != widget.phase.id) {
      _sourceId = null;
      _reviewingCompletedControls = false;
      return;
    }
    if (!widget.state.interactionCompletedPhaseIds.contains(widget.phase.id)) {
      _reviewingCompletedControls = false;
    }
    if (widget.state.interactionCompletedPhaseIds.contains(widget.phase.id) &&
        !_reviewingCompletedControls &&
        _sourceId != null &&
        _sourceHasConnection(_sourceId!)) {
      _sourceId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = interactionItems(widget.phase.presentation['sources']);
    final destinations =
        interactionItems(widget.phase.presentation['destinations']);
    final interactionComplete =
        widget.state.interactionCompletedPhaseIds.contains(widget.phase.id);
    final showControls = !interactionComplete || _reviewingCompletedControls;
    final recordedConnections = widget.state.connectedNodePairs
        .map((pair) => _connectionLabel(pair, sources, destinations))
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showControls) ...[
          const MissionSectionLabel(
              icon: Icons.cable_outlined, text: 'Sources'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final source in sources)
                Semantics(
                  button: true,
                  selected: _sourceId == source.id,
                  enabled: widget.enabled,
                  child: Draggable<String>(
                    data: source.id,
                    maxSimultaneousDrags: widget.enabled ? 1 : 0,
                    feedback: Material(child: Chip(label: Text(source.label))),
                    child: ChoiceChip(
                      key: ValueKey('connection-source-${source.id}'),
                      label: Text(source.label),
                      selected: _sourceId == source.id,
                      onSelected: widget.enabled
                          ? (_) => setState(() => _sourceId = source.id)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const MissionSectionLabel(
            icon: Icons.hub_outlined,
            text: 'Destinations',
          ),
          const SizedBox(height: 8),
          for (final destination in destinations) ...[
            DragTarget<String>(
              onWillAcceptWithDetails: (_) => widget.enabled,
              onAcceptWithDetails: (details) => _connect(
                details.data,
                destination.id,
                'drag',
              ),
              builder: (context, candidates, _) => OutlinedButton.icon(
                key: ValueKey('connection-destination-${destination.id}'),
                onPressed: widget.enabled && _sourceId != null
                    ? () => _connect(_sourceId!, destination.id, 'tap')
                    : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor:
                      candidates.isEmpty ? null : AppTheme.softBlueAccent,
                ),
                icon: const Icon(Icons.settings_input_component_outlined),
                label: Text(destination.label),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (recordedConnections.isNotEmpty) ...[
          ConnectionPath(connections: recordedConnections),
          const SizedBox(height: 4),
        ],
        if (interactionComplete)
          TextButton.icon(
            key: const ValueKey('connection-toggle-completed-controls'),
            onPressed: widget.enabled
                ? () => setState(() {
                      _reviewingCompletedControls =
                          !_reviewingCompletedControls;
                    })
                : null,
            icon: Icon(
              _reviewingCompletedControls
                  ? Icons.visibility_off_outlined
                  : Icons.edit_outlined,
            ),
            label: Text(
              _reviewingCompletedControls
                  ? MissionContentData.hideCompletedControlsLabel
                  : MissionContentData.reviewOrChangeConnectionsLabel,
            ),
          ),
      ],
    );
  }

  bool _sourceHasConnection(String sourceId) => widget.state.connectedNodePairs
      .any((pair) => pair.startsWith('$sourceId>'));

  String _connectionLabel(
    String pair,
    List<InteractionItem> sources,
    List<InteractionItem> destinations,
  ) {
    final separator = pair.indexOf('>');
    if (separator <= 0 || separator == pair.length - 1) return pair;
    final sourceId = pair.substring(0, separator);
    final destinationId = pair.substring(separator + 1);
    return '${_labelFor(sources, sourceId)} → '
        '${_labelFor(destinations, destinationId)}';
  }

  String _labelFor(List<InteractionItem> items, String id) {
    for (final item in items) {
      if (item.id == id) return item.label;
    }
    return id;
  }

  void _connect(String source, String destination, String inputMethod) {
    setState(() => _sourceId = null);
    unawaited(HapticFeedback.selectionClick());
    unawaited(widget.onAction('connection_created', destination, {
      'source_id': source,
      'destination_id': destination,
      'input_method': inputMethod,
    }));
  }
}

class ComponentPlacement extends StatefulWidget {
  const ComponentPlacement({
    super.key,
    required this.stage,
    required this.selectedMatchField,
    required this.fieldValues,
    required this.writing,
    required this.onFieldSelected,
    required this.onSourceSelected,
    required this.onDestinationSelected,
  });

  final AuthoritativeMissionStage stage;
  final String? selectedMatchField;
  final Map<String, String> fieldValues;
  final bool writing;
  final void Function(String field, String value) onFieldSelected;
  final ValueChanged<String?> onSourceSelected;
  final ValueChanged<String> onDestinationSelected;

  @override
  State<ComponentPlacement> createState() => _ComponentPlacementState();
}

class _ComponentPlacementState extends State<ComponentPlacement> {
  bool _reviewingCompletedControls = false;

  bool get _interactionComplete =>
      widget.stage.requiredCount > 0 &&
      widget.fieldValues.length >= widget.stage.requiredCount;

  @override
  void didUpdateWidget(covariant ComponentPlacement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage.id != widget.stage.id || !_interactionComplete) {
      _reviewingCompletedControls = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinations = <String, String>{};
    for (final field in widget.stage.fields) {
      for (final option in field.options) {
        destinations.putIfAbsent(option.id, () => option.label);
      }
    }
    String sourceLabel(String id) =>
        widget.stage.fields.firstWhere((field) => field.id == id).label;
    final showControls = !_interactionComplete || _reviewingCompletedControls;
    final availableFields = _reviewingCompletedControls
        ? widget.stage.fields
        : widget.stage.fields
            .where((field) => !widget.fieldValues.containsKey(field.id))
            .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showControls) ...[
          const MissionSectionLabel(
            icon: Icons.cable_outlined,
            text: 'Source components',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final field in availableFields)
                Semantics(
                  key: ValueKey('assessment-match-source-${field.id}'),
                  button: true,
                  selected: widget.selectedMatchField == field.id,
                  excludeSemantics: true,
                  label: widget.fieldValues[field.id] == null
                      ? '${field.label}, not connected'
                      : '${field.label}, connected to ${destinations[widget.fieldValues[field.id]]}',
                  child: Draggable<String>(
                    data: field.id,
                    maxSimultaneousDrags: widget.writing ? 0 : 1,
                    feedback: Material(
                      color: Colors.transparent,
                      child: _ConnectionChip(
                        label: field.label,
                        selected: true,
                      ),
                    ),
                    child: InkWell(
                      onTap: widget.writing
                          ? null
                          : () => widget.onSourceSelected(
                                widget.selectedMatchField == field.id
                                    ? null
                                    : field.id,
                              ),
                      child: _ConnectionChip(
                        label: widget.fieldValues[field.id] == null
                            ? field.label
                            : '${field.label} → ${destinations[widget.fieldValues[field.id]]}',
                        selected: widget.selectedMatchField == field.id,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        ConnectionPath(
          connections: widget.fieldValues.entries
              .map((entry) =>
                  '${sourceLabel(entry.key)} → ${destinations[entry.value]}')
              .toList(growable: false),
        ),
        if (showControls) ...[
          const SizedBox(height: 12),
          const MissionSectionLabel(
              icon: Icons.hub_outlined, text: 'Destinations'),
          const SizedBox(height: 8),
          for (final destination in destinations.entries) ...[
            DragTarget<String>(
              onWillAcceptWithDetails: (_) => !widget.writing,
              onAcceptWithDetails: (details) {
                widget.onFieldSelected(details.data, destination.key);
                widget.onSourceSelected(null);
              },
              builder: (context, candidates, _) {
                final assigned = widget.fieldValues.entries
                    .where((entry) => entry.value == destination.key)
                    .map((entry) => sourceLabel(entry.key))
                    .toList(growable: false);
                return Semantics(
                  key: ValueKey(
                    'assessment-match-destination-${destination.key}',
                  ),
                  button: true,
                  excludeSemantics: true,
                  label: assigned.isEmpty
                      ? '${destination.value}, available destination'
                      : '${destination.value}, connected from ${assigned.join(', ')}',
                  child: InkWell(
                    onTap: widget.writing || widget.selectedMatchField == null
                        ? null
                        : () => widget.onDestinationSelected(destination.key),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 64),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: candidates.isNotEmpty
                            ? AppTheme.softBlueAccent
                            : AppTheme.backgroundOffWhite,
                        borderRadius: AppTheme.radiusSm,
                        border: Border.all(color: AppTheme.borderLight),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(destination.value, style: AppTheme.labelLarge),
                          Text(
                            assigned.isEmpty
                                ? (widget.selectedMatchField == null
                                    ? 'Drag or choose a source first'
                                    : 'Select to connect the chosen source')
                                : assigned.join(', '),
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (_interactionComplete)
          TextButton.icon(
            key: const ValueKey(
              'assessment-match-toggle-completed-controls',
            ),
            onPressed: widget.writing
                ? null
                : () => setState(() {
                      _reviewingCompletedControls =
                          !_reviewingCompletedControls;
                    }),
            icon: Icon(
              _reviewingCompletedControls
                  ? Icons.visibility_off_outlined
                  : Icons.edit_outlined,
            ),
            label: Text(
              _reviewingCompletedControls
                  ? MissionContentData.hideCompletedControlsLabel
                  : MissionContentData.reviewOrChangeConnectionsLabel,
            ),
          ),
        SimulationFeedback(
          icon: Icons.hub_outlined,
          text:
              '${widget.fieldValues.length} of ${widget.stage.requiredCount} connections recorded',
        ),
      ],
    );
  }
}

class ConnectionPath extends StatelessWidget {
  const ConnectionPath({super.key, required this.connections});

  final List<String> connections;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.backgroundPaleBlue,
          borderRadius: AppTheme.radiusSm,
        ),
        child: connections.isEmpty
            ? Text('No connection path recorded.', style: AppTheme.bodySmall)
            : Wrap(
                spacing: 8,
                runSpacing: 6,
                children: connections
                    .map((value) => Chip(label: Text(value)))
                    .toList(growable: false),
              ),
      );
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.softBlueAccent : Colors.white,
          borderRadius: AppTheme.radiusSm,
          border: Border.all(
            color: selected ? AppTheme.primaryBlue : AppTheme.borderLight,
          ),
        ),
        child: Text(label),
      );
}
