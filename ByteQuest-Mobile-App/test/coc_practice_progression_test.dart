import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/models/practice_progress_model.dart';
import 'package:bytequest/screens/quizzes/practice_quiz_screen.dart';
import 'package:bytequest/screens/simulation/interactions/controlled_placement_interaction.dart';
import 'package:bytequest/screens/simulation/interactions/sequencing_interaction.dart';
import 'package:bytequest/screens/simulation/runtime/mission_runtime_models.dart';
import 'package:bytequest/screens/simulation/runtime/mission_phase_completion_policy.dart';
import 'package:bytequest/services/practice_progress_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/equipment_practice_driver.dart';

void main() {
  test('COC4 backup preparation cannot skip inspection or diagnostics', () {
    for (var n = 1; n <= 5; n++) {
      final definition = MissionSimulationDefinitions.byId('coc4_m$n');
      final driver = EquipmentPracticeDriver(definition);
      final phase = definition.phases.first;
      driver.act(phase, 'equipment_operation', 'protect_service_data');
      expect(
          MissionPhaseCompletionPolicy.canAdvance(phase, driver.state), false,
          reason: definition.id);
    }
  });
  test('missing access and practical work cannot enable the COC quiz', () {
    final locked = PracticeCocProgress.fromJson({
      'coc_code': 'coc2',
      'completed_missions': ['coc2_m1']
    });
    expect(locked.unlocked, false);
    expect(locked.quizAvailable, false);
    expect(
        PracticeCocProgress.fromJson({
          'coc_code': 'coc1',
          'unlocked': true,
          'completed_missions': ['coc1_m1']
        }).quizAvailable,
        false);
  });
  testWidgets(
      'server deployment supports a real drop and COC4 replacement uses taps only',
      (tester) async {
    final definition = MissionSimulationDefinitions.byId('coc3_m1');
    final panel =
        definition.phases.first.presentation['equipment']['placement'] as Map;
    final actions = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: ControlledPlacementInteraction(
      phase: MissionPhaseDefinition(
          id: 'deploy',
          title: 'Deploy',
          instruction: 'Deploy',
          primaryInteraction: InteractionFamily.place,
          presentation: Map<String, dynamic>.from(panel)),
      state: MissionRuntimeState.initial(definition.id),
      onAction: (type, target, value) async {
        actions.add(value);
      },
    )))));
    final source = find.byKey(const ValueKey('placement-item-server_node'));
    final target = find
        .byKey(const ValueKey('placement-destination-server_node_position'));
    await tester.dragFrom(tester.getCenter(source),
        tester.getCenter(target) - tester.getCenter(source));
    await tester.pumpAndSettle();
    expect(actions.single['input_method'], 'drag');
    expect(actions.single['destination_id'], 'server_node_position');
    final repair = MissionSimulationDefinitions.byId('coc4_m4');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ControlledPlacementInteraction(
      phase: repair.phases[1],
      state: MissionRuntimeState.initial(repair.id),
      onAction: (_, __, ___) async {},
    ))));
    expect(find.byType(Draggable<String>), findsNothing);
    expect(find.byType(DragTarget<String>), findsNothing);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SequencingInteraction(
      phase: repair.phases.first,
      state: MissionRuntimeState.initial(repair.id),
      onAction: (_, __, ___) async {},
    ))));
    expect(find.byType(ReorderableDragStartListener), findsNothing);
    expect(find.byType(ReorderableDelayedDragStartListener), findsNothing);
  });
  for (final size in const [Size(320, 568), Size(640, 360)]) {
    testWidgets(
        'practice quiz resumes answers and displays server explanations at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _QuizService();
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(
                  size: size, textScaler: const TextScaler.linear(2)),
              child: PracticeQuizScreen(coc: 'coc1', service: service))));
      await tester.pumpAndSettle();
      expect(find.text('Teacher explanation'), findsNothing);
      final submit = find.text('Submit quiz');
      await tester.scrollUntilVisible(submit, 300);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.textContaining('4/5 (80%)'), -300);
      expect(service.submissions, 1);
      expect(find.textContaining('4/5 (80%)'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.textContaining('Teacher explanation').first, 300);
      expect(find.textContaining('Teacher explanation'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}

class _QuizService extends PracticeProgressService {
  int submissions = 0;
  Map<String, dynamic> payload(bool submitted) => {
        'id': 'saved-attempt',
        'status': submitted ? 'submitted' : 'active',
        'source': 'bank',
        'answers': {for (var i = 0; i < 5; i++) 'q$i': 0},
        'score': 4,
        'passed': true,
        'questions': [
          for (var i = 0; i < 5; i++)
            {
              'id': 'q$i',
              'question': 'Select the safe service procedure for task $i.',
              'choices': [
                'Isolate power',
                'Keep power on',
                'Skip inspection',
                'Use an incompatible part'
              ],
              if (submitted) 'answer': 0,
              if (submitted) 'explanation': 'Teacher explanation'
            }
        ],
      };
  @override
  Future<PracticeQuiz> beginQuiz(String coc) async =>
      PracticeQuiz(payload(false));
  @override
  Future<PracticeQuiz> submitQuiz(String id, Map<String, int> answers) async {
    submissions++;
    return PracticeQuiz(payload(true));
  }
}
