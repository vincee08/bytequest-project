/// Identity of this learner app build. Keep both values equal to the
/// `pubspec.yaml` `version:` (version name + build number); a test checks it.
const String kAppVersion = '1.2.0';
const String kAppBuildNumber = '3';

/// Request header that names this app version on every Supabase request and
/// every dashboard API request. The server refuses to start a simulation
/// assessment or an essay quiz for a client below the configured minimum
/// version (SQLSTATE P0001, message prefix [kAppUpdateRequiredCode]).
const String kAppVersionHeader = 'x-bytequest-app-version';
const Map<String, String> kAppVersionHeaders = {kAppVersionHeader: kAppVersion};

/// Message prefix of the server refusal for an unsupported app version.
const String kAppUpdateRequiredCode = 'APP_UPDATE_REQUIRED';
