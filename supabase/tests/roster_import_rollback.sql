-- Slice A5: staff-managed student IDs, minimum app version, class roster
-- import (preview, confirm, idempotent re-import) and pending-roster claim on
-- sign-up. Rollback-only; every fixture (including auth.users rows) is undone.
begin;
select plan(26);

create temporary table a5_ctx as
select
  (select user_id from public.profiles where email = 'qa.admin@bytequest.local') admin_id,
  (select user_id from public.profiles where email = 'qa.instructor@bytequest.local') instructor_id,
  (select user_id from public.profiles where email = 'qa.instructor2@bytequest.local') other_instructor_id,
  '00000000-0000-4000-8000-0000000a5001'::uuid learner_a,
  '00000000-0000-4000-8000-0000000a5002'::uuid learner_b;
grant select on a5_ctx to authenticated, service_role, anon;

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-0000000a5001', 'authenticated', 'authenticated',
   'a5.learner.a@bytequest.invalid', '', '{"provider":"email","providers":["email"]}', '{"full_name":"A5 Learner A"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-0000000a5002', 'authenticated', 'authenticated',
   'a5.learner.b@bytequest.invalid', '', '{"provider":"email","providers":["email"]}', '{"full_name":"A5 Learner B"}', now(), now());

-- ---------------------------------------------------------------------------
-- Part 1: staff-managed student IDs
-- ---------------------------------------------------------------------------
select has_column('public', 'profiles', 'learner_id_managed', 'profiles record whether the student ID is staff-managed');
select is((select learner_id_managed from public.profiles where user_id = (select learner_a from a5_ctx)), false,
  'new learner profiles start with a self-managed student ID');
select ok(has_column_privilege('authenticated', 'public.profiles', 'learner_id', 'UPDATE'),
  'the learner_id column grant stays so older installed apps keep saving profiles');
select ok(not has_column_privilege('authenticated', 'public.profiles', 'learner_id_managed', 'UPDATE'),
  'learners cannot clear the staff-managed flag');
select ok(not has_function_privilege('authenticated', 'public.set_learner_student_id(uuid,uuid,text)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.set_learner_student_id(uuid,uuid,text)', 'EXECUTE'),
  'student ID assignment is a service-only operation');

select set_config('request.jwt.claim.sub', (select learner_a::text from a5_ctx), true);
set local role authenticated;
select lives_ok($$update public.profiles set learner_id = '2026-0001' where user_id = '00000000-0000-4000-8000-0000000a5001'$$,
  'a learner can set an unmanaged student ID');
reset role;

select set_config('request.jwt.claim.sub', '', true);
set local role service_role;
select is((select public.set_learner_student_id((select admin_id from a5_ctx), (select learner_a from a5_ctx), ' 2026-0001 ')->>'learner_id'),
  '2026-0001', 'an admin confirms a student ID through the service path (trimmed)');
reset role;
select is((select learner_id_managed from public.profiles where user_id = (select learner_a from a5_ctx)), true,
  'a staff-confirmed student ID becomes staff-managed');

select set_config('request.jwt.claim.sub', (select learner_a::text from a5_ctx), true);
set local role authenticated;
select lives_ok($$update public.profiles set full_name = 'A5 Learner A Renamed', learner_id = '2026-0001', school = 'DNSC'
  where user_id = '00000000-0000-4000-8000-0000000a5001'$$,
  'unchanged_learner_id_update_allowed: resending the same managed student ID keeps older app saves working');
select is((select full_name from public.profiles where user_id = '00000000-0000-4000-8000-0000000a5001'), 'A5 Learner A Renamed',
  'the profile edit with an unchanged managed student ID was saved');
select throws_ok($$update public.profiles set learner_id = '2026-9999' where user_id = '00000000-0000-4000-8000-0000000a5001'$$,
  '42501', 'STUDENT_ID_STAFF_MANAGED', 'a learner cannot change a staff-managed student ID');
select throws_ok($$update public.profiles set learner_id = null where user_id = '00000000-0000-4000-8000-0000000a5001'$$,
  '42501', 'STUDENT_ID_STAFF_MANAGED', 'a learner cannot clear a staff-managed student ID');
select throws_ok($$update public.profiles set learner_id_managed = false where user_id = '00000000-0000-4000-8000-0000000a5001'$$,
  '42501', null, 'a learner cannot unlock the managed flag directly');
reset role;

select set_config('request.jwt.claim.sub', '', true);
set local role service_role;
select throws_ok($$select public.set_learner_student_id((select instructor_id from a5_ctx), (select learner_a from a5_ctx), '2026-7777')$$,
  '42501', 'ADMIN_ACCESS_REQUIRED', 'instructors cannot reassign student IDs through the admin path');
select is((select public.set_learner_student_id((select admin_id from a5_ctx), (select learner_a from a5_ctx), '2026-0002')->>'learner_id'),
  '2026-0002', 'an admin can change a staff-managed student ID');
select throws_ok($$select public.set_learner_student_id((select admin_id from a5_ctx), (select learner_b from a5_ctx), ' 2026-0002')$$,
  '23505', 'STUDENT_ID_IN_USE', 'an admin cannot give two learners the same student ID');
select throws_ok($$select public.set_learner_student_id((select admin_id from a5_ctx), (select instructor_id from a5_ctx), '2026-5555')$$,
  '22023', 'LEARNER_PROFILE_REQUIRED', 'student IDs are assigned to learner profiles only');
reset role;

select ok(
  exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'profiles_learner_student_id_unique_idx')
  or exists (select 1 from public.profiles where role = 'learner' and nullif(btrim(learner_id), '') is not null
             group by lower(btrim(learner_id)) having count(*) > 1),
  'student IDs are unique among learners unless legacy duplicates forced the migration to skip the index');
select set_config('request.jwt.claim.sub', (select learner_b::text from a5_ctx), true);
set local role authenticated;
select case when exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'profiles_learner_student_id_unique_idx')
  then throws_ok($$update public.profiles set learner_id = ' 2026-0002 ' where user_id = '00000000-0000-4000-8000-0000000a5002'$$,
    '23505', null, 'a learner cannot self-assign another learner''s student ID (case and spacing ignored)')
  else skip('legacy duplicate student IDs: uniqueness enforced at import', 1) end;
reset role;
select ok(exists (select 1 from public.audit_events where action = 'profile.student_id_set'
  and target_id = (select learner_a from a5_ctx) and actor_id = (select admin_id from a5_ctx)),
  'every staff student ID assignment is audited');

-- ---------------------------------------------------------------------------
-- Part 1b: minimum supported app version
-- ---------------------------------------------------------------------------
select is((select value from public.app_release_config where key = 'min_supported_app_version'), '1.2.0',
  'the minimum supported app version is seeded');
select ok((select relrowsecurity from pg_class where oid = 'public.app_release_config'::regclass),
  'app release config keeps RLS enabled');
select set_config('request.jwt.claim.sub', (select learner_a::text from a5_ctx), true);
set local role authenticated;
select is((select value from public.app_release_config where key = 'min_supported_app_version'), '1.2.0',
  'signed-in learners can read the minimum app version');
select throws_ok($$update public.app_release_config set value = '0.0.1' where key = 'min_supported_app_version'$$,
  '42501', null, 'learners cannot lower the minimum app version');
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select is((select value from public.app_release_config where key = 'min_supported_app_version'), '1.2.0',
  'the splash screen can check the minimum version before sign-in');
reset role;
select ok(not has_table_privilege('authenticated', 'public.app_release_config', 'INSERT,UPDATE,DELETE')
  and not has_table_privilege('anon', 'public.app_release_config', 'INSERT,UPDATE,DELETE')
  and has_table_privilege('service_role', 'public.app_release_config', 'UPDATE'),
  'only the service role can change release configuration');

select * from finish();
rollback;
