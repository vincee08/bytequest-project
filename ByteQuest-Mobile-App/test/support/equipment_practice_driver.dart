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
  'wireless_ssid': 'BQ-LAB',
  'wireless_security': 'wpa2_aes',
  'wan_mode': 'dhcp',
  'firewall_policy': 'deny_unsolicited',
  'repeater_mode': 'bridge',
  'cable_route': 'protected_design_route',
  'raceway_material': 'pvc',
};
const practiceOrders = {
  // Retired COC1 M2 v2 contract (test/support/legacy_assembly_fixture.dart).
  'legacy_m2_p3': ['isolate', 'board', 'cooling', 'power'],
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
/// Scripted work orders for the COC1 M2 assembly bench, in physical order.
/// Each step is (action type, target, value).
const practiceScripts = <String, List<(String, String?, Map<String, dynamic>)>>{
  'coc1_m2_p1': [
    ('object_inspected', 'system_case', {}),
    ('object_inspected', 'motherboard', {}),
    ('object_inspected', 'cpu', {}),
    ('object_inspected', 'cooler', {}),
    ('object_inspected', 'ram', {}),
    ('object_inspected', 'psu', {}),
    ('object_inspected', 'storage', {}),
    ('equipment_operation', 'wear_wrist_strap', {}),
    ('equipment_operation', 'ground_wrist_strap', {}),
  ],
  'coc1_m2_p2': [
    ('equipment_operation', 'open_cpu_lever', {}),
    (
      'placement_attempted',
      'cpu_socket',
      {'item_id': 'cpu', 'destination_id': 'cpu_socket', 'orientation': '0'}
    ),
    ('equipment_operation', 'close_cpu_lever', {}),
    ('equipment_operation', 'apply_thermal_compound', {}),
    (
      'placement_attempted',
      'cooler_mount',
      {'item_id': 'cooler', 'destination_id': 'cooler_mount'}
    ),
    (
      'connection_created',
      'cpu_fan_header',
      {'source_id': 'cooler_fan', 'destination_id': 'cpu_fan_header'}
    ),
    ('equipment_operation', 'open_dimm_latches', {}),
    (
      'placement_attempted',
      'dimm_a2',
      {'item_id': 'ram_1', 'destination_id': 'dimm_a2', 'orientation': '0'}
    ),
    (
      'placement_attempted',
      'dimm_b2',
      {'item_id': 'ram_2', 'destination_id': 'dimm_b2', 'orientation': '0'}
    ),
    ('equipment_operation', 'close_dimm_latches', {}),
  ],
  'coc1_m2_p3': [
    (
      'placement_attempted',
      'psu_bay',
      {'item_id': 'psu', 'destination_id': 'psu_bay', 'orientation': '0'}
    ),
    ('equipment_operation', 'pick_screwdriver', {}),
    ('equipment_operation', 'fasten_psu', {}),
    (
      'placement_attempted',
      'io_cutout',
      {'item_id': 'io_shield', 'destination_id': 'io_cutout'}
    ),
    (
      'placement_attempted',
      'board_standoffs',
      {'item_id': 'motherboard', 'destination_id': 'board_standoffs'}
    ),
    ('equipment_operation', 'fasten_motherboard', {}),
    (
      'placement_attempted',
      'drive_bay',
      {'item_id': 'storage', 'destination_id': 'drive_bay'}
    ),
    ('equipment_operation', 'fasten_drive', {}),
  ],
  'coc1_m2_p4': [
    (
      'connection_created',
      'board_atx24',
      {'source_id': 'atx_24pin', 'destination_id': 'board_atx24'}
    ),
    (
      'connection_created',
      'board_eps8',
      {'source_id': 'eps_8pin', 'destination_id': 'board_eps8'}
    ),
    (
      'connection_created',
      'drive_power',
      {'source_id': 'sata_power', 'destination_id': 'drive_power'}
    ),
    (
      'connection_created',
      'drive_data',
      {'source_id': 'sata_data', 'destination_id': 'drive_data'}
    ),
    (
      'connection_created',
      'board_front_panel',
      {'source_id': 'front_panel', 'destination_id': 'board_front_panel'}
    ),
  ],
  'coc1_m2_p5': [
    ('test_started', 'coc1_m2_post', {'test_status': 'running'}),
    ('test_completed', 'coc1_m2_post', {'test_status': 'completed'}),
    (
      'result_interpreted',
      'coc1_m2_p5',
      {
        'interpretation':
            'POST passed: CPU, dual-channel memory, CPU fan and boot drive detected; the system is ready for OS installation.'
      }
    ),
  ],
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
    final script = practiceScripts[phase.id];
    if (script != null) {
      for (final step in script) {
        act(phase, step.$1, step.$2, step.$3);
      }
      if (!MissionPhaseCompletionPolicy.canAdvance(phase, state)) {
        throw StateError(
            'Work order cannot advance ${phase.id}: ${state.equipmentState}');
      }
      return;
    }
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
        final destination =
            sourceId == 'server_node' || sourceId == 'client_node'
                ? 'server_switch'
                : sourceId == 'switch'
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
    if (eq['placement'] is Map) {
      for (final part in MissionEquipmentSimulator.maps(
          (eq['placement'] as Map)['items'])) {
        act(phase, 'placement_attempted', '${part['id']}_position', {
          'item_id': part['id'],
          'destination_id': '${part['id']}_position',
        });
      }
    }
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
            {'order': practiceOrders[phase.id]!, 'confirmed': true});
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
        for (final operation
            in MissionEquipmentSimulator.maps(eq['operations'])) {
          act(phase, 'equipment_operation', operation['id'] as String);
        }
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
    if (phase.resolvedInteraction != InteractionFamily.testRun) {
      for (var pass = 0; pass < 2; pass++) {
        for (final operation
            in MissionEquipmentSimulator.maps(eq['operations'])) {
          act(phase, 'equipment_operation', operation['id'] as String);
        }
      }
    }
    if (!MissionPhaseCompletionPolicy.canAdvance(phase, state)) {
      throw StateError(
          'Work order cannot advance ${phase.id}: ${state.equipmentState}');
    }
  }
}
