-- Separate instructor-managed training concerns from administrator-managed
-- platform incidents without changing existing class or audit records.
begin;

create table public.support_concerns (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('training', 'system')),
  class_id uuid references public.classes(id) on delete restrict,
  opened_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  title text not null check (length(btrim(title)) between 5 and 160),
  details text not null check (length(btrim(details)) between 10 and 4000),
  status text not null default 'open' check (status in ('open', 'in_progress', 'resolved')),
  status_reason text,
  history jsonb not null default '[]'::jsonb check (jsonb_typeof(history) = 'array'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint support_concerns_scope_class_check check (
    (scope = 'training' and class_id is not null)
    or (scope = 'system' and class_id is null)
  ),
  constraint support_concerns_resolved_check check (
    (status = 'resolved') = (resolved_at is not null)
  )
);

create index support_concerns_scope_created_idx
  on public.support_concerns(scope, created_at desc);
create index support_concerns_class_status_idx
  on public.support_concerns(class_id, status) where class_id is not null;
create index support_concerns_opened_by_idx
  on public.support_concerns(opened_by, created_at desc);

create function private.record_support_concern_history()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_now timestamptz := now();
begin
  if tg_op = 'INSERT' then
    new.opened_by := (select auth.uid());
    if new.opened_by is null or new.status <> 'open' then
      raise exception 'CONCERN_OPEN_NOT_AUTHORIZED' using errcode = '42501';
    end if;
    new.created_at := v_now;
    new.updated_at := v_now;
    new.history := jsonb_build_array(jsonb_build_object(
      'event', 'opened', 'actor_id', new.opened_by,
      'actor_role', public.current_app_role(), 'at', v_now,
      'to_status', 'open'
    ));
    return new;
  end if;

  if new.status = old.status then
    raise exception 'CONCERN_STATUS_CHANGE_REQUIRED' using errcode = '22023';
  end if;
  if length(btrim(coalesce(new.status_reason, ''))) < 5 then
    raise exception 'CONCERN_STATUS_REASON_REQUIRED' using errcode = '22023';
  end if;
  new.updated_at := v_now;
  new.resolved_at := case when new.status = 'resolved' then v_now else null end;
  new.history := old.history || jsonb_build_array(jsonb_build_object(
    'event', 'status_changed', 'actor_id', (select auth.uid()),
    'actor_role', public.current_app_role(), 'at', v_now,
    'from_status', old.status, 'to_status', new.status,
    'reason', btrim(new.status_reason)
  ));
  return new;
end
$$;

create trigger record_support_concern_history
before insert or update on public.support_concerns
for each row execute function private.record_support_concern_history();

revoke all on function private.record_support_concern_history() from public, anon, authenticated;
revoke all on public.support_concerns from public, anon, authenticated;
grant select on public.support_concerns to authenticated;
grant insert (scope, class_id, title, details) on public.support_concerns to authenticated;
grant update (status, status_reason) on public.support_concerns to authenticated;
grant all on public.support_concerns to service_role;

alter table public.support_concerns enable row level security;

create policy support_concerns_staff_read
on public.support_concerns for select to authenticated
using (
  public.is_active_user()
  and (
    public.is_admin()
    or (public.is_instructor() and scope = 'training' and opened_by = (select auth.uid()))
  )
);

create policy support_concerns_role_insert
on public.support_concerns for insert to authenticated
with check (
  public.is_active_user()
  and opened_by = (select auth.uid())
  and (
    (public.is_instructor() and scope = 'training' and public.instructor_owns_class(class_id))
    or (public.is_admin() and scope = 'system' and class_id is null)
  )
);

create policy support_concerns_scope_update
on public.support_concerns for update to authenticated
using (
  public.is_active_user()
  and (
    (public.is_instructor() and scope = 'training' and opened_by = (select auth.uid()))
    or (public.is_admin() and scope = 'system')
  )
)
with check (
  public.is_active_user()
  and (
    (public.is_instructor() and scope = 'training' and opened_by = (select auth.uid()))
    or (public.is_admin() and scope = 'system')
  )
);

comment on table public.support_concerns is
  'Retained training concerns and system incidents; only staff roles may write in their own scope.';

commit;
