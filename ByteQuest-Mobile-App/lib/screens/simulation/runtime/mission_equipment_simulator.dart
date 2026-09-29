import '../../../data/mission_content_data.dart';
import 'mission_runtime_models.dart';

/// Deterministic equipment behavior for practice, not a competency evaluator.
/// No scores, passing percentages, rubric answers or release decisions exist
/// here. Assessment actions bypass this model and retain the trusted gateway.
abstract final class MissionEquipmentSimulator {
  static Map<String, dynamic> describeAction({
    required MissionSimulationDefinition definition,
    required MissionPhaseDefinition phase,
    required MissionRuntimeState state,
    required String actionType,
    required String? target,
    required Map<String, dynamic> value,
  }) {
    if (state.mode != MissionRuntimeMode.practice ||
        phase.presentation['equipment'] is! Map) {
      return value;
    }
    final spec = map(phase.presentation['equipment']);
    final next = Map<String, dynamic>.from(state.equipmentState);
    var valid = true;
    var feedback = MissionContentData.equipmentRecordedFeedback;
    final recorded = Map<String, dynamic>.from(value);
    final phaseValues = map(next['phases']);
    final phaseState = map(phaseValues[phase.id]);

    void reject(String message) {
      valid = false;
      feedback = message;
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
          feedback = value['tool_id'] == 'lan_cable_tester'
              ? state.connectedNodePairs.isEmpty
                  ? MissionContentData.disconnectedToolReading
                  : MissionContentData.connectedToolReading
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
        final part = item(phase.presentation['items'], value['item_id']);
        final slot =
            item(phase.presentation['destinations'], value['destination_id']);
        final categories =
            strings(slot['socket_categories'] ?? slot['accepted_categories']);
        if (part.isEmpty ||
            slot.isEmpty ||
            categories.isEmpty ||
            !categories.contains(part['category'])) {
          reject(MissionContentData.incompatiblePlacementFeedback);
        } else if (part['seating_orientation'] != null &&
            value['orientation'] != part['seating_orientation']) {
          reject(MissionContentData.orientationFeedback);
        } else if (!strings(part['requires_placements'])
            .every(state.placements.containsKey)) {
          reject(MissionContentData.placementPrerequisiteFeedback);
        } else if (state.placements.entries.any((entry) =>
            entry.key != value['item_id'] &&
            entry.value == value['destination_id'])) {
          reject(MissionContentData.occupiedDestinationFeedback);
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
              MissionContentData.equipmentUpdatedFeedback;
        }
        break;
      case 'test_completed':
        final checks = maps(spec['checks']);
        final readings = <Map<String, dynamic>>[];
        for (final check in checks) {
          final operating = conditionsMet(check['requires'], state);
          readings.add({
            'id': check['id'],
            'label': check['label'],
            'operating': operating,
            'reading': operating ? check['nominal'] : check['fault'],
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
        recorded['measured_result'] = result;
        if (phase.presentation['test_reveals_fact_id'] is String) {
          recorded['reveals_fact_id'] =
              phase.presentation['test_reveals_fact_id'];
        }
        feedback = MissionContentData.testResultRecordedFeedback;
        break;
    }
    if ((valid || actionType == 'configuration_applied') &&
        const {
          'connection_created',
          'configuration_applied',
          'placement_attempted',
          'sequence_reordered',
          'scenario_decision',
          'selection_confirmed',
          'equipment_operation',
          'tool_attempted',
        }.contains(actionType)) {
      next['input_revision'] =
          (next['input_revision'] as num? ?? 0).toInt() + 1;
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
