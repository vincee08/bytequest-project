import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/data/mission_lab_phases.dart';
import 'package:bytequest/data/mission_phase_guidance.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/screens/simulation/components/labs/mission_labs.dart';
import 'package:bytequest/screens/simulation/runtime/mission_equipment_simulator.dart';
import 'package:bytequest/screens/simulation/runtime/mission_phase_completion_policy.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/equipment_practice_driver.dart';

/// The realistic labs perform the same recorded actions as the standard
/// panels: the same types, targets and values, evaluated by the real
/// equipment simulator and reducer, so scoring contracts are unchanged.
typedef _Recorded = (
  String type,
  String? target,
  Map<String, dynamic> value,
  Map<String, dynamic> enriched,
);

class _Lab {
  _Lab(String missionId, String phaseId, {bool assessment = false})
      : definition = MissionSimulationDefinitions.byId(missionId) {
    driver = EquipmentPracticeDriver(definition);
    if (assessment) {
      driver.state = MissionRuntimeState.initial(missionId,
          mode: MissionRuntimeMode.assessment,
          assessmentAttemptId: 'lab-test-attempt',
          definitionVersion:
              MissionSimulationDefinitions.contractVersion(missionId));
    }
    phase = definition.phases.firstWhere((p) => p.id == phaseId);
    driver.state = driver.state.copyWith(currentPhaseId: phaseId);
  }

  final MissionSimulationDefinition definition;
  late final EquipmentPracticeDriver driver;
  late final MissionPhaseDefinition phase;
  final recorded = <_Recorded>[];

  List<String> get types => [for (final r in recorded) r.$1];

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => MissionLabs.build(
            definition: definition,
            phase: phase,
            state: driver.state,
            enabled: true,
            onAction: (type, target, value) async {
              final enriched = driver.act(phase, type, target, value);
              recorded.add((type, target, value, enriched));
              setState(() {});
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) =>
    _tap(tester, find.byKey(ValueKey(key)));

const _t568b = [
  'white_orange',
  'orange',
  'white_green',
  'blue',
  'white_blue',
  'green',
  'white_brown',
  'brown',
];

Future<void> _terminate(WidgetTester tester, List<String> order) async {
  for (var i = 0; i < order.length; i++) {
    await _tapKey(tester, 'lab-cable-conductor-${order[i]}');
    await _tapKey(tester, 'lab-cable-pin-${i + 1}');
  }
}

void main() {
  test('the labs own only their phases', () {
    final m2 = MissionSimulationDefinitions.byId('coc2_m2');
    final m4 = MissionSimulationDefinitions.byId('coc4_m4');
    expect([
      for (final p in m2.phases)
        if (MissionLabs.ownsPhase(m2, p)) p.id
    ], [
      'coc2_m2_p2'
    ]);
    expect([
      for (final p in m4.phases)
        if (MissionLabs.ownsPhase(m4, p)) p.id
    ], [
      'coc4_m4_p1',
      'coc4_m4_p2',
      'coc4_m4_p4'
    ]);
    for (final definition in MissionSimulationDefinitions.all) {
      if (definition.id == 'coc2_m2' || definition.id == 'coc4_m4') continue;
      expect(definition.phases.any((p) => MissionLabs.ownsPhase(definition, p)),
          isFalse,
          reason: definition.id);
    }
  });

  group('COC2 M2 RJ45 termination lab', () {
    testWidgets('a T568B crimp records the confirmed order and completes',
        (tester) async {
      final lab = _Lab('coc2_m2', 'coc2_m2_p2');
      await lab.pump(tester);
      await _terminate(tester, _t568b);
      expect(lab.recorded, isEmpty,
          reason: 'inserting conductors records nothing until the crimp');

      await _tapKey(tester, 'lab-cable-crimp');
      expect(lab.types, ['sequence_reordered']);
      final (_, target, value, enriched) = lab.recorded.single;
      expect(target, 'coc2_m2_p2');
      expect(value['order'], _t568b);
      expect(value['confirmed'], isTrue);
      expect(value['input_method'], 'tap');
      expect(enriched['simulation_valid'], isTrue);
      expect(
          MissionPhaseCompletionPolicy.canAdvance(lab.phase, lab.driver.state),
          isTrue);
      expect(find.text(MissionContentData.labCableCrimpedPractice),
          findsOneWidget);
    });

    testWidgets('a miswired crimp is recorded as wrong and can be redone',
        (tester) async {
      final lab = _Lab('coc2_m2', 'coc2_m2_p2');
      await lab.pump(tester);
      final swapped = [..._t568b]
        ..[0] = 'orange'
        ..[1] = 'white_orange';
      await _terminate(tester, swapped);
      await _tapKey(tester, 'lab-cable-crimp');
      expect(lab.recorded.single.$4['simulation_valid'], isFalse);
      expect(
          MissionPhaseCompletionPolicy.canAdvance(lab.phase, lab.driver.state),
          isFalse);
      expect(find.text(MissionContentData.labCableMiswiredPractice),
          findsOneWidget);

      await _tapKey(tester, 'lab-cable-reterminate');
      await _terminate(tester, _t568b);
      await _tapKey(tester, 'lab-cable-crimp');
      expect(lab.recorded.last.$4['simulation_valid'], isTrue);
      expect(
          MissionPhaseCompletionPolicy.canAdvance(lab.phase, lab.driver.state),
          isTrue);
    });

    testWidgets('a conductor can be dragged into a channel', (tester) async {
      final lab = _Lab('coc2_m2', 'coc2_m2_p2');
      await lab.pump(tester);
      // A 411 dp phone (Pixel 7) shows the plug's front view.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      await tester.pumpAndSettle();
      expect(find.text(MissionContentData.labCableConnectorCaption),
          findsOneWidget);
      final wire = find.byKey(const ValueKey('lab-cable-conductor-blue'));
      final pin = find.byKey(const ValueKey('lab-cable-pin-4'));
      await tester.ensureVisible(wire);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(wire));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(tester.getCenter(pin));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('lab-cable-conductor-blue')), findsNothing,
          reason: 'the conductor left the cable end for pin 4');
      expect(find.bySemanticsLabel(RegExp(r'^Pin 4 channel, holds Blue')),
          findsOneWidget);
    });

    for (final (width, sideways) in const [
      (360.0, true),
      (411.0, false),
      (900.0, false),
    ]) {
      testWidgets('all eight pin channels are on screen at $width dp',
          (tester) async {
        final lab = _Lab('coc2_m2', 'coc2_m2_p2');
        await lab.pump(tester);
        tester.view.physicalSize = Size(width * 3, 2400);
        await tester.pumpAndSettle();
        for (var pin = 1; pin <= 8; pin++) {
          final rect =
              tester.getRect(find.byKey(ValueKey('lab-cable-pin-$pin')));
          expect(rect.left, greaterThanOrEqualTo(0), reason: 'pin $pin');
          expect(rect.right, lessThanOrEqualTo(width), reason: 'pin $pin');
          expect(rect.width, greaterThanOrEqualTo(48), reason: 'pin $pin');
          expect(rect.height, greaterThanOrEqualTo(48), reason: 'pin $pin');
        }
        expect(
            find.text(sideways
                ? MissionContentData.labCableConnectorCaptionSide
                : MissionContentData.labCableConnectorCaption),
            findsOneWidget);
      });
    }

    testWidgets('assessment hides the colour order and stays neutral',
        (tester) async {
      final lab = _Lab('coc2_m2', 'coc2_m2_p2', assessment: true);
      await lab.pump(tester);
      expect(
          find.text(MissionContentData.labCableReferenceTitle), findsNothing);
      final swapped = [..._t568b]
        ..[3] = 'white_blue'
        ..[4] = 'blue';
      await _terminate(tester, swapped);
      await _tapKey(tester, 'lab-cable-crimp');
      final (_, _, value, enriched) = lab.recorded.single;
      expect(value['confirmed'], isTrue);
      expect(enriched['simulation_valid'], isFalse);
      // The confirmed order is the answer: the phase may continue, and the
      // screen does not say whether it was right.
      expect(lab.driver.state.interactionCompletedPhaseIds,
          contains('coc2_m2_p2'));
      expect(find.text(MissionContentData.labCableCrimped), findsOneWidget);
      expect(
          find.text(MissionContentData.labCableMiswiredPractice), findsNothing);
    });
  });

  group('COC4 M4 PCIe replacement lab', () {
    testWidgets('isolating first, then removing and inspecting completes p1',
        (tester) async {
      final lab = _Lab('coc4_m4', 'coc4_m4_p1');
      await lab.pump(tester);
      await _tapKey(tester, 'lab-pcie-contingency');
      await _tap(tester, find.text(MissionContentData.labPcieUnplugLabel));
      await _tap(tester, find.text(MissionContentData.labPcieWearStrapLabel));
      await _tapKey(tester, 'lab-pcie-tool-esd_driver');
      await _tapKey(tester, 'lab-pcie-screw');
      await _tapKey(tester, 'lab-pcie-lift');
      await _tapKey(tester, 'lab-pcie-inspect');

      expect(lab.types,
          ['equipment_operation', 'tool_attempted', 'sequence_reordered']);
      expect(lab.recorded[0].$2, 'protect_service_data');
      expect(lab.recorded[1].$2, 'retaining_screw');
      expect(lab.recorded[1].$3['tool_id'], 'esd_driver');
      expect(lab.recorded[1].$4['simulation_valid'], isTrue);
      expect(lab.recorded[2].$3['order'], ['isolate', 'remove', 'inspect']);
      expect(lab.recorded[2].$3['confirmed'], isTrue);
      expect(lab.recorded[2].$4['simulation_valid'], isTrue);
      expect(
          MissionPhaseCompletionPolicy.canAdvance(lab.phase, lab.driver.state),
          isTrue);
    });

    testWidgets('removing the card before isolating is recorded as unsafe',
        (tester) async {
      final lab = _Lab('coc4_m4', 'coc4_m4_p1');
      await lab.pump(tester);
      await _tapKey(tester, 'lab-pcie-tool-esd_driver');
      await _tapKey(tester, 'lab-pcie-screw');
      await _tapKey(tester, 'lab-pcie-lift');
      await _tap(tester, find.text(MissionContentData.labPcieUnplugLabel));
      await _tap(tester, find.text(MissionContentData.labPcieWearStrapLabel));
      await _tapKey(tester, 'lab-pcie-inspect');
      final sequence = lab.recorded.last;
      expect(sequence.$3['order'], ['remove', 'isolate', 'inspect']);
      expect(sequence.$4['simulation_valid'], isFalse);
      expect(find.text(MissionContentData.labPcieProcedureOutOfOrder),
          findsOneWidget);
      expect(find.byKey(const ValueKey('lab-pcie-restart')), findsOneWidget);
    });

    testWidgets('the wire cutter does not undo the bracket screw',
        (tester) async {
      final lab = _Lab('coc4_m4', 'coc4_m4_p1');
      await lab.pump(tester);
      await _tapKey(tester, 'lab-pcie-tool-wire_cutter');
      await _tapKey(tester, 'lab-pcie-screw');
      expect(lab.types, ['tool_attempted']);
      expect(lab.recorded.single.$3['tool_id'], 'wire_cutter');
      expect(lab.recorded.single.$4['simulation_valid'], isFalse);
      final lift = tester.widget<OutlinedButton>(find.descendant(
          of: find.byKey(const ValueKey('lab-pcie-lift')),
          matching: find.byWidgetPredicate((w) => w is OutlinedButton)));
      expect(lift.onPressed, isNull, reason: 'the screw still holds the card');
    });

    testWidgets('the new adapter seats only with its bracket at the rear',
        (tester) async {
      final lab = _Lab('coc4_m4', 'coc4_m4_p2');
      await lab.pump(tester);
      await _tapKey(tester, 'lab-pcie-adapter');
      await _tapKey(tester, 'lab-pcie-slot');
      expect(lab.recorded.single.$1, 'placement_attempted');
      expect(lab.recorded.single.$2, 'workstation');
      expect(lab.recorded.single.$3['item_id'], 'replacement_component');
      expect(lab.recorded.single.$3['orientation'], 'rotated');
      expect(lab.recorded.single.$4['simulation_valid'], isFalse);
      expect(lab.driver.state.placements,
          isNot(contains('replacement_component')));

      await _tapKey(tester, 'lab-pcie-rotate');
      await _tapKey(tester, 'lab-pcie-adapter');
      await _tapKey(tester, 'lab-pcie-slot');
      expect(lab.recorded.last.$3['orientation'], 'aligned');
      expect(lab.recorded.last.$3['compatible'], isTrue);
      expect(lab.recorded.last.$4['simulation_valid'], isTrue);
      expect(
          lab.driver.state.placements['replacement_component'], 'workstation');
      expect(
          MissionPhaseCompletionPolicy.canAdvance(lab.phase, lab.driver.state),
          isTrue);
    });

    testWidgets('latch, fasten, configure, then close and power complete p4',
        (tester) async {
      final lab = _Lab('coc4_m4', 'coc4_m4_p4');
      await lab.pump(tester);
      await _tapKey(tester, 'lab-pcie-latch');
      await _tapKey(tester, 'lab-pcie-tool-esd_driver');
      await _tapKey(tester, 'lab-pcie-screw');
      await _tapKey(tester, 'lab-pcie-configure');
      await _tapKey(tester, 'lab-pcie-panel');
      await _tapKey(tester, 'lab-pcie-power-back');
      expect(lab.types, ['sequence_reordered'],
          reason: 'phase 4 records only its step order');
      expect(lab.recorded.single.$3['order'],
          ['seat', 'fasten', 'configure', 'restore']);
      expect(lab.recorded.single.$4['simulation_valid'], isTrue);
      expect(
          MissionPhaseCompletionPolicy.canAdvance(lab.phase, lab.driver.state),
          isTrue);
    });

    testWidgets('assessment never reveals whether the order was safe',
        (tester) async {
      final lab = _Lab('coc4_m4', 'coc4_m4_p4', assessment: true);
      await lab.pump(tester);
      await _tapKey(tester, 'lab-pcie-configure');
      await _tapKey(tester, 'lab-pcie-latch');
      await _tapKey(tester, 'lab-pcie-tool-esd_driver');
      await _tapKey(tester, 'lab-pcie-screw');
      await _tapKey(tester, 'lab-pcie-panel');
      await _tapKey(tester, 'lab-pcie-power-back');
      expect(lab.recorded.single.$4['simulation_valid'], isFalse);
      expect(find.text(MissionContentData.labPcieProcedureRecorded),
          findsOneWidget);
      expect(find.text(MissionContentData.labPcieProcedureOutOfOrder),
          findsNothing);
      expect(find.byKey(const ValueKey('lab-pcie-restart')), findsOneWidget);
    });

    testWidgets('a resumed assessment shows every recorded step as performed',
        (tester) async {
      final lab = _Lab('coc4_m4', 'coc4_m4_p1', assessment: true);
      await lab.pump(tester);
      await _tapKey(tester, 'lab-pcie-tool-esd_driver');
      await _tapKey(tester, 'lab-pcie-screw');
      await _tapKey(tester, 'lab-pcie-lift');
      await _tapKey(tester, 'lab-pcie-inspect');
      await _tap(tester, find.text(MissionContentData.labPcieUnplugLabel));
      await _tap(tester, find.text(MissionContentData.labPcieWearStrapLabel));
      expect(lab.recorded.last.$4['simulation_valid'], isFalse);

      // Pause and resume: a fresh lab restores from the recorded state.
      await tester.pumpWidget(const SizedBox.shrink());
      await lab.pump(tester);
      expect(find.text(MissionContentData.labPciePowerIsolated), findsWidgets);
      expect(find.text(MissionContentData.labPcieStrapOn), findsWidgets);
      expect(find.text(MissionContentData.labPcieInspected), findsOneWidget);
      expect(find.text(MissionContentData.labPcieProcedureRecorded),
          findsOneWidget);
      expect(find.text(MissionContentData.labPcieProcedureOutOfOrder),
          findsNothing);
    });

    testWidgets('the slot says what it holds while the failed card is in it',
        (tester) async {
      final lab = _Lab('coc4_m4', 'coc4_m4_p1');
      await lab.pump(tester);
      expect(find.bySemanticsLabel(MissionContentData.labPcieSlotHoldsFailed),
          findsOneWidget);
      expect(find.bySemanticsLabel(MissionContentData.labPcieSlotEmpty),
          findsNothing);
      await _tapKey(tester, 'lab-pcie-tool-esd_driver');
      await _tapKey(tester, 'lab-pcie-screw');
      await _tapKey(tester, 'lab-pcie-lift');
      expect(find.bySemanticsLabel(MissionContentData.labPcieSlotVacant),
          findsOneWidget);
    });
  });

  group('lab guidance', () {
    const labPhases = {
      'coc2_m2': ['coc2_m2_p2'],
      'coc4_m4': ['coc4_m4_p1', 'coc4_m4_p2', 'coc4_m4_p4'],
    };
    for (final assessment in [false, true]) {
      for (final entry in labPhases.entries) {
        for (final phaseId in entry.value) {
          testWidgets(
              '$phaseId ${assessment ? 'assessment' : 'practice'}: every '
              'guide step outlines a rendered lab control', (tester) async {
            final lab = _Lab(entry.key, phaseId, assessment: assessment);
            await lab.pump(tester);
            final guide =
                MissionActionGuide.forPhase(lab.phase, lab.driver.state);
            expect(
                guide.steps.first.text, MissionLabPhases.guide(phaseId)!.text);
            for (final step in guide.steps) {
              expect(find.byKey(ValueKey<String>(step.controlKey!)),
                  findsOneWidget,
                  reason: '$phaseId: ${step.text}');
            }
            final panel =
                MissionPhaseGuidance.forPhase(lab.phase, lab.driver.state);
            expect(panel.steps,
                MissionLabPhases.panel(phaseId, practice: !assessment)!.steps);
            // The colour order lives on the practice reference card only.
            expect(
                [...panel.steps, ...guide.steps.map((step) => step.text)]
                    .any((text) => text.contains('T568B')),
                !assessment && phaseId == 'coc2_m2_p2');
          });
        }
      }
    }

    // The standard reorder list starts from the phase's listed order; the
    // bench lists its step controls the same way, so reading it top to
    // bottom never spells out the safe order.
    for (final (phaseId, keys) in const [
      (
        'coc4_m4_p1',
        {
          'isolate': 'lab-pcie-power',
          'remove': 'lab-pcie-lift',
          'inspect': 'lab-pcie-inspect',
        }
      ),
      (
        'coc4_m4_p4',
        {
          'seat': 'lab-pcie-latch',
          'fasten': 'lab-pcie-tool-esd_driver',
          'configure': 'lab-pcie-configure',
          'restore': 'lab-pcie-panel',
        }
      ),
    ]) {
      testWidgets('$phaseId lists its step controls in the listed order',
          (tester) async {
        final lab = _Lab('coc4_m4', phaseId, assessment: true);
        await lab.pump(tester);
        final listed =
            MissionEquipmentSimulator.maps(lab.phase.presentation['items'])
                .map((item) => item['id'] as String)
                .toList();
        expect(listed, isNot(practiceOrders[phaseId]),
            reason: 'the listed order is not the safe order');
        final tops = [
          for (final step in listed)
            tester.getTopLeft(find.byKey(ValueKey<String>(keys[step]!))).dy,
        ];
        expect(tops, [...tops]..sort(), reason: '$listed top to bottom');
      });
    }
  });
}
