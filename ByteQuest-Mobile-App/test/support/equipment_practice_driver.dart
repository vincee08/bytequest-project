import 'dart:convert';

import 'package:bytequest/screens/simulation/runtime/mission_equipment_simulator.dart';
import 'package:bytequest/screens/simulation/runtime/mission_phase_completion_policy.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_action_reducer.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';

/// Explicit successful work orders, independent of the catalog's checks.
const practiceConfiguration = <String, dynamic>{
  'boot_mode': 'uefi',
  'storage_mode': 'ahci',
  'install_target': 'system_disk',
  'network_driver': 'ethernet',
  'display_resolution': '1920x1080',
  'address_mode': 'automatic',
  'ppe_prepared': true,
  'termination_tool': 'crimping_tool',
  'workstation_interface': 'ethernet_auto',
  'physical_link_inspected': true,
  'device_context': 'managed_switch',
  'interface_address': '192.168.10.2',
  'subnet_mask': '255.255.255.0',
  'default_gateway': '192.168.10.1',
  'server_role': 'file_service',
  'host_name': 'BQ-FS01',
  'management_address': '192.168.30.10',
  'account_name': 'technician',
  'group_assignment': 'support',
  'resource_permission': 'modify',
  'service_name': 'file',
  'listen_port': '445',
  'startup_mode': 'automatic',
  'service_control': 'start',
  'status_inspected': true,
  'device_mode': 'automatic',
  'device_identifier': 'BQ-ETH01',
  'driver_state': 'installed',
};
const practiceOrders = {
  'coc1_m2_p3': ['isolate', 'board', 'cooling', 'power'],
  'coc1_m3_p2': ['boot_media', 'select_disk', 'copy_files', 'configure_device'],
  'coc2_m1_p3': ['measure', 'strip', 'arrange', 'terminate', 'inspect'],
  'coc2_m2_p2': [
    'white_orange',
    'orange',
    'white_green',
    'blue',
    'white_blue',
    'green',
    'white_brown',
    'brown'
  ],
  'coc3_m1_p4': ['power', 'network', 'capacity', 'media'],
  'coc3_m2_p2': ['validate', 'partition', 'install', 'role'],
  'coc4_m4_p1': ['isolate', 'remove', 'inspect'],
  'coc4_m4_p4': ['seat', 'fasten', 'configure', 'restore'],
};
const practiceDecisions = {
  'coc1_m5_p4': 'replace_storage_cable',
  'coc2_m3_p4': 'replace_link_segment',
  'coc3_m1_p2': 'record_server_requirements',
  'coc3_m1_p3': 'file_service',
  'coc3_m2_p3': 'restart_after_configuration',
  'coc3_m5_p4': 'restore_support_membership',
  'coc4_m1_p3': 'prioritize_network_path',
  'coc4_m1_p4': 'preliminary_network_path',
  'coc4_m2_p4': 'replace_storage',
  'coc4_m5_p2': 'service_verified_faults',
  'coc4_m5_p3': 'open_service_console',
};
const practiceConnections = {
  'atx': 'board_power',
  'sata': 'storage_data',
  'monitor': 'hdmi_port',
  'keyboard': 'usb_port',
  'mouse': 'usb_port',
  'network_adapter': 'ethernet_port',
  'copper_cable': 'lan_cable_tester',
  'workstation': 'switch',
  'router': 'switch',
  'workstation_a': 'switch',
  'workstation_b': 'switch',
};
const practicePlacements = {
  'motherboard': 'motherboard_area',
  'cpu': 'cpu_socket',
  'ram': 'ram_slot',
  'storage': 'drive_bay',
  'cooling_fan': 'fan_area',
  'psu': 'psu_bay',
  'replacement_component': 'workstation',
};

class EquipmentPracticeDriver {
  EquipmentPracticeDriver(this.definition)
      : state = MissionRuntimeState.initial(definition.id);
  final MissionSimulationDefinition definition;
  MissionRuntimeState state;
  final actions = <MissionEvidenceAction>[];

  Map<String, dynamic> act(
      MissionPhaseDefinition phase, String type, String? target,
      [Map<String, dynamic> value = const {}]) {
    final enriched = MissionEquipmentSimulator.describeAction(
        definition: definition,
        phase: phase,
        state: state,
        actionType: type,
        target: target,
        value: value);
    final action = MissionEvidenceAction(
        clientActionId: 'action-${actions.length}',
        missionId: definition.id,
        phaseId: phase.id,
        actionType: type,
        target: target,
        value: {...enriched, 'runtime_action_type': type},
        occurredAt: DateTime.utc(2026, 9, 22));
    actions.add(action);
    state = MissionRuntimeActionReducer(definition).reduce(state, action);
    // Emulate a complete process boundary, not an in-memory reference copy.
    state = MissionRuntimeState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>);
    return enriched;
  }

  void complete(MissionPhaseDefinition phase) {
    state = state.copyWith(currentPhaseId: phase.id);
    final p = phase.presentation;
    final eq = MissionEquipmentSimulator.map(p['equipment']);
    void configure(Object? fields) {
      act(phase, 'configuration_applied', phase.id, {
        'values': {
          for (final field in MissionEquipmentSimulator.maps(fields))
            field['id'] as String:
                definition.id == 'coc2_m5' && field['id'] == 'interface_address'
                    ? '192.168.10.24'
                    : practiceConfiguration[field['id']],
        }
      });
    }

    void connect(Map<String, dynamic> panel) {
      for (final source in MissionEquipmentSimulator.maps(panel['sources'])) {
        final sourceId = source['id'] as String;
        final destination = sourceId == 'switch'
            ? (definition.id == 'coc2_m2' ? 'router' : 'server')
            : practiceConnections[sourceId]!;
        act(phase, 'connection_created', destination,
            {'source_id': sourceId, 'destination_id': destination});
      }
    }

    void tools(Map<String, dynamic> panel) {
      for (final target in MissionEquipmentSimulator.maps(panel['targets'])) {
        final tool = MissionEquipmentSimulator.maps(panel['tools']).firstWhere(
            (tool) => (tool['compatible_categories'] as List)
                .contains(target['category']));
        act(phase, 'tool_attempted', target['id'] as String,
            {'tool_id': tool['id'], 'compatible': true});
      }
    }

    // Supplementary controls operate the same state before the measured test.
    if (eq['tools'] is List) {
      tools(eq);
    }
    if (eq['configuration'] is Map) {
      configure((eq['configuration'] as Map)['fields']);
    }
    if (eq['connection'] is Map) {
      connect(Map<String, dynamic>.from(eq['connection'] as Map));
    }
    if (eq['selection_groups'] is List) {
      for (final group
          in {'processing': 'cpu', 'memory': 'ram', 'power': 'psu'}.entries) {
        act(phase, 'selection_confirmed', '${phase.id}_${group.key}', {
          'selection_group': group.key,
          'selected_ids': [group.value]
        });
      }
    }
    switch (phase.resolvedInteraction) {
      case InteractionFamily.inspect:
        for (final object in MissionEquipmentSimulator.maps(p['objects'])) {
          act(phase, 'object_inspected', object['id'] as String);
        }
      case InteractionFamily.select:
        act(phase, 'selection_confirmed', phase.id, {
          'selected_ids': definition.id == 'coc1_m1'
              ? ['esd_protection', 'open_memory_latch']
              : phase.availableObjectIds.toList()
        });
      case InteractionFamily.tool:
        tools(p);
      case InteractionFamily.connect:
        connect(p);
      case InteractionFamily.configure:
        configure(p['fields']);
      case InteractionFamily.sequence:
        act(phase, 'sequence_reordered', phase.id,
            {'order': practiceOrders[phase.id]!});
      case InteractionFamily.place:
        for (final part in MissionEquipmentSimulator.maps(p['items'])) {
          act(phase, 'placement_attempted', practicePlacements[part['id']], {
            'item_id': part['id'],
            'destination_id': practicePlacements[part['id']],
            'orientation': 'aligned',
            'compatible': true,
          });
        }
      case InteractionFamily.troubleshoot:
        for (final diagnostic
            in MissionEquipmentSimulator.maps(p['diagnostic_actions'])) {
          act(phase, 'diagnostic_action', diagnostic['id'] as String,
              {'reveals_fact_id': diagnostic['reveals_fact_id']});
        }
      case InteractionFamily.testRun:
        final target = p['target'] as String? ?? phase.id;
        act(phase, 'test_started', target, {'test_status': 'running'});
        act(phase, 'test_completed', target, {'test_status': 'completed'});
        if (p['requires_interpretation'] == true) {
          act(phase, 'result_interpreted', phase.id, {
            'interpretation':
                'Recorded output supports the next service action; verify each measured subsystem.'
          });
        }
      case InteractionFamily.observe:
        act(phase, 'observation_recorded', phase.id, {
          'observation':
              'Inspected indicators and documented the observed operating condition.'
        });
      case InteractionFamily.decide:
        act(phase, 'scenario_decision', practiceDecisions[phase.id]!);
      case InteractionFamily.interpret:
        act(phase, 'result_interpreted', phase.id, {
          'interpretation':
              'The measured outputs isolate the service path; correction and retest are recorded.'
        });
      case InteractionFamily.review:
        return;
      case InteractionFamily.match:
        throw StateError('Add a matching work-order fixture.');
    }
    for (final operation in MissionEquipmentSimulator.maps(eq['operations'])) {
      act(phase, 'equipment_operation', operation['id'] as String);
    }
    if (!MissionPhaseCompletionPolicy.canAdvance(phase, state)) {
      throw StateError(
          'Work order cannot advance ${phase.id}: ${state.equipmentState}');
    }
  }
}
