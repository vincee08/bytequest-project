-- Slice A5 / WS8: staff-managed student IDs.
-- Additive only. The learner_id column grant is kept so older installed app
-- versions that resend an unchanged value keep saving profiles; a trigger
-- rejects only a learner's own change to a value that staff have confirmed.
-- No new SECURITY DEFINER function.
begin;
set local lock_timeout = '5s';

alter table public.profiles
  add column if not exists learner_id_managed boolean not null default false;

comment on column public.profiles.learner_id_managed is
  'True once a roster import or an administrator confirmed the student ID. The learner can no longer change it from the app.';

-- Invoker trigger: fires only when learner_id is part of the UPDATE and its
-- value changes. Other profile columns (including ones added later, for example
-- a leaderboard preference) never reach this check.
create or replace function private.protect_staff_managed_learner_id()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.learner_id_managed
     and new.learner_id is distinct from old.learner_id
     and (select auth.uid()) = old.user_id then
    raise exception 'STUDENT_ID_STAFF_MANAGED'
      using errcode = '42501',
            hint = 'Your student ID is managed by your instructor. Ask your instructor or an administrator to correct it.';
  end if;
  return new;
end
$$;

revoke all on function private.protect_staff_managed_learner_id() from public, anon, authenticated, service_role;

drop trigger if exists protect_staff_managed_learner_id on public.profiles;
create trigger protect_staff_managed_learner_id
  before update of learner_id on public.profiles
  for each row
  when (old.learner_id_managed and new.learner_id is distinct from old.learner_id)
  execute function private.protect_staff_managed_learner_id();

-- Uniqueness among learners (case and surrounding spaces ignored) when the
-- existing data allows it. Otherwise the roster import enforces it and reports
-- conflicts, and this migration leaves the legacy rows untouched.
do $$
begin
  if exists (
    select 1
    from public.profiles
    where role = 'learner'::public.user_role
      and nullif(btrim(learner_id), '') is not null
    group by lower(btrim(learner_id))
    having count(*) > 1
  ) then
    raise notice 'STUDENT_ID_UNIQUE_INDEX_SKIPPED: duplicate learner student IDs exist; roster import validation enforces uniqueness instead.';
  elsif not exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'profiles_learner_student_id_unique_idx'
  ) then
    create unique index profiles_learner_student_id_unique_idx
      on public.profiles (lower(btrim(learner_id)))
      where role = 'learner'::public.user_role
        and nullif(btrim(learner_id), '') is not null;
  end if;
end
$$;

-- Service-only invoker (called by the authenticated admin dashboard route with
-- the service client). Re-checks the actor from profiles; trims the value;
-- refuses a student ID already used by another learner; audits the change.
-- Setting a value marks it staff-managed; clearing it returns control to the
-- learner.
create or replace function public.set_learner_student_id(
  p_actor uuid,
  p_learner_id uuid,
  p_student_id text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_value text := nullif(btrim(coalesce(p_student_id, '')), '');
  v_old public.profiles;
  v_new public.profiles;
begin
  if not exists (
    select 1 from public.profiles
    where user_id = p_actor
      and role = 'admin'::public.user_role
      and status = 'active'::public.account_status
  ) then
    raise exception 'ADMIN_ACCESS_REQUIRED' using errcode = '42501';
  end if;

  select * into v_old from public.profiles where user_id = p_learner_id for update;
  if not found or v_old.role <> 'learner'::public.user_role then
    raise exception 'LEARNER_PROFILE_REQUIRED' using errcode = '22023';
  end if;

  if v_value is not null and (length(v_value) > 64 or v_value ~ '[[:cntrl:]]') then
    raise exception 'STUDENT_ID_INVALID' using errcode = '22023';
  end if;

  if v_value is not null and exists (
    select 1 from public.profiles p
    where p.role = 'learner'::public.user_role
      and p.user_id <> p_learner_id
      and lower(btrim(p.learner_id)) = lower(v_value)
  ) then
    raise exception 'STUDENT_ID_IN_USE' using errcode = '23505';
  end if;

  update public.profiles
  set learner_id = v_value,
      learner_id_managed = v_value is not null
  where user_id = p_learner_id
  returning * into v_new;

  insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, old_value, new_value, metadata)
  values (
    p_actor,
    'admin'::public.user_role,
    'profile.student_id_set',
    'profile',
    p_learner_id,
    jsonb_build_object('learner_id', v_old.learner_id, 'learner_id_managed', v_old.learner_id_managed),
    jsonb_build_object('learner_id', v_new.learner_id, 'learner_id_managed', v_new.learner_id_managed),
    jsonb_build_object('source', 'admin')
  );

  return jsonb_build_object(
    'user_id', v_new.user_id,
    'learner_id', v_new.learner_id,
    'learner_id_managed', v_new.learner_id_managed
  );
end
$$;

revoke all on function public.set_learner_student_id(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.set_learner_student_id(uuid, uuid, text) to service_role;

comment on function public.set_learner_student_id(uuid, uuid, text) is
  'Service-only (admin dashboard route): set or clear a learner student ID; a set value becomes staff-managed. Audited.';

commit;
