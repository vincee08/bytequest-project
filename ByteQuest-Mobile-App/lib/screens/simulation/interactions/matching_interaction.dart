import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/mission_content_data.dart';
import '../components/tool_tray.dart';
import '../runtime/mission_runtime_models.dart';
import 'multi_select_interaction.dart';

class MatchingInteraction extends StatefulWidget {
  const MatchingInteraction({
    super.key,
    required this.phase,
    required this.state,
    required this.onAction,
    this.enabled = true,
  });

  final MissionPhaseDefinition phase;
  final MissionRuntimeState state;
  final MissionActionCallback onAction;
  final bool enabled;

  @override
  State<MatchingInteraction> createState() => _MatchingInteractionState();
}

class _MatchingInteractionState extends State<MatchingInteraction> {
  String? _selectedSource;
  bool _reviewingCompletedControls = false;

  @override
  void didUpdateWidget(covariant MatchingInteraction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase.id != widget.phase.id) {
      _selectedSource = null;
      _reviewingCompletedControls = false;
      return;
    }
    if (!widget.state.interactionCompletedPhaseIds.contains(widget.phase.id)) {
      _reviewingCompletedControls = false;
    }
    if (!_reviewingCompletedControls &&
        _selectedSource != null &&
        widget.state.matches.containsKey(_selectedSource)) {
      _selectedSource = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = interactionItems(widget.phase.presentation['sources']);
    final destinations =
        interactionItems(widget.phase.presentation['destinations']);
    final interactionComplete =
        widget.state.interactionCompletedPhaseIds.contains(widget.phase.id);
    final showControls = !interactionComplete || _reviewingCompletedControls;
    final availableSources = _reviewingCompletedControls
        ? sources
        : sources
            .where((source) => !widget.state.matches.containsKey(source.id))
            .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showControls)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Text('Sources'),
                    for (final source in availableSources)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Semantics(
                          button: true,
                          selected: _selectedSource == source.id,
                          child: OutlinedButton(
                            key: ValueKey('matching-source-${source.id}'),
                            onPressed: widget.enabled
                                ? () =>
                                    setState(() => _selectedSource = source.id)
                                : null,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: Text(source.label),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    const Text('Matches'),
                    for (final destination in destinations)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton(
                          key: ValueKey(
                            'matching-destination-${destination.id}',
                          ),
                          onPressed: widget.enabled && _selectedSource != null
                              ? () => _match(destination.id)
                              : null,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: Text(destination.label),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        if (widget.state.matches.isNotEmpty) ...[
          if (showControls) const SizedBox(height: 12),
          _RecordedMatches(
            sources: sources,
            destinations: destinations,
            matches: widget.state.matches,
          ),
        ],
        if (interactionComplete)
          TextButton.icon(
            key: const ValueKey('matching-toggle-completed-controls'),
            onPressed: widget.enabled
                ? () => setState(() {
                      _reviewingCompletedControls =
                          !_reviewingCompletedControls;
                    })
                : null,
            icon: Icon(
              _reviewingCompletedControls
                  ? Icons.visibility_off_outlined
                  : Icons.edit_outlined,
            ),
            label: Text(
              _reviewingCompletedControls
                  ? MissionContentData.hideCompletedControlsLabel
                  : MissionContentData.reviewOrChangeMatchesLabel,
            ),
          ),
      ],
    );
  }

  void _match(String destination) {
    final source = _selectedSource!;
    setState(() => _selectedSource = null);
    unawaited(widget.onAction('match_created', destination, {
      'source_id': source,
      'destination_id': destination,
      'input_method': 'tap',
    }));
  }
}

class _RecordedMatches extends StatelessWidget {
  const _RecordedMatches({
    required this.sources,
    required this.destinations,
    required this.matches,
  });

  final List<InteractionItem> sources;
  final List<InteractionItem> destinations;
  final Map<String, String> matches;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: MissionContentData.recordedMatchesLabel,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.backgroundPaleBlue,
            borderRadius: AppTheme.radiusSm,
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: matches.entries
                .map(
                  (entry) => Chip(
                    label: Text(
                      '${_labelFor(sources, entry.key)} → '
                      '${_labelFor(destinations, entry.value)}',
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      );

  String _labelFor(List<InteractionItem> items, String id) {
    for (final item in items) {
      if (item.id == id) return item.label;
    }
    return id;
  }
}
