import 'package:bytequest/data/missions_data.dart';
import 'package:flutter_test/flutter_test.dart';

// QA audit 2026-11-20: the class space launched an assigned simulation
// assessment by the database mission UUID, which is never an installed
// mission id, so "Open activity" always failed with "no installed mobile
// simulation mapping". Every launcher now shares one resolver.
void main() {
  const coc1M2Uuid = '6baceb01-d886-4716-8cd9-59922531231c';

  test('an assignment resolves through its mission code, not the database UUID',
      () {
    final mission = MissionsData.resolveAssigned(
        learnerPayload: const {}, missionCode: 'coc1_m2');
    expect(mission?.id, 'coc1_m2');
    expect(MissionsData.getMissionById(coc1M2Uuid), isNull,
        reason: 'the database UUID never names an installed mission');
  });

  test('the published payload code wins and ignores case and punctuation', () {
    final mission = MissionsData.resolveAssigned(
        learnerPayload: const {'local_mission_code': 'COC1-M3'},
        missionCode: 'coc1_m2');
    expect(mission?.id, 'coc1_m3');
  });

  test('an unknown or empty code resolves to nothing', () {
    expect(
        MissionsData.resolveAssigned(
            learnerPayload: const {}, missionCode: coc1M2Uuid),
        isNull);
    expect(
        MissionsData.resolveAssigned(learnerPayload: const {}, missionCode: ''),
        isNull);
  });

  test('every installed mission resolves from its own code', () {
    for (final mission in MissionsData.getAllMissions()) {
      expect(
          MissionsData.resolveAssigned(
                  learnerPayload: const {}, missionCode: mission.missionCode)
              ?.id,
          mission.id,
          reason: mission.missionCode);
    }
  });
}
