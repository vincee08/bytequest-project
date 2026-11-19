/// Learner curriculum projection returned by the server function
/// `get_learner_curriculum()`. Every lock, completion and count is computed by
/// the server; the app only renders it.
int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
bool _bool(Object? value) => value == true;
String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

List<Map<String, dynamic>> _maps(Object? value) => [
      for (final item in value is List ? value : const [])
        if (item is Map) Map<String, dynamic>.from(item)
    ];

class CurriculumProgress {
  const CurriculumProgress(
      {required this.done, required this.total, required this.percent});

  final int done;
  final int total;
  final int percent;

  double get ratio => total == 0
      ? (percent >= 100 ? 1 : 0)
      : (done / total).clamp(0, 1).toDouble();

  factory CurriculumProgress.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return CurriculumProgress(
        done: _int(map['done']),
        total: _int(map['total']),
        percent: _int(map['percent']).clamp(0, 100).toInt());
  }
}

class CurriculumTopic {
  const CurriculumTopic({
    required this.id,
    required this.revisionId,
    required this.title,
    required this.summary,
    required this.sequenceOrder,
    required this.completed,
  });

  final String id;
  final String revisionId;
  final String title;
  final String? summary;
  final int sequenceOrder;
  final bool completed;

  factory CurriculumTopic.fromJson(Map<String, dynamic> json) =>
      CurriculumTopic(
        id: json['id'] as String,
        revisionId: json['revision_id'] as String,
        title: _text(json['title']) ?? 'Lesson',
        summary: _text(json['summary']),
        sequenceOrder: _int(json['sequence_order']),
        completed: _bool(json['completed']),
      );
}

class CurriculumOutcome {
  const CurriculumOutcome(
      {required this.id, required this.code, required this.statement});

  final String id;
  final String code;
  final String statement;

  factory CurriculumOutcome.fromJson(Map<String, dynamic> json) =>
      CurriculumOutcome(
        id: json['id']?.toString() ?? '',
        code: _text(json['code']) ?? '',
        statement: _text(json['statement']) ?? '',
      );
}

class CurriculumMission {
  const CurriculumMission({
    required this.missionCode,
    required this.missionNumber,
    required this.title,
    required this.unlocked,
    required this.verified,
    required this.runs,
    required this.bestSeconds,
  });

  final String missionCode;
  final int missionNumber;
  final String title;
  final bool unlocked;
  final bool verified;
  final int runs;
  final int? bestSeconds;

  factory CurriculumMission.fromJson(Map<String, dynamic> json) =>
      CurriculumMission(
        missionCode: json['mission_code'] as String,
        missionNumber: _int(json['mission_number']),
        title: _text(json['title']) ?? json['mission_code'] as String,
        unlocked: _bool(json['unlocked']),
        verified: _bool(json['verified']),
        runs: _int(json['runs']),
        bestSeconds:
            json['best_seconds'] == null ? null : _int(json['best_seconds']),
      );
}

class CurriculumModule {
  const CurriculumModule({
    required this.id,
    required this.code,
    required this.title,
    required this.sequenceOrder,
    required this.sourceReference,
    required this.unlocked,
    required this.completed,
    required this.lockReason,
    required this.noRequiredItems,
    required this.newContent,
    required this.progress,
    required this.topics,
    required this.outcomes,
    required this.missions,
  });

  final String id;
  final String code;
  final String title;
  final int sequenceOrder;
  final String? sourceReference;
  final bool unlocked;
  final bool completed;
  final String? lockReason;
  final bool noRequiredItems;
  final bool newContent;
  final CurriculumProgress progress;
  final List<CurriculumTopic> topics;
  final List<CurriculumOutcome> outcomes;
  final List<CurriculumMission> missions;

  int get topicsCompleted => topics.where((topic) => topic.completed).length;
  int get missionsVerified =>
      missions.where((mission) => mission.verified).length;
  int get totalRuns => missions.fold(0, (sum, mission) => sum + mission.runs);

  factory CurriculumModule.fromJson(Map<String, dynamic> json) =>
      CurriculumModule(
        id: json['id'] as String,
        code: _text(json['code']) ?? '',
        title: _text(json['title']) ?? '',
        sequenceOrder: _int(json['sequence_order']),
        sourceReference: _text(json['source_reference']),
        unlocked: _bool(json['unlocked']),
        completed: _bool(json['completed']),
        lockReason: _text(json['lock_reason']),
        noRequiredItems: _bool(json['no_required_items']),
        newContent: _bool(json['new_content']),
        progress: CurriculumProgress.fromJson(json['progress']),
        topics: _maps(json['topics'])
            .map(CurriculumTopic.fromJson)
            .toList(growable: false),
        outcomes: _maps(json['outcomes'])
            .map(CurriculumOutcome.fromJson)
            .toList(growable: false),
        missions: _maps(json['missions'])
            .map(CurriculumMission.fromJson)
            .toList(growable: false),
      );
}

class CurriculumQuizState {
  const CurriculumQuizState({required this.eligible, required this.passed});

  final bool eligible;
  final bool passed;

  factory CurriculumQuizState.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return CurriculumQuizState(
        eligible: _bool(map['eligible']), passed: _bool(map['passed']));
  }
}

class CurriculumCoc {
  const CurriculumCoc({
    required this.cocCode,
    required this.title,
    required this.order,
    required this.unlocked,
    required this.completed,
    required this.lockReason,
    required this.progress,
    required this.quiz,
    required this.modules,
  });

  final String cocCode;
  final String title;
  final int order;
  final bool unlocked;
  final bool completed;
  final String? lockReason;
  final CurriculumProgress progress;
  final CurriculumQuizState quiz;
  final List<CurriculumModule> modules;

  int get number => order > 0
      ? order
      : int.tryParse(cocCode.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  int get modulesCompleted =>
      modules.where((module) => module.completed).length;
  List<CurriculumMission> get missions =>
      [for (final module in modules) ...module.missions];

  factory CurriculumCoc.fromJson(Map<String, dynamic> json) => CurriculumCoc(
        cocCode: (json['coc_code'] as String).toLowerCase(),
        title: _text(json['title']) ?? '',
        order: _int(json['order']),
        unlocked: _bool(json['unlocked']),
        completed: _bool(json['completed']),
        lockReason: _text(json['lock_reason']),
        progress: CurriculumProgress.fromJson(json['progress']),
        quiz: CurriculumQuizState.fromJson(json['quiz']),
        modules: _maps(json['modules'])
            .map(CurriculumModule.fromJson)
            .toList(growable: false),
      );
}

class CurriculumProjection {
  const CurriculumProjection({required this.cocs});

  final List<CurriculumCoc> cocs;

  List<CurriculumModule> get modules =>
      [for (final coc in cocs) ...coc.modules];
  int get modulesCompleted =>
      modules.where((module) => module.completed).length;
  int get topicsTotal =>
      modules.fold(0, (sum, module) => sum + module.topics.length);
  int get topicsCompleted =>
      modules.fold(0, (sum, module) => sum + module.topicsCompleted);
  int get missionsTotal =>
      modules.fold(0, (sum, module) => sum + module.missions.length);
  int get missionsVerified =>
      modules.fold(0, (sum, module) => sum + module.missionsVerified);
  int get totalRuns => modules.fold(0, (sum, module) => sum + module.totalRuns);

  CurriculumCoc? coc(String code) {
    for (final coc in cocs) {
      if (coc.cocCode == code) return coc;
    }
    return null;
  }

  /// The module (and its COC) that contains a practice mission.
  ({CurriculumCoc coc, CurriculumModule module})? locateMission(
      String missionCode) {
    for (final coc in cocs) {
      for (final module in coc.modules) {
        if (module.missions
            .any((mission) => mission.missionCode == missionCode)) {
          return (coc: coc, module: module);
        }
      }
    }
    return null;
  }

  /// First COC the learner can work in that is not yet complete.
  CurriculumCoc? get currentCoc {
    for (final coc in cocs) {
      if (coc.unlocked && !coc.completed) return coc;
    }
    return cocs.isEmpty ? null : cocs.first;
  }

  factory CurriculumProjection.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    final cocs = _maps(map['cocs']).map(CurriculumCoc.fromJson).toList()
      ..sort((left, right) => left.number.compareTo(right.number));
    return CurriculumProjection(cocs: List.unmodifiable(cocs));
  }
}

/// A published lesson revision opened in the reader.
class CurriculumLesson {
  const CurriculumLesson(
      {required this.revisionId,
      required this.title,
      required this.summary,
      required this.bodyMarkdown});

  final String revisionId;
  final String title;
  final String? summary;
  final String bodyMarkdown;

  factory CurriculumLesson.fromJson(Map<String, dynamic> json) =>
      CurriculumLesson(
        revisionId: json['id'] as String,
        title: _text(json['title']) ?? 'Lesson',
        summary: _text(json['summary']),
        bodyMarkdown: json['body_markdown']?.toString() ?? '',
      );
}
