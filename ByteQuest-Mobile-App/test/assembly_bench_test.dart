import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/models/mission_model.dart';
import 'package:bytequest/screens/simulation/components/assembly/assembly_bench.dart';
import 'package:bytequest/screens/simulation/components/assembly/assembly_bench_layout.dart';
import 'package:bytequest/screens/simulation/components/simulation_scene.dart';
import 'package:bytequest/screens/simulation/mission_simulation_screen.dart';
import 'package:bytequest/screens/simulation/runtime/mission_evidence_gateway.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_controller.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:bytequest/services/progress_resume_service.dart';
import 'package:flutter/material.dart';
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
}
