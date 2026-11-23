-- Slice A5: staff-managed student IDs, minimum app version, class roster
-- import (preview, confirm, idempotent re-import) and pending-roster claim on
-- sign-up. Rollback-only; every fixture (including auth.users rows) is undone.
begin;
select plan(62);

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

-- ---------------------------------------------------------------------------
-- Part 2: class roster preview, import, idempotent re-import and sign-up claim
-- ---------------------------------------------------------------------------
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email, '',
  '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', name), now(), now()
from (values
  ('00000000-0000-4000-8000-0000000a5003'::uuid, 'a5.learner.c@bytequest.invalid', 'A5 Learner C'),
  ('00000000-0000-4000-8000-0000000a5004'::uuid, 'a5.learner.d@bytequest.invalid', 'A5 Learner D'),
  ('00000000-0000-4000-8000-0000000a5005'::uuid, 'a5.learner.e@bytequest.invalid', 'A5 Learner E'),
  ('00000000-0000-4000-8000-0000000a5010'::uuid, 'a5.learner.f@bytequest.invalid', 'A5 Learner F')
) fixture(id, email, name);
update public.profiles set status = 'deactivated', deactivated_at = now(), deactivation_reason = 'A5 roster fixture'
where user_id = '00000000-0000-4000-8000-0000000a5003';
update public.profiles set learner_id = '2026-0500' where user_id = '00000000-0000-4000-8000-0000000a5005';
update public.profiles set learner_id = '2026-0600' where user_id = '00000000-0000-4000-8000-0000000a5010';
insert into public.classes (id, title, instructor_id, created_by)
select '00000000-0000-4000-8000-0000000a5c01', 'A5 Roster QA', instructor_id, instructor_id from a5_ctx;
insert into public.class_memberships (class_id, learner_id, status, enrolled_by)
select '00000000-0000-4000-8000-0000000a5c01', '00000000-0000-4000-8000-0000000a5004', 'active', instructor_id from a5_ctx;

create temporary table a5_rows as select $json$[
  {"row_number":2,"student_id":"2026-0100","last_name":"Learner","first_name":"B","email":"A5.Learner.B@BYTEQUEST.invalid","course_section":"CSS NC II - A"},
  {"row_number":3,"student_id":null,"last_name":"Learner","first_name":"D","email":"a5.learner.d@bytequest.invalid","course_section":null},
  {"row_number":4,"student_id":"2026-0200","last_name":"Pending","first_name":"Paula","email":"a5.pending@bytequest.invalid","course_section":"CSS NC II - A"},
  {"row_number":5,"student_id":"2026-0002","last_name":"Other","first_name":"Owen","email":"a5.other.sid@bytequest.invalid","course_section":null},
  {"row_number":6,"student_id":"S-STAFF","last_name":"Instructor","first_name":"Two","email":"qa.instructor2@bytequest.local","course_section":null},
  {"row_number":7,"student_id":"2026-0300","last_name":"Missing","first_name":"","email":"a5.missing@bytequest.invalid","course_section":null},
  {"row_number":8,"student_id":"2026-0301","last_name":"Bad","first_name":"Email","email":"not-an-email","course_section":null},
  {"row_number":9,"student_id":"2026-0302","last_name":"Pending","first_name":"Again","email":"A5.PENDING@bytequest.invalid","course_section":null},
  {"row_number":10,"student_id":"2026-0999","last_name":"Learner","first_name":"E","email":"a5.learner.e@bytequest.invalid","course_section":null},
  {"row_number":11,"student_id":null,"last_name":"Learner","first_name":"C","email":"a5.learner.c@bytequest.invalid","course_section":null},
  {"row_number":12,"student_id":"2026-0200","last_name":"Twin","first_name":"Tina","email":"a5.twin@bytequest.invalid","course_section":null},
  {"row_number":13,"student_id":"S-MISMATCH","last_name":"Mismatch","first_name":"Mia","email":"a5.mismatch@bytequest.invalid","course_section":null},
  {"row_number":14,"student_id":null,"last_name":"Failing","first_name":"Fay","email":"a5.failing@bytequest.invalid","course_section":null},
  {"row_number":15,"student_id":null,"last_name":"Cancelled","first_name":"Cal","email":"a5.cancelled@bytequest.invalid","course_section":null},
  {"row_number":16,"student_id":" 2026-0600 ","last_name":"Learner","first_name":"F","email":"a5.learner.f@bytequest.invalid","course_section":null}
]$json$::jsonb as payload;
create temporary table a5_results (label text primary key, result jsonb);
grant select on a5_rows to authenticated, service_role;
grant select, insert on a5_results to service_role;

select ok(not has_function_privilege('authenticated', 'public.preview_class_roster(uuid,uuid,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.import_class_roster(uuid,uuid,jsonb,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.import_class_roster(uuid,uuid,jsonb,text)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.import_class_roster(uuid,uuid,jsonb,text)', 'EXECUTE'),
  'roster preview and import are service-only operations');
select ok(not has_table_privilege('authenticated', 'public.class_roster_entries', 'INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated', 'public.roster_import_batches', 'INSERT,UPDATE,DELETE')
  and (select relrowsecurity from pg_class where oid = 'public.class_roster_entries'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.roster_import_batches'::regclass),
  'roster tables are RLS-protected and client read-only');

select set_config('request.jwt.claim.sub', '', true);
set local role service_role;
insert into a5_results select 'preview', public.preview_class_roster((select instructor_id from a5_ctx),
  '00000000-0000-4000-8000-0000000a5c01', (select payload from a5_rows));
select is((select string_agg((r->>'row_number') || ':' || (r->>'status'), ',' order by (r->>'row_number')::int)
    from a5_results, jsonb_array_elements(result->'rows') r where label = 'preview'),
  '2:enroll_now,3:already_enrolled,4:pending,5:conflict_student_id,6:staff_account,7:invalid,8:invalid,9:invalid,10:conflict_student_id,11:invalid,12:invalid,13:pending,14:pending,15:pending,16:enroll_now',
  'preview classifies every row: enroll now, already enrolled, pending, student ID conflict, staff account, invalid');
select is((select result->'summary' from a5_results where label = 'preview'),
  '{"total":15,"enroll_now":2,"already_enrolled":1,"pending":4,"enrolled_elsewhere":0,"pending_elsewhere":0,"conflict_student_id":2,"staff_account":1,"invalid":5}'::jsonb,
  'preview summary counts every status');
select is((select r->>'message' from a5_results, jsonb_array_elements(result->'rows') r where label = 'preview' and r->>'row_number' = '9'),
  'Duplicate email: same as row 4.', 'duplicates within the file name the original row (email compared case-insensitively)');
select is((select r->>'message' from a5_results, jsonb_array_elements(result->'rows') r where label = 'preview' and r->>'row_number' = '12'),
  'Duplicate student ID: same as row 4.', 'duplicate student IDs within the file are invalid');
select is((select r->>'message' from a5_results, jsonb_array_elements(result->'rows') r where label = 'preview' and r->>'row_number' = '7'),
  'Missing required field: first_name.', 'missing required fields are named');
select is((select r->>'email' from a5_results, jsonb_array_elements(result->'rows') r where label = 'preview' and r->>'row_number' = '2'),
  'a5.learner.b@bytequest.invalid', 'emails are trimmed and lower-cased');
select ok((select bool_and(not (r ? 'account_id')) from a5_results, jsonb_array_elements(result->'rows') r where label = 'preview'),
  'preview rows do not expose internal account identifiers');
reset role;
select is((select count(*)::integer from public.class_roster_entries where class_id = '00000000-0000-4000-8000-0000000a5c01')
  + (select count(*)::integer from public.roster_import_batches where class_id = '00000000-0000-4000-8000-0000000a5c01')
  + (select count(*)::integer from public.class_memberships where class_id = '00000000-0000-4000-8000-0000000a5c01'), 1,
  'nothing changes until the instructor confirms the import');

select set_config('request.jwt.claim.sub', '', true);
set local role service_role;
select throws_ok($$select public.preview_class_roster((select other_instructor_id from a5_ctx), '00000000-0000-4000-8000-0000000a5c01', (select payload from a5_rows))$$,
  '42501', 'INSTRUCTOR_CLASS_SCOPE_REQUIRED', 'another instructor cannot preview this class roster');
select throws_ok($$select public.import_class_roster((select other_instructor_id from a5_ctx), '00000000-0000-4000-8000-0000000a5c01', (select payload from a5_rows), 'roster.xlsx')$$,
  '42501', 'INSTRUCTOR_CLASS_SCOPE_REQUIRED', 'another instructor cannot import into this class');
select throws_ok($$select public.import_class_roster((select learner_a from a5_ctx), '00000000-0000-4000-8000-0000000a5c01', (select payload from a5_rows), 'roster.xlsx')$$,
  '42501', 'INSTRUCTOR_CLASS_SCOPE_REQUIRED', 'learners cannot import rosters');
select throws_ok($$select public.preview_class_roster((select instructor_id from a5_ctx), '00000000-0000-4000-8000-0000000a5c01',
    (select jsonb_agg(jsonb_build_object('row_number', n, 'last_name', 'L', 'first_name', 'F', 'email', 'bulk' || n || '@bytequest.invalid')) from generate_series(1, 1001) n))$$,
  '22023', 'ROSTER_TOO_MANY_ROWS', 'a roster is limited to 1000 rows');

insert into a5_results select 'import', public.import_class_roster((select instructor_id from a5_ctx),
  '00000000-0000-4000-8000-0000000a5c01', (select payload from a5_rows), 'BSIT-2A roster.xlsx');
select is((select jsonb_build_object('applied', result->'applied', 'summary', result->'summary') from a5_results where label = 'import'),
  '{"applied":true,"summary":{"total":15,"enroll_now":2,"already_enrolled":1,"pending":4,"enrolled_elsewhere":0,"pending_elsewhere":0,"conflict_student_id":2,"staff_account":1,"invalid":5}}'::jsonb,
  'import applies the previewed classification');
reset role;
select is((select string_agg(p.email, ',' order by p.email) from public.class_memberships m join public.profiles p on p.user_id = m.learner_id
    where m.class_id = '00000000-0000-4000-8000-0000000a5c01' and m.status = 'active'),
  'a5.learner.b@bytequest.invalid,a5.learner.d@bytequest.invalid,a5.learner.f@bytequest.invalid',
  'existing learner accounts are enrolled immediately; staff, conflicting and invalid rows are not');
select is((select learner_id || ':' || learner_id_managed from public.profiles where user_id = '00000000-0000-4000-8000-0000000a5002'),
  '2026-0100:true', 'an enrolled learner without a student ID receives the roster ID as staff-managed');
select is((select learner_id || ':' || learner_id_managed from public.profiles where user_id = '00000000-0000-4000-8000-0000000a5010'),
  '2026-0600:true', 'a matching self-entered student ID becomes staff-managed without being rewritten');
select is((select learner_id || ':' || learner_id_managed from public.profiles where user_id = '00000000-0000-4000-8000-0000000a5005'),
  '2026-0500:false', 'a conflicting roster row never overwrites the learner''s student ID');
select is((select string_agg(email_normalized || ':' || coalesce(student_id, '-') || ':' || status, ',' order by email_normalized)
    from public.class_roster_entries where class_id = '00000000-0000-4000-8000-0000000a5c01'),
  'a5.cancelled@bytequest.invalid:-:pending,a5.failing@bytequest.invalid:-:pending,a5.mismatch@bytequest.invalid:S-MISMATCH:pending,a5.pending@bytequest.invalid:2026-0200:pending',
  'new emails become pending roster entries; invalid and conflicting rows are never stored');
select is((select row_count || '/' || enrolled_count || '/' || pending_count || '/' || skipped_count || '/' || invalid_count || '/' || file_name
    from public.roster_import_batches where class_id = '00000000-0000-4000-8000-0000000a5c01'),
  '15/2/4/4/5/BSIT-2A roster.xlsx', 'the import batch records its summary');
select ok(exists (select 1 from public.audit_events where action = 'class_membership.enrolled'
    and target_id = (select id from public.class_memberships where class_id = '00000000-0000-4000-8000-0000000a5c01' and learner_id = '00000000-0000-4000-8000-0000000a5002')
    and actor_id = (select instructor_id from a5_ctx) and metadata->>'source' = 'roster_import')
  and exists (select 1 from public.audit_events where action = 'class_roster.imported'
    and target_id = (select id from public.roster_import_batches where class_id = '00000000-0000-4000-8000-0000000a5c01')),
  'roster enrollments and the import batch are audited');

select set_config('request.jwt.claim.sub', '', true);
set local role service_role;
insert into a5_results select 'reimport', public.import_class_roster((select instructor_id from a5_ctx),
  '00000000-0000-4000-8000-0000000a5c01', (select payload from a5_rows), 'BSIT-2A roster.xlsx');
select is((select result->'summary' from a5_results where label = 'reimport'),
  '{"total":15,"enroll_now":0,"already_enrolled":3,"pending":4,"enrolled_elsewhere":0,"pending_elsewhere":0,"conflict_student_id":2,"staff_account":1,"invalid":5}'::jsonb,
  'idempotent re-import: enrolled rows become already enrolled and pending rows stay pending');
reset role;
select is((select count(*)::integer from public.class_memberships where class_id = '00000000-0000-4000-8000-0000000a5c01')
  || '/' || (select count(*)::integer from public.class_roster_entries where class_id = '00000000-0000-4000-8000-0000000a5c01'),
  '3/4', 're-import creates no duplicate memberships or roster entries');

-- Sign-up with a pending email (different case) enrolls automatically.
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-0000000a5006', 'authenticated', 'authenticated',
  'A5.Pending@ByteQuest.invalid', '', '{"provider":"email","providers":["email"]}', '{"full_name":"Paula Pending"}', now(), now());
select is((select status::text from public.class_memberships where class_id = '00000000-0000-4000-8000-0000000a5c01'
    and learner_id = '00000000-0000-4000-8000-0000000a5006'), 'active',
  'signing up with a pending roster email enrolls the learner');
select is((select status || ':' || (claimed_user_id = '00000000-0000-4000-8000-0000000a5006') from public.class_roster_entries
    where class_id = '00000000-0000-4000-8000-0000000a5c01' and email_normalized = 'a5.pending@bytequest.invalid'),
  'enrolled:true', 'the claimed roster entry is marked enrolled for that learner');
select is((select learner_id || ':' || learner_id_managed from public.profiles where user_id = '00000000-0000-4000-8000-0000000a5006'),
  '2026-0200:true', 'the roster student ID is set as staff-managed on sign-up');
select ok(exists (select 1 from public.audit_events where action = 'class_roster_entry.claimed'
  and actor_id = '00000000-0000-4000-8000-0000000a5006'), 'the roster claim is audited');

-- A different student ID in the sign-up metadata does not claim the entry.
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-0000000a5007', 'authenticated', 'authenticated',
  'a5.mismatch@bytequest.invalid', '', '{"provider":"email","providers":["email"]}', '{"full_name":"Mia","learner_id":"S-OTHER"}', now(), now());
select is((select status from public.class_roster_entries where class_id = '00000000-0000-4000-8000-0000000a5c01'
    and email_normalized = 'a5.mismatch@bytequest.invalid')
  || ':' || (select count(*) from public.class_memberships where learner_id = '00000000-0000-4000-8000-0000000a5007'),
  'pending:0', 'a sign-up whose student ID differs from the roster entry is not enrolled');

-- A failing claim never blocks the sign-up.
create function public.a5_test_forced_failure() returns trigger language plpgsql as $f$
begin raise exception 'A5_FORCED_CLAIM_FAILURE'; end $f$;
create trigger a5_test_forced_failure before insert on public.class_memberships
  for each row execute function public.a5_test_forced_failure();
select lives_ok($$insert into auth.users (instance_id, id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-0000000a5008', 'authenticated', 'authenticated',
  'a5.failing@bytequest.invalid', '', '{"provider":"email","providers":["email"]}', '{"full_name":"Fay"}', now(), now())$$,
  'a failing roster claim never fails the sign-up');
drop trigger a5_test_forced_failure on public.class_memberships;
drop function public.a5_test_forced_failure();
select is((select (select count(*) from public.profiles where user_id = '00000000-0000-4000-8000-0000000a5008') || ':'
    || (select status from public.class_roster_entries where class_id = '00000000-0000-4000-8000-0000000a5c01' and email_normalized = 'a5.failing@bytequest.invalid')
    || ':' || exists (select 1 from public.audit_events where action = 'class_roster_entry.claim_failed'
      and target_id = '00000000-0000-4000-8000-0000000a5008' and outcome = 'failed')),
  '1:pending:true', 'after a failed claim the profile exists, the entry stays pending and the failure is audited');

-- Cancelled entries are never claimed; only the owning instructor can cancel.
select set_config('request.jwt.claim.sub', '', true);
set local role service_role;
select throws_ok($$select public.cancel_class_roster_entry((select other_instructor_id from a5_ctx),
    (select id from public.class_roster_entries where class_id = '00000000-0000-4000-8000-0000000a5c01' and email_normalized = 'a5.cancelled@bytequest.invalid'))$$,
  '42501', 'INSTRUCTOR_CLASS_SCOPE_REQUIRED', 'another instructor cannot cancel a pending roster entry');
select is((select public.cancel_class_roster_entry((select instructor_id from a5_ctx),
    (select id from public.class_roster_entries where class_id = '00000000-0000-4000-8000-0000000a5c01' and email_normalized = 'a5.cancelled@bytequest.invalid'))->>'status'),
  'cancelled', 'the owning instructor can cancel a pending roster entry');
reset role;
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-0000000a5009', 'authenticated', 'authenticated',
  'a5.cancelled@bytequest.invalid', '', '{"provider":"email","providers":["email"]}', '{"full_name":"Cal"}', now(), now());
select is((select count(*)::integer from public.class_memberships where learner_id = '00000000-0000-4000-8000-0000000a5009'), 0,
  'a cancelled roster entry is never claimed');

-- Roster rows are visible only to the owning instructor and admins.
select set_config('request.jwt.claim.sub', (select other_instructor_id::text from a5_ctx), true);
set local role authenticated;
select is((select count(*)::integer from public.class_roster_entries where class_id = '00000000-0000-4000-8000-0000000a5c01')
  + (select count(*)::integer from public.roster_import_batches where class_id = '00000000-0000-4000-8000-0000000a5c01'), 0,
  'another instructor cannot read this class roster');
reset role;
select set_config('request.jwt.claim.sub', (select instructor_id::text from a5_ctx), true);
set local role authenticated;
select is((select count(*)::integer from public.class_roster_entries where class_id = '00000000-0000-4000-8000-0000000a5c01'), 4,
  'the owning instructor reads the class roster entries');
reset role;

select * from finish();
rollback;
