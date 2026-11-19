-- Slice A6: leaderboard entries change only through their refresh triggers.
--
-- A learner's own opt-in toggle on public.profiles runs the refresh trigger as
-- that learner, which is why the entry keeps one column-level UPDATE grant.
-- This policy limits that update to trigger context, so a direct client
-- request changes no row. Every value was already re-derived from profiles and
-- learner_point_events on each write; this removes the client write path
-- itself. Additive; no new SECURITY DEFINER function.

begin;

alter policy gamification_leaderboard_entries_refresh_own on public.gamification_leaderboard_entries
  using (learner_id = (select auth.uid()) and pg_catalog.pg_trigger_depth() > 0)
  with check (learner_id = (select auth.uid()) and pg_catalog.pg_trigger_depth() > 0);

comment on policy gamification_leaderboard_entries_refresh_own on public.gamification_leaderboard_entries is
  'Only the profiles refresh trigger (trigger depth > 0) may update the caller''s own entry; direct client updates match no row.';

commit;
