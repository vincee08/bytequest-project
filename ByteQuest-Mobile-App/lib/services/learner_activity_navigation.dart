import 'package:flutter/material.dart';
import '../data/mission_content_data.dart';
import '../models/learner_notification.dart';
import '../models/homework_model.dart';
import '../models/learner_quiz_model.dart';
import '../screens/homework/homework_details_screen.dart';
import '../screens/missions/class_details_screen.dart';
import '../screens/quizzes/quiz_details_screen.dart';
import '../screens/quizzes/quiz_result_screen.dart';
import 'authoritative_assessment_service.dart';
import 'homework_service.dart';
import 'learner_quiz_service.dart';

/// Notifications are pointers, never access grants. Resolve again on every tap.
class LearnerActivityNavigation {
  static Future<Widget> resolve(
    LearnerNotification item, {
    LearnerQuizService? quizzes,
    HomeworkService? homework,
    AuthoritativeAssessmentService? assessment,
  }) async {
    if (item.activityType == 'quiz') {
      final q = item.activityId == null || item.classId == null
          ? null
          : await (quizzes ?? LearnerQuizService())
              .getNotificationQuiz(item.activityId!, item.classId!);
      if (q != null) {
        return q.state == LearnerQuizState.completed && q.attemptId != null
            ? QuizResultScreen(attemptId: q.attemptId!)
            : QuizDetailsScreen(quiz: q);
      }
    } else if (item.activityType == 'homework') {
      final List<HomeworkAssignment> rows;
      try {
        rows = await (homework ?? HomeworkService())
            .getAssignments(id: item.activityId, classId: item.classId);
      } on StateError catch (error) {
        if (error.message == 'HOMEWORK_ACCESS_DENIED') {
          throw StateError(MissionContentData.activityNoAccess);
        }
        rethrow;
      }
      if (rows.isNotEmpty &&
          rows.first.id == item.activityId &&
          rows.first.classId == item.classId) {
        return HomeworkDetailsScreen(assignment: rows.first);
      }
    } else if (item.activityType == 'technical') {
      final service = assessment ?? AuthoritativeAssessmentService.instance;
      final rows = await service.getAssignedActivities();
      final matches = rows
          .where((a) => a.id == item.activityId && a.classId == item.classId);
      if (matches.isNotEmpty) {
        final a = matches.first;
        // Open the specific authorized task's existing class review/launch flow.
        // No attempt is created until the learner explicitly opens the activity.
        return ClassDetailsScreen(
            classId: a.classId,
            classTitle: a.classTitle,
            focusedAssignmentId: a.id,
            assignments: [a],
            resources: const []);
      }
    }
    throw StateError(MissionContentData.activityNoAccess);
  }
}
