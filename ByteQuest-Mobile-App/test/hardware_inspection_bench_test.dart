import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/screens/simulation/components/equipment_workspace.dart';
import 'package:bytequest/screens/simulation/components/labs/hardware_inspection_bench.dart';
import 'package:bytequest/screens/simulation/components/physical/physical_surface.dart';
import 'package:bytequest/screens/simulation/components/simulation_scene.dart';
import 'package:bytequest/screens/simulation/interactions/tap_inspect_interaction.dart';
import 'package:bytequest/screens/simulation/runtime/mission_phase_completion_policy.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'support/equipment_practice_driver.dart';
import 'support/hardware_inspection_scenario.dart';

final definition = MissionSimulationDefinitions.byId('coc1_m1');
final phase = definition.phases.first;
Finder _key(String id) => find.byKey(ValueKey(id));
Future<void> _revealObject(WidgetTester tester, Finder item) async {
  await tester.scrollUntilVisible(item.hitTestable(), 70,
      scrollable: find.descendant(
          of: find.byType(BottomSheet), matching: find.byType(Scrollable)));
  await tester.pumpAndSettle();
  expect(item.hitTestable(), findsOneWidget);
}

class _Fixture {
  final driver = EquipmentPracticeDriver(definition);
  final inputs = <(String, String?, Map<String, dynamic>)>[];
  final camera = <(double, Offset)>[];

  Widget app(
          {bool enabled = true,
          bool saving = false,
          double textScale = 1,
          bool panel = false}) =>
      MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: Scaffold(body: StatefulBuilder(builder: (context, update) {
          Future<void> act(
              String type, String? target, Map<String, dynamic> value) async {
            inputs.add((type, target, value));
            update(() => driver.act(phase, type, target, value));
          }

          if (panel) {
            return SingleChildScrollView(
                child: TapInspectInteraction(
                    phase: phase, state: driver.state, onAction: act));
          }
          return EquipmentWorkspace(
              definition: definition,
              phase: phase,
              state: driver.state,
              onAction: act,
              enabled: enabled,
              saving: saving,
              onCameraChanged: (scale, offset) => camera.add((scale, offset)),
              hotspotStates: driver.state.hotspotStates);
        })),
      );
}

Offset _global(WidgetTester tester, Offset world) => tester
    .renderObject<RenderBox>(
        find.byKey(const Key('simulation-logical-workspace')))
    .localToGlobal(world);
Offset _photoPoint(WidgetTester t, String id, Offset pixel) =>
    _global(t, HardwareInspectionLayout.imagePoint(id, pixel));
Future<TestGesture> _probe(WidgetTester tester, Offset end,
    {PointerDeviceKind kind = PointerDeviceKind.touch}) async {
  final start = tester.getCenter(_key('inspection-probe'));
  final g = await tester.startGesture(start, kind: kind);
  await g.moveBy(const Offset(0, -30));
  await tester.pump();
  await g.moveTo(end);
  await tester.pump();
  return g;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'real mission reopens the inspection timeline and advances after seven targets',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await exerciseHardwareInspection(tester);
  });

  test(
      'only the current inspection phase and contract use the photographed equipment',
      () {
    final v = MissionSimulationDefinitions.contractVersion(definition.id);
    final practice = MissionRuntimeState.initial(definition.id);
    final assessment = MissionRuntimeState.initial(definition.id,
        mode: MissionRuntimeMode.assessment, assessmentAttemptId: 'fixture');
    expect(
        HardwareInspectionBench.supports(definition, phase, practice), isTrue);
    expect(
        HardwareInspectionBench.supports(
            definition, phase, assessment.copyWith(definitionVersion: v)),
        isTrue);
    expect(HardwareInspectionBench.supports(definition, phase, assessment),
        isFalse);
    for (final state in [assessment, practice]) {
      expect(
          HardwareInspectionBench.supports(definition, phase,
              state.copyWith(definitionVersion: 'a-different-contract')),
          isFalse);
    }
    for (final other in definition.phases.skip(1)) {
      expect(HardwareInspectionBench.supports(definition, other, practice),
          isFalse);
    }
    expect(HardwareInspectionLayout.bounds.keys.toSet(),
        definition.scene.objects.map((o) => o.id).toSet());
  });

  test(
      'camera geometry distinguishes nested features, unfeatured PCB and empty mat',
      () {
    PhysicalMount? at(double x, double y) => PhysicalMount.at(
        HardwareInspectionLayout.imagePoint('motherboard', Offset(x, y)),
        HardwareInspectionLayout.mounts);
    expect(at(257, 169)?.id, 'cpu_socket');
    expect(at(350, 135)?.id, 'dimm_slot');
    expect(at(417, 152)?.id, 'atx_power_port');
    expect(at(391, 153)?.id, 'motherboard');
    expect(at(265, 320)?.id, 'motherboard');
    expect(at(453, 322), isNull);
    expect(
        HardwareInspectionLayout.onPart('ram',
            HardwareInspectionLayout.imagePoint('ram', const Offset(62, 132))),
        isFalse);
    expect(
        HardwareInspectionLayout.onPart(
            'anti_static_strap',
            HardwareInspectionLayout.imagePoint(
                'anti_static_strap', const Offset(330, 161))),
        isFalse);
  });

  testWidgets(
      'moving the lens samples the exact photo point; only a real release inspects',
      (tester) async {
    final f = _Fixture();
    await tester.pumpWidget(f.app());
    await tester.pumpAndSettle();
    final socket = _photoPoint(tester, 'motherboard', const Offset(257, 169));
    final atx = _photoPoint(tester, 'motherboard', const Offset(417, 150));
    final drag = await _probe(tester, socket);
    final loupe = _key('inspection-loupe');
    expect(loupe, findsOneWidget);
    final enlarged = find.descendant(
        of: loupe, matching: _key('inspection-photo-motherboard'));
    Offset enlargedPixel(Offset pixel) {
      final rect = tester.getRect(enlarged);
      return rect.topLeft + pixel * (rect.width / 500);
    }

    expect(
        (enlargedPixel(const Offset(257, 169)) - tester.getCenter(loupe))
            .distance,
        lessThan(1));
    expect(f.inputs, isEmpty);
    await drag.moveTo(atx);
    await tester.pump();
    expect(
        (enlargedPixel(const Offset(417, 150)) - tester.getCenter(loupe))
            .distance,
        lessThan(1));
    expect(f.inputs, isEmpty);
    expect(
        find.text(MissionContentData.hardwareObservations['atx_power_port']!),
        findsNothing);
    await drag.up();
    await tester.pumpAndSettle();
    expect(loupe, findsNothing);
    expect(f.inputs.single.$1, 'object_inspected');
    expect(f.inputs.single.$2, 'atx_power_port');
    expect(f.inputs.single.$3, {'input_method': 'scene'});
    expect(_key('inspection-seen-atx_power_port'), findsOneWidget);
    expect(_key('inspection-seen-cpu_socket'), findsNothing);
    expect(
        find.text(MissionContentData.hardwareObservations['atx_power_port']!),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a miss, transparent corner, cancel or interrupted drag records nothing',
      (tester) async {
    final f = _Fixture();
    await tester.pumpWidget(f.app());
    await tester.pumpAndSettle();
    final blank = _global(tester, const Offset(1180, 675));
    final clearRamCorner = _photoPoint(tester, 'ram', const Offset(62, 132));
    for (final miss in [blank, clearRamCorner]) {
      await (await _probe(tester, miss)).up();
      await tester.pumpAndSettle();
      expect(find.text(MissionContentData.inspectionLensMiss), findsOneWidget);
      await tester.tapAt(miss);
      await tester.pumpAndSettle();
    }
    final socket = _photoPoint(tester, 'motherboard', const Offset(259, 166));
    await (await _probe(tester, socket)).cancel();
    await tester.pumpAndSettle();
    final disabledDuringDrag = await _probe(tester, socket);
    await tester.pumpWidget(f.app(saving: true));
    await disabledDuringDrag.up();
    await tester.pumpAndSettle();
    await tester.tapAt(socket);
    expect(f.inputs, isEmpty);
    expect(f.driver.state.placements, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'zoom, pan, fit and reopening never inspect a different part or replay input',
      (tester) async {
    final f = _Fixture();
    await tester.pumpWidget(f.app());
    await tester.pumpAndSettle();
    await tester.tap(_key('simulation-zoom-in'));
    await tester.pumpAndSettle();
    expect(f.camera.last.$1, greaterThan(1));
    final before = f.camera.length;
    await tester.dragFrom(
        _photoPoint(tester, 'motherboard', const Offset(260, 278)),
        const Offset(-36, -25));
    await tester.pumpAndSettle();
    expect(f.camera.length, greaterThan(before));
    expect(f.inputs, isEmpty);
    await (await _probe(
            tester, _photoPoint(tester, 'motherboard', const Offset(345, 143)),
            kind: PointerDeviceKind.mouse))
        .up();
    await tester.pumpAndSettle();
    expect(f.inputs.single.$2, 'dimm_slot');
    await tester.tap(_key('simulation-fit-view'));
    await tester.pumpAndSettle();
    expect(f.camera.last, (1.0, Offset.zero));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(f.app());
    await tester.pumpAndSettle();
    expect(f.inputs, hasLength(1));
    expect(_key('inspection-seen-dimm_slot'), findsOneWidget);
    expect(_key('inspection-seen-motherboard'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'photo, native picker, and task panel keep their original evidence and seven-target gate',
      (tester) async {
    final f = _Fixture();
    await tester.pumpWidget(f.app());
    await tester.pumpAndSettle();
    await tester.tap(_key('simulation-objects-button'));
    await tester.pumpAndSettle();
    expect(f.inputs, isEmpty);
    final strap = _key('object-list-anti_static_strap');
    await _revealObject(tester, strap);
    expect(tester.getSize(strap).height, greaterThanOrEqualTo(48));
    await tester.tap(strap);
    await tester.pumpAndSettle();
    expect(f.inputs.single.$2, 'anti_static_strap');
    for (final id in [
      'motherboard',
      'cpu',
      'ram',
      'psu',
      'cpu_socket',
      'dimm_slot'
    ]) {
      await tester.tap(_key('simulation-object-$id'));
      await tester.pumpAndSettle();
      expect(f.inputs.last.$2, id);
      expect(f.inputs.last.$3, {'input_method': 'scene'});
    }
    expect(MissionPhaseCompletionPolicy.canAdvance(phase, f.driver.state),
        isFalse);
    await tester.pumpWidget(f.app(panel: true));
    final target = _key('inspect-target-atx_power_port');
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(f.inputs.last.$2, 'atx_power_port');
    expect(f.inputs.last.$3, {'input_method': 'tap'});
    expect(f.inputs.map((v) => v.$1).toSet(), {'object_inspected'});
    expect(f.driver.state.placements, isEmpty);
    expect(
        MissionPhaseCompletionPolicy.canAdvance(phase, f.driver.state), isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 568), const Size(740, 320)]) {
    testWidgets(
        'equipment stays fitted and alternatives remain accessible at $size with 2x text',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = _Fixture();
      f.driver.state = MissionRuntimeState.initial(definition.id,
          mode: MissionRuntimeMode.assessment,
          assessmentAttemptId: 'fixture',
          definitionVersion:
              MissionSimulationDefinitions.contractVersion(definition.id));
      await tester.pumpWidget(f.app(textScale: 2));
      await tester.pumpAndSettle();
      final viewport = tester.getRect(_key('simulation-workspace-scroll'));
      final world =
          tester.getRect(find.byKey(const Key('simulation-logical-workspace')));
      expect(viewport.inflate(1).contains(world.topLeft), isTrue);
      expect(viewport.inflate(1).contains(world.bottomRight), isTrue);
      expect(tester.getSize(_key('inspection-probe')).shortestSide,
          greaterThanOrEqualTo(48));
      expect(find.byTooltip(MissionContentData.inspectionLensLabel),
          findsOneWidget);
      final scene =
          tester.widget<SimulationScene>(find.byType(SimulationScene));
      expect(scene.highlightObjectId, isNull);
      expect(find.text(MissionContentData.hardwareObservations['ram']!),
          findsNothing);
      await tester.tap(_key('simulation-objects-button'));
      await tester.pumpAndSettle();
      final ram = _key('object-list-ram');
      await _revealObject(tester, ram);
      expect(tester.getSemantics(ram).label, contains('Memory module'));
      expect(tester.getSize(ram).height, greaterThanOrEqualTo(48));
      await tester.tap(ram);
      await tester.pumpAndSettle();
      await tester.tap(_key('inspection-readout'));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byType(AlertDialog),
              matching:
                  find.text(MissionContentData.hardwareObservations['ram']!)),
          findsOneWidget);
      expect(
          find.textContaining('Isolate power before reseating'), findsNothing);
      expect(f.inputs, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }
}
