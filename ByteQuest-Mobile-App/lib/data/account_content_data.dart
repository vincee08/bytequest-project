/// Account, student ID and app version strings (slice A5).
/// Widget files read their text from here, never inline.
class AccountContentData {
  AccountContentData._();

  // Staff-managed student ID.
  static const studentIdLabel = 'Student ID';
  static const studentIdManagedHelper = 'Managed by your instructor';
  static const studentIdManagedHint =
      'Your instructor or an administrator set this ID. Ask them if it needs to change.';
  static String studentIdManagedSemantics(String value) => value.isEmpty
      ? 'Student ID, managed by your instructor, not set'
      : 'Student ID $value, managed by your instructor, read only';
  static const studentIdManagedSaveError =
      'Your student ID is managed by your instructor and was not changed. Your other details can still be saved.';
  static const studentIdTakenSaveError =
      'This student ID is already registered to another learner. Check the ID or ask your instructor.';

  // Installed app version (Settings, About).
  static String appVersionLabel(String version, String build) =>
      'Version $version (build $build)';

  // Minimum supported app version.
  static const updateRequiredTitle = 'Update ByteQuest';
  static String updateRequiredBody(String current, String minimum) =>
      'This version of ByteQuest ($current) is no longer supported. Install version $minimum or later so your progress, module locks and assessments keep working.';
  static const updateRequiredHint =
      'Ask your instructor for the latest ByteQuest app, install it, then open ByteQuest again.';
  static const updateCheckAgain = 'Check again';
  static const updateCheckAgainSemantics =
      'Check again whether this version of ByteQuest is supported';
  static const updateChecking = 'Checking the supported version…';
  static const versionCheckFailedTitle = 'Could not confirm the app version';
  static const versionCheckFailedBody =
      'ByteQuest could not reach the server to check the minimum supported version. Check your connection and try again, or continue for now.';
  static const versionCheckRetry = 'Try again';
  static const versionCheckRetrySemantics =
      'Try the app version check again';
  static const versionCheckContinue = 'Continue';
  static const versionCheckContinueSemantics =
      'Continue without confirming the app version';
}
