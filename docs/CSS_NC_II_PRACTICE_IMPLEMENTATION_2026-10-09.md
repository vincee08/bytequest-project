# CSS NC II virtual practice implementation — 2026-10-09

## Source and instructional interpretation

Reviewed all seven pages of the supplied `Computer-Systems-Servicing-NC-II_copy.pdf`.
It is the TESDA **Self-Assessment Guide**, document ELCCSS 213-0119, revision 00,
03/01/17. It is not the complete Training Regulations or an approved examination
rubric. The source SHA-256 is
`3a2401a7a28c427128a0be35587b10c22bcd736aa349ee68e8feba46ea688bbf`.

The starred activities identify critical aspects of competency. The simulation
therefore preserves work preparation, actual equipment decisions, earned
observations, corrective actions, fresh testing, and documented handover. Quiz
answers alone cannot complete practical work. The 80% supplementary quiz threshold
and sequential learning path are ByteQuest learning policies; the PDF does not
specify those rules. Official assessment and instructor-controlled result release
continue through the existing authoritative assessment pipeline.

## Competency-to-practice mapping

The existing 20 typed missions and shared simulation engine are retained. This
table identifies their virtual coverage, including the additions in this session.

| Source | Competencies practiced | Existing missions and additions |
|---|---|---|
| COC1, pages 1–2 | Preparation, component installation, interfaces, BIOS, boot media, OS/drivers, licensed applications/portable utilities, updates, function/reliability checks, environmental close-out/report | M1 inspection/tool classification and safety; M2 hardware placement, alignment, assembly sequence and connections; M3 firmware/installation/drivers/restart plus verified boot media, licensed software and updates; M4 peripherals/configuration/function checks; M5 fault correction and monitored load test. Final work orders include 5S/3Rs and reporting. |
| COC2, pages 3–4 | Cable routes/materials/tools/PPE, 568A/B principles, termination/testing, raceways, NIC/addressing/resources, network diagnosis, router/Wi-Fi/repeater/LAN/WAN/firewall and final checks | M1 specifies a protected indoor route and PVC raceway, then cable preparation and continuity; M2 practises the work-order T568B conductor map and topology links; M3 adds device deployment to the existing switched-star connections and fault correction; M4 adds secured Wi-Fi, bridged repeater, DHCP WAN and inbound filtering to device addressing; M5 diagnoses/configures/retests terminal connectivity. The fixed T568B exercise is retained; selecting arbitrary T568A work orders is not added in this change. |
| COC3, page 5 | Server preparation, NOS settings, accounts/folders/access policy, modules/add-ons/updates, network services, file/printer sharing, pre-deployment security/tests/reporting | M1 adds server/client/switch deployment and compatible Ethernet links to preparation checks; M2 server configuration/install/restart; M3 user/group/permissions plus user-folder isolation; M4 service controls/listener/client tests plus approved modules/updates and printer sharing; M5 permission-fault diagnosis and recovery. Final tests require safety and handover documentation. |
| COC4, pages 6–7 | Service-order planning, checked tools/OHS, inspection, scheduled maintenance, contingency, measured diagnosis, safe replacement/configuration, final function/safety checks, 5S/4Rs/report | M1 intake/triage; M2 measured hardware diagnosis and supported repair; M3 staged software/network diagnostics; M4 isolated adapter replacement and configuration; M5 prioritized maintenance, correction, tests and report. Backup/contingency preparation is required in the first phase and cannot substitute for inspection/diagnostics. All COC4 interactions use taps, sequencing buttons, tools, settings and diagnostic actions without draggable controls. |

These are constrained virtual work orders. They do not perform real OS installation,
physical cable splicing/conduit fitting, thermal measurement, or arbitrary IOS
command/network emulation. The Packet Tracer-style experience consists of a 2D
device workspace, valid links, configuration controls, derived readings and fault
correction. Practical certification still requires the appropriate physical
competency assessment. Existing hardware and network images are reused; no new
image assets or replacement simulation engine were introduced.

## Progression and evidence authority

1. COC1 starts available. Access to each later COC requires completion records for
   **every** earlier COC. Widgets and the mission route check server access; a
   restrictive RLS INSERT policy also denies locked-COC evidence.
2. Each of the five mission work orders must be confirmed at its review stage.
   The authenticated server invokes a service-role-only, SECURITY INVOKER
   PostgreSQL evaluator. It replays append-only raw actions in server-ID order
   against the versioned server contract, following the latest explicit reset.
3. Evaluation derives compatibility, placement/orientation, prerequisite steps,
   connections, settings, tool use, revealed facts, repair operations and test
   outcomes. It ignores client `simulation_valid`, phase-completion flags,
   equipment snapshots and measured-result claims. Configuration changes make
   earlier test readings stale. Completion requires every work phase and its
   equipment conditions.
4. After five verified missions, the server reserves or resumes one quiz attempt.
   Five MCQs are selected and shuffled from the 32-question grounded bank (eight
   per COC). Optional free AI produces wording variants while trusted choices,
   answer keys, explanations and page references stay server-controlled.
5. Each selected answer is saved on the server. Keys/explanations/scores are
   excluded from active-quiz responses and the private table has no learner SELECT
   grant. Submitted quizzes show their database-derived score and explanations.
6. A score of at least 4/5 records COC completion once. Failed attempts retain the
   lock and allow another quiz. Repeated submissions return the saved result;
   completed COCs reopen their successful quiz rather than consuming another
   generation request. Other learners cannot read or submit the attempt.

Existing mission persistence remains in `progress_resume_service.dart` and the
practice evidence transport. The new progression records are independent of local
preferences and official released-result projections. Realtime subscriptions
include owned practice completion/progression records. Account/role checks require
an active learner before any trusted server operation. No new SECURITY DEFINER
function, client AI key, local scoring authority, or auto-release was introduced.

## Activation/configuration

Changes are committed locally on `Dro-branch`; no remote push, hosted migration,
published assessment change, or production deployment was performed.

- Review/apply the two new migrations in order:
  `20261009090000_coc_practice_progression.sql`, then
  `20261009091000_css_practice_contracts.sql`.
- Deploy the dashboard, which serves `/api/learner/practice`. Its existing
  server-only Supabase secret/service-role configuration is required. Keep it out
  of public variables and mobile assets.
- Optional server variables: `OPENROUTER_API_KEY` and
  `PRACTICE_OPENROUTER_MODEL=openrouter/free`. Only `openrouter/free` or a `:free`
  selector is accepted. Provider prompt/completion prices are constrained to zero;
  failed, timed-out, rate-limited, malformed or unsupported generation uses the
  bank. Quiz reservations cap new attempts at eight per learner per 24 hours and
  recover abandoned generation after 60 seconds. No AI credential is required for
  bank-based practice to operate.
- Set the public mobile endpoint in the ignored environment file as
  `PRACTICE_API_URL=https://your-dashboard/api/learner/practice`, or build with
  `--dart-define=BQ_PRACTICE_API_URL=...`. Production uses HTTPS. Local HTTP is
  accepted only for localhost, 127.0.0.1, or Android emulator host 10.0.2.2.
  Access remains closed if progression cannot be verified; confirmed mission
  completion and quiz submission require connectivity.

The existing hosted migration history differs from the repository history, as
documented in `CODEX_STATE.md`. Reconcile history and apply only these reviewed new
changes; do not blindly replay the repository foundation on the hosted project.

## Reproducible verification

Run the repository's mobile and dashboard validation gates. For the new server
quiz tests, from `ByteQuest-Web-Dashboard`:

```powershell
node --import tsx --conditions=react-server --test tests/practice-quiz.test.ts
```

Generate independent raw action fixtures and check all 20 work orders against a
disposable local Supabase stack:

```powershell
cd ByteQuest-Mobile-App
dart run tool/export_practice_test_evidence.dart "$env:TEMP\bytequest-practice-evidence.json"
cd ..
node scripts/test-practice-progression.mjs "$env:TEMP\bytequest-practice-evidence.json"
node scripts/authenticated-practice-progression-e2e.mjs "$env:TEMP\bytequest-practice-evidence.json"
```

The first script rolls back everything. The authenticated HTTP script refuses a
remote Supabase URL, starts its own local dashboard on port 3006, creates two
disposable identities, checks the real API and retires the identities while
retaining their append-only evidence. It explicitly disables the AI credential
for deterministic fallback checks. It needs the local Supabase CLI, Docker, Node
and installed dashboard dependencies.

`dart run tool/export_practice_contracts.dart <temporary-output.sql>` exports the
canonical constraints for a drift comparison. Future changes to an already-applied
contract must use a **new forward migration and a new contract version**, not edit
these published migration files.

## Validation and remaining acceptance

Final gate results are recorded in the newest `CODEX_STATE.md` continuation.
The all-20 PostgreSQL replay, authenticated quiz/progression checks, responsive
widgets, fallback/provider validation tests and debug APK build are local evidence.
A live free-provider probe returned five fallback questions with trusted keys
preserved; successful live AI generation is **not** claimed.

No Android device is attached for a new on-device gesture/TalkBack acceptance run.
Device performance, real hosted rollout and successful live free-provider
generation remain deployment/acceptance checks. These limits do not change the
existing instructor-release requirements or claim new certification acceptance.
