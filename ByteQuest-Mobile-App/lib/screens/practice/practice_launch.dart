import 'package:flutter/material.dart';

import '../../data/learning_content_data.dart';
import '../../data/missions_data.dart';
import '../../models/mission_model.dart';
import '../../services/authoritative_assessment_service.dart';
import '../../services/practice_progress_service.dart';
import '../simulation/mission_launcher.dart';

typedef MissionAccessCheck = Future<void> Function(String missionCode);
typedef MissionRouteLauncher = Future<void> Function(
    BuildContext context, Mission mission);

/// Opens a practice mission only after the server confirms the module is
/// unlocked (`practice_mission_unlocked`, the same rule as the evidence gate),
/// then hands over to the shared [MissionLauncher]. Returns true when the
/// mission was launched (and has now been closed).
abstract final class PracticeMissionLauncher {
  static Future<bool> open(
    BuildContext context,
    String missionCode, {
    MissionAccessCheck? accessCheck,
    MissionRouteLauncher? launch,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    void tell(String message) =>
        messenger?.showSnackBar(SnackBar(content: Text(message)));
    final mission = MissionsData.getMissionById(missionCode);
    if (mission == null) {
      tell(LearningContentData.missionUnavailable);
      return false;
    }
    try {
      await (accessCheck ??
          PracticeProgressService().requireMissionAccess)(missionCode);
    } on StateError catch (error) {
      tell(error.message == 'PRACTICE_COC_LOCKED'
          ? LearningContentData.missionAccessDenied
          : LearningContentData.missionAccessFailed);
      return false;
    } catch (_) {
      tell(LearningContentData.missionAccessFailed);
      return false;
    }
    if (!context.mounted) return false;
    if (launch == null) {
      // Practice never continues a local assessment session.
      AuthoritativeAssessmentService.instance.abandonLocalSession();
    }
    await (launch ?? MissionLauncher.launch)(context, mission);
    return true;
  }
}
