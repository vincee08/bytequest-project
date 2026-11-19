import '../../runtime/mission_equipment_simulator.dart';
import '../../runtime/mission_runtime_models.dart';
import 'assembly_bench_layout.dart';

/// A part the learner can install on the bench (one placement-panel item).
final class BenchPart {
  const BenchPart({
    required this.id,
    required this.label,
    required this.asset,
    required this.orientations,
    required this.initialOrientation,
    required this.placedAt,
  });

  final String id;
  final String label;
  final String? asset;
  final List<String> orientations;
  final String initialOrientation;
  final String? placedAt;

  bool get rotatable => orientations.isNotEmpty;
  bool get placed => placedAt != null;
}

final class BenchSlot {
  const BenchSlot(
      {required this.id, required this.label, required this.categories});

  final String id;
  final String label;
  final List<String> categories;
}

final class BenchCable {
  const BenchCable({
    required this.id,
    required this.label,
    required this.asset,
    required this.interfaces,
    required this.linkedTo,
  });

  final String id;
  final String label;
  final String? asset;
  final List<String> interfaces;
  final String? linkedTo;
}

final class BenchHeader {
  const BenchHeader(
      {required this.id, required this.label, required this.interface});

  final String id;
  final String label;
  final String? interface;
}

final class BenchOperation {
  const BenchOperation({
    required this.id,
    required this.label,
    required this.enabled,
    required this.done,
  });

  final String id;
  final String label;
  final bool enabled;
  final bool done;
}

final class BenchStep {
  const BenchStep({
    required this.id,
    required this.label,
    required this.done,
    required this.focusKind,
    required this.focusId,
  });

  final String id;
  final String label;
  final bool done;
  final String? focusKind;
  final String? focusId;
}

final class BenchInspectable {
  const BenchInspectable({
    required this.id,
    required this.label,
    required this.asset,
    required this.inspection,
    required this.inspected,
  });

  final String id;
  final String label;
  final String? asset;
  final String inspection;
  final bool inspected;
}

/// Presentation model of one bench phase, derived from the typed definition
/// and runtime state. It never decides correctness; the server replays the
/// recorded evidence.
final class AssemblyBenchModel {
  AssemblyBenchModel._({
    required this.parts,
    required this.slots,
    required this.cables,
    required this.headers,
    required this.operations,
    required this.inspectables,
    required this.steps,
    required this.validCount,
    required this.invalidCount,
    required this.correctionCount,
    required this.startedAt,
  });

  factory AssemblyBenchModel.of(
      MissionPhaseDefinition phase, MissionRuntimeState state) {
    final p = phase.presentation;
    final equipment = MissionEquipmentSimulator.map(p['equipment']);
    final family = phase.resolvedInteraction;
    final placement = family == InteractionFamily.place
        ? p
        : MissionEquipmentSimulator.map(equipment['placement']);
    final connection = family == InteractionFamily.connect
        ? p
        : MissionEquipmentSimulator.map(equipment['connection']);
    final counts = MissionEquipmentSimulator.map(state.equipmentState['counts']);
    final started = state.equipmentState['started_at'];
    return AssemblyBenchModel._(
      parts: [
        for (final item in MissionEquipmentSimulator.maps(placement['items']))
          BenchPart(
            id: item['id'] as String,
            label: item['label'] as String? ?? item['id'] as String,
            asset: AssemblyBenchLayout.partAssets[item['id']],
            orientations:
                MissionEquipmentSimulator.strings(item['orientations']),
            initialOrientation: item['initial_orientation'] as String? ?? '0',
            placedAt: state.placements[item['id']],
          ),
      ],
      slots: [
        for (final slot
            in MissionEquipmentSimulator.maps(placement['destinations']))
          BenchSlot(
            id: slot['id'] as String,
            label: slot['label'] as String? ?? slot['id'] as String,
            categories: MissionEquipmentSimulator.strings(
                slot['socket_categories'] ?? slot['accepted_categories']),
          ),
      ],
      cables: [
        for (final source
            in MissionEquipmentSimulator.maps(connection['sources']))
          BenchCable(
            id: source['id'] as String,
            label: source['label'] as String? ?? source['id'] as String,
            asset: AssemblyBenchLayout.partAssets[source['id']],
            interfaces: MissionEquipmentSimulator.strings(source['interfaces']),
            linkedTo: _linkedDestination(state, source['id'] as String),
          ),
      ],
      headers: [
        for (final header
            in MissionEquipmentSimulator.maps(connection['destinations']))
          BenchHeader(
            id: header['id'] as String,
            label: header['label'] as String? ?? header['id'] as String,
            interface: header['interface'] as String?,
          ),
      ],
      operations: [
        for (final operation
            in MissionEquipmentSimulator.maps(equipment['operations']))
          BenchOperation(
            id: operation['id'] as String,
            label: operation['label'] as String? ?? operation['id'] as String,
            enabled: MissionEquipmentSimulator.conditionsMet(
                operation['requires'], state),
            done: MissionEquipmentSimulator.map(
                    state.equipmentState['operations'])[operation['id']] ==
                true,
          ),
      ],
      inspectables: family == InteractionFamily.inspect
          ? [
              for (final object in MissionEquipmentSimulator.maps(p['objects']))
                BenchInspectable(
                  id: object['id'] as String,
                  label: object['label'] as String? ?? object['id'] as String,
                  asset: object['imageAsset'] as String?,
                  inspection: object['inspection'] as String? ?? '',
                  inspected: state.hotspotStates[object['id']] != null &&
                      state.hotspotStates[object['id']] !=
                          HotspotVisualState.neutral,
                ),
            ]
          : const [],
      steps: [
        for (final step in MissionEquipmentSimulator.maps(p['bench_steps']))
          BenchStep(
            id: step['id'] as String,
            label: step['label'] as String,
            done: MissionEquipmentSimulator.conditionsMet(step['done'], state),
            focusKind: MissionEquipmentSimulator.map(step['focus'])['kind']
                as String?,
            focusId:
                MissionEquipmentSimulator.map(step['focus'])['id'] as String?,
          ),
      ],
      validCount: (counts['valid'] as num? ?? 0).toInt(),
      invalidCount: (counts['invalid'] as num? ?? 0).toInt(),
      correctionCount: (counts['corrections'] as num? ?? 0).toInt(),
      startedAt: started is String ? DateTime.tryParse(started) : null,
    );
  }

  final List<BenchPart> parts;
  final List<BenchSlot> slots;
  final List<BenchCable> cables;
  final List<BenchHeader> headers;
  final List<BenchOperation> operations;
  final List<BenchInspectable> inspectables;
  final List<BenchStep> steps;
  final int validCount;
  final int invalidCount;
  final int correctionCount;
  final DateTime? startedAt;

  /// Index of the first unfinished step, or the step count when all are done.
  int get currentStepIndex {
    final index = steps.indexWhere((step) => !step.done);
    return index < 0 ? steps.length : index;
  }

  BenchStep? get currentStep =>
      currentStepIndex < steps.length ? steps[currentStepIndex] : null;

  BenchPart? part(String? id) {
    for (final part in parts) {
      if (part.id == id) return part;
    }
    return null;
  }

  BenchCable? cable(String? id) {
    for (final cable in cables) {
      if (cable.id == id) return cable;
    }
    return null;
  }

  BenchSlot? slot(String? id) {
    for (final slot in slots) {
      if (slot.id == id) return slot;
    }
    return null;
  }

  /// Physically compatible slots for a part (practice highlights only).
  Iterable<BenchSlot> compatibleSlots(String partId,
      Map<String, dynamic> itemSpec, Map<String, String> placements) {
    final category = itemSpec['category'];
    return slots.where((slot) =>
        slot.categories.contains(category) &&
        !placements.entries
            .any((entry) => entry.key != partId && entry.value == slot.id));
  }

  /// Headers whose connector type matches the cable (practice highlights).
  Iterable<BenchHeader> compatibleHeaders(String cableId) {
    final interfaces = cable(cableId)?.interfaces ?? const [];
    return headers.where((header) =>
        interfaces.isEmpty || interfaces.contains(header.interface));
  }

  static String? _linkedDestination(MissionRuntimeState state, String source) {
    for (final pair in state.connectedNodePairs) {
      if (pair.startsWith('$source>')) return pair.substring(source.length + 1);
    }
    return null;
  }
}
