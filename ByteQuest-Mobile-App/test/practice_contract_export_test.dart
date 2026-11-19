import 'dart:io';

import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/screens/simulation/runtime/mission_equipment_simulator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/export_practice_contracts.dart'
    show
        assemblyContractMigrationDigest,
        assemblyContractMigrationSql,
        assemblyMigrationFileName,
        assemblyMigrationSha256;

/// Condition paths and operators the server replay understands.
const _serverPaths = {
  'inspected',
  'placed',
  'link',
  'config',
  'setting',
  'operation',
  'tool',
  'fact',
  'result',
  'observation',
  'interpretation',
  'selection',
  'classification',
  'decision',
  'sequence',
  'order',
};
const _serverOperators = {
  'equals',
  'present',
  'contains',
  'set_equals',
  'one_of',
  'not_equals',
  'minimum',
};

Iterable<Map<String, dynamic>> _serverConditions(Map<String, dynamic> phase) sync* {
  final presentation = MissionEquipmentSimulator.map(phase['presentation']);
  final equipment = MissionEquipmentSimulator.map(presentation['equipment']);
  yield* MissionEquipmentSimulator.maps(equipment['completion']);
  for (final check in MissionEquipmentSimulator.maps(equipment['checks'])) {
    yield* MissionEquipmentSimulator.maps(check['requires']);
  }
  for (final operation
      in MissionEquipmentSimulator.maps(equipment['operations'])) {
    yield* MissionEquipmentSimulator.maps(operation['requires']);
  }
  for (final panel in [
    presentation,
    MissionEquipmentSimulator.map(equipment['placement'])
  ]) {
    for (final item in MissionEquipmentSimulator.maps(panel['items'])) {
      yield* MissionEquipmentSimulator.maps(item['requires']);
    }
  }
}

void main() {
  final definition = MissionSimulationDefinitions.byId('coc1_m2');

  test('the COC1 M2 assembly contract export matches its recorded digest', () {
    expect(assemblyContractMigrationDigest(), assemblyMigrationSha256,
        reason: 'The COC1 M2 definition changed. Publish a new contract '
            'migration and record its digest; never edit an applied one.');
    expect(assemblyContractMigrationSql(),
        contains("'coc1_m2', 'css-assembly-20261119-v3'"));
  });

  final migration = File('../supabase/migrations/$assemblyMigrationFileName');
  test('the committed migration equals the exported contract', () {
    expect(migration.readAsStringSync().replaceAll('\r\n', '\n'),
        assemblyContractMigrationSql());
  },
      skip: migration.existsSync()
          ? false
          : 'Repository migrations are not mounted in this test run.');

  test('the app publishes the assembly contract version', () {
    expect(MissionSimulationDefinitions.contractVersion('coc1_m2'),
        'css-assembly-20261119-v3');
    expect(MissionSimulationDefinitions.contractVersion('coc1_m1'),
        'css-sag-20261109-v3');
    expect(MissionSimulationDefinitions.contractVersion('coc4_m3'),
        'css-sag-20261009-v1');
    expect(MissionSimulationDefinitions.contractVersion('coc2_m2'),
        'css-sag-20261011-v2');
  });

  test('server-evaluated conditions only use paths the replay understands',
      () {
    for (final mission in MissionSimulationDefinitions.all) {
      for (final phase in mission.toJson()['phases'] as List) {
        for (final condition
            in _serverConditions(Map<String, dynamic>.from(phase as Map))) {
          final path = condition['path'] as String;
          expect(_serverPaths, contains(path.split('.').first),
              reason: '${mission.id} ${phase['id']} uses $path');
          expect(_serverOperators,
              contains(condition['operator'] as String? ?? 'equals'),
              reason: '${mission.id} ${phase['id']} uses $condition');
        }
      }
    }
  });

  test('the bench contract has six phases with visible steps', () {
    expect(definition.phases.map((phase) => phase.resolvedInteraction.name),
        ['inspect', 'place', 'place', 'connect', 'testRun', 'review']);
    for (final phase in definition.phases.take(5)) {
      expect(phase.presentation['bench_steps'], isA<List>(),
          reason: phase.id);
    }
    expect(MissionEquipmentSimulator.isAssemblyBench(definition), isTrue);
    expect(
        MissionSimulationDefinitions.all
            .where(MissionEquipmentSimulator.isAssemblyBench)
            .map((mission) => mission.id),
        ['coc1_m2']);
  });
}
