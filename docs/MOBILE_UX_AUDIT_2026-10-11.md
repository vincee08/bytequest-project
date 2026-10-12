# Mobile usability audit and implementation — 2026-10-11

Scope: existing Flutter Android learner app on the user-selected `new` branch.
This is an in-place change to presentation and navigation, using the existing
Material 3 theme, services, scene engine and typed mission runtime.

## Evidence and priorities

The learner could place the preparation equipment but could not identify why
Continue was disabled, needed instructions for component placement, and could
not discover both the cable and sequence tasks in Phase 3. Source inspection
confirmed that Continue, secondary operations and feedback were below several
scrolling sections. The workspace's selected mode did not make its objects'
roles clear. Connected ports retained the same appearance as unused ports.

Inspection covered all **45 screen source files**, the auth wrapper, named
routes, mission launcher, 14 interaction families, shared theme, buttons,
surfaces, navigation, service boundaries and existing test coverage. The table
below distinguishes source inspection from actual runtime verification.
Shared changes apply to screens which consume those components; an unchanged
screen is not being presented as a newly implemented or manually tested screen.

| Priority | Root cause | Implemented response |
|---|---|---|
| 1 | Hidden Continue/final confirmation and unexplained disabled state | Persistent Continue, Review and Confirm evidence area with pending inspection, placement, connection or procedure requirements; existing advance/submission gates retain their meaning |
| 1 | Equipment sources and locations look alike | Source/action captions, drop-location captions, mode icons, selected-source instructions, installed/connected state indicators |
| 1 | Avatar camera badges and underlined policy text imply unavailable actions | Remove decorative camera affordances; provide a real Terms & Privacy route button |
| 1 | Custom buttons have fixed heights and truncate labels | Minimum-height controls with wrapping labels, visible loading labels, disabled styles and duplicate-tap blocking |
| 1 | Practice progress repeats the same policy and hides quiz access behind an icon | Static verified-mission count, a clear next-task message and a labeled Take/resume or Review COC quiz action when existing access permits it |
| 2 | Home pushes a duplicate learning hub | Select the existing Learn destination through a shared navigation scope |
| 2 | Hidden or poorly labeled destinations | Labeled Learning path and Quizzes buttons; explicit Back on standalone Learn and Profile |
| 2 | Tab history and hidden tab semantics | IndexedStack preserves state; system Back revisits the prior main destination; inactive content is excluded by the stack |
| 3 | Sequence arrows, intermediate order and final confirmation are unclear | Numbered steps, visible arrow-button surfaces and explicit reorder/apply instruction |
| 3 | Save failure replaces an entered form | Keep Edit Profile fields mounted, show an inline recovery message and allow a guarded retry |
| 3 | Mission save/submit errors can be below the visible controls | Show a visible error message with a guarded retry; keep the recorded progress and existing sync/submission operations |
| 3 | Retrying a failed phase save can repeat a transition | Flush existing pending evidence using its original action ID before allowing another phase action |
| 4 | Interactive and static cards share treatment | Tappable shared surfaces use a stronger blue outline and visible Material ink feedback; static cards retain quiet borders |
| 5 | Extra text and fixed chrome overflow compact layouts | Large-text missions use one scrollable workspace/task panel and a persistent action area with an explicit Remaining actions dialog |
| 5 | Password controls and inputs lack bound descriptions | Input labels, optional/required markers, visibility-control tooltips and a labeled help search |
| 5 | Completed disabled objects use white text on a muted surface; Back arrows lack spoken labels | Readable disabled foreground, single screen-reader hotspot activation and described Back controls on Settings/auth secondary screens |

## Navigation

The four primary destinations remain Home, Learn, Progress and Rewards.
Home → Learn → Practice reaches the mission list in two taps; opening a mission
is the third tap. Learn → Learning path / Quizzes is one visible action.
Secondary routes keep their current destination and Back behavior. Main-tab
switches preserve widget and form state. Mission exit still saves through the
existing persistence service. Practice discard and restore-reset require an
explicit consequence confirmation.

## Screen-by-screen audit

Paths below are relative to `ByteQuest-Mobile-App/lib/screens/`.
“Shared” means button, surface or state-view improvements apply through reuse.
“Source” means inspected without claiming a new Android/device run.

| Screen file | Finding / disposition | Verification scope |
|---|---|---|
| splash/splash_screen.dart | Startup/session route transitions retained | Source; existing tests |
| auth/auth_wrapper.dart | Trusted account/session gate retained | Source; no auth-rule change |
| onboarding/onboarding_screen.dart | Labeled next/skip controls already exist; shared buttons grow with text | Existing responsive suite |
| onboarding/get_started_screen.dart | Explicit signup/login actions retained; shared button states | Existing responsive suite |
| auth/login_screen.dart | Bound input labels, password tooltip, wrapping account link and brand header | New compact/keyboard/large-text test |
| auth/signup_screen.dart | Real policy link; replace small gesture login link with TextButton; bound labels | New policy navigation/draft-retention and layout tests |
| auth/forgot_password_screen.dart | Bound email label; reset and return actions retained | Source; shared button tests |
| profile_setup/profile_setup_screen.dart | Remove fake upload affordance; label inputs and optional fields | Existing profile setup tests |
| dashboard/main_navigation_screen.dart | Reuse stateful destination shell, tab history and active-page semantics | New navigation/state-retention test |
| dashboard/dashboard_screen.dart | Home's learning action selects existing Learn; Settings becomes labeled | Source; Android navigation smoke |
| missions/missions_screen.dart | Labeled path/quizzes, standalone Back, responsive tabs, loading/recovery access states and non-fixed assignment action | Source; Android navigation/practice smoke |
| missions/class_details_screen.dart | Explicit class identity, resource affordances and Open activity retained | Source; shared surfaces |
| missions/mission_detail_screen.dart | Existing mission briefing/start/back flow retained | Source; shared buttons |
| courses/courses_screen.dart | Existing labeled path, access state and close control retained | Source; existing path tests |
| courses/coc_details_screen.dart | Existing access-gated mission list/back retained | Source; shared buttons |
| progress/progress_screen.dart | Results remain static information; explicit attempt-history action retained | Source; shared states |
| progress/attempt_history_screen.dart | Static timeline, error retry and Back retained | Source; shared surfaces/states |
| achievements/achievements_screen.dart | Static earned results and empty/error states retained | Source; shared states |
| leaderboard/leaderboard_screen.dart | Rewards availability notice has no misleading fake claim/action | Source; no rewards-rule change |
| notifications/notifications_screen.dart | Read/unread action behavior retained; no fake destination added | Source |
| profile/profile_screen.dart | Add visible Back; settings/edit/account actions retained | Source; shared surfaces |
| settings/settings_screen.dart | Existing actions/toggles retained; shared settings rows show ink feedback; labeled Back | Source; Android route smoke (preferences unchanged) |
| settings/edit_profile_screen.dart | Remove fake camera; preserve entered form after failed save; labels and guarded retry | New failure/retry/duplicate-save test using service doubles |
| settings/change_password_screen.dart | Bound labels and described visibility controls; API call retained | Source; shared buttons |
| settings/help_center_screen.dart | Search has a persistent label; nested Material ink and labeled Back | Compact/keyboard/large-text test; Android FAQ expansion |
| settings/terms_privacy_screen.dart | Existing policy route reachable from signup; labeled Back | New route navigation and compact/keyboard/large-text tests |
| resources/resource_viewer_screen.dart | Explicit file-open/retry/back controls retained | Existing resource viewer suite |
| quizzes/learner_quizzes_screen.dart | Existing quiz list/status/open controls retained | Existing quiz suite |
| quizzes/quiz_details_screen.dart | Existing availability/start loading state retained | Existing quiz suite |
| quizzes/quiz_taking_screen.dart | Existing answer-save, previous/next and exit guard retained | Existing quiz suite |
| quizzes/quiz_result_screen.dart | Result and question feedback remain static; retry/back retained | Existing quiz suite |
| quizzes/practice_quiz_screen.dart | Existing question/submit/retry controls retained | Existing practice/quiz suites |
| simulation/mission_simulation_screen.dart | Persistent Continue/Review/Confirm area, phase identity, pending tasks, visible scrolling, guarded retry and destructive confirmation | All-20 work-phase widget flow/layout suite; Android M2 restore/review/exit smoke |
| simulation/simulation_screen.dart | Retained catalog selector; production practice uses MissionLauncher | Source; launcher tests |
| simulation/result_screen.dart | Explicit review/submit/return behavior retained | Source; existing review tests |
| simulation/templates/authoritative_mission_assessment_screen.dart | Protected server contract retained; inherits shared visual controls | Existing authoritative widget tests |
| simulation/templates/coc2_cable_termination_assessment_screen.dart | Protected cable assessment and accessible alternatives retained | Existing contract/accessibility tests |
| simulation/templates/coc1_m2_screen.dart | Retained legacy screen; not the production practice renderer | Source; no mission-rule rewrite |
| simulation/templates/coc1_m2_screen_enhanced.dart | Retained legacy screen; production COC1 M2 uses runtime | Source; shared controls |
| simulation/templates/coc1_m3_screen_enhanced.dart | Retained legacy screen; production COC1 M3 uses runtime | Source; shared controls |
| simulation/templates/identification_mission_screen.dart | Retained legacy screen; inherits shared buttons | Source; legacy tests |
| simulation/templates/identification_mission_screen_enhanced.dart | Retained legacy screen; existing answer/control feedback | Source; legacy tests |
| simulation/templates/drag_drop_mission_screen.dart | Retained legacy drag/tap alternatives | Source; accessibility tests |
| simulation/templates/step_procedure_mission_screen.dart | Retained legacy procedure screen | Source; legacy tests |
| simulation/templates/troubleshooting_mission_screen.dart | Retained legacy screen; production troubleshooting uses richer runtime | Source; legacy tests |
| simulation/templates/configuration_mission_screen.dart | Retained legacy configuration screen | Source; legacy tests |

## Design system

Primary actions use the ByteQuest blue fill; supporting actions use a blue
outline or quiet text treatment. Destructive actions use the darker error red
and consequence confirmation. Buttons have at least 48 dp targets, wrap labels,
show an understandable loading state and block repeat activation while busy.
Shared Material ink surfaces make presses visible. Static content has no
navigation arrow unless a real navigation handler exists.

Reduced-motion support remains in the scene and interaction engines. Normal
mission layouts retain the workspace/control split; large-text layouts allow
both to scroll together without clipping the primary action. No text scaling
is disabled. Light theme is the existing supported theme; this task does not
claim a new dark theme or iOS device certification.

Implementation follows Flutter's official
[accessibility guidance](https://docs.flutter.dev/ui/accessibility) and
[PopScope behavior](https://api.flutter.dev/flutter/widgets/PopScope-class.html).

## Validation and remaining scope

Final validation on 2026-10-12 supersedes the earlier restricted-environment
attempt. The three reported failures are fixed and exercised: an offscreen
power-supply drag remains reachable, sequence assertions distinguish step
numbers from task labels, and nested Help Center expansion ink is visible.

- Flutter dependency resolution PASS.
- Flutter analyzer PASS: **0 errors, 0 warnings, 206 existing infos**.
- Full Flutter suite PASS: **389/389 tests**. Coverage includes all twenty
  mission work orders through real widget controls; every real phase at
  **320x568, 640x360 and 800x360 with doubled text**; offscreen part/cable drags;
  keyed orientation/cancellation; nav/form retention; reset/discard guards;
  profile save recovery; original-action-ID evidence retry; and hotspot
  screen-reader activation/disabled contrast. These are automated widget
  checks, not a claim that all twenty missions were completed on a device.
- Dashboard TypeScript, lint and complete production build PASS. No dashboard,
  API, database or authentication behavior was modified by this UX change.
- Android debug APK build PASS using the existing hosted public practice API.
  Installed with `adb install -r`; the rebuilt file and installed package have
  matching SHA-256:
  `2F378211EE3720D40F5BCA9689AD89982831CE35DBB52FB036C87E246703DCE2`.
  APK: `ByteQuest-Mobile-App/build/app/outputs/flutter-apk/app-debug.apk`.
  Artifacts, client environment files and temporary QA logs stay uncommitted.
- Android API 35 emulator smoke PASS: Home Continue/View all selects the
  existing Learn destination; Progress -> system Back retains Practice; Learning
  path/Quizzes -> Back retains Learn; Settings/Profile routes return correctly;
  the labeled Settings Back action works; Help Center FAQ expands; COC1 M2
  shows the phase title, recorded work and pinned Confirm evidence control.
  No current-process Flutter exception or overflow was logged in these checks.
- APK replacement, force-stop/relaunch and M2 reentry preserve login and the
  user's saved Phase 5 run: **8 placements, 2 connections, 47 accepted evidence
  IDs and 0 pending evidence** before and after. The catalog reports the user's
  existing **1 of 5** COC1 practices verified. No practice action, reset,
  submission, quiz score or completion was generated for this UI smoke test.

The audit covers all screen sources; device validation is limited to the flows
listed above. Full TalkBack use, additional physical devices and independent
first-time-learner testing remain acceptance activities. Light theme is the
existing supported theme; dark mode and iOS were not validated. Existing
analyzer infos and Kotlin/plugin migration notices remain non-blocking.

API payloads, schema, roles, competency evaluation, instructor release and
practice unlock rules retain their existing contracts. No hosted migration or
Vercel API redeployment is required for these Flutter presentation changes.
The `vercel:verification` user-story checks were scoped to existing mobile
navigation and persistence.
