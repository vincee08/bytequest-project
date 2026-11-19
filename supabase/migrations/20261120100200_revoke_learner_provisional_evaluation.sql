-- Final fix wave (final review SQL-A I2): learners can no longer run
-- public.evaluate_submitted_attempt and read their unreleased provisional
-- result.
--
-- The definer (20260808112000) admits the owning learner and returns the
-- automated_provisional score revision, including outcome, percentage and
-- per-criterion observed evidence, while score_revisions and criterion_results
-- stay hidden from the learner by RLS until release. That bypassed
-- Evaluate -> Finalize -> Release for every technical assessment.
--
-- Callers (checked 2026-11-19): public.submit_attempt only (SECURITY DEFINER,
-- owned by postgres, so its call keeps working), the service role, and two
-- rollback suites. Neither the Flutter app, the dashboard nor any script calls
-- it; database.generated.ts only lists it. This changes a privilege only: the
-- body, owner and SECURITY DEFINER are unchanged, and service_role keeps
-- EXECUTE.
begin;
set local lock_timeout = '5s';

revoke execute on function public.evaluate_submitted_attempt(uuid) from public, anon, authenticated;
grant execute on function public.evaluate_submitted_attempt(uuid) to service_role;

notify pgrst, 'reload schema';
commit;
