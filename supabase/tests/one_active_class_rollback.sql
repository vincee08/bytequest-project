-- One active class per learner (20261123090000): instructor enrollment, direct
-- reactivation, archived classes, legacy duplicates, roster import outcomes and
-- the sign-up roster claim. Rollback-only; every fixture (including auth.users
-- rows) is undone.
begin;
select plan(21);

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email, '',
  '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', name), now(), now()
from (values
  ('00000000-0000-4000-8000-0000000c1001'::uuid, 'oac.teacher.a@bytequest.invalid', 'OAC Teacher A'),
  ('00000000-0000-4000-8000-0000000c1002'::uuid, 'oac.teacher.b@bytequest.invalid', 'OAC Teacher B'),
  ('00000000-0000-4000-8000-0000000c1003'::uuid, 'oac.learner.one@bytequest.invalid', 'OAC Learner One'),
  ('00000000-0000-4000-8000-0000000c1004'::uuid, 'oac.learner.two@bytequest.invalid', 'OAC Learner Two'),
  ('00000000-0000-4000-8000-0000000c1005'::uuid, 'oac.learner.legacy@bytequest.invalid', 'OAC Legacy Learner'),
  ('00000000-0000-4000-8000-0000000c1006'::uuid, 'oac.learner.free@bytequest.invalid', 'OAC Free Learner')
) fixture(id, email, name);
update public.profiles set role = 'instructor'
where user_id in ('00000000-0000-4000-8000-0000000c1001', '00000000-0000-4000-8000-0000000c1002');

insert into public.classes (id, title, instructor_id, created_by) values
  ('00000000-0000-4000-8000-0000000c1c0a', 'OAC Class A', '00000000-0000-4000-8000-0000000c1001', '00000000-0000-4000-8000-0000000c1001'),
  ('00000000-0000-4000-8000-0000000c1c0b', 'OAC Class B', '00000000-0000-4000-8000-0000000c1002', '00000000-0000-4000-8000-0000000c1002'),
  ('00000000-0000-4000-8000-0000000c1c0c', 'OAC Class C', '00000000-0000-4000-8000-0000000c1001', '00000000-0000-4000-8000-0000000c1001'),
  ('00000000-0000-4000-8000-0000000c1c0d', 'OAC Class D', '00000000-0000-4000-8000-0000000c1001', '00000000-0000-4000-8000-0000000c1001');

create temporary table oac_results (label text primary key, result jsonb);
grant select, insert on oac_results to service_role;

select ok(exists (
    select 1 from pg_trigger
    where tgrelid = 'public.class_memberships'::regclass
      and tgname = 'trg_class_memberships_one_active_class'
      and tgenabled = 'O'),
  'the one-active-class trigger guards every write to class_memberships');
select ok(pg_get_functiondef('private.enforce_one_active_class_per_learner()'::regprocedure) like '%pg_advisory_xact_lock%',
  'activations are serialised per learner with a transaction advisory lock');

-- Instructor enrollment.
select set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-4000-8000-0000000c1001', 'role', 'authenticated')::text, true);
set local role authenticated;
select lives_ok($$select public.enroll_learner('00000000-0000-4000-8000-0000000c1c0a', '00000000-0000-4000-8000-0000000c1003')$$,
  'a learner without a class can be enrolled');
reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-4000-8000-0000000c1002', 'role', 'authenticated')::text, true);
set local role authenticated;
select throws_ok($$select public.enroll_learner('00000000-0000-4000-8000-0000000c1c0b', '00000000-0000-4000-8000-0000000c1003')$$,
  '23505', 'LEARNER_ALREADY_IN_ANOTHER_CLASS',
  'a second active class is refused with a stable code that never names the first class');
reset role;
select is((select count(*)::int from public.class_memberships
  where learner_id = '00000000-0000-4000-8000-0000000c1003' and status = 'active'), 1,
  'the refused enrollment writes nothing');

select set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-4000-8000-0000000c1001', 'role', 'authenticated')::text, true);
set local role authenticated;
select throws_ok($$select public.enroll_learner('00000000-0000-4000-8000-0000000c1c0a', '00000000-0000-4000-8000-0000000c1003')$$,
  '23505', 'LEARNER_ALREADY_ENROLLED', 'a duplicate in the same class keeps its own message');
select lives_ok($$select public.deactivate_class_membership(
    (select id from public.class_memberships
     where class_id = '00000000-0000-4000-8000-0000000c1c0a' and learner_id = '00000000-0000-4000-8000-0000000c1003' and status = 'active'),
    'Moved to another section')$$,
  'the first instructor can remove the learner from the class');
reset role;

select set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-4000-8000-0000000c1002', 'role', 'authenticated')::text, true);
set local role authenticated;
select lives_ok($$select public.enroll_learner('00000000-0000-4000-8000-0000000c1c0b', '00000000-0000-4000-8000-0000000c1003')$$,
  'a deactivated membership is a previous enrollment and does not block a new class');
reset role;

-- An active membership in an archived class does not count.
select set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-4000-8000-0000000c1001', 'role', 'authenticated')::text, true);
set local role authenticated;
select public.enroll_learner('00000000-0000-4000-8000-0000000c1c0c', '00000000-0000-4000-8000-0000000c1004') is not null as enrolled_in_c;
select public.archive_class('00000000-0000-4000-8000-0000000c1c0c', 'Term ended') is not null as archived_c;
select lives_ok($$select public.enroll_learner('00000000-0000-4000-8000-0000000c1c0d', '00000000-0000-4000-8000-0000000c1004')$$,
  'a membership in an archived class does not block a new class');
reset role;

-- Direct reactivation and legacy duplicates (postgres writes).
select throws_ok($$update public.class_memberships
    set status = 'active', deactivated_at = null, deactivated_by = null, deactivation_reason = null
    where class_id = '00000000-0000-4000-8000-0000000c1c0a' and learner_id = '00000000-0000-4000-8000-0000000c1003'$$,
  '23505', 'LEARNER_ALREADY_IN_ANOTHER_CLASS',
  'reactivating an old membership is refused while the learner is active in another class');

alter table public.class_memberships disable trigger trg_class_memberships_one_active_class;
insert into public.class_memberships (class_id, learner_id, enrolled_by) values
  ('00000000-0000-4000-8000-0000000c1c0a', '00000000-0000-4000-8000-0000000c1005', '00000000-0000-4000-8000-0000000c1001'),
  ('00000000-0000-4000-8000-0000000c1c0b', '00000000-0000-4000-8000-0000000c1005', '00000000-0000-4000-8000-0000000c1002');
alter table public.class_memberships enable trigger trg_class_memberships_one_active_class;
select lives_ok($$update public.class_memberships set status = 'active'
    where class_id = '00000000-0000-4000-8000-0000000c1c0a' and learner_id = '00000000-0000-4000-8000-0000000c1005'$$,
  'existing duplicate rows stay valid: rewriting an active row is not a new enrollment');
select lives_ok($$update public.class_memberships
    set status = 'deactivated', deactivated_at = now(), deactivated_by = '00000000-0000-4000-8000-0000000c1001', deactivation_reason = 'Legacy cleanup'
    where class_id = '00000000-0000-4000-8000-0000000c1c0a' and learner_id = '00000000-0000-4000-8000-0000000c1005'$$,
  'an existing duplicate can still be deactivated');

-- Roster import: never aborts; skips learners in another class and emails
-- already waiting to join another class.
insert into public.class_roster_entries (class_id, email_normalized, last_name, first_name, status, created_by)
values ('00000000-0000-4000-8000-0000000c1c0b', 'oac.pending.elsewhere@bytequest.invalid', 'Elsewhere', 'Pat', 'pending',
  '00000000-0000-4000-8000-0000000c1002');
set local role service_role;
insert into oac_results
select 'import', public.import_class_roster(
  '00000000-0000-4000-8000-0000000c1001', '00000000-0000-4000-8000-0000000c1c0a',
  $json$[
    {"row_number":2,"student_id":null,"last_name":"Learner","first_name":"One","email":"oac.learner.one@bytequest.invalid","course_section":null},
    {"row_number":3,"student_id":null,"last_name":"Elsewhere","first_name":"Pat","email":"oac.pending.elsewhere@bytequest.invalid","course_section":null},
    {"row_number":4,"student_id":null,"last_name":"Learner","first_name":"Free","email":"oac.learner.free@bytequest.invalid","course_section":null},
    {"row_number":5,"student_id":null,"last_name":"New","first_name":"Nina","email":"oac.new@bytequest.invalid","course_section":null}
  ]$json$::jsonb, 'oac-roster.xlsx');
reset role;
select is((select result -> 'summary' from oac_results where label = 'import'),
  '{"total":4,"enroll_now":1,"already_enrolled":0,"enrolled_elsewhere":1,"pending_elsewhere":1,"pending":1,"conflict_student_id":0,"staff_account":0,"invalid":0}'::jsonb,
  'the import completes and reports learners in another class separately');
select is((select array_agg(r ->> 'status' order by (r ->> 'row_number')::int)
    from oac_results, jsonb_array_elements(result -> 'rows') r where label = 'import'),
  array['enrolled_elsewhere', 'pending_elsewhere', 'enroll_now', 'pending'],
  'each roster row reports its own outcome');
select is((select r ->> 'message' from oac_results, jsonb_array_elements(result -> 'rows') r
    where label = 'import' and r ->> 'row_number' = '2'),
  'This learner is already enrolled in another class. A learner can belong to only one class at a time.',
  'the skipped row explains the one-class rule');
select is((select row(enrolled_count, pending_count, skipped_count, invalid_count)::text
    from public.roster_import_batches
    where id = (select (result ->> 'batch_id')::uuid from oac_results where label = 'import')),
  '(1,1,2,0)', 'batch counts include the skipped rows');
select ok(exists (select 1 from public.class_memberships
      where class_id = '00000000-0000-4000-8000-0000000c1c0a' and learner_id = '00000000-0000-4000-8000-0000000c1006' and status = 'active')
    and not exists (select 1 from public.class_memberships
      where class_id = '00000000-0000-4000-8000-0000000c1c0a' and learner_id = '00000000-0000-4000-8000-0000000c1003' and status = 'active'),
  'only the learner without a class is enrolled by the import');

-- Sign-up claim: joins only the oldest pending class and never fails.
insert into public.class_roster_entries (class_id, email_normalized, last_name, first_name, status, created_by, created_at) values
  ('00000000-0000-4000-8000-0000000c1c0a', 'oac.claim@bytequest.invalid', 'Claim', 'Cora', 'pending', '00000000-0000-4000-8000-0000000c1001', now() - interval '2 days'),
  ('00000000-0000-4000-8000-0000000c1c0b', 'oac.claim@bytequest.invalid', 'Claim', 'Cora', 'pending', '00000000-0000-4000-8000-0000000c1002', now() - interval '1 day');
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-0000000c1007', 'authenticated', 'authenticated',
  'oac.claim@bytequest.invalid', '', '{"provider":"email","providers":["email"]}', '{"full_name":"OAC Claim Learner"}', now(), now());
select is((select array_agg(c.title order by c.title) from public.class_memberships cm
    join public.classes c on c.id = cm.class_id
    where cm.learner_id = '00000000-0000-4000-8000-0000000c1007' and cm.status = 'active'),
  array['OAC Class A'], 'sign-up joins only the oldest pending class');
select is((select status || ':' || (claimed_user_id = '00000000-0000-4000-8000-0000000c1007')
    from public.class_roster_entries
    where class_id = '00000000-0000-4000-8000-0000000c1c0b' and email_normalized = 'oac.claim@bytequest.invalid'),
  'enrolled_elsewhere:true', 'the later pending entry is marked enrolled elsewhere');
select ok(exists (select 1 from public.audit_events
      where action = 'class_roster_entry.claim_skipped' and actor_id = '00000000-0000-4000-8000-0000000c1007')
    and not exists (select 1 from public.audit_events
      where action = 'class_roster_entry.claim_failed' and actor_id = '00000000-0000-4000-8000-0000000c1007'),
  'the skipped claim is audited and the sign-up claim did not fail');

select ok(not has_function_privilege('authenticated', 'private.learner_active_class_elsewhere(uuid,uuid,uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'private.learner_active_class_elsewhere(uuid,uuid,uuid)', 'EXECUTE'),
  'the membership lookup is not callable by clients');

select * from finish();
rollback;
