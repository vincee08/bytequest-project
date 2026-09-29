import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/data/missions_data.dart';
import 'package:bytequest/screens/simulation/components/simulation_scene.dart';
import 'package:bytequest/screens/simulation/mission_simulation_screen.dart';
import 'package:bytequest/screens/simulation/runtime/mission_equipment_simulator.dart';
import 'package:bytequest/screens/simulation/runtime/mission_evidence_gateway.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_action_reducer.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_controller.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:bytequest/services/practice_mission_evidence_service.dart';
import 'package:bytequest/services/progress_resume_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../test/support/equipment_practice_driver.dart';
import '../test/support/equipment_widget_driver.dart';

/// Run with scripts/android-mission-runtime-e2e.ps1. Uses disposable local
/// learner credentials only. Two invocations exercise a real app restart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const stage = String.fromEnvironment('BQ_E2E_STAGE', defaultValue: 'save');
  const missionFilter = String.fromEnvironment('BQ_E2E_MISSION');
  const url = String.fromEnvironment('BQ_E2E_URL');
  const key = String.fromEnvironment('BQ_E2E_ANON_KEY');
  const email = String.fromEnvironment('BQ_E2E_EMAIL');
  const password = String.fromEnvironment('BQ_E2E_PASSWORD');
  late SharedPreferences preferences;

  setUpAll(() async {
    final endpoint = Uri.parse(url);
    if (!['10.0.2.2', '127.0.0.1', 'localhost'].contains(endpoint.host) ||
        endpoint.port != 57321) {
      throw StateError('This suite refuses a non-local backend.');
    }
    await Supabase.initialize(url: url, publishableKey: key);
    await Supabase.instance.client.auth
        .signInWithPassword(email: email, password: password);
    preferences = await SharedPreferences.getInstance();
  });
  tearDownAll(() async {
    await Supabase.instance.client.auth.signOut();
  });

  for (final definition in MissionSimulationDefinitions.all.where(
    (definition) => missionFilter.isEmpty || definition.id == missionFilter,
  )) {
    testWidgets(
        '${definition.id}: $stage real UI, database evidence and restart checkpoint',
        (tester) async {
      final service = PracticeMissionEvidenceService(missionId: definition.id);
      final initial = MissionRuntimeState.initial(definition.id)
          .copyWith(currentPhaseId: definition.phases.first.id);
      final controller = MissionRuntimeController(
        userId: Supabase.instance.client.auth.currentUser!.id,
        initialState: initial,
        store: const SharedPreferencesMissionRuntimeStore(),
        evidenceGateway: MissionEvidenceGateway(transport: service),
        restoreReducer: MissionRuntimeActionReducer(definition),
        submissionPhaseIds: {definition.phases.last.id},
      );
      final before = await service.readAcknowledgedActions();
      final captureKey = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: MissionSimulationScreen(
                key: ValueKey('$stage-${definition.id}'),
                mission: MissionsData.getMissionById(definition.id)!,
                definition: definition,
                controller: controller,
              ))));
      await waitForEquipmentState(
          tester, () => find.byType(SimulationScene).evaluate().isNotEmpty);
      await _capture(tester, captureKey, '${definition.id}-$stage-start');
      if (stage == 'resume') {
        final saved = preferences.getString('bq-e2e-${definition.id}');
        expect(saved, isNotNull,
            reason: 'No checkpoint from the preceding app process.');
        final expected = MissionRuntimeState.fromJson(
            jsonDecode(saved!) as Map<String, dynamic>);
        expect(controller.state.currentPhaseId, expected.currentPhaseId);
        expect(
            controller.state.configurationValues, expected.configurationValues);
        expect(
            controller.state.connectedNodePairs, expected.connectedNodePairs);
        expect(controller.state.placements, expected.placements);
        expect(controller.state.equipmentState, expected.equipmentState);
        expect(
            controller.state.acceptedEvidenceIds, expected.acceptedEvidenceIds);
        expect((await service.readAcknowledgedActions()).length, before.length,
            reason: 'Restoring must not duplicate evidence.');
      }

      final plan = EquipmentPracticeDriver(definition);
      for (final phase in definition.phases) {
        plan.complete(phase);
      }
      const start = stage == 'save' ? 0 : 2;
      final end = stage == 'save' ? 2 : definition.phases.length - 1;
      for (var index = start; index < end; index++) {
        final phase = definition.phases[index];
        debugPrint('BQ-E2E ${definition.id}/$stage start ${phase.id}');
        expect(controller.state.currentPhaseId, phase.id);
        for (final action
            in plan.actions.where((action) => action.phaseId == phase.id)) {
          debugPrint(
            'BQ-E2E ${definition.id}/$stage action '
            '${phase.id}/${action.actionType}/${action.target}',
          );
          await performEquipmentAction(tester, phase, action, controller);
          debugPrint(
            'BQ-E2E ${definition.id}/$stage accepted '
            '${phase.id}/${action.actionType}',
          );
          expect(tester.takeException(), isNull,
              reason: '${phase.id}/${action.actionType}');
        }
        final next = find.byKey(const ValueKey('mission-next'));
        expect(tester.widget<FilledButton>(next).onPressed, isNotNull,
            reason: phase.id);
        await tapEquipmentControl(tester, next);
        await waitForEquipmentState(
            tester,
            () =>
                controller.state.currentPhaseId ==
                definition.phases[index + 1].id);
        debugPrint('BQ-E2E ${definition.id}/$stage advanced ${phase.id}');
      }
      await controller.persist();
      await _capture(tester, captureKey, '${definition.id}-$stage-checkpoint');
      expect(controller.state.pendingEvidence, isEmpty);
      final records = await service.readAcknowledgedActions();
      expect(records.length, controller.state.acceptedEvidenceIds.length);
      expect(
          records.map((record) => record.action.clientActionId).toSet().length,
          records.length);
      // A transport retry must retain exactly one accepted row.
      await service.append(records.last.action);
      expect((await service.readAcknowledgedActions()).length, records.length);

      if (stage == 'save') {
        await preferences.setString(
            'bq-e2e-${definition.id}', jsonEncode(controller.state.toJson()));
      } else {
        expect(
            MissionEquipmentSimulator.readyForReview(
                definition, controller.state),
            true);
        await tapEquipmentControl(tester, find.text('Confirm evidence'));
        await waitForEquipmentState(
            tester,
            () => find
                .text(
                    'Practice evidence saved. Official competency is unchanged.')
                .evaluate()
                .isNotEmpty);
      }
      final attempts = await Supabase.instance.client
          .from('attempts')
          .select('id')
          .eq('learner_id', Supabase.instance.client.auth.currentUser!.id);
      expect(attempts, isEmpty,
          reason: 'Practice must not initiate official evaluation.');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }, timeout: const Timeout(Duration(minutes: 4)));
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.5);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${Directory.systemTemp.path}/bq-qa-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  } finally {
    image.dispose();
  }
}
