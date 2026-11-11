# Practice mission regression — 2026-11-11

## Verified root cause and scope

The earlier COC1 M1 failure had two separate causes: the emulator saved evidence in local Supabase while its practice verification request used a hosted API, and the local v2 COC1 M1 contract required placement evidence from a phase that the identification UI now completes by tapping. The previous session aligned the emulator with the local API and published the versioned v3 identification contract locally. This session did not reapply that migration or change learner evidence.

The same contract defect was **not** found in the other missions. A UTF-8 JSONB comparison found exact Flutter/database parity for COC1 M2–M5, COC2 M1–M5, COC3 M1–M5, and COC4 M1–M5. COC1 M1 differs in one presentation option label (`—` in Flutter, `???` in the local database); its verifier constraints and action requirements match. No migration is warranted for this non-evaluation label difference during this task.

One regression tool was stale: `scripts/test-practice-progression.mjs` still expected COC1 M1 placement evidence and selected existing learners in the populated database. It now creates disposable synthetic users within a rollback-only transaction, checks the required identification role action, and refuses to run unless pointed at the isolated QA database container. A new local API runner verifies the route and persistence workflow for all 20 missions.

## Verification key

- **T**: Flutter widget suite exercises every work phase through touch controls, phase navigation, evidence review, and responsive screens. Focused tests cover inspection counts, wrong actions, placement, duplicate prevention, zoom/pan drops, restoration, timer expiry, and API retry behavior.
- **A**: Local Supabase Auth/REST + production-built Next.js practice route with synthetic learners: incomplete rejection, invalid action recorded without awarding completion, valid evidence write, successful verification, and idempotent retry for every mission. Four quizzes and the final Learn Page projection also passed. **138 API checks passed.**
- **P**: Isolated PostgreSQL rollback replay of all 20 missions, four sequential COCs, quiz state, RLS, and tampering. The practice progression, COC1 M1 identification, and foundation/instructor release rollback tests passed.

`PASS` means these automated local QA workflows passed. It does not claim physical device or owner manual acceptance.

| ID | Actual mission name | Issue / fix in this session | Tests | Result |
|---|---|---|---|---|
| COC1 M1 | Identify Computer Parts and Tools | Previous local API/v3 fix verified; stale placement test corrected | T, A, P | PASS |
| COC1 M2 | Install Internal Components | No new defect reproduced | T, A, P | PASS |
| COC1 M3 | Install and Configure a Workstation OS | No new defect reproduced | T, A, P | PASS |
| COC1 M4 | Connect and Configure Peripheral Devices | No new defect reproduced | T, A, P | PASS |
| COC1 M5 | Install Drivers and Test the System | No new defect reproduced | T, A, P | PASS |
| COC2 M1 | Identify Network Devices and Tools | No new defect reproduced | T, A, P | PASS |
| COC2 M2 | Create Network Cables | No new defect reproduced | T, A, P | PASS |
| COC2 M3 | Construct and Verify a Network Topology | No new defect reproduced | T, A, P | PASS |
| COC2 M4 | Configure Network Devices | No new defect reproduced | T, A, P | PASS |
| COC2 M5 | Troubleshoot Network Connectivity | No new defect reproduced | T, A, P | PASS |
| COC3 M1 | Prepare Server Setup Requirements | No new defect reproduced | T, A, P | PASS |
| COC3 M2 | Install and Configure Server OS | No new defect reproduced | T, A, P | PASS |
| COC3 M3 | Manage Users, Groups, and Permissions | No new defect reproduced | T, A, P | PASS |
| COC3 M4 | Configure and Test Server Services | No new defect reproduced | T, A, P | PASS |
| COC3 M5 | Test Client Access and Document Setup | No new defect reproduced | T, A, P | PASS |
| COC4 M1 | Identify System and Network Problems | No new defect reproduced | T, A, P | PASS |
| COC4 M2 | Diagnose and Repair Hardware Faults | No new defect reproduced | T, A, P | PASS |
| COC4 M3 | Diagnose Hardware and Software Faults | No new defect reproduced | T, A, P | PASS |
| COC4 M4 | Replace and Reconfigure a Component | No new defect reproduced | T, A, P | PASS |
| COC4 M5 | Apply Repair Action and Create Report | No new defect reproduced | T, A, P | PASS |

## Boundaries

The local API test uses synthetic QA users and evidence, never the owner's manual session. PostgreSQL replay and lifecycle tests roll back their synthetic records. The API integration creates synthetic users and completions only in the isolated QA database. The populated `supabase_db_ByteQuest` was queried read-only for contract parity. No hosted Supabase database, assessment scoring, instructor release code, or production credential file changed. The foundation lifecycle test confirms instructor finalization and release still work in isolated PostgreSQL.

The original Flutter app was built with explicit loopback `BQ_SUPABASE_URL` and `BQ_PRACTICE_API_URL` local QA defines for `emulator-5556`. That AVD keeps airplane mode enabled. Android's existing debug network policy already allows loopback HTTP, and `adb reverse` connects device ports 29453 and 3001 to the isolated Supabase stack and local Next.js API. Device-to-service TCP probes passed with airplane mode still enabled. If the emulator restarts, restore the two mappings with `adb -s emulator-5556 reverse tcp:29453 tcp:29453` and `adb -s emulator-5556 reverse tcp:3001 tcp:3001` before opening the app.

The owner should use a fresh QA learner account on that emulator, inspect the Learn Page, and manually exercise the desired mission phases. Synthetic QA completions belong to separate users and will not complete the owner's missions.
