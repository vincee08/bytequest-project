import 'package:bytequest/screens/simulation/runtime/mission_equipment_simulator.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_controller.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> waitForEquipmentState(
    WidgetTester tester, bool Function() predicate) async {
  for (var count = 0; count < 150 && !predicate(); count++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(predicate(), true,
      reason: 'Timed out waiting for persisted UI state.');
  await tester.pumpAndSettle();
}

Future<void> tapEquipmentControl(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.ensureVisible(finder);
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignment: 0.35,
    duration: Duration.zero,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  // The tap may start an asynchronous evidence write and a progress
  // animation. Waiting for the whole tree to settle here can deadlock a live
  // device binding (especially while a landscape keyboard is dismissing).
  // Callers wait for the specific persisted state they require.
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> performEquipmentAction(
    WidgetTester tester,
    MissionPhaseDefinition phase,
    MissionEvidenceAction action,
    MissionRuntimeController controller) async {
  final value = action.value;
  final equipment =
      MissionEquipmentSimulator.map(phase.presentation['equipment']);
  final before = controller.state.acceptedEvidenceIds.length;
  switch (action.actionType) {
    case 'object_inspected':
      await tapEquipmentControl(
          tester, find.byKey(ValueKey('inspect-target-${action.target}')));
    case 'selection_confirmed':
      final group = value['selection_group'];
      Finder within(Finder finder) => group is String
          ? find.descendant(
              of: find.byKey(ValueKey('classification-$group')),
              matching: finder)
          : finder.first;
      for (final id in value['selected_ids'] as List) {
        await tapEquipmentControl(
            tester, within(find.byKey(ValueKey('multi-select-$id'))));
      }
      await tapEquipmentControl(
          tester, within(find.byKey(const ValueKey('multi-select-confirm'))));
    case 'tool_attempted':
      await tapEquipmentControl(
          tester, find.byKey(ValueKey('tool-target-${action.target}')));
      await tapEquipmentControl(
          tester, find.byKey(ValueKey('tool-tray-tool-${value['tool_id']}')));
    case 'connection_created':
      await tapEquipmentControl(tester,
          find.byKey(ValueKey('connection-source-${value['source_id']}')));
      await tapEquipmentControl(
          tester,
          find.byKey(
              ValueKey('connection-destination-${value['destination_id']}')));
    case 'configuration_applied':
      final fields = MissionEquipmentSimulator.maps(
          MissionEquipmentSimulator.map(equipment['configuration'])['fields'] ??
              phase.presentation['fields']);
      for (final field in fields) {
        final desired = (value['values'] as Map)[field['id']];
        final finder =
            find.byKey(ValueKey('configuration-field-${field['id']}'));
        await tester.ensureVisible(finder);
        if (field['type'] == 'dropdown') {
          final option =
              MissionEquipmentSimulator.item(field['options'], desired);
          await tapEquipmentControl(tester, finder);
          await tapEquipmentControl(
              tester, find.text(option['label'] as String).last);
        } else if (field['type'] == 'toggle') {
          if (tester.widget<SwitchListTile>(finder).value != desired) {
            await tapEquipmentControl(tester, finder);
          }
        } else {
          await tester.enterText(finder, desired.toString());
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
        }
      }
      await tapEquipmentControl(
          tester, find.widgetWithText(FilledButton, 'Apply configuration'));
    case 'sequence_reordered':
      final desired = (value['order'] as List).cast<String>();
      for (var position = 0; position < desired.length; position++) {
        List<String> renderedOrder() => tester
            .widgetList<Card>(find.byType(Card))
            .where((card) =>
                card.key is ValueKey<String> &&
                (card.key as ValueKey<String>)
                    .value
                    .startsWith('sequence-item-'))
            .map((card) => (card.key as ValueKey<String>)
                .value
                .substring('sequence-item-'.length))
            .toList();
        final item = MissionEquipmentSimulator.item(
            phase.presentation['items'], desired[position]);
        while (renderedOrder().indexOf(desired[position]) > position) {
          final count = controller.state.acceptedEvidenceIds.length;
          await tapEquipmentControl(
              tester, find.byTooltip('Move ${item['label']} up'));
          await waitForEquipmentState(tester,
              () => controller.state.acceptedEvidenceIds.length > count);
        }
      }
      await tapEquipmentControl(
          tester, find.byKey(ValueKey('sequence-confirm-${phase.id}')));
    case 'placement_attempted':
      await tapEquipmentControl(
          tester, find.byKey(ValueKey('placement-item-${value['item_id']}')));
      await tapEquipmentControl(
          tester,
          find.byKey(
              ValueKey('placement-destination-${value['destination_id']}')));
      await tapEquipmentControl(
          tester,
          find.byKey(
              ValueKey('placement-orientation-${value['orientation']}')));
      await tapEquipmentControl(
          tester, find.byKey(const ValueKey('placement-place')));
    case 'diagnostic_action':
      final diagnostic = MissionEquipmentSimulator.item(
          phase.presentation['diagnostic_actions'], action.target);
      await tapEquipmentControl(tester,
          find.widgetWithText(OutlinedButton, diagnostic['label'] as String));
    case 'test_started':
      final start = find.byKey(const ValueKey('test-run-start'));
      await tester.ensureVisible(start);
      await tester.pumpAndSettle();
      await tester.tap(start);
      // Do not pumpAndSettle while the indeterminate test-progress indicator
      // is active. On a live Android binding that animation intentionally
      // never settles; pump frames until the persisted timer result arrives.
      await tester.pump();
      for (var count = 0;
          count < 600 &&
              !(controller.state.acceptedEvidenceIds.length > before &&
                  controller.state.pendingEvidence.isEmpty);
          count++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        controller.state.acceptedEvidenceIds.length > before &&
            controller.state.pendingEvidence.isEmpty,
        true,
        reason: 'Timed out waiting for test-start evidence acknowledgement.',
      );
      for (var count = 0;
          count < 600 &&
              controller.state.testStatusFor(action.target!) !=
                  MissionTestStatus.completed;
          count++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        controller.state.testStatusFor(action.target!),
        MissionTestStatus.completed,
        reason: 'Timed out waiting for the scheduled technical test result.',
      );
      await tester.pumpAndSettle();
    case 'test_completed':
      return; // The real scheduler records completion.
    case 'result_interpreted':
      final combined = phase.presentation['requires_interpretation'] == true;
      final field = find.byKey(ValueKey(
          '${combined ? 'test-interpretation' : 'interpretation-input'}-${phase.id}'));
      await tester.ensureVisible(field);
      await tester.enterText(field, value['interpretation'] as String);
      FocusManager.instance.primaryFocus?.unfocus();
      await tapEquipmentControl(
          tester,
          combined
              ? find.byKey(ValueKey('test-interpretation-record-${phase.id}'))
              : find.widgetWithText(FilledButton, 'Record interpretation'));
    case 'observation_recorded':
      final field = find.byKey(ValueKey('observation-input-${phase.id}'));
      await tester.ensureVisible(field);
      await tester.enterText(field, value['observation'] as String);
      FocusManager.instance.primaryFocus?.unfocus();
      await tapEquipmentControl(
          tester, find.widgetWithText(FilledButton, 'Record observation'));
    case 'scenario_decision':
      final choice = MissionEquipmentSimulator.item(
          phase.presentation['choices'], action.target);
      await tapEquipmentControl(tester,
          find.widgetWithText(OutlinedButton, choice['label'] as String));
    case 'equipment_operation':
      await tapEquipmentControl(
          tester, find.byKey(ValueKey('equipment-operation-${action.target}')));
    default:
      throw StateError('No UI driver for ${action.actionType}.');
  }
  await waitForEquipmentState(
      tester,
      () =>
          controller.state.acceptedEvidenceIds.length > before &&
          controller.state.pendingEvidence.isEmpty);
}
