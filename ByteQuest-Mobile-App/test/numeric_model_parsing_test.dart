import 'package:bytequest/models/learner_progress_model.dart';
import 'package:bytequest/models/task_result_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('learner progress accepts PostgreSQL numeric values', () {
    final progress = LearnerProgress.fromJson({
      'id': 'progress-1',
      'user_id': 'learner-1',
      'coc_id': 'coc-1',
      'mission_id': 'mission-1',
      'completion_percentage': 42.625,
      'best_score': 87.5,
      'latest_score': 74.25,
      'created_at': '2026-09-14T01:00:00.000Z',
      'updated_at': '2026-09-14T02:00:00.000Z',
    });

    expect(progress.completionPercentage, 42.625);
    expect(progress.bestScore, 87.5);
    expect(progress.latestScore, 74.25);
  });

  test('task results accept PostgreSQL numeric values', () {
    final result = TaskResultDb.fromJson({
      'id': 'task-result-1',
      'mission_result_id': 'mission-result-1',
      'user_id': 'learner-1',
      'mission_id': 'mission-1',
      'score_obtained': 7.5,
      'max_score': 10.0,
      'created_at': '2026-09-14T01:00:00.000Z',
    });

    expect(result.scoreObtained, 7.5);
    expect(result.maxScore, 10.0);
  });
}
