import 'dart:async';

import 'package:bytequest/data/mission_lab_phases.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/data/mission_phase_guidance.dart';
import 'package:bytequest/models/mission_model.dart';
import 'package:bytequest/screens/simulation/components/simulation_scene.dart';
import 'package:bytequest/screens/simulation/components/mission_tutorial_panel.dart';
import 'package:bytequest/screens/simulation/interactions/mission_interactions.dart';
import 'package:bytequest/screens/simulation/mission_simulation_screen.dart';
import 'package:bytequest/screens/simulation/runtime/mission_evidence_gateway.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_controller.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:bytequest/services/progress_resume_service.dart';
import 'package:bytequest/services/practice_coc_session_service.dart';
import 'package:bytequest/screens/simulation/components/labs/mission_labs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/equipment_practice_driver.dart';
import 'support/equipment_widget_driver.dart';
import 'support/mission_lab_driver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('timed practice starts explicitly and restores the same deadline',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final definition = MissionSimulationDefinitions.byId('coc4_m1');
    final controller = _controller(definition);
    await tester.pumpWidget(_host(definition,
        controller: controller,
        timedPractice: true,
        practiceUserId: 'timer-learner'));
    await tester.pumpAndSettle();
    expect(find.text(MissionContentData.practiceTimerStart), findsOneWidget);
    expect(find.byKey(const ValueKey('mission-next')), findsNothing);
    await tester.tap(find.text(MissionContentData.practiceTimerStart));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('practice-coc-time-label')), findsOneWidget);
    final first =
        await const PracticeCocSessionService().load('timer-learner', 'coc4');
    expect(first, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_host(definition,
        controller: _controller(definition),
        timedPractice: true,
        practiceUserId: 'timer-learner'));
    await tester.pumpAndSettle();
    final restored =
        await const PracticeCocSessionService().load('timer-learner', 'coc4');
    expect(restored!.deadlineUtc, first!.deadlineUtc);
    expect(
        find.byKey(const ValueKey('practice-coc-time-label')), findsOneWidget);
  });

  testWidgets('expired COC session blocks controls but preserves evidence',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final definition = MissionSimulationDefinitions.byId('coc4_m1');
    final controller = _controller(definition);
    await const PracticeCocSessionService().start('expired-learner', 'coc4',
        now: DateTime.now().toUtc().subtract(const Duration(minutes: 61)));
    await tester.pumpWidget(_host(definition,
        controller: controller,
        timedPractice: true,
        practiceUserId: 'expired-learner'));
    await tester.pumpAndSettle();
    expect(find.textContaining(MissionContentData.practiceTimerExpired),
        findsWidgets);
    expect(find.byKey(const ValueKey('mission-next')), findsNothing);
    expect(controller.state.pendingEvidence, isEmpty);
    expect(controller.state.placements, isEmpty);
  });

  testWidgets('Show me where scrolls to the actual off-screen scene object',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'bq_mission_tutorial_seen_locator-learner': true,
    });
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final definition = MissionSimulationDefinitions.byId('coc1_m1');
    final phase = definition.phases.first;
    final objects = (phase.presentation['objects'] as List)
        .whereType<Map>()
        .map((item) => item['id'] as String)
        .toList();
    final last = objects.last;
    final state = MissionRuntimeState.initial(definition.id).copyWith(
      currentPhaseId: phase.id,
      hotspotStates: {
        for (final id in objects.take(objects.length - 1))
          id: HotspotVisualState.completed,
      },
    );
    final controller = _controller(definition, initialState: state);
    await tester.pumpWidget(_host(definition,
        controller: controller, practiceUserId: 'locator-learner'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Full remaining-action details are disclosed from the compact status
    // control, leaving the workspace available for equipment.
    await tester.tap(find.byKey(const ValueKey('mission-task-status')));
    await tester.pumpAndSettle();
    expect(
        find.textContaining(
            'Cannot continue yet: ${objects.length - 1} of ${objects.length} '
            'required actions complete'),
        findsOneWidget);
    await tester.tap(find.text(MissionContentData.backLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mission-show-me-how')));
    await tester.pumpAndSettle();
    expect(find.byType(SimulationScene), findsOneWidget);
    expect(
        tester
            .widget<SimulationScene>(find.byType(SimulationScene))
            .highlightObjectId,
        last);
    final workspaceScroll =
        find.byKey(const ValueKey('simulation-workspace-scroll'));
    expect(
        tester
            .state<ScrollableState>(find
                .descendant(
                    of: workspaceScroll, matching: find.byType(Scrollable))
                .first)
            .position
            .pixels,
        greaterThan(0));
    expect(controller.state.acceptedEvidenceIds, isEmpty);
    await tester.ensureVisible(find.byKey(ValueKey('inspect-target-$last')));
    await tester.tap(find.byKey(ValueKey('inspect-target-$last')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('mission-next')))
            .onPressed,
        isNotNull);
    expect(find.text(MissionContentData.guideReadyToContinue), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Show me where outlines selection controls without blocking taps',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'bq_mission_tutorial_seen-selection-learner': true,
    });
    final definition = MissionSimulationDefinitions.byId('coc1_m1');
    final phase = definition.phases[1];
    final controller = _controller(definition,
        initialState: MissionRuntimeState.initial(definition.id)
            .copyWith(currentPhaseId: phase.id));
    await tester.pumpWidget(_host(definition,
        controller: controller, practiceUserId: 'selection-learner'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mission-show-me-how')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mission-guide-outline')), findsOneWidget);
    final controlsScroll =
        find.byKey(const ValueKey('mission-controls-scroll'));
    final firstOption = (phase.presentation['options'] as List).first as Map;
    final option = find.byKey(ValueKey('multi-select-${firstOption['id']}'));
    expect(tester.getRect(controlsScroll).contains(tester.getCenter(option)),
        isTrue,
        reason:
            'The outlined control must be visible, whether or not scrolling was needed.');
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pump();
    expect(tester.widget<MissionSelectableActionCard>(option).selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first-use tutorial can be skipped, persisted, and replayed',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final definition = MissionSimulationDefinitions.byId('coc4_m1');
    final first = _controller(definition);
    await tester.pumpWidget(
        _host(definition, controller: first, practiceUserId: 'tour-learner'));
    await tester.pumpAndSettle();
    expect(find.byType(MissionTutorialPanel), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mission-tutorial-skip')));
    await tester.pumpAndSettle();
    expect(find.byType(MissionTutorialPanel), findsNothing);
    expect(await ProgressResumeService.missionTutorialSeen('tour-learner'),
        isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_host(definition,
        controller: _controller(definition), practiceUserId: 'tour-learner'));
    await tester.pumpAndSettle();
    expect(find.byType(MissionTutorialPanel), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mission-replay-tutorial')));
    await tester.pumpAndSettle();
    expect(find.byType(MissionTutorialPanel), findsOneWidget);
    final tutorial =
        tester.widget<MissionTutorialPanel>(find.byType(MissionTutorialPanel));
    expect(tutorial.steps, contains(MissionContentData.tutorialWorkspace));
    expect(
        tutorial.steps, isNot(contains(MissionContentData.tutorialPlacement)));
    expect(first.state.acceptedEvidenceIds, isEmpty);
    for (var step = 0; step < tutorial.steps.length; step++) {
      await tester.tap(find.byKey(const ValueKey('mission-tutorial-next')));
      await tester.pumpAndSettle();
    }
    expect(find.byType(MissionTutorialPanel), findsNothing);
  });

  for (final size in const [Size(320, 568), Size(800, 360)]) {
    testWidgets(
        'first-use tutorial keeps workspace and Continue usable at $size',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final definition = MissionSimulationDefinitions.byId('coc1_m1');
      await tester.pumpWidget(_host(definition,
          controller: _controller(definition),
          practiceUserId: 'compact-tour-${size.width}',
          textScale: 2));
      await tester.pumpAndSettle();
      expect(find.byType(MissionTutorialPanel), findsOneWidget);
      expect(find.byType(SimulationScene), findsOneWidget);
      expect(find.byKey(const ValueKey('mission-next')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester
          .ensureVisible(find.byKey(const ValueKey('mission-tutorial-start')));
      await tester.tap(find.byKey(const ValueKey('mission-tutorial-start')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester
          .ensureVisible(find.byKey(const ValueKey('mission-tutorial-skip')));
      await tester.tap(find.byKey(const ValueKey('mission-tutorial-skip')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in const [
    Size(320, 568),
    Size(640, 360),
    Size(800, 360),
  ]) {
    testWidgets('all real mission phases fit $size with 2x text',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final definition in MissionSimulationDefinitions.all) {
        final plan = EquipmentPracticeDriver(definition);
        for (final phase in definition.phases) {
          plan.complete(phase);
        }
        for (final phase in definition.phases) {
          final controller = _controller(definition,
              initialState: plan.state.copyWith(currentPhaseId: phase.id));
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
              _host(definition, controller: controller, textScale: 2));
          await tester.pumpAndSettle();
          final lab = MissionLabs.ownsPhase(definition, phase);
          expect(find.byType(SimulationScene),
              lab ? findsNothing : findsOneWidget,
              reason: phase.id);
          expect(find.byKey(const ValueKey('mission-lab')),
              lab ? findsOneWidget : findsNothing,
              reason: phase.id);
          expect(tester.takeException(), isNull,
              reason: '${phase.id} at $size');
        }
      }
    });
  }

  for (final definition in MissionSimulationDefinitions.all) {
    testWidgets(
        '${definition.id}: every work phase completes through touch controls',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _controller(definition);
      await tester.pumpWidget(_host(definition, controller: controller));
      await tester.pumpAndSettle();
      final plan = EquipmentPracticeDriver(definition);
      for (final phase in definition.phases) {
        plan.complete(phase);
      }
      for (var index = 0; index < definition.phases.length - 1; index++) {
        final phase = definition.phases[index];
        if (MissionLabs.ownsPhase(definition, phase)) {
          // A realistic lab owns this phase: do the work in the lab.
          await completeLabPhase(tester, phase);
          expect(tester.takeException(), isNull, reason: phase.id);
        } else {
          for (final action
              in plan.actions.where((action) => action.phaseId == phase.id)) {
            await performEquipmentAction(tester, phase, action, controller);
            expect(tester.takeException(), isNull,
                reason: '${phase.id}/${action.actionType}');
          }
        }
        final next = find.byKey(const ValueKey('mission-next'));
        expect(tester.widget<FilledButton>(next).onPressed, isNotNull,
            reason: phase.id);
        await tapEquipmentControl(tester, next);
        expect(
            controller.state.currentPhaseId, definition.phases[index + 1].id);
        final controlsScrollable = find
            .descendant(
              of: find.byKey(const ValueKey('mission-controls-scroll')),
              matching: find.byType(Scrollable),
            )
            .first;
        expect(
            tester.state<ScrollableState>(controlsScrollable).position.pixels,
            0,
            reason: 'New phase controls must start with visible components');
      }
      expect(find.byType(EvidenceReviewPanel), findsOneWidget);
      expect(controller.state.pendingEvidence, isEmpty);
    });
  }

  group('MissionSimulationScreen', () {
    testWidgets('does not advance before the active interaction is terminal', (
      tester,
    ) async {
      final definition = MissionSimulationDefinitions.byId('coc1_m1');
      final controller = _controller(definition);

      await tester.pumpWidget(_host(definition, controller: controller));
      await tester.pumpAndSettle();

      final nextFinder = find.byKey(const ValueKey('mission-next'));
      final before = tester.widget<FilledButton>(nextFinder);
      expect(before.onPressed, isNull);

      for (final object in const [
        'motherboard',
        'cpu',
        'ram',
        'psu',
        'cpu_socket',
        'dimm_slot',
        'atx_power_port'
      ]) {
        final target = find.byKey(ValueKey('inspect-target-$object'));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      expect(controller.state.placements, isEmpty);
      final after = tester.widget<FilledButton>(nextFinder);
      expect(after.onPressed, isNotNull);
      await tester.ensureVisible(nextFinder);
      await tester.tap(nextFinder);
      await tester.pumpAndSettle();
      expect(controller.state.currentPhaseId, definition.phases[1].id);
    });

    testWidgets(
        'failed evidence save shows an immediate retry without duplication',
        (tester) async {
      final definition = MissionSimulationDefinitions.byId('coc1_m1');
      final store = _MemoryStore()..saveSucceeds = false;
      final transport = _MemoryTransport();
      final controller =
          _controller(definition, store: store, transport: transport);
      await tester.pumpWidget(_host(definition, controller: controller));
      await tester.pumpAndSettle();
      final target = find.byKey(const ValueKey('inspect-target-motherboard'));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(SnackBar),
              matching:
                  find.text(MissionContentData.technicalEvidenceSyncFailed)),
          findsOneWidget);
      final actionId = controller.state.pendingEvidence.single.clientActionId;
      store.saveSucceeds = true;
      await tester.tap(find.byType(SnackBarAction));
      await tester.pumpAndSettle();
      expect(controller.state.pendingEvidence, isEmpty);
      expect(transport.appendedIds, [actionId]);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'failed phase save retries the pending action instead of advancing again',
        (tester) async {
      final definition = MissionSimulationDefinitions.byId('coc1_m1');
      final plan = EquipmentPracticeDriver(definition)
        ..complete(definition.phases.first);
      final store = _MemoryStore()..saveSucceeds = false;
      final transport = _MemoryTransport();
      final controller = _controller(definition,
          store: store,
          transport: transport,
          initialState:
              plan.state.copyWith(currentPhaseId: definition.phases.first.id));
      await tester.pumpWidget(_host(definition, controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mission-next')));
      await tester.pumpAndSettle();
      final actionId = controller.state.pendingEvidence.single.clientActionId;
      expect(controller.state.currentPhaseId, definition.phases[1].id);
      store.saveSucceeds = true;
      await tester.tap(find.byType(SnackBarAction));
      await tester.pumpAndSettle();
      expect(controller.state.currentPhaseId, definition.phases[1].id);
      expect(controller.state.pendingEvidence, isEmpty);
      expect(transport.appendedIds, [actionId]);
      expect(transport.appendedActions.single.actionType, 'phase_completed');
      expect(tester.takeException(), isNull);
    });

    testWidgets('restores before exposing the interactive workspace', (
      tester,
    ) async {
      final definition = MissionSimulationDefinitions.byId('coc1_m1');
      final store = _MemoryStore()..loadGate = Completer<void>();

      await tester.pumpWidget(
        _host(definition, controller: _controller(definition, store: store)),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(SimulationScene), findsNothing);

      store.loadGate!.complete();
      await tester.pumpAndSettle();

      expect(find.byType(SimulationScene), findsOneWidget);
      expect(store.saveCount, 0);
    });

    testWidgets('unknown restored phase fails closed and can reset safely', (
      tester,
    ) async {
      final definition = MissionSimulationDefinitions.byId('coc1_m1');
      final store = _MemoryStore()
        ..saved = MissionRuntimeState.initial(
          definition.id,
        ).copyWith(currentPhaseId: 'removed-catalog-phase');

      await tester.pumpWidget(
        _host(definition, controller: _controller(definition, store: store)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TechnicalUnavailableState), findsOneWidget);
      expect(find.byType(TapInspectInteraction), findsNothing);

      await tester.tap(find.text('Reset saved progress'));
      await tester.pumpAndSettle();
      expect(store.clearCount, 0);
      await tester.tap(find.text(MissionContentData.discardProgressLabel));
      await tester.pumpAndSettle();

      expect(store.clearCount, 1);
      expect(find.byType(TechnicalUnavailableState), findsNothing);
      expect(find.byType(TapInspectInteraction), findsOneWidget);
    });

    testWidgets(
      'keeps the scene visible and controls scrollable at target sizes',
      (tester) async {
        final definition = MissionSimulationDefinitions.byId('coc1_m1');
        for (final size in const [
          Size(360, 800),
          Size(640, 360),
          Size(800, 360),
          Size(1280, 800),
        ]) {
          tester.view
            ..physicalSize = size
            ..devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            _host(
              definition,
              controller: _controller(definition),
              textScale: 2,
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(SimulationScene), findsOneWidget, reason: '$size');
          expect(
            find.byKey(const ValueKey('simulation-fullscreen-button')),
            findsOneWidget,
            reason: '$size',
          );
          expect(
            find.byKey(const ValueKey('mission-controls-scroll')),
            findsOneWidget,
            reason: '$size',
          );
          expect(tester.takeException(), isNull, reason: '$size');
        }
      },
    );

    testWidgets('persists once for a pause lifecycle event', (tester) async {
      final definition = MissionSimulationDefinitions.byId('coc1_m1');
      final store = _MemoryStore();

      await tester.pumpWidget(
        _host(definition, controller: _controller(definition, store: store)),
      );
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();

      expect(store.saveCount, 1);
    });

    testWidgets('save and exit preserves the runtime snapshot', (tester) async {
      final definition = MissionSimulationDefinitions.byId('coc1_m1');
      final store = _MemoryStore();

      await tester.pumpWidget(
        _routeHost(
          definition,
          controller: _controller(definition, store: store),
        ),
      );
      await tester.tap(find.text('Open mission'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Exit mission'));
      await tester.pumpAndSettle();
      expect(find.text('Exit Mission?'), findsOneWidget);
      await tester.tap(find.text('Save and Exit'));
      await tester.pumpAndSettle();

      expect(find.byType(MissionSimulationScreen), findsNothing);
      expect(store.saved?.missionId, definition.id);
      expect(store.clearCount, 0);
    });

    testWidgets('failed save keeps the mission open', (tester) async {
      final definition = MissionSimulationDefinitions.byId('coc1_m1');
      final store = _MemoryStore()..saveSucceeds = false;

      await tester.pumpWidget(
        _routeHost(
          definition,
          controller: _controller(definition, store: store),
        ),
      );
      await tester.tap(find.text('Open mission'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Exit mission'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save and Exit'));
      await tester.pumpAndSettle();

      expect(find.byType(MissionSimulationScreen), findsOneWidget);
      expect(
        find.text(
          'Progress could not be saved. Keep the mission open and retry.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('continue from exit dialog keeps practice progress open', (
      tester,
    ) async {
      final definition = MissionSimulationDefinitions.byId('coc1_m1');
      final store = _MemoryStore();

      await tester.pumpWidget(
        _routeHost(
          definition,
          controller: _controller(definition, store: store),
        ),
      );
      await tester.tap(find.text('Open mission'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Exit Mission?'), findsOneWidget);
      await tester.tap(find.text('Continue Mission'));
      await tester.pumpAndSettle();

      expect(find.byType(MissionSimulationScreen), findsOneWidget);
      expect(store.clearCount, 0);
    });

    testWidgets('explicit discard clears practice snapshot before exit', (
      tester,
    ) async {
      final definition = MissionSimulationDefinitions.byId('coc1_m1');
      final store = _MemoryStore();
      // Any transport, such as a class-practice attempt, receives the marker.
      final transport = _MemoryTransport();

      await tester.pumpWidget(
        _routeHost(
          definition,
          controller:
              _controller(definition, store: store, transport: transport),
        ),
      );
      await tester.tap(find.text('Open mission'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Exit mission'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard Progress'));
      await tester.pumpAndSettle();
      expect(store.clearCount, 0);
      expect(
          find.text(MissionContentData.discardProgressMessage), findsOneWidget);
      await tester.tap(find.text(MissionContentData.discardProgressLabel));
      await tester.pumpAndSettle();

      expect(find.byType(MissionSimulationScreen), findsNothing);
      expect(store.clearCount, 1);
      expect(transport.appendedActions.last.actionType,
          MissionRuntimeController.progressDiscardedActionType,
          reason: 'the discard marker goes through the mission transport');
      expect(transport.appendedActions.last.value['reason'],
          'learner_confirmed_discard');
    });

    testWidgets('does not force landscape and restores orientations on exit', (
      tester,
    ) async {
      final definition = MissionSimulationDefinitions.byId('coc1_m1');
      final orientation = _FakeOrientationCoordinator();

      await tester.pumpWidget(
        _host(
          definition,
          controller: _controller(definition),
          orientationCoordinator: orientation,
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(orientation.restoreRequests, 1);
    });

    testWidgets(
      'reaches review, can return, and submits only on confirmation',
      (tester) async {
        final definition = MissionSimulationDefinitions.byId('coc1_m1');
        var submissions = 0;
        final controller = _controller(definition);

        await tester.pumpWidget(
          _host(
            definition,
            controller: controller,
            onSubmit: () async => submissions++,
          ),
        );
        await tester.pumpAndSettle();

        await _advanceToReview(tester, definition, controller);

        expect(find.byType(EvidenceReviewPanel), findsOneWidget);
        expect(submissions, 0);

        final returnButton = find.text('Return to mission');
        await tester.ensureVisible(returnButton);
        await tester.tap(returnButton);
        await tester.pumpAndSettle();
        expect(find.byType(EvidenceReviewPanel), findsNothing);

        final next = find.byKey(const ValueKey('mission-next'));
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
        final confirmButton = find.text('Confirm evidence');
        await tester.ensureVisible(confirmButton);
        await tester.tap(confirmButton);
        await tester.pumpAndSettle();

        expect(submissions, 1);
      },
    );

    testWidgets('successful submission disables a second confirmation', (
      tester,
    ) async {
      final definition = MissionSimulationDefinitions.byId('coc1_m1');
      var submissions = 0;
      final controller = _controller(definition);

      await tester.pumpWidget(
        _host(
          definition,
          controller: controller,
          onSubmit: () async => submissions++,
        ),
      );
      await tester.pumpAndSettle();
      await _advanceToReview(tester, definition, controller);

      final confirmText = find.text('Confirm evidence');
      await tester.ensureVisible(confirmText);
      await tester.tap(confirmText);
      await tester.pumpAndSettle();

      final confirmButton = tester.widget<FilledButton>(
        find.ancestor(of: confirmText, matching: find.byType(FilledButton)),
      );
      expect(confirmButton.onPressed, isNull);

      await tester.tap(confirmText, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(submissions, 1);
    });

    testWidgets('practice confirmation saves without authoritative scoring', (
      tester,
    ) async {
      final definition = MissionSimulationDefinitions.byId('coc1_m1');
      final controller = _controller(definition);

      await tester.pumpWidget(_host(definition, controller: controller));
      await tester.pumpAndSettle();
      await _advanceToReview(tester, definition, controller);

      final confirm = find.text('Confirm evidence');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(
        find.text(MissionContentData.practiceSavedMessage),
        findsOneWidget,
      );
      expect(controller.state.mode, MissionRuntimeMode.practice);
      expect(controller.state.assessmentAttemptId, isNull);
    });

    testWidgets(
      'retry synchronizes the same pending evidence and unblocks submission',
      (tester) async {
        final definition = MissionSimulationDefinitions.byId('coc1_m1');
        final pending = MissionEvidenceAction(
          clientActionId: 'pending-action-1',
          missionId: definition.id,
          phaseId: definition.phases[3].id,
          actionType: 'test_completed',
          target: definition.phases[3].id,
          value: const {'test_status': 'completed'},
          occurredAt: DateTime.utc(2026, 8, 22),
        );
        final appendGate = Completer<void>();
        final transport = _MemoryTransport(
          appendGate: appendGate,
          readError: StateError('offline'),
        );
        final completedDriver = EquipmentPracticeDriver(definition);
        for (final phase in definition.phases) {
          completedDriver.complete(phase);
        }
        final localState = completedDriver.state.copyWith(
          currentPhaseId: definition.phases.last.id,
          completedPhaseIds: definition.phases
              .take(definition.phases.length - 1)
              .map((phase) => phase.id)
              .toSet(),
          pendingEvidence: [pending],
        );
        final store = _MemoryStore()..saved = localState;
        final controller = _controller(
          definition,
          store: store,
          transport: transport,
          initialState: localState,
        );

        await tester.pumpWidget(_host(definition, controller: controller));
        await tester.pumpAndSettle();

        final retry = find.widgetWithText(
          OutlinedButton,
          'Retry pending evidence',
        );
        expect(retry, findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirm evidence'),
              )
              .onPressed,
          isNull,
        );

        transport.readError = null;
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await tester.pump();

        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Retrying evidence…'),
              )
              .onPressed,
          isNull,
        );
        expect(
          controller.state.pendingEvidence.single.clientActionId,
          'pending-action-1',
        );

        appendGate.complete();
        await tester.pumpAndSettle();

        expect(transport.appendedIds, ['pending-action-1']);
        expect(controller.state.pendingEvidence, isEmpty);
        expect(controller.state.acceptedEvidenceIds, {'pending-action-1'});
        expect(find.text('Pending evidence synchronized.'), findsOneWidget);
        expect(find.text('Retry pending evidence'), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirm evidence'),
              )
              .onPressed,
          isNotNull,
        );
      },
    );

    testWidgets('incompatible placement never renders as installed', (
      tester,
    ) async {
      final definition = _incompatiblePlacementDefinition();
      final controller = _controller(definition);

      await tester.pumpWidget(_host(definition, controller: controller));
      await tester.pumpAndSettle();

      final item = find.byKey(const ValueKey('placement-item-memory'));
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pump();
      final destination = find.byKey(
        const ValueKey('placement-destination-cpu-socket'),
      );
      await tester.ensureVisible(destination);
      await tester.tap(destination);
      await tester.pump();
      final place = find.byKey(const ValueKey('placement-place'));
      await tester.ensureVisible(place);
      await tester.tap(place);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('incorrect-placement-dialog')),
          findsOneWidget);
      expect(
          find.textContaining('Memory module to CPU socket'), findsOneWidget);
      expect(
          find.textContaining(MissionContentData.incompatiblePlacementFeedback),
          findsOneWidget);
      expect(controller.state.placements, isEmpty);
      expect(
        find.byKey(const ValueKey('placement-state-memory')),
        findsNothing,
      );
      expect(controller.state.acceptedEvidenceIds, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('incorrect-placement-close')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(MissionSimulationScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('incorrect-placement-dialog')),
          findsNothing);
      expect(
          find.textContaining(MissionContentData.incompatiblePlacementFeedback),
          findsNothing);
    });

    testWidgets('wrong canvas slot explains the mismatch for five seconds',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final definition = MissionSimulationDefinitions.byId('coc3_m2');
      final controller = _controller(definition);
      await tester.pumpWidget(_host(definition, controller: controller));
      await tester.pumpAndSettle();
      final source = find.byKey(const ValueKey('workspace-source-server_node'));
      final wrongSlot = find
          .byKey(const ValueKey('workspace-destination-client_node_position'));
      await tester.ensureVisible(source);
      await tester.ensureVisible(wrongSlot);
      await tester.pumpAndSettle();
      await tester.dragFrom(tester.getCenter(source),
          tester.getCenter(wrongSlot) - tester.getCenter(source));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('incorrect-placement-dialog')),
          findsOneWidget);
      expect(find.textContaining('Server to Deployment test position'),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('incorrect-placement-dialog')),
              matching: find.textContaining(
                  MissionContentData.incompatiblePlacementFeedback)),
          findsOneWidget);
      expect(
          find.textContaining(MissionContentData.incompatiblePlacementFeedback),
          findsOneWidget);
      expect(controller.state.placements, isEmpty);
      expect(controller.state.acceptedEvidenceIds, hasLength(1));
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const ValueKey('incorrect-placement-dialog')),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('incorrect-placement-dialog')),
          findsNothing);
      expect(
          find.textContaining(MissionContentData.incompatiblePlacementFeedback),
          findsNothing);
      expect(find.byType(MissionSimulationScreen), findsOneWidget);
      expect(controller.state.acceptedEvidenceIds, hasLength(1));
    });

    testWidgets('configured test evidence type is emitted only on completion', (
      tester,
    ) async {
      final definition = MissionSimulationDefinitions.byId('coc2_m5');
      final phase = definition.phases.singleWhere(
        (item) => (item.presentation['mechanics'] as List).contains(
          'retest_network_path',
        ),
      );
      final transport = _MemoryTransport();
      final controller = _controller(
        definition,
        transport: transport,
        initialState: MissionRuntimeState.initial(
          definition.id,
        ).copyWith(currentPhaseId: phase.id),
      );

      await tester.pumpWidget(_host(definition, controller: controller));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Run test'));
      await tester.tap(find.widgetWithText(FilledButton, 'Run test'));
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.widgetWithText(FilledButton, 'Run test again'));
      await tester.tap(find.widgetWithText(FilledButton, 'Run test again'));
      await tester.pumpAndSettle();

      expect(transport.appendedActions.map((action) => action.actionType), [
        'test_started',
        'retest_requested',
        'test_started',
        'retest_requested',
      ]);
      expect(
        transport.appendedActions.where(
          (action) => action.actionType == 'retest_requested',
        ),
        hasLength(2),
      );
      expect(
        transport.appendedActions.map(
          (action) => action.value['runtime_action_type'],
        ),
        ['test_started', 'test_completed', 'test_started', 'test_completed'],
      );
    });
  });

  group('MissionPhaseInteraction', () {
    final expectedWidgets = <InteractionFamily, Type>{
      InteractionFamily.inspect: TapInspectInteraction,
      InteractionFamily.select: MultiSelectInteraction,
      InteractionFamily.tool: ToolSelectionInteraction,
      InteractionFamily.connect: ConnectionInteraction,
      InteractionFamily.configure: ConfigurationPanel,
      InteractionFamily.sequence: SequencingInteraction,
      InteractionFamily.match: MatchingInteraction,
      InteractionFamily.place: ControlledPlacementInteraction,
      InteractionFamily.troubleshoot: TroubleshootingBranchInteraction,
      InteractionFamily.testRun: TestRunInteraction,
      InteractionFamily.observe: ObservationInteraction,
      InteractionFamily.decide: ScenarioDecisionInteraction,
      InteractionFamily.interpret: ResultInterpretationInteraction,
      InteractionFamily.review: EvidenceReviewPanel,
    };

    testWidgets(
      'renders every catalog phase without technical unavailability',
      (tester) async {
        final failures = <String>[];
        for (final definition in MissionSimulationDefinitions.all) {
          for (final phase in definition.phases) {
            final state = MissionRuntimeState.initial(definition.id)
                .copyWith(currentPhaseId: phase.id);
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: MissionPhaseInteraction(
                      phase: phase,
                      state: state,
                      onAction: (_, __, ___) async {},
                      onRuntimeTransition: (_) {},
                      onReturnFromReview: () {},
                      onConfirmReview: () {},
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();

            final renderedWidgets = expectedWidgets.values
                .where((type) => find.byType(type).evaluate().isNotEmpty)
                .toList(growable: false);
            final exception = tester.takeException();
            final key = MissionActionGuide.forPhase(phase, state)
                .currentStep
                ?.controlKey;
            if (find.byType(TechnicalUnavailableState).evaluate().isNotEmpty ||
                renderedWidgets.length != 1 ||
                // A lab's controls live in the lab, not in this panel.
                (key != null &&
                    !MissionLabPhases.owns(phase.id) &&
                    find.byKey(ValueKey(key)).evaluate().isEmpty) ||
                exception != null) {
              failures.add(
                '${definition.id}/${phase.id}: '
                'widgets=$renderedWidgets control=$key exception=$exception',
              );
            }
          }
        }
        if (failures.isNotEmpty) {
          debugPrint(failures.join('\n'));
        }
        expect(failures, isEmpty);
      },
    );

    for (final entry in expectedWidgets.entries) {
      testWidgets('maps ${entry.key.name} to ${entry.value}', (tester) async {
        final phase = _phase(entry.key);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MissionPhaseInteraction(
                  phase: phase,
                  state: MissionRuntimeState.initial(
                    'test',
                  ).copyWith(currentPhaseId: phase.id),
                  onAction: (_, __, ___) async {},
                  onRuntimeTransition: (_) {},
                  onReturnFromReview: () {},
                  onConfirmReview: () {},
                ),
              ),
            ),
          ),
        );

        expect(find.byType(entry.value), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'shows technical unavailable for an unknown component override',
      (tester) async {
        final phase = MissionPhaseDefinition(
          id: 'broken',
          title: 'Broken phase',
          instruction: 'Unavailable',
          primaryInteraction: InteractionFamily.connect,
          presentation: const {'component': 'not_registered'},
        );
        await tester.pumpWidget(
          MaterialApp(
            home: MissionPhaseInteraction(
              phase: phase,
              state: MissionRuntimeState.initial('test'),
              onAction: (_, __, ___) async {},
              onRuntimeTransition: (_) {},
              onReturnFromReview: () {},
              onConfirmReview: () {},
            ),
          ),
        );

        expect(find.byType(TechnicalUnavailableState), findsOneWidget);
        expect(find.textContaining('not available'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

Widget _host(
  MissionSimulationDefinition definition, {
  required MissionRuntimeController controller,
  MissionOrientationCoordinator? orientationCoordinator,
  MissionSubmitCallback? onSubmit,
  double textScale = 1,
  bool timedPractice = false,
  String? practiceUserId,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: MissionSimulationScreen(
      mission: _mission(definition.id),
      definition: definition,
      controller: controller,
      orientationCoordinator:
          orientationCoordinator ?? _FakeOrientationCoordinator(),
      onSubmit: onSubmit,
      timedPractice: timedPractice,
      practiceUserId: practiceUserId,
    ),
  );
}

Widget _routeHost(
  MissionSimulationDefinition definition, {
  required MissionRuntimeController controller,
}) =>
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => MissionSimulationScreen(
                  mission: _mission(definition.id),
                  definition: definition,
                  controller: controller,
                  orientationCoordinator: _FakeOrientationCoordinator(),
                ),
              ),
            ),
            child: const Text('Open mission'),
          ),
        ),
      ),
    );

MissionRuntimeController _controller(
  MissionSimulationDefinition definition, {
  _MemoryStore? store,
  MissionEvidenceTransport? transport,
  MissionRuntimeState? initialState,
}) {
  return MissionRuntimeController(
    userId: 'learner-1',
    initialState: initialState ??
        MissionRuntimeState.initial(
          definition.id,
        ).copyWith(currentPhaseId: definition.phases.first.id),
    store: store ?? _MemoryStore(),
    evidenceGateway: MissionEvidenceGateway(
      transport: transport ?? _MemoryTransport(),
    ),
    submissionPhaseIds: {definition.phases.last.id},
    clientActionIdFactory: _sequentialIds(),
  );
}

MissionSimulationDefinition _incompatiblePlacementDefinition() =>
    MissionSimulationDefinition(
      id: 'coc1_m9',
      cocId: 'coc1',
      title: 'Verify component placement',
      scenario: 'A memory module must be installed in a compatible socket.',
      environmentLabel: 'Hardware lab',
      practiceGuidance: 'Match component category to socket category.',
      scene: SimulationSceneDefinition(
        id: 'hardware-lab',
        objects: [
          SceneObjectDefinition(
            id: 'workbench',
            label: 'Hardware workbench',
            x: .2,
            y: .2,
            width: .4,
            height: .4,
            hotspotType: 'workbench',
          ),
        ],
      ),
      phases: [
        MissionPhaseDefinition(
          id: 'place-component',
          title: 'Place component',
          instruction: 'Install the memory module.',
          primaryInteraction: InteractionFamily.place,
          presentation: const {
            'items': [
              {'id': 'memory', 'label': 'Memory module', 'category': 'dimm'},
            ],
            'destinations': [
              {
                'id': 'cpu-socket',
                'label': 'CPU socket',
                'accepted_categories': ['processor'],
              },
            ],
          },
        ),
        MissionPhaseDefinition(
          id: 'decide',
          title: 'Decide',
          instruction: 'Choose the safe response.',
          primaryInteraction: InteractionFamily.decide,
          presentation: const {
            'choices': [
              {'id': 'stop', 'label': 'Stop and inspect compatibility'},
            ],
          },
        ),
        MissionPhaseDefinition(
          id: 'verify',
          title: 'Verify',
          instruction: 'Run the verification test.',
          primaryInteraction: InteractionFamily.testRun,
        ),
      ],
      interactionFamilies: const {
        InteractionFamily.place,
        InteractionFamily.decide,
        InteractionFamily.testRun,
      },
    );

Future<void> _advanceToReview(
  WidgetTester tester,
  MissionSimulationDefinition definition,
  MissionRuntimeController controller,
) async {
  final plan = EquipmentPracticeDriver(definition);
  for (final phase in definition.phases) {
    plan.complete(phase);
  }
  for (final phase in definition.phases.take(definition.phases.length - 1)) {
    for (final action
        in plan.actions.where((action) => action.phaseId == phase.id)) {
      await performEquipmentAction(tester, phase, action, controller);
    }
    final next = find.byKey(const ValueKey('mission-next'));
    expect(tester.widget<FilledButton>(next).onPressed, isNotNull,
        reason: '${phase.id} did not reach terminal interaction state');
    await tapEquipmentControl(tester, next);
  }
}

ClientActionIdFactory _sequentialIds() {
  var value = 0;
  return () => 'action-${value++}';
}

Mission _mission(String id) => Mission(
      id: id,
      cocId: id.substring(0, 4),
      missionCode: id.toUpperCase(),
      missionNumber: int.parse(id.substring(id.length - 1)),
      title: id,
      missionType: MissionType.identification,
      orderIndex: 1,
    );

MissionPhaseDefinition _phase(InteractionFamily family) {
  final presentation = switch (family) {
    InteractionFamily.inspect => const {
        'objects': [
          {'id': 'device', 'label': 'Device'},
        ],
      },
    InteractionFamily.select => const {
        'options': [
          {'id': 'device', 'label': 'Device'},
        ],
      },
    InteractionFamily.tool => const {
        'targets': [
          {'id': 'device', 'label': 'Device'},
        ],
        'tools': [
          {'id': 'meter', 'label': 'Meter'},
        ],
      },
    InteractionFamily.connect || InteractionFamily.match => const {
        'sources': [
          {'id': 'source', 'label': 'Source'},
        ],
        'destinations': [
          {'id': 'destination', 'label': 'Destination'},
        ],
      },
    InteractionFamily.configure => const {
        'fields': [
          {'id': 'address', 'label': 'Address'},
        ],
      },
    InteractionFamily.sequence => const {
        'steps': [
          {'id': 'step', 'label': 'Step'},
        ],
      },
    InteractionFamily.place => const {
        'items': [
          {'id': 'part', 'label': 'Part'},
        ],
        'destinations': [
          {'id': 'slot', 'label': 'Slot'},
        ],
      },
    InteractionFamily.troubleshoot => const {
        'diagnostic_actions': [
          {'id': 'inspect', 'label': 'Inspect', 'reveals_fact_id': 'fact'},
        ],
        'facts': {'fact': 'The link indicator remains dark.'},
        'required_fact_ids': ['fact'],
      },
    InteractionFamily.decide => const {
        'choices': [
          {'id': 'isolate', 'label': 'Isolate the device'},
        ],
      },
    _ => const <String, dynamic>{},
  };
  return MissionPhaseDefinition(
    id: 'phase-${family.name}',
    title: family.name,
    instruction: 'Complete ${family.name}',
    primaryInteraction: family,
    availableObjectIds: const ['device'],
    presentation: presentation,
  );
}

final class _MemoryStore implements MissionRuntimeStore {
  MissionRuntimeState? saved;
  Completer<void>? loadGate;
  int saveCount = 0;
  int clearCount = 0;
  bool saveSucceeds = true;

  @override
  Future<bool> clearMissionRuntime({
    required String userId,
    required String missionId,
    required MissionRuntimeMode mode,
    String? assessmentAttemptId,
  }) async {
    clearCount++;
    saved = null;
    return true;
  }

  @override
  Future<MissionRuntimeState?> loadMissionRuntime({
    required String userId,
    required String missionId,
    required MissionRuntimeMode mode,
    String? assessmentAttemptId,
  }) async {
    await loadGate?.future;
    return saved;
  }

  @override
  Future<bool> saveMissionRuntime({
    required String userId,
    required MissionRuntimeState state,
  }) async {
    saveCount++;
    if (saveSucceeds) saved = state;
    return saveSucceeds;
  }
}

final class _MemoryTransport implements MissionEvidenceTransport {
  _MemoryTransport({this.appendGate, this.readError});

  final Completer<void>? appendGate;
  Object? readError;
  final Set<String> accepted = <String>{};
  final List<String> appendedIds = <String>[];
  final List<MissionEvidenceAction> appendedActions = <MissionEvidenceAction>[];

  @override
  Future<List<AcknowledgedMissionEvidenceAction>>
      readAcknowledgedActions() async {
    if (readError case final error?) throw error;
    return [
      for (final (index, id) in accepted.indexed)
        AcknowledgedMissionEvidenceAction(
          action: MissionEvidenceAction(
            clientActionId: id,
            missionId: 'coc1_m1',
            phaseId: 'coc1_m1_p1',
            actionType: 'object_inspected',
            value: const {},
            occurredAt: DateTime.utc(2026),
          ),
          serverRecordId: 'server-$id',
          serverOrder: index + 1,
          recordedAt: DateTime.utc(2026),
        ),
    ];
  }

  @override
  Future<void> append(MissionEvidenceAction action) async {
    appendedIds.add(action.clientActionId);
    appendedActions.add(action);
    await appendGate?.future;
    accepted.add(action.clientActionId);
  }
}

final class _FakeOrientationCoordinator
    implements MissionOrientationCoordinator {
  int restoreRequests = 0;

  @override
  Future<void> restoreSupportedOrientations() async => restoreRequests++;
}
