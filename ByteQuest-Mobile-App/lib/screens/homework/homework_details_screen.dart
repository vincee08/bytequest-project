import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/supabase_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../data/homework_content_data.dart';
import '../../data/homework_requirements_content_data.dart';
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

  List<HomeworkFile> get _chosenFiles => _assignment.answerFiles
      .where((f) => _selectedFiles.contains(f.id))
      .toList();

  /// What still stops this submission, or null when it meets the rule.
  String? get _missing =>
      _assignment.rule.missing(_answer.text, _chosenFiles);

  @override
  Widget build(BuildContext context) {
    final h = _assignment;
    final submission = h.submission;
    final rule = h.rule;
    final missing = submission == null ? _missing : null;
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
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(HomeworkContentData.maxScore(h.maxScore),
                          style: AppTheme.labelMedium)),
                  if (h.cocCode != null ||
                      h.missionCode != null ||
                      h.moduleCode != null) ...[
                    const SizedBox(height: 20),
                    const LearnerSectionHeader(
                        title: HomeworkContentData.competencyTitle),
                    const SizedBox(height: 10),
                    LearnerSurface(
                        color: AppTheme.softBlueAccent,
                        child: Text(h.competencyLine,
                            style: AppTheme.labelLarge
                                .copyWith(color: AppTheme.navy))),
                  ],
                  const SizedBox(height: 20),
                  const LearnerSectionHeader(
                      title: MissionContentData.homeworkInstructions),
                  const SizedBox(height: 10),
                  LearnerSurface(child: SelectableText(h.instructions)),
                  if (h.learningObjectives.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const LearnerSectionHeader(
                        title: HomeworkContentData.objectivesTitle),
                    const SizedBox(height: 10),
                    LearnerSurface(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          for (final objective in h.learningObjectives)
                            Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                          padding: EdgeInsets.only(top: 2),
                                          child: Icon(
                                              Icons.check_circle_outline,
                                              size: 18,
                                              color: AppTheme.primaryBlue)),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(objective)),
                                    ])),
                        ])),
                  ],
                  if (h.criteria.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const LearnerSectionHeader(
                      title: HomeworkContentData.criteriaTitle),
                  const SizedBox(height: 10),
                  LearnerSurface(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        for (final criterion in h.criteria)
                          Semantics(
                              container: true,
                              label: HomeworkContentData.criterionSemantics(
                                  criterion.criterion, criterion.maxPoints),
                              child: ExcludeSemantics(
                                  child: Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  Text(criterion.criterion,
                                                      style:
                                                          AppTheme.labelLarge),
                                                  if (criterion.description !=
                                                      null)
                                                    Text(
                                                        criterion.description!,
                                                        style:
                                                            AppTheme.bodySmall),
                                                ])),
                                            const SizedBox(width: 12),
                                            Flexible(
                                                child: Text(
                                                    HomeworkContentData.points(
                                                        criterion.maxPoints),
                                                    textAlign: TextAlign.end,
                                                    style:
                                                        AppTheme.labelMedium)),
                                          ])))),
                      ])),
                  ],
                  if (h.submissionRequirements != null) ...[
                    const SizedBox(height: 20),
                    const LearnerSectionHeader(
                        title: HomeworkContentData.requirementsTitle),
                    const SizedBox(height: 10),
                    LearnerSurface(
                        child: SelectableText(h.submissionRequirements!)),
                  ],
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
                    if (submission.isBeingEvaluated) ...[
                      const SizedBox(height: 20),
                      Semantics(
                          liveRegion: true,
                          child: LearnerSurface(
                              color: AppTheme.softBlueAccent,
                              child: Text(HomeworkContentData.beingEvaluatedHelp,
                                  style: AppTheme.bodyMedium))),
                    ],
                    // Score and feedback exist only for a released result.
                    if (submission.isReleased) ...[
                      const SizedBox(height: 20),
                      const LearnerSectionHeader(
                          title: HomeworkContentData.resultTitle),
                      if (submission.score != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                                HomeworkContentData.score(
                                    submission.score!, h.maxScore),
                                style: AppTheme.titleLarge)),
                      if (submission.criterionScores.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(HomeworkContentData.resultCriteriaTitle,
                            style: AppTheme.labelLarge),
                        for (final criterion in h.criteria)
                          if (submission.criterionScores[criterion.id] != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: Text(criterion.criterion)),
                                      const SizedBox(width: 12),
                                      Flexible(
                                          child: Text(
                                              HomeworkContentData.criterionScore(
                                                  submission.criterionScores[
                                                      criterion.id]!,
                                                  criterion.maxPoints),
                                              textAlign: TextAlign.end,
                                              style: AppTheme.labelLarge)),
                                    ])),
                      ],
                      if (submission.feedback?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 16),
                        const LearnerSectionHeader(
                            title: MissionContentData.homeworkFeedback),
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: SelectableText(submission.feedback!)),
                      ],
                    ],
                  ] else ...[
                    const LearnerSectionHeader(
                        title: HomeworkRequirementsContent.title),
                    const SizedBox(height: 10),
                    LearnerSurface(
                        key: const ValueKey('homework-submission-rule'),
                        color: AppTheme.softBlueAccent,
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(Icons.assignment_turned_in_outlined,
                                      size: 20, color: AppTheme.primaryBlue)),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(rule.description,
                                      style: AppTheme.labelLarge
                                          .copyWith(color: AppTheme.navy))),
                            ])),
                    const SizedBox(height: 16),
                    const Text(MissionContentData.homeworkOutside),
                    const SizedBox(height: 16),
                    if (rule.takesAnswer) ...[
                      TextField(
                          key: const ValueKey('homework-answer-field'),
                          controller: _answer,
                          enabled: !_busy,
                          maxLength: 20000,
                          minLines: 4,
                          maxLines: 10,
                          decoration: InputDecoration(
                              labelText: MissionContentData.homeworkAnswer,
                              hintText: rule.format == 'answer'
                                  ? HomeworkRequirementsContent.answerOnlyHint
                                  : rule.format == 'answer_and_file'
                                      ? HomeworkRequirementsContent
                                          .answerWithFilesHint
                                      : MissionContentData.homeworkAnswerHint,
                              border: const OutlineInputBorder()),
                          onChanged: (_) {
                            setState(() {});
                            unawaited(_saveDraft());
                          }),
                      const SizedBox(height: 16),
                    ],
                    if (rule.takesFiles) ...[
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
                        key: const ValueKey('homework-attach'),
                        onPressed: _busy ? null : _attach,
                        icon: Icon(rule.imagesOnly
                            ? Icons.add_photo_alternate_outlined
                            : Icons.attach_file),
                        label: Text(_busy
                            ? MissionContentData.homeworkUploading
                            : rule.imagesOnly
                                ? HomeworkRequirementsContent.addImage
                                : MissionContentData.homeworkAddFile)),
                    const SizedBox(height: 8),
                    Text(rule.imagesOnly
                        ? HomeworkRequirementsContent.imagesHelp
                        : MissionContentData.homeworkFileHelp),
                    if (_uploadingFile) ...[
                      const SizedBox(height: 8),
                      Semantics(
                          liveRegion: true,
                          label: MissionContentData.homeworkUploading,
                          child:
                              LinearProgressIndicator(value: _uploadProgress)),
                    ],
                    ],
                    const SizedBox(height: 20),
                    if (missing != null) ...[
                      Semantics(
                          liveRegion: true,
                          child: Row(
                              key: const ValueKey('homework-missing'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.info_outline,
                                    size: 18, color: AppTheme.primaryBlue),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(missing,
                                        style: AppTheme.labelMedium)),
                              ])),
                      const SizedBox(height: 10),
                    ],
                    FilledButton(
                        key: const ValueKey('homework-review'),
                        onPressed: _busy || missing != null ? null : _review,
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
    if (_busy || !_assignment.rule.takesFiles) return;
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
          allowedExtensions: _assignment.rule.allowedExtensions);
      if (file == null) return;
      if (_assignment.rule.imagesOnly &&
          !HomeworkSubmissionRule.imageExtensions
              .contains(file.name.split('.').last.toLowerCase())) {
        if (mounted) {
          setState(() => _error = HomeworkRequirementsContent.notImage);
        }
        return;
      }
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
    } on HomeworkRuleException catch (refusal) {
      if (mounted) setState(() => _error = refusal.message);
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
    final rule = _assignment.rule;
    final missing = _missing;
    if (missing != null) {
      setState(() => _error = missing);
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
                      if (rule.takesAnswer) Text(_answer.text.trim()),
                      if (rule.takesFiles)
                        ..._chosenFiles.map((f) => Text(f.filename)),
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
      // Only the parts this homework accepts are sent.
      await _service.submit(
          assignmentId: _assignment.id,
          answer: rule.takesAnswer ? _answer.text.trim() : '',
          fileIds: rule.takesFiles
              ? _chosenFiles.map((f) => f.id).toList()
              : const []);
      final rows = await _service.getAssignments(id: _assignment.id);
      if (mounted) setState(() => _assignment = rows.single);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } on HomeworkRuleException catch (refusal) {
      if (mounted) setState(() => _error = refusal.message);
    } catch (_) {
      if (mounted) setState(() => _error = MissionContentData.homeworkFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
