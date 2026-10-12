import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/mission_content_data.dart';
import '../components/tool_tray.dart';
import '../runtime/mission_runtime_models.dart';
import '../templates/authoritative_mission_contract.dart';
import 'multi_select_interaction.dart';

class SequencingInteraction extends StatefulWidget {
  const SequencingInteraction({
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
  State<SequencingInteraction> createState() => _SequencingInteractionState();
}

class _SequencingInteractionState extends State<SequencingInteraction> {
  late List<InteractionItem> _definitions;
  late List<String> _order;

  @override
  void initState() {
    super.initState();
    _loadRuntimeInputs();
  }

  @override
  void didUpdateWidget(covariant SequencingInteraction oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldItems = jsonEncode(oldWidget.phase.presentation['items']);
    final newItems = jsonEncode(widget.phase.presentation['items']);
    if (oldWidget.phase.id != widget.phase.id ||
        oldItems != newItems ||
        !listEquals(
          oldWidget.state.sequenceOrder,
          widget.state.sequenceOrder,
        )) {
      _loadRuntimeInputs();
    }
  }

  void _loadRuntimeInputs() {
    _definitions = interactionItems(widget.phase.presentation['items']);
    final ids = _definitions.map((item) => item.id).toSet();
    final phases = widget.state.equipmentState['phases'];
    final phase = phases is Map ? phases[widget.phase.id] : null;
    final recorded = phase is Map && phase['order'] is List
        ? (phase['order'] as List).whereType<String>().toList()
        : widget.state.sequenceOrder;
    _order = recorded.length != ids.length || !ids.containsAll(recorded)
        ? _definitions.map((item) => item.id).toList()
        : List<String>.from(recorded);
  }

  String _label(String id) =>
      _definitions.firstWhere((item) => item.id == id).label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.state.missionId.startsWith('coc4')
              ? MissionContentData.sequenceTapHelp
              : MissionContentData.sequenceHelp),
          const SizedBox(height: 8),
          ReorderableListView.builder(
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _order.length,
            onReorderItem: widget.enabled
                ? (oldIndex, newIndex) => _move(oldIndex, newIndex, 'drag')
                : (_, __) {},
            itemBuilder: (context, index) {
              final id = _order[index];
              final label = _label(id);
              return Card(
                key: ValueKey('sequence-item-$id'),
                child: Row(
                  children: [
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child:
                            Text('${index + 1}', style: AppTheme.labelLarge)),
                    if (!widget.state.missionId.startsWith('coc4'))
                      ReorderableDragStartListener(
                        index: index,
                        enabled: widget.enabled,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.drag_handle_rounded),
                        ),
                      ),
                    Expanded(
                      child: Text(label, key: ValueKey('sequence-label-$id')),
                    ),
                    IconButton(
                      tooltip: MissionContentData.moveStep(label, 'up'),
                      style: IconButton.styleFrom(
                          backgroundColor: AppTheme.surfaceMuted),
                      onPressed: widget.enabled && index > 0
                          ? () => _move(index, index - 1, 'button')
                          : null,
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                    IconButton(
                      tooltip: MissionContentData.moveStep(label, 'down'),
                      style: IconButton.styleFrom(
                          backgroundColor: AppTheme.surfaceMuted),
                      onPressed: widget.enabled && index < _order.length - 1
                          ? () => _move(index, index + 1, 'button')
                          : null,
                      icon: const Icon(Icons.arrow_downward_rounded),
                    ),
                  ],
                ),
              );
            },
          ),
          FilledButton.icon(
              key: ValueKey('sequence-confirm-${widget.phase.id}'),
              onPressed: widget.enabled ? () => _record('button') : null,
              icon: const Icon(Icons.playlist_add_check_rounded),
              label: const Text(MissionContentData.confirmSequenceLabel)),
        ],
      );

  void _move(int oldIndex, int newIndex, String inputMethod) {
    setState(() {
      final item = _order.removeAt(oldIndex);
      _order.insert(newIndex, item);
    });
    _record(inputMethod);
  }

  void _record(String inputMethod) {
    unawaited(widget.onAction('sequence_reordered', widget.phase.id, {
      'order': List<String>.from(_order),
      'input_method': inputMethod,
    }));
  }
}

class SequenceActivity extends StatelessWidget {
  const SequenceActivity({
    super.key,
    required this.stage,
    required this.sequence,
    required this.writing,
    required this.onSelected,
  });

  final AuthoritativeMissionStage stage;
  final List<String> sequence;
  final bool writing;
  final Future<void> Function(String id) onSelected;

  String _label(String id) =>
      stage.options.firstWhere((option) => option.id == id).label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MissionSectionLabel(
            icon: Icons.playlist_add_check_rounded,
            text: 'Choose next action',
          ),
          const SizedBox(height: 10),
          for (final option in stage.options) ...[
            MissionSelectableActionCard(
              key: ValueKey('sequence-option-${option.id}'),
              label: option.label,
              selected: sequence.contains(option.id),
              enabled: !writing && !sequence.contains(option.id),
              icon: Icons.arrow_forward_rounded,
              onTap: () => unawaited(onSelected(option.id)),
            ),
            const SizedBox(height: 8),
          ],
          EvidenceTimeline(labels: sequence.map(_label).toList()),
          const SizedBox(height: 10),
          SimulationFeedback(
            icon: Icons.timeline_rounded,
            text:
                '${sequence.length} of ${stage.requiredCount} actions recorded',
          ),
        ],
      );
}

class EvidenceTimeline extends StatelessWidget {
  const EvidenceTimeline({super.key, required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Evidence timeline', style: AppTheme.labelLarge),
          const SizedBox(height: 8),
          if (labels.isEmpty)
            Text('No actions recorded yet.', style: AppTheme.bodyMedium)
          else
            for (var index = 0; index < labels.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${index + 1}. ${labels[index]}'),
              ),
        ],
      );
}
