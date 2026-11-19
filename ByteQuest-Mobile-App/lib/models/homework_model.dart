import 'package:intl/intl.dart';

import '../data/homework_content_data.dart';
import '../data/mission_content_data.dart';

String manilaDate(DateTime? value) => value == null
    ? MissionContentData.homeworkNoDeadline
    : '${DateFormat('MMM d, yyyy · h:mm a').format(value.toUtc().add(const Duration(hours: 8)))} (Manila)';

String latenessDuration(num seconds) {
  if (seconds <= 0) return 'On time';
  var minutes = (seconds / 60).floor();
  if (minutes == 0) return 'Less than 1 minute';
  final days = minutes ~/ 1440;
  minutes %= 1440;
  final hours = minutes ~/ 60;
  minutes %= 60;
  return [
    if (days > 0) '$days ${days == 1 ? 'day' : 'days'}',
    if (hours > 0) '$hours ${hours == 1 ? 'hour' : 'hours'}',
    if (minutes > 0) '$minutes ${minutes == 1 ? 'minute' : 'minutes'}',
  ].join(', ');
}

num? _number(Object? value) => num.tryParse(value?.toString() ?? '');
String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

/// One evaluation criterion of a homework assignment.
class HomeworkCriterion {
  final String id;
  final String criterion;
  final String? description;
  final num maxPoints;

  HomeworkCriterion.fromJson(Map<String, dynamic> json)
      : id = json['id']?.toString() ?? '',
        criterion = json['criterion']?.toString() ?? '',
        description = _text(json['description']),
        maxPoints = _number(json['max_points']) ?? 0;
}

class HomeworkSubmission {
  final String id;
  final String answer;

  /// Server workflow state: submitted, graded, finalized or released.
  final String evaluationStatus;

  /// `graded` only once the result is released (the meaning older screens and
  /// the Home summary rely on); otherwise `submitted`.
  final String status;
  final DateTime submittedAt;
  final DateTime? effectiveDeadline;
  final num latenessSeconds;
  final String? feedback;
  final num? score;
  final Map<String, num> criterionScores;
  final DateTime? releasedAt;

  const HomeworkSubmission._({
    required this.id,
    required this.answer,
    required this.evaluationStatus,
    required this.status,
    required this.submittedAt,
    required this.effectiveDeadline,
    required this.latenessSeconds,
    required this.feedback,
    required this.score,
    required this.criterionScores,
    required this.releasedAt,
  });

  /// Grade fields are read only for a released result, even if a response
  /// ever carried them earlier.
  factory HomeworkSubmission.fromJson(Map<String, dynamic> json) {
    final workflow = _text(json['evaluation_status']) ??
        (json['status'] == 'graded' ? 'released' : 'submitted');
    final released = workflow == 'released';
    final scores = json['criterion_scores'];
    return HomeworkSubmission._(
      id: json['id'] as String,
      answer: json['answer'] as String? ?? '',
      evaluationStatus: workflow,
      status: released ? 'graded' : 'submitted',
      submittedAt: DateTime.parse(json['submitted_at'] as String),
      effectiveDeadline:
          DateTime.tryParse(json['effective_deadline_at']?.toString() ?? ''),
      latenessSeconds: _number(json['lateness_seconds']) ?? 0,
      feedback: released ? json['feedback'] as String? : null,
      score: released ? _number(json['score']) : null,
      criterionScores: released && scores is Map
          ? {
              for (final entry in scores.entries)
                if (_number(entry.value) != null)
                  entry.key.toString(): _number(entry.value)!
            }
          : const {},
      releasedAt: released
          ? DateTime.tryParse(json['released_at']?.toString() ?? '')
          : null,
    );
  }

  bool get isReleased => evaluationStatus == 'released';
  bool get isBeingEvaluated =>
      evaluationStatus == 'graded' || evaluationStatus == 'finalized';

  String get statusLabel => isReleased
      ? HomeworkContentData.statusReleased
      : isBeingEvaluated
          ? HomeworkContentData.statusBeingEvaluated
          : MissionContentData.homeworkSubmitted;
}

class HomeworkFile {
  final String id;
  final String filename;
  final String kind;
  final String? submissionId;
  final int size;

  HomeworkFile.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        filename = json['filename'] as String,
        kind = json['kind'] as String,
        submissionId = json['submission_id'] as String?,
        size = (json['size_bytes'] as num).toInt();
}

class HomeworkAssignment {
  final String id;
  final String classId;
  final String classTitle;
  final String title;
  final String instructions;
  final DateTime? deadline;
  final DateTime serverNow;
  final HomeworkSubmission? submission;
  final List<HomeworkFile> files;
  final String? cocCode;
  final String? cocTitle;
  final String? missionCode;
  final String? missionTitle;
  final String? moduleCode;
  final String? moduleTitle;
  final List<String> learningObjectives;
  final List<HomeworkCriterion> criteria;
  final num maxScore;
  final String? submissionRequirements;

  HomeworkAssignment.fromJson(
    Map<String, dynamic> json, {
    required this.classTitle,
    required this.serverNow,
    required this.submission,
    required this.files,
  })  : id = json['id'] as String,
        classId = json['class_id'] as String,
        title = json['title'] as String,
        instructions = json['instructions'] as String,
        deadline = DateTime.tryParse(json['deadline_at']?.toString() ?? ''),
        cocCode = _text(json['coc_code']),
        cocTitle = _text(json['coc_title']),
        missionCode = _text(json['mission_code']),
        missionTitle = _text(json['mission_title']),
        moduleCode = _text(json['module_code']),
        moduleTitle = _text(json['module_title']),
        learningObjectives = [
          for (final item in json['learning_objectives'] as List? ?? const [])
            if (_text(item) != null) _text(item)!
        ],
        criteria = [
          for (final item in json['criteria'] as List? ?? const [])
            if (item is Map)
              HomeworkCriterion.fromJson(Map<String, dynamic>.from(item))
        ],
        maxScore = _number(json['max_score']) ?? 100,
        submissionRequirements = _text(json['submission_requirements']);

  String get statusLabel =>
      submission?.statusLabel ?? MissionContentData.homeworkAssigned;
  bool get deadlinePassed => deadline != null && serverNow.isAfter(deadline!);
  String get competencyLine => HomeworkContentData.competencyLine(
      cocCode: cocCode,
      cocTitle: cocTitle,
      missionCode: missionCode,
      missionTitle: missionTitle,
      moduleCode: moduleCode,
      moduleTitle: moduleTitle);
  List<HomeworkFile> get instructionFiles =>
      files.where((f) => f.kind == 'instruction').toList();
  List<HomeworkFile> get answerFiles => files
      .where((f) =>
          f.kind == 'answer' &&
          (submission == null
              ? f.submissionId == null
              : f.submissionId == submission!.id))
      .toList();
}
