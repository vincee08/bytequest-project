import 'dart:convert';
import 'dart:io';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import '../test/support/equipment_practice_driver.dart';

// Raw independent work-order evidence for rollback-only PostgreSQL parity tests.
void main(List<String> args) {
  final fixtures = <String, dynamic>{};
  for (final definition in MissionSimulationDefinitions.all) {
    final driver = EquipmentPracticeDriver(definition);
    for (final phase in definition.phases) {
      driver.complete(phase);
    }
    fixtures[definition.id] = driver.actions.map((a) => a.toJson()).toList();
  }
  File(args.single).writeAsStringSync(jsonEncode(fixtures));
}
