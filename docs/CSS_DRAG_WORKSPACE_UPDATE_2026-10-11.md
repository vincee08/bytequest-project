# CSS NC II practice canvas update — 2026-10-11

Continued the user's authorized work on branch `new`. Re-scanned all seven pages
of `Computer-Systems-Servicing-NC-II_copy.pdf`, the TESDA Self-Assessment Guide
ELCCSS 213-0119, revision 00, 03/01/17. Source SHA-256:
`3a2401a7a28c427128a0be35587b10c22bcd736aa349ee68e8feba46ea688bbf`.
The original competency mapping remains in
`CSS_NC_II_PRACTICE_IMPLEMENTATION_2026-10-09.md`.

## Learner practice behavior

All fifteen COC1–COC3 work orders now start with required equipment deployment.
The primary canvas has **Place equipment**, **Connect ports** when applicable,
and **Inspect** modes. Learners drag equipment from the inventory to work locations
and drag source ports to destinations to make compatible links. Installed
components and links render from saved mission state. Selecting an item and then
tapping its destination provides the same accessible action path. Keyed assembly
parts require an explicit orientation choice; incompatible placements are recorded
and give the existing technical feedback without installing a component.

| PDF source | Practice canvas and retained technical work |
|---|---|
| COC1, pages 1–2: install/configure computer systems | Inspection stations; grounded assembly bench; motherboard/CPU/RAM/storage/power placement and internal cables; OS workstation and boot media; peripherals and interface links; monitored system/storage tests. Preparation, inspection, BIOS/OS/drivers/licensed software, configuration, measured tests and close-out remain required. |
| COC2, pages 3–4: set up computer networks | Cable/connector/tester workbench; switch/router placement and cable links; switched-star device deployment; router/switch/repeater positions; client/network verification. Protected routes/raceway, termination order, addressing, Wi-Fi/WAN/firewall, diagnosis and connectivity checks remain required. |
| COC3, page 5: set up computer servers | Server/client/switch deployment and Ethernet links; NOS installation rack; protected user-folder server and access-test client; file/printer service positions; access verification. Accounts/groups/permissions, modules/updates, services, sharing, restarts and security tests remain required. |
| COC4, pages 6–7: maintain/repair systems and networks | No draggable placement, connections or sequencing controls. Retains service-order preparation, taps/tool selection, progressive diagnosis, contingent repair/reconfiguration, retesting and documentation. |

Every practice uses inspection, configuration, decisions or tests in addition to
equipment placement. `EquipmentWorkspace` composes the existing `SimulationScene`
engine, including zoom, pan, object access and connection painting. Separate
canvas IDs distinguish source and destination roles for the same network device;
raw evidence retains the original contract IDs. Existing mission controls and
`progress_resume_service.dart` remain the action and persistence path.

This is a constrained Packet Tracer-style virtual workspace. Arbitrary IOS
commands, physical installations and an official certification scoring rubric
are outside this change. The PDF supplies competency activities, not a numeric
practice passing threshold.

## Hosted practice contracts

Created the new forward migration with the Supabase CLI, then generated and
reviewed its fifteen definitions. Repository migration
`20261011043723_css_drag_workspace_contracts.sql` was applied to project
`rslmteqipxqfifwftugk`; hosted history records version `20261011044331`.

- Fifteen COC1–COC3 contracts use `css-sag-20261011-v2` and require first-phase
  placement evidence. The five COC4 contracts retain `css-sag-20261009-v1`.
- No table, function, grant, RLS policy or official assessment contract changed.
  Hosted checks confirm evidence RLS/append-only access, private quiz keys and
  denial of client evaluation calls.
- The deployed Vercel API reads the current Supabase contracts. No dashboard
  application change or additional API deployment is required for this update.
- Existing evidence and historical completions are preserved. A new COC quiz
  requires mission verification against the current contract version; learners
  with earlier mission completions may need to verify the updated work orders.
  Previously completed COCs retain their existing progression records.
- The ignored pre-change audit `.tmp/hosted-workspace-before-20261011.json`
  records contract versions and hosted migration history. It is not a full backup.

Local rollback tests pass **8 files / 19 assertions**, including the foundation
lifecycle. All **20 raw mission replays**, sequential COC quizzes, saved answers,
failure locks, idempotency, RLS and tampering checks pass. An added rollback check
removes all COC1 M1 placements and confirms that backend verification rejects
the otherwise completed work order.

## Rebuilt app and device evidence

Rebuilt the Android debug APK and installed it with `adb install -r` on the
visible `emulator-5554` / `ByteQuest_QA_API35`, retaining the learner's login and
app data. The final APK embeds the hosted Supabase URL and public production
practice endpoint; configuration was checked without exposing keys.

APK: `ByteQuest-Mobile-App/build/app/outputs/flutter-apk/app-debug.apk` (ignored).
SHA-256: `C972A9091954D3D87FF5A88C2249AFAD49D264034A3175E39519457B31ACF923`.

A real Android drag in COC1 M1 placed the motherboard on the ESD inspection mat.
Hosted Supabase recorded one accepted `placement_attempted` action with
`input_method=drag`. Backgrounding, force-stopping, relaunching and reentering the
mission restored the installed component and phase 1. Evidence remained exactly
one drag-placement record / five total records, including earlier discarded
activity. Mission and COC completions remained zero.

Focused workspace tests pass **23/23**, covering all fifteen first-phase drag
gestures, incompatible drops, restored placements, tap alternatives, keyed-part
orientation, cable drawing and overlapping switch source/destination roles.
Final mobile gates pass: dependency resolution, analyzer **0 errors / 0 warnings /
212 existing infos**, **361/361 Flutter tests** and Android debug APK build. The
suite includes all twenty work orders through actual touch controls and every
phase at 320dp portrait, 640dp/800dp landscape and 2x text. The mode selector
scrolls horizontally to preserve canvas space at large text sizes. Existing
Kotlin plugin migration notices remain non-blocking.

Dashboard TypeScript, lint and production build pass. The public practice API
returns the expected anonymous JSON 401. All twenty local/hosted definition
digests match, and a fresh temporary contract export matches the applied
migration byte-for-byte. The final installed APK again restored the motherboard
with no extra evidence records.

Full hosted learner mission/quiz completion, independent TalkBack/device-matrix
acceptance and successful live AI generation remain separate checks. Official
results continue to require authenticated instructor release.
