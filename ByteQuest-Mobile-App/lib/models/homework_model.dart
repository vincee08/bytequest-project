import 'package:intl/intl.dart';

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

class HomeworkSubmission {
  final String id;
  final String answer;
  final String status;
  final DateTime submittedAt;
  final DateTime? effectiveDeadline;
  final num latenessSeconds;
  final String? feedback;
  final num? score;

  HomeworkSubmission.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        answer = json['answer'] as String? ?? '',
        status = json['status'] as String,
        submittedAt = DateTime.parse(json['submitted_at'] as String),
        effectiveDeadline =
            DateTime.tryParse(json['effective_deadline_at']?.toString() ?? ''),
        latenessSeconds =
            num.tryParse(json['lateness_seconds']?.toString() ?? '') ?? 0,
        feedback = json['feedback'] as String?,
        score = num.tryParse(json['score']?.toString() ?? '');

  String get statusLabel => status == 'graded'
      ? MissionContentData.homeworkGraded
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
        deadline = DateTime.tryParse(json['deadline_at']?.toString() ?? '');

  String get statusLabel =>
      submission?.statusLabel ?? MissionContentData.homeworkAssigned;
  bool get deadlinePassed => deadline != null && serverNow.isAfter(deadline!);
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
