import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/models/mission_model.dart';
import 'package:bytequest/screens/simulation/components/assembly/assembly_bench.dart';
import 'package:bytequest/screens/simulation/components/assembly/assembly_bench_layout.dart';
import 'package:bytequest/screens/simulation/components/assembly/assembly_bench_painter.dart';
import 'package:bytequest/screens/simulation/components/simulation_scene.dart';
import 'package:bytequest/screens/simulation/mission_simulation_screen.dart';
import 'package:bytequest/screens/simulation/runtime/mission_evidence_gateway.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_controller.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:bytequest/services/progress_resume_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/equipment_practice_driver.dart';

final _definition = MissionSimulationDefinitions.byId('coc1_m2');
MissionPhaseDefinition _phase(int number) => _definition.phases[number - 1];

class _RecordingTransport implements MissionEvidenceTransport {
  final actions = <MissionEvidenceAction>[];

  @override
  Future<void> append(MissionEvidenceAction action) async => actions.add(action);

  @override
  Future<List<AcknowledgedMissionEvidenceAction>>
      readAcknowledgedActions() async => [];
}

/// Completes phases 1..[through] with the scripted work order.
MissionRuntimeState _stateAt(int phase, {MissionRuntimeMode? mode}) {
  final driver = EquipmentPracticeDriver(_definition);
  for (final previous in _definition.phases.take(phase - 1)) {
    driver.complete(previous);
  }
  final state = driver.state.copyWith(currentPhaseId: _phase(phase).id);
  if (mode != MissionRuntimeMode.assessment) return state;
  return MissionRuntimeState.fromJson({
    ...state.toJson(),
    'mode': 'assessment',
    'assessmentAttemptId': 'attempt-qa',
  });
}

var _harnessCount = 0;

class _Harness {
  _Harness(this.initial) : transport = _RecordingTransport();

  final MissionRuntimeState initial;
  final _RecordingTransport transport;
  // A fresh learner per harness, so one pump never restores another's save.
  final String userId = 'bench-qa-${_harnessCount++}';
  late final MissionRuntimeController controller = MissionRuntimeController(
    userId: userId,
    initialState: initial,
    store: const SharedPreferencesMissionRuntimeStore(),
    evidenceGateway: MissionEvidenceGateway(transport: transport),
    submissionPhaseIds: {_definition.phases.last.id},
  );
  int submissions = 0;

  Widget app({bool reducedMotion = true, double textScale = 1}) => MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              disableAnimations: reducedMotion,
              textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: MissionSimulationScreen(
          mission: Mission(
              id: 'coc1_m2',
              cocId: 'coc1',
              missionCode: 'COC1_M2',
              missionNumber: 2,
              title: _definition.title,
              missionType: MissionType.identification,
              orderIndex: 2),
          definition: _definition,
          controller: controller,
          onSubmit: () async => submissions++,
        ),
      );

  Map<String, dynamic>? lastValue(String runtimeType) {
    for (final action in transport.actions.reversed) {
      if (action.value['runtime_action_type'] == runtimeType) {
        return action.value;
      }
    }
    return null;
  }
}

Future<_Harness> _pump(WidgetTester tester, MissionRuntimeState state,
    {Size size = const Size(412, 915), bool reducedMotion = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = _Harness(state);
  await tester.pumpWidget(harness.app(reducedMotion: reducedMotion));
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String key) {
  final button = tester.widget<ButtonStyleButton>(find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton)));
  return button.onPressed != null;
}

double _turns(WidgetTester tester, String part) => tester
    .widget<AnimatedRotation>(find.byKey(ValueKey('bench-rotation-$part')).first)
    .turns;

/// Which side of its photograph a part's marker is on, on screen: the sign
/// of the marker centre relative to the photograph centre, after rotation.
/// Offsets under 15 % of the photograph count as centred (0).
(int, int) _markerSide(WidgetTester tester, Finder within, String part) {
  final image = find.descendant(
      of: within, matching: find.byKey(ValueKey('bench-rotation-$part')));
  final marker = find.descendant(
      of: within, matching: find.byKey(ValueKey('bench-marker-$part')));
  expect(marker, findsOneWidget, reason: 'the marker is drawn on the part');
  final photo = tester.getRect(image);
  final offset = tester.getCenter(marker) - photo.center;
  final tolerance = photo.width * .15;
  int sign(double value) => value.abs() < tolerance ? 0 : value.sign.toInt();
  return (sign(offset.dx), sign(offset.dy));
}

String _description(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('bench-part-preview-description')))
    .data!;

/// The practice guide outline on the bench, mapped to the screen through
/// the canvas, the fitted workspace and the camera.
List<Rect> _outlinesOnScreen(WidgetTester tester) {
  final wiring = find.byKey(const ValueKey('assembly-bench-wiring'));
  final painter =
      tester.widget<CustomPaint>(wiring).painter! as AssemblyBenchPainter;
  final box = tester.renderObject<RenderBox>(wiring);
  final sx = box.size.width / AssemblyBenchLayout.canvas.width;
  final sy = box.size.height / AssemblyBenchLayout.canvas.height;
  final toScreen = box.getTransformTo(null);
  return [
    for (final rect in AssemblyBenchPainter.highlightRects(
        painter.view, painter.highlighted))
      MatrixUtils.transformRect(
          toScreen,
          Rect.fromLTRB(rect.left * sx, rect.top * sy, rect.right * sx,
              rect.bottom * sy)),
  ];
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ProgressResumeService.markMissionTutorialSeen('bench-qa');
  });

  testWidgets('the bench replaces the card workspace with real part images',
      (tester) async {
    await _pump(tester, _stateAt(2));
    expect(find.byType(AssemblyBench), findsOneWidget);
    expect(find.byKey(const ValueKey('simulation-workspace-scroll')),
        findsOneWidget, reason: 'zoom and pan come from the shared scene');
    final images = tester
        .widgetList<Image>(find.descendant(
            of: find.byType(AssemblyBench), matching: find.byType(Image)))
        .map((image) => (image.image as AssetImage).assetName)
        .toSet();
    expect(images, containsAll([
      AssemblyBenchLayout.boardAsset,
      'assets/COC1/Mission 2/cpu.png',
      'assets/COC1/Mission 2/ram.png',
      'assets/COC1/Mission 2/cooling_fan.png',
    ]));
    expect(find.textContaining('Step 1 of 9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging a part shows its photograph as the ghost',
      (tester) async {
    await _pump(tester, _stateAt(2));
    final part = find.byKey(const ValueKey('bench-part-cpu'));
    await tester.ensureVisible(part);
    final gesture = await tester.startGesture(tester.getCenter(part));
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();
    final ghost = find.byKey(const ValueKey('bench-drag-ghost-cpu'));
    expect(ghost, findsOneWidget);
    final image = tester.widget<Image>(
        find.descendant(of: ghost, matching: find.byType(Image)));
    expect((image.image as AssetImage).assetName,
        'assets/COC1/Mission 2/cpu.png');
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'rotation is visible and recorded; a dragged part snaps into the exact slot',
      (tester) async {
    final harness = await _pump(tester, _stateAt(2));
    await _tapKey(tester, 'bench-operation-open_cpu_lever');
    expect(harness.controller.state.equipmentState['cpu_lever'], 'open');
    await _tapKey(tester, 'bench-part-cpu');
    expect(_turns(tester, 'cpu'), .25, reason: 'the CPU starts turned 90°');
    for (var i = 0; i < 3; i++) {
      await _tapKey(tester, 'bench-rotate');
    }
    expect(_turns(tester, 'cpu'), 1, reason: 'four quarter turns, clockwise');
    final part = find.byKey(const ValueKey('bench-part-cpu'));
    final slot = find.byKey(const ValueKey('bench-slot-cpu_socket'));
    await tester.ensureVisible(part);
    await tester.pumpAndSettle();
    await tester.dragFrom(
        tester.getCenter(part), tester.getCenter(slot) - tester.getCenter(part));
    await tester.pump();
    await tester.pump();
    expect(harness.controller.state.placements['cpu'], 'cpu_socket');
    expect(harness.lastValue('placement_attempted')?['orientation'], '0');
    expect(harness.lastValue('placement_attempted')?['input_method'], 'drag');
    final placed = find.byKey(const ValueKey('bench-placed-cpu'));
    final seated = tester.getRect(placed);
    final target = tester.getRect(slot);
    expect(target.contains(seated.topLeft + const Offset(.5, .5)), isTrue);
    expect(target.contains(seated.bottomRight - const Offset(.5, .5)), isTrue);
    final seat = tester.widget<TweenAnimationBuilder<double>>(find
        .descendant(
            of: placed, matching: find.byType(TweenAnimationBuilder<double>))
        .first);
    expect(seat.duration, Duration.zero,
        reason: 'no seat animation under reduced motion');
    final scale = tester.widget<Transform>(
        find.descendant(of: placed, matching: find.byType(Transform)).first);
    expect(scale.transform.getMaxScaleOnAxis(), 1);
    await tester.pumpAndSettle();
  });

  testWidgets('the seat animation runs for 150–250 ms with motion enabled',
      (tester) async {
    final harness =
        await _pump(tester, _stateAt(2), reducedMotion: false);
    await _tapKey(tester, 'bench-operation-open_cpu_lever');
    await _tapKey(tester, 'bench-part-cpu');
    for (var i = 0; i < 3; i++) {
      await _tapKey(tester, 'bench-rotate');
    }
    await _tapKey(tester, 'bench-slot-chip-cpu_socket');
    expect(harness.controller.state.placements['cpu'], 'cpu_socket');
    final seat = tester.widget<TweenAnimationBuilder<double>>(find
        .descendant(
            of: find.byKey(const ValueKey('bench-placed-cpu')),
            matching: find.byType(TweenAnimationBuilder<double>))
        .first);
    expect(seat.duration.inMilliseconds, inInclusiveRange(150, 250));
  });

  testWidgets('tap a part, then tap a slot, installs it', (tester) async {
    final harness = await _pump(tester, _stateAt(2));
    await _tapKey(tester, 'bench-operation-open_dimm_latches');
    await _tapKey(tester, 'bench-part-ram_1');
    await _tapKey(tester, 'bench-rotate');
    await _tapKey(tester, 'bench-rotate');
    await _tapKey(tester, 'bench-slot-chip-dimm_a2');
    expect(harness.controller.state.placements['ram_1'], 'dimm_a2');
    expect(harness.lastValue('placement_attempted'), containsPair('input_method', 'tap'));
  });

  testWidgets('levers, latches and screws stay disabled until physically possible',
      (tester) async {
    final harness = await _pump(tester, _stateAt(2));
    expect(_enabled(tester, 'bench-operation-close_cpu_lever'), isFalse);
    expect(_enabled(tester, 'bench-operation-apply_thermal_compound'), isFalse);
    expect(_enabled(tester, 'bench-operation-close_dimm_latches'), isFalse);
    expect(find.byKey(const ValueKey('bench-hotspot-close_cpu_lever')),
        findsNothing);
    await _tapKey(tester, 'bench-operation-open_cpu_lever');
    expect(_enabled(tester, 'bench-operation-close_cpu_lever'), isTrue);
    expect(harness.controller.state.equipmentState['cpu_lever'], 'open');
    await tester.pumpWidget(const SizedBox.shrink());

    await _pump(tester, _stateAt(3));
    expect(_enabled(tester, 'bench-operation-fasten_psu'), isFalse);
    await _tapKey(tester, 'bench-operation-pick_screwdriver');
    expect(_enabled(tester, 'bench-operation-fasten_psu'), isFalse,
        reason: 'no power supply is seated yet');
  });

  testWidgets('practice refuses a part that cannot fit with a technical reason',
      (tester) async {
    final harness = await _pump(tester, _stateAt(2));
    await _tapKey(tester, 'bench-part-cooler');
    await _tapKey(tester, 'bench-slot-chip-dimm_a1');
    expect(harness.controller.state.placements.containsKey('cooler'), isFalse);
    expect(find.text(MissionContentData.incorrectPlacementTitle), findsOneWidget);
  });

  testWidgets('assessment refuses an impossible fit with neutral feedback only',
      (tester) async {
    final harness =
        await _pump(tester, _stateAt(2, mode: MissionRuntimeMode.assessment));
    await _tapKey(tester, 'bench-operation-open_cpu_lever');
    await _tapKey(tester, 'bench-part-cpu');
    await _tapKey(tester, 'bench-slot-chip-dimm_a1');
    expect(harness.controller.state.placements.containsKey('cpu'), isFalse);
    expect(find.text(MissionContentData.incorrectPlacementTitle), findsNothing);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('assembly-bench-information')))
            .data,
        MissionContentData.assessmentNeutralPlacement);
    expect(find.textContaining('triangle'), findsNothing);
    expect(harness.lastValue('placement_attempted')?['simulation_valid'], isFalse);
  });

  testWidgets('a wrong DIMM pair is accepted, flagged at POST and fixable',
      (tester) async {
    final driver = EquipmentPracticeDriver(_definition)
      ..complete(_phase(1));
    final p2 = _phase(2);
    for (final step in practiceScripts[p2.id]!) {
      final value = Map<String, dynamic>.from(step.$3);
      if (value['item_id'] == 'ram_1') value['destination_id'] = 'dimm_a1';
      if (value['item_id'] == 'ram_2') value['destination_id'] = 'dimm_b1';
      driver.act(p2, step.$1, value['destination_id'] as String? ?? step.$2, value);
    }
    expect(driver.state.placements['ram_1'], 'dimm_a1',
        reason: 'a physically possible mistake is not refused');
    driver
      ..complete(_phase(3))
      ..complete(_phase(4));
    final harness = await _pump(
        tester, driver.state.copyWith(currentPhaseId: _phase(5).id));

    Future<void> runPost() async {
      await _tapKey(tester, 'test-run-start');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    await runPost();
    expect(find.textContaining('single-channel mode'), findsOneWidget);
    for (final module in ['ram_1', 'ram_2']) {
      await _tapKey(tester, 'bench-part-$module');
      await _tapKey(tester, 'bench-remove');
    }
    expect(harness.controller.state.placements.containsKey('ram_1'), isFalse);
    await _tapKey(tester, 'bench-operation-open_dimm_latches');
    for (final (module, slot) in [('ram_1', 'dimm_a2'), ('ram_2', 'dimm_b2')]) {
      await _tapKey(tester, 'bench-part-$module');
      await _tapKey(tester, 'bench-rotate');
      await _tapKey(tester, 'bench-rotate');
      await _tapKey(tester, 'bench-slot-chip-$slot');
      expect(harness.controller.state.placements[module], slot);
    }
    await _tapKey(tester, 'bench-operation-close_dimm_latches');
    await runPost();
    expect(find.textContaining('Dual-channel mode'), findsOneWidget);
    expect(find.textContaining('single-channel mode'), findsNothing);
    // Fix round 2: the failed POST charged the memory step once; reseating
    // the modules it flagged is the repair, not two more corrections.
    final counts =
        harness.controller.state.equipmentState['counts'] as Map;
    expect(counts['faults'], 1);
    expect(counts['repairs'], 2);
    expect(counts['corrections'], isNull);
    expect(find.byKey(const ValueKey('assembly-bench-fault-count')),
        findsOneWidget);
  });

  testWidgets('assessment hides guidance and highlights and submits on confirm',
      (tester) async {
    final harness =
        await _pump(tester, _stateAt(2, mode: MissionRuntimeMode.assessment));
    expect(find.byKey(const ValueKey('mission-guidance-toggle')), findsNothing);
    expect(find.byKey(const ValueKey('assessment-bar')), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('assembly-bench-step')))
            .data,
        MissionContentData.benchAssessmentHeader);
    await _tapKey(tester, 'bench-operation-open_dimm_latches');
    await _tapKey(tester, 'bench-part-ram_1');
    expect(find.byIcon(Icons.add_task_rounded), findsNothing,
        reason: 'no compatible-slot highlight in assessment');
    await _tapKey(tester, 'bench-cancel');

    await _tapKey(tester, 'assessment-submit');
    expect(find.text(MissionContentData.assessmentSubmitTitle), findsOneWidget);
    await _tapKey(tester, 'assessment-submit-cancel');
    expect(harness.submissions, 0);
    await _tapKey(tester, 'assessment-submit');
    await _tapKey(tester, 'assessment-submit-confirm');
    expect(harness.submissions, 1,
        reason: 'unfinished assessments can be submitted after confirmation');
  });

  testWidgets('practice highlights compatible slots and guides the next step',
      (tester) async {
    await _pump(tester, _stateAt(2));
    await _tapKey(tester, 'bench-operation-open_dimm_latches');
    await _tapKey(tester, 'bench-part-ram_1');
    expect(find.byIcon(Icons.add_task_rounded), findsNWidgets(4),
        reason: 'all four DIMM slots accept the module');
  });

  for (final size in const [Size(320, 568), Size(640, 360)]) {
    testWidgets('every bench phase fits $size without overflow', (tester) async {
      for (var phase = 1; phase <= 6; phase++) {
        await _pump(tester, _stateAt(phase), size: size);
        expect(tester.takeException(), isNull, reason: 'phase $phase');
        expect(find.byType(SimulationScene), findsOneWidget);
        final canvas = tester.getRect(
            find.byKey(const ValueKey('simulation-workspace-scroll')));
        expect(canvas.height, greaterThanOrEqualTo(100), reason: 'phase $phase');
        final tray = find.byKey(const ValueKey('assembly-bench-tray'));
        if (phase < 6) {
          expect(tester.getSize(tray).height, greaterThanOrEqualTo(48));
        } else {
          expect(tray, findsNothing, reason: 'the review bench is read-only');
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  testWidgets('bench controls carry semantic labels and 48 dp targets',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _stateAt(2));
    expect(find.bySemanticsLabel(RegExp(r'^Processor\. Drag it to the bench')),
        findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^DIMM_A2, empty')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Open the CPU socket lever')),
        findsWidgets);
    expect(find.bySemanticsLabel(RegExp(r'^Elapsed time')), findsOneWidget);
    for (final key in ['bench-part-cpu', 'bench-operation-open_cpu_lever']) {
      final size = tester.getSize(find.byKey(ValueKey(key)));
      expect(size.height, greaterThanOrEqualTo(48), reason: key);
      expect(size.width, greaterThanOrEqualTo(48), reason: key);
    }
    semantics.dispose();
  });

  testWidgets('the inspection phase inspects parts on the mat and grounds ESD',
      (tester) async {
    final harness = await _pump(tester, _stateAt(1));
    await _tapKey(tester, 'bench-inspect-chip-cpu');
    expect(harness.controller.state.hotspotStates['cpu'],
        HotspotVisualState.selected);
    expect(find.textContaining('gold triangle marks pin 1'), findsOneWidget);
    expect(_enabled(tester, 'bench-operation-ground_wrist_strap'), isFalse);
    await _tapKey(tester, 'bench-operation-wear_wrist_strap');
    expect(_enabled(tester, 'bench-operation-ground_wrist_strap'), isTrue);
  });

  // Polish round P1: a keyed part's marker is drawn on the part and turns
  // with it in the tray, the larger preview, the drag ghost and the slot.
  testWidgets('the CPU triangle moves with every rotation in tray and preview',
      (tester) async {
    await _pump(tester, _stateAt(2));
    await _tapKey(tester, 'bench-part-cpu');
    final preview = find.byKey(const ValueKey('bench-part-preview'));
    final tile = find.byKey(const ValueKey('bench-part-cpu'));
    expect(preview, findsOneWidget);
    final seen = <(int, int)>{};
    // From the initial 90°, one clockwise quarter turn per tap.
    for (final (index, (degrees, corner, side)) in const [
      (90, 'top-left', (-1, -1)),
      (180, 'top-right', (1, -1)),
      (270, 'bottom-right', (1, 1)),
      (0, 'bottom-left', (-1, 1)),
    ].indexed) {
      if (index > 0) await _tapKey(tester, 'bench-rotate');
      expect(
          _description(tester),
          MissionContentData.benchMarkerDescription(
              MissionContentData.benchMarkerTriangle, corner, degrees));
      expect(_markerSide(tester, preview, 'cpu'), side,
          reason: 'preview at $degrees°');
      expect(_markerSide(tester, tile, 'cpu'), side,
          reason: 'tray tile at $degrees°');
      seen.add(side);
    }
    expect(seen, hasLength(4), reason: 'each rotation moves the triangle');
    Rect photo(Finder within) => tester.getRect(find.descendant(
        of: within, matching: find.byKey(const ValueKey('bench-rotation-cpu'))));
    expect(photo(preview).width, greaterThanOrEqualTo(2 * photo(tile).width),
        reason: 'the preview is a larger view of the part in hand');
  });

  testWidgets('the drag ghost and the seated CPU carry the triangle',
      (tester) async {
    final harness = await _pump(tester, _stateAt(2));
    await _tapKey(tester, 'bench-operation-open_cpu_lever');
    final part = find.byKey(const ValueKey('bench-part-cpu'));
    await tester.ensureVisible(part);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(part));
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();
    expect(
        _markerSide(
            tester, find.byKey(const ValueKey('bench-drag-ghost-cpu')), 'cpu'),
        (-1, -1),
        reason: 'the ghost shows the part as held: 90°, triangle top-left');
    await gesture.cancel();
    await tester.pumpAndSettle();
    await _tapKey(tester, 'bench-part-cpu');
    for (var i = 0; i < 3; i++) {
      await _tapKey(tester, 'bench-rotate');
    }
    await _tapKey(tester, 'bench-slot-chip-cpu_socket');
    expect(harness.controller.state.placements['cpu'], 'cpu_socket');
    final seated = find.byKey(const ValueKey('bench-placed-cpu'));
    expect(_markerSide(tester, seated, 'cpu'), (-1, 1));
    // The seated triangle covers the one printed on the socket.
    final marker = tester.getRect(find.descendant(
        of: seated, matching: find.byKey(const ValueKey('bench-marker-cpu'))));
    final socket =
        tester.getRect(find.byKey(const ValueKey('bench-slot-cpu_socket')));
    final mark = AssemblyBenchLayout.markers['cpu']!.box;
    final printed = Rect.fromLTWH(
        socket.left + mark.left * socket.width,
        socket.top + mark.top * socket.height,
        mark.width * socket.width,
        mark.height * socket.height);
    expect((marker.center - printed.center).distance, lessThan(1));
  });

  testWidgets('the memory notch marker moves with every rotation',
      (tester) async {
    await _pump(tester, _stateAt(2));
    await _tapKey(tester, 'bench-part-ram_1');
    final preview = find.byKey(const ValueKey('bench-part-preview'));
    final tile = find.byKey(const ValueKey('bench-part-ram_1'));
    final seen = <(int, int)>{};
    for (final (index, (degrees, edge, side)) in const [
      (180, 'right edge', (1, 0)),
      (270, 'bottom edge', (0, 1)),
      (0, 'left edge', (-1, 0)),
      (90, 'top edge', (0, -1)),
    ].indexed) {
      if (index > 0) await _tapKey(tester, 'bench-rotate');
      expect(
          _description(tester),
          MissionContentData.benchMarkerDescription(
              MissionContentData.benchMarkerNotch, edge, degrees));
      expect(_markerSide(tester, preview, 'ram_1'), side,
          reason: 'preview at $degrees°');
      expect(_markerSide(tester, tile, 'ram_1'), side,
          reason: 'tray tile at $degrees°');
      seen.add(side);
    }
    expect(seen, hasLength(4));
  });

  testWidgets('the power-supply fan marker moves with every rotation',
      (tester) async {
    final harness = await _pump(tester, _stateAt(3));
    await _tapKey(tester, 'bench-part-psu');
    final preview = find.byKey(const ValueKey('bench-part-preview'));
    final tile = find.byKey(const ValueKey('bench-part-psu'));
    final seen = <(int, int)>{};
    for (final (index, (degrees, facing, side)) in const [
      (180, 'facing up', (0, -1)),
      (270, 'facing right', (1, 0)),
      (0, 'facing down', (0, 1)),
      (90, 'facing left', (-1, 0)),
    ].indexed) {
      if (index > 0) await _tapKey(tester, 'bench-rotate');
      expect(
          _description(tester),
          MissionContentData.benchMarkerDescription(
              MissionContentData.benchMarkerFan, facing, degrees));
      expect(_markerSide(tester, preview, 'psu'), side,
          reason: 'preview at $degrees°');
      expect(_markerSide(tester, tile, 'psu'), side,
          reason: 'tray tile at $degrees°');
      seen.add(side);
    }
    expect(seen, hasLength(4));
    for (var i = 0; i < 3; i++) {
      await _tapKey(tester, 'bench-rotate');
    }
    await _tapKey(tester, 'bench-slot-chip-psu_bay');
    expect(harness.controller.state.placements['psu'], 'psu_bay');
    expect(
        _markerSide(
            tester, find.byKey(const ValueKey('bench-placed-psu')), 'psu'),
        (0, 1),
        reason: 'seated, the fan faces the intake vent in the bay floor');
  });

  testWidgets('assessment shows where the marker is, never whether it fits',
      (tester) async {
    await _pump(tester, _stateAt(2, mode: MissionRuntimeMode.assessment));
    await _tapKey(tester, 'bench-part-cpu');
    expect(
        _description(tester),
        MissionContentData.benchMarkerPosition(
            MissionContentData.benchMarkerTriangle, 'top-left'));
    expect(
        _markerSide(
            tester, find.byKey(const ValueKey('bench-part-preview')), 'cpu'),
        (-1, -1));
    expect(find.text(MissionContentData.benchOrientationFeedback['cpu']!),
        findsNothing);
  });

  // Polish round P2: an operation confirms what physically changed.
  testWidgets('bench operations confirm the change without asking for a test',
      (tester) async {
    // The confirmation appears in the task panel below the bench.
    void shows(String text) {
      expect(find.text(text, skipOffstage: false), findsOneWidget);
      expect(
          find.text(MissionContentData.equipmentUpdatedFeedback,
              skipOffstage: false),
          findsNothing);
    }

    await _pump(tester, _stateAt(1));
    for (final operation in ['wear_wrist_strap', 'ground_wrist_strap']) {
      await _tapKey(tester, 'bench-operation-$operation');
      shows(MissionContentData.benchOperationFeedback[operation]!);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, _stateAt(2));
    await _tapKey(tester, 'bench-operation-open_cpu_lever');
    shows('Load lever opened.');
    await _tapKey(tester, 'bench-operation-close_cpu_lever');
    shows(MissionContentData.benchOperationFeedback['close_cpu_lever']!);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, _stateAt(2, mode: MissionRuntimeMode.assessment));
    await _tapKey(tester, 'bench-operation-open_cpu_lever');
    shows(MissionContentData.assessmentNeutralRecorded);
    expect(find.text('Load lever opened.', skipOffstage: false), findsNothing,
        reason: 'assessment feedback stays neutral');
  });

  // Polish round P3: the guide outline is drawn in canvas units, so it sits
  // on its target at any zoom, pan and viewport size.
  for (final size in const [
    Size(412, 915),
    Size(320, 568),
    Size(915, 412),
    Size(1280, 800),
  ]) {
    testWidgets('the guide outline sits on its target at $size',
        (tester) async {
      final p2 = _phase(2);
      final script = practiceScripts[p2.id]!;
      for (final (steps, slot) in const [
        (1, 'cpu_socket'), // Seat the CPU (lever open).
        (4, 'cooler_mount'), // Mount the cooler over the CPU.
      ]) {
        for (final (scale, offset) in const [
          (1.0, Offset.zero),
          (2.0, Offset(-300, -150)),
        ]) {
          final driver = EquipmentPracticeDriver(_definition)
            ..complete(_phase(1));
          for (final step in script.take(steps)) {
            driver.act(p2, step.$1, step.$2, step.$3);
          }
          await _pump(
              tester,
              driver.state.copyWith(
                  currentPhaseId: p2.id,
                  cameraScale: scale,
                  cameraOffsetX: offset.dx,
                  cameraOffsetY: offset.dy),
              size: size);
          await _tapKey(tester, 'mission-show-me-how');
          final target =
              tester.getRect(find.byKey(ValueKey('bench-slot-$slot')));
          final outlines = _outlinesOnScreen(tester);
          final reason = '$slot at ×$scale';
          expect(outlines, hasLength(1), reason: reason);
          expect((outlines.single.center - target.center).distance,
              lessThan(1), reason: reason);
          expect(outlines.single.contains(target.topLeft), isTrue,
              reason: reason);
          expect(outlines.single.contains(target.bottomRight - const Offset(.5, .5)),
              isTrue, reason: reason);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    });
  }

  // Polish round P4: the mat hotspots name their object in both modes.
  testWidgets('the wrist strap and the mat ground point are labelled',
      (tester) async {
    for (final mode in MissionRuntimeMode.values) {
      await _pump(tester, _stateAt(1, mode: mode));
      for (final (id, label) in const [
        ('wear_wrist_strap', 'Wrist strap'),
        ('ground_wrist_strap', 'Mat ground point'),
      ]) {
        final plate = find.byKey(ValueKey('bench-hotspot-label-$id'));
        expect(find.descendant(of: plate, matching: find.text(label)),
            findsOneWidget, reason: '$id in ${mode.name}');
        // Beside its hotspot, inside the canvas, never over it.
        final rect = AssemblyBenchLayout.hotspotLabel(id)!;
        final spot = AssemblyBenchLayout.operation(id, BenchView.mat)!;
        expect((Offset.zero & AssemblyBenchLayout.canvas).contains(rect.topLeft) &&
                (Offset.zero & AssemblyBenchLayout.canvas)
                    .contains(rect.bottomRight),
            isTrue);
        expect(rect.overlaps(spot), isFalse);
        expect(rect.center.dx - spot.center.dx, lessThan(260));
        expect((rect.center.dy - spot.center.dy).abs(), lessThan(160));
      }
      final strap = find.byWidgetPredicate((widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName ==
              AssemblyBenchLayout.strapAsset);
      expect(strap, findsOneWidget, reason: 'the strap is pictured');
      expect(find.text('Wear the anti-static wrist strap'), findsWidgets,
          reason: 'the tray keeps the operation');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  // Final fix C1: on a phone a finger swipe on the tray scrolls it; a part
  // or cable is dragged only by a deliberate move up toward the bench, and a
  // tap still selects. No test here scrolls the tray programmatically.
  group('tray touch gestures at 360x640', () {
    const phone = Size(360, 640);

    ScrollPosition trayPosition(WidgetTester tester) => tester
        .state<ScrollableState>(find.descendant(
            of: find.byKey(const ValueKey('assembly-bench-tray-scroll')),
            matching: find.byType(Scrollable)))
        .position;

    Rect trayRect(WidgetTester tester) =>
        tester.getRect(find.byKey(const ValueKey('assembly-bench-tray')));

    bool anyGhost() => find
        .byWidgetPredicate((widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('bench-drag-ghost-'))
        .evaluate()
        .isNotEmpty;

    /// A slow finger swipe (no fling) from [start] by [delta], in small steps.
    Future<bool> swipe(WidgetTester tester, Offset start, Offset delta) async {
      final gesture =
          await tester.startGesture(start, kind: PointerDeviceKind.touch);
      var ghost = false;
      const steps = 12;
      for (var i = 1; i <= steps; i++) {
        await gesture.moveTo(start + delta * (i / steps));
        await tester.pump(const Duration(milliseconds: 16));
        ghost = ghost || anyGhost();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      return ghost;
    }

    /// The centre of a tray chip that starts a drag (a part or cable tile)
    /// and lies fully inside the tray, else of any visible tray control.
    Offset chipStart(WidgetTester tester) {
      final tray = trayRect(tester);
      Offset? fallback;
      for (final element in find
          .byWidgetPredicate((widget) =>
              widget.key is ValueKey<String> &&
              RegExp(r'^bench-(part|cable|operation|inspect-chip|slot-chip|header-chip)-')
                  .hasMatch((widget.key! as ValueKey<String>).value))
          .evaluate()) {
        final box = element.renderObject as RenderBox?;
        if (box == null || !box.hasSize) continue;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        if (rect.left < tray.left + 2 || rect.right > tray.right - 2) continue;
        if (rect.top < tray.top || rect.bottom > tray.bottom) continue;
        final key = (element.widget.key! as ValueKey<String>).value;
        if (key.startsWith('bench-part-') || key.startsWith('bench-cable-')) {
          return rect.center;
        }
        fallback ??= rect.center;
      }
      return fallback ?? tray.center;
    }

    /// Swipes the tray, always starting on a chip, until [key] lies fully
    /// inside it; every swipe must scroll and must never pick a part up.
    Future<void> swipeTo(WidgetTester tester, String key) async {
      for (var i = 0; i < 30; i++) {
        final tray = trayRect(tester);
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        if (rect.left >= tray.left && rect.right <= tray.right) return;
        final before = trayPosition(tester).pixels;
        final left = rect.right > tray.right;
        final ghost =
            await swipe(tester, chipStart(tester), Offset(left ? -140 : 140, 0));
        expect(ghost, isFalse, reason: 'a sideways swipe never drags a part');
        expect(trayPosition(tester).pixels, isNot(before),
            reason: 'a swipe that starts on a chip scrolls the tray ($key)');
      }
      fail('$key never became reachable by swiping');
    }

    testWidgets('a horizontal swipe on a part tile scrolls the tray',
        (tester) async {
      final harness = await _pump(tester, _stateAt(2), size: phone);
      final actions = harness.transport.actions.length;
      final start = tester.getCenter(find.byKey(const ValueKey('bench-part-cpu')));
      expect(trayRect(tester).contains(start), isTrue);
      final ghost = await swipe(tester, start, const Offset(-200, 0));
      expect(ghost, isFalse, reason: 'the swipe must not pick the CPU up');
      expect(trayPosition(tester).pixels, greaterThan(100));
      expect(harness.transport.actions, hasLength(actions),
          reason: 'a scroll records no evidence');
      expect(find.byKey(const ValueKey('bench-rotate')), findsNothing,
          reason: 'a swipe does not select the part either');
    });

    testWidgets('every cable of the cabling phase is reachable and selectable',
        (tester) async {
      await _pump(tester, _stateAt(4), size: phone);
      for (final cable in const [
        'atx_24pin',
        'eps_8pin',
        'sata_power',
        'sata_data',
        'front_panel',
      ]) {
        await swipeTo(tester, 'bench-cable-$cable');
        await tester.tap(find.byKey(ValueKey('bench-cable-$cable')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('bench-cancel')), findsOneWidget,
            reason: 'tapping $cable selects it');
        expect(find.textContaining('selected'), findsWidgets);
        await swipeTo(tester, 'bench-cancel');
        await tester.tap(find.byKey(const ValueKey('bench-cancel')));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('every cable and the screwdriver are reachable in the POST phase',
        (tester) async {
      await _pump(tester, _stateAt(5), size: phone);
      for (final key in const [
        'bench-cable-cooler_fan',
        'bench-cable-atx_24pin',
        'bench-cable-eps_8pin',
        'bench-cable-sata_power',
        'bench-cable-sata_data',
        'bench-cable-front_panel',
        'bench-operation-pick_screwdriver',
      ]) {
        await swipeTo(tester, key);
      }
      // Swiping back the other way reaches the first tile again.
      await swipeTo(tester, 'assembly-bench-toggle-view');
    });

    testWidgets('a deliberate drag up from a tile still seats the part',
        (tester) async {
      final harness = await _pump(tester, _stateAt(2), size: phone);
      await swipeTo(tester, 'bench-operation-open_cpu_lever');
      await tester.tap(find.byKey(const ValueKey('bench-operation-open_cpu_lever')));
      await tester.pumpAndSettle();
      expect(harness.controller.state.equipmentState['cpu_lever'], 'open');
      // A touch tap selects the processor; rotate it to the socket mark.
      await swipeTo(tester, 'bench-part-cpu');
      await tester.tap(find.byKey(const ValueKey('bench-part-cpu')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('bench-rotate')));
        await tester.pumpAndSettle();
      }
      final start = tester.getCenter(find.byKey(const ValueKey('bench-part-cpu')));
      final gesture =
          await tester.startGesture(start, kind: PointerDeviceKind.touch);
      for (var i = 1; i <= 6; i++) {
        await gesture.moveTo(start + Offset(0, -8.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byKey(const ValueKey('bench-drag-ghost-cpu')), findsOneWidget,
          reason: 'moving up toward the bench picks the part up');
      final socket =
          tester.getCenter(find.byKey(const ValueKey('bench-slot-cpu_socket')));
      await gesture.moveTo(socket);
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(harness.controller.state.placements['cpu'], 'cpu_socket');
      expect(harness.lastValue('placement_attempted')?['input_method'], 'drag');
    });

    testWidgets('a deliberate drag up from a cable tile still connects it',
        (tester) async {
      final harness = await _pump(tester, _stateAt(4), size: phone);
      final start =
          tester.getCenter(find.byKey(const ValueKey('bench-cable-atx_24pin')));
      final gesture =
          await tester.startGesture(start, kind: PointerDeviceKind.touch);
      for (var i = 1; i <= 6; i++) {
        await gesture.moveTo(start + Offset(0, -8.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byKey(const ValueKey('bench-drag-ghost-atx_24pin')),
          findsOneWidget);
      await gesture.moveTo(tester
          .getCenter(find.byKey(const ValueKey('bench-header-board_atx24'))));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(harness.controller.state.connectedNodePairs,
          contains('atx_24pin>board_atx24'));
    });
  });

  // Final fix I3: TalkBack activates tray tiles and buttons (ACTION_CLICK is
  // the semantic tap), not only the canvas hotspots.
  testWidgets('screen-reader taps select, rotate, install and connect',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = await _pump(tester, _stateAt(2));
    SemanticsNode node(String key) =>
        tester.getSemantics(find.byKey(ValueKey(key)).first);
    Future<void> semanticTap(String key) async {
      final finder = find.byKey(ValueKey(key)).first;
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      final target = node(key);
      expect(target.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
          reason: '$key has a semantic tap action');
      target.owner!.performAction(target.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
    }

    await semanticTap('bench-operation-open_cpu_lever');
    expect(harness.controller.state.equipmentState['cpu_lever'], 'open');
    await semanticTap('bench-part-cpu');
    expect(find.byKey(const ValueKey('bench-rotate')), findsOneWidget,
        reason: 'the processor is selected');
    for (var i = 0; i < 3; i++) {
      await semanticTap('bench-rotate');
    }
    await semanticTap('bench-slot-chip-cpu_socket');
    expect(harness.controller.state.placements['cpu'], 'cpu_socket');
    expect(harness.lastValue('placement_attempted')?['orientation'], '0');

    await semanticTap('bench-cable-cooler_fan');
    expect(find.byKey(const ValueKey('bench-header-chip-cpu_fan_header')),
        findsOneWidget, reason: 'the fan cable is selected');
    await semanticTap('bench-header-chip-cpu_fan_header');
    expect(harness.controller.state.connectedNodePairs,
        contains('cooler_fan>cpu_fan_header'));

    await semanticTap('bench-part-ram_1');
    await semanticTap('bench-cancel');
    expect(find.byKey(const ValueKey('bench-cancel')), findsNothing);
    semantics.dispose();
  });

  testWidgets('the view toggle and inspection tiles take a semantic tap',
      (tester) async {
    final semantics = tester.ensureSemantics();
    for (final (phase, key) in const [
      (1, 'bench-inspect-chip-cpu'),
      (5, 'assembly-bench-toggle-view'),
    ]) {
      final harness = await _pump(tester, _stateAt(phase));
      final target = tester.getSemantics(find.byKey(ValueKey(key)));
      expect(target.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
          reason: key);
      target.owner!.performAction(target.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      if (phase == 1) {
        expect(harness.controller.state.hotspotStates['cpu'],
            HotspotVisualState.selected);
      } else {
        expect(find.byKey(const ValueKey('bench-scene-board-coc1_m2_p5')),
            findsOneWidget, reason: 'the close-up opened');
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
    semantics.dispose();
  });

  // Re-review 4 O2: the tile itself names where the marker is.
  testWidgets('a keyed tile announces its marker position', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final mode in MissionRuntimeMode.values) {
      await _pump(tester, _stateAt(2, mode: mode));
      final label = tester
          .getSemantics(find.byKey(const ValueKey('bench-part-cpu')))
          .label;
      expect(
          label,
          contains(MissionContentData.benchMarkerPosition(
              MissionContentData.benchMarkerTriangle, 'top-left')),
          reason: mode.name);
      expect(label, isNot(contains('°')));
      expect(label, isNot(contains('degree')));
      await tester.pumpWidget(const SizedBox.shrink());
    }
    semantics.dispose();
  });

  // Final fix I2: in assessment the readout states only where the marker is;
  // no angle that equals the seating orientation is ever shown or announced.
  testWidgets('assessment never shows or announces the part angle',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _stateAt(2, mode: MissionRuntimeMode.assessment));
    await _tapKey(tester, 'bench-part-cpu');
    for (final corner in const [
      'top-left',
      'top-right',
      'bottom-right',
      'bottom-left',
    ]) {
      if (corner != 'top-left') await _tapKey(tester, 'bench-rotate');
      expect(
          _description(tester),
          MissionContentData.benchMarkerPosition(
              MissionContentData.benchMarkerTriangle, corner));
      final rotate = tester
          .getSemantics(find.byKey(const ValueKey('bench-rotate')))
          .label;
      final preview = tester
          .getSemantics(find.byKey(const ValueKey('bench-part-preview')))
          .label;
      for (final text in [_description(tester), rotate, preview]) {
        expect(text, isNot(contains('°')), reason: text);
        expect(text, isNot(matches(RegExp(r'\d+ degrees?$|turned \d'))),
            reason: text);
      }
      expect(rotate, contains(corner));
    }
    semantics.dispose();
  });

  testWidgets('practice keeps the angle beside the marker position',
      (tester) async {
    await _pump(tester, _stateAt(2));
    await _tapKey(tester, 'bench-part-cpu');
    expect(
        _description(tester),
        MissionContentData.benchMarkerDescription(
            MissionContentData.benchMarkerTriangle, 'top-left', 90));
  });

  // Flutter-sim m5: assessment never coaches the next move.
  testWidgets('assessment shows a neutral note when a part is picked up',
      (tester) async {
    await _pump(tester, _stateAt(2, mode: MissionRuntimeMode.assessment));
    await _tapKey(tester, 'bench-part-cooler');
    final note = tester
        .widget<Text>(find.byKey(const ValueKey('assembly-bench-information')))
        .data!;
    expect(note, MissionContentData.benchSelectedNeutral('CPU cooler'));
    expect(note, isNot(contains('rotate')));
    expect(note, isNot(contains('tap where')));
  });

  // Flutter-sim m1: an occupied slot's tile says what it holds and does not
  // spend an attempt.
  testWidgets('an occupied slot tile names its module and is disabled',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final harness =
        await _pump(tester, _stateAt(2, mode: MissionRuntimeMode.assessment));
    await _tapKey(tester, 'bench-operation-open_dimm_latches');
    await _tapKey(tester, 'bench-part-ram_1');
    await _tapKey(tester, 'bench-rotate');
    await _tapKey(tester, 'bench-rotate');
    await _tapKey(tester, 'bench-slot-chip-dimm_a2');
    expect(harness.controller.state.placements['ram_1'], 'dimm_a2');
    await _tapKey(tester, 'bench-part-ram_2');
    final chip = find.byKey(const ValueKey('bench-slot-chip-dimm_a2'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    expect(tester.getSemantics(chip).label,
        MissionContentData.benchSlotSemantics('DIMM_A2', 'Memory module 1'));
    expect(_enabled(tester, 'bench-slot-chip-dimm_a2'), isFalse);
    final before = harness.transport.actions.length;
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(harness.transport.actions, hasLength(before),
        reason: 'no refused attempt is recorded');
    semantics.dispose();
  });

  // Final fix I4: memory slot targets never overlap, in any view.
  test('memory slot targets never overlap each other', () {
    const dimms = ['dimm_a1', 'dimm_a2', 'dimm_b1', 'dimm_b2'];
    for (final view in const [BenchView.board, BenchView.chassis]) {
      for (var i = 0; i < dimms.length; i++) {
        for (var j = i + 1; j < dimms.length; j++) {
          final a = AssemblyBenchLayout.target(dimms[i], view)!;
          final b = AssemblyBenchLayout.target(dimms[j], view)!;
          // Neighbours share an edge (one pitch wide each); any overlap is
          // floating-point rounding only (the old case view overlapped by
          // about 56 canvas units).
          expect(a.intersect(b).width, lessThanOrEqualTo(1e-6),
              reason: '${dimms[i]} and ${dimms[j]} in ${view.name}');
          expect(a.contains(AssemblyBenchLayout.slot(dimms[i], view)!.center),
              isTrue);
        }
      }
    }
  });

  for (final size in const [
    Size(360, 640),
    Size(412, 915),
    Size(640, 360),
    Size(1280, 800),
  ]) {
    testWidgets('a module dragged in the case view lands in the aimed slot '
        'at $size', (tester) async {
      final harness = await _pump(tester, _stateAt(5), size: size);
      await _tapKey(tester, 'bench-operation-open_dimm_latches');
      await _tapKey(tester, 'bench-part-ram_1');
      await _tapKey(tester, 'bench-remove');
      expect(harness.controller.state.placements.containsKey('ram_1'), isFalse);
      await _tapKey(tester, 'bench-part-ram_1');
      await _tapKey(tester, 'bench-rotate');
      await _tapKey(tester, 'bench-rotate');
      await _tapKey(tester, 'bench-cancel');
      expect(find.byKey(const ValueKey('bench-scene-chassis-coc1_m2_p5')),
          findsOneWidget, reason: 'the drag starts in the case view');
      final chip = find.byKey(const ValueKey('bench-part-ram_1'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      final start = tester.getCenter(chip);
      final gesture =
          await tester.startGesture(start, kind: PointerDeviceKind.touch);
      for (var i = 1; i <= 6; i++) {
        await gesture.moveTo(start + Offset(0, -8.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final slot = find.byKey(const ValueKey('bench-slot-dimm_a2'));
      final aimed = tester.getCenter(slot);
      for (final other in const ['dimm_a1', 'dimm_b1', 'dimm_b2']) {
        expect(
            tester
                .getRect(find.byKey(ValueKey('bench-slot-$other')))
                .contains(aimed),
            isFalse,
            reason: '$other does not cover the centre of DIMM_A2');
      }
      await gesture.moveTo(aimed);
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(harness.controller.state.placements['ram_1'], 'dimm_a2');
      expect(harness.lastValue('placement_attempted')?['destination_id'],
          'dimm_a2');
      expect(harness.lastValue('placement_attempted')?['simulation_valid'],
          isNot(false));
    });
  }

  // QA Q6: assessment never shows a bench step title (they name the
  // expected slots and headers, e.g. "the manual specifies DIMM_A2 and
  // DIMM_B2"); practice does.
  testWidgets('assessment shows no bench step title in any phase',
      (tester) async {
    final semantics = tester.ensureSemantics();
    for (var number = 1; number <= 5; number++) {
      final phase = _phase(number);
      final labels = [
        for (final step in phase.presentation['bench_steps'] as List)
          (step as Map)['label'] as String,
      ];
      // A step named exactly like a tray control (every operation of the
      // phase is listed there, in both modes) is the control's own name.
      final equipment = phase.presentation['equipment'] as Map? ?? const {};
      final controls = {
        for (final operation in equipment['operations'] as List? ?? const [])
          (operation as Map)['label'] as String,
      };
      await _pump(tester, _stateAt(number, mode: MissionRuntimeMode.assessment));
      expect(find.textContaining(RegExp(r'Step \d+ of \d+'), skipOffstage: false),
          findsNothing,
          reason: '${phase.id}: no step position in assessment');
      for (final label in labels.where((label) => !controls.contains(label))) {
        expect(find.textContaining(label, skipOffstage: false), findsNothing,
            reason: '${phase.id}: $label');
        expect(find.bySemanticsLabel(RegExp(RegExp.escape(label))),
            findsNothing,
            reason: '${phase.id} semantics: $label');
      }
      expect(find.text(MissionContentData.benchAssessmentHeader),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, _stateAt(number));
      expect(find.textContaining(labels.first, skipOffstage: false),
          findsWidgets,
          reason: 'practice shows the step (${phase.id})');
      await tester.pumpWidget(const SizedBox.shrink());
    }
    semantics.dispose();
  });

  // QA audit 2026-11-20 (live Android run): the rings drawn on the bench
  // were dead under the slot and header targets, so the lever, the thermal
  // compound and every screw could only be worked from the tray, and a tap
  // on a ring with a part in hand counted as a refused placement.
  group('rings on the bench take their tap', () {
    Future<void> tapRing(WidgetTester tester, String operation) async {
      await tester.tap(find.byKey(ValueKey('bench-hotspot-$operation')));
      await tester.pumpAndSettle();
    }

    int invalid(_Harness harness) =>
        ((harness.controller.state.equipmentState['counts'] as Map?)?['invalid']
            as int?) ??
        0;

    testWidgets('the socket lever and the thermal compound work at their ring',
        (tester) async {
      final harness = await _pump(tester, _stateAt(2));
      await tapRing(tester, 'open_cpu_lever');
      expect(harness.controller.state.equipmentState['cpu_lever'], 'open');
      await _tapKey(tester, 'bench-part-cpu');
      for (var i = 0; i < 3; i++) {
        await _tapKey(tester, 'bench-rotate');
      }
      await _tapKey(tester, 'bench-slot-chip-cpu_socket');
      expect(harness.controller.state.placements['cpu'], 'cpu_socket');
      await tapRing(tester, 'close_cpu_lever');
      expect(harness.controller.state.equipmentState['cpu_lever'], 'closed');
      await tapRing(tester, 'apply_thermal_compound');
      expect(
          harness.controller.state.equipmentState['thermal_compound'], isTrue);
      expect(find.byKey(const ValueKey('bench-hotspot-apply_thermal_compound')),
          findsNothing,
          reason: 'applied compound leaves no ring to work again');
      final paste =
          tester.getRect(find.byKey(const ValueKey('bench-thermal-compound')));
      expect(
          tester
              .getRect(find.byKey(const ValueKey('bench-placed-cpu')))
              .contains(paste.center),
          isTrue,
          reason: 'the compound dot sits over the seated processor photograph');
      expect(_enabled(tester, 'bench-operation-apply_thermal_compound'), isTrue,
          reason: 'the tray still lists the operation');
      expect(invalid(harness), 0);
    });

    testWidgets(
        'a ring tapped with a part in hand works the ring, not a placement',
        (tester) async {
      final harness = await _pump(tester, _stateAt(2));
      await _tapKey(tester, 'bench-part-cpu');
      await tapRing(tester, 'open_cpu_lever');
      expect(harness.controller.state.equipmentState['cpu_lever'], 'open');
      expect(harness.lastValue('placement_attempted'), isNull,
          reason: 'the lever tap is not a CPU drop');
      expect(invalid(harness), 0);
      expect(find.byKey(const ValueKey('bench-rotate')), findsOneWidget,
          reason: 'the processor stays in hand for the next move');
    });

    testWidgets('screws are fastened at the ring over their bay',
        (tester) async {
      final harness = await _pump(tester, _stateAt(3));
      await _tapKey(tester, 'bench-part-psu');
      await _tapKey(tester, 'bench-rotate');
      await _tapKey(tester, 'bench-rotate');
      await _tapKey(tester, 'bench-slot-chip-psu_bay');
      expect(harness.controller.state.placements['psu'], 'psu_bay');
      await _tapKey(tester, 'bench-operation-pick_screwdriver');
      await tapRing(tester, 'fasten_psu');
      expect(harness.controller.state.equipmentState['psu_fastened'], isTrue);
      expect(
          find.byKey(const ValueKey('bench-hotspot-fasten_psu')), findsNothing);
      expect(invalid(harness), 0);
    });

    testWidgets('a drop that misses every slot says where to release the part',
        (tester) async {
      final harness = await _pump(tester, _stateAt(2));
      final part = find.byKey(const ValueKey('bench-part-cpu'));
      await tester.ensureVisible(part);
      await tester.pumpAndSettle();
      final scene = tester.getRect(find.byType(SimulationScene));
      final from = tester.getCenter(part);
      // Straight up, then into the empty top-left corner of the bench.
      final gesture = await tester.startGesture(from);
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      await gesture.moveTo(scene.topLeft + const Offset(14, 70));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(harness.controller.state.placements.containsKey('cpu'), isFalse);
      expect(harness.lastValue('placement_attempted'), isNull);
      expect(find.text(MissionContentData.benchDropOnTarget), findsOneWidget);
    });

    testWidgets('the mat ground stud explains itself before the strap is on',
        (tester) async {
      final harness = await _pump(tester, _stateAt(1));
      await tester.tap(find
          .byKey(const ValueKey('bench-hotspot-blocked-ground_wrist_strap')));
      await tester.pumpAndSettle();
      expect(find.textContaining('is not possible yet'), findsOneWidget);
      expect(harness.lastValue('equipment_operation'), isNull,
          reason: 'nothing is recorded for a tap that changes nothing');
      expect(
          harness.controller.state.equipmentState['esd_grounded'], isNot(true));
      await _tapKey(tester, 'bench-operation-wear_wrist_strap');
      expect(find.byKey(const ValueKey('bench-hotspot-wear_wrist_strap')),
          findsNothing,
          reason: 'the worn strap has no ring left');
      await tapRing(tester, 'ground_wrist_strap');
      expect(harness.controller.state.equipmentState['esd_grounded'], isTrue);
    });

    testWidgets('a screen-reader tap on a bench slot places the part in hand',
        (tester) async {
      // A semantic tap carries no pointer position, so it must never be
      // routed to a ring that happens to overlap the slot (the thermal
      // compound ring sits over the cooler mount).
      final semantics = tester.ensureSemantics();
      final harness = await _pump(tester, _stateAt(2));
      Future<void> semanticTap(String key) async {
        final finder = find.byKey(ValueKey(key)).first;
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        final node = tester.getSemantics(finder);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
            reason: '$key has a semantic tap action');
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
      }

      await tapRing(tester, 'open_cpu_lever');
      await _tapKey(tester, 'bench-part-cpu');
      for (var i = 0; i < 3; i++) {
        await _tapKey(tester, 'bench-rotate');
      }
      await semanticTap('bench-slot-cpu_socket');
      expect(harness.controller.state.placements['cpu'], 'cpu_socket');
      await tapRing(tester, 'close_cpu_lever');
      expect(find.byKey(const ValueKey('bench-hotspot-apply_thermal_compound')),
          findsOneWidget,
          reason: 'the compound ring is live over the socket');
      await _tapKey(tester, 'bench-part-cooler');
      await semanticTap('bench-slot-cooler_mount');
      expect(harness.lastValue('placement_attempted')?['destination_id'],
          'cooler_mount',
          reason: 'the semantic tap is a cooler placement');
      expect(harness.controller.state.equipmentState['thermal_compound'],
          isNot(true),
          reason: 'the compound ring was not worked by the slot tap');
      semantics.dispose();
    });
  });
}
