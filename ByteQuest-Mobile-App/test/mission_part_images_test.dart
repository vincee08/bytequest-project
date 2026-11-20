import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testers reported parts across COC1–COC4 showing an icon instead of a
/// photo. Every physical part a learner inspects or handles now has one, and
/// every picture a mission references is bundled with the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, String?> picturesOf(String missionId) {
    final definition = MissionSimulationDefinitions.byId(missionId);
    final pictures = <String, String?>{};
    void add(Object? id, Object? image) {
      if (id is! String) return;
      pictures[id] ??= image is String && image.isNotEmpty ? image : null;
    }

    for (final object in definition.scene.objects) {
      add(object.id, object.metadata['imageAsset']);
    }
    for (final phase in definition.phases) {
      final presentation = phase.presentation;
      final lists = [
        for (final key in const [
          'objects',
          'items',
          'targets',
          'sources',
          'destinations',
        ])
          presentation[key],
        if (presentation['equipment'] case final Map equipment) ...[
          for (final group in const ['placement', 'connection'])
            if (equipment[group] case final Map lists)
              for (final key in const ['items', 'sources', 'destinations'])
                lists[key],
        ],
      ];
      for (final list in lists) {
        for (final entry in (list as List? ?? const []).whereType<Map>()) {
          add(entry['id'], entry['imageAsset']);
        }
      }
    }
    return pictures;
  }

  test('every part picture referenced by a mission is bundled', () async {
    final assets = <String>{
      for (final definition in MissionSimulationDefinitions.all)
        ...picturesOf(definition.id).values.whereType<String>(),
    };
    expect(assets.length, greaterThan(20));
    for (final asset in assets) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(1000), reason: asset);
    }
  });

  test('physical parts in COC1–COC4 show a photo, not an icon', () {
    const parts = {
      'coc1_m1': ['cpu_socket', 'dimm_slot', 'atx_power_port'],
      'coc1_m3': [
        'system_unit',
        'boot_usb',
        'installation_media',
        'driver_media',
        'system_disk',
        'boot_monitor',
      ],
      'coc1_m4': ['network_adapter'],
      'coc1_m5': ['workstation', 'display', 'network'],
      'coc2_m2': ['workstation'],
      'coc2_m4': ['workstation', 'repeater'],
      'coc2_m5': ['workstation', 'server'],
      'coc3_m1': [
        'server_chassis',
        'network_drop',
        'power_conditioner',
        'installation_media',
      ],
      'coc3_m2': ['server', 'server_node', 'client_node', 'installation_media'],
      'coc3_m3': ['server_node', 'client_node'],
      'coc3_m4': [
        'server',
        'client',
        'server_node',
        'client_node',
        'network_printer',
      ],
      'coc3_m5': ['server', 'client', 'server_node', 'client_node'],
      'coc4_m1': ['workstation', 'display', 'network_adapter'],
      'coc4_m2': [
        'workstation',
        'memory_module',
        'storage_drive',
        'power_supply',
        'diagnostic_tool',
      ],
      'coc4_m3': ['workstation', 'network_interface'],
      'coc4_m4': ['workstation', 'replacement_component', 'service_tool'],
      'coc4_m5': ['workstation', 'maintenance_tool'],
    };
    for (final mission in parts.entries) {
      final pictures = picturesOf(mission.key);
      for (final id in mission.value) {
        expect(pictures.containsKey(id), isTrue,
            reason: '${mission.key} has no part $id');
        expect(pictures[id], isNotNull,
            reason: '${mission.key} $id shows an icon instead of a photo');
      }
    }
  });

  test('procedure steps and placement positions keep their icons', () {
    // coc3_m1 uses `network` for a procedure step, not for an adapter.
    final coc3m1 = picturesOf('coc3_m1');
    expect(coc3m1.containsKey('network'), isTrue);
    expect(coc3m1['network'], isNull);
    // A photo on a position would hint where a part belongs.
    for (final definition in MissionSimulationDefinitions.all) {
      if (definition.id == 'coc1_m2') continue;
      final pictures = picturesOf(definition.id);
      for (final id in pictures.keys.where((id) => id.endsWith('_position'))) {
        expect(pictures[id], isNull, reason: '${definition.id} $id');
      }
    }
  });
}
