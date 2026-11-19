/// Learner-facing homework strings for COC/mission organisation and the
/// Evaluate -> Finalize -> Release workflow (Objective 4). Kept out of widget
/// files per AGENTS.md; mission feedback strings stay in
/// mission_content_data.dart.
class HomeworkContentData {
  HomeworkContentData._();

  // Workflow status shown to the learner. "Submitted" keeps the existing
  // MissionContentData.homeworkSubmitted wording.
  static const statusBeingEvaluated = 'Being evaluated';
  static const statusReleased = 'Released';
  static const beingEvaluatedHelp =
      'Your instructor is evaluating this submission. The score and feedback appear here after the result is released.';
  static const resultTitle = 'Your result';
  static const resultCriteriaTitle = 'Score by criterion';

  // Assignment organisation.
  static const competencyTitle = 'Competency';
  static const generalHomework = 'General homework (not linked to a COC)';
  static const objectivesTitle = 'Learning objectives';
  static const criteriaTitle = 'Evaluation criteria';
  static const requirementsTitle = 'Submission requirements';

  // Filtered list.
  static const listTitle = 'Homework by COC and mission';
  static const listAction = 'Filter by COC';
  static const listHelp =
      'Choose a COC, then a mission, to see the homework for that competency.';
  static const cocFilterLabel = 'Filter homework by COC';
  static const missionFilterLabel = 'Filter homework by mission';
  static const allCocs = 'All COCs';
  static const allMissions = 'All missions';
  static const notLinked = 'Not linked';
  static const listEmpty = 'No homework assigned';
  static const noMatch = 'No homework matches this COC and mission.';
  static const listUnavailable =
      'Homework could not be loaded. Check your connection, then try again.';
  static const retry = 'Try again';
  static const refresh = 'Refresh homework';

  static String cocLabel(String cocCode) {
    final number = RegExp(r'(\d+)').firstMatch(cocCode)?.group(1);
    return number == null ? cocCode.toUpperCase() : 'COC $number';
  }

  static String missionLabel(String missionCode, String? title) {
    final number = RegExp(r'_m(\d+)$').firstMatch(missionCode)?.group(1);
    final short = number == null ? missionCode.toUpperCase() : 'M$number';
    return title == null || title.isEmpty ? short : '$short · $title';
  }

  static String competencyLine(
      {String? cocCode,
      String? cocTitle,
      String? missionCode,
      String? missionTitle,
      String? moduleCode,
      String? moduleTitle}) {
    final parts = [
      if (cocCode != null)
        cocTitle == null || cocTitle.isEmpty
            ? cocLabel(cocCode)
            : '${cocLabel(cocCode)} · $cocTitle',
      if (missionCode != null) missionLabel(missionCode, missionTitle),
      if (moduleCode != null)
        moduleTitle == null || moduleTitle.isEmpty
            ? moduleCode
            : '$moduleCode $moduleTitle',
    ];
    return parts.isEmpty ? generalHomework : parts.join('\n');
  }

  static String maxScore(num value) => 'Maximum score: ${_number(value)}';
  static String points(num value) =>
      '${_number(value)} ${value == 1 ? 'point' : 'points'}';
  static String score(num score, num max) =>
      'Score: ${_number(score)}/${_number(max)}';
  static String criterionScore(num score, num max) =>
      '${_number(score)}/${_number(max)}';
  static String criterionSemantics(String criterion, num max) =>
      '$criterion, ${points(max)}';
  static String count(int shown, int total) =>
      shown == total ? '$total homework' : '$shown of $total homework';

  static String _number(num value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}
