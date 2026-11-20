import 'package:flutter/widgets.dart';

import '../../../../data/mission_lab_phases.dart';
import '../../runtime/mission_runtime_models.dart';
import '../tool_tray.dart' show MissionActionCallback;
import 'cable_termination_lab.dart';
import 'pcie_replacement_lab.dart';

/// Mission-specific realistic labs.
///
/// A lab is another way to perform the actions a phase already defines. It
/// emits the same action types, targets and values as the standard task
/// panel, so mission definitions, the practice contracts published to the
/// server and the published assessment contracts stay unchanged. Phases a
/// lab does not own keep their standard workspace and panel.
abstract final class MissionLabs {
  /// True when a realistic lab, not the standard panel, drives [phase]. The
  /// owned phases are listed in [MissionLabPhases] with their guidance.
  static bool ownsPhase(
    MissionSimulationDefinition definition,
    MissionPhaseDefinition phase,
  ) =>
      phase.id.startsWith('${definition.id}_') &&
      MissionLabPhases.owns(phase.id);

  static Widget build({
    Key? key,
    required MissionSimulationDefinition definition,
    required MissionPhaseDefinition phase,
    required MissionRuntimeState state,
    required MissionActionCallback onAction,
    required bool enabled,
  }) =>
      switch (definition.id) {
        'coc2_m2' => CableTerminationLab(
            key: key,
            phase: phase,
            state: state,
            onAction: onAction,
            enabled: enabled,
          ),
        'coc4_m4' => PcieReplacementLab(
            key: key,
            phase: phase,
            state: state,
            onAction: onAction,
            enabled: enabled,
          ),
        _ => throw ArgumentError.value(definition.id, 'definition.id'),
      };
}
