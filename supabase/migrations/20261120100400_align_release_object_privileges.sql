-- Re-defense release, pre-production rehearsal fix (2026-11-20).
--
-- The hosted project's migration history diverged from this repository: its
-- default privileges for objects that role postgres creates in schema public
-- are still Supabase's stock ones (anon and authenticated receive SELECT,
-- INSERT, UPDATE and DELETE on new tables and SELECT/USAGE on new sequences;
-- service_role receives EXECUTE on new functions). The repository history had
-- hardened those defaults, and several re-defense migrations relied on that
-- instead of revoking explicitly. The restored-production rehearsal showed the
-- difference: these objects came out with broader client privileges than the
-- same migrations produce locally (RLS still blocked the writes, but the
-- intended least-privilege grants were not in place).
--
-- This migration sets exactly the intended privileges on the objects created by
-- the release. It changes no data, and it is a no-op on a database where the
-- objects already have their intended privileges (for example a local stack).
begin;

-- Tables: clients read through RLS-scoped SELECT only; every write is server-side.
revoke all on table
  public.curriculum_modules,
  public.learning_outcomes,
  public.curriculum_topics,
  public.curriculum_topic_revisions,
  public.content_publication_events,
  public.mission_curriculum_links,
  public.activity_curriculum_links,
  public.learner_topic_progress,
  public.learner_module_unlocks,
  public.learner_module_completions,
  public.practice_mission_runs,
  public.mission_catalog_history
from anon, authenticated;

grant select on table
  public.curriculum_modules,
  public.learning_outcomes,
  public.curriculum_topics,
  public.curriculum_topic_revisions,
  public.content_publication_events,
  public.mission_curriculum_links,
  public.activity_curriculum_links,
  public.learner_topic_progress,
  public.learner_module_unlocks,
  public.learner_module_completions,
  public.practice_mission_runs,
  public.mission_catalog_history
to authenticated;

-- Sequences of server-written tables: no client SELECT/USAGE.
revoke select, usage on sequence
  public.content_publication_events_id_seq,
  public.mission_catalog_history_id_seq,
  public.quiz_essay_scores_sequence_seq
from anon, authenticated;

-- Functions the release intends for signed-in users or triggers only.
revoke execute on function public.sync_mission_catalog_from_contract() from service_role;
revoke execute on function public.create_instructor_quiz(text, text, text, uuid, text, text, text, text, uuid, uuid[], uuid[], integer, text) from service_role;
revoke execute on function public.update_instructor_quiz(uuid, text, text, text, uuid, text, text, text, uuid, uuid[], uuid[], integer, text, text) from service_role;
revoke execute on function public.upsert_quiz_item(uuid, public.quiz_item_type, text, jsonb, jsonb, text, integer, uuid, jsonb, numeric, text, integer, integer) from service_role;
revoke execute on function public.get_learner_rewards() from service_role;

notify pgrst, 'reload schema';

commit;
