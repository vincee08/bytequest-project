# ByteQuest — Principal QA implementation audit

Audit date: 2026-09-22. Verdict: **NOT READY for acceptance against the PDF**. This is an implementation audit; no application, evaluator, database-schema, or mission-logic fixes were made.

Companion deliverables: [290-item requirements matrix](BYTEQUEST_PRINCIPAL_QA_TRACEABILITY_2026-09-22.md) · [prioritized remediation TODO](BYTEQUEST_PRINCIPAL_QA_REMEDIATION_TODO_2026-09-22.md).

## A. Executive summary

The project and reference PDF both exist. The PDF was read across all 11 pages. Its SHA-256 is `16993438CED913718B2B0295D0ADF773675AE7A87671F89AE3F538BD22BCC9EB`.

The existing implementation is substantial: all 20 practice missions route into a shared typed simulation engine; reusable interaction widgets, structured evidence, offline retry/reconciliation, submission review, backend evaluation, instructor finalization/release, Realtime subscriptions, and accessibility tests exist. This audit does not recommend replacing those systems.

The principal gap is the difference between recording an interaction and simulating its technical consequence. Several practice interactions accept any populated selection/configuration/connection, while generic test actions finish on a timer and display “Test completed.” Consequently, a learner can record work without observing whether the equipment would actually function. The backend may still correctly evaluate an authoritative assessment; these findings do not establish a bypass of backend scoring.

There are also definite mission-content and wiring gaps: COC1 M3 implements cable routing instead of the PDF installation/configuration workflow; COC1 M2 lacks effective compatibility and orientation validation; COC4 M4 shares the placement weakness; and COC4 M5 reduces maintenance/repair to a single generic action.

| Requirement classification | Count |
|---|---:|
| IMPLEMENTED — VERIFIED within stated evidence scope | 119 |
| PARTIALLY IMPLEMENTED | 120 |
| IMPLEMENTED BUT BROKEN | 3 |
| IMPLEMENTED BUT NON-COMPLIANT | 7 |
| NOT IMPLEMENTED | 14 |
| UNKNOWN / REQUIRES RUNTIME VERIFICATION | 7 |
| BLOCKED | 20 |
| **Total atomic PDF requirements** | **290** |

Counting is one row per PDF checkbox/score target/command/final acceptance statement. Global requirements are not multiplied by 20. Requirement counts are not defect counts: one shared defect can affect many requirements.

All 20 missions were individually inspected in the catalog and traced to active routing and shared components. None received full Android end-to-end certification. Six have especially clear failing mission-specific acceptance conditions; fourteen are partially verified. Manual Android acceptance is blocked for all 20 because no Android device/emulator is attached. Hosted authenticated lifecycle/Realtime results were not verified with the available environment.

### Baseline and scope

The audited working tree is branch `new`, HEAD `3d095aa2abf35acb305a067c571024b9945b64fe`, with substantial pre-existing tracked and untracked changes. Findings describe that working tree, not just HEAD. The standing branch name `Dro-branch` does not match the current branch; no branch switch, reset, staging, commit, or push was performed.

The initial inventory covered roughly 750 relevant files: 356 mobile, 219 dashboard, 56 Supabase, 97 documentation, and 15 scripts, plus root configuration. Generated dependency/build directories and Git internals were excluded from source inventory. File inventory does not imply line-by-line review of every unrelated screen; the mission execution paths, persistence/evidence/authority paths, relevant UI components, tests, migrations and configuration received the detailed review.

```text
ByteQuest/
  ByteQuest-Mobile-App/
    lib/core/                  config, routes, theme, shared widgets
    lib/data/                  mission catalog, COC1–COC4 definitions/content
    lib/models/                learner, assessment, progress and content models
    lib/screens/simulation/    launcher, shared runtime, components, interactions, templates
    lib/services/              Supabase, evidence, resume, auth, Realtime
    lib/screens/               learner/auth/progress/result and supporting workflows
    test/                      unit, widget, catalog, recovery, accessibility tests
    android/                   Gradle, manifest and Android launcher configuration
    pubspec.yaml               provider, supabase_flutter, shared_preferences, dotenv
    integration_test/          ABSENT
  ByteQuest Web Dashboard/
    src/app/                   instructor/admin routes, reports and server endpoints
    src/components/attempts/   evidence review, finalize and release controls
    src/components/realtime/  route invalidation
    src/lib/supabase/          server/client/admin access
    tests/                     web unit/security/provider tests
  supabase/
    migrations/                schema, RLS, RPCs, evaluators, Realtime, catalogs
    tests/                     seven rollback SQL test files
    config.toml
  scripts/                     authenticated lifecycle, Realtime and package tools
  docs/                        architecture, earlier audits, scorecard and references
  AGENTS.md, bytequest.md, CODEX_STATE.md, README.md
```

Earlier reports and “complete” comments were used as search leads only. Fresh command results take precedence over prior claims. No secrets are included here.

## B. Phase summary

“Partial” below is the phase conclusion, not a claim that every row in that phase is incomplete. Exact classifications are in the RTM.

| Phase | Conclusion | Evidence and remaining gap |
|---|---|---|
| 1 Global quality | PARTIALLY IMPLEMENTED | 20 typed scenarios and interaction/evidence paths; technical feedback/results and full device acceptance incomplete. |
| 2 Reusable system | PARTIALLY IMPLEMENTED | SimulationScene and 14 reusable families are actively used; placement metadata and technical result fidelity incomplete. |
| 3 COC1 | PARTIALLY IMPLEMENTED / specific failures | M2 validation broken; M3 scope non-compliant; M1/M4 technical tasks missing. |
| 4 COC2 | PARTIALLY IMPLEMENTED | Protected reference assessment contract retained; practice links/configuration lack technical simulation validation. |
| 5 COC3 | PARTIALLY IMPLEMENTED | Server-oriented workflows exist; configuration does not produce state-derived service/access outcomes. |
| 6 COC4 | PARTIALLY IMPLEMENTED / specific failures | Progressive findings exist; M4 placement and M5 maintenance depth fail. |
| 7 Feedback | PARTIALLY IMPLEMENTED | Stable concise overlay and compatibility feedback exist; most incorrect technical actions have no explanatory path. |
| 8 State changes | PARTIALLY IMPLEMENTED | Real connections, placements, hotspot and test lifecycle state; missing configuration-driven operational state/results. |
| 9 Branching | PARTIALLY IMPLEMENTED | Action-to-fact revelation works; M5 gives obvious cause hints and generic later repair choices. |
| 10 Gamification | IMPLEMENTED — VERIFIED, active-route scope | Progress separated from evaluation; unapproved reward rankings remain unavailable. |
| 11 Review | PARTIALLY IMPLEMENTED | Steps/count/return/explicit confirmation implemented; final Android readability unverified. |
| 12 Authority | IMPLEMENTED — VERIFIED, local/static scope | Backend evaluates; instructor finalizes/releases; no active client scoring equivalence accepted. |
| 13 Realtime | PARTIALLY IMPLEMENTED | Subscriptions/publication/refetch traced; current authenticated hosted propagation unverified. |
| 14 Accessibility | IMPLEMENTED — VERIFIED, automated component scope | Tap alternatives, 48dp/semantics/large text/reduced-motion tests pass; TalkBack acceptance remains blocked. |
| 15 Visual design | PARTIALLY IMPLEMENTED | Theme tokens and transitions traced; device visual hierarchy and scene-space dominance unverified. |
| 16 Animations | PARTIALLY IMPLEMENTED | State animations exist; a status animation cannot substitute for missing technical device state. |
| 17 Pause/resume | PARTIALLY IMPLEMENTED | Snapshot/replay/retry tests pass; physical process-death/relaunch of the same attempt unverified. |
| 18 Scorecard | NOT ACCEPTED | Existing provisional high scores cannot be promoted to verified acceptance; see conservative scorecard below. |
| 19 Showcases | PARTIALLY IMPLEMENTED | Four choices documented; COC1 showcase label conflicts with actual M3 cable workflow. |
| 20 Final testing | PARTIALLY IMPLEMENTED | Required three Flutter commands pass; all-mission manual Android acceptance remains blocked. |

## C. Twenty-mission matrix

Legend: **A** = automated/static capability verified; **P** = partial technical behavior; **U** = no device/hosted runtime proof; **F** = definite static defect/non-compliance. Launch A means the mission ID resolves through tested routing/catalog, not a claim of manual device launch. Evidence A covers structured dispatch/retry tests, not confirmed hosted receipt for every action. Persistence and accessibility share tested engines but still need mission-by-mission device checks. Evaluation A/U means server architecture/local checks verified, current authenticated deployed outcome unverified. Realtime P/U means wired but unverified end to end.

| Mission | Launch | Scenario | Interactions | Technical Decision | Evidence | Persistence | Accessibility | Evaluation | Realtime | Overall Status |
|---|---|---|---|---|---|---|---|---|---|---|
| COC1 M1 | A/U | A | P | P | A/U | A/U | A/U | A/U | P/U | PARTIALLY VERIFIED |
| COC1 M2 | A/U | A | F | P | A/U | A/U | A/U | A/U | P/U | FAIL — placement wiring |
| COC1 M3 | A/U | F vs PDF | P | P | A/U | A/U | A/U | A/U | P/U | FAIL — wrong workflow |
| COC1 M4 | A/U | A | P | P | A/U | A/U | A/U | A/U | P/U | PARTIALLY VERIFIED |
| COC1 M5 | A/U | A | P | P | A/U | A/U | A/U | A/U | P/U | PARTIALLY VERIFIED |
| COC2 M1 | A/U | A | P | P | A/U | A/U | A/U | A/U | P/U | PARTIALLY VERIFIED |
| COC2 M2 | A/U | A | P | P | A/U | A/U | A/U | A/U, golden contract | P/U | PARTIALLY VERIFIED |
| COC2 M3 | A/U | A | F | P | A/U | A/U | A/U | A/U | P/U | FAIL — invalid links unvalidated |
| COC2 M4 | A/U | A | F | P | A/U | A/U | A/U | A/U | P/U | FAIL — no technical config outcome |
| COC2 M5 | A/U | A | P | P | A/U | A/U | A/U | A/U | P/U | PARTIALLY VERIFIED |
| COC3 M1 | A/U | A | P | P | A/U | A/U | A/U | A/U | P/U | PARTIALLY VERIFIED |
| COC3 M2 | A/U | A | P | P | A/U | A/U | A/U | A/U | P/U | PARTIALLY VERIFIED |
| COC3 M3 | A/U | A, title mismatch | P | P | A/U | A/U | A/U | A/U | P/U | PARTIALLY VERIFIED |
| COC3 M4 | A/U | A, title mismatch | P | P | A/U | A/U | A/U | A/U | P/U | PARTIALLY VERIFIED |
| COC3 M5 | A/U | A | P | P | A/U | A/U | A/U | A/U | P/U | PARTIALLY VERIFIED |
| COC4 M1 | A/U | A | P | P | A/U | A/U | A/U | A/U | P/U | PARTIALLY VERIFIED |
| COC4 M2 | A/U | A, title mismatch | P | P | A/U | A/U | A/U | A/U | P/U | PARTIALLY VERIFIED |
| COC4 M3 | A/U | A | P | P | A/U | A/U | A/U | A/U | P/U | PARTIALLY VERIFIED |
| COC4 M4 | A/U | A, title mismatch | F | P | A/U | A/U | A/U | A/U | P/U | FAIL — replacement validation |
| COC4 M5 | A/U | A | F | P | A/U | A/U | A/U | A/U | P/U | FAIL — maintenance reduced to choice |

### Individual mission findings and the 22 requested checks

Every row below was checked against its own definition, not inferred from another mission. The RTM separately enumerates every COC-specific PDF action. Common checks 1–22 map as follows: launch/scenario (matrix), technical environment/phase variety/decisions/tasks/responses (row notes and F01–F07), testing/interpretation (F04), evidence/structure (RUN/AUTH/PERSIST), incorrect feedback (F01/F07), assessment secrecy (T01/GOLD/backend), practice guidance (catalog), persistence/pause/deduplication (T02/V01), review (REVIEW), responsive/accessible alternatives (T03/V01). Device-only claims remain unverified for each mission.

| Mission | What is implemented | What fails or remains incomplete |
|---|---|---|
| COC1 M1 | Inspection objects, safe-set selection, observation and readiness-test stages. | Multi-select choices describe actions rather than component classification; abnormalities/port-specific inspection/tool identification are insufficiently modeled; readiness output generic. |
| COC1 M2 | Component/destination selection, installed-state records, sequence UI, verification/review. | Empty compatibility metadata accepts every destination; orientation metadata is at the wrong level; no assembly-sequence validation or required connection phase. |
| COC1 M3 | Cable sequencing, five cable source/destination choices, test, interpretation and review. | PDF requires boot/setup/install/configure workflow; no configuration panel, driver selection, invalid setup consequence or real restart simulation. |
| COC1 M4 | Peripheral station inspection, tool use, connection and test flow. | Title says BIOS/OS; no full peripheral settings/status/error-correction simulation. |
| COC1 M5 | Symptom-driven actions, revealed diagnostic facts, correction/verification progression. | Tool/correction choices do not create a sufficiently detailed equipment state; test/interpretation fidelity incomplete. |
| COC2 M1 | Network objects, tool tray, preparation sequence, controlled connections and testing. | Sequence correctness, cable suitability and meaningful cable/network output are not simulated. |
| COC2 M2 | Practice topology/configuration/test stages and separate protected cable assessment contract. | Generic practice test output remains; current complete authenticated reference lifecycle was not rerun. No authoritative rule changes are proposed. |
| COC2 M3 | Requirement/device choices, node links and visible paths. | Arbitrary source/destination pairs accepted; no invalid-link diagnosis or corrective validation. |
| COC2 M4 | Network fields, apply action, test/interpretation/correction stages. | Nonempty values suffice; wrong address/subnet/gateway does not produce a differentiated connectivity result. |
| COC2 M5 | Topology/configuration inspection and progressive diagnostic facts, correction and retest. | Branch evidence exists, but corrective choices and retest are not coupled to a computed network condition. |
| COC3 M1 | Server environment/role/readiness/preparation stages. | Readiness/setup validation is generic; requirements are not a complete constraint model. |
| COC3 M2 | Setup fields, role, installation sequence and restart/verification stages. | Role/configuration choices mostly record data; incorrect settings do not produce meaningful later installation/service problems. |
| COC3 M3 | Account/group/permission controls plus access/diagnostic stages. | Title refers to network settings; effective access is not computed from user/group permissions; test output generic. |
| COC3 M4 | Service inspection/configuration and start/stop controls, client test/interpretation. | Title refers to users/groups; values/toggles do not produce a modeled service response. |
| COC3 M5 | Client/server/service/permission observations and correction/retest progression. | Recovery verification is not derived from a complete server/client state. |
| COC4 M1 | Environment inspection, observations and priority/diagnosis selection. | Choices record a decision but do not establish technical prioritization consequences. |
| COC4 M2 | Hardware symptom/tool diagnostics, interpretation, repair selection and verification. | Title says preventive maintenance; repair selection and generic verification do not demonstrate a repaired component. |
| COC4 M3 | Progressive diagnostic facts interleaved with result-interpretation stages. | Stronger branching structure than a single question; arbitrary nonempty interpretations still pass the interaction gate, with no validated technical response. |
| COC4 M4 | Replacement item/orientation UI, configuration, repair sequence and post-repair test. | No actual tool-selection control despite phase wording; compatibility defaults open; second placement phase has misplaced orientation metadata; no sequence/correct-operation validation. |
| COC4 M5 | Five service requests, separate fact-reveal actions, priority choice, test/interpretation, observation report and review. | Cause lists include obvious fault answers upfront; “maintenance/repair” is a single generic confirmation; no actual selected tool, repair/configuration operations or state-derived final verification. |

### PDF scorecard, applied conservatively

These are **provisional static quality judgments**, not new acceptance thresholds. The ten categories and thresholds are exactly the PDF's. U means insufficient runtime/visual evidence to score defensibly; U cannot pass a target. No total, percentage, weighted score or competency grade is invented. Scores of 3 indicate a meaningful but incomplete capability; 2 indicates materially shallow/misaligned behavior. Variety receives 4 for multiple functioning families; it does not imply technical depth.

Scenario/technical/decision ratings derive from the individual mission notes. Evidence quality is capped at 3 here because structured records exist but some records describe generic actions/results. Scene quality, visual polish, full accessibility, persistence 5/5 and assessment integrity 5/5 are withheld pending the required physical/hosted verification. Passing component tests is recorded separately.

| Mission | Scenario ≥4 | Variety ≥4 | Technical ≥4 | Decision ≥3 | Scene ≥4 | Evidence ≥4 | Access ≥4 | Polish ≥4 | Persist 5 | Integrity 5 | Acceptance |
|---|---:|---:|---:|---:|---|---:|---|---|---|---|---|
| COC1 M1 | 3 | 4 | 3 | 2 | U | 3 | U | U | U | U | Not met |
| COC1 M2 | 4 | 4 | 3 | 2 | U | 3 | U | U | U | U | Not met |
| COC1 M3 | 2 | 4 | 2 | 2 | U | 3 | U | U | U | U | Not met |
| COC1 M4 | 3 | 4 | 3 | 2 | U | 3 | U | U | U | U | Not met |
| COC1 M5 | 4 | 4 | 3 | 3 | U | 3 | U | U | U | U | Not met |
| COC2 M1 | 3 | 4 | 3 | 2 | U | 3 | U | U | U | U | Not met |
| COC2 M2 | 4 | 4 | 4 | 3 | U | 3 | U | U | U | U | Not met |
| COC2 M3 | 4 | 4 | 3 | 2 | U | 3 | U | U | U | U | Not met |
| COC2 M4 | 4 | 4 | 3 | 2 | U | 3 | U | U | U | U | Not met |
| COC2 M5 | 4 | 4 | 3 | 3 | U | 3 | U | U | U | U | Not met |
| COC3 M1 | 3 | 4 | 3 | 2 | U | 3 | U | U | U | U | Not met |
| COC3 M2 | 4 | 4 | 3 | 2 | U | 3 | U | U | U | U | Not met |
| COC3 M3 | 4 | 4 | 3 | 3 | U | 3 | U | U | U | U | Not met |
| COC3 M4 | 4 | 4 | 3 | 2 | U | 3 | U | U | U | U | Not met |
| COC3 M5 | 4 | 4 | 3 | 3 | U | 3 | U | U | U | U | Not met |
| COC4 M1 | 3 | 4 | 3 | 2 | U | 3 | U | U | U | U | Not met |
| COC4 M2 | 4 | 4 | 3 | 3 | U | 3 | U | U | U | U | Not met |
| COC4 M3 | 4 | 4 | 4 | 3 | U | 3 | U | U | U | U | Not met |
| COC4 M4 | 4 | 4 | 3 | 2 | U | 3 | U | U | U | U | Not met |
| COC4 M5 | 4 | 4 | 3 | 2 | U | 3 | U | U | U | U | Not met |

The existing scorecard identifies COC1 M3, COC2 M3, COC3 M4 and COC4 M5 as showcases. Selection exists; showcase readiness does not. COC1 M3 is especially misleading because the active content is cables. The final targets **20/20 functional, 20/20 acceptable/rich, 0 weak and 0 form-only** are not demonstrated. **0 drag-drop-only** is verified from active catalog composition and accessible alternative tests. “Form-only” is not inferred merely because a form exists; it needs task/scene behavior review.

## D. Detailed findings

Evidence abbreviations below resolve to exact paths/tests in the RTM registry. Findings are grouped by root cause so the remediation list does not request duplicate components. Each incomplete RTM row links to these findings or verification gates.

### F01 — Technical inputs do not produce validated practice consequences

Severity: **HIGH**. Status: PARTIALLY IMPLEMENTED / IMPLEMENTED BUT NON-COMPLIANT where a mission explicitly requires invalid-action correction. Phases 1, 3–9.

Locations: `M/lib/screens/simulation/interactions/connection_interaction.dart:179` (_connect), `configuration_panel.dart`, `sequencing_interaction.dart`, `scenario_decision_interaction.dart`, and `runtime/mission_phase_completion_policy.dart` (_isTerminal, _configurationComplete).

What works: controls collect values, emit structured evidence, update state and allow review. Actual behavior from code: connections do not check endpoint suitability; configuration completion checks nonempty values; sequencing checks set membership rather than ordering; any offered decision completes that interaction. The phase policy intentionally proves interaction completion, not competency, which is appropriate as far as assessment authority goes.

What does not work: no separate practice simulation model supplies the required technical failure/status feedback for these inputs. Expected behavior: a wrong network setting/link or unsafe sequence should have an observable technical consequence without exposing the answer or turning Flutter into the official evaluator.

Static reproduction: trace any listed source to any listed destination through _connect; choose nonempty invalid network values; reorder a sequence arbitrarily. The recorded state satisfies the corresponding completion predicates. This is a deterministic source trace, not a claimed device reproduction.

Recommended fix: extend the existing runtime with domain state/constraint responses and negative-action feedback. Keep official scoring in PostgreSQL and preserve the COC2 reference evaluator.
Test needed: actual catalog fixtures, invalid/valid endpoints, address/subnet/gateway combinations, unsafe sequences, alternative decisions, and backend scoring isolation.

### F02 — Controlled placement metadata does not enforce assembly/replacement constraints

Severity: **HIGH**. Status: IMPLEMENTED — DEFECTIVE. Phases 2, 3 M2 and 6 M4.

Locations: `C1:73–149`, `C4:267–358`; `controlled_placement_interaction.dart:68` and `:236`.

What works: select item/destination, accessible confirm, installed visuals, evidence and generic category rejection when valid metadata is supplied. Actual behavior: COC1 M2 destinations lack accepted_categories, so accepted.isEmpty makes compatibility true. Orientation options are defined at phase level while the widget reads selected-item data, so the M2 orientation control is absent. COC4 M4 has item-level orientation in its first placement phase but phase-level orientation in its second; neither validates the selected orientation as technically valid. Sequence UI records order but does not enforce assembly safety.

Expected: incompatible placement/orientation/sequence must not create a valid installed simulation state. Static reproduction: select CPU → drive_bay; the empty category set returns compatible=true. Existing synthetic incompatible-placement tests do not cover this production metadata mismatch.

Recommended fix: correct existing typed presentation contracts and add domain checks, without duplicating the placement widget.
Test needed: all production assembly/replacement item×destination combinations, orientations and sequencing; wrong choices retain recoverable state and technical feedback.

### F03 — COC1 M3 does not implement its PDF installation/configuration scope

Severity: **HIGH**. Status: IMPLEMENTED — NON-COMPLIANT. Phases 3 M3 and 19.

Location: `C1:152`, catalog ID coc1_m3. The actual title is “Connect Power and Data Cables”; phases sequence cable installation, connect sources/destinations, run cable test, interpret, review. This is a meaningful cable workflow but not the specified boot/setup, configuration panel, installation/driver choices, invalid configuration, restart and verification.

Expected: the PDF's M3 installation/configuration experience. Recommended fix: reconcile the mission-ID/content mapping against the authoritative requirements, preserve working cable content where it belongs, and align any published package mapping through controlled review. Do not silently retitle a cable task as installation.

Test needed: M3 route launches the correct scenario and exercises setup → configuration → installation → restart → state-derived verification/interpretation; protected assessment package IDs/rules remain intact.

### F04 — Generic timer completion substitutes for technical test output

Severity: **HIGH**. Status: PARTIALLY IMPLEMENTED. Phases 1, 3–9, 16, 18.

Location: `test_run_interaction.dart:34`, `:184`, `:206`, `:264` (TestRunInteraction, _complete); interpretation/observation widgets; reducer test-status handling.

What works: idle/running/completed lifecycle, reduced-motion progress, timer disposal, structured completion event, optional text interpretation, persistence of lifecycle state. Actual result is generic “Test completed,” with duration/status evidence. It is not computed from cable pinout, link topology, IP configuration, service state, permissions or repairs. Any nonempty interpretation can satisfy its completion gate.

Expected: relevant readings, statuses or test logs derived from learner-created state, including failure and retest differences. Recommended fix: add typed test-result data and reusable result rendering to the existing test system; record inputs/result/interpretation and preserve backend authority.

Test needed: wrong/correct configurations produce different outputs; correction changes retest; canceled/restarted tests do not duplicate completion; restored results match the original accepted result.

### F05 — Troubleshooting reveals facts but M5 diagnostic choices remain shallow

Severity: **MEDIUM**. Status: PARTIALLY IMPLEMENTED. Phases 6 M5 and 9.

Locations: `mission_simulation_definitions.dart:327` (_coc4M5ServiceDiagnostics); `mission_content_data.dart:1308` (getCOC4M5Scenarios); `troubleshooting_branch_interaction.dart:155` (_ServiceCaseCard).

What works: each diagnostic action reveals one new fact, and COC4 M3 interleaves diagnostic and interpretation phases. Actual M5 service cards expose possible-cause lists initially. In each case the first cause is the real fault, while other entries describe healthy conditions; selecting “Diagnose [symptom]” reveals the root observation and repair explanation in one step. These are practice data; no evidence here establishes exposure of the protected assessment evaluator.

Expected: diagnostic tool/action choices should narrow plausible hypotheses and reveal earned information. Recommended fix: gate specific cause findings and separate observation from corrective-action choice. Avoid turning the shared branch engine into one question per symptom.
Test needed: initial UI excludes unearned findings/answer-order cues; distinct diagnostic actions reveal different facts; subsequent available actions depend on findings.

### F06 — Camera position is not connected to serialized runtime camera fields

Severity: **INFORMATIONAL**. Status: optional UX gap, not a proven failure of the PDF's required phase/evidence/configuration/connection restoration.

Location: `simulation_scene.dart:51` local TransformationController; `mission_runtime_models.dart:555` cameraScale/cameraOffset fields and serialization. Actual camera changes stay in the scene controller; runtime fields are not bound to those changes. Equipment state still persists through the existing controller.

Recommendation: if camera restoration is intended, wire the existing fields and test pan/zoom/reopen; otherwise remove the unsupported claim from documentation. This is optional and is not counted as an additional missing mandatory PDF requirement.

### F07 — Several required technical actions are absent or replaced by generic choices

Severity: **HIGH**. Status: PARTIALLY IMPLEMENTED / NOT IMPLEMENTED / specific NON-COMPLIANT rows. Phases 1, 3–7.

Locations: C1–C4 definitions and their resolved shared widgets, particularly C1 M1/M2/M4 and C4 M4/M5.

Working subsets are listed in the individual mission table. Concrete gaps: COC1 M1 classification/abnormality identification; M2 required connections; M4 settings/error correction; COC4 M4 tool selection; COC4 M5 tool use and maintenance/repair operations. M5's maintenance phase contains one “Record the prioritized maintenance action” choice, not manipulation of an affected device/configuration. Several inspection phases only select a labeled object: TapInspectInteraction displays technical detail only when an item has an inspection field, while the catalog fallback supplies description equal to the object label. Such taps are structured evidence but do not prove technical inspection. Similarly, COC3 M4 service controls record a dropdown selection and a status-inspected toggle without operating a modeled service; these rows are partial, not verified service operation.

Expected behavior is each missing atomic action in the RTM, not merely a phase title promising it. Recommended fix: compose the missing tasks using the existing reusable widgets and domain state, then add task-specific feedback strings in mission_content_data.dart. Do not add a duplicate screen or generic confirmation as a substitute.

Test needed: an explicit production-catalog test for every missing RTM action and its evidence/state consequence, plus an end-to-end walkthrough.

### F08 — Scene and premium visual acceptance are not yet evidenced

Severity: **INFORMATIONAL / verification gap**, not a confirmed visual defect. Phases 1, 3 M1, 15, 18–20.

Locations: SimulationScene, catalog scene mapping, AppTheme. The source uses logical positions, real state overlays, shared background art and schematic objects; some scenes have limited object-specific artwork. A schematic is not automatically non-compliant, and absence of unique image assets is not proof of a defect.

Unknown: whether all scenes communicate a complete technical workspace, occupy most useful screen space, remain readable with keyboards/large text, and look polished on Android. No new screenshots or physical inspection were available. Recommended action/test: V01/V03 visual review on compact phone, standard phone, tablet and landscape; collect screenshots and score the PDF categories. Do not redesign before observing the failures.

### F09 — Several displayed mission titles contradict their active scenarios

Severity: **MEDIUM**. Status: IMPLEMENTED — NON-COMPLIANT with coherent task communication; additional repository/UI finding.

Locations: `C1:222`, `C3:148/257`, `C4:80/268`, and mission list/catalog mappings. Examples: COC1 M4 says BIOS/OS while presenting peripherals; COC3 M3 says network settings while presenting accounts/permissions; COC3 M4 says users/groups while presenting services; COC4 M2 says preventive maintenance while presenting hardware diagnosis; M4 says network troubleshooting while presenting replacement.

Expected: list title, briefing, active task, assessment mapping and evidence identity agree. Recommended fix: review and reconcile labels/mapping without altering evaluation rules. Test needed: consistency checks against the official mission map and rendered list/briefing/runtime labels.

### F10 — Feedback text remains partly inline

Severity: **LOW**. Additional repository-rule finding; not a reason to invalidate working behavior.

Locations: connection_interaction.dart, tool_selection_interaction.dart, test_run_interaction.dart and other shared widgets. Many UI/feedback labels are hardcoded despite AGENTS.md requiring mission feedback in mission_content_data.dart. Existing centralized feedback works, but generic and inline strings complicate consistent technical feedback.

Expected/fix: move relevant feedback strings into the existing content system while preserving semantics. Test: regression snapshots/semantics plus a targeted string audit. Do not rewrite the widgets.

### F11 — Toolchain maintenance warnings

Severity: **LOW**. Android Kotlin 2.2.20 compatibility warning, legacy KGP usage including shared_preferences_android, Android SDK XML version skew, 202 informational Dart diagnostics, and deprecated next lint. Current builds pass.

Expected/fix: schedule compatible tooling/plugin updates separately; no dependency upgrades were performed during this audit. Test: required Flutter/web gates and device smoke after the approved upgrade. These warnings are not current application failures.

### V01–V03 — Verification gates, not application defects

| Gate | Status / cause | Required next evidence |
|---|---|---|
| V01 Android runtime/accessibility/restart | BLOCKED: no Android device/emulator. Existing widget tests simulate layout/lifecycle, not Android process death/TalkBack. | All 20 missions: launch, scenario, interactions/negative paths, evidence, save/exit, force-close/relaunch same attempt, review/submit, no crashes/overflow/dead buttons; portrait/landscape, large text, TalkBack, reduced motion, interrupted network. |
| V02 Authenticated deployed integration | BLOCKED for configured harness: dashboard .env.local points to hosted Supabase; service-role test setup key and E2E password absent. No production data/schema was changed. Local rollback SQL passed; current authenticated lifecycle/Realtime scripts were not executed. | Disposable authorized test identities/packages; learner submit → instructor review → finalize → release → learner result; role-denial, duplicate submit, reconnect, progress/analytics checks; capture deployment migration version. |
| V03 Visual/scorecard/showcase acceptance | UNKNOWN pending V01 and technical fixes. Prior provisional scorecard is not runtime evidence. | Evidence-backed ratings for all ten PDF categories for every mission; four functioning showcases with different technical interactions. |

## E. Architecture findings

### Flutter, state management and reuse

The app uses Provider in the wider learner shell and an explicit typed MissionRuntimeController/reducer/state model in simulations. mission_launcher.dart selects active practice definitions and protected assessment routes. MissionSimulationScreen composes simulation_framework.dart, SimulationScene and the reusable interaction families. Legacy templates still exist; their existence does not prove active mission behavior and their validators must not be credited to the typed practice route.

MissionPhaseCompletionPolicy gates completion, not official correctness. That separation is appropriate. The missing layer is a richer simulated equipment/test response, which should extend the current architecture. The golden COC2 cable assessment route must remain protected.

### Evidence and persistence

PracticeMissionEvidenceService writes structured practice_mission_actions to Supabase; assessment evidence goes through AuthoritativeAssessmentService and append_attempt_action. Pending records carry stable client IDs; persistence occurs before transport, acknowledgments are reconciled, retries remain pending, and submission is blocked when evidence is unsynchronized. Unique client-action identity prevents replay duplication. Intentional repeated user actions with new IDs are not automatically a duplicate-evidence defect.

ProgressResumeService stores runtime state with mode/mission/attempt isolation. Controller tests cover reconstruction from server actions, offline snapshots, stale state replacement, duplicate acknowledgments and prior-attempt rejection. MissionSimulationScreen saves on lifecycle pause and explicit exit. These are strong automated findings; app restart on Android and actual network interruption remain V01/V02.

### PostgreSQL authority, security and instructor workflow

Migrations implement start_attempt, append_attempt_action, submit_attempt, trusted evaluation, provisional revisions, instructor finalize_attempt and release_attempt. Dashboard AttemptReviewActions and attempt detail pages consume those operations. Learner result visibility is release-controlled in the inspected model. No local-only score was accepted as authoritative.

RLS/role checks, append-only evidence, SECURITY DEFINER grant restrictions and local rollback tests were inspected. Fresh local tests/lint pass, but not every possible authorization combination has been exercised through the deployed API. This is not a penetration-test certification.

Mobile .env contains only SUPABASE_URL and SUPABASE_ANON_KEY key names; no service/secret/password key name was found there. SupabaseConfig loads the client key; .env is bundled as an asset, so it must remain public-client configuration only. Tracked environment files are examples. The dashboard service-role client is in a server-only module. No secret values are included in this report, and no service-role use was found in mobile source.

Android manifest includes INTERNET/ACCESS_NETWORK_STATE and orientation/font-scale configuration handling. No missing Android permission was identified as a cause of the observed findings.

### Realtime and synchronization

LearnerRealtimeCoordinator and dashboard RealtimeRouteRefresh subscribe/refetch relevant records. Migrations publish lifecycle/progress-related tables. This is meaningful implementation evidence, not proof of deployed websocket behavior. A dashboard build and SQL test cannot establish delivery, reconnection, cross-role filtering or synchronized analytics; V02 remains open.

### Test architecture

There is useful unit/widget/catalog coverage and SQL rollback testing. There is no mobile integration_test directory. Existing tests often verify structure/interaction terminality with synthetic data; green tests therefore coexist with production metadata gaps such as F02. Add production-definition negative cases and cross-system/device tests rather than discarding the existing suite.

## F. UI/UX findings

Confirmed UI problems are task/title mismatches (F09), missing control/task depth (F02/F07), and absent actionable technical result feedback (F01/F04). These affect understanding even if styling is attractive.

Automated accessibility coverage is meaningful: tap-based connection/placement alternatives, semantic actions, 48dp targets, compact layouts at 2x text, and reduced-motion behavior. This does not establish TalkBack focus order or all screen/keyboard combinations.

No new manual overflow, crash, dead-button or excessive-animation defect was reproduced on an Android device. Such checks are blocked, not passed. Source-derived optional camera reset behavior is F06. Professional visual quality and scene dominance remain F08/V03; no unsupported visual redesign is recommended.

## G. Actual test results

Commands were run against the existing working tree. PATH initially lacked flutter and pnpm; the installed Flutter absolute path and npx --no-install pnpm were used successfully. Those initial shell errors are environment issues, not application defects.

| Command / check | Fresh result | Classification and limits |
|---|---|---|
| flutter pub get | PASS | Dependency resolution succeeded; 43 packages have newer versions incompatible with current constraints. No upgrades requested. |
| flutter test | **PASS — 245 tests** | Unit/widget/catalog suite. Does not equal 20 manual mission passes. |
| flutter analyze --no-fatal-infos | **PASS — 202 info issues; no errors/warnings** | Informational debt retained. |
| flutter build apk --debug | **PASS — exit 0** | Final assembleDebug reported 176.7s; “Built build\\app\\outputs\\flutter-apk\\app-debug.apk”. Warnings in F11. |
| Flutter toolchain | Flutter 3.47.4 / Dart 3.13.3 | Android SDK 36; Java 17 available; no Android device/emulator. |
| supabase test db --local | **PASS — Files=7, Tests=10** | Rollback SQL tests against local Supabase. |
| supabase db lint --local --level warning --fail-on error | **PASS — no schema errors** | Local schema, not hosted migration/deployment proof. |
| npx --no-install pnpm exec tsc --noEmit | PASS — exit 0 | Dashboard types. |
| npx --no-install pnpm lint | PASS — no ESLint warnings/errors | next lint deprecation notice only. |
| npx --no-install pnpm build | PASS — exit 0 | Next.js 15.5.24 compiled; 23 static pages generated; dynamic routes built. |
| Authenticated all-mission/cable/Realtime scripts | NOT EXECUTED in current audit | Configured hosted harness lacks server test setup key/password; preflight identified V02. Prior reports are not fresh passes. |
| Android all-mission manual / TalkBack / process-death | BLOCKED | V01. |
| Hosted database migrations and deployment parity | UNKNOWN | No deployment/schema changes or hosted administrative probes performed. |

APK SHA-256: `36546E8349C5BCD029C88579C12C7A32FF137E8E57427DC379B17A36049E8361`. The output is a debug artifact, not a signed release/readiness assertion.

Initial environment failures were command-not-found errors for flutter and pnpm. The pnpm error was: “The term 'pnpm' is not recognized as the name of a cmdlet, function, script file, or operable program.” Both were worked around by locating existing tools. No failed Flutter test, analyzer error or APK compilation error was observed in the completed commands.

Testing levels covered: static inspection, unit/widget, regression suite, local database integration/rollback, and simulated responsive/accessibility/recovery negatives. Full authenticated Flutter→Supabase→PostgreSQL→Realtime integration, device E2E, real network interruption and Android responsive/TalkBack validation remain open.

## H. Final acceptance matrix

| Area | Required | Current | Pass/Fail | Evidence |
|---|---|---|---|---|
| Mission availability | Exact 20 COC1–4 M1–5 | Exact typed catalog/routes | PASS scoped | CAT, T01 |
| Functional Android missions | 20/20 | 0 fully device-verified | BLOCKED | V01 |
| Mission depth | Technical tasks, decisions, stateful results | Meaningful structure but substantial generic operations | FAIL | F01–F07 |
| No drag-only missions | 0 | Multiple families and tap alternatives | PASS | CAT, T01–T03 |
| No weak/form-only missions | 0 | Not established; significant shallow stages | FAIL / UNKNOWN | Scorecard, F04/F07 |
| Structured evidence | Real actions, saved/deduplicated | Implemented and tested, deployed receipt open | PARTIAL | RUN, PERSIST, T02, V02 |
| Pause/restart | Same attempt/phase/evidence/config/links, no premature evaluation | Automated recovery passed; device restart untested | PARTIAL | T02, V01 |
| Review | Steps/count/return/explicit confirm | Implemented; physical polish open | PARTIAL | REVIEW, T02, V01 |
| Backend assessment authority | Trusted evaluator, instructor finalization/release | Static/local checks pass | PASS scoped; deployment UNKNOWN | AUTH, DB, WEB, T04 |
| Realtime | Submit/review/release/progress synchronized | Wired; fresh authenticated end-to-end not run | BLOCKED for acceptance | RT, V02 |
| Accessibility | Alternatives, targets, semantics, text, motion | Component tests pass; TalkBack/device open | PARTIAL | T03, V01 |
| Premium visual/animations | PDF scene/design standards | Tokens/state animations exist; final visual review open | UNKNOWN | F08, V03 |
| Flutter commands | All three pass | All pass | PASS | Section G |
| Showcase readiness | Four rich, distinct technical missions | Four named; scope/depth/verification gaps | FAIL | SCORE, F03/F04/F07 |
| PDF quality scorecard | All 20 meet all ten targets | Targets not demonstrated | FAIL | Scorecard above |

## Final QA verdict and immediate priorities

```text
Total Requirements: 290
Implemented: 119
Partially Implemented: 120
Implemented but Broken: 3
Implemented but Non-Compliant: 7
Not Implemented: 14
Unknown: 7
Blocked: 20

Total Missions: 20
Fully Verified: 0
Partially Verified: 14
Failing (clear mission-specific acceptance failures): 6
Wholly inaccessible to static/automated audit: 0
Manual Android workflow blocked: 20/20 (overlaps the categories above)

Confirmed grouped defects:
Critical: 0
High: 5 (F01, F02, F03, F04, F07)
Medium: 2 (F05, F09)
Low: 2 (F10, F11)
Informational findings: 2 (F06, F08)
Verification gates: 3 (V01–V03; not counted as defects)

Automated Test Status: PASS — 245 Flutter tests; 7 SQL files / 10 tests
Static Analysis Status: PASS — 202 informational Dart issues
APK Build Status: PASS
Runtime Verification Status: Android manual acceptance BLOCKED
Realtime Verification Status: implementation traced; deployed end-to-end UNVERIFIED
Assessment Integrity Status: local/static checks PASS; deployed full chain UNVERIFIED
Persistence Status: recovery/retry tests PASS; Android process-death UNVERIFIED
Accessibility Status: component tests PASS; TalkBack/full device matrix UNVERIFIED
```

Immediate actions are to repair placement constraints, align COC1 M3 with the PDF, implement state-derived technical results/feedback and missing mission operations, then execute the blocked Android and authenticated release/Realtime acceptance gates. Preserve the existing engine, evidence recovery, protected evaluator, review workflow and accessibility alternatives. Already verified requirements are excluded from the remediation list.
