# COC1 M3 installation assessment — instructor review draft

Status: **DRAFT, NOT APPROVED, NOT PUBLISHED**. Prepared at the user's request on 2026-09-23. Nothing in this artifact changes an existing activity, assignment, rubric, attempt, evaluation, or release.

The frozen legacy package `coc1-m3-authoritative-v1` remains the cabling/connection assessment. The proposed separate identity is `coc1-m3-installation-pdf-review-v1`. Historical results must retain their original package and rubric references.

## Review artifacts

- `scripts/assessment-drafts/coc1-m3-installation-draft.mjs`: machine-readable proposed stages, server-side criteria, provenance, preservation policy and review gates.
- `installationDraftLearnerPreview()`: answer-free preview using the existing contract schema; explicitly review-only. This is not an authorization to ship the current generic stage UI as a full simulation assessment.
- `installationDraftRubricProposal()`: proposed expected values, intentionally marked pending validation, with no passing percentage or approved scoring assertion.
- `scripts/assessment-drafts/coc1-m3-installation-draft.test.mjs`: identity isolation, PDF hash, answer-leak and review-status checks.

No network client, publishing call, migration, or publisher import was added. The proposed numeric/configuration values are project-simulation conditions, not newly asserted official TESDA rules.

## Requirements and evidence contract

| PDF requirement | Proposed task and evidence | Review concern |
|---|---|---|
| P03-19–22 boot/setup, actions, sequence, configuration | Apply UEFI/AHCI/internal GPT destination; perform boot-media → select-disk → copy-files → configure-device operations | Confirm hardware scenario, non-destructive destination selection and accepted sequence |
| P03-23 driver selection | Apply the matching Ethernet driver | Confirm simulated adapter identity and valid alternatives |
| P03-24 incorrect configuration | Incompatible firmware/storage/driver produces a non-operational state; correction requires another verification | Trusted backend must derive this state; a submitted client success flag is not proof |
| P03-25 restart/verification | Record restart followed by boot and adapter measurements | Require a restart after the latest driver update and reject stale verification |
| P03-26 interpretation | Attach interpretation and measured outputs to review | A selected “verified ready” statement alone must never prove readiness |
| P19-01 showcase | Reuse the typed 2D installation workspace and its controls | Do not replace equipment operation with a disconnected questionnaire |

## Instructor decisions required

1. Validate the technical work order, source mapping, expected values, sequence, and acceptable alternative evidence. The project PDF alone does not approve a TESDA rubric.
2. Review the five criterion proposals and decide whether any require human judgment. Approvals remain unset.
3. Approve a trusted-state evaluation adapter before deployment. Existing generic value/sequence rules are proposed encodings only: they do not independently verify the client simulation's measured results or cross-stage freshness.
4. Verify typed-runtime authoritative transport against the proposed evidence contract. Practice evidence must not be retroactively promoted into assessment evidence.
5. Run isolated lifecycle, tampering, missing evidence, sequence, duplicate, offline/restart, RLS and release tests before asking for publication approval.
6. On separate publication authorization, create a distinct version and new assignments; preserve existing package/history. Only an authenticated instructor may finalize and release results.

Validation command: `node --test scripts/assessment-drafts/coc1-m3-installation-draft.test.mjs`.
