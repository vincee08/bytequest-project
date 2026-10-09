import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../data/mission_content_data.dart';
import '../../models/practice_progress_model.dart';
import '../../services/practice_progress_service.dart';

class PracticeQuizScreen extends StatefulWidget {
  const PracticeQuizScreen({super.key, required this.coc, this.service});
  final String coc;
  final PracticeProgressService? service;
  @override
  State<PracticeQuizScreen> createState() => _PracticeQuizScreenState();
}

class _PracticeQuizScreenState extends State<PracticeQuizScreen> {
  late final _service = widget.service ?? PracticeProgressService();
  PracticeQuiz? _quiz;
  Map<String, int> _answers = {};
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final quiz = await _service.beginQuiz(widget.coc);
      if (!mounted) return;
      setState(() {
        _quiz = quiz;
        _answers = quiz.answers;
        _error = null;
      });
      if (quiz.status == 'generating') {
        _error = MissionContentData.practiceQuizFailed;
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = MissionContentData.practiceQuizFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(String id, int answer) async {
    final previous = Map<String, int>.from(_answers);
    setState(() {
      _answers[id] = answer;
      _busy = true;
    });
    try {
      await _service.saveAnswers(_quiz!.id, _answers);
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) {
        setState(() {
          _answers = previous;
          _error = MissionContentData.practiceQuizFailed;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final quiz = await _service.submitQuiz(_quiz!.id, _answers);
      if (mounted) {
        setState(() {
          _quiz = quiz;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = MissionContentData.practiceQuizFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quiz = _quiz;
    return PopScope(
        canPop: !_busy,
        child: Scaffold(
          backgroundColor: AppTheme.backgroundOffWhite,
          appBar:
              AppBar(title: const Text(MissionContentData.practiceQuizTitle)),
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(20), children: [
            const Text(MissionContentData.practiceQuizNotice),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (quiz == null || quiz.status == 'generating')
              FilledButton(
                  onPressed: _busy ? null : _load,
                  child: const Text(MissionContentData.practiceQuizRetry)),
            if (quiz != null && quiz.status != 'generating') ...[
              Text(quiz.json['source'] == 'ai'
                  ? MissionContentData.practiceQuizAi
                  : MissionContentData.practiceQuizFallback),
              if (quiz.submitted)
                Semantics(
                    liveRegion: true,
                    child: Text(
                        '${quiz.score}/5 (${quiz.score * 20}%). ${quiz.passed ? MissionContentData.practiceQuizPassed : MissionContentData.practiceQuizNeedsReview}',
                        style: AppTheme.titleMedium)),
              for (final question in quiz.questions)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(question['question'] as String,
                              style: AppTheme.labelLarge),
                          for (var i = 0;
                              i < (question['choices'] as List).length;
                              i++)
                            Semantics(
                                button: true,
                                selected: _answers[question['id']] == i,
                                label:
                                    (question['choices'] as List)[i] as String,
                                child: Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                          minimumSize:
                                              const Size.fromHeight(48)),
                                      onPressed: _busy || quiz.submitted
                                          ? null
                                          : () => _save(
                                              question['id'] as String, i),
                                      icon: Icon(_answers[question['id']] == i
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_unchecked),
                                      label: Text((question['choices']
                                          as List)[i] as String),
                                    ))),
                          if (quiz.submitted)
                            Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                    '${(question['choices'] as List)[question['answer'] as int]}\n${question['explanation']}')),
                        ])),
              if (!quiz.submitted)
                FilledButton(
                    onPressed: _busy || _answers.length != 5 ? null : _submit,
                    child: const Text(MissionContentData.practiceQuizSubmit)),
              if (quiz.submitted && !quiz.passed)
                FilledButton(
                    onPressed: _busy ? null : _load,
                    child: const Text(MissionContentData.practiceQuizRetry)),
            ],
          ])),
        ));
  }
}
