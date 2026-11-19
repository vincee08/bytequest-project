import 'package:flutter/foundation.dart' show protected;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/config/supabase_config.dart';
import '../models/learner_quiz_model.dart';
import 'app_version_service.dart';

/// The server refused a quiz write because the attempt is no longer open:
/// its time limit or the class deadline passed (and the saved answers were
/// submitted automatically), or it was already submitted.
class LearnerQuizClosedException implements Exception {
  const LearnerQuizClosedException(this.code);
  final String code;

  @override
  String toString() => 'LearnerQuizClosedException($code)';
}

/// The quiz was submitted on the server, but its result could not be read.
class LearnerQuizSubmittedException implements Exception {
  const LearnerQuizSubmittedException(this.cause);
  final Object cause;

  @override
  String toString() => 'LearnerQuizSubmittedException($cause)';
}

/// The server refused to start the quiz because this app version cannot
/// answer it (scenario essays need 1.2.0 or later): the learner must update.
class LearnerQuizUpdateRequiredException implements Exception {
  const LearnerQuizUpdateRequiredException();

  @override
  String toString() => 'LearnerQuizUpdateRequiredException';
}

class LearnerQuizService {
  LearnerQuizService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  late final SupabaseClient _client = SupabaseConfig.client;

  static const _closedCodes = {
    'QUIZ_NOT_AVAILABLE',
    'QUIZ_ATTEMPT_EXPIRED',
    'QUIZ_ATTEMPT_ALREADY_SUBMITTED',
    'QUIZ_ATTEMPT_ALREADY_USED',
  };

  Never _rethrow(Object error) {
    if (error is PostgrestException) {
      final text = '${error.message} ${error.details ?? ''}';
      for (final code in _closedCodes) {
        if (text.contains(code)) throw LearnerQuizClosedException(code);
      }
    }
    throw error;
  }

  Future<List<LearnerQuizSummary>> getAvailableQuizzes() async {
    final response = await _client.rpc('get_available_learner_quizzes');
    if (response is Map && response['error'] != null) {
      throw StateError(response['error'].toString());
    }
    return (response as List? ?? const [])
        .map((item) => LearnerQuizSummary.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<LearnerQuizAttempt> startOrResume(String assignmentId) async {
    try {
      final response = await _client.rpc(
        'start_learner_quiz',
        params: {
          'p_assignment_id': assignmentId,
          'p_client_start_key': _uuid.v4(),
        },
      );
      return LearnerQuizAttempt.fromJson(Map<String, dynamic>.from(response));
    } catch (error) {
      if (isAppUpdateRequiredError(error)) {
        throw const LearnerQuizUpdateRequiredException();
      }
      _rethrow(error);
    }
  }

  /// The availability projection intentionally returns one row per quiz.
  /// A notification may reference another eligible class assignment of it.
  Future<LearnerQuizSummary?> getNotificationQuiz(
      String assignmentId, String classId) async {
    final rows = await getAvailableQuizzes();
    final exact = rows
        .where((q) => q.assignmentId == assignmentId && q.classId == classId);
    if (exact.isNotEmpty) return exact.first;
    // References are emitted by the same authoritative RPC after checking
    // current class membership, class status and publication/attempt history.
    final canonical =
        rows.where((q) => q.eligibleAssignments[assignmentId] == classId);
    return canonical.isEmpty ? null : canonical.first;
  }

  Future<void> saveAnswer({
    required String attemptId,
    required String itemId,
    required String answer,
  }) async {
    try {
      await _client.rpc(
        'save_learner_quiz_answer',
        params: {
          'p_attempt_id': attemptId,
          'p_item_id': itemId,
          'p_answer': answer,
        },
      );
    } catch (error) {
      _rethrow(error);
    }
  }

  /// Records the learner's submission (idempotent: a completed attempt
  /// returns its payload). Separate from [submit] so the two steps can fail
  /// apart.
  @protected
  Future<void> sendSubmission(String attemptId) async {
    try {
      await _client.rpc(
        'submit_learner_quiz',
        params: {
          'p_attempt_id': attemptId,
          'p_submission_key': _uuid.v4(),
        },
      );
    } catch (error) {
      _rethrow(error);
    }
  }

  /// Submits, then reads the result. A failed result read after a
  /// successful submission throws [LearnerQuizSubmittedException], so the
  /// learner is never told the quiz was not submitted when it was.
  Future<LearnerQuizResult> submit(String attemptId) async {
    await sendSubmission(attemptId);
    try {
      return await getResult(attemptId);
    } catch (error) {
      throw LearnerQuizSubmittedException(error);
    }
  }

  /// Reading a result also lets the server finalise an attempt whose time
  /// ran out, so this is how the app learns about an automatic submission.
  Future<LearnerQuizResult> getResult(String attemptId) async {
    final response = await _client.rpc(
      'get_learner_quiz_result',
      params: {'p_attempt_id': attemptId},
    );
    return LearnerQuizResult.fromJson(Map<String, dynamic>.from(response));
  }
}

/// Keeps unsaved essay text on the device so a closed app or a lost
/// connection never loses a learner's writing. The server copy stays
/// authoritative; a device draft is only used while it differs from it.
abstract class QuizEssayDraftStore {
  Future<String?> read(String attemptId, String itemId);
  Future<void> write(String attemptId, String itemId, String text);
  Future<void> clear(String attemptId, String itemId);
}

class SharedPreferencesQuizEssayDraftStore implements QuizEssayDraftStore {
  const SharedPreferencesQuizEssayDraftStore();

  static String _key(String attemptId, String itemId) =>
      'bytequest.quiz_essay_draft.$attemptId.$itemId';

  @override
  Future<String?> read(String attemptId, String itemId) async =>
      (await SharedPreferences.getInstance())
          .getString(_key(attemptId, itemId));

  @override
  Future<void> write(String attemptId, String itemId, String text) async {
    await (await SharedPreferences.getInstance())
        .setString(_key(attemptId, itemId), text);
  }

  @override
  Future<void> clear(String attemptId, String itemId) async {
    await (await SharedPreferences.getInstance())
        .remove(_key(attemptId, itemId));
  }
}
