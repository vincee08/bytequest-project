enum LearnerQuizState {
  available,
  inProgress,
  submitted,
  completed,
  unavailable
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

int? _int(Object? value) => (value as num?)?.toInt();

double? _number(Object? value) => (value as num?)?.toDouble();

bool _isAutoKind(String? kind) =>
    kind == 'auto_deadline' || kind == 'auto_time_limit';

class LearnerQuizSummary {
  final String assignmentId;
  final String quizVersionId;
  final String quizId;
  final String title;
  final String? description;
  final String topic;
  final String? instructions;
  final String classId;
  final String classTitle;
  final String? cocCode;
  final String? cocTitle;
  final int questionCount;
  final DateTime? availableAt;
  final DateTime? dueAt;
  final int? attemptsAllowed;
  final bool isAvailable;
  final String? attemptId;
  final String? attemptStatus;
  final int answeredCount;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? closedReason;
  final DateTime? serverNow;
  final Map<String, String> eligibleAssignments;

  /// Server lifecycle status: not_started, in_progress, closed, unavailable,
  /// completed, awaiting_evaluation or released.
  final String? status;
  final int? timeLimitMinutes;
  final DateTime? expiresAt;
  final DateTime? submittedAt;
  final String? submissionKind;
  final String? evaluationStatus;
  final String? resultReleaseMode;
  final String? focus;
  final String? quizType;
  final String? difficulty;
  final List<String> moduleCodes;
  final int essayCount;

  const LearnerQuizSummary({
    required this.assignmentId,
    required this.quizVersionId,
    required this.quizId,
    required this.title,
    required this.description,
    required this.topic,
    required this.instructions,
    required this.classId,
    required this.classTitle,
    required this.cocCode,
    required this.cocTitle,
    required this.questionCount,
    required this.availableAt,
    required this.dueAt,
    required this.attemptsAllowed,
    required this.isAvailable,
    required this.attemptId,
    required this.attemptStatus,
    required this.answeredCount,
    required this.startedAt,
    required this.completedAt,
    this.closedReason,
    this.serverNow,
    this.eligibleAssignments = const {},
    this.status,
    this.timeLimitMinutes,
    this.expiresAt,
    this.submittedAt,
    this.submissionKind,
    this.evaluationStatus,
    this.resultReleaseMode,
    this.focus,
    this.quizType,
    this.difficulty,
    this.moduleCodes = const [],
    this.essayCount = 0,
  });

  LearnerQuizState get state {
    if (!isAvailable && attemptStatus == 'in_progress') {
      return LearnerQuizState.unavailable;
    }
    switch (attemptStatus) {
      case 'completed':
        return LearnerQuizState.completed;
      case 'submitted':
        return LearnerQuizState.submitted;
      case 'in_progress':
        return LearnerQuizState.inProgress;
      default:
        return isAvailable
            ? LearnerQuizState.available
            : LearnerQuizState.unavailable;
    }
  }

  bool get isAutoSubmitted =>
      attemptStatus != 'in_progress' && _isAutoKind(submissionKind);
  bool get awaitingEvaluation =>
      status == 'awaiting_evaluation' ||
      const {'pending', 'evaluated', 'finalized'}.contains(evaluationStatus);
  bool get resultReleased =>
      status == 'released' || evaluationStatus == 'released';
  bool get isTimed => timeLimitMinutes != null;
  bool get hasEssays => essayCount > 0;
  bool get usesInstructorRelease =>
      resultReleaseMode == 'instructor_release' || hasEssays;

  factory LearnerQuizSummary.fromJson(Map<String, dynamic> json) {
    return LearnerQuizSummary(
      assignmentId: json['assignment_id'] as String,
      quizVersionId: json['quiz_version_id'] as String,
      quizId: json['quiz_id'] as String,
      title: json['title'] as String? ?? 'Quiz',
      description: json['description'] as String?,
      topic: json['topic'] as String? ?? 'Supplementary review',
      instructions: json['instructions'] as String?,
      classId: json['class_id'] as String,
      classTitle: json['class_title'] as String? ?? 'Class',
      cocCode: json['coc_code'] as String?,
      cocTitle: json['coc_title'] as String?,
      questionCount: _int(json['question_count']) ?? 0,
      availableAt: _date(json['available_at']),
      dueAt: _date(json['due_at']),
      attemptsAllowed: _int(json['attempts_allowed']),
      isAvailable: json['is_available'] as bool? ?? false,
      attemptId: json['attempt_id'] as String?,
      attemptStatus: json['attempt_status'] as String?,
      answeredCount: _int(json['answered_count']) ?? 0,
      startedAt: _date(json['started_at']),
      completedAt: _date(json['completed_at']),
      closedReason: json['closed_reason'] as String?,
      serverNow: _date(json['server_now']),
      eligibleAssignments: {
        for (final link in json['eligible_assignments'] as List? ?? const [])
          link['assignment_id'] as String: link['class_id'] as String
      },
      status: json['status'] as String?,
      timeLimitMinutes: _int(json['time_limit_minutes']),
      expiresAt: _date(json['expires_at']),
      submittedAt: _date(json['submitted_at']),
      submissionKind: json['submission_kind'] as String?,
      evaluationStatus: json['evaluation_status'] as String?,
      resultReleaseMode: json['result_release_mode'] as String?,
      focus: json['focus'] as String?,
      quizType: json['quiz_type'] as String?,
      difficulty: json['difficulty'] as String?,
      moduleCodes: [
        for (final code in json['module_codes'] as List? ?? const [])
          code.toString()
      ],
      essayCount: _int(json['essay_count']) ?? 0,
    );
  }
}

/// A rubric criterion. During an attempt only the name and maximum points are
/// sent; descriptors and awarded points arrive after release.
class LearnerQuizRubricCriterion {
  final String id;
  final String criterion;
  final double maxPoints;
  final String? description;
  final double? points;

  const LearnerQuizRubricCriterion({
    required this.id,
    required this.criterion,
    required this.maxPoints,
    this.description,
    this.points,
  });

  factory LearnerQuizRubricCriterion.fromJson(Map<String, dynamic> json) =>
      LearnerQuizRubricCriterion(
        id: json['id']?.toString() ?? '',
        criterion: json['criterion'] as String? ?? '',
        maxPoints: _number(json['max_points']) ?? 0,
        description: (json['description'] as String?)?.trim().isEmpty ?? true
            ? null
            : json['description'] as String,
        points: _number(json['points']),
      );
}

List<LearnerQuizRubricCriterion> _rubric(Object? value) => [
      for (final item in value as List? ?? const [])
        LearnerQuizRubricCriterion.fromJson(
            Map<String, dynamic>.from(item as Map)),
    ];

class LearnerQuizQuestion {
  final String id;
  final String code;
  final String type;
  final String prompt;
  final List<String> options;
  final int orderIndex;
  final String? savedAnswer;
  final double points;
  final String? scenario;
  final int? minWords;
  final int? maxWords;
  final int maxAnswerLength;
  final List<LearnerQuizRubricCriterion> rubric;

  const LearnerQuizQuestion({
    required this.id,
    required this.code,
    required this.type,
    required this.prompt,
    required this.options,
    required this.orderIndex,
    this.savedAnswer,
    this.points = 1,
    this.scenario,
    this.minWords,
    this.maxWords,
    this.maxAnswerLength = 2000,
    this.rubric = const [],
  });

  bool get isEssay => type == 'scenario_essay';
  bool get isTextAnswer => type == 'identification' || isEssay;

  factory LearnerQuizQuestion.fromJson(Map<String, dynamic> json) =>
      LearnerQuizQuestion(
        id: json['id'] as String,
        code: json['code'] as String? ?? 'ITEM',
        type: json['type'] as String? ?? 'multiple_choice',
        prompt: json['prompt'] as String? ?? '',
        options: (json['options'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(growable: false),
        orderIndex: _int(json['order_index']) ?? 0,
        savedAnswer: json['saved_answer'] as String?,
        points: _number(json['points']) ?? 1,
        scenario: json['scenario'] as String?,
        minWords: _int(json['min_words']),
        maxWords: _int(json['max_words']),
        maxAnswerLength: _int(json['max_answer_length']) ??
            (json['type'] == 'scenario_essay' ? 10000 : 2000),
        rubric: _rubric(json['rubric']),
      );
}

class LearnerQuizAttempt {
  final DateTime? dueAt;
  final DateTime? serverNow;
  final String attemptId;
  final String status;
  final DateTime startedAt;
  final String assignmentId;
  final String title;
  final String? description;
  final String topic;
  final String? instructions;
  final String classTitle;
  final int versionNumber;
  final List<LearnerQuizQuestion> questions;
  final int? timeLimitMinutes;

  /// Server-authoritative end of the attempt (time limit or class deadline).
  final DateTime? expiresAt;
  final String? resultReleaseMode;
  final String? focus;

  const LearnerQuizAttempt({
    this.dueAt,
    this.serverNow,
    required this.attemptId,
    required this.status,
    required this.startedAt,
    required this.assignmentId,
    required this.title,
    required this.description,
    required this.topic,
    required this.instructions,
    required this.classTitle,
    required this.versionNumber,
    required this.questions,
    this.timeLimitMinutes,
    this.expiresAt,
    this.resultReleaseMode,
    this.focus,
  });

  factory LearnerQuizAttempt.fromJson(Map<String, dynamic> json) {
    final quiz = Map<String, dynamic>.from(json['quiz'] as Map? ?? const {});
    return LearnerQuizAttempt(
      dueAt: _date(json['due_at']),
      serverNow: _date(json['server_now']),
      attemptId: json['attempt_id'] as String,
      status: json['status'] as String? ?? 'in_progress',
      startedAt: DateTime.parse(json['started_at'] as String),
      assignmentId: quiz['assignment_id'] as String,
      title: quiz['title'] as String? ?? 'Quiz',
      description: quiz['description'] as String?,
      topic: quiz['topic'] as String? ?? 'Supplementary review',
      instructions: quiz['instructions'] as String?,
      classTitle: quiz['class_title'] as String? ?? 'Class',
      versionNumber: _int(quiz['version_number']) ?? 1,
      questions: (json['questions'] as List? ?? const [])
          .map((item) => LearnerQuizQuestion.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(growable: false),
      timeLimitMinutes: _int(json['time_limit_minutes']),
      expiresAt: _date(json['expires_at']),
      resultReleaseMode: json['result_release_mode'] as String?,
      focus: quiz['focus'] as String?,
    );
  }
}

class LearnerQuizItemResult {
  final String itemId;
  final String code;
  final String type;
  final String prompt;
  final String learnerAnswer;
  final bool isCorrect;
  final int orderIndex;

  /// False when the attempt was submitted automatically before this item was answered.
  final bool answered;

  /// Null before release and for essays awaiting a score.
  final bool? correct;
  final double? points;
  final double? pointsAwarded;
  final String? feedback;
  final List<LearnerQuizRubricCriterion> rubric;

  const LearnerQuizItemResult({
    required this.itemId,
    required this.code,
    required this.type,
    required this.prompt,
    required this.learnerAnswer,
    required this.isCorrect,
    required this.orderIndex,
    this.answered = true,
    this.correct,
    this.points,
    this.pointsAwarded,
    this.feedback,
    this.rubric = const [],
  });

  bool get isEssay => type == 'scenario_essay';

  factory LearnerQuizItemResult.fromJson(Map<String, dynamic> json) =>
      LearnerQuizItemResult(
        itemId: json['item_id'] as String,
        code: json['code'] as String? ?? 'ITEM',
        type: json['type'] as String? ?? 'multiple_choice',
        prompt: json['prompt'] as String? ?? '',
        learnerAnswer: json['learner_answer'] as String? ?? '',
        isCorrect: json['is_correct'] as bool? ?? false,
        orderIndex: _int(json['order_index']) ?? 0,
        answered: json['answered'] as bool? ?? true,
        correct: json['is_correct'] as bool?,
        points: _number(json['points']),
        pointsAwarded: _number(json['points_awarded']),
        feedback: json['feedback'] as String?,
        rubric: _rubric(json['rubric']),
      );
}

class LearnerQuizResult {
  final String attemptId;
  final String status;
  final String title;
  final String classTitle;
  final DateTime completedAt;
  final int correctCount;
  final int questionCount;
  final List<LearnerQuizItemResult> items;
  final DateTime? submittedAt;
  final String submissionKind;
  final String evaluationStatus;

  /// available (immediate result), awaiting_evaluation or released.
  final String resultStatus;
  final int answeredCount;
  final double? objectivePoints;
  final double? essayPoints;
  final double? totalPoints;
  final double? maxPoints;
  final double? percent;
  final DateTime? releasedAt;

  const LearnerQuizResult({
    required this.attemptId,
    required this.status,
    required this.title,
    required this.classTitle,
    required this.completedAt,
    required this.correctCount,
    required this.questionCount,
    required this.items,
    this.submittedAt,
    this.submissionKind = 'learner',
    this.evaluationStatus = 'not_required',
    this.resultStatus = 'available',
    this.answeredCount = 0,
    this.objectivePoints,
    this.essayPoints,
    this.totalPoints,
    this.maxPoints,
    this.percent,
    this.releasedAt,
  });

  bool get awaitingEvaluation => resultStatus == 'awaiting_evaluation';
  bool get released => resultStatus == 'released';
  bool get isAutoSubmitted => _isAutoKind(submissionKind);

  /// Score shown to the learner: final total after release, otherwise the
  /// objective points (or correct answers for results recorded before points).
  double get displayScore =>
      totalPoints ?? objectivePoints ?? correctCount.toDouble();
  double get displayMax => maxPoints ?? questionCount.toDouble();

  factory LearnerQuizResult.fromJson(Map<String, dynamic> json) =>
      LearnerQuizResult(
        attemptId: json['attempt_id'] as String,
        status: json['status'] as String? ?? 'completed',
        title: json['title'] as String? ?? 'Quiz result',
        classTitle: json['class_title'] as String? ?? 'Class',
        completedAt: DateTime.parse(
            (json['completed_at'] ?? json['submitted_at']) as String),
        correctCount: _int(json['correct_count']) ?? 0,
        questionCount: _int(json['question_count']) ?? 0,
        items: (json['item_results'] as List? ?? const [])
            .map((item) => LearnerQuizItemResult.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList(growable: false),
        submittedAt: _date(json['submitted_at']),
        submissionKind: json['submission_kind'] as String? ?? 'learner',
        evaluationStatus:
            json['evaluation_status'] as String? ?? 'not_required',
        resultStatus: json['result_status'] as String? ?? 'available',
        answeredCount: _int(json['answered_count']) ?? 0,
        objectivePoints: _number(json['objective_points']),
        essayPoints: _number(json['essay_points']),
        totalPoints: _number(json['total_points']),
        maxPoints: _number(json['max_points']),
        percent: _number(json['percent']),
        releasedAt: _date(json['released_at']),
      );
}
