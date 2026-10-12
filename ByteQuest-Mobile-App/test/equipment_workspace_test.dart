import 'dart:convert';

import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/screens/simulation/components/equipment_workspace.dart';
import 'package:bytequest/screens/simulation/components/hotspot_widget.dart';
import 'package:bytequest/screens/simulation/components/scene_connection_painter.dart';
import 'package:bytequest/screens/simulation/runtime/mission_equipment_simulator.dart';
import 'package:bytequest/screens/simulation/runtime/mission_phase_completion_policy.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/equipment_practice_driver.dart';

void main() {
  testWidgets('canvas drag scrolls to an offscreen destination',
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
    await tester.pumpWidget(_host(driver, phase, height: 220));
    final source = find.byKey(const ValueKey('workspace-source-motherboard'));
    final target = find.byKey(const ValueKey('workspace-destination-psu_bay'));
    await tester.ensureVisible(source);
    await tester.pumpAndSettle();
    final viewport = tester
        .getRect(find.byKey(const ValueKey('simulation-workspace-scroll')));
    expect(tester.getCenter(target).dy, greaterThan(viewport.bottom));
    final gesture = await tester.startGesture(tester.getCenter(source));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveTo(Offset(viewport.center.dx, viewport.bottom - 2));
    for (var i = 0;
        i < 8 && tester.getCenter(target).dy > viewport.bottom - 12;
        i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(tester.getCenter(target).dy, lessThan(viewport.bottom));
    await gesture.moveTo(tester.getCenter(target));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('workspace-orientation-aligned')));
    await tester.pumpAndSettle();
    expect(driver.actions.length - initialActions, 1);
    expect(driver.actions.last.value['destination_id'], 'psu_bay');
    expect(driver.actions.last.value['input_method'], 'drag');
    expect(driver.state.placements.containsKey('motherboard'), false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an installed part image renders only at its destination',
      (tester) async {
    final definition = MissionSimulationDefinitions.byId('coc1_m2');
    final driver = EquipmentPracticeDriver(definition);
    driver.complete(definition.phases.first);
    final phase = definition.phases[1];
    await tester.pumpWidget(_host(driver, phase));
    await _drag(tester, 'motherboard', 'motherboard_area');
    await tester
        .tap(find.byKey(const ValueKey('workspace-orientation-aligned')));
    await tester.pumpAndSettle();
    final source = tester.widget<HotspotWidget>(find.descendant(
        of: find.byKey(const ValueKey('workspace-source-motherboard')),
        matching: find.byType(HotspotWidget)));
    expect(source.object.metadata['imageAsset'], isNull);
    expect(source.state, HotspotVisualState.completed);
    expect(
        find.byKey(const ValueKey('hotspot-image-motherboard')), findsNothing);
    expect(
        find.byKey(
            const ValueKey('hotspot-image-destination:motherboard_area')),
        findsOneWidget);
    expect(driver.state.placements['motherboard'], 'motherboard_area');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a drag while saving cannot move the equipment out of reach',
      (tester) async {
    final driver =
        EquipmentPracticeDriver(MissionSimulationDefinitions.byId('coc1_m2'));
    await tester.pumpWidget(
        _host(driver, driver.definition.phases.first, enabled: false));
    final panel = MissionEquipmentSimulator.map(
        driver.definition.phases.first.presentation['equipment']['placement']);
    final source =
        MissionEquipmentSimulator.maps(panel['items']).first['id'] as String;
    await _drag(tester, source, '${source}_position');
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer.transformationController!.value, Matrix4.identity());
    expect(driver.actions, isEmpty);
  });

  testWidgets('all six assembly parts can be dragged in a phone-sized canvas',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final driver =
        EquipmentPracticeDriver(MissionSimulationDefinitions.byId('coc1_m2'));
    driver.complete(driver.definition.phases.first);
    final phase = driver.definition.phases[1];
    final initialActions = driver.actions.length;
    await tester.pumpWidget(_host(driver, phase, height: 330));
    for (final part in practicePlacements.entries.take(6)) {
      await _drag(tester, part.key, part.value);
      await tester
          .tap(find.byKey(const ValueKey('workspace-orientation-aligned')));
      await tester.pumpAndSettle();
      expect(driver.state.placements[part.key], part.value);
    }
    expect(driver.actions.length - initialActions, 6);
    expect(tester.takeException(), isNull);
  });

  for (final mission in ['coc1_m2', 'coc1_m4']) {
    testWidgets('$mission connects every cable in a phone-sized canvas',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final driver =
          EquipmentPracticeDriver(MissionSimulationDefinitions.byId(mission));
      for (final phase in driver.definition.phases.take(2)) {
        driver.complete(phase);
      }
      final phase = driver.definition.phases[2];
      await tester.pumpWidget(_host(driver, phase, height: 330));
      final panel = phase.resolvedInteraction == InteractionFamily.connect
          ? phase.presentation
          : MissionEquipmentSimulator.map(
              phase.presentation['equipment']['connection']);
      for (final source in MissionEquipmentSimulator.maps(panel['sources'])) {
        final id = source['id'] as String;
        final destination = practiceConnections[id]!;
        await _drag(tester, id, destination);
        expect(driver.state.connectedNodePairs, contains('$id>$destination'));
        expect(driver.actions.last.value['input_method'], 'drag');
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final definition
      in MissionSimulationDefinitions.all.where((d) => d.cocId != 'coc4')) {
    testWidgets(
        '${definition.id} records a real placement from the main canvas',
        (tester) async {
      final driver = EquipmentPracticeDriver(definition);
      final phase = definition.phases.first;
      final panel = MissionEquipmentSimulator.map(
          phase.presentation['equipment']['placement']);
      final source =
          MissionEquipmentSimulator.maps(panel['items']).first['id'] as String;
      final destination = '${source}_position';
      await tester.pumpWidget(_host(driver, phase));
      await tester.pumpAndSettle();
      expect(
          MissionPhaseCompletionPolicy.canAdvance(phase, driver.state), false);
      await _drag(tester, source, destination);
      expect(driver.actions.single.actionType, 'placement_attempted');
      expect(driver.actions.single.value['input_method'], 'drag');
      expect(driver.state.placements[source], destination);
      expect(find.byKey(ValueKey('workspace-destination-$destination')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'incompatible drops are recorded without installing and accepted placements restore',
      (tester) async {
    final definition = MissionSimulationDefinitions.byId('coc1_m1');
    final driver = EquipmentPracticeDriver(definition);
    final phase = definition.phases.first;
    await tester.pumpWidget(_host(driver, phase));
    await _drag(tester, 'motherboard', 'cpu_position');
    expect(driver.actions.single.value['simulation_valid'], false);
    expect(driver.state.placements, isEmpty);
    await _drag(tester, 'motherboard', 'motherboard_position');
    expect(driver.state.placements['motherboard'], 'motherboard_position');
    driver.state = MissionRuntimeState.fromJson(
        jsonDecode(jsonEncode(driver.state.toJson())) as Map<String, dynamic>);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_host(driver, phase));
    await tester.pumpAndSettle();
    final installed = tester.widget<HotspotWidget>(find.descendant(
        of: find.byKey(
            const ValueKey('workspace-destination-motherboard_position')),
        matching: find.byType(HotspotWidget)));
    expect(installed.object.label, contains('Motherboard'));
    expect(installed.state, HotspotVisualState.completed);
    expect(driver.actions.length, 2);
  });

  testWidgets('tap placement reaches the same durable state as dragging',
      (tester) async {
    final definition = MissionSimulationDefinitions.byId('coc3_m2');
    final driver = EquipmentPracticeDriver(definition);
    await tester.pumpWidget(_host(driver, definition.phases.first));
    await tester
        .tap(find.byKey(const ValueKey('workspace-source-server_node')));
    await tester.pumpAndSettle();
    await tester.tap(find
        .byKey(const ValueKey('workspace-destination-server_node_position')));
    await tester.pumpAndSettle();
    expect(driver.state.placements['server_node'], 'server_node_position');
    expect(driver.actions.single.value['input_method'], 'tap');
  });

  testWidgets('assembly requires an explicit orientation after a canvas drop',
      (tester) async {
    final definition = MissionSimulationDefinitions.byId('coc1_m2');
    final driver = EquipmentPracticeDriver(definition);
    await tester.pumpWidget(_host(driver, definition.phases[1]));
    await _drag(tester, 'motherboard', 'motherboard_area');
    expect(driver.actions, isEmpty);
    expect(find.byKey(const ValueKey('workspace-orientation-aligned')),
        findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('workspace-orientation-aligned')));
    await tester.pumpAndSettle();
    expect(driver.state.placements['motherboard'], 'motherboard_area');
    expect(driver.actions.single.value['orientation'], 'aligned');
  });

  testWidgets(
      'canvas cable gesture saves an endpoint pair and draws the connection',
      (tester) async {
    final definition = MissionSimulationDefinitions.byId('coc3_m1');
    final driver = EquipmentPracticeDriver(definition);
    await tester.pumpWidget(_host(driver, definition.phases.first));
    await tester.tap(find.byKey(const ValueKey('workspace-mode-connect')));
    await tester.pumpAndSettle();
    await _drag(tester, 'server_node', 'server_switch');
    expect(
        driver.state.connectedNodePairs, contains('server_node>server_switch'));
    final painter = tester
        .widget<CustomPaint>(find.byKey(const Key('scene-connections')))
        .painter as SceneConnectionPainter;
    expect(painter.connections, hasLength(1));
    expect(driver.actions.single.value['input_method'], 'drag');
  });

  testWidgets(
      'a switch can be both a source and destination without collisions',
      (tester) async {
    final definition = MissionSimulationDefinitions.byId('coc2_m2');
    final driver = EquipmentPracticeDriver(definition);
    await tester.pumpWidget(_host(driver, definition.phases[2]));
    await _drag(tester, 'workstation', 'switch');
    await _drag(tester, 'switch', 'router');
    expect(driver.state.connectedNodePairs,
        containsAll(['workstation>switch', 'switch>router']));
    final painter = tester
        .widget<CustomPaint>(find.byKey(const Key('scene-connections')))
        .painter as SceneConnectionPainter;
    expect(painter.connections, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(320, 568), Size(640, 360)]) {
    testWidgets(
        'all workspace exercises fit $size with large text and reduced motion',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final definition in MissionSimulationDefinitions.all) {
        final driver = EquipmentPracticeDriver(definition);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester
            .pumpWidget(_host(driver, definition.phases.first, textScale: 2));
        await tester.pumpAndSettle();
        if (definition.cocId == 'coc4') {
          expect(find.byType(Draggable<String>), findsNothing);
          expect(find.byType(DragTarget<String>), findsNothing);
        }
        expect(tester.takeException(), isNull, reason: definition.id);
      }
    });
  }

  test('all COC1–COC3 work orders require placement evidence before review',
      () {
    for (final definition
        in MissionSimulationDefinitions.all.where((d) => d.cocId != 'coc4')) {
      final driver = EquipmentPracticeDriver(definition);
      for (final phase in definition.phases) {
        driver.complete(phase);
      }
      expect(MissionEquipmentSimulator.readyForReview(definition, driver.state),
          true);
      driver.state = driver.state.copyWith(placements: const {});
      expect(MissionEquipmentSimulator.readyForReview(definition, driver.state),
          false,
          reason: definition.id);
    }
  });
}

Future<void> _drag(
    WidgetTester tester, String source, String destination) async {
  await tester.ensureVisible(find.byKey(ValueKey('workspace-source-$source')));
  await tester.ensureVisible(
      find.byKey(ValueKey('workspace-destination-$destination')));
  await tester.pumpAndSettle();
  final start =
      tester.getCenter(find.byKey(ValueKey('workspace-source-$source')));
  final end = tester
      .getCenter(find.byKey(ValueKey('workspace-destination-$destination')));
  await tester.dragFrom(start, end - start);
  await tester.pumpAndSettle();
}

Widget _host(EquipmentPracticeDriver driver, MissionPhaseDefinition phase,
        {double textScale = 1, bool enabled = true, double? height}) =>
    MaterialApp(
      home: Scaffold(
          body: StatefulBuilder(
              builder: (context, refresh) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(textScale),
                        disableAnimations: true),
                    child: SizedBox(
                      height: height,
                      child: EquipmentWorkspace(
                        definition: driver.definition,
                        phase: phase,
                        state: driver.state,
                        hotspotStates: driver.state.hotspotStates,
                        enabled: enabled,
                        saving: !enabled,
                        onCameraChanged: (_, __) {},
                        onAction: (type, target, value) async {
                          driver.act(phase, type, target, value);
                          refresh(() {});
                        },
                      ),
                    ),
                  ))),
    );
