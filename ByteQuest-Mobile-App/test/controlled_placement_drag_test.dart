import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/screens/simulation/interactions/controlled_placement_interaction.dart';
import 'package:bytequest/screens/simulation/interactions/connection_interaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/equipment_practice_driver.dart';

void main() {
  for (final installation in [true, false]) {
    testWidgets(
        'lower-panel ${installation ? 'part' : 'cable'} drag scrolls to an offscreen destination',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final definition = MissionSimulationDefinitions.byId(
          installation ? 'coc1_m2' : 'coc1_m4');
      final driver = EquipmentPracticeDriver(definition);
      for (final phase in definition.phases.take(installation ? 1 : 2)) {
        driver.complete(phase);
      }
      final phase = definition.phases[installation ? 1 : 2];
      Future<void> record(
          String type, String? target, Map<String, dynamic> value) async {
        driver.act(phase, type, target, value);
      }

      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
              height: 300,
              child: SingleChildScrollView(
                key: const ValueKey('drag-scroll-viewport'),
                child: installation
                    ? ControlledPlacementInteraction(
                        phase: phase, state: driver.state, onAction: record)
                    : ConnectionInteraction(
                        phase: phase, state: driver.state, onAction: record),
              )),
        ),
      )));
      final source = find.byKey(ValueKey(installation
          ? 'placement-item-psu'
          : 'connection-source-network_adapter'));
      final target = find.byKey(ValueKey(installation
          ? 'placement-destination-psu_bay'
          : 'connection-destination-ethernet_port'));
      final viewport =
          tester.getRect(find.byKey(const ValueKey('drag-scroll-viewport')));
      expect(viewport.contains(tester.getCenter(source)), true);
      expect(viewport.contains(tester.getCenter(target)), false);
      final gesture = await tester.startGesture(tester.getCenter(source));
      await gesture.moveBy(const Offset(24, 0));
      await gesture.moveTo(Offset(viewport.center.dx, viewport.bottom - 4));
      for (var step = 0; step < 200; step++) {
        await tester.pump(const Duration(milliseconds: 30));
        if (viewport.contains(tester.getCenter(target))) break;
      }
      expect(viewport.contains(tester.getCenter(target)), true);
      await gesture.moveTo(tester.getCenter(target));
      await gesture.up();
      await tester.pumpAndSettle();
      if (installation) {
        await tester
            .tap(find.byKey(const ValueKey('workspace-orientation-aligned')));
        await tester.pumpAndSettle();
        expect(driver.state.placements['psu'], 'psu_bay');
      } else {
        expect(driver.state.connectedNodePairs,
            contains('network_adapter>ethernet_port'));
      }
      expect(driver.actions.last.value['input_method'], 'drag');
      final scrollState = tester.state<ScrollableState>(find
          .descendant(
            of: find.byKey(const ValueKey('drag-scroll-viewport')),
            matching: find.byType(Scrollable),
          )
          .first);
      final settledOffset = scrollState.position.pixels;
      await tester.pump(const Duration(seconds: 1));
      expect(scrollState.position.pixels, settledOffset);
      expect(tester.takeException(), isNull);
    });
  }

  for (final cancel in [false, true]) {
    testWidgets(
        'lower-panel part drop ${cancel ? 'cancels' : 'confirms'} alignment',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final definition = MissionSimulationDefinitions.byId('coc1_m2');
      final driver = EquipmentPracticeDriver(definition);
      driver.complete(definition.phases.first);
      final phase = definition.phases[1];
      final initialActions = driver.actions.length;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: SingleChildScrollView(
            child: ControlledPlacementInteraction(
          phase: phase,
          state: driver.state,
          onAction: (type, target, value) async =>
              driver.act(phase, type, target, value),
        )),
      )));
      final start = tester
          .getCenter(find.byKey(const ValueKey('placement-item-motherboard')));
      final end = tester.getCenter(
          find.byKey(const ValueKey('placement-destination-motherboard_area')));
      await tester.dragFrom(start, end - start);
      await tester.pumpAndSettle();
      expect(driver.actions.length, initialActions);
      expect(find.byKey(const ValueKey('workspace-orientation-aligned')),
          findsOneWidget);
      if (cancel) {
        Navigator.of(tester.element(find.byType(SimpleDialog))).pop();
        await tester.pumpAndSettle();
        expect(driver.actions.length, initialActions);
        expect(driver.state.placements.containsKey('motherboard'), false);
      } else {
        await tester
            .tap(find.byKey(const ValueKey('workspace-orientation-aligned')));
        await tester.pumpAndSettle();
        expect(driver.actions.length, initialActions + 1);
        expect(driver.actions.last.value['input_method'], 'drag');
        expect(driver.actions.last.value['orientation'], 'aligned');
        expect(driver.state.placements['motherboard'], 'motherboard_area');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('lower-panel peripheral cable drops save all endpoint pairs',
      (tester) async {
    final definition = MissionSimulationDefinitions.byId('coc1_m4');
    final driver = EquipmentPracticeDriver(definition);
    for (final phase in definition.phases.take(2)) {
      driver.complete(phase);
    }
    final phase = definition.phases[2];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: ConnectionInteraction(
        phase: phase,
        state: driver.state,
        onAction: (type, target, value) async =>
            driver.act(phase, type, target, value),
      ),
    )));
    for (final id in ['monitor', 'keyboard', 'mouse', 'network_adapter']) {
      final destination = practiceConnections[id]!;
      final start =
          tester.getCenter(find.byKey(ValueKey('connection-source-$id')));
      final end = tester.getCenter(
          find.byKey(ValueKey('connection-destination-$destination')));
      await tester.dragFrom(start, end - start);
      await tester.pumpAndSettle();
      expect(driver.state.connectedNodePairs, contains('$id>$destination'));
      expect(driver.actions.last.value['input_method'], 'drag');
    }
  });
}
