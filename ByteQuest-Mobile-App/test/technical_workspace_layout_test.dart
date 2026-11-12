import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/models/mission_model.dart';
import 'package:bytequest/screens/simulation/components/hotspot_widget.dart';
import 'package:bytequest/screens/simulation/components/simulation_scene.dart';
import 'package:bytequest/screens/simulation/mission_simulation_screen.dart';
import 'package:bytequest/screens/simulation/runtime/mission_evidence_gateway.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_controller.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:bytequest/services/practice_coc_session_service.dart';
import 'package:bytequest/services/progress_resume_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/equipment_practice_driver.dart';

const _capture = String.fromEnvironment('WORKSPACE_CAPTURE');
const _fontDirectory = String.fromEnvironment('WORKSPACE_FONT_DIR');

void main() {
  setUpAll(() async {
    // Real glyphs for the optional local visual captures; normal CI uses its
    // deterministic test font and never depends on a system font.
    if (_capture.isNotEmpty && _fontDirectory.isNotEmpty) {
      for (final family in ['Ahem', AppTheme.fontFamily, 'Roboto']) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(
              await File('$_fontDirectory/roboto-regular.ttf').readAsBytes())));
        await loader.load();
      }
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(
                await File('$_fontDirectory/materialicons-regular.otf')
                    .readAsBytes()))))
          .load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'bq_mission_tutorial_seen_workspace-qa': true});
    for (final coc in ['coc1', 'coc2', 'coc3', 'coc4']) {
      await const PracticeCocSessionService().start('workspace-qa', coc);
    }
  });
  for (final size in const [
    Size(320, 568),
    Size(360, 800),
    Size(412, 915),
    Size(568, 320),
    Size(640, 360)
  ]) {
    testWidgets('all 20 workspaces fit safe phone bounds $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final measurements = <Map<String, Object>>[];
      for (final definition in MissionSimulationDefinitions.all) {
        SharedPreferences.setMockInitialValues(
            {'bq_mission_tutorial_seen_workspace-qa': true});
        await const PracticeCocSessionService()
            .start('workspace-qa', definition.cocId);
        await tester.pumpWidget(_host(definition));
        await tester.pumpAndSettle();
        final exception = tester.takeException();
        if (_capture.startsWith('before')) {
          if (exception != null) {
            debugPrint('BASELINE_LAYOUT_ERROR ${definition.id}: $exception');
          }
        } else {
          expect(exception, isNull, reason: definition.id);
        }
        final scene = tester.getRect(find.byType(SimulationScene));
        final canvas = tester
            .getRect(find.byKey(const ValueKey('simulation-workspace-scroll')));
        final next = tester.getRect(find.byKey(const ValueKey('mission-next')));
        expect(next.bottom, lessThanOrEqualTo(size.height - 24));
        expect(
            canvas.width,
            greaterThanOrEqualTo(
                size.width < 520 ? size.width - 2 : size.width * .5));
        if (!_capture.startsWith('before')) {
          expect(canvas.height, greaterThanOrEqualTo(112),
              reason: definition.id);
        }
        for (final object in find.byType(HotspotWidget).evaluate()) {
          final rect = tester.getRect(find.byWidget(object.widget));
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
        }
        measurements.add({
          'mission': definition.id,
          'scene': [scene.width, scene.height],
          'canvas': [canvas.width, canvas.height]
        });
        if (_capture.isNotEmpty &&
            (size == const Size(360, 800) || definition.id.endsWith('_m1'))) {
          await _captureScreen(
              tester,
              size == const Size(360, 800)
                  ? definition.id
                  : '${definition.id}-${size.width.toInt()}x${size.height.toInt()}');
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
      debugPrint(
          'WORKSPACE_MEASUREMENTS ${size.width}x${size.height} ${jsonEncode(measurements)}');
      if (_capture.isNotEmpty) {
        await tester.runAsync(() async {
          final file = File(
              'build/workspace-qa/$_capture/${size.width.toInt()}x${size.height.toInt()}.json');
          await file.parent.create(recursive: true);
          await file.writeAsString(
              const JsonEncoder.withIndent('  ').convert(measurements));
        });
      }
    });
  }

  for (final size in const [Size(320, 568), Size(568, 320), Size(640, 360)]) {
    testWidgets('all 20 timed workspaces support 2x text and a cutout $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final definition in MissionSimulationDefinitions.all) {
        await tester.pumpWidget(_host(definition,
            textScale: 2, padding: const EdgeInsets.fromLTRB(24, 32, 0, 24)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: definition.id);
        final next = tester.getRect(find.byKey(const ValueKey('mission-next')));
        expect(next.bottom, lessThanOrEqualTo(size.height - 24));
        expect(next.left, greaterThanOrEqualTo(24));
        expect(next.height, greaterThanOrEqualTo(48));
        if (_capture.isNotEmpty && definition.id.endsWith('_m1')) {
          await _captureScreen(tester,
              '${definition.id}-${size.width.toInt()}x${size.height.toInt()}-text2');
        }
        final guideToggle =
            find.byKey(const ValueKey('mission-guidance-toggle'));
        // In a short landscape sidebar the header and guide share the task
        // scroll area, so bring the guide into view as a learner would.
        await tester.ensureVisible(guideToggle);
        await tester.pumpAndSettle();
        expect(guideToggle.hitTestable(), findsOneWidget);
        await tester.tap(guideToggle);
        await tester.pumpAndSettle();
        expect(find.text(definition.scenario), findsOneWidget);
        final close = find.byKey(const ValueKey('mission-guide-close'));
        expect(tester.getRect(close).top, greaterThanOrEqualTo(32));
        await tester.drag(find.byKey(const ValueKey('mission-guide-scroll')),
            const Offset(0, -300));
        await tester.pumpAndSettle();
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: definition.id);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  testWidgets(
      'expanding controls and reading the guide retain a draft and camera',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final definition = MissionSimulationDefinitions.byId('coc2_m4');
    final initial = MissionRuntimeState.initial(definition.id)
        .copyWith(currentPhaseId: definition.phases[1].id);
    await tester.pumpWidget(_host(definition, initialState: initial));
    await tester.pumpAndSettle();
    final fixture = tester
        .widget<MissionSimulationScreen>(find.byType(MissionSimulationScreen));
    final originalCanvasHeight =
        tester.getSize(find.byType(SimulationScene)).height;
    final toggle = find.byKey(const ValueKey('mission-controls-toggle'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(SimulationScene)).height,
        lessThan(originalCanvasHeight));
    final field =
        find.byKey(const ValueKey('configuration-field-interface_address'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '192.168.10.24');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('simulation-zoom-in')));
    await tester.pumpAndSettle();
    final camera = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    String draft() => tester
        .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)))
        .controller
        .text;
    expect(draft(), '192.168.10.24');
    expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController,
        same(camera));
    expect(camera!.value.getMaxScaleOnAxis(), 1.25);
    tester.view.physicalSize = const Size(800, 360);
    await tester.pumpAndSettle();
    expect(draft(), '192.168.10.24');
    expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController,
        same(camera));
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    expect(draft(), '192.168.10.24');
    await tester.tap(find.byKey(const ValueKey('mission-guidance-toggle')));
    await tester.pumpAndSettle();
    expect(find.text(MissionContentData.workspaceGuideLabel), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mission-guide-close')));
    await tester.pumpAndSettle();
    expect(draft(), '192.168.10.24');
    expect(fixture.controller!.state.acceptedEvidenceIds, isEmpty);
    expect(fixture.controller!.state.currentPhaseId, initial.currentPhaseId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard leaves the action accessible without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final definition = MissionSimulationDefinitions.byId('coc2_m4');
    await tester.pumpWidget(_host(definition,
        initialState: MissionRuntimeState.initial(definition.id)
            .copyWith(currentPhaseId: definition.phases[1].id),
        viewInsets: const EdgeInsets.only(bottom: 300)));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('mission-next'))).bottom,
        lessThanOrEqualTo(500));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'resized workspace keeps a real drag aligned with its destination',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final definition = MissionSimulationDefinitions.byId('coc1_m2');
    final plan = EquipmentPracticeDriver(definition)
      ..complete(definition.phases.first);
    await tester.pumpWidget(_host(definition,
        initialState:
            plan.state.copyWith(currentPhaseId: definition.phases[1].id)));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<MissionSimulationScreen>(find.byType(MissionSimulationScreen))
        .controller!;
    final before = controller.state.acceptedEvidenceIds.length;
    await tester.tap(find.byKey(const ValueKey('mission-controls-toggle')));
    await tester.pumpAndSettle();
    final source = find.byKey(const ValueKey('workspace-source-motherboard'));
    final target =
        find.byKey(const ValueKey('workspace-destination-motherboard_area'));
    await tester.ensureVisible(source);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.dragFrom(tester.getCenter(source),
        tester.getCenter(target) - tester.getCenter(source));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('workspace-orientation-aligned')));
    await tester.pumpAndSettle();
    expect(controller.state.placements['motherboard'], 'motherboard_area');
    expect(controller.state.acceptedEvidenceIds.length, before + 1);
    expect(controller.state.pendingEvidence, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showcase work phases retain a usable canvas and guide',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final sample in [
      ('coc1_m2', 1),
      ('coc2_m3', 2),
      ('coc3_m4', 1),
      ('coc4_m5', 3)
    ]) {
      final definition = MissionSimulationDefinitions.byId(sample.$1);
      final plan = EquipmentPracticeDriver(definition);
      for (final previous in definition.phases.take(sample.$2)) {
        plan.complete(previous);
      }
      await tester.pumpWidget(_host(definition,
          initialState: plan.state
              .copyWith(currentPhaseId: definition.phases[sample.$2].id)));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SimulationScene)).height,
          greaterThan(250));
      expect(tester.takeException(), isNull, reason: sample.$1);
      if (_capture.isNotEmpty) {
        await _captureScreen(tester, '${sample.$1}-phase${sample.$2 + 1}');
      }
      await tester.tap(find.byKey(const ValueKey('mission-guidance-toggle')));
      await tester.pumpAndSettle();
      if (_capture.isNotEmpty) {
        await _captureScreen(tester, '${sample.$1}-guide');
      }
      await tester.tap(find.byKey(const ValueKey('mission-guide-close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: sample.$1);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

Future<void> _captureScreen(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('workspace-capture')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
    final file = File('build/workspace-qa/$_capture/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  });
}

Widget _host(
  MissionSimulationDefinition definition, {
  double textScale = 1,
  MissionRuntimeState? initialState,
  EdgeInsets padding = const EdgeInsets.only(top: 24, bottom: 24),
  EdgeInsets viewInsets = EdgeInsets.zero,
}) {
  final controller = MissionRuntimeController(
    userId: 'workspace-qa',
    initialState: initialState ??
        MissionRuntimeState.initial(definition.id)
            .copyWith(currentPhaseId: definition.phases.first.id),
    store: const SharedPreferencesMissionRuntimeStore(),
    evidenceGateway: MissionEvidenceGateway(transport: _NoNetworkTransport()),
    submissionPhaseIds: {definition.phases.last.id},
  );
  return MaterialApp(
    theme: AppTheme.lightTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
          padding: padding,
          viewInsets: viewInsets,
          textScaler: TextScaler.linear(textScale)),
      child: RepaintBoundary(
          key: const ValueKey('workspace-capture'), child: child!),
    ),
    home: MissionSimulationScreen(
      key: ValueKey(definition.id),
      mission: Mission(
          id: definition.id,
          cocId: definition.cocId,
          missionCode: definition.id.toUpperCase(),
          missionNumber: int.parse(definition.id.substring(6)),
          title: definition.title,
          missionType: MissionType.identification,
          orderIndex: 1),
      definition: definition,
      controller: controller,
      timedPractice: true,
      practiceUserId: 'workspace-qa',
    ),
  );
}

class _NoNetworkTransport implements MissionEvidenceTransport {
  @override
  Future<void> append(MissionEvidenceAction action) async {}

  @override
  Future<List<AcknowledgedMissionEvidenceAction>>
      readAcknowledgedActions() async => [];
}
