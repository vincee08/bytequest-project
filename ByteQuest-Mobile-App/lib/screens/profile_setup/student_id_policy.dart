import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';

/// Whether the signed-in learner's student ID was confirmed by staff (roster
/// import or administrator). A managed ID is shown read-only and never resent.
class StudentIdPolicy {
  const StudentIdPolicy({required this.learnerId, required this.managed});

  final String? learnerId;
  final bool managed;
}

typedef StudentIdPolicyLoader = Future<StudentIdPolicy?> Function();

/// Reads the policy for the signed-in learner. Returns null when signed out
/// or when the backend does not know managed IDs yet (older deployments);
/// the database trigger still protects managed IDs either way.
Future<StudentIdPolicy?> loadSignedInStudentIdPolicy() async {
  try {
    final userId = SupabaseConfig.currentUserId;
    if (userId == null) return null;
    final row = await SupabaseConfig.client
        .from('profiles')
        .select('learner_id, learner_id_managed')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return StudentIdPolicy(
      learnerId: row['learner_id'] as String?,
      managed: row['learner_id_managed'] == true,
    );
  } catch (error) {
    debugPrint('Student ID policy could not be loaded: $error');
    return null;
  }
}

/// The database refused a learner's change to a staff-managed student ID.
bool isStudentIdManagedError(Object error) =>
    error.toString().contains('STUDENT_ID_STAFF_MANAGED');

/// Another learner already uses this student ID (unique index).
bool isStudentIdTakenError(Object error) =>
    (error is PostgrestException && error.code == '23505') ||
    error.toString().contains('STUDENT_ID_IN_USE');
