import 'package:flutter/material.dart';
import 'dart:async';
import '../../data/mission_content_data.dart';
import '../../data/quiz_content_data.dart';
import '../../models/homework_model.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/learner_ui.dart';
import '../../models/learner_quiz_model.dart';
import '../simulation/practice_option_order.dart';
import '../../services/learner_quiz_service.dart';
import 'quiz_result_screen.dart';

class QuizTakingScreen extends StatefulWidget {
  const QuizTakingScreen({
    super.key,
    required this.attempt,
    this.service,
    this.draftStore,
    this.now,
  });

  final LearnerQuizAttempt attempt;
  final LearnerQuizService? service;
  final QuizEssayDraftStore? draftStore;

  /// Device clock. The server's expiry stays authoritative; this only drives
  /// the on-screen countdown (and lets tests advance time).
  final DateTime Function()? now;

  @override
  State<QuizTakingScreen> createState() => _QuizTakingScreenState();
}

class _QuizTakingScreenState extends State<QuizTakingScreen>
    with WidgetsBindingObserver {
  static const _essayAutosaveDelay = Duration(milliseconds: 1500);
  static const _finalFlushWindow = Duration(seconds: 5);
  static const _warningWindow = Duration(minutes: 1);

  late final LearnerQuizService _service =
      widget.service ?? LearnerQuizService();
  late final QuizEssayDraftStore _drafts =
      widget.draftStore ?? const SharedPreferencesQuizEssayDraftStore();
  final _textController = TextEditingController();
  late final Map<String, String> _answers;
  final Map<String, String> _savedAnswers = {};
  int _index = 0;
  bool _saving = false;
  bool _submitting = false;
  String? _error;
  String? _notice;
  late final PracticeOptionOrder _optionOrder;
  Timer? _availabilityPoll;
  Timer? _ticker;
  Timer? _expiryTimer;
  Timer? _essayDebounce;
  Timer? _finishRetry;
  DateTime? _dueAt;
  DateTime? _expiresAt;
  Duration _serverOffset = Duration.zero;
  bool _clockSynced = false;
  Duration? _remaining;
  bool _unavailable = false;
  bool _checkingAvailability = false;
  bool _closed = false;
  bool _expired = false;
  bool _finishing = false;
  bool _essaySaveFailed = false;
  bool get _locked => _closed || _unavailable || _expired;
  bool get _timed => widget.attempt.timeLimitMinutes != null;

  LearnerQuizQuestion get _question => widget.attempt.questions[_index];
  String? get _answer => _answers[_question.id];

  DateTime _deviceNow() => (widget.now ?? DateTime.now)();
  DateTime _serverNow() => _deviceNow().add(_serverOffset);

  @override
  void initState() {
    super.initState();
    _answers = {
      for (final question in widget.attempt.questions)
        if (question.savedAnswer?.isNotEmpty ?? false)
          question.id: question.savedAnswer!,
    };
    _savedAnswers.addAll(_answers);
    _optionOrder = PracticeOptionOrder.create(
      seed: PracticeOptionOrder.stableSeed(widget.attempt.attemptId),
      sourceOptions: {
        for (final question in widget.attempt.questions)
          question.id: question.type == 'true_false'
              ? const ['True', 'False']
              : question.options,
      },
    );
    _syncTextAnswer();
    WidgetsBinding.instance.addObserver(this);
    _dueAt = widget.attempt.dueAt;
    if (widget.attempt.serverNow != null) {
      _serverOffset = widget.attempt.serverNow!.difference(_deviceNow());
      _clockSynced = true;
    }
    _setExpiry(widget.attempt.expiresAt ?? widget.attempt.dueAt);
    _availabilityPoll = Timer.periodic(
        const Duration(seconds: 20), (_) => unawaited(_refreshAvailability()));
    unawaited(_restoreDrafts());
  }

  /// Schedules the end of the attempt from the server expiry. A one-shot
  /// timer ends it in the foreground; the per-second check against the
  /// server-calibrated clock also catches time that passed while suspended.
  void _setExpiry(DateTime? expiresAt) {
    _expiresAt = expiresAt;
    _ticker?.cancel();
    _expiryTimer?.cancel();
    _ticker = null;
    _expiryTimer = null;
    if (expiresAt == null || !_clockSynced) {
      _remaining = null;
      return;
    }
    final remaining = expiresAt.difference(_serverNow());
    if (remaining <= Duration.zero) {
      _closed = true;
      _expired = true;
      _remaining = Duration.zero;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => unawaited(_finishAutomatically()));
      return;
    }
    _remaining = remaining;
    _expiryTimer = Timer(remaining, () => unawaited(_onExpired()));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final expiresAt = _expiresAt;
    if (expiresAt == null || _expired || !mounted) return;
    final remaining = expiresAt.difference(_serverNow());
    if (remaining <= Duration.zero) {
      unawaited(_onExpired());
      return;
    }
    if (remaining <= _finalFlushWindow && _hasUnsavedText && !_saving) {
      unawaited(_saveEssayNow());
    }
    if (_timed || remaining <= _warningWindow) {
      setState(() => _remaining = remaining);
    } else {
      _remaining = remaining;
    }
  }

  bool get _hasUnsavedText {
    if (widget.attempt.questions.isEmpty || !_question.isEssay) return false;
    final text = (_answers[_question.id] ?? '').trim();
    return text.isNotEmpty && text != _savedAnswers[_question.id];
  }

  Future<void> _onExpired() async {
    if (_expired || !mounted) return;
    _ticker?.cancel();
    _expiryTimer?.cancel();
    _essayDebounce?.cancel();
    setState(() {
      _expired = true;
      _closed = true;
      _remaining = Duration.zero;
      _error = null;
    });
    await _finishAutomatically();
  }

  /// The server submits saved answers at the expiry time; reading the result
  /// lets it do so now and returns the automatic submission.
  Future<void> _finishAutomatically([int attempt = 0]) async {
    if (!mounted) return;
    setState(() => _finishing = true);
    try {
      final result = await _service.getResult(widget.attempt.attemptId);
      if (!mounted) return;
      await _clearDrafts();
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => QuizResultScreen(
            attemptId: widget.attempt.attemptId,
            initialResult: result,
            service: _service,
          ),
        ),
      );
    } catch (error) {
      debugPrint('Quiz automatic submission check failed: $error');
      if (!mounted) return;
      if (attempt < 5) {
        _finishRetry = Timer(const Duration(seconds: 3),
            () => unawaited(_finishAutomatically(attempt + 1)));
      } else {
        setState(() => _finishing = false);
      }
    }
  }

  Future<void> _restoreDrafts() async {
    final restored = <String, String>{};
    for (final question in widget.attempt.questions.where((q) => q.isEssay)) {
      try {
        final draft = await _drafts.read(widget.attempt.attemptId, question.id);
        if (draft == null || draft.trim().isEmpty) continue;
        if (draft.trim() == (_savedAnswers[question.id] ?? '').trim()) {
          await _drafts.clear(widget.attempt.attemptId, question.id);
          continue;
        }
        restored[question.id] = draft;
      } catch (error) {
        debugPrint('Quiz essay draft could not be read: $error');
      }
    }
    if (!mounted || restored.isEmpty || _locked) return;
    setState(() {
      _answers.addAll(restored);
      _notice = QuizContentData.essayRestored;
      _syncTextAnswer();
    });
    for (final entry in restored.entries) {
      if (!mounted || _locked) return;
      await _persist(entry.key, entry.value.trim(), background: true);
    }
  }

  Future<void> _clearDrafts() async {
    for (final question in widget.attempt.questions.where((q) => q.isEssay)) {
      try {
        await _drafts.clear(widget.attempt.attemptId, question.id);
      } catch (_) {/* A stale device draft is ignored once submitted. */}
    }
  }

  Future<void> _refreshAvailability() async {
    if (_checkingAvailability || _submitting || _expired) return;
    _checkingAvailability = true;
    try {
      final quizzes = await _service.getAvailableQuizzes();
      if (!mounted) return;
      final matches =
          quizzes.where((q) => q.attemptId == widget.attempt.attemptId);
      final quiz = matches.isEmpty ? null : matches.first;
      if (quiz != null && quiz.attemptStatus == 'completed') {
        await _onExpired();
        return;
      }
      setState(() {
        _unavailable = quiz == null ||
            !quiz.isAvailable ||
            quiz.attemptStatus != 'in_progress';
        _closed = quiz?.closedReason == 'deadline_passed';
        _dueAt = quiz?.dueAt;
        if (quiz?.serverNow != null) {
          _serverOffset = quiz!.serverNow!.difference(_deviceNow());
          _clockSynced = true;
        }
        if (quiz != null && quiz.isAvailable) {
          // An extension before expiry also extends this attempt.
          _setExpiry(quiz.expiresAt ?? quiz.dueAt);
        }
      });
    } catch (_) {
      /* Backend availability checks remain authoritative. */
    } finally {
      _checkingAvailability = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick();
      unawaited(_refreshAvailability());
    } else if (state == AppLifecycleState.paused) {
      unawaited(_saveEssayNow());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _expiryTimer?.cancel();
    _availabilityPoll?.cancel();
    _essayDebounce?.cancel();
    _finishRetry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _textController.dispose();
    super.dispose();
  }

  void _syncTextAnswer() {
    if (widget.attempt.questions.isEmpty) return;
    final value = _question.isTextAnswer ? (_answer ?? '') : '';
    _textController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.attempt.questions.isEmpty) {
      return const Scaffold(
        body: SafeArea(
          child: LearnerStateView(
            icon: Icons.quiz_outlined,
            title: QuizContentData.noQuestionsTitle,
            message: QuizContentData.noQuestionsMessage,
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: AppTheme.backgroundOffWhite,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: _saving || _submitting ? null : _confirmLeave,
                      tooltip: QuizContentData.leaveQuiz,
                      icon: const Icon(Icons.close_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.attempt.title,
                            style: AppTheme.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            QuizContentData.questionProgress(
                                _index + 1, widget.attempt.questions.length),
                            style: AppTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                    if (_saving)
                      Semantics(
                        label: QuizContentData.savingAnswer,
                        liveRegion: true,
                        child: const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    else
                      Semantics(
                        label:
                            QuizContentData.answersSaved(_savedAnswers.length),
                        child: const Icon(
                          Icons.cloud_done_outlined,
                          color: AppTheme.accentGreen,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: LearnerProgressBar(
                  value: (_index + 1) / widget.attempt.questions.length,
                  semanticLabel: QuizContentData.progressLabel,
                ),
              ),
              if (_timed && !_expired && _remaining != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: _CountdownBanner(remaining: _remaining!),
                )
              else if (_dueAt != null || _locked)
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Semantics(
                        liveRegion: _closed,
                        child: Text(_expired && _timed
                            ? QuizContentData.timeUpTitle
                            : _closed
                                ? MissionContentData.quizClosedDeadline
                                : _unavailable
                                    ? MissionContentData.quizAttemptUnavailable
                                    : MissionContentData.homeworkDue(
                                        manilaDate(_dueAt))))),
              if (_expired)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: _TimeUpPanel(checking: _finishing, timed: _timed),
                )
              else if (_closed)
                const Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Text(MissionContentData.quizExpiryHelp)),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _QuestionTypeLabel(type: _question.type),
                      const SizedBox(height: 12),
                      if (_question.isEssay &&
                          (_question.scenario?.isNotEmpty ?? false)) ...[
                        _ScenarioPanel(text: _question.scenario!),
                        const SizedBox(height: 12),
                      ],
                      LearnerSurface(
                        elevated: true,
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          _question.prompt,
                          style: AppTheme.titleLarge.copyWith(height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildAnswerEditor(),
                      if (_notice != null) ...[
                        const SizedBox(height: 14),
                        _Message(text: _notice!, tone: AppTheme.primaryBlue),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        _Message(text: _error!, tone: AppTheme.errorRed),
                      ],
                    ],
                  ),
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnswerEditor() {
    if (_question.isEssay) return _buildEssayEditor();
    if (_question.type == 'identification') {
      return LearnerSurface(
        child: TextField(
          controller: _textController,
          enabled: !_submitting && !_locked,
          maxLength: _question.maxAnswerLength,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: QuizContentData.answerLabel,
            hintText: QuizContentData.answerHint,
            helperText: QuizContentData.answerHelper,
          ),
          onChanged: (value) => _answers[_question.id] = value,
          onSubmitted: (_) => _saveCurrent(),
        ),
      );
    }

    final sourceOptions = _question.type == 'true_false'
        ? const ['True', 'False']
        : _question.options;
    final options = _optionOrder.optionsFor(_question.id, sourceOptions);
    if (options.isEmpty) {
      return const LearnerStateView(
        icon: Icons.warning_amber_rounded,
        title: QuizContentData.optionsUnavailableTitle,
        message: QuizContentData.optionsUnavailableMessage,
      );
    }
    return Column(
      children: [
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AnswerOption(
              label: option,
              selected: _answer == option,
              enabled: !_saving && !_submitting && !_locked,
              onTap: () => _selectOption(option),
            ),
          ),
      ],
    );
  }

  Widget _buildEssayEditor() {
    final question = _question;
    final words = QuizContentData.countWords(_textController.text);
    final saved = (_answers[question.id] ?? '').trim().isNotEmpty &&
        (_answers[question.id] ?? '').trim() == _savedAnswers[question.id];
    final status = _saving
        ? QuizContentData.essaySaving
        : _essaySaveFailed
            ? QuizContentData.essaySaveRetry
            : saved
                ? QuizContentData.essaySaved
                : (_answers[question.id] ?? '').trim().isEmpty
                    ? null
                    : QuizContentData.essayUnsaved;
    final wordStatus = QuizContentData.wordCountStatus(
        words, question.minWords, question.maxWords);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LearnerSurface(
          child: TextField(
            key: const ValueKey('quiz-essay-field'),
            controller: _textController,
            enabled: !_submitting && !_locked,
            minLines: 8,
            maxLines: null,
            maxLength: question.maxAnswerLength,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: QuizContentData.essayLabel,
              hintText: QuizContentData.essayHint,
              helperText: QuizContentData.wordGuidance(
                  question.minWords, question.maxWords),
              helperMaxLines: 2,
              counterText: '',
              alignLabelWithHint: true,
            ),
            onChanged: _onEssayChanged,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              label: wordStatus,
              child: ExcludeSemantics(
                child: Text(
                  wordStatus,
                  key: const ValueKey('quiz-essay-word-count'),
                  style: AppTheme.labelMedium,
                ),
              ),
            ),
            if (status != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  status,
                  style: AppTheme.labelMedium.copyWith(
                    color: _essaySaveFailed
                        ? AppTheme.accentOrange
                        : AppTheme.textMedium,
                  ),
                ),
              ),
          ],
        ),
        if (question.rubric.isNotEmpty) ...[
          const SizedBox(height: 14),
          _RubricPreview(question: question),
        ],
      ],
    );
  }

  void _onEssayChanged(String value) {
    final itemId = _question.id;
    setState(() {
      _answers[itemId] = value;
      _error = null;
    });
    unawaited(_drafts
        .write(widget.attempt.attemptId, itemId, value)
        .catchError((Object error) {
      debugPrint('Quiz essay draft could not be stored: $error');
    }));
    _essayDebounce?.cancel();
    _essayDebounce =
        Timer(_essayAutosaveDelay, () => unawaited(_saveEssayNow()));
  }

  Future<void> _saveEssayNow() async {
    if (_locked || _saving || widget.attempt.questions.isEmpty) return;
    final question = _question;
    if (!question.isEssay) return;
    final text = (_answers[question.id] ?? '').trim();
    if (text.isEmpty || text == _savedAnswers[question.id]) return;
    await _persist(question.id, text, background: true);
  }

  Widget _buildFooter() => Material(
        color: AppTheme.cardWhite,
        child: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.borderLight)),
            ),
            child: Row(
              children: [
                Flexible(
                  child: OutlinedButton.icon(
                    onPressed: _index == 0 || _saving || _submitting || _locked
                        ? null
                        : _goPrevious,
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text(QuizContentData.previous,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed:
                        _saving || _submitting || _locked ? null : _continue,
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_index == widget.attempt.questions.length - 1
                            ? Icons.fact_check_outlined
                            : Icons.arrow_forward_rounded),
                    label: Text(
                      _submitting
                          ? QuizContentData.submitting
                          : _index == widget.attempt.questions.length - 1
                              ? QuizContentData.reviewAndSubmit
                              : QuizContentData.next,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _selectOption(String value) async {
    setState(() {
      _answers[_question.id] = value;
      _error = null;
    });
    await _saveCurrent();
  }

  Future<bool> _saveCurrent() async {
    if (_locked) return false;
    final question = _question;
    final value = question.isTextAnswer
        ? _textController.text.trim()
        : (_answer ?? '').trim();
    if (value.isEmpty) {
      setState(() => _error = QuizContentData.answerRequired);
      return false;
    }
    if (question.isEssay && value == _savedAnswers[question.id]) return true;
    _essayDebounce?.cancel();
    return _persist(question.id, value);
  }

  /// Saves one answer to the server. Background essay saves report through
  /// the essay status line instead of the error banner.
  Future<bool> _persist(String itemId, String value,
      {bool background = false}) async {
    if (_locked) return false;
    setState(() {
      _saving = true;
      if (!background) {
        _error = null;
        _answers[itemId] = value;
      }
    });
    try {
      await _service.saveAnswer(
        attemptId: widget.attempt.attemptId,
        itemId: itemId,
        answer: value,
      );
      _savedAnswers[itemId] = value;
      if (mounted) setState(() => _essaySaveFailed = false);
      final isEssay =
          widget.attempt.questions.any((q) => q.id == itemId && q.isEssay);
      final latest = (_answers[itemId] ?? '').trim();
      if (isEssay && latest == value) {
        unawaited(_drafts
            .clear(widget.attempt.attemptId, itemId)
            .catchError((Object _) {}));
      } else if (isEssay && latest.isNotEmpty && mounted) {
        // Writing continued while this save was in flight: save the newer text too.
        _essayDebounce?.cancel();
        _essayDebounce =
            Timer(_essayAutosaveDelay, () => unawaited(_saveEssayNow()));
      }
      return true;
    } on LearnerQuizClosedException catch (error) {
      debugPrint('Quiz answer refused: ${error.code}');
      if (mounted) {
        setState(() => _saving = false);
        await _onExpired();
      }
      return false;
    } catch (error) {
      debugPrint('Quiz answer save failed: $error');
      if (mounted) {
        setState(() {
          if (background) {
            _essaySaveFailed = true;
          } else {
            _error = QuizContentData.answerNotSaved;
          }
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _goPrevious() async {
    final currentValue = _question.isTextAnswer
        ? _textController.text.trim()
        : (_answer ?? '').trim();
    if (currentValue.isNotEmpty && !await _saveCurrent()) return;
    if (!mounted) return;
    setState(() {
      _index--;
      _error = null;
      _syncTextAnswer();
    });
  }

  Future<void> _continue() async {
    if (!await _saveCurrent() || !mounted) return;
    if (_index < widget.attempt.questions.length - 1) {
      setState(() {
        _index++;
        _syncTextAnswer();
      });
      return;
    }
    await _showSubmissionReview();
  }

  Future<bool> _flushUnsaved() async {
    for (final question in widget.attempt.questions) {
      final text = (_answers[question.id] ?? '').trim();
      if (text.isEmpty || text == _savedAnswers[question.id]) continue;
      if (!await _persist(question.id, text)) return false;
    }
    return true;
  }

  Future<void> _showSubmissionReview() async {
    final missing = widget.attempt.questions
        .where((question) => (_answers[question.id]?.trim().isEmpty ?? true))
        .length;
    final submit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(QuizContentData.submitTitle, style: AppTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                missing == 0
                    ? QuizContentData.submitAllAnswered(
                        widget.attempt.questions.length)
                    : QuizContentData.submitMissing(missing),
                style: AppTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text(QuizContentData.reviewAnswers),
                  ),
                  FilledButton(
                    onPressed: missing == 0
                        ? () => Navigator.pop(context, true)
                        : null,
                    child: const Text(QuizContentData.submit),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (submit == true) await _submit();
  }

  Future<void> _submit() async {
    if (_submitting || _locked) return;
    if (!await _flushUnsaved() || !mounted || _locked) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await _service.submit(widget.attempt.attemptId);
      if (!mounted) return;
      await _clearDrafts();
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => QuizResultScreen(
            attemptId: widget.attempt.attemptId,
            initialResult: result,
            service: _service,
          ),
        ),
      );
    } catch (error) {
      debugPrint('Quiz submission failed: $error');
      if (mounted) {
        setState(() => _error = QuizContentData.submitFailed);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmLeave() async {
    unawaited(_saveEssayNow());
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(QuizContentData.leaveTitle),
        content: const Text(QuizContentData.leaveMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(QuizContentData.leaveStay),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(QuizContentData.leaveQuiz),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context);
  }
}

class _CountdownBanner extends StatelessWidget {
  const _CountdownBanner({required this.remaining});
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    final clock = remaining.inHours > 0
        ? '${remaining.inHours}:${(minutes % 60).toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
        : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    final warning = remaining <= const Duration(minutes: 1);
    final tone = warning ? AppTheme.accentOrange : AppTheme.deepBlue;
    return Semantics(
      liveRegion: warning,
      label: QuizContentData.timeLeftSemantics(minutes, seconds),
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: warning
                ? AppTheme.accentOrange.withValues(alpha: .08)
                : AppTheme.backgroundPaleBlue,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tone.withValues(alpha: .25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.timer_outlined, color: tone, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      QuizContentData.timeLeft(clock),
                      key: const ValueKey('quiz-countdown'),
                      style: AppTheme.titleMedium.copyWith(
                        color: tone,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              if (warning) ...[
                const SizedBox(height: 4),
                Text(QuizContentData.timeAlmostUp,
                    style: AppTheme.bodySmall.copyWith(color: tone)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeUpPanel extends StatelessWidget {
  const _TimeUpPanel({required this.checking, required this.timed});
  final bool checking;

  /// Deadline expiry is already announced by the closed-quiz label above.
  final bool timed;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        container: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.backgroundPaleBlue,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.timer_off_outlined, color: AppTheme.deepBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (timed) ...[
                      Text(QuizContentData.timeUpTitle,
                          style: AppTheme.titleMedium),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      checking
                          ? QuizContentData.timeUpChecking
                          : QuizContentData.timeUpMessage,
                      style: AppTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _ScenarioPanel extends StatelessWidget {
  const _ScenarioPanel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: '${QuizContentData.scenarioHeading}. $text',
        child: ExcludeSemantics(
          child: LearnerSurface(
            color: AppTheme.backgroundPaleBlue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  QuizContentData.scenarioHeading.toUpperCase(),
                  style: AppTheme.labelMedium.copyWith(
                    color: AppTheme.deepBlue,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .7,
                  ),
                ),
                const SizedBox(height: 6),
                Text(text, style: AppTheme.bodyMedium.copyWith(height: 1.45)),
              ],
            ),
          ),
        ),
      );
}

class _RubricPreview extends StatelessWidget {
  const _RubricPreview({required this.question});
  final LearnerQuizQuestion question;

  @override
  Widget build(BuildContext context) => LearnerSurface(
        color: AppTheme.surfaceMuted,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(QuizContentData.essayPoints(question.points),
                style:
                    AppTheme.labelMedium.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(QuizContentData.rubricHeading, style: AppTheme.bodySmall),
            const SizedBox(height: 4),
            for (final criterion in question.rubric)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  QuizContentData.rubricCriterion(
                      criterion.criterion, criterion.maxPoints),
                  style: AppTheme.bodySmall,
                ),
              ),
          ],
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.tone});
  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tone.withValues(alpha: .25)),
          ),
          child: Text(text, style: AppTheme.bodySmall),
        ),
      );
}

class _QuestionTypeLabel extends StatelessWidget {
  const _QuestionTypeLabel({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final label = switch (type) {
      'multiple_choice' => QuizContentData.typeMultipleChoice,
      'true_false' => QuizContentData.typeTrueFalse,
      'identification' => QuizContentData.typeIdentification,
      'scenario_based' => QuizContentData.typeScenario,
      'scenario_essay' => QuizContentData.typeScenarioEssay,
      _ => QuizContentData.typeQuestion,
    };
    return Text(
      label.toUpperCase(),
      style: AppTheme.labelMedium.copyWith(
        color: AppTheme.primaryBlue,
        fontWeight: FontWeight.w800,
        letterSpacing: .7,
      ),
    );
  }
}

class _AnswerOption extends StatelessWidget {
  const _AnswerOption({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        label: QuizContentData.optionSemantics(label, selected),
        child: Material(
          color: selected ? AppTheme.backgroundPaleBlue : AppTheme.cardWhite,
          shape: RoundedRectangleBorder(
            borderRadius: AppTheme.radiusLg,
            side: BorderSide(
              color: selected ? AppTheme.primaryBlue : AppTheme.borderLight,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: AppTheme.radiusLg,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color:
                          selected ? AppTheme.primaryBlue : AppTheme.textMedium,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(label, style: AppTheme.bodyMedium)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
