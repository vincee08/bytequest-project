# Technical Workspace implementation and verification — 12 November 2026

Scope: the existing Flutter mobile UI on `vince-branch`, across all 20 production
practice routes. The Supabase schema, published mission definitions, evidence
payloads, reducers, completion policies, services, authentication, scoring,
instructor release, and dashboard product source are unchanged.

Final source validation: **PASS — 449/449 Flutter tests**, including all 20 touch
work orders and all 115 phases. Analyzer: **0 errors, 0 warnings, 217 existing
informational notices**. Final APK attestation is recorded below.

## What changed

| Component | Change |
|---|---|
| `mission_workspace_layout.dart` (new) | Constraint-based workspace allocation, expandable task panel, independent landscape sidebar. |
| `mission_simulation_screen.dart` | Shared layout for all 20 routes; full guide sheet; scenario/help disclosure; task controls before phase-revision navigation; retained canvas and form subtrees during resizing and rotation. |
| `mission_guidance_panel.dart` | One current-step row with independent guide, location highlight, and tutorial actions. |
| `mission_task_status.dart` | Compact action count/status disclosure beside the pinned Continue/Review/Confirm button. Large text preserves the status disclosure without squeezing the primary label. |
| `equipment_workspace.dart` | One source and destination per row; scrollable mode strip; feedback outside the canvas, expiring after five seconds; consistent compact toolbar. |
| `simulation_scene.dart` | Larger minimum object dimensions, text-scaled height, reduced toolbar padding. The existing resolved rectangles still drive hotspots, drop targets, and connection endpoints. |
| `tool_tray.dart` | Tools wrap within the panel width with 8 dp gaps and 48 dp minimum buttons, using the task panel's vertical scrolling. |
| `practice_coc_session_panel.dart` | Optional compact timer presentation in missions; timer policy and deadline behavior unchanged. |
| `mission_content_data.dart` | Shared copy for the guide, panel controls, camera controls, and feedback disclosure. |

Read `simulation_framework.dart`, the launcher, existing templates, typed models,
and interaction components before implementation. The protected COC2 cable
assessment adapter and official assessment contracts remain intact.

## Reproduced causes

- Header, 48 dp timer, multi-row guidance, workspace modes, camera toolbar, and a
  two-row action footer consumed most of a short phone's height.
- The scene received only 56% of what remained. At 320×568 with system insets,
  several timed equipment workspaces had zero available canvas height and
  RenderFlex overflow. This was reproduced, not inferred from source alone.
- Four placement columns reduced a source to approximately 72 dp wide on a
  360 dp phone. Technical names and artwork competed for those small rectangles.
- Scenario, help, duplicated directions, and revision navigation preceded the
  actual tools. A persistent positioned feedback banner covered scene targets.

## Layout behavior

Portrait uses nearly the full safe width. The default scene receives about three
quarters of the working area, with a task preview and an explicit expansion
control. Short phones reserve less preview space so a complete 112 dp object
can fit in the default canvas. Expanding controls gives forms and tools more
room; expanding the workspace restores the primary equipment view.

Landscape uses a sidebar from 520 dp of actual safe width. Mission identity,
timer, guidance, and tools share its scroll area; the action remains pinned.
This prevents the header from consuming the short equipment viewport. No
orientation is forced. Large-text portrait uses a scrollable scene and task
flow with the primary action retained in the safe area.

The full guide is an explicit, scrollable sheet with a persistent 48 dp Close
control, safe-area handling, scenario, phase objective, all current-phase steps,
recorded progress, and the existing practice help. It changes no evidence.
Location highlights continue to point to real controls. Feedback no longer
occupies a positioned layer above objects; its full technical reason remains
available in the task panel after the brief canvas-adjacent notice expires.

Placement/connection scenes use two wide columns and additional vertical rows.
Object IDs, socket/interface compatibility, orientation prompts, tap alternatives,
and evidence actions remain the same. Camera transforms, auto-scrolling drags,
hit-testing, and line painting all use the existing shared scene mapping.

## Measurements

Measured from rendered widgets with the same Material theme, loaded Roboto
glyphs, 24 dp top/bottom system insets, active COC timer, normal text, initial
phase, and unexpanded task panel. Canvas means the interactive scene viewport;
it excludes the mode strip and camera toolbar. Values are dp, rounded to one
decimal. A zero below describes the reproduced broken baseline, not a usable
old viewport. Portrait width was already almost edge-to-edge.

| Phone / mission | Before canvas | After canvas |
|---|---:|---:|
| 320×568 / COC1 M2 | 318×0 (overflow) | 318×125 |
| 360×800 / COC1 M1 | 358×156.3 | 358×367.8 |
| 360×800 / COC1 M2 | 358×92.5 | 358×311.8 |
| 360×800 / COC2 M3 | 358×100.3 | 358×311.8 |
| 360×800 / COC3 M4 | 358×100.3 | 358×311.8 |
| 360×800 / COC4 M5 | 358×148.5 | 358×367.8 |
| 412×915 / COC1 M2 | 410×164.7 | 410×399.2 |
| 640×360 / COC1 M2 | 381.4×14 | 357×202 |

At 568×320 the updated COC1 M2 canvas is 317×162 dp. There is no
font-matched baseline measurement for that additional profile.

At 360 dp, a placement source grows from about **71.6×72 dp to 150.4×112 dp**.
Dense scenes scroll rather than reducing every object to fit at once. The
landscape sidebar deliberately reserves readable control width; its benefit is
usable canvas area, not a claim of greater width on every profile.

Raw measurements, before/after PNGs, showcase phases, and four COC galleries
are in ignored `build/workspace-qa/`. The readable captures use Flutter's bundled
Roboto and Material Icons fonts, not screenshots from a physical Android phone.

## 20-mission coverage matrix

`P1` means the initial timed practice screen was rendered and visually inspected
at 360×800. `All phases` and `Touch work order` refer to automated widget/runtime
regressions with synthetic evidence transports, not hosted learner completions.
PASS refers to the final source validation reported above.

| Mission | Shared UI | All phases | Touch work order | P1 visual | Physical phone |
|---|---|---|---|---|---|
| COC1 M1 | Updated | PASS | PASS | Reviewed | Pending |
| COC1 M2 | Updated | PASS | PASS | Reviewed | Pending |
| COC1 M3 | Updated | PASS | PASS | Reviewed | Pending |
| COC1 M4 | Updated | PASS | PASS | Reviewed | Pending |
| COC1 M5 | Updated | PASS | PASS | Reviewed | Pending |
| COC2 M1 | Updated | PASS | PASS | Reviewed | Pending |
| COC2 M2 | Updated | PASS | PASS | Reviewed | Pending |
| COC2 M3 | Updated | PASS | PASS | Reviewed | Pending |
| COC2 M4 | Updated | PASS | PASS | Reviewed | Pending |
| COC2 M5 | Updated | PASS | PASS | Reviewed | Pending |
| COC3 M1 | Updated | PASS | PASS | Reviewed | Pending |
| COC3 M2 | Updated | PASS | PASS | Reviewed | Pending |
| COC3 M3 | Updated | PASS | PASS | Reviewed | Pending |
| COC3 M4 | Updated | PASS | PASS | Reviewed | Pending |
| COC3 M5 | Updated | PASS | PASS | Reviewed | Pending |
| COC4 M1 | Updated | PASS | PASS | Reviewed | Pending |
| COC4 M2 | Updated | PASS | PASS | Reviewed | Pending |
| COC4 M3 | Updated | PASS | PASS | Reviewed | Pending |
| COC4 M4 | Updated | PASS | PASS | Reviewed | Pending |
| COC4 M5 | Updated | PASS | PASS | Reviewed | Pending |

## Validation evidence

- New timed/safe-area layout matrix: all 20 missions at 320×568, 360×800,
  412×915, 568×320, and 640×360; minimum targets and safe primary actions.
- New doubled-text/cutout/guide matrix: all 20 at 320×568, 568×320, and 640×360;
  guide scrolling and Close controls stay reachable.
- Existing all-phase matrix: all **115 phases** at 320×568, 640×360, and
  800×360 with doubled text. Existing object-overlap and reduced-motion checks
  exercise the common scene engine separately.
- Focused draft/camera checks: panel expansion, portrait/landscape rotation,
  guide opening/closing, unchanged phase/evidence, and keyboard safe action.
- Real gesture regressions: all six assembly parts, cable connections, tap
  alternatives, explicit orientation, transformed zoom/pan drops, offscreen
  auto-scrolling, rejected placement, and a drop after workspace resizing.
- Feedback regression: notice is outside the canvas, expires after five
  seconds, preserves targets, and creates no evidence by itself.
- All 20 complete touch-control work orders use the existing production
  phase policies and structured actions. Pause/resume, retry/idempotency,
  submission review and authoritative-service contract tests remain included.
- Flutter dependency resolution passed. Analyzer passed with 0 errors, 0
  warnings, and 217 existing informational notices. Full suite passed
  **449/449**. The 12 focused layout tests also passed with real-font captures.
  No post-fix RenderFlex overflow or missed-pointer warning occurred in the
  final full run.
- Dashboard TypeScript, lint, and production build passed through the existing
  Corepack/pnpm toolchain. No dashboard product source was changed.

The primary design guide was installed UI/UX Pro Max: content priority,
progressive disclosure, 48 dp Android targets, 8 dp spacing, safe areas, large
text, gesture alternatives, and Flutter constraint-based composition. Its
bundled Flutter rules and official Flutter documentation were consulted:
[SafeArea and MediaQuery](https://docs.flutter.dev/ui/adaptive-responsive/safearea-mediaquery),
[InteractiveViewer](https://api.flutter.dev/flutter/widgets/InteractiveViewer-class.html),
and [modal sheets](https://api.flutter.dev/flutter/material/showModalBottomSheet.html).
Standalone Flutter/Dart and Superpowers skill files were not found in the
available skill locations. Python's CLI was unavailable, so the installed
skill's reference material was used without installing software.

## APK and phone acceptance

Output: `build/app/outputs/flutter-apk/ByteQuest-workspace-hosted-20261112-debug.apk`.

- Debug APK build passed; **211,997,300 bytes**.
- SHA-256: `F005C4668B92CE51F38B2600FA43E52D53100435CD3B5318F0B0CCF825B40492`.
- Package `com.example.bytequest`, version `1.0` (`1`). Signature verifies and
  matches the preceding hosted-testing APK's Android Debug certificate:
  `a4d01056c847034cf2fdc199d4a5dbfa203af5e716d715f560f6db9755bd1d37`.
- Compiled debug kernel contains the new workspace class/guide copy, the exact
  configured hosted Supabase URL and matching publishable key, and
  `https://bytequest-alpha.vercel.app/api/learner/practice`. No local Supabase
  override was found. Key values are omitted from this report and Git.
- Configuration was supplied by the existing ignored hosted BQ define file;
  environment files and hosted configuration were not rewritten.
- APK attestation: ignored `build/workspace-qa/apk-attestation.json`.
- Existing Kotlin/plugin migration and SDK XML compatibility notices remain
  non-blocking. Dependencies and platform configuration were not upgraded.

`adb devices -l` returned no Android device. No emulator was started, no app was
installed/uninstalled, and no application data was cleared. Physical Android,
TalkBack, touch latency, real drag performance, and hosted end-to-end writes
after this UI change remain pending owner testing.

For the owner's phone testing, update the existing application in place with
the APK above and retain the current hosted learner/session and saved missions.
Do not uninstall or reset progress. Use Learn → Practice → the relevant COC and
mission. If that mission is already in progress, resume it normally.

1. COC1 M1, Inspect hardware: read the images/labels, scroll to the final object,
   tap targets, and open/close the full guide and Objects list.
2. COC1 M2, Place components (phase 2): expand the workspace, drag/tap a component
   into its intended socket, use the existing alignment dialog, then confirm
   that the photo/status appears at the actual destination. Check a lower row
   with scrolling. Saved progress must survive leaving and reopening.
3. COC2 M3, Connect topology (phase 2): select source/destination and check line
   endpoints; repeat with a drag and zoom/Fit. No tool panel should cover ports.
4. COC3 M4, Configure service (phase 2): expand controls, edit a draft, collapse
   and expand the panel, rotate if supported, and open the guide. The draft
   should remain. Apply configuration through the existing action when ready.
5. COC4 M5, Inspect request and system (phase 1): expand controls, inspect
   progressive feedback and diagnostic choices, then continue the existing work
   order, Test and interpret (phase 4), and review flow.
6. Repeat entry/control checks for all 20 rows above at normal and larger
   Android font settings, with system navigation visible. Check the smallest
   phone and landscape if available. Review/Confirm must remain reachable.

Existing generic schematic/icons in some server/repair scenes were enlarged,
not replaced with new artwork. Long scene labels remain fully available through
the Objects list, tooltips, and semantics. The automated and screenshot checks
do not certify every phase as visually inspected or physically accepted.
