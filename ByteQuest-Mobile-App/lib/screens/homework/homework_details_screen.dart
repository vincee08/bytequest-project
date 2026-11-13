import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/supabase_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../data/mission_content_data.dart';
import '../../models/homework_model.dart';
import '../../services/homework_service.dart';

class HomeworkDetailsScreen extends StatefulWidget {
  const HomeworkDetailsScreen(
      {super.key, required this.assignment, this.service});
  final HomeworkAssignment assignment;
  final HomeworkService? service;

  @override
  State<HomeworkDetailsScreen> createState() => _HomeworkDetailsScreenState();
}

class _HomeworkDetailsScreenState extends State<HomeworkDetailsScreen>
    with WidgetsBindingObserver {
  late HomeworkAssignment _assignment;
  late HomeworkService _service;
  final _answer = TextEditingController();
  final _selectedFiles = <String>{};
  bool _busy = false;
  bool _uploadingFile = false;
  double? _uploadProgress;
  bool _refreshing = false;
  bool _draftTouched = false;
  String? _error;
  Timer? _poll;
  String get _draftKey =>
      'homework-draft:${SupabaseConfig.currentUserId}:${_assignment.id}';

  @override
  void initState() {
    super.initState();
    _assignment = widget.assignment;
    _service = widget.service ?? HomeworkService();
    _selectedFiles.addAll(_assignment.answerFiles.map((f) => f.id));
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreDraft());
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && !_busy && ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_refresh(quiet: true));
      }
    });
  }

  Future<void> _restoreDraft() async {
    if (_assignment.submission != null) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_draftKey);
    if (!mounted || stored == null || _draftTouched) return;
    try {
      final data = jsonDecode(stored) as Map;
      setState(() {
        _answer.text = data['answer'] as String? ?? '';
        _selectedFiles
          ..clear()
          ..addAll((data['files'] as List? ?? []).cast<String>());
      });
    } catch (_) {/* An invalid local draft never changes persisted homework. */}
  }

  Future<void> _saveDraft() async {
    _draftTouched = true;
    final draft =
        jsonEncode({'answer': _answer.text, 'files': _selectedFiles.toList()});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftKey, draft);
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (_refreshing || _busy) return;
    _refreshing = true;
    try {
      final rows = await _service.getAssignments(id: _assignment.id);
      if (!mounted || rows.isEmpty) return;
      setState(() {
        _assignment = rows.single;
        _error = null;
      });
    } catch (_) {
      if (mounted && !quiet) {
        setState(() => _error = MissionContentData.classActivitiesUnavailable);
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh(quiet: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _assignment;
    final submission = h.submission;
    return Scaffold(
        backgroundColor: AppTheme.backgroundOffWhite,
        appBar: AppBar(title: Text(h.title), actions: [
          IconButton(
              onPressed: _busy ? null : () => _refresh(),
              tooltip: MissionContentData.homeworkRefresh,
              icon: const Icon(Icons.refresh))
        ]),
        body: SafeArea(
            child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Text(h.classTitle, style: AppTheme.bodySmall),
                  const SizedBox(height: 12),
                  Semantics(
                      liveRegion: true,
                      child: Text(h.statusLabel, style: AppTheme.titleMedium)),
                  const SizedBox(height: 8),
                  Text(MissionContentData.homeworkDue(manilaDate(h.deadline))),
                  if (submission == null && h.deadlinePassed)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(MissionContentData.homeworkLateAllowed,
                            style: AppTheme.labelMedium)),
                  if (submission != null && submission.latenessSeconds > 0)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                            MissionContentData.homeworkLateBy(
                                latenessDuration(submission.latenessSeconds)),
                            style: AppTheme.labelMedium)),
                  const SizedBox(height: 20),
                  const LearnerSectionHeader(
                      title: MissionContentData.homeworkInstructions),
                  const SizedBox(height: 10),
                  LearnerSurface(child: SelectableText(h.instructions)),
                  if (h.instructionFiles.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const LearnerSectionHeader(
                        title: MissionContentData.homeworkFiles),
                    ...h.instructionFiles.map(_fileButton)
                  ],
                  const SizedBox(height: 20),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Semantics(
                            liveRegion: true,
                            child: Text(_error!,
                                style: const TextStyle(
                                    color: AppTheme.errorRed)))),
                  if (submission != null) ...[
                    Text(MissionContentData.homeworkSubmittedAt(
                        manilaDate(submission.submittedAt))),
                    const SizedBox(height: 8),
                    Text(
                        MissionContentData.homeworkEffectiveDeadline(
                            manilaDate(submission.effectiveDeadline)),
                        style: AppTheme.bodySmall),
                    const SizedBox(height: 12),
                    LearnerSurface(
                        child: SelectableText(submission.answer.isEmpty
                            ? MissionContentData.homeworkNoAnswer
                            : submission.answer)),
                    ...h.answerFiles.map(_fileButton),
                    if (submission.status == 'graded') ...[
                      const SizedBox(height: 20),
                      const LearnerSectionHeader(
                          title: MissionContentData.homeworkFeedback),
                      if (submission.feedback?.isNotEmpty ?? false)
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: SelectableText(submission.feedback!)),
                      if (submission.score != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(MissionContentData.homeworkScore(
                                submission.score!)))
                    ],
                  ] else ...[
                    const Text(MissionContentData.homeworkOutside),
                    const SizedBox(height: 16),
                    TextField(
                        controller: _answer,
                        enabled: !_busy,
                        maxLength: 20000,
                        minLines: 4,
                        maxLines: 10,
                        decoration: const InputDecoration(
                            labelText: MissionContentData.homeworkAnswer,
                            hintText: MissionContentData.homeworkAnswerHint,
                            border: OutlineInputBorder()),
                        onChanged: (_) => unawaited(_saveDraft())),
                    const SizedBox(height: 16),
                    const LearnerSectionHeader(
                        title: MissionContentData.homeworkAnswerFiles),
                    ...h.answerFiles
                        .where((f) => _selectedFiles.contains(f.id))
                        .map((f) => Row(children: [
                              Expanded(child: _fileButton(f)),
                              IconButton(
                                  tooltip:
                                      MissionContentData.homeworkRemoveFile,
                                  onPressed: _busy
                                      ? null
                                      : () {
                                          setState(() =>
                                              _selectedFiles.remove(f.id));
                                          unawaited(_saveDraft());
                                        },
                                  icon: const Icon(Icons.close))
                            ])),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                        onPressed: _busy ? null : _attach,
                        icon: const Icon(Icons.attach_file),
                        label: Text(_busy
                            ? MissionContentData.homeworkUploading
                            : MissionContentData.homeworkAddFile)),
                    const SizedBox(height: 8),
                    const Text(MissionContentData.homeworkFileHelp),
                    if (_uploadingFile) ...[
                      const SizedBox(height: 8),
                      Semantics(
                          liveRegion: true,
                          label: MissionContentData.homeworkUploading,
                          child:
                              LinearProgressIndicator(value: _uploadProgress)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                        onPressed: _busy ? null : _review,
                        child: Text(_busy
                            ? MissionContentData.loadingLabel
                            : MissionContentData.homeworkReview)),
                  ],
                ]))));
  }

  Widget _fileButton(HomeworkFile file) => TextButton.icon(
      style: TextButton.styleFrom(
          minimumSize: const Size(48, 48), alignment: Alignment.centerLeft),
      onPressed: _busy
          ? null
          : () async {
              try {
                final uri = await _service.fileUrl(file.id);
                if (!await launchUrl(uri,
                    mode: LaunchMode.externalApplication,
                    webOnlyWindowName: '_self')) {
                  throw StateError('FILE_OPEN_FAILED');
                }
              } catch (_) {
                if (mounted) {
                  setState(
                      () => _error = MissionContentData.homeworkOpenFailed);
                }
              }
            },
      icon: const Icon(Icons.download_outlined),
      label: Text(file.filename));

  Future<void> _attach() async {
    if (_busy) return;
    if (_assignment.answerFiles.length >= 5) {
      setState(() => _error = MissionContentData.homeworkFileLimit);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const [
            'pdf',
            'jpg',
            'jpeg',
            'png',
            'webp',
            'txt'
          ]);
      if (file == null) return;
      final length = await file.length();
      if (length == null || length < 1 || length > 10485760) {
        if (mounted) {
          setState(() => _error = MissionContentData.homeworkTooLarge);
        }
        return;
      }
      final uploaded = await _service.upload(
          assignmentId: _assignment.id,
          filename: file.name,
          bytes: await file.readAsBytes(),
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _uploadingFile = true;
                _uploadProgress = progress;
              });
            }
          });
      _selectedFiles.add(uploaded.id);
      await _saveDraft();
      final rows = await _service.getAssignments(id: _assignment.id);
      if (mounted) setState(() => _assignment = rows.single);
    } catch (_) {
      if (mounted) {
        setState(() => _error = MissionContentData.homeworkFileFailed);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _uploadingFile = false;
        });
      }
    }
  }

  Future<void> _review() async {
    if (_answer.text.trim().isEmpty && _selectedFiles.isEmpty) {
      setState(() => _error = MissionContentData.homeworkRequired);
      return;
    }
    final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text(MissionContentData.homeworkReviewTitle),
                content: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text(MissionContentData.homeworkReviewHelp),
                      const SizedBox(height: 12),
                      Text(MissionContentData.homeworkDue(
                          manilaDate(_assignment.deadline))),
                      if (_assignment.deadlinePassed)
                        const Text(MissionContentData.homeworkLateAllowed),
                      const SizedBox(height: 12),
                      Text(_answer.text.trim()),
                      ..._assignment.answerFiles
                          .where((f) => _selectedFiles.contains(f.id))
                          .map((f) => Text(f.filename)),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text(MissionContentData.homeworkCancel)),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text(MissionContentData.homeworkSubmit))
                ]));
    if (confirm != true || !mounted || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.submit(
          assignmentId: _assignment.id,
          answer: _answer.text.trim(),
          fileIds: _selectedFiles.toList());
      final rows = await _service.getAssignments(id: _assignment.id);
      if (mounted) setState(() => _assignment = rows.single);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {
      if (mounted) setState(() => _error = MissionContentData.homeworkFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
