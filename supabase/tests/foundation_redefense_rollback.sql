-- Re-defense foundation: evaluator secrecy, official curriculum seed, shared
-- progression tables and canonical catalog. Rollback-only.
begin;
select plan(25);

-- WS0 security: learners can no longer read evaluator rules.
select ok(not has_column_privilege('authenticated', 'public.activity_versions', 'evaluator_config', 'SELECT'),
  'authenticated users cannot read activity evaluator_config');
select ok(has_column_privilege('authenticated', 'public.activity_versions', 'learner_payload', 'SELECT'),
  'learner payload remains readable for assignment hydration');
select ok(has_column_privilege('authenticated', 'public.activity_versions', 'created_by', 'SELECT'),
  'created_by stays readable for rubric RLS policy evaluation');

-- Official curriculum seed.
select is((select count(*)::integer from public.curriculum_modules), 16, 'sixteen official curriculum modules');
select is((select string_agg(coc_code || ':' || n, ',' order by coc_code) from (
  select coc_code, count(*) n from public.curriculum_modules group by coc_code) s),
  'coc1:4,coc2:4,coc3:3,coc4:5', 'module counts per COC follow the TR curriculum');
select is((select title from public.curriculum_modules where coc_code = 'coc1' and code = 'LO1.1'),
  'Assemble computer hardware', 'LO1.1 title is verbatim');
select is((select o.statement from public.learning_outcomes o join public.curriculum_modules m on m.id = o.module_id
  where m.coc_code = 'coc1' and o.code = '1.4'),
  'Computer hardware is assembled in accordance with established procedures and systems requirements',
  'PC 1.4 statement is verbatim');
select is((select count(*)::integer from public.learning_outcomes), 76, 'seventy-six official performance criteria');
select is((select count(*)::integer from public.learning_outcomes o join public.curriculum_modules m on m.id = o.module_id
  where m.coc_code = 'coc1' and m.code = 'LO1.2' and o.code like '2.%'), 3,
  'Element 2 Prepare installer criteria are attached to LO1.2');
select is((select string_agg(code, '>' order by sequence_order) from public.curriculum_modules where coc_code = 'coc3'),
  'LO3.2>LO3.1>LO3.3', 'COC3 teaching sequence starts with LO3.2');

-- Mission placement.
select is((select count(*)::integer from public.mission_curriculum_links), 20, 'all twenty missions are placed in a module');
select is((select count(*)::integer from public.mission_curriculum_links l join public.curriculum_modules m on m.id = l.module_id
  where left(l.mission_code, 4) <> m.coc_code), 0, 'every mission module belongs to the mission COC');
select is((select count(*)::integer from public.curriculum_modules m where not exists (
  select 1 from public.mission_curriculum_links l where l.module_id = m.id)), 3,
  'exactly three modules have no practice mission yet (LO1.3, LO2.3, LO4.2)');

-- Canonical catalog follows the practice contracts.
select is((select title from public.missions where mission_code = 'coc2_m3'),
  'Construct and Verify a Network Topology', 'catalog uses the practice title for COC2 M3');
select is((select title from public.missions where mission_code = 'coc1_m3'),
  'Install and Configure a Workstation OS', 'catalog uses the practice title for COC1 M3');
select is((select count(*)::integer from public.missions m join public.practice_mission_contracts c on c.mission_id = m.mission_code
  where m.title <> c.definition->>'title'), 0, 'no catalog title differs from its practice contract');
select ok((select count(*) from public.mission_catalog_history) >= 9, 'previous catalog values are retained in history');

-- Shared progression tables are read-only for clients and protected by RLS.
select ok(not has_table_privilege('authenticated', 'public.learner_module_unlocks', 'INSERT'), 'learners cannot grant themselves unlocks');
select ok(not has_table_privilege('authenticated', 'public.practice_mission_runs', 'INSERT'), 'learners cannot write run metrics');
select ok(not has_table_privilege('authenticated', 'public.learner_topic_progress', 'INSERT'), 'topic completion is server-recorded');
select ok(not has_table_privilege('authenticated', 'public.learner_module_completions', 'INSERT'), 'module completion is server-recorded');
select is((select count(*)::integer from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity), 0, 'every public table keeps RLS enabled');

-- Learners see only published topic revisions.
create temporary table foundation_ctx as
select (select user_id from public.profiles where role = 'learner' and status = 'active' order by created_at limit 1) learner,
       (select id from public.curriculum_modules where coc_code = 'coc1' and code = 'LO1.1') module_id;
insert into public.curriculum_topics (id, module_id, sequence_order)
select '00000000-0000-4000-8000-000000000101', module_id, 1 from foundation_ctx;
insert into public.curriculum_topic_revisions (topic_id, revision_number, title, body_markdown, status)
values ('00000000-0000-4000-8000-000000000101', 1, 'Published ESD precautions', 'Wear the wrist strap.', 'published'),
       ('00000000-0000-4000-8000-000000000101', 2, 'Draft ESD precautions', 'Draft text.', 'draft');
grant select on foundation_ctx to authenticated;
select set_config('request.jwt.claim.sub', (select learner::text from foundation_ctx), true);
set local role authenticated;
select is((select count(*)::integer from public.curriculum_topic_revisions where topic_id = '00000000-0000-4000-8000-000000000101'), 1,
  'learner sees only the published revision');
select is((select public.practice_mission_unlocked('coc1_m1', (select learner from foundation_ctx))), true,
  'COC1 missions stay unlocked for a new learner');
select is((select public.practice_mission_unlocked('coc2_m1', (select learner from foundation_ctx))), false,
  'COC2 stays locked until COC1 is complete');
reset role;

select * from finish();
rollback;
