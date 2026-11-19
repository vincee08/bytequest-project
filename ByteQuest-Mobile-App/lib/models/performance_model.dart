/// Learner performance projection returned by the `get_my_performance()`
/// SECURITY INVOKER RPC (supabase/migrations/20261119170300). Every value is
/// the learner's own RLS-visible data; assessment results are released only.
class PerformanceSnapshot {
  const PerformanceSnapshot({
    required this.progress,
    required this.competency,
    required this.quizzes,
    required this.homework,
    required this.assessments,
    required this.practice,
    required this.summary,
    required this.updatedAt,
  });

  final PerformanceProgress progress;
  final List<CompetencyOutcome> competency;
  final List<QuizScore> quizzes;
  final List<HomeworkScore> homework;
  final List<ReleasedAssessmentScore> assessments;
  final PracticeSummary practice;

  /// Server-computed averages and counts for the compact Progress section.
  final PerformanceSummary summary;
  final DateTime updatedAt;

  /// True when the learner has no recorded activity of any kind yet.
  /// Anything the compact Progress-screen summary can average or count.
  bool get hasScoredWork =>
      quizzes.isNotEmpty ||
      summary.homeworkReleased > 0 ||
      assessments.isNotEmpty ||
      competency.isNotEmpty;

  bool get hasActivity =>
      progress.completedItems > 0 ||
      competency.isNotEmpty ||
      quizzes.isNotEmpty ||
      homework.isNotEmpty ||
      assessments.isNotEmpty ||
      practice.runs > 0 ||
      practice.missionsVerified > 0;

  factory PerformanceSnapshot.fromJson(Map<String, dynamic> json) {
    final scores = _map(json['scores']);
    return PerformanceSnapshot(
      progress: PerformanceProgress.fromJson(_map(json['progress'])),
      competency: _list(json['competency'], CompetencyOutcome.fromJson),
      quizzes: _list(scores['quizzes'], QuizScore.fromJson),
      homework: _list(scores['homework'], HomeworkScore.fromJson),
      assessments: _list(json['assessments'], ReleasedAssessmentScore.fromJson),
      practice: PracticeSummary.fromJson(_map(json['practice'])),
      summary: PerformanceSummary.fromJson(_map(json['summary'])),
      updatedAt: _date(json['updated_at']) ?? DateTime.now().toUtc(),
    );
  }
}

class PerformanceProgress {
  const PerformanceProgress({
    required this.overallPercent,
    required this.completedItems,
    required this.totalItems,
    required this.cocs,
  });

  final double? overallPercent;
  final int completedItems;
  final int totalItems;
  final List<CocPerformance> cocs;

  factory PerformanceProgress.fromJson(Map<String, dynamic> json) =>
      PerformanceProgress(
        overallPercent: _double(json['overall_percent']),
        completedItems: _int(json['completed_items']),
        totalItems: _int(json['total_items']),
        cocs: _list(json['cocs'], CocPerformance.fromJson),
      );
}

class CocPerformance {
  const CocPerformance({
    required this.cocCode,
    required this.title,
    required this.percent,
    required this.completedItems,
    required this.totalItems,
    required this.modulesCompleted,
    required this.modulesTotal,
  });

  final String cocCode;
  final String title;
  final double? percent;
  final int completedItems;
  final int totalItems;
  final int modulesCompleted;
  final int modulesTotal;

  String get label => cocCode.toUpperCase();

  factory CocPerformance.fromJson(Map<String, dynamic> json) => CocPerformance(
        cocCode: json['coc_code'] as String? ?? '',
        title: json['title'] as String? ?? '',
        percent: _double(json['percent']),
        completedItems: _int(json['completed_items']),
        totalItems: _int(json['total_items']),
        modulesCompleted: _int(json['modules_completed']),
        modulesTotal: _int(json['modules_total']),
      );
}

class CompetencyOutcome {
  const CompetencyOutcome({
    required this.criterion,
    required this.code,
    required this.missionCode,
    required this.missionTitle,
    required this.outcome,
    required this.releasedAt,
  });

  final String? criterion;
  final String? code;
  final String? missionCode;
  final String? missionTitle;

  /// Released criterion observation: satisfied, not_satisfied, requires_review
  /// or not_evaluated.
  final String outcome;
  final DateTime? releasedAt;

  bool get achieved => outcome == 'satisfied';

  factory CompetencyOutcome.fromJson(Map<String, dynamic> json) =>
      CompetencyOutcome(
        criterion: json['criterion'] as String?,
        code: json['code'] as String?,
        missionCode: json['mission_code'] as String?,
        missionTitle: json['mission_title'] as String?,
        outcome: json['outcome'] as String? ?? 'not_evaluated',
        releasedAt: _date(json['released_at']),
      );
}

class QuizScore {
  const QuizScore({
    required this.attemptId,
    required this.title,
    required this.percent,
    required this.correctCount,
    required this.questionCount,
    required this.submittedAt,
  });

  final String attemptId;
  final String? title;
  final double? percent;
  final int? correctCount;
  final int? questionCount;
  final DateTime? submittedAt;

  factory QuizScore.fromJson(Map<String, dynamic> json) => QuizScore(
        attemptId: json['attempt_id'] as String? ?? '',
        title: json['title'] as String?,
        percent: _double(json['percent']),
        correctCount: _nullableInt(json['correct_count']),
        questionCount: _nullableInt(json['question_count']),
        submittedAt: _date(json['submitted_at']),
      );
}

class HomeworkScore {
  const HomeworkScore({
    required this.title,
    required this.score,
    required this.maxScore,
    required this.percent,
    required this.released,
    required this.submittedAt,
    required this.late,
  });

  final String? title;

  /// Present only once the score is released to the learner.
  final double? score;
  final double maxScore;

  /// Released score as a share of the assignment's maximum score.
  final double? percent;
  final bool released;
  final DateTime? submittedAt;
  final bool late;

  factory HomeworkScore.fromJson(Map<String, dynamic> json) => HomeworkScore(
        title: json['title'] as String?,
        score: _double(json['score']),
        maxScore: _double(json['max_score']) ?? 100,
        percent: _double(json['percent']),
        released: json['released'] == true,
        submittedAt: _date(json['submitted_at']),
        late: json['late'] == true,
      );
}

class ReleasedAssessmentScore {
  const ReleasedAssessmentScore({
    required this.attemptId,
    required this.missionCode,
    required this.title,
    required this.assignmentTitle,
    required this.percent,
    required this.outcome,
    required this.releasedAt,
  });

  final String attemptId;
  final String? missionCode;
  final String? title;
  final String? assignmentTitle;
  final double? percent;
  final String? outcome;
  final DateTime? releasedAt;

  factory ReleasedAssessmentScore.fromJson(Map<String, dynamic> json) =>
      ReleasedAssessmentScore(
        attemptId: json['attempt_id'] as String? ?? '',
        missionCode: json['mission'] as String?,
        title: json['title'] as String?,
        assignmentTitle: json['assignment_title'] as String?,
        percent: _double(json['percent']),
        outcome: json['outcome'] as String?,
        releasedAt: _date(json['released_at']),
      );
}

class PracticeSummary {
  const PracticeSummary({
    required this.missionsVerified,
    required this.runs,
    required this.bestTimes,
  });

  final int missionsVerified;
  final int runs;
  final List<BestPracticeTime> bestTimes;

  factory PracticeSummary.fromJson(Map<String, dynamic> json) =>
      PracticeSummary(
        missionsVerified: _int(json['missions_verified']),
        runs: _int(json['runs']),
        bestTimes: _list(json['best_times'], BestPracticeTime.fromJson),
      );
}

class PerformanceSummary {
  const PerformanceSummary({
    required this.quizAvg,
    required this.homeworkAvg,
    required this.homeworkReleased,
    required this.assessmentsReleased,
    required this.assessmentsCompetent,
    required this.criteriaTotal,
    required this.criteriaAchieved,
  });

  final double? quizAvg;

  /// Mean of released homework grades as a share of each maximum score.
  final double? homeworkAvg;
  final int homeworkReleased;
  final int assessmentsReleased;
  final int assessmentsCompetent;
  final int criteriaTotal;
  final int criteriaAchieved;

  factory PerformanceSummary.fromJson(Map<String, dynamic> json) =>
      PerformanceSummary(
        quizAvg: _double(json['quiz_avg']),
        homeworkAvg: _double(json['homework_avg']),
        homeworkReleased: _int(json['homework_released']),
        assessmentsReleased: _int(json['assessments_released']),
        assessmentsCompetent: _int(json['assessments_competent']),
        criteriaTotal: _int(json['criteria_total']),
        criteriaAchieved: _int(json['criteria_achieved']),
      );
}

class BestPracticeTime {
  const BestPracticeTime({
    required this.missionCode,
    required this.title,
    required this.bestSeconds,
  });

  final String missionCode;
  final String? title;
  final int bestSeconds;

  factory BestPracticeTime.fromJson(Map<String, dynamic> json) =>
      BestPracticeTime(
        missionCode: json['mission_code'] as String? ?? '',
        title: json['title'] as String?,
        bestSeconds: _int(json['best_seconds']),
      );
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) parse) =>
    value is List
        ? List.unmodifiable(value.whereType<Map>().map(
            (item) => parse(Map<String, dynamic>.from(item)),
          ))
        : List<T>.unmodifiable(const []);

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _nullableInt(Object? value) {
  if (value is num) return value.round();
  if (value is String) return num.tryParse(value)?.round();
  return null;
}

int _int(Object? value) => _nullableInt(value) ?? 0;

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
