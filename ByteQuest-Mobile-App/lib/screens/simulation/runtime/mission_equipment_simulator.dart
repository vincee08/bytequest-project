import '../../../data/mission_content_data.dart';
import 'mission_runtime_models.dart';

/// Deterministic equipment behavior, not a competency evaluator. No scores,
/// passing percentages, rubric answers or release decisions exist here; the
/// server replay remains authoritative in practice and assessment. In
/// assessment mode the same physical rules apply but feedback is neutral, so
/// a refusal never names the correct target or procedure.
abstract final class MissionEquipmentSimulator {
  static bool isAssemblyBench(MissionSimulationDefinition definition) =>
      definition.scene.initialStatus['workspace'] == 'assembly_bench';

  static Map<String, dynamic> describeAction({
    required MissionSimulationDefinition definition,
    required MissionPhaseDefinition phase,
    required MissionRuntimeState state,
    required String actionType,
    required String? target,
    required Map<String, dynamic> value,
    DateTime? now,
  }) {
    if (phase.presentation['equipment'] is! Map) {
      return value;
    }
    final assessment = state.mode == MissionRuntimeMode.assessment;
    final bench = isAssemblyBench(definition);
    final spec = map(phase.presentation['equipment']);
    final next = Map<String, dynamic>.from(state.equipmentState);
    var valid = true;
    var feedback = assessment
        ? MissionContentData.assessmentNeutralRecorded
        : MissionContentData.equipmentRecordedFeedback;
    var correction = false;
    // Steps a completed test charges: one per step with a failing check
    // (mirrors failed_checks in private.simulation_replay).
    var faults = 0;
    final recorded = Map<String, dynamic>.from(value);
    final phaseValues = map(next['phases']);
    final phaseState = map(phaseValues[phase.id]);

    void reject(String message) {
      valid = false;
      feedback = assessment ? _neutralRefusal(actionType) : message;
    }

    switch (actionType) {
      case 'connection_created':
        final panel = map(spec['connection']);
        final source = item(panel['sources'] ?? phase.presentation['sources'],
            value['source_id']);
        final destination = item(
            panel['destinations'] ?? phase.presentation['destinations'],
            value['destination_id']);
        final allowed = strings(source['interfaces']);
        if (source.isEmpty ||
            destination.isEmpty ||
            source['id'] == destination['id'] ||
            (allowed.isNotEmpty &&
                !allowed.contains(destination['interface']))) {
          reject(MissionContentData.incompatibleConnectionFeedback);
        } else if (spec['single_connection'] == true &&
            state.connectedNodePairs.any((pair) =>
                pair.startsWith('${value['source_id']}>') &&
                pair != '${value['source_id']}>${value['destination_id']}')) {
          correction = true;
        }
        recorded['compatible'] = valid;
        recorded['replace_source_connection'] =
            spec['single_connection'] == true;
        break;
      case 'tool_attempted':
        final tool = item(
            spec['tools'] ?? phase.presentation['tools'], value['tool_id']);
        final destination =
            item(spec['targets'] ?? phase.presentation['targets'], target);
        final categories = strings(tool['compatible_categories']);
        if (tool.isEmpty ||
            destination.isEmpty ||
            (categories.isNotEmpty &&
                !categories.contains(destination['category']))) {
          reject(MissionContentData.incompatibleToolFeedback);
        } else {
          // Assessment shows what the tool reads, never the next step.
          feedback = value['tool_id'] == 'lan_cable_tester'
              ? state.connectedNodePairs.isEmpty
                  ? assessment
                      ? MissionContentData.assessmentDisconnectedToolReading
                      : MissionContentData.disconnectedToolReading
                  : assessment
                      ? MissionContentData.assessmentConnectedToolReading
                      : MissionContentData.connectedToolReading
              : assessment
                  ? MissionContentData
                          .assessmentToolObservations[value['tool_id']] ??
                      MissionContentData.assessmentToolContact
                  : MissionContentData.toolObservations[value['tool_id']] ??
                      MissionContentData.toolContactFeedback;
          recorded['measured_tool_result'] = {
            'tool_id': tool['id'],
            'target': target,
            'observation': feedback,
          };
          phaseState['tool_output'] = recorded['measured_tool_result'];
        }
        recorded['compatible'] = valid;
        break;
      case 'placement_attempted':
        final panel = map(spec['placement']);
        final part = item(
            panel['items'] ?? phase.presentation['items'], value['item_id']);
        final slot = item(
            panel['destinations'] ?? phase.presentation['destinations'],
            value['destination_id']);
        final categories =
            strings(slot['socket_categories'] ?? slot['accepted_categories']);
        if (part.isEmpty ||
            slot.isEmpty ||
            categories.isEmpty ||
            !categories.contains(part['category'])) {
          reject(MissionContentData.incompatiblePlacementFeedback);
        } else if (part['seating_orientation'] != null &&
            value['orientation'] != part['seating_orientation']) {
          reject(MissionContentData.benchOrientationFeedback[part['id']] ??
              MissionContentData.orientationFeedback);
        } else if (!strings(part['requires_placements'])
            .every(state.placements.containsKey)) {
          reject(MissionContentData.placementPrerequisiteFeedback);
        } else if (!conditionsMet(part['requires'], state)) {
          reject(MissionContentData.benchRequirementFeedback[part['id']] ??
              MissionContentData.placementPrerequisiteFeedback);
        } else if (state.placements.entries.any((entry) =>
            entry.key != value['item_id'] &&
            entry.value == value['destination_id'])) {
          reject(MissionContentData.occupiedDestinationFeedback);
        } else if (state.placements[value['item_id']] != null &&
            state.placements[value['item_id']] != value['destination_id']) {
          correction = true;
        }
        recorded['compatible'] = valid;
        break;
      case 'placement_removed':
        final panel = map(spec['placement']);
        final part = item(
            panel['items'] ?? phase.presentation['items'], value['item_id']);
        if (part.isEmpty || !state.placements.containsKey(value['item_id'])) {
          reject(MissionContentData.benchRemovalUnavailable);
        } else {
          next.addAll(map(part['removal_effects']));
          correction = true;
          feedback = assessment
              ? MissionContentData.assessmentNeutralRecorded
              : MissionContentData.benchRemovalFeedback;
        }
        recorded['compatible'] = valid;
        break;
      case 'sequence_reordered':
        final order = strings(value['order']);
        final ids =
            maps(phase.presentation['items']).map((item) => item['id']).toSet();
        if (order.length != ids.length ||
            order.toSet().length != ids.length ||
            !ids.containsAll(order)) {
          reject(MissionContentData.sequenceConstraintFeedback);
        }
        for (final edge in maps(spec['precedence'])) {
          final before = order.indexOf(edge['before'] as String);
          final after = order.indexOf(edge['after'] as String);
          if (before < 0 || after < 0 || before >= after) {
            reject(edge['message'] as String? ??
                MissionContentData.sequenceConstraintFeedback);
          }
        }
        phaseState['order'] = order;
        phaseState['sequence_valid'] = valid;
        break;
      case 'configuration_applied':
        final values = map(value['values']);
        for (final field in maps(map(spec['configuration'])['fields'] ??
            phase.presentation['fields'])) {
          final input = values[field['id']];
          if (!_formatValid(field, input)) {
            reject(field['format_feedback'] as String? ??
                MissionContentData.fieldFormatFeedback);
          }
        }
        // Even a technically unsuitable configuration is retained, so the
        // learner can test it, inspect the failure, correct it and retest.
        phaseState['configuration'] = values;
        // A restart verifies the configuration that existed at that time.
        // Subsequent changes must not reuse that earlier boot observation.
        if (next.containsKey('restarted')) next['restarted'] = false;
        if (values.containsKey('service_control')) {
          next['service_running'] = values['service_control'] != 'stop';
        }
        feedback =
            valid ? MissionContentData.equipmentUpdatedFeedback : feedback;
        break;
      case 'selection_confirmed':
        if (value['selection_group'] is String) {
          next['classifications'] = {
            ...map(next['classifications']),
            value['selection_group'] as String: strings(value['selected_ids'])
          };
        } else {
          phaseState['selection'] = strings(value['selected_ids']);
        }
        break;
      case 'scenario_decision':
        phaseState['decision'] = target;
        final choice = item(phase.presentation['choices'], target);
        final effects = map(choice['equipment_effects']);
        if (effects.isNotEmpty) next.addAll(effects);
        feedback = choice['consequence'] as String? ?? feedback;
        break;
      case 'diagnostic_action':
        final diagnostic =
            item(phase.presentation['diagnostic_actions'], target);
        if (!conditionsMet(diagnostic['requires'], state)) {
          reject(MissionContentData.operationPrerequisiteFeedback);
          recorded.remove('reveals_fact_id');
        } else {
          final factId = value['reveals_fact_id'];
          final dynamicFact = map(map(spec['fact_readings'])[factId]);
          final description = dynamicFact.isEmpty
              ? map(phase.presentation['facts'])[factId]
              : conditionsMet(dynamicFact['requires'], state)
                  ? dynamicFact['nominal']
                  : dynamicFact['fault'];
          if (description is String && factId is String) {
            next['fact_observations'] = {
              ...map(next['fact_observations']),
              factId: description
            };
            recorded['measured_fact'] = description;
          }
        }
        break;
      case 'equipment_operation':
        final operation = item(spec['operations'], target);
        if (operation.isEmpty || !conditionsMet(operation['requires'], state)) {
          reject(operation['unavailable_feedback'] as String? ??
              MissionContentData.operationPrerequisiteFeedback);
        } else {
          next.addAll(map(operation['effects']));
          final operations = map(next['operations']);
          operations[target!] = true;
          next['operations'] = operations;
          feedback = operation['feedback'] as String? ??
              (bench ? _benchOperationFeedback(phase, target) : null) ??
              MissionContentData.equipmentUpdatedFeedback;
        }
        break;
      case 'test_completed':
        final checks = maps(spec['checks']);
        final readings = <Map<String, dynamic>>[];
        // Mirrors private.simulation_replay: each step ("counts") with a
        // failing check is charged once per run, and the parts and cables
        // those checks examine are under repair until the next run.
        final chargedSteps = <String>{};
        final repairing = <String>{};
        for (final check in checks) {
          final operating = conditionsMet(check['requires'], state);
          if (!operating && check['counts'] is String) {
            chargedSteps.add(check['counts'] as String);
            repairing.addAll(strings(check['repairs']));
            for (final condition in maps(check['requires'])) {
              final path = condition['path'];
              if (path is! String) continue;
              if (path.startsWith('placed.')) {
                repairing.add('item:${path.substring(7)}');
              } else if (path.startsWith('link.')) {
                repairing.add('connection:${path.substring(5).split('>').first}');
              }
            }
          }
          readings.add({
            'id': check['id'],
            'label': assessment
                ? MissionContentData.assessmentReadingLabel(phase.id,
                    check['id'] as String?, check['label'] as String? ?? '')
                : check['label'],
            'operating': operating,
            // Assessment readouts state the symptom only: they never name
            // the slot, header, cable or step that fixes it.
            'reading': assessment
                ? MissionContentData.assessmentReading(
                    phase.id, check['id'] as String?, operating)
                : operating
                    ? check['nominal']
                    : check['fault'],
          });
        }
        final result = {
          'target': target,
          'phase_id': phase.id,
          'readings': readings,
          'operating': readings.isNotEmpty &&
              readings.every((reading) => reading['operating'] == true),
          'input_revision': next['input_revision'] ?? 0,
          'configuration_snapshot': state.configurationValues,
          'connection_snapshot': state.connectedNodePairs.toList(),
          'placement_snapshot': state.placements,
        };
        final results = map(next['results']);
        results[target!] = result;
        next['results'] = results;
        faults = chargedSteps.length;
        next['repairing'] = repairing.toList();
        recorded['measured_result'] = result;
        if (phase.presentation['test_reveals_fact_id'] is String) {
          recorded['reveals_fact_id'] =
              phase.presentation['test_reveals_fact_id'];
        }
        feedback = assessment
            ? MissionContentData.assessmentTestRecorded
            : MissionContentData.testResultRecordedFeedback;
        break;
    }
    if (assessment &&
        valid &&
        !const {'tool_attempted', 'diagnostic_action', 'test_completed'}
            .contains(actionType)) {
      // Measured readings stay visible; everything else is neutral.
      feedback = MissionContentData.assessmentNeutralRecorded;
    }
    if ((valid || actionType == 'configuration_applied') &&
        const {
          'connection_created',
          'configuration_applied',
          'placement_attempted',
          'placement_removed',
          'sequence_reordered',
          'scenario_decision',
          'selection_confirmed',
          'equipment_operation',
          'tool_attempted',
        }.contains(actionType)) {
      next['input_revision'] =
          (next['input_revision'] as num? ?? 0).toInt() + 1;
    }
    if (bench) {
      // Learner-facing bench metrics only; the server replay recomputes
      // invalid actions and corrections for runs and assessments.
      next['started_at'] ??= (now ?? DateTime.now()).toUtc().toIso8601String();
      final counts = map(next['counts']);
      final correctionTarget = actionType == 'connection_created'
          ? 'connection:${value['source_id']}'
          : 'item:${value['item_id']}';
      final key = !valid
          ? 'invalid'
          : correction
              ? strings(state.equipmentState['repairing'])
                      .contains(correctionTarget)
                  // Reseating what a failed run flagged is the repair the
                  // run already charged, not another correction.
                  ? 'repairs'
                  : 'corrections'
              : 'valid';
      counts[key] = (counts[key] as num? ?? 0).toInt() + 1;
      if (faults > 0) {
        counts['faults'] = (counts['faults'] as num? ?? 0).toInt() + faults;
      }
      next['counts'] = counts;
    }
    phaseState['last_action_valid'] = valid;
    phaseValues[phase.id] = phaseState;
    next['phases'] = phaseValues;
    next['feedback'] = feedback;
    return {
      ...recorded,
      'simulation_valid': valid,
      'simulation_feedback': feedback,
      'equipment_snapshot': next,
    };
  }

  /// What a bench operation physically changed ("Load lever opened."). Only
  /// the power-on phase has a test that can check the change; assessment
  /// replaces this with neutral feedback.
  static String? _benchOperationFeedback(
      MissionPhaseDefinition phase, String target) {
    final done = MissionContentData.benchOperationFeedback[target];
    if (done == null) return null;
    return phase.resolvedInteraction == InteractionFamily.testRun
        ? '$done ${MissionContentData.benchOperationRetest}'
        : done;
  }

  static String _neutralRefusal(String actionType) => switch (actionType) {
        'placement_attempted' => MissionContentData.assessmentNeutralPlacement,
        'placement_removed' => MissionContentData.assessmentNeutralRemoval,
        'connection_created' => MissionContentData.assessmentNeutralConnection,
        'equipment_operation' => MissionContentData.assessmentNeutralOperation,
        'tool_attempted' => MissionContentData.assessmentNeutralTool,
        _ => MissionContentData.assessmentNeutralRecorded,
      };

  static bool phaseReady(
      MissionPhaseDefinition phase, MissionRuntimeState state) {
    if (state.mode != MissionRuntimeMode.practice ||
        phase.presentation['equipment'] is! Map) return true;
    final spec = map(phase.presentation['equipment']);
    return conditionsMet(spec['completion'], state);
  }

  static bool readyForReview(
      MissionSimulationDefinition definition, MissionRuntimeState state) {
    if (state.mode != MissionRuntimeMode.practice) return true;
    return definition.phases
        .where((phase) => phase.resolvedInteraction != InteractionFamily.review)
        .every((phase) =>
            state.interactionCompletedPhaseIds.contains(phase.id) &&
            phaseReady(phase, state));
  }

  static bool conditionsMet(Object? conditions, MissionRuntimeState state) =>
      maps(conditions).every((condition) => conditionMet(condition, state));

  static bool conditionMet(
      Map<String, dynamic> condition, MissionRuntimeState state) {
    final actual = read(condition['path'] as String? ?? '', state);
    final operand = condition['value'];
    switch (condition['operator'] ?? 'equals') {
      case 'present':
        return actual != null &&
            actual != false &&
            (actual is! Iterable || actual.isNotEmpty) &&
            actual.toString().trim().isNotEmpty;
      case 'contains':
        return actual is Iterable && actual.contains(operand);
      case 'set_equals':
        return actual is Iterable &&
            operand is Iterable &&
            actual.toSet().length == operand.toSet().length &&
            actual.toSet().containsAll(operand);
      case 'one_of':
        return operand is Iterable && operand.contains(actual);
      case 'not_equals':
        return actual != operand;
      case 'minimum':
        return num.tryParse(actual.toString()) != null &&
            num.parse(actual.toString()) >= (operand as num);
      default:
        return actual == operand;
    }
  }

  static Object? read(String path, MissionRuntimeState state) {
    final split = path.indexOf('.');
    if (split < 0) return state.equipmentState[path];
    final family = path.substring(0, split);
    final key = path.substring(split + 1);
    switch (family) {
      case 'config':
        return state.configurationValues[key];
      case 'placed':
        return state.placements[key];
      case 'link':
        return state.connectedNodePairs.contains(key);
      // Presentation-only paths for bench steps; never used by server rules.
      case 'connected':
        return state.connectedNodePairs.any((pair) => pair.startsWith('$key>'));
      case 'tested':
        return state.testStatusFor(key) == MissionTestStatus.completed;
      case 'tool':
        return state.toolApplications[key];
      case 'inspected':
        return state.hotspotStates[key] != null &&
            state.hotspotStates[key] != HotspotVisualState.neutral;
      case 'fact':
        return state.revealedFactIds.contains(key);
      case 'operation':
        return map(state.equipmentState['operations'])[key] == true;
      case 'decision':
        return map(map(state.equipmentState['phases'])[key])['decision'];
      case 'selection':
        return map(map(state.equipmentState['phases'])[key])['selection'];
      case 'classification':
        return map(state.equipmentState['classifications'])[key];
      case 'order':
        return map(map(state.equipmentState['phases'])[key])['order'];
      case 'sequence':
        return map(map(state.equipmentState['phases'])[key])['sequence_valid'];
      case 'observation':
        return state.observations[key];
      case 'interpretation':
        return state.interpretations[key];
      case 'setting':
        return state.equipmentState[key];
      case 'result':
        final result = map(map(state.equipmentState['results'])[key]);
        return result['operating'] == true &&
            result['input_revision'] ==
                (state.equipmentState['input_revision'] ?? 0);
      default:
        return null;
    }
  }

  static bool _formatValid(Map<String, dynamic> field, Object? value) {
    final text = value?.toString().trim() ?? '';
    if (field['required'] == false && text.isEmpty) return true;
    if (text.isEmpty) return false;
    if (field['type'] == 'toggle') return value is bool;
    if (field['type'] == 'dropdown') {
      return maps(field['options']).any((option) => option['id'] == value);
    }
    switch (field['format']) {
      case 'ipv4':
        final parts = text.split('.');
        return parts.length == 4 &&
            parts.every((part) =>
                RegExp(r'^(0|[1-9]\d{0,2})$').hasMatch(part) &&
                int.parse(part) <= 255);
      case 'port':
        final port = int.tryParse(text);
        return port != null && port > 0 && port <= 65535;
      case 'positive_integer':
        final number = int.tryParse(text);
        return number != null && number > 0;
      default:
        return true;
    }
  }

  static Map<String, dynamic> map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  static List<Map<String, dynamic>> maps(Object? value) =>
      value is List ? value.whereType<Map>().map(map).toList() : [];
  static List<String> strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : [];
  static Map<String, dynamic> item(Object? items, Object? id) {
    for (final item in maps(items)) {
      if (item['id'] == id) return item;
    }
    return {};
  }
}
