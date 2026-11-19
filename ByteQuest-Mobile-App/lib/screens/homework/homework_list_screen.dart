import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../data/homework_content_data.dart';
import '../../data/mission_content_data.dart';
import '../../models/homework_model.dart';
import '../../services/homework_service.dart';
import 'homework_details_screen.dart';

/// All assigned homework organised by COC, then mission. Scores and feedback
/// only appear inside a released result (see HomeworkDetailsScreen).
class HomeworkListScreen extends StatefulWidget {
  const HomeworkListScreen(
      {super.key, this.service, this.initial, this.classId});
  final HomeworkService? service;
  final List<HomeworkAssignment>? initial;
  final String? classId;

  @override
  State<HomeworkListScreen> createState() => _HomeworkListScreenState();
}

class _HomeworkListScreenState extends State<HomeworkListScreen> {
  late final HomeworkService _service = widget.service ?? HomeworkService();
  List<HomeworkAssignment> _rows = const [];
  bool _loading = true;
  bool _error = false;

  /// null = every COC; '' = homework not linked to a COC.
  String? _coc;
  String? _mission;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _rows = widget.initial!;
      _loading = false;
    }
    unawaited(_load(quiet: true));
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = _rows.isEmpty;
        _error = false;
      });
    }
    try {
      final rows = await _service.getAssignments(classId: widget.classId);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _rows.isEmpty;
      });
    }
  }

  List<String> get _cocs =>
      ({for (final h in _rows) h.cocCode}.whereType<String>().toList()..sort());
  bool get _hasUnlinked => _rows.any((h) => h.cocCode == null);
  List<(String, String?)> get _missions {
    if (_coc == null || _coc!.isEmpty) return const [];
    final seen = <String, String?>{};
    for (final h in _rows) {
      if (h.cocCode == _coc && h.missionCode != null) {
        seen[h.missionCode!] = h.missionTitle;
      }
    }
    return seen.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
  }

  List<HomeworkAssignment> get _shown => _rows.where((h) {
        if (_coc == '') return h.cocCode == null;
        if (_coc != null && h.cocCode != _coc) return false;
        return _mission == null || h.missionCode == _mission;
      }).toList();

  void _chooseCoc(String? coc) => setState(() {
        _coc = coc;
        _mission = null;
      });

  Future<void> _open(HomeworkAssignment h) async {
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) =>
                HomeworkDetailsScreen(assignment: h, service: _service)));
    if (mounted) await _load();
  }

  Widget _chip(String label, bool selected, VoidCallback onSelected) =>
      ChoiceChip(
          label: Text(label),
          selected: selected,
          materialTapTargetSize: MaterialTapTargetSize.padded,
          onSelected: (_) => onSelected());

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return Scaffold(
        backgroundColor: AppTheme.backgroundOffWhite,
        appBar:
            AppBar(title: const Text(HomeworkContentData.listTitle), actions: [
          IconButton(
              tooltip: HomeworkContentData.refresh,
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh))
        ]),
        body: SafeArea(
            child: RefreshIndicator(
                onRefresh: _load,
                // A class has a short homework list: lay it out eagerly so
                // large text never hides an off-screen state from assistive tech.
                child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(HomeworkContentData.listHelp),
                          const SizedBox(height: 12),
                          Semantics(
                              container: true,
                              label: HomeworkContentData.cocFilterLabel,
                              child: Wrap(spacing: 8, runSpacing: 4, children: [
                                _chip(HomeworkContentData.allCocs, _coc == null,
                                    () => _chooseCoc(null)),
                                for (final coc in _cocs)
                                  _chip(HomeworkContentData.cocLabel(coc),
                                      _coc == coc, () => _chooseCoc(coc)),
                                if (_hasUnlinked)
                                  _chip(HomeworkContentData.notLinked,
                                      _coc == '', () => _chooseCoc('')),
                              ])),
                          if (_missions.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Semantics(
                                container: true,
                                label: HomeworkContentData.missionFilterLabel,
                                child:
                                    Wrap(spacing: 8, runSpacing: 4, children: [
                                  _chip(
                                      HomeworkContentData.allMissions,
                                      _mission == null,
                                      () => setState(() => _mission = null)),
                                  for (final (code, title) in _missions)
                                    _chip(
                                        HomeworkContentData.missionLabel(
                                            code, title),
                                        _mission == code,
                                        () => setState(() => _mission = code)),
                                ])),
                          ],
                          const SizedBox(height: 16),
                          if (_loading)
                            const Padding(
                                padding: EdgeInsets.all(16),
                                child:
                                    Center(child: CircularProgressIndicator()))
                          else if (_error) ...[
                            Semantics(
                                liveRegion: true,
                                child: const Text(
                                    HomeworkContentData.listUnavailable,
                                    style:
                                        TextStyle(color: AppTheme.errorRed))),
                            const SizedBox(height: 8),
                            Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(48, 48)),
                                    onPressed: _load,
                                    child:
                                        const Text(HomeworkContentData.retry))),
                          ] else if (_rows.isEmpty)
                            const Text(HomeworkContentData.listEmpty)
                          else ...[
                            Semantics(
                                liveRegion: true,
                                child: Text(
                                    HomeworkContentData.count(
                                        shown.length, _rows.length),
                                    style: AppTheme.labelMedium)),
                            const SizedBox(height: 10),
                            if (shown.isEmpty)
                              const Text(HomeworkContentData.noMatch)
                            else
                              for (final h in shown)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _HomeworkCard(
                                        homework: h, onOpen: () => _open(h))),
                          ],
                        ])))));
  }
}

class _HomeworkCard extends StatelessWidget {
  const _HomeworkCard({required this.homework, required this.onOpen});
  final HomeworkAssignment homework;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => LearnerSurface(
      onTap: onOpen,
      semanticLabel: '${homework.title}. ${homework.statusLabel}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.assignment_outlined,
              size: 20, color: AppTheme.primaryBlue),
          const SizedBox(width: 8),
          Expanded(child: Text(homework.title, style: AppTheme.titleMedium)),
        ]),
        const SizedBox(height: 6),
        Text(homework.competencyLine, style: AppTheme.bodySmall),
        Text(homework.classTitle, style: AppTheme.bodySmall),
        Text(MissionContentData.homeworkDue(manilaDate(homework.deadline)),
            style: AppTheme.bodySmall),
        const SizedBox(height: 6),
        Text(homework.statusLabel,
            style: AppTheme.labelMedium.copyWith(color: AppTheme.primaryBlue)),
        Text(HomeworkContentData.maxScore(homework.maxScore),
            style: AppTheme.bodySmall),
      ]));
}
