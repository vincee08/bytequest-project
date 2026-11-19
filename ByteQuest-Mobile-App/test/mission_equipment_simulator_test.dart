import 'dart:convert';

import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/screens/simulation/runtime/mission_equipment_simulator.dart';
import 'package:bytequest/screens/simulation/runtime/mission_phase_completion_policy.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_action_reducer.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/equipment_practice_driver.dart';
import 'support/legacy_assembly_fixture.dart';

void main() {
  test('tool contact validates actual categories and records an observation',
      () {
    final definition = MissionSimulationDefinitions.byId('coc1_m4');
    final phase = definition.phases[1];
    final driver = EquipmentPracticeDriver(definition);
    final incompatible = driver.act(phase, 'tool_attempted', 'monitor',
        {'tool_id': 'lan_loopback_adapter', 'compatible': true});
    expect(incompatible['compatible'], false);
    expect(driver.state.toolApplications, isEmpty);
    final contact = driver.act(phase, 'tool_attempted', 'network_adapter',
        {'tool_id': 'lan_loopback_adapter', 'compatible': true});
    expect(contact['compatible'], true);
    expect((contact['measured_tool_result'] as Map)['observation'],
        contains('external network'));
    expect(driver.state.toolApplications['network_adapter'],
        'lan_loopback_adapter');
  });

  test('driver reconfiguration requires another restart before verification',
      () {
    final definition = MissionSimulationDefinitions.byId('coc1_m3');
    final driver = EquipmentPracticeDriver(definition);
    for (final phase in definition.phases) {
      driver.complete(phase);
    }
    final configure = definition.phases[2];
    final verify = definition.phases[3];
    driver.act(configure, 'configuration_applied', configure.id, {
      'values': {'network_driver': 'ethernet'}
    });
    final staleBoot = driver.act(verify, 'test_completed',
        verify.presentation['target'] as String, {'test_status': 'completed'});
    expect((staleBoot['measured_result'] as Map)['operating'], false);
    expect(MissionEquipmentSimulator.readyForReview(definition, driver.state),
        false);
    driver.act(configure, 'equipment_operation', 'restart_workstation');
    final restarted = driver.act(verify, 'test_completed',
        verify.presentation['target'] as String, {'test_status': 'completed'});
    expect((restarted['measured_result'] as Map)['operating'], true);
  });

  test('all assembly item/destination pairs enforce physical compatibility',
      () {
    final definition = legacyAssemblyDefinition;
    final phase = definition.phases[1];
    for (final item in practicePlacements.keys
        .where((id) => id != 'replacement_component')) {
      for (final destination
          in practicePlacements.values.where((id) => id != 'workstation')) {
        final driver = EquipmentPracticeDriver(definition);
        // Supply only the mounting prerequisites for this independent attempt.
        driver.state = driver.state.copyWith(placements: {
          if (item != 'motherboard') 'motherboard': 'motherboard_area',
          if (item == 'cooling_fan') 'cpu': 'cpu_socket',
        });
        final response = driver.act(phase, 'placement_attempted', destination, {
          'item_id': item,
          'destination_id': destination,
          'orientation': 'aligned'
        });
        expect(response['compatible'], destination == practicePlacements[item],
            reason: '$item -> $destination');
      }
    }
  });

  for (final entry in practiceOrders.entries) {
    test('${entry.key}: reversed unsafe chronology cannot complete the phase',
        () {
      final missionId = entry.key.substring(0, entry.key.lastIndexOf('_p'));
      final driver = EquipmentPracticeDriver(missionId == 'legacy_m2'
          ? legacyAssemblyDefinition
          : MissionSimulationDefinitions.byId(missionId));
      final phase = driver.definition.phases
          .singleWhere((phase) => phase.id == entry.key);
      final response = driver.act(phase, 'sequence_reordered', phase.id,
          {'order': entry.value.reversed.toList()});
      expect(response['simulation_valid'], false);
      expect(
          MissionPhaseCompletionPolicy.canAdvance(phase, driver.state), false);
    });
  }

  for (final entry in {
    'coc1_m5': 'install_display_driver',
    'coc2_m3': 'isolate_invalid_link',
    'coc3_m2': 'defer_restart',
    'coc3_m5': 'grant_everyone',
    'coc4_m5': 'replace_unverified_hardware',
    'coc4_m2': 'replace_memory',
  }.entries) {
    test('${entry.key}: an unrelated correction reproduces a measured fault',
        () {
      final driver =
          EquipmentPracticeDriver(MissionSimulationDefinitions.byId(entry.key));
      for (final phase in driver.definition.phases) {
        driver.complete(phase);
      }
      final correction = driver.definition.phases.singleWhere((phase) =>
          MissionEquipmentSimulator.maps(phase.presentation['choices'])
              .any((choice) => choice['id'] == entry.value));
      driver.act(correction, 'scenario_decision', entry.value);
      final testPhase = driver.definition.phases.lastWhere(
          (phase) => phase.resolvedInteraction == InteractionFamily.testRun);
      final response = driver.act(
          testPhase,
          'test_completed',
          testPhase.presentation['target'] as String,
          {'test_status': 'completed'});
      expect((response['measured_result'] as Map)['operating'], false);
      expect(
          MissionEquipmentSimulator.readyForReview(
              driver.definition, driver.state),
          false);
    });
  }

  for (final definition in MissionSimulationDefinitions.all) {
    test(
        '${definition.id}: operational work order completes and replays across restarts',
        () {
      final driver = EquipmentPracticeDriver(definition);
      for (final phase in definition.phases) {
        driver.complete(phase);
      }
      expect(MissionEquipmentSimulator.readyForReview(definition, driver.state),
          isTrue);
      var replayed = MissionRuntimeState.initial(definition.id);
      final reducer = MissionRuntimeActionReducer(definition);
      for (final action in driver.actions) {
        replayed = reducer.reduce(
            replayed,
            MissionEvidenceAction.fromJson(
                jsonDecode(jsonEncode(action.toJson()))
                    as Map<String, dynamic>));
      }
      expect(replayed.equipmentState, driver.state.equipmentState);
      expect(replayed.configurationValues, driver.state.configurationValues);
      expect(replayed.connectedNodePairs, driver.state.connectedNodePairs);
      expect(replayed.placements, driver.state.placements);
      expect(replayed.interactionCompletedPhaseIds,
          driver.state.interactionCompletedPhaseIds);
    });
    test(
        '${definition.id}: untouched equipment cannot produce nominal readings',
        () {
      for (final phase in definition.phases.where(
          (phase) => phase.resolvedInteraction == InteractionFamily.testRun)) {
        final driver = EquipmentPracticeDriver(definition);
        final result = driver.act(
            phase,
            'test_completed',
            phase.presentation['target'] as String? ?? phase.id,
            {'test_status': 'completed'});
        expect(result['measured_result'], isA<Map>(), reason: phase.id);
        expect((result['measured_result'] as Map)['readings'], isNotEmpty,
            reason: phase.id);
        expect((result['measured_result'] as Map)['operating'], false,
            reason: phase.id);
        expect(
            MissionEquipmentSimulator.readyForReview(definition, driver.state),
            false);
      }
    });
  }

  test('placement rejects incompatible slot, premature CPU and rotated keying',
      () {
    final definition = legacyAssemblyDefinition;
    final driver = EquipmentPracticeDriver(definition);
    final phase = definition.phases[1];
    for (final values in [
      {
        'item_id': 'cpu',
        'destination_id': 'ram_slot',
        'orientation': 'aligned'
      },
      {
        'item_id': 'cpu',
        'destination_id': 'cpu_socket',
        'orientation': 'aligned'
      },
      {
        'item_id': 'motherboard',
        'destination_id': 'motherboard_area',
        'orientation': 'rotated'
      },
    ]) {
      final result = driver.act(
          phase, 'placement_attempted', values['destination_id'], values);
      expect(result['simulation_valid'], false);
      expect(driver.state.placements, isEmpty);
      expect(
          MissionPhaseCompletionPolicy.canAdvance(phase, driver.state), false);
    }
  });

  test(
      'cross-interface connection is rejected and rewiring replaces the previous link',
      () {
    final definition = MissionSimulationDefinitions.byId('coc1_m4');
    final driver = EquipmentPracticeDriver(definition);
    final phase = definition.phases[2];
    expect(
        driver.act(phase, 'connection_created', 'usb_port', {
          'source_id': 'monitor',
          'destination_id': 'usb_port'
        })['simulation_valid'],
        false);
    expect(driver.state.connectedNodePairs, isEmpty);
    driver.act(phase, 'connection_created', 'hdmi_port',
        {'source_id': 'monitor', 'destination_id': 'hdmi_port'});
    expect(driver.state.connectedNodePairs, {'monitor>hdmi_port'});
    final network =
        EquipmentPracticeDriver(MissionSimulationDefinitions.byId('coc2_m3'));
    final connection = network.definition.phases[1];
    network.act(connection, 'connection_created', 'server',
        {'source_id': 'router', 'destination_id': 'server'});
    network.act(connection, 'connection_created', 'switch',
        {'source_id': 'router', 'destination_id': 'switch'});
    expect(network.state.connectedNodePairs, {'router>switch'});
  });

  test(
      'reconfiguration invalidates a previously nominal result and review readiness',
      () {
    final definition = MissionSimulationDefinitions.byId('coc3_m4');
    final driver = EquipmentPracticeDriver(definition);
    for (final phase in definition.phases) {
      driver.complete(phase);
    }
    expect(MissionEquipmentSimulator.readyForReview(definition, driver.state),
        true);
    driver.act(definition.phases[2], 'configuration_applied',
        definition.phases[2].id, {
      'values': {'service_control': 'stop', 'status_inspected': true}
    });
    expect(driver.state.equipmentState['service_running'], false);
    expect(MissionEquipmentSimulator.readyForReview(definition, driver.state),
        false);
    final measured = driver.act(
        definition.phases[3],
        'test_completed',
        definition.phases[3].presentation['target'] as String,
        {'test_status': 'completed'});
    expect((measured['measured_result'] as Map)['operating'], false);
  });

  test(
      'invalid configuration is retained for diagnosis without a successful format gate',
      () {
    final definition = MissionSimulationDefinitions.byId('coc2_m4');
    final driver = EquipmentPracticeDriver(definition);
    final result = driver.act(definition.phases[1], 'configuration_applied',
        definition.phases[1].id, {
      'values': {
        'interface_address': '999.1.1.1',
        'subnet_mask': '255.255.255.0',
        'default_gateway': '192.168.10.1'
      }
    });
    expect(result['simulation_valid'], false);
    expect(driver.state.configurationValues['interface_address'], '999.1.1.1');
    expect(
        MissionPhaseCompletionPolicy.canAdvance(
            definition.phases[1], driver.state),
        false);
  });

  // Re-defense decision 4: assessment runs the same physical model as
  // practice, but feedback is neutral and never names a target or step.
  test('assessment applies the physical model with neutral feedback only', () {
    final definition = MissionSimulationDefinitions.byId('coc1_m2');
    final phase = definition.phases[1];
    final state = MissionRuntimeState.initial(definition.id,
        mode: MissionRuntimeMode.assessment,
        assessmentAttemptId: 'assessment-test');
    final refused = MissionEquipmentSimulator.describeAction(
        definition: definition,
        phase: phase,
        state: state,
        actionType: 'placement_attempted',
        target: 'dimm_a1',
        value: const {'item_id': 'cpu', 'destination_id': 'dimm_a1'});
    expect(refused['simulation_valid'], false);
    expect(refused['compatible'], false);
    expect(refused['simulation_feedback'],
        MissionContentData.assessmentNeutralPlacement);
    final accepted = MissionEquipmentSimulator.describeAction(
        definition: definition,
        phase: phase,
        state: state,
        actionType: 'equipment_operation',
        target: 'open_cpu_lever',
        value: const {});
    expect(accepted['simulation_valid'], true);
    expect(accepted['simulation_feedback'],
        MissionContentData.assessmentNeutralRecorded);
    expect((accepted['equipment_snapshot'] as Map)['cpu_lever'], 'open',
        reason: 'the snapshot restores physical state after a restart');
    final practice = MissionEquipmentSimulator.describeAction(
        definition: definition,
        phase: phase,
        state: MissionRuntimeState.initial(definition.id),
        actionType: 'placement_attempted',
        target: 'cpu_socket',
        value: const {
          'item_id': 'cpu',
          'destination_id': 'cpu_socket',
          'orientation': '0'
        });
    expect(practice['simulation_feedback'],
        MissionContentData.benchRequirementFeedback['cpu'],
        reason: 'practice names the physical reason');
  });

  test('bench parts declare requires, removal resets fastening, reseat counts',
      () {
    final definition = MissionSimulationDefinitions.byId('coc1_m2');
    final driver = EquipmentPracticeDriver(definition)
      ..complete(definition.phases[0])
      ..complete(definition.phases[1]);
    final caseInstall = definition.phases[2];
    driver.act(caseInstall, 'placement_attempted', 'board_standoffs',
        {'item_id': 'motherboard', 'destination_id': 'board_standoffs'});
    final shield = driver.act(caseInstall, 'placement_attempted', 'io_cutout',
        {'item_id': 'io_shield', 'destination_id': 'io_cutout'});
    expect(shield['simulation_valid'], false,
        reason: 'the I/O shield cannot pass an installed motherboard');
    driver.act(caseInstall, 'equipment_operation', 'pick_screwdriver');
    driver.act(caseInstall, 'equipment_operation', 'fasten_motherboard');
    expect(driver.state.equipmentState['board_fastened'], true);
    final removed = driver.act(caseInstall, 'placement_removed', 'motherboard',
        {'item_id': 'motherboard'});
    expect(removed['simulation_valid'], true);
    expect(driver.state.placements.containsKey('motherboard'), false);
    expect(driver.state.equipmentState['board_fastened'], false);
    expect((driver.state.equipmentState['counts'] as Map)['corrections'], 1);
    expect(
        driver.act(caseInstall, 'placement_removed', 'motherboard',
            {'item_id': 'motherboard'})['simulation_valid'],
        false,
        reason: 'nothing left to remove');
    expect(
        driver.act(caseInstall, 'placement_attempted', 'io_cutout', {
          'item_id': 'io_shield',
          'destination_id': 'io_cutout'
        })['simulation_valid'],
        true);
  });

  test(
      'a missed thermal compound found at POST costs one fault; taking the '
      'cooler off to fix it is the repair', () {
    final definition = MissionSimulationDefinitions.byId('coc1_m2');
    final driver = EquipmentPracticeDriver(definition)
      ..complete(definition.phases[0]);
    final board = definition.phases[1];
    for (final step in practiceScripts[board.id]!) {
      if (step.$2 == 'apply_thermal_compound') continue;
      driver.act(board, step.$1, step.$2, step.$3);
    }
    driver
      ..complete(definition.phases[2])
      ..complete(definition.phases[3]);
    final post = definition.phases[4];
    driver.act(post, 'test_started', 'coc1_m2_post', {'test_status': 'running'});
    driver.act(post, 'test_completed', 'coc1_m2_post',
        {'test_status': 'completed'});
    driver.act(post, 'placement_removed', 'cooler', {'item_id': 'cooler'});
    driver.act(post, 'equipment_operation', 'apply_thermal_compound');
    driver.act(post, 'placement_attempted', 'cooler_mount',
        {'item_id': 'cooler', 'destination_id': 'cooler_mount'});
    final counts = driver.state.equipmentState['counts'] as Map;
    expect(counts['faults'], 1);
    expect(counts['repairs'], 1);
    expect(counts['corrections'], isNull);
  });

  test('missing cables and wrong DIMMs pass their phase but fail the POST',
      () {
    final definition = MissionSimulationDefinitions.byId('coc1_m2');
    final driver = EquipmentPracticeDriver(definition)
      ..complete(definition.phases[0]);
    final board = definition.phases[1];
    for (final step in practiceScripts[board.id]!) {
      final value = Map<String, dynamic>.from(step.$3);
      if (value['item_id'] == 'ram_1') value['destination_id'] = 'dimm_a1';
      if (value['item_id'] == 'ram_2') value['destination_id'] = 'dimm_a2';
      driver.act(board, step.$1, step.$2, value);
    }
    expect(MissionPhaseCompletionPolicy.canAdvance(board, driver.state), true);
    driver.complete(definition.phases[2]);
    final cables = definition.phases[3];
    driver.act(cables, 'connection_created', 'board_atx24',
        {'source_id': 'atx_24pin', 'destination_id': 'board_atx24'});
    expect(MissionPhaseCompletionPolicy.canAdvance(cables, driver.state), true,
        reason: 'only the 24-pin cable is required to leave the phase');
    final post = definition.phases[4];
    driver.act(post, 'test_started', 'coc1_m2_post', {'test_status': 'running'});
    final result = driver.act(post, 'test_completed', 'coc1_m2_post',
        {'test_status': 'completed'});
    final readings = {
      for (final reading in ((result['measured_result'] as Map)['readings']
          as List))
        reading['id']: reading['operating']
    };
    expect(readings['memory_channels'], false);
    expect(readings['cpu_power'], false);
    expect(readings['boot_device'], false);
    expect(readings['cpu_detection'], true);
    expect(MissionPhaseCompletionPolicy.canAdvance(post, driver.state), false);
  });
}
