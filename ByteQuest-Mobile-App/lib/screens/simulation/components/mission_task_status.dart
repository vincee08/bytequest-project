import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/mission_content_data.dart';
import '../runtime/mission_runtime_models.dart';

/// Describes recorded actions without determining correctness or competency.
/// Counts come from learner-visible requirements and existing runtime state.
List<String> missionPendingTasks(
    MissionPhaseDefinition phase, MissionRuntimeState state) {
  final pending = <String>[];
  final presentation = phase.presentation;
  final equipment = state.mode == MissionRuntimeMode.practice
      ? _map(presentation['equipment'])
      : <String, dynamic>{};
  final family = phase.resolvedInteraction;
  void count(
      String label, Iterable<String> ids, bool Function(String) recorded) {
    final required = ids.toSet();
    if (required.isEmpty) return;
    final done = required.where(recorded).length;
    if (done < required.length) {
      pending.add(MissionContentData.taskCount(label, done, required.length));
    }
  }

  if (family == InteractionFamily.inspect) {
    final objects = _ids(presentation['objects']);
    count(
        MissionContentData.inspectionsTaskLabel,
        objects.isEmpty ? phase.availableObjectIds : objects,
        (id) =>
            state.hotspotStates[id] != null &&
            state.hotspotStates[id] != HotspotVisualState.neutral);
  }
  final placement = family == InteractionFamily.place
      ? presentation
      : _map(equipment['placement']);
  count(MissionContentData.placementsTaskLabel, _ids(placement['items']),
      state.placements.containsKey);
  final connection = family == InteractionFamily.connect
      ? presentation
      : _map(equipment['connection']);
  count(MissionContentData.connectionsTaskLabel, _ids(connection['sources']),
      (id) => state.connectedNodePairs.any((pair) => pair.startsWith('$id>')));
  if (family == InteractionFamily.sequence &&
      !state.interactionCompletedPhaseIds.contains(phase.id)) {
    pending.add(MissionContentData.sequencePendingLabel);
  }
  if (family == InteractionFamily.configure) {
    count(
        MissionContentData.configurationTaskLabel,
        _ids(presentation['fields']),
        (id) =>
            state.configurationValues[id]?.toString().trim().isNotEmpty ==
            true);
  }
  return pending;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
List<String> _ids(Object? value) => value is List
    ? value
        .whereType<Map>()
        .map((item) => item['id'])
        .whereType<String>()
        .toList()
    : const [];

class MissionActionBar extends StatelessWidget {
  const MissionActionBar(
      {super.key,
      required this.status,
      required this.label,
      required this.onContinue,
      this.saving = false,
      this.complete = false});

  final String status;
  final String label;
  final VoidCallback? onContinue;
  final bool saving;
  final bool complete;

  @override
  Widget build(BuildContext context) => Material(
        color: AppTheme.cardWhite,
        child: Container(
          key: const ValueKey('mission-action-bar'),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.borderMedium))),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (MediaQuery.textScalerOf(context).scale(1) > 1.4)
                  OutlinedButton.icon(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                                scrollable: true,
                                title: Text(complete || onContinue != null
                                    ? MissionContentData.phaseCompleteLabel
                                    : MissionContentData.taskStatusLabel),
                                content: Text(status),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext),
                                      child: const Text(
                                          MissionContentData.backLabel))
                                ],
                              )),
                      icon: const Icon(Icons.checklist_rounded),
                      label: Text(saving
                          ? MissionContentData.workspaceSavingLabel
                          : complete || onContinue != null
                              ? MissionContentData.phaseCompleteLabel
                              : MissionContentData.taskStatusLabel))
                else
                  Semantics(
                      liveRegion: true,
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                                complete || onContinue != null
                                    ? Icons.check_circle_outline
                                    : Icons.info_outline,
                                size: 20,
                                color: AppTheme.deepBlue),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(
                                    saving
                                        ? MissionContentData
                                            .workspaceSavingLabel
                                        : status,
                                    style: AppTheme.bodySmall)),
                          ])),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const ValueKey('mission-next'),
                  onPressed: saving ? null : onContinue,
                  icon: saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.arrow_forward_rounded),
                  label: Text(label),
                ),
              ]),
        ),
      );
}
