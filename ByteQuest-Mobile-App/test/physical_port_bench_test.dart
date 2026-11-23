import 'dart:convert';

import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/screens/simulation/components/equipment_workspace.dart';
import 'package:bytequest/screens/simulation/components/physical/port_bench_painter.dart';
import 'package:bytequest/screens/simulation/components/physical/port_connection_bench.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/equipment_practice_driver.dart';

Finder _key(String key) => find.byKey(ValueKey(key));
Finder _source(String id) => _key('workspace-source-$id');
Finder _socket(String bank, int index) =>
    _key('simulation-object-$bank:$index');

class _Rig {
  _Rig(String mission, int n, {bool assessment = false})
      : driver = EquipmentPracticeDriver(
            MissionSimulationDefinitions.byId(mission)) {
    phase = driver.definition.phases[n - 1];
    for (final previous in driver.definition.phases.take(n - 1)) {
      driver.complete(previous);
    }
    driver.state = driver.state.copyWith(currentPhaseId: phase.id);
    if (assessment) {
      driver.state = driver.state.copyWith(
          mode: MissionRuntimeMode.assessment, assessmentAttemptId: 'test');
    }
    driver.actions.clear();
  }
  final EquipmentPracticeDriver driver;
  late final MissionPhaseDefinition phase;
  final raw = <Map<String, dynamic>>[];
  Widget app(
          {bool enabled = true,
          bool saving = false,
          bool reducedMotion = false,
          double scale = 1}) =>
      MaterialApp(
          home: Scaffold(
              body: StatefulBuilder(
                  builder: (context, refresh) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(scale),
                          disableAnimations: reducedMotion),
                      child: EquipmentWorkspace(
                        definition: driver.definition,
                        phase: phase,
                        state: driver.state,
                        hotspotStates: driver.state.hotspotStates,
                        enabled: enabled,
                        saving: saving,
                        onCameraChanged: (_, __) {},
                        onDraftChanged: (draft) => driver.state =
                            driver.state.copyWith(workbenchDraft: draft),
                        onAction: (type, target, value) async {
                          raw.add(value);
                          driver.act(phase, type, target, value);
                          refresh(() {});
                        },
                      )))));
}

void _phone(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> _drag(WidgetTester t, Finder source, Offset end,
    {PointerDeviceKind kind = PointerDeviceKind.touch}) async {
  final g = await t.startGesture(t.getCenter(source), kind: kind);
  await g.moveBy(const Offset(16, -6));
  await t.pump();
  await g.moveTo(end);
  await t.pump();
  await g.up();
  await t.pumpAndSettle();
}

PortCablePainter _painter(WidgetTester t, String key) =>
    t.widget<CustomPaint>(_key(key)).painter! as PortCablePainter;

void main() {
  testWidgets(
      'HDMI lead continuously follows the finger; a release away from any jack creates no attempt',
      (t) async {
    _phone(t, const Size(360, 720));
    final rig = _Rig('coc1_m4', 3);
    await t.pumpWidget(rig.app());
    await t.pumpAndSettle();
    final source = _source('monitor');
    final bench = t.getRect(_key('physical-port-surface'));
    final g = await t.startGesture(t.getCenter(source));
    await g.moveBy(const Offset(22, 2));
    await t.pump();
    for (final f in [.35, .48, .52]) {
      final pointer =
          Offset(bench.left + bench.width * f, bench.top + bench.height * .49);
      await g.moveTo(pointer);
      await t.pump();
      final live = _painter(t, 'physical-port-live-lead').leads['monitor']!;
      expect(live.tip.dx, closeTo(f * 360, .02));
      expect(live.tip.dy, closeTo(.49 * 216, .02));
      expect(rig.raw, isEmpty);
    }
    await g.up();
    await t.pumpAndSettle();
    expect(rig.raw, isEmpty);
    expect(rig.driver.state.connectedNodePairs, isEmpty);
    expect(find.text(MissionContentData.portBenchMiss), findsOneWidget);
  });
  for (final assessment in [false, true]) {
    testWidgets(
        'mouse HDMI-to-USB is refused without a latched cable; valid drag seats HDMI (assessment=$assessment)',
        (t) async {
      _phone(t, const Size(412, 915));
      final rig = _Rig('coc1_m4', 3, assessment: assessment);
      await t.pumpWidget(rig.app());
      await t.pumpAndSettle();
      await _drag(t, _source('monitor'), t.getCenter(_socket('usb_port', 0)),
          kind: PointerDeviceKind.mouse);
      expect(rig.raw.single, {
        'source_id': 'monitor',
        'destination_id': 'usb_port',
        'input_method': 'drag'
      });
      final action = rig.driver.actions.single;
      expect(action.actionType, 'connection_created');
      expect(action.target, 'usb_port');
      expect(action.value['simulation_valid'], false);
      expect(
          action.value['simulation_feedback'],
          assessment
              ? MissionContentData.assessmentNeutralConnection
              : MissionContentData.incompatibleConnectionFeedback);
      expect(
          _painter(t, 'physical-port-cables').leads['monitor']!.seated, false);
      expect(
          rig.driver.state.workbenchDraft.containsKey('port_jacks'), isFalse);
      final to = t.getCenter(_socket('hdmi_port', 0));
      await _drag(t, _source('monitor'), to, kind: PointerDeviceKind.mouse);
      expect(
          rig.driver.state.connectedNodePairs, contains('monitor>hdmi_port'));
      expect(_painter(t, 'physical-port-cables').leads['monitor']!.tip,
          const Offset(283, 49));
      await _drag(t, _source('monitor'), to);
      expect(rig.raw, hasLength(2));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'equivalent USB sockets have distinct persisted locations, not extra grades',
      (t) async {
    _phone(t, const Size(360, 700));
    final rig = _Rig('coc1_m4', 3);
    await t.pumpWidget(rig.app());
    await t.pumpAndSettle();
    await _tap(t, _source('mouse'));
    await _tap(t, _socket('usb_port', 1));
    expect(rig.raw.single, {
      'source_id': 'mouse',
      'destination_id': 'usb_port',
      'input_method': 'tap'
    });
    expect(_painter(t, 'physical-port-cables').leads['mouse']!.tip,
        const Offset(306, 106));
    await _drag(t, _socket('usb_port', 1), t.getCenter(_socket('usb_port', 0)));
    expect(rig.raw, hasLength(1));
    expect(_painter(t, 'physical-port-cables').leads['mouse']!.tip,
        const Offset(259, 106));
    await _tap(t, _source('keyboard'));
    await _tap(t, _socket('usb_port', 0));
    expect(rig.raw, hasLength(1));
    expect(find.text(MissionContentData.portBenchOccupied), findsOneWidget);
    await _tap(t, _socket('usb_port', 1));
    expect(rig.raw, hasLength(2));
    final saved = jsonDecode(jsonEncode(rig.driver.state.toJson()))
        as Map<String, dynamic>;
    await t.pumpWidget(const SizedBox());
    rig.driver.state = MissionRuntimeState.fromJson(saved);
    await t.pumpWidget(rig.app());
    await t.pumpAndSettle();
    expect(_painter(t, 'physical-port-cables').leads['keyboard']!.tip,
        const Offset(306, 106));
    expect(_painter(t, 'physical-port-cables').leads['mouse']!.tip,
        const Offset(259, 106));
    expect(rig.raw, hasLength(2));
    await t.pumpWidget(const SizedBox());
    rig.driver.state = rig.driver.state.copyWith(connectedNodePairs: const {});
    await t.pumpWidget(rig.app());
    await t.pumpAndSettle();
    expect(
        _painter(t, 'physical-port-cables').leads.values.where((l) => l.seated),
        isEmpty,
        reason: 'stale socket preferences are not evidence');
  });
  testWidgets(
      'restored logical pairs get distinct free jacks even with no or damaged socket preferences',
      (t) async {
    _phone(t, const Size(360, 640));
    final rig = _Rig('coc1_m4', 3);
    final snapshot = rig.driver.state.copyWith(
        connectedNodePairs: {'mouse>usb_port', 'keyboard>usb_port'}).toJson()
      ..remove('workbenchDraft');
    for (final draft in <Map<String, dynamic>?>[
      null,
      {'keyboard>usb_port': 90, 'mouse>usb_port': '0', 'monitor>hdmi_port': 0},
      {'keyboard>usb_port': 1, 'mouse>usb_port': 1},
    ]) {
      rig.driver.state = MissionRuntimeState.fromJson({
        ...snapshot,
        if (draft != null) 'workbenchDraft': {'port_jacks': draft}
      });
      await t.pumpWidget(rig.app());
      await t.pumpAndSettle();
      final leads = _painter(t, 'physical-port-cables').leads;
      expect({leads['keyboard']!.tip, leads['mouse']!.tip},
          {const Offset(259, 106), const Offset(306, 106)});
      expect(leads['monitor']!.seated, false);
      expect(rig.raw, isEmpty);
      await t.pumpWidget(const SizedBox.shrink());
    }
  });
  testWidgets(
      'disabled and in-flight benches do not accept picked-up or tapped plugs',
      (t) async {
    _phone(t, const Size(320, 568));
    final rig = _Rig('coc2_m1', 4);
    for (final (enabled, saving) in [(false, false), (true, true)]) {
      await t.pumpWidget(rig.app(enabled: enabled, saving: saving));
      await t.pumpAndSettle();
      await _drag(t, _source('copper_cable'),
          t.getCenter(_socket('lan_cable_tester', 0)));
      await _tap(t, _source('copper_cable'));
      await _tap(t, _socket('lan_cable_tester', 0));
      expect(rig.raw, isEmpty);
      expect(rig.driver.state.workbenchDraft, isEmpty);
    }
  });
  for (final size in const [Size(320, 568), Size(760, 360)]) {
    testWidgets(
        'a physically possible wrong topology survives until rewired on $size',
        (t) async {
      _phone(t, size);
      final rig = _Rig('coc2_m3', 2);
      await t.pumpWidget(rig.app(scale: 1.5, reducedMotion: true));
      await t.pumpAndSettle();
      Future<void> tapConnect(String source, String bank, int index) async {
        await _tap(t, _source(source));
        await _tap(t, _socket(bank, index));
      }

      await tapConnect('router', 'server', 1);
      expect(rig.driver.state.connectedNodePairs, contains('router>server'));
      expect(rig.driver.actions.single.value['simulation_valid'], true);
      await _drag(t, _socket('server', 1), t.getCenter(_socket('switch', 2)));
      expect(rig.driver.actions.last.value['input_method'], 'drag');
      expect(rig.driver.state.connectedNodePairs,
          isNot(contains('router>server')));
      await tapConnect('workstation_a', 'switch', 1);
      await tapConnect('workstation_b', 'switch', 0);
      await tapConnect('switch', 'server', 3);
      expect(rig.raw, hasLength(5));
      expect(rig.driver.state.connectedNodePairs, {
        'router>switch',
        'workstation_a>switch',
        'workstation_b>switch',
        'switch>server'
      });
      expect(
          _painter(t, 'physical-port-cables')
              .leads
              .values
              .where((l) => l.seated),
          hasLength(4));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'tester connection remains available through full-size accessible object list',
      (t) async {
    _phone(t, const Size(320, 568));
    final rig = _Rig('coc2_m1', 4);
    await t.pumpWidget(rig.app(scale: 1.8));
    await t.pumpAndSettle();
    Future<void> choose(String id) async {
      await _tap(t, _key('simulation-objects-button'));
      final row = _key('object-list-$id');
      expect(t.getSize(row).height, greaterThanOrEqualTo(48));
      final node = t.getSemantics(row);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await t.pumpAndSettle();
    }

    await choose('copper_cable');
    await choose('lan_cable_tester:0');
    expect(
        rig.driver.state.connectedNodePairs, {'copper_cable>lan_cable_tester'});
    expect(rig.raw.single, {
      'source_id': 'copper_cable',
      'destination_id': 'lan_cable_tester',
      'input_method': 'tap'
    });
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'zoomed switch can originate and receive links, but a self-loop is recorded and refused',
      (t) async {
    _phone(t, const Size(460, 850));
    final rig = _Rig('coc2_m2', 3);
    await t.pumpWidget(rig.app());
    await t.pumpAndSettle();
    final viewer = t.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    viewer.transformationController!.value =
        Matrix4.diagonal3Values(1.18, 1.18, 1)..setTranslationRaw(-27, -18, 0);
    await t.pump();
    await _drag(t, _source('switch'), t.getCenter(_socket('switch', 0)));
    expect(rig.driver.actions.single.value['simulation_valid'], false);
    await _drag(t, _source('workstation'), t.getCenter(_socket('switch', 0)));
    await _drag(t, _source('switch'), t.getCenter(_socket('router', 1)));
    expect(rig.driver.state.connectedNodePairs,
        {'workstation>switch', 'switch>router'});
    await _tap(t, _key('workspace-mode-inspect'));
    expect(find.byType(PortConnectionBench), findsNothing);
    await _tap(t, _key('workspace-mode-connect'));
    expect(
        _painter(t, 'physical-port-cables').leads.values.where((l) => l.seated),
        hasLength(2));
    expect(rig.raw, hasLength(3));
  });
}
