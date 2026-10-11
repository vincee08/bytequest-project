# Hosted practice activation — 2026-10-11

The authorized rollout is complete on branch `new`: hosted Supabase has the
practice schema and twenty mission contracts, the production Vercel practice API
is deployed, and the rebuilt Android app is installed with existing data retained.
The earlier missing-RPC and missing-endpoint blockers are resolved.

## Hosted Supabase

Project: `rslmteqipxqfifwftugk` (`ByteQuest`, Tokyo). Hosted migration history
differs from the repository, so only the required practice prerequisite, the two
reviewed feature migrations, and a forward permissions fix were applied.
Foundation migrations and existing history were not replayed or repaired.

| Repository migration | Hosted recorded version |
|---|---|
| `20260822124500_practice_mission_evidence.sql` | `20261011035806` |
| `20261009090000_coc_practice_progression.sql` | `20261011035837` |
| `20261009091000_css_practice_contracts.sql` | `20261011035915` |
| `20261011040839_harden_practice_evidence_grants.sql` | `20261011040956` |

The migration API records its own application timestamps. The new forward
migration explicitly removes inherited UPDATE, DELETE and TRUNCATE privileges
from learner evidence. Learners retain SELECT/INSERT and sequence USAGE; existing
server evaluation access remains intact. RLS stays enabled.

Verified twenty `css-sag-20261009-v1` contracts, practice-table RLS, answer-key
privacy, append-only grants and service-only SECURITY INVOKER evaluators. No new
SECURITY DEFINER function was added. The learner projection returns four COCs:
COC1 available, COC2–COC4 locked pending completion.

A private pre-change schema/access snapshot is saved in ignored
`.tmp/hosted-practice-before-20261011.json`. It is not a full database backup.
No credential or private snapshot is committed.

## Production Vercel API

- Project: `bytequest` / `prj_vUXjALnNCLQWzzdScvwXMfYvppga`.
- Team: `team_9kWTkm9JMxTpNKitR90fUDiV` (`vincee08s-projects`).
- Root Directory: `ByteQuest-Web-Dashboard`; framework: Next.js.
- Production URL: <https://bytequest-alpha.vercel.app>.
- Practice endpoint: `/api/learner/practice`.
- Deployment: `dpl_5rWf1YtWUC7DDVsy9stu9UZ6bY7a`, **READY**, production.
- Exact build URL: <https://bytequest-myu9x8bgq-vincee08s-projects.vercel.app>.
- Application source: `ccb3aef4d8e70c27e934a66f12d38fa40df38216`, branch `new`;
  includes feature commit `64dcbac`. Remote build duration: 114.061 seconds.

The connected Vercel plugin actor lacked access to this existing team. The
authenticated Vercel CLI was used for the same verified team/project. A clean
226-file tracked dashboard source snapshot excluded local secrets and unrelated
user files. Protected staged production checks passed before promotion; the
production alias was then independently checked against this deployment ID.

Staged and public production checks pass: anonymous GET 401, authenticated learner
GET without an attempt 400, incomplete COC1 verification 422, locked COC2
verification 403, and quiz access before five verified missions 403. These are
expected validation responses. No completion was fabricated. An error-level log
scan over the preceding twenty minutes returned no entries. No drains are
configured; the returned project configuration did not show enabled observability,
analytics or speed insights.

Supabase and AI credentials remain server-only. Production has the existing
OpenRouter credential as a Secret and
`PRACTICE_OPENROUTER_MODEL=openrouter/free`. A live provider probe returned five
grounded fallback-bank questions. Successful live AI generation is not claimed;
provider failures and quotas use the bank without blocking the quiz.

## Rebuilt Android app

The ignored mobile `.env` sets
`PRACTICE_API_URL=https://bytequest-alpha.vercel.app/api/learner/practice`.
The rebuilt APK's embedded asset was checked for this endpoint and the correct
hosted Supabase URL without printing keys. Installed with `adb install -r` on
`emulator-5554` / `ByteQuest_QA_API35`, retaining the existing learner session.

The learner account `buladaco.johnvincent@dnsc.edu.ph` can open Learn → Practice
and the COC1 hardware inspection workspace. Tapping the motherboard saved an
authenticated `object_inspected` action for `coc1_m1_p1` to hosted
`practice_mission_actions`. No mission or COC completion was awarded by this check.
After backgrounding and force-stopping the app, reopening the mission restored
the selected motherboard and phase 1. Hosted evidence remained exactly one row,
with zero mission/COC completions. The app is left open for the learner.

APK: `ByteQuest-Mobile-App/build/app/outputs/flutter-apk/app-debug.apk` (ignored).
SHA-256: `61B1B197E4592E7F2622AF5F8B9B4D750FCA119EE4338B7777C806421E826216`.

## Fresh validation and acceptance limits

- Mobile dependency resolution, analyzer (0 errors / 0 warnings / 212 existing
  infos), all **338 Flutter tests**, and Android debug APK build pass.
- Dashboard TypeScript, lint and production build (24 generated pages) pass;
  practice/provider tests pass **13/13**.
- Local database rollback suite passes **8 files / 18 assertions**, including
  the foundation lifecycle and the append-only grant regression check.
- All **20 raw mission replays**, four sequential COCs, quiz resume/failure,
  grading, idempotency, RLS and tampering checks pass in a rollback transaction.
- Hosted API, progression/security and Android workspace evidence checks pass.

Five verified missions and a server-graded quiz are required for each COC; the
supplementary learning threshold is 80%. Full hosted mission/quiz completion
requires real learner work. Independent TalkBack/device-matrix acceptance and
successful live AI generation remain separate checks. Official assessment results
still require authenticated instructor release.

See `CSS_NC_II_PRACTICE_IMPLEMENTATION_2026-10-09.md` for the evidence contract
and original acceptance details. Earlier session access failures are superseded.
