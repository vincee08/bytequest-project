final class PracticeCocProgress {
  const PracticeCocProgress(
      {required this.coc,
      required this.unlocked,
      required this.completed,
      required this.completedMissions});
  final String coc;
  final bool unlocked;
  final bool completed;
  final Set<String> completedMissions;
  bool get quizAvailable => unlocked && completedMissions.length == 5;
  factory PracticeCocProgress.fromJson(Map<String, dynamic> json) =>
      PracticeCocProgress(
          coc: json['coc_code'] as String,
          unlocked: json['unlocked'] == true,
          completed: json['completed'] == true,
          completedMissions: Set.unmodifiable(
              (json['completed_missions'] as List? ?? []).whereType<String>()));
}

final class PracticeQuiz {
  PracticeQuiz(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'] as String;
  String get status => json['status'] as String;
  bool get submitted => status == 'submitted';
  bool get passed => json['passed'] == true;
  int get score => (json['score'] as num?)?.toInt() ?? 0;
  List<Map<String, dynamic>> get questions => (json['questions'] as List)
      .map((q) => Map<String, dynamic>.from(q as Map))
      .toList();
  Map<String, int> get answers => (json['answers'] as Map? ?? {})
      .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
}
