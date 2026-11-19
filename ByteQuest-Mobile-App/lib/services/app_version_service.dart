import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/config/supabase_config.dart';

/// The version of this learner app build. The coordinator keeps it equal to
/// the `pubspec.yaml` version name (build number excluded).
const String kAppVersion = '1.2.0';

/// Key of the minimum supported version in `public.app_release_config`.
const String kMinimumAppVersionKey = 'min_supported_app_version';

enum AppVersionStatus { supported, updateRequired, unknown }

class AppVersionCheck {
  const AppVersionCheck({
    required this.status,
    required this.currentVersion,
    this.minimumVersion,
  });

  final AppVersionStatus status;
  final String currentVersion;
  final String? minimumVersion;
}

typedef AppVersionChecker = Future<AppVersionCheck> Function();

/// Parses `major.minor.patch` (build metadata and pre-release tags ignored).
/// Returns null for anything that is not a dotted list of numbers.
List<int>? parseAppVersion(String? value) {
  final core = (value ?? '').trim().split('+').first.split('-').first;
  if (core.isEmpty) return null;
  final parts = core.split('.');
  if (parts.length > 4) return null;
  final numbers = <int>[];
  for (final part in parts) {
    final number = int.tryParse(part);
    if (number == null || number < 0) return null;
    numbers.add(number);
  }
  return numbers;
}

/// Negative when [a] is older than [b], zero when equal, positive when newer.
/// Missing segments count as zero (1.2 == 1.2.0).
int compareAppVersions(List<int> a, List<int> b) {
  final length = a.length > b.length ? a.length : b.length;
  for (var index = 0; index < length; index++) {
    final left = index < a.length ? a[index] : 0;
    final right = index < b.length ? b[index] : 0;
    if (left != right) return left - right;
  }
  return 0;
}

/// Only a valid minimum that is newer than the running app blocks it. A
/// missing or malformed minimum never blocks learners (fail open).
AppVersionCheck evaluateAppVersion({
  required String current,
  required String? minimum,
}) {
  final currentParts = parseAppVersion(current);
  final minimumParts = parseAppVersion(minimum);
  if (currentParts == null || minimumParts == null) {
    if (minimum != null && minimumParts == null) {
      debugPrint('Ignoring malformed $kMinimumAppVersionKey value: $minimum');
    }
    return AppVersionCheck(
      status: AppVersionStatus.supported,
      currentVersion: current,
      minimumVersion: minimum,
    );
  }
  return AppVersionCheck(
    status: compareAppVersions(currentParts, minimumParts) < 0
        ? AppVersionStatus.updateRequired
        : AppVersionStatus.supported,
    currentVersion: current,
    minimumVersion: minimum,
  );
}

/// Reads the server's minimum supported learner app version. The value is
/// public release configuration, readable before sign-in.
class AppVersionService {
  AppVersionService({this.timeout = const Duration(seconds: 8)});

  final Duration timeout;

  Future<AppVersionCheck> check() async {
    try {
      final row = await SupabaseConfig.client
          .from('app_release_config')
          .select('value')
          .eq('key', kMinimumAppVersionKey)
          .maybeSingle()
          .timeout(timeout);
      return evaluateAppVersion(
        current: kAppVersion,
        minimum: row?['value'] as String?,
      );
    } catch (error) {
      debugPrint('Minimum app version check failed: $error');
      return const AppVersionCheck(
        status: AppVersionStatus.unknown,
        currentVersion: kAppVersion,
      );
    }
  }
}
