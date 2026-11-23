import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Completes a phase that a realistic lab owns, by touch, through the lab.
///
/// The steps follow the order in which the exported happy path records its
/// evidence (EquipmentPracticeDriver), so assessment_mode_test can compare
/// the recorded evidence with the server-evaluated plan action by action.
Future<void> completeLabPhase(
    WidgetTester tester, MissionPhaseDefinition phase) async {
  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> key(String value) => tap(find.byKey(ValueKey(value)));

  switch (phase.id) {
    case 'coc2_m2_p2':
      const t568b = [
        'white_orange',
        'orange',
        'white_green',
        'blue',
        'white_blue',
        'green',
        'white_brown',
        'brown',
      ];
      for (var i = 0; i < t568b.length; i++) {
        await key('lab-cable-conductor-${t568b[i]}');
        await key('lab-cable-pin-${i + 1}');
      }
      await key('lab-cable-crimp');
    case 'coc4_m4_p1':
      // Plan order: tool on the screw, the confirmed sequence, the operation.
      await key('lab-pcie-tool-esd_driver');
      await key('lab-pcie-screw');
      await tap(find.text(MissionContentData.labPcieUnplugLabel));
      await tap(find.text(MissionContentData.labPcieWearStrapLabel));
      await key('lab-pcie-lift');
      await key('lab-pcie-inspect');
      await key('lab-pcie-contingency');
    case 'coc4_m4_p2':
      await key('lab-pcie-rotate');
      await key('lab-pcie-adapter');
      await key('lab-pcie-slot');
    case 'coc4_m4_p4':
      await key('lab-pcie-latch');
      await key('lab-pcie-tool-esd_driver');
      await key('lab-pcie-screw');
      await key('lab-pcie-configure');
      await key('lab-pcie-panel');
      await key('lab-pcie-power-back');
    default:
      throw ArgumentError.value(phase.id, 'phase.id', 'no lab owns this phase');
  }
}
