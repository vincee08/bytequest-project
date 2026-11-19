-- QA fixture identities for a database without an Auth (GoTrue) service: a
-- hand-built empty database or a network-less restore-rehearsal copy. It
-- creates the same six qa.*@bytequest.local accounts as
-- scripts/local-qa-fixtures.mjs (same emails, names and roles; no password, so
-- nobody can sign in with them) for the rollback suites that look them up.
-- Idempotent. Not a suite: run-local-sql-tests.mjs reads only supabase/tests/*.sql.
--
-- Rehearsal and local copies only, never production. It refuses to run unless
-- the session opts in:
--   PGOPTIONS='-c bytequest.qa_fixtures=rehearsal' psql -d <copy> -v ON_ERROR_STOP=1 -f qa_fixture_users.sql
begin;

do $$
begin
  if coalesce(current_setting('bytequest.qa_fixtures', true), '') <> 'rehearsal' then
    raise exception 'Refusing to create QA fixtures: set bytequest.qa_fixtures=rehearsal (local or rehearsal copies only).';
  end if;
end
$$;

create temporary table qa_fixture(email text primary key, full_name text not null, role public.user_role not null) on commit drop;
insert into qa_fixture values
  ('qa.admin@bytequest.local', 'QA Admin', 'admin'),
  ('qa.instructor@bytequest.local', 'QA Instructor', 'instructor'),
  ('qa.instructor2@bytequest.local', 'QA Second Instructor', 'instructor'),
  ('qa.learner1@bytequest.local', 'QA Learner One', 'learner'),
  ('qa.learner2@bytequest.local', 'QA Learner Two', 'learner'),
  ('qa.learner3@bytequest.local', 'QA Learner Three', 'learner');

-- public.handle_new_user creates each profile.
insert into auth.users(instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000'::uuid, gen_random_uuid(), 'authenticated', 'authenticated',
  f.email, '', now(), '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('full_name', f.full_name), now(), now()
from qa_fixture f
where not exists (select 1 from auth.users u where lower(u.email) = f.email);

update public.profiles p
set role = f.role, status = 'active', full_name = f.full_name
from qa_fixture f, auth.users u
where lower(u.email) = f.email and p.user_id = u.id;

select f.email, p.role, p.status
from qa_fixture f join auth.users u on lower(u.email) = f.email join public.profiles p on p.user_id = u.id
order by f.email;

commit;
