import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/data/mission_simulation_definitions.dart';
import 'package:bytequest/data/quiz_content_data.dart';
import 'package:bytequest/screens/simulation/templates/coc2_cable_assessment_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Rest Minors 1 and 11.
  test('result and progress copy follows the binding rules', () {
    for (final label in [
      QuizContentData.itemCorrect,
      QuizContentData.itemNeedsReview,
    ]) {
      expect(label, isNot(matches(RegExp(r'^(Correct|Wrong)\W*$'))),
          reason: 'never a bare Correct or Wrong');
    }
    expect(MissionContentData.practiceSavedMessage,
        isNot(contains('five missions')),
        reason: 'the COC quiz follows module completion, lessons included');
    expect(MissionContentData.practiceSavedMessage, contains('lesson'));
  });

  test('COC 2 identification answer keys exist in their option sets', () {
    final questions = MissionContentData.getCOC2M1Questions();

    for (final question in questions) {
      expect(
        question.options,
        contains(question.correctAnswer),
        reason: '${question.id} has an impossible answer key',
      );
    }
  });

  test('RJ45 practice components and targets use one shared sequence', () {
    final sequence = MissionContentData.getCOC2M2WireSequence();

    expect(sequence, hasLength(8));
    expect(sequence.toSet(), hasLength(8));
    expect(sequence.every((color) => color.trim().isNotEmpty), isTrue);
  });

  test('COC2 IP scenario rejects IPv4 octets outside 0 to 255', () {
    final config = MissionContentData.getCOC2M5ConfigData();
    final ipConfig = config['ipAddress'] as Map<String, dynamic>;
    final validation = RegExp(ipConfig['validation'] as String);

    expect(validation.hasMatch('192.168.1.100'), isTrue);
    expect(validation.hasMatch('192.168.1.255'), isTrue);
    expect(validation.hasMatch('192.168.1.256'), isFalse);
    expect(validation.hasMatch('192.168.1.999'), isFalse);
    expect(validation.hasMatch('192.168.1.01'), isFalse);
  });

  test(
      'mission feedback uses technical constraints instead of generic verdicts',
      () {
    const genericVerdicts = {'wrong', 'correct', 'try again', 'incorrect'};

    for (final catalog in MissionContentData.missionFeedbackCatalogs.values) {
      expect(catalog, isNotEmpty);
      for (final message in catalog.values) {
        expect(message.trim(), isNotEmpty);
        expect(genericVerdicts, isNot(contains(message.trim().toLowerCase())));
      }
    }
  });

  test('presentation catalog preserves protected evidence identifiers', () {
    // COC1 M2 moved to the assembly-bench contract (css-assembly-20261119-v3):
    // its actions are recorded with their runtime types and the power-on
    // self-test keeps a dedicated evidence type.
    final assembly = MissionSimulationDefinitions.byId('coc1_m2');
    expect(_actionTypes(assembly), isNot(contains('component_drop_attempted')));
    expect(
        assembly.phases[4].presentation['evidenceActionType'],
        'power_on_self_test');
    // COC1 M3 practice now follows the PDF's installation workflow. Cable
    // assessment evidence remains in its immutable server-owned contract.
    expect(MissionSimulationDefinitions.byId('coc1_m3').title,
        'Install and Configure a Workstation OS');
    expect(
      _actionTypes(MissionSimulationDefinitions.byId('coc2_m2')),
      containsAll({
        'ppe_selection_submitted',
        'tools_materials_selection_submitted',
        'cable_preparation_step',
        'conductor_placed',
        'termination_step',
        'tester_step',
        'tester_result_submitted',
        'inspection_selection_submitted',
        'cleanup_selection_submitted',
      }),
    );
    expect(
      MissionContentData.getCOC2M2WireSequence()
          .map((label) => label.toLowerCase().replaceAll('-', '_'))
          .toList(),
      Coc2CableAssessmentContract.t568bOrder,
    );
  });
}

Set<String> _actionTypes(dynamic definition) =>
    _collectActionTypes(definition.toJson());

Set<String> _collectActionTypes(dynamic value) {
  if (value is Map) {
    return {
      if (value['action_type'] is String) value['action_type'] as String,
      ...value.values.expand(_collectActionTypes),
    };
  }
  if (value is Iterable) return value.expand(_collectActionTypes).toSet();
  return const {};
}
