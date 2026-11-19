-- Slice A5: server-side learner search (scope, matching, filters, sort,
-- pagination). Rollback-only; fixtures include auth.users rows.
begin;
select plan(27);

create temporary table s5_ctx as
select
  (select user_id from public.profiles where email = 'qa.admin@bytequest.local') admin_id,
  (select user_id from public.profiles where email = 'qa.instructor@bytequest.local') instructor_id,
  (select user_id from public.profiles where email = 'qa.instructor2@bytequest.local') other_instructor_id;
grant select on s5_ctx to authenticated;

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email, '',
  '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', name), now(), now()
from (values
  ('00000000-0000-4000-8000-0000000b5001'::uuid, 'a5s.maria@bytequest.invalid', 'Maria Santos'),
  ('00000000-0000-4000-8000-0000000b5002'::uuid, 'a5s.juan@bytequest.invalid', 'Juan Dela Cruz'),
  ('00000000-0000-4000-8000-0000000b5003'::uuid, 'a5s.ana@bytequest.invalid', 'Ana Reyes'),
  ('00000000-0000-4000-8000-0000000b5004'::uuid, 'a5s.pedro@bytequest.invalid', 'Pedro Inactive'),
  ('00000000-0000-4000-8000-0000000b5005'::uuid, 'a5s.lone@bytequest.invalid', 'Lone Learner')
) fixture(id, email, name);
update public.profiles set learner_id = 'S-1001', last_activity_at = now() - interval '1 day', created_at = now() - interval '5 days'
  where user_id = '00000000-0000-4000-8000-0000000b5001';
update public.profiles set learner_id = 'S-1002', last_activity_at = now() - interval '2 hours', created_at = now() - interval '4 days'
  where user_id = '00000000-0000-4000-8000-0000000b5002';
update public.profiles set created_at = now() - interval '3 days' where user_id = '00000000-0000-4000-8000-0000000b5003';
update public.profiles set status = 'deactivated', deactivated_at = now(), deactivation_reason = 'A5 search fixture', created_at = now() - interval '2 days'
  where user_id = '00000000-0000-4000-8000-0000000b5004';
update public.profiles set created_at = now() - interval '1 day' where user_id = '00000000-0000-4000-8000-0000000b5005';

insert into public.classes (id, title, instructor_id, created_by)
select id, title, owner, owner from (values
  ('00000000-0000-4000-8000-0000000b5c01'::uuid, 'A5 Search Alpha', (select instructor_id from s5_ctx)),
  ('00000000-0000-4000-8000-0000000b5c02'::uuid, 'A5 Search Beta', (select instructor_id from s5_ctx)),
  ('00000000-0000-4000-8000-0000000b5c03'::uuid, 'A5 Search Archived', (select instructor_id from s5_ctx)),
  ('00000000-0000-4000-8000-0000000b5c04'::uuid, 'A5 Search Delta', (select other_instructor_id from s5_ctx))
) c(id, title, owner);
insert into public.class_memberships (class_id, learner_id, status, enrolled_by)
select class_id, learner_id, 'active', (select instructor_id from s5_ctx) from (values
  ('00000000-0000-4000-8000-0000000b5c01'::uuid, '00000000-0000-4000-8000-0000000b5001'::uuid),
  ('00000000-0000-4000-8000-0000000b5c03'::uuid, '00000000-0000-4000-8000-0000000b5001'::uuid),
  ('00000000-0000-4000-8000-0000000b5c01'::uuid, '00000000-0000-4000-8000-0000000b5002'::uuid),
  ('00000000-0000-4000-8000-0000000b5c02'::uuid, '00000000-0000-4000-8000-0000000b5002'::uuid),
  ('00000000-0000-4000-8000-0000000b5c04'::uuid, '00000000-0000-4000-8000-0000000b5003'::uuid),
  ('00000000-0000-4000-8000-0000000b5c02'::uuid, '00000000-0000-4000-8000-0000000b5004'::uuid)
) m(class_id, learner_id);
update public.classes set status = 'archived', archived_at = now(), archived_by = created_by, archive_reason = 'A5 search fixture'
  where id = '00000000-0000-4000-8000-0000000b5c03';

create function pg_temp.names(p_result jsonb) returns text language sql as $f$
  select coalesce(string_agg(r->>'full_name', ',' order by o), '') from jsonb_array_elements(p_result->'rows') with ordinality t(r, o)
$f$;
grant execute on function pg_temp.names(jsonb) to authenticated;

select ok((select not prosecdef from pg_proc where oid = 'public.search_learners(text,uuid,text,text,integer,integer)'::regprocedure),
  'learner search is SECURITY INVOKER (RLS decides the scope)');
select ok(has_function_privilege('authenticated', 'public.search_learners(text,uuid,text,text,integer,integer)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.search_learners(text,uuid,text,text,integer,integer)', 'EXECUTE'),
  'signed-in staff can call the search; anonymous clients cannot');

-- Learners are refused.
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000b5001', true);
set local role authenticated;
select throws_ok($$select public.search_learners('a5s.', null, null, 'name', 25, 0)$$, '42501', 'STAFF_ACCESS_REQUIRED',
  'learners cannot search the learner directory');
reset role;

-- Admin scope: every learner.
select set_config('request.jwt.claim.sub', (select admin_id::text from s5_ctx), true);
set local role authenticated;
select is((select (public.search_learners('a5s.', null, null, 'name', 25, 0)->>'total')::int), 5, 'admins search every learner');
select is(pg_temp.names(public.search_learners('a5s.', null, null, 'name', 25, 0)), 'Ana Reyes,Juan Dela Cruz,Lone Learner,Maria Santos,Pedro Inactive',
  'name sort is alphabetical');
select is(pg_temp.names(public.search_learners('a5s.', null, null, 'name.desc', 25, 0)), 'Pedro Inactive,Maria Santos,Lone Learner,Juan Dela Cruz,Ana Reyes',
  'name sort can be reversed');
select is(pg_temp.names(public.search_learners('a5s.', null, null, 'student_id', 25, 0)), 'Maria Santos,Juan Dela Cruz,Ana Reyes,Lone Learner,Pedro Inactive',
  'student ID sort lists missing IDs last');
select is(pg_temp.names(public.search_learners('a5s.', null, null, 'last_activity', 25, 0)), 'Juan Dela Cruz,Maria Santos,Ana Reyes,Lone Learner,Pedro Inactive',
  'last activity sort shows the most recent first and never-active learners last');
select is(pg_temp.names(public.search_learners('a5s.', null, null, 'created', 25, 0)), 'Lone Learner,Pedro Inactive,Ana Reyes,Juan Dela Cruz,Maria Santos',
  'created sort shows the newest accounts first');
select is(pg_temp.names(public.search_learners('a5s.', null, null, 'name', 2, 2)), 'Lone Learner,Maria Santos', 'pagination returns the requested page');
select is((select (public.search_learners('a5s.', null, null, 'name', 2, 2)->>'total')::int), 5, 'the total counts every match, not just the page');
select is((select (public.search_learners('a5s.', null, null, 'name', 500, -3)->>'limit')::int || '/' || (public.search_learners('a5s.', null, null, 'name', 500, -3)->>'offset')),
  '100/0', 'page size is capped at 100 and negative offsets start at the first row');
select is(pg_temp.names(public.search_learners('a5s.', null, 'inactive', 'name', 25, 0)), 'Pedro Inactive', 'the inactive filter returns non-active accounts');
select is((select (public.search_learners('a5s.', null, 'active', 'name', 25, 0)->>'total')::int), 4, 'the active filter excludes inactive accounts');
select is(pg_temp.names(public.search_learners('  MARIA  ', null, null, 'name', 25, 0)), 'Maria Santos', 'names match case-insensitively after trimming');
select is(pg_temp.names(public.search_learners('s-1002', null, null, 'name', 25, 0)), 'Juan Dela Cruz', 'student IDs match case-insensitively');
select is(pg_temp.names(public.search_learners('A5S.ANA@BYTEQUEST', null, null, 'name', 25, 0)), 'Ana Reyes', 'emails match case-insensitively');
select is(pg_temp.names(public.search_learners('santos, maria', null, null, 'name', 25, 0)), 'Maria Santos', 'every word must match, in any order');
select is(pg_temp.names(public.search_learners('Search Beta', null, null, 'name', 25, 0)), 'Juan Dela Cruz,Pedro Inactive', 'class titles are searchable');
select is((select (public.search_learners('%', null, null, 'name', 25, 0)->>'total')::int), 0, 'LIKE wildcards are matched literally');
select is((select jsonb_path_query_array(r, '$.classes[*].title')::text from jsonb_array_elements(public.search_learners('a5s.maria', null, null, 'name', 25, 0)->'rows') r),
  '["A5 Search Alpha"]', 'only active memberships in active classes are listed');
select is((select array_to_string(array(select jsonb_object_keys(r) order by 1), ',') from jsonb_array_elements(public.search_learners('a5s.juan', null, null, 'name', 25, 0)->'rows') r),
  'classes,created_at,email,full_name,last_activity_at,learner_id,learner_id_managed,status,user_id', 'rows carry the documented learner fields');
select throws_ok($$select public.search_learners(null, null, null, 'grade', 25, 0)$$, '22023', 'SEARCH_SORT_INVALID', 'unknown sort keys are rejected');
select throws_ok($$select public.search_learners(null, null, 'archived', 'name', 25, 0)$$, '22023', 'SEARCH_STATUS_INVALID', 'unknown status filters are rejected');
reset role;

-- Instructor scope: only learners in their own active classes.
select set_config('request.jwt.claim.sub', (select instructor_id::text from s5_ctx), true);
set local role authenticated;
select is(pg_temp.names(public.search_learners('a5s.', null, null, 'name', 25, 0)), 'Juan Dela Cruz,Maria Santos,Pedro Inactive',
  'instructors see only learners enrolled in their own active classes');
select is(pg_temp.names(public.search_learners(null, '00000000-0000-4000-8000-0000000b5c02', null, 'name', 25, 0))
  || '|' || pg_temp.names(public.search_learners(null, '00000000-0000-4000-8000-0000000b5c04', null, 'name', 25, 0)),
  'Juan Dela Cruz,Pedro Inactive|', 'the class filter works for owned classes and reveals nothing for another instructor''s class');
reset role;
select set_config('request.jwt.claim.sub', (select other_instructor_id::text from s5_ctx), true);
set local role authenticated;
select is((select jsonb_path_query_array(r, '$.classes[*].title')::text || ':' || (r->>'full_name')
    from jsonb_array_elements(public.search_learners('a5s.', null, null, 'name', 25, 0)->'rows') r),
  '["A5 Search Delta"]:Ana Reyes', 'another instructor sees only their learner and their own class');
reset role;

select * from finish();
rollback;
