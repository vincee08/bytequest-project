import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/models/mission_model.dart';
import 'package:bytequest/screens/simulation/components/assembly/assembly_bench.dart';
import 'package:bytequest/screens/simulation/components/equipment_workspace.dart';
import 'package:bytequest/screens/simulation/components/mission_guidance_panel.dart';
import 'package:bytequest/screens/simulation/components/simulation_scene.dart';
import 'package:bytequest/screens/simulation/mission_simulation_screen.dart';
import 'package:bytequest/screens/simulation/runtime/mission_evidence_gateway.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_controller.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:bytequest/services/authoritative_assessment_service.dart';
import 'package:bytequest/services/progress_resume_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/equipment_practice_driver.dart';

// Practice vs Assessment for every production mission (re-defense slice A1):
// assessment hides guidance, tutorials and compatible-slot highlights, keeps
// the equipment interactive, submits only after confirmation, and refuses a
// package published from a different definition version.

class _RecordingTransport implements MissionEvidenceTransport {
  final actions = <MissionEvidenceAction>[];

  @override
  Future<void> append(MissionEvidenceAction action) async => actions.add(action);

  @override
  Future<List<AcknowledgedMissionEvidenceAction>>
      readAcknowledgedActions() async => [];
}

MissionRuntimeState _assessment(MissionRuntimeState state) =>
    MissionRuntimeState.fromJson({
      ...state.toJson(),
      'mode': 'assessment',
      'assessmentAttemptId': 'attempt-qa',
    });

var _harnessCount = 0;

class _Harness {
  _Harness(this.definition, {this.learnerPayload = const {}});

  final MissionSimulationDefinition definition;
  final Map<String, dynamic> learnerPayload;
  final transport = _RecordingTransport();
  final String userId = 'assessment-qa-${_harnessCount++}';
  late final controller = MissionRuntimeController(
    userId: userId,
    initialState: _assessment(MissionRuntimeState.initial(definition.id)
        .copyWith(currentPhaseId: definition.phases.first.id)),
    store: const SharedPreferencesMissionRuntimeStore(),
    evidenceGateway: MissionEvidenceGateway(transport: transport),
    submissionPhaseIds: {definition.phases.last.id},
  );
  int submissions = 0;

  Widget app() => MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: MissionSimulationScreen(
          mission: Mission(
              id: definition.id,
              cocId: definition.cocId,
              missionCode: definition.id.toUpperCase(),
              missionNumber: int.parse(definition.id.substring(6)),
              title: definition.title,
              missionType: MissionType.identification,
              orderIndex: int.parse(definition.id.substring(6))),
          definition: definition,
          learnerPayload: learnerPayload,
          controller: controller,
          onSubmit: () async => submissions++,
        ),
      );
}

Future<_Harness> _pump(WidgetTester tester, _Harness harness) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(harness.app());
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('requiresAppUpdate', () {
    const current = MissionSimulationDefinitions.coc1M2AssemblyContractVersion;
    Map<String, dynamic> payload(Object? version) => {
          'mission_id': 'coc1_m2',
          'definition_version': version,
          'mode': 'assessment',
        };

    test('accepts a simulation assessment of the installed definition', () {
      expect(AuthoritativeAssessmentService.requiresAppUpdate(payload(current)),
          isFalse);
      expect(
          AuthoritativeAssessmentService.requiresAppUpdate({
            'mission_id': 'coc2_m1',
            'definition_version': 'css-sag-20261011-v2',
            'mode': 'assessment',
          }),
          isFalse);
    });

    test('refuses another, missing or unknown definition version', () {
      expect(
          AuthoritativeAssessmentService.requiresAppUpdate(
              payload('css-sag-20261011-v2')),
          isTrue);
      expect(AuthoritativeAssessmentService.requiresAppUpdate(payload(null)),
          isTrue);
      expect(
          AuthoritativeAssessmentService.requiresAppUpdate(
              {...payload(current), 'mission_id': 'coc9_m9'}),
          isTrue);
    });

    test('ignores form-based packages and non-assessment payloads', () {
      expect(
          AuthoritativeAssessmentService.requiresAppUpdate(
              {'mode': 'assessment', 'simulation_template': 'coc1_m2_enhanced'}),
          isFalse);
      expect(
          AuthoritativeAssessmentService.requiresAppUpdate(
              {'assessment_package_id': 'legacy-package'}),
          isFalse);
    });
  });

  testWidgets('a package from another definition version asks for an update',
      (tester) async {
    final definition = MissionSimulationDefinitions.byId('coc1_m2');
    final stale = await _pump(
        tester,
        _Harness(definition, learnerPayload: {
          'mission_id': 'coc1_m2',
          'definition_version': 'css-sag-20261011-v2',
          'mode': 'assessment',
        }));
    expect(find.text(MissionContentData.assessmentUpdateRequired),
        findsOneWidget);
    expect(find.byType(AssemblyBench), findsNothing);
    expect(stale.transport.actions, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await _pump(
        tester,
        _Harness(definition, learnerPayload: {
          'mission_id': 'coc1_m2',
          'definition_version':
              MissionSimulationDefinitions.coc1M2AssemblyContractVersion,
          'mode': 'assessment',
        }));
    expect(find.text(MissionContentData.assessmentUpdateRequired),
        findsNothing);
    expect(find.byType(AssemblyBench), findsOneWidget);
  });

  for (final definition in MissionSimulationDefinitions.all) {
    testWidgets(
        '${definition.id}: assessment hides guidance and submits only after '
        'confirmation', (tester) async {
      final harness = await _pump(tester, _Harness(definition));
      expect(find.byType(MissionGuidanceBar), findsNothing);
      expect(find.byKey(const ValueKey('mission-tutorial-panel')),
          findsNothing);
      expect(find.byKey(const ValueKey('assessment-bar')), findsOneWidget);

      await _tapKey(tester, 'assessment-submit');
      await _tapKey(tester, 'assessment-submit-cancel');
      expect(harness.submissions, 0);
      await _tapKey(tester, 'assessment-submit');
      await _tapKey(tester, 'assessment-submit-confirm');
      expect(harness.submissions, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final assessment in [false, true]) {
    testWidgets(
        '${assessment ? 'assessment' : 'practice'} placement '
        '${assessment ? 'stays interactive without' : 'shows'} '
        'compatible-slot highlights', (tester) async {
      final definition = MissionSimulationDefinitions.byId('coc3_m2');
      final driver = EquipmentPracticeDriver(definition);
      if (assessment) driver.state = _assessment(driver.state);
      final phase = definition.phases.first;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, refresh) => EquipmentWorkspace(
              definition: definition,
              phase: phase,
              state: driver.state,
              hotspotStates: driver.state.hotspotStates,
              enabled: true,
              saving: false,
              onCameraChanged: (_, __) {},
              onAction: (type, target, value) async {
                driver.act(phase, type, target, value);
                refresh(() {});
              },
            ),
          ),
        ),
      ));
      await _tapKey(tester, 'workspace-source-server_node');
      final highlighted = tester
          .widget<SimulationScene>(find.byType(SimulationScene))
          .hotspotStates['destination:server_node_position'];
      expect(highlighted, assessment ? isNull : HotspotVisualState.selected);

      await _tapKey(tester, 'workspace-destination-server_node_position');
      expect(driver.state.placements['server_node'], 'server_node_position');
      expect(tester.takeException(), isNull);
    });
  }
}
