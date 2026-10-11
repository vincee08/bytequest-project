-- Supabase default table grants may survive a narrower GRANT. Revoke them
-- explicitly so learner evidence stays append-only, including for TRUNCATE
-- (which is not constrained by row-level security).
begin;

revoke all privileges on table public.practice_mission_actions
  from public, anon, authenticated;
grant select, insert on table public.practice_mission_actions to authenticated;

revoke all privileges on sequence public.practice_mission_actions_id_seq
  from public, anon, authenticated;
grant usage on sequence public.practice_mission_actions_id_seq to authenticated;

-- Keep the existing server-only evaluator's evidence access intact.
grant all privileges on table public.practice_mission_actions to service_role;
grant all privileges on sequence public.practice_mission_actions_id_seq
  to service_role;

commit;
