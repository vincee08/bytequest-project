# ByteQuest — Prioritized remediation TODO — 2026-09-22

Derived from [the audit](BYTEQUEST_PRINCIPAL_QA_IMPLEMENTATION_AUDIT_2026-09-22.md) and [the 290-item RTM](BYTEQUEST_PRINCIPAL_QA_TRACEABILITY_2026-09-22.md). This is the **frozen baseline planning output** and its statuses describe the 2026-09-22 starting point. It is superseded for current status by [the final local verification report](BYTEQUEST_REMEDIATION_FINAL_VERIFICATION_2026-09-28.md) and [the item-level remediation traceability matrix](BYTEQUEST_REMEDIATION_TRACEABILITY_2026-09-27.md). Do not execute a baseline item without checking its reconciled status; already implemented/verified items are excluded from the current remaining TODOs. M = ByteQuest-Mobile-App; W = ByteQuest Web Dashboard; paths relative to repository root.

## P0 — Critical

No confirmed P0 defect was established by this audit. Do not interpret unavailable runtime evidence as proof that core authentication, submission or authority is broken. Reclassify promptly if V01/V02 reproduces an integrity failure.

## Remediation items

Already verified capabilities are excluded. R07–R09 are validation/acceptance work, not allegations of broken application behavior. R12 is additional maintenance of warnings, not a request to reimplement passing builds. R13 is explicitly optional. Do not change authoritative evaluation rules to simplify simulation implementation.

### R01 — P1 — High

ID: R01<br>
Priority: P1 — High<br>
Original PDF Phase: 2, 3 (COC1 M2), 6 (COC4 M4)<br>
Original Requirement: Validate compatibility, orientation and sequence; controlled installation/replacement; RTM P03-12–P03-14, P06-21.<br>
Current Status: IMPLEMENTED — DEFECTIVE<br>
Defect: F02. Production destinations omit accepted_categories, defaulting compatibility to true. Phase-level orientation options are not read by the item-level UI. Orientation/assembly order is not technically validated.<br>
Affected Mission: COC1 M2; COC4 M4.<br>
Affected File(s): M/lib/data/mission_definitions/coc1_definitions.dart; coc4_definitions.dart; M/lib/screens/simulation/interactions/controlled_placement_interaction.dart; runtime/mission_phase_completion_policy.dart.<br>
Recommended Fix: Repair the existing presentation contract and domain constraint handling. Preserve tap alternatives, structured evidence and the existing reusable widget. Invalid work may be recorded as evidence, but must not render as a valid installed state.<br>
Validation Test: Production-catalog item×destination matrix, all orientations, safe/unsafe sequences, correction and restart; compare visible installed state and accepted evidence.<br>
Acceptance Criteria: Every incompatible placement/orientation receives technical feedback; installed state is valid only when constraints are satisfied; correction is possible; no answer target highlighting in assessment; no duplicate component created.

### R02 — P1 — High

ID: R02<br>
Priority: P1 — High<br>
Original PDF Phase: 3 (COC1 M3), 19<br>
Original Requirement: Boot/setup, installation/configuration panel, driver/component choices, invalid configuration, restart, verification and interpretation; P03-19–P03-26, P19-01.<br>
Current Status: IMPLEMENTED — NON-COMPLIANT<br>
Defect: F03. Active M3 is cable routing, while the PDF and showcase require installation/configuration.<br>
Affected Mission: COC1 M3; related catalog/assessment mapping.<br>
Affected File(s): M/lib/data/mission_definitions/coc1_definitions.dart; mission_simulation_definitions.dart; M/lib/data/missions_data.dart; docs/BYTEQUEST_20_MISSION_SCORECARD.md; affected published package mapping after separate review.<br>
Recommended Fix: Reconcile the official mission map, preserve working cable functionality in the appropriate location, and compose the required installation workflow on the existing engine. Do not silently rename the current cable task or alter evaluator rules.<br>
Validation Test: Route/list/briefing/package identity consistency; boot → configuration → installation → restart → verification; negative configuration; evidence and resume.<br>
Acceptance Criteria: The launched M3 actually performs every PDF M3 action and is suitable as an installation/configuration showcase; protected evaluation contracts remain unchanged unless separately authorized.

### R03 — P1 — High

ID: R03<br>
Priority: P1 — High<br>
Original PDF Phase: 1, 3–9<br>
Original Requirement: Technical decisions, useful incorrect-action feedback, valid connections/configuration/sequences, and operational scenario consequences.<br>
Current Status: PARTIALLY IMPLEMENTED; affected missions IMPLEMENTED — NON-COMPLIANT<br>
Defect: F01. Input completeness is checked, but many inputs have no technical consequence. Invalid links and nonempty invalid settings can complete practice interaction gates.<br>
Affected Mission: All missions using connection/configuration/sequencing/decision; especially COC2 M3/M4 and COC3 M2–M4.<br>
Affected File(s): M/lib/screens/simulation/interactions/connection_interaction.dart; configuration_panel.dart; sequencing_interaction.dart; scenario_decision_interaction.dart; runtime/mission_runtime_reducer.dart; runtime/mission_phase_completion_policy.dart; COC definitions.<br>
Recommended Fix: Add stateful equipment constraints and responses to the existing runtime. Keep interaction completion separate from official competency evaluation. Provide concise failure reasons without exposing the correct answer. Keep the COC2 golden evaluator intact.<br>
Validation Test: Wrong endpoints, self/incompatible connections, invalid IP/subnet/gateway, service port/role/permission conflicts, unsafe order and correction paths using production definitions.<br>
Acceptance Criteria: Relevant invalid inputs visibly affect the simulated system/test result; corrective action changes that state; every meaningful action is evidenced; Flutter cannot finalize or release official competency.

### R04 — P1 — High

ID: R04<br>
Priority: P1 — High<br>
Original PDF Phase: 1, 3–9, 16, 18<br>
Original Requirement: Meaningful simulated tests, result interpretation, verification and recovery; configuration-driven device status and test-result visuals.<br>
Current Status: PARTIALLY IMPLEMENTED<br>
Defect: F04. Tests mostly finish on a timer and display Test completed, independent of technical system state.<br>
Affected Mission: All 20 practice missions; each technical test needs its own domain result contract.<br>
Affected File(s): M/lib/screens/simulation/interactions/test_run_interaction.dart; result_interpretation_interaction.dart; runtime/mission_runtime_models.dart; runtime/mission_runtime_reducer.dart; components/simulation_scene.dart; COC definitions.<br>
Recommended Fix: Introduce typed, state-derived technical result data and reuse the existing test lifecycle/rendering/persistence. Model appropriate cable/network/installation/service/access/repair results. Preserve backend scoring and existing cancellation/retry protection.<br>
Validation Test: Paired wrong/right setup outputs, corrected retest, result persistence, interruption/cancel/resume, duplicate completion prevention, interpretation linked to the recorded result.<br>
Acceptance Criteria: The learner can observe a concrete result and explain it; wrong work produces a meaningful failure/result difference; test evidence includes enough inputs/results to review the work.

### R05 — P1 — High

ID: R05<br>
Priority: P1 — High<br>
Original PDF Phase: 1, 3–7<br>
Original Requirement: Every missing or shallow COC-specific task identified in the atomic matrix, including meaningful inspection, classification, abnormalities, connections, settings, tool use, service operation and maintenance.<br>
Current Status: PARTIALLY IMPLEMENTED / NOT IMPLEMENTED / IMPLEMENTED — NON-COMPLIANT<br>
Defect: F07. Some phase titles promise actions that resolve to labels, a generic choice, or a record-only control. COC4 M5 maintenance/repair is one generic confirmation.<br>
Affected Mission: COC1 M1/M2/M4/M5; COC3 preparation/install/permissions/services/recovery; COC4 M1/M4/M5; other partial rows in Phases 3–6.<br>
Affected File(s): M/lib/data/mission_definitions/coc1_definitions.dart; coc2_definitions.dart; coc3_definitions.dart; coc4_definitions.dart; mission_simulation_definitions.dart; mission_content_data.dart; existing interaction widgets.<br>
Recommended Fix: Compose each missing technical task using the existing interaction families and domain state. Supply actual inspection details instead of repeating object labels. Add per-case maintenance/tool/configuration operations and a structured service report. Do not create 20 replacement screens.<br>
Validation Test: Trace every affected atomic requirement to a production-data action, visible response, structured evidence and negative case. Verify tool compatibility and per-case maintenance/repair state.<br>
Acceptance Criteria: No task is credited solely because a phase title/button exists. Each affected RTM row has a demonstrated technical action and evidence; all five M5 service cases have performed corrective work and verification.

### R07 — P1 — High verification gate

ID: R07<br>
Priority: P1 — High verification gate<br>
Original PDF Phase: 1, 11, 14, 17, 18, 20<br>
Original Requirement: All 20 Android workflows; same-attempt restart, phase/evidence/configuration/connection restoration, deduplication, no premature evaluation; responsive/accessibility acceptance.<br>
Current Status: BLOCKED / UNKNOWN — not a confirmed application defect<br>
Defect: V01. No Android device/emulator available. Unit/widget tests do not establish process-death, TalkBack or complete device operation.<br>
Affected Mission: All 20, each individually.<br>
Affected File(s): M/integration_test/ (currently absent); existing test/ runtime/accessibility tests; docs audit evidence; Android device/emulator environment.<br>
Recommended Fix: Provide an Android test target and authorized test learner. Execute the complete manual matrix and add durable device integration coverage where practical. Do not alter application behavior merely to make tests pass.<br>
Validation Test: For every mission: launch, scenario, correct/incorrect interactions, evidence, configure/connect, pause, force-close, relaunch same attempt, resume, review/back/confirm, submit; compact/standard/tablet portrait and landscape; 2x text, TalkBack, reduced motion; network loss/reconnect.<br>
Acceptance Criteria: Dated per-mission evidence proves all 18 Phase 20 manual checks; same attempt and accepted evidence restored exactly once; no premature evaluation, crashes, overflow or dead controls; all gesture alternatives usable.

### R08 — P1 — High verification gate

ID: R08<br>
Priority: P1 — High verification gate<br>
Original PDF Phase: 12, 13, 17, 18, 20<br>
Original Requirement: Authenticated learner submission → instructor review → finalization → release → learner result; synchronized progress/analytics and authoritative persistence.<br>
Current Status: PARTIALLY IMPLEMENTED / BLOCKED for configured end-to-end harness<br>
Defect: V02. Implementation and local SQL checks exist; current hosted authenticated lifecycle/Realtime behavior and migration parity are unverified. Available hosted harness lacks test setup credentials.<br>
Affected Mission: All 20; preserve dedicated COC2 M2 reference path.<br>
Affected File(s): scripts/authenticated-all-missions-lifecycle-e2e.mjs; authenticated-coc2-lifecycle-e2e.mjs; authenticated-realtime-sync-e2e.mjs; M/lib/services/learner_realtime_coordinator.dart; W/src/components/realtime/RealtimeRouteRefresh.tsx; supabase migrations/tests.<br>
Recommended Fix: Use an authorized disposable test environment/accounts and confirm deployment version; run existing scripts with complete configuration and observe both UIs. Do not apply migrations or publish assessment packages as an unreviewed audit side effect.<br>
Validation Test: Correct/incorrect/incomplete evidence, cross-role denials, replay/duplicate submit, provisional visibility, instructor ownership, finalize/release idempotency, websocket reconnect, learner release visibility and progress/analytics invalidation.<br>
Acceptance Criteria: Fresh authenticated results cover every mission and the protected cable contract; no premature learner release; permitted changes propagate and unauthorized users cannot read/write them. Existing local/static verified authority is preserved.

### R06 — P2 — Medium

ID: R06<br>
Priority: P2 — Medium<br>
Original PDF Phase: 6 (COC4 M5), 9<br>
Original Requirement: Earned information, diagnostic choices, delayed cause revelation and meaningful branching evidence.<br>
Current Status: PARTIALLY IMPLEMENTED<br>
Defect: F05. Initial possible-cause lists make the fault obvious; one diagnose button reveals both finding and repair explanation.<br>
Affected Mission: COC4 M5 primarily; regression across COC1/2/3/4 troubleshooting missions.<br>
Affected File(s): M/lib/data/mission_simulation_definitions.dart:_coc4M5ServiceDiagnostics; mission_content_data.dart:getCOC4M5Scenarios; interactions/troubleshooting_branch_interaction.dart.<br>
Recommended Fix: Use plausible hypotheses and gate specific facts behind relevant tool/actions. Separate observed result, interpretation and corrective choice. Preserve the existing fact-reveal engine.<br>
Validation Test: Initial-state content/semantics inspection; different diagnostic branches; one earned fact per action; unavailable actions until prerequisites; evidence for every decision.<br>
Acceptance Criteria: No fixed answer-order cue or unearned root finding at start; diagnostic decisions influence information; recovery depends on the chosen corrective action.

### R09 — P2 — Medium verification/quality gate

ID: R09<br>
Priority: P2 — Medium verification/quality gate<br>
Original PDF Phase: 1, 15, 16, 18, 19<br>
Original Requirement: Premium technical 2D workspace, all ten PDF scorecard targets and four distinct showcases.<br>
Current Status: PARTIALLY IMPLEMENTED / UNKNOWN<br>
Defect: F08/V03. Existing high scores are provisional. Scene realism, visual hierarchy, smoothness and showcase quality lack current device evidence; known technical gaps already prevent acceptance.<br>
Affected Mission: All 20; showcases COC1 M3, COC2 M3, COC3 M4, COC4 M5 need reassessment.<br>
Affected File(s): docs/BYTEQUEST_20_MISSION_SCORECARD.md; M/lib/screens/simulation/components/simulation_scene.dart; lib/core/theme/app_theme.dart; COC definitions.<br>
Recommended Fix: After technical fixes, capture real layouts and apply the PDF's existing scorecard. Adjust only observed visual defects. Confirm four different technical experiences; avoid duplicate scene engines or speculative redesign.<br>
Validation Test: Screenshots/video and interaction traces at target Android sizes/orientations/text settings; compare all ten categories to exact thresholds; inspect animation-to-state relationships.<br>
Acceptance Criteria: 20/20 functional and acceptable/rich, 0 weak/form-only/drag-only; every category meets its PDF threshold with evidence; four showcases communicate simulation depth.

### R10 — P2 — Medium

ID: R10<br>
Priority: P2 — Medium<br>
Original PDF Phase: 1, 3, 5, 6, 19 (task communication)<br>
Original Requirement: Clear, consistent scenario and mission identity.<br>
Current Status: IMPLEMENTED — NON-COMPLIANT in identified labels<br>
Defect: F09. Titles and active tasks disagree for several mission IDs.<br>
Affected Mission: COC1 M4; COC3 M3/M4; COC4 M2/M4; M3 scope handled by R02.<br>
Affected File(s): M/lib/data/mission_definitions/coc1_definitions.dart; coc3_definitions.dart; coc4_definitions.dart; missions_data.dart; relevant list/briefing/published package mappings.<br>
Recommended Fix: Reconcile display labels and approved mission map, retaining stable evidence identity and evaluator contracts. Review database-backed labels as well as local catalog labels.<br>
Validation Test: List → briefing → runtime → evidence review → instructor record identity checks for all 20 missions.<br>
Acceptance Criteria: No mission promises BIOS/OS while showing peripherals, users while showing services, or network troubleshooting while showing component replacement.

### R11 — P3 — Low

ID: R11<br>
Priority: P3 — Low<br>
Original PDF Phase: 7; additional AGENTS.md content rule<br>
Original Requirement: Consistent centralized technical feedback.<br>
Current Status: PARTIALLY IMPLEMENTED<br>
Defect: F10. Several feedback/UI strings remain inline in reusable widgets.<br>
Affected Mission: Shared interaction components.<br>
Affected File(s): M/lib/screens/simulation/interactions/connection_interaction.dart; tool_selection_interaction.dart; test_run_interaction.dart; M/lib/data/mission_content_data.dart.<br>
Recommended Fix: Move relevant feedback text into the existing content catalog during the approved feedback implementation, preserving behavior and semantics.<br>
Validation Test: Existing widget/semantics suite plus targeted content-reference checks.<br>
Acceptance Criteria: Technical feedback is consistently sourced and concise; no generic Wrong/Correct substitutes for technical explanation; no regression in accessible labels.

### R12 — P3 — Low

ID: R12<br>
Priority: P3 — Low<br>
Original PDF Phase: 20; tooling maintenance<br>
Original Requirement: Maintain reliable analysis/tests/builds as supported tooling evolves.<br>
Current Status: Current gates IMPLEMENTED — VERIFIED; maintenance warning only<br>
Defect: F11. Kotlin/KGP/SDK XML warnings, next lint deprecation and informational Dart diagnostics. This item addresses warnings only, not already-passing build requirements.<br>
Affected Mission: Repository-wide tooling.<br>
Affected File(s): M/android/settings.gradle; android/app/build.gradle; pubspec.yaml when needed; W/package.json; analyzer-reported source locations.<br>
Recommended Fix: Schedule narrowly scoped compatible tool/plugin updates and info cleanup in a separate change; keep versions/evaluator behavior stable during the audit.<br>
Validation Test: All required Flutter and web gates plus Android launch/regression smoke.<br>
Acceptance Criteria: Addressed warnings no longer appear; no new analyzer errors, failed tests or build/runtime regressions.

### R13 — P3 — Optional

ID: R13<br>
Priority: P3 — Optional<br>
Original PDF Phase: 2 (scene UX extension, not explicit mandatory restart data)<br>
Original Requirement: Optional camera restoration if intended by the existing runtime model.<br>
Current Status: INFORMATIONAL<br>
Defect: F06. Serialized camera fields are not bound to SimulationScene's TransformationController.<br>
Affected Mission: Shared scene across all missions.<br>
Affected File(s): M/lib/screens/simulation/components/simulation_scene.dart; runtime/mission_runtime_models.dart.<br>
Recommended Fix: Only if desired, connect existing camera fields to persistence; otherwise clarify scope. Do not treat this as failure of verified evidence/configuration/connection restoration.<br>
Validation Test: Pan/zoom, leave/reopen/restart, fit/reset, orientation change.<br>
Acceptance Criteria: Chosen camera behavior is documented and consistent; required mission-state persistence remains correct.

## Complete open-requirement coverage

The following table includes only the 171 RTM rows that are not IMPLEMENTED — VERIFIED. Multiple rows can share one root-cause fix. Optional practice hints are not converted into a mandatory requirement. The row's original requirement, exact status and evidence remain in the linked RTM.

| RTM ID | Scope | Required action / validation |
|---|---|---|
| P01-02 | Global mission quality: 3–6 meaningful interaction phases | R03, R04, R05, R07 |
| P01-05 | Global mission quality: At least one technical decision | R03, R04, R05, R07 |
| P01-06 | Global mission quality: Observation, testing or verification | R04, R05; R07 for device proof |
| P01-08 | Global mission quality: Useful incorrect-action feedback without revealing answers | R03, R04, R05, R07 |
| P01-10 | Global mission quality: Additional practice hints where appropriate (permissive PDF wording) | Optional guidance review only; PDF says may. No mandatory fix. |
| P01-11 | Global mission quality: Mission state survives pause/resume | R03, R04, R05, R07 |
| P01-14 | Global mission quality: Works across Android screen sizes | R07 |
| P01-15 | Global mission quality: Polished submission-review stage | R03, R04, R05, R07 |
| P02-07 | Core scene: Landscape support | R01, R03, R04, R07 |
| P02-12 | Core scene: Error feedback | R01, R03, R04, R07 |
| P02-13 | Core scene: Scene-state persistence | R01, R03, R04, R07 |
| P02-21 | Reusable interactions: Controlled Placement | R01, R03, R04, R07 |
| P02-23 | Reusable interactions: Testing | R04, R05; R07 for device proof |
| P02-26 | Reusable interactions: Result Interpretation | R04, R05; R07 for device proof |
| P02-29 | Tool system: Apply tool only to compatible objects | R01, R03, R04, R07 |
| P02-30 | Tool system: Reject invalid tool usage with technical feedback | R01, R03, R04, R07 |
| P02-31 | Tool system: Show simulated result after tool action | R04, R05; R07 for device proof |
| P03-01 | COC1 M1: Complete 2D computer/workbench scene | R03, R04, R05 |
| P03-02 | COC1 M1: Tap-to-inspect components | R03, R04, R05 |
| P03-03 | COC1 M1: Multi-select relevant components | R03, R04, R05 |
| P03-04 | COC1 M1: Inspect ports/components | R03, R04, R05 |
| P03-05 | COC1 M1: Tool identification | R03, R04, R05 |
| P03-06 | COC1 M1: Component classification | R03, R04, R05 |
| P03-07 | COC1 M1: Identify abnormalities | R03, R04, R05 |
| P03-09 | COC1 M1: Finish with verification | R04, R05; R07 for device proof |
| P03-12 | COC1 M2: Validate compatibility | R01 |
| P03-13 | COC1 M2: Validate assembly sequence | R01, R04, R05 |
| P03-14 | COC1 M2: Validate orientation where relevant | R01 |
| P03-16 | COC1 M2: Connect required simulated connections | R01, R04, R05 |
| P03-18 | COC1 M2: Verify final assembly | R01, R04, R05 |
| P03-19 | COC1 M3: Boot/setup scenario | R02, R04 |
| P03-20 | COC1 M3: Select installation/configuration actions | R02, R04 |
| P03-21 | COC1 M3: Sequence installation steps | R02, R04 |
| P03-22 | COC1 M3: Simulated configuration panel | R02, R04 |
| P03-23 | COC1 M3: Driver/component selection where appropriate | R02, R04 |
| P03-24 | COC1 M3: Detect incorrect configuration | R02, R04 |
| P03-25 | COC1 M3: Simulate restart/verification | R02, R04 |
| P03-26 | COC1 M3: Interpret result | R02, R04 |
| P03-27 | COC1 M4: Identify peripheral | R03, R04, R05 |
| P03-28 | COC1 M4: Select correct connection | R03, R04, R05 |
| P03-30 | COC1 M4: Configure appropriate setting | R03, R04, R05 |
| P03-31 | COC1 M4: Inspect device status | R04, R05; R07 for device proof |
| P03-32 | COC1 M4: Run simulated test | R04, R05; R07 for device proof |
| P03-33 | COC1 M4: Interpret result | R04, R05; R07 for device proof |
| P03-34 | COC1 M4: Fix incorrect configuration | R03, R04, R05 |
| P03-37 | COC1 M5: Select tool | R03, R04, R05 |
| P03-38 | COC1 M5: Perform simulated test | R04, R05; R07 for device proof |
| P03-39 | COC1 M5: Interpret result | R04, R05; R07 for device proof |
| P03-40 | COC1 M5: Identify likely problem | R03, R04, R05 |
| P03-41 | COC1 M5: Perform corrective action | R03, R04, R05 |
| P03-42 | COC1 M5: Final verification | R04, R05; R07 for device proof |
| P04-01 | COC2 M1: Identify network devices | R03, R04, R05 |
| P04-02 | COC2 M1: Select appropriate cable/connection | R03, R04, R05 |
| P04-04 | COC2 M1: Sequence preparation | R03, R04, R05 |
| P04-06 | COC2 M1: Simulated cable/network test | R04, R05; R07 for device proof |
| P04-07 | COC2 M1: Interpret test output | R04, R05; R07 for device proof |
| P04-13 | COC2 M2: Connectivity testing | R04, R05; R07 for device proof |
| P04-14 | COC2 M2: Result interpretation | R04, R05; R07 for device proof |
| P04-16 | COC2 M3: Inspect requirements | R03, R04, R05 |
| P04-20 | COC2 M3: Build topology | R03, R04, R05 |
| P04-21 | COC2 M3: Verify link status | R04, R05; R07 for device proof |
| P04-22 | COC2 M3: Fix invalid connections | R03, R04, R05 |
| P04-27 | COC2 M4: Connectivity test | R04, R05; R07 for device proof |
| P04-28 | COC2 M4: Interpret result | R04, R05; R07 for device proof |
| P04-29 | COC2 M4: Correct configuration errors | R03, R04, R05 |
| P04-30 | COC2 M5: Inspect topology | R03, R04, R05 |
| P04-31 | COC2 M5: Test connection | R04, R05; R07 for device proof |
| P04-33 | COC2 M5: Identify possible fault | R03, R04, R05 |
| P04-35 | COC2 M5: Apply fix | R03, R04, R05 |
| P04-36 | COC2 M5: Retest | R04, R05; R07 for device proof |
| P05-01 | COC3 M1: Inspect server environment | R03, R04, R05 |
| P05-02 | COC3 M1: Identify requirements | R03, R04, R05 |
| P05-04 | COC3 M1: Inspect network readiness | R03, R04, R05 |
| P05-05 | COC3 M1: Sequence setup preparation | R03, R04, R05 |
| P05-06 | COC3 M1: Validate setup | R03, R04, R05 |
| P05-07 | COC3 M2: Simulated setup/configuration flow | R03, R04, R05 |
| P05-09 | COC3 M2: Choices affect later simulated state | R03, R04, R05 |
| P05-11 | COC3 M2: Simulate restart | R04, R05; R07 for device proof |
| P05-12 | COC3 M2: Verify installation | R04, R05; R07 for device proof |
| P05-13 | COC3 M2: Meaningful issues for incorrect configuration | R03, R04, R05 |
| P05-15 | COC3 M3: Assign role/group | R03, R04, R05 |
| P05-16 | COC3 M3: Assign appropriate permissions | R03, R04, R05 |
| P05-17 | COC3 M3: Inspect effective access | R04, R05; R07 for device proof |
| P05-18 | COC3 M3: Test access | R04, R05; R07 for device proof |
| P05-19 | COC3 M3: Diagnose permission errors | R03, R04, R05 |
| P05-20 | COC3 M4: Inspect services | R03, R04, R05 |
| P05-21 | COC3 M4: Configure service | R03, R04, R05 |
| P05-22 | COC3 M4: Start/stop simulated service | R03, R04, R05 |
| P05-23 | COC3 M4: Configure required values | R03, R04, R05 |
| P05-24 | COC3 M4: Inspect status | R04, R05; R07 for device proof |
| P05-25 | COC3 M4: Test client access | R04, R05; R07 for device proof |
| P05-26 | COC3 M4: Interpret server response | R04, R05; R07 for device proof |
| P05-30 | COC3 M5: Test connectivity | R04, R05; R07 for device proof |
| P05-32 | COC3 M5: Select corrective action | R03, R04, R05 |
| P05-33 | COC3 M5: Retest | R04, R05; R07 for device proof |
| P05-34 | COC3 M5: Verify recovery | R04, R05; R07 for device proof |
| P06-01 | COC4 M1: Inspect environment | R03, R04, R05 |
| P06-02 | COC4 M1: Identify symptoms | R03, R04, R05 |
| P06-05 | COC4 M1: Choose diagnostic priority | R03, R04, R05 |
| P06-06 | COC4 M1: Build preliminary diagnosis | R03, R04, R05 |
| P06-10 | COC4 M2: Simulated test | R04, R05; R07 for device proof |
| P06-11 | COC4 M2: Interpret result | R04, R05; R07 for device proof |
| P06-12 | COC4 M2: Identify fault | R03, R04, R05 |
| P06-14 | COC4 M2: Verify | R04, R05; R07 for device proof |
| P06-17 | COC4 M3: Interpret each result | R04, R05; R07 for device proof |
| P06-20 | COC4 M4: Tool selection | R01, R04, R05 |
| P06-21 | COC4 M4: Controlled replacement | R01 |
| P06-23 | COC4 M4: Repair sequence | R01, R04, R05 |
| P06-24 | COC4 M4: Verification | R01, R04, R05 |
| P06-25 | COC4 M4: Post-repair test | R01, R04, R05 |
| P06-28 | COC4 M5: Identify issues | R05, R06 |
| P06-29 | COC4 M5: Prioritize faults | R05, R06 |
| P06-30 | COC4 M5: Choose tools | R05, R06 |
| P06-31 | COC4 M5: Perform maintenance | R05, R06 |
| P06-32 | COC4 M5: Repair/configure | R05, R06 |
| P06-33 | COC4 M5: Test system | R04, R05; R07 for device proof |
| P06-34 | COC4 M5: Interpret results | R04, R05; R07 for device proof |
| P06-35 | COC4 M5: Final verification | R04, R05; R07 for device proof |
| P06-36 | COC4 M5: Submission report | R05, R06 |
| P07-01 | Technical feedback: Concise technical feedback rather than generic Wrong | R03, R05, R11 |
| P07-02 | Technical feedback: Explain failure without revealing answer | R03, R05, R11 |
| P07-03 | Technical feedback: Brief success feedback after verified action | R03, R05, R11 |
| P08-02 | Scenario state: Device status changes after correct configuration | R03, R04 |
| P08-04 | Scenario state: Visual test status/result | R03, R04 |
| P09-01 | Troubleshooting branches: Do not expose all diagnostic information initially | R06, R05 |
| P09-04 | Troubleshooting branches: Meaningful evidence-producing branches | R06, R05 |
| P11-05 | Submission review: Readable compact review | R07, R09 |
| P13-01 | Realtime: Submission updates instructor review | R08 |
| P13-02 | Realtime: Release updates learner mobile result | R08 |
| P13-03 | Realtime: Progress and analytics synchronized | R08 |
| P15-03 | Visual design: 2D workspace gets most screen space | R09 (after R01–R05), R07, R08 |
| P15-06 | Visual design: Avoid giant cards/logos/excessive effects or childish styling | R09 (after R01–R05), R07, R08 |
| P16-02 | State animations: Status indicators fade on change | R03, R04 |
| P17-01 | Pause/resume: Same attempt after app restart | R07 |
| P18-01 | Quality targets: Scenario realism ≥4/5 | R09 (after R01–R05), R07, R08 |
| P18-03 | Quality targets: Technical relevance ≥4/5 | R09 (after R01–R05), R07, R08 |
| P18-04 | Quality targets: Decision depth ≥3/5 | R09 (after R01–R05), R07, R08 |
| P18-05 | Quality targets: 2D scene quality ≥4/5 | R09 (after R01–R05), R07, R08 |
| P18-06 | Quality targets: Evidence quality ≥4/5 | R09 (after R01–R05), R07, R08 |
| P18-07 | Quality targets: Accessibility ≥4/5 | R09 (after R01–R05), R07, R08 |
| P18-08 | Quality targets: Visual polish ≥4/5 | R09 (after R01–R05), R07, R08 |
| P18-09 | Quality targets: Persistence 5/5 | R09 (after R01–R05), R07, R08 |
| P18-10 | Quality targets: Assessment integrity 5/5 | R09 (after R01–R05), R07, R08 |
| P18-11 | Quality targets: 20/20 functional | R09 (after R01–R05), R07, R08 |
| P18-12 | Quality targets: 20/20 acceptable or rich | R09 (after R01–R05), R07, R08 |
| P18-13 | Quality targets: 0 weak | R09 (after R01–R05), R07, R08 |
| P18-14 | Quality targets: 0 form-only | R09 (after R01–R05), R07, R08 |
| P19-01 | Showcases: COC1 installation/configuration showcase | R02, R04 |
| P19-02 | Showcases: COC2 networking/topology showcase | R09 (after R01–R05), R07, R08 |
| P19-03 | Showcases: COC3 server-configuration showcase | R09 (after R01–R05), R07, R08 |
| P19-04 | Showcases: COC4 troubleshooting/repair showcase | R09 (after R01–R05), R07, R08 |
| P19-05 | Showcases: Four showcases demonstrate different interaction types | R09 (after R01–R05), R07, R08 |
| P20-04 | Manual all-mission acceptance: Launch | R07, R08 |
| P20-05 | Manual all-mission acceptance: Scenario displays | R07, R08 |
| P20-06 | Manual all-mission acceptance: Responsive 2D scene | R07, R08 |
| P20-07 | Manual all-mission acceptance: Interactions work | R07, R08 |
| P20-08 | Manual all-mission acceptance: Incorrect states work | R07, R08 |
| P20-09 | Manual all-mission acceptance: Evidence saves | R07, R08 |
| P20-10 | Manual all-mission acceptance: Pause works | R07, R08 |
| P20-11 | Manual all-mission acceptance: Resume works | R07, R08 |
| P20-12 | Manual all-mission acceptance: Submission review works | R07, R08 |
| P20-13 | Manual all-mission acceptance: Submit works | R07, R08 |
| P20-14 | Manual all-mission acceptance: Evaluation works | R07, R08 |
| P20-15 | Manual all-mission acceptance: Realtime works | R07, R08 |
| P20-16 | Manual all-mission acceptance: Instructor sees result | R07, R08 |
| P20-17 | Manual all-mission acceptance: Release works | R07, R08 |
| P20-18 | Manual all-mission acceptance: Learner sees result | R07, R08 |
| P20-19 | Manual all-mission acceptance: No crashes | R07, R08 |
| P20-20 | Manual all-mission acceptance: No overflow | R07, R08 |
| P20-21 | Manual all-mission acceptance: No dead buttons | R07, R08 |
| P20-22 | Final experience: Inspect → Interact → Diagnose → Configure → Connect → Test → Interpret → Troubleshoot → Verify → Submit Evidence | R04, R05; R07 for device proof |

## Revalidation sequence

1. Correct production catalog/placement wiring and mission-scope mismatches (R01/R02).
2. Add technical equipment/test consequences and missing tasks on the existing engine (R03–R05), with production-definition negative tests.
3. Strengthen diagnostic choices and task identity (R06/R10).
4. Execute Android and authenticated backend/Realtime acceptance (R07/R08); retain the passing regression suite and reference cable evaluator.
5. Re-score all 20 missions using only the PDF thresholds and approve four showcases from actual evidence (R09).
6. Address optional maintenance/polish separately (R11–R13).
