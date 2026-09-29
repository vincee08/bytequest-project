import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/mission_content_data.dart';
import '../interactions/tool_selection_interaction.dart';
import '../interactions/configuration_panel.dart';
import '../interactions/connection_interaction.dart';
import '../interactions/multi_select_interaction.dart';
import '../runtime/mission_equipment_simulator.dart';
import '../runtime/mission_runtime_models.dart';
import 'tool_tray.dart';

/// Optional operations compose with the existing phase interaction and scene.
class EquipmentOperations extends StatelessWidget {
  const EquipmentOperations(
      {super.key,
      required this.phase,
      required this.state,
      required this.onAction,
      required this.enabled});
  final MissionPhaseDefinition phase;
  final MissionRuntimeState state;
  final MissionActionCallback onAction;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (state.mode != MissionRuntimeMode.practice)
      return const SizedBox.shrink();
    final spec = MissionEquipmentSimulator.map(phase.presentation['equipment']);
    final operations = MissionEquipmentSimulator.maps(spec['operations']);
    final hasTools = spec['tools'] is List && spec['targets'] is List;
    final configuration = MissionEquipmentSimulator.map(spec['configuration']);
    final connection = MissionEquipmentSimulator.map(spec['connection']);
    final selectionGroups =
        MissionEquipmentSimulator.maps(spec['selection_groups']);
    final toolOutput = MissionEquipmentSimulator.map(
        MissionEquipmentSimulator.map(MissionEquipmentSimulator.map(
            state.equipmentState['phases'])[phase.id])['tool_output']);
    if (operations.isEmpty &&
        !hasTools &&
        configuration.isEmpty &&
        connection.isEmpty &&
        selectionGroups.isEmpty &&
        toolOutput.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 12),
      if (toolOutput['observation'] is String)
        Semantics(
            liveRegion: true,
            child: Text(toolOutput['observation'] as String,
                style: AppTheme.bodyMedium)),
      for (final group in selectionGroups) ...[
        Text(group['label'] as String, style: AppTheme.labelLarge),
        MultiSelectInteraction(
            key: ValueKey('classification-${group['id']}'),
            phase: MissionPhaseDefinition(
                id: '${phase.id}_${group['id']}',
                title: group['label'] as String,
                instruction: phase.instruction,
                primaryInteraction: InteractionFamily.select,
                presentation: {
                  'options': group['options'],
                  'selection_group': group['id']
                }),
            state: state,
            enabled: enabled,
            onAction: (type, target, value) => onAction(
                type, target, {...value, 'selection_group': group['id']})),
        const SizedBox(height: 12),
      ],
      if (configuration.isNotEmpty)
        ConfigurationPanel(
            phase: MissionPhaseDefinition(
                id: phase.id,
                title: phase.title,
                instruction: phase.instruction,
                primaryInteraction: InteractionFamily.configure,
                presentation: configuration),
            state: state,
            onAction: onAction,
            enabled: enabled),
      if (connection.isNotEmpty)
        ConnectionInteraction(
            phase: MissionPhaseDefinition(
                id: phase.id,
                title: phase.title,
                instruction: phase.instruction,
                primaryInteraction: InteractionFamily.connect,
                presentation: connection),
            state: state,
            onAction: onAction,
            enabled: enabled),
      if (hasTools)
        ToolSelectionInteraction(
          phase: MissionPhaseDefinition(
              id: phase.id,
              title: phase.title,
              instruction: phase.instruction,
              primaryInteraction: InteractionFamily.tool,
              presentation: {
                'tools': spec['tools'],
                'targets': spec['targets']
              }),
          state: state,
          onAction: onAction,
          enabled: enabled,
        ),
      if (operations.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(MissionContentData.equipmentOperationsLabel,
            style: AppTheme.labelLarge),
        for (final operation in operations) ...[
          const SizedBox(height: 8),
          Semantics(
            button: true,
            label: operation['label'] as String,
            child: OutlinedButton.icon(
              key: ValueKey('equipment-operation-${operation['id']}'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              onPressed: enabled
                  ? () => onAction('equipment_operation',
                      operation['id'] as String, const {'input_method': 'tap'})
                  : null,
              icon: const Icon(Icons.settings_outlined),
              label: Text(operation['label'] as String),
            ),
          ),
        ],
      ],
    ]);
  }
}

class EquipmentTestReadout extends StatelessWidget {
  const EquipmentTestReadout({super.key, required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final readings = MissionEquipmentSimulator.maps(result['readings']);
    if (readings.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      liveRegion: true,
      label: MissionContentData.equipmentOutputLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(MissionContentData.equipmentOutputLabel,
              style: AppTheme.labelLarge),
          for (final reading in readings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                    reading['operating'] == true
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    size: 20,
                    color: reading['operating'] == true
                        ? AppTheme.deepBlue
                        : AppTheme.errorRed),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('${reading['label']}: ${reading['reading']}',
                        style: AppTheme.bodyMedium)),
              ]),
            ),
        ]),
      ),
    );
  }
}
