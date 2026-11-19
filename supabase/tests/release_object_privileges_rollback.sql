-- The objects created by the re-defense release carry exactly their intended
-- privileges on every database, including one whose default privileges are
-- Supabase's stock ones (the hosted project). Rollback-only.
begin;
select plan(8);

select ok(not exists (
  select 1 from unnest(array[
    'public.curriculum_modules','public.learning_outcomes','public.curriculum_topics','public.curriculum_topic_revisions',
    'public.content_publication_events','public.mission_curriculum_links','public.activity_curriculum_links',
    'public.learner_topic_progress','public.learner_module_unlocks','public.learner_module_completions',
    'public.practice_mission_runs','public.mission_catalog_history']) t(name)
  where has_table_privilege('authenticated', t.name, 'INSERT') or has_table_privilege('authenticated', t.name, 'UPDATE')
     or has_table_privilege('authenticated', t.name, 'DELETE') or has_table_privilege('authenticated', t.name, 'TRUNCATE')),
  'signed-in clients cannot write the server-written release tables');

select ok(not exists (
  select 1 from unnest(array[
    'public.curriculum_modules','public.learning_outcomes','public.curriculum_topics','public.curriculum_topic_revisions',
    'public.content_publication_events','public.mission_curriculum_links','public.activity_curriculum_links',
    'public.learner_topic_progress','public.learner_module_unlocks','public.learner_module_completions',
    'public.practice_mission_runs','public.mission_catalog_history']) t(name)
  where has_table_privilege('anon', t.name, 'SELECT') or has_table_privilege('anon', t.name, 'INSERT')
     or has_table_privilege('anon', t.name, 'UPDATE') or has_table_privilege('anon', t.name, 'DELETE')),
  'anonymous clients have no access to the release tables');

select ok((select bool_and(has_table_privilege('authenticated', t.name, 'SELECT')) from unnest(array[
    'public.curriculum_modules','public.learning_outcomes','public.curriculum_topics','public.curriculum_topic_revisions',
    'public.content_publication_events','public.mission_curriculum_links','public.activity_curriculum_links',
    'public.learner_topic_progress','public.learner_module_unlocks','public.learner_module_completions',
    'public.practice_mission_runs','public.mission_catalog_history']) t(name)),
  'signed-in clients keep RLS-scoped read access');

select ok(not exists (
  select 1 from unnest(array['public.content_publication_events_id_seq','public.mission_catalog_history_id_seq',
    'public.quiz_essay_scores_sequence_seq']) s(name)
  where has_sequence_privilege('anon', s.name, 'USAGE') or has_sequence_privilege('authenticated', s.name, 'USAGE')
     or has_sequence_privilege('anon', s.name, 'SELECT') or has_sequence_privilege('authenticated', s.name, 'SELECT')),
  'clients cannot use the sequences of server-written tables');

select ok(not has_function_privilege('service_role', 'public.sync_mission_catalog_from_contract()', 'EXECUTE'),
  'the catalog sync trigger function is not callable by service_role');
select ok(not has_function_privilege('service_role',
  'public.create_instructor_quiz(text, text, text, uuid, text, text, text, text, uuid, uuid[], uuid[], integer, text)', 'EXECUTE')
  and not has_function_privilege('service_role',
  'public.update_instructor_quiz(uuid, text, text, text, uuid, text, text, text, uuid, uuid[], uuid[], integer, text, text)', 'EXECUTE'),
  'quiz authoring runs as the signed-in instructor, not service_role');
select ok(not has_function_privilege('service_role',
  'public.upsert_quiz_item(uuid, public.quiz_item_type, text, jsonb, jsonb, text, integer, uuid, jsonb, numeric, text, integer, integer)', 'EXECUTE'),
  'quiz item authoring runs as the signed-in instructor, not service_role');
select ok(has_function_privilege('authenticated', 'public.get_learner_rewards()', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.get_learner_rewards()', 'EXECUTE'),
  'learner rewards are read by the signed-in learner');

select * from finish();
rollback;
