import 'dart:convert';
import 'dart:io';

import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';

/// The retired COC1 M2 practice contract css-sag-20261011-v2 (card-style
/// placement with orientation dialog, sequence and inspection test), renamed
/// `legacy_m2`. COC1 M2 now runs on the assembly bench; this fixture keeps
/// the generic EquipmentWorkspace and ControlledPlacementInteraction
/// behaviours covered for the missions that still use them.
final MissionSimulationDefinition legacyAssemblyDefinition =
    MissionSimulationDefinition.fromJson(jsonDecode(
            File('test/support/legacy_assembly_definition.json')
                .readAsStringSync())
        as Map<String, dynamic>);
