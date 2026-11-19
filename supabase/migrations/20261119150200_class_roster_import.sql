-- Slice A5 / WS8: class roster import (owner decision 3).
-- Instructors upload a roster; existing learner accounts are enrolled
-- immediately, new emails become pending roster entries that are claimed when
-- that learner signs up with the same email (see 20261119150300). Instructors
-- never create accounts. Preview and import share one classification so the
-- confirmed import applies exactly what was previewed; invalid rows are never
-- imported. Service-only SECURITY INVOKER functions behind authenticated
-- dashboard routes; no new SECURITY DEFINER function. Additive only.
begin;
set local lock_timeout = '5s';

create table if not exists public.roster_import_batches (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete restrict,
  instructor_id uuid not null references auth.users(id) on delete restrict,
  file_name text check (file_name is null or length(file_name) between 1 and 255),
  row_count integer not null check (row_count between 1 and 1000),
  enrolled_count integer not null default 0 check (enrolled_count >= 0),
  pending_count integer not null default 0 check (pending_count >= 0),
  skipped_count integer not null default 0 check (skipped_count >= 0),
  invalid_count integer not null default 0 check (invalid_count >= 0),
  created_at timestamptz not null default now(),
  constraint roster_import_batches_counts_check
    check (enrolled_count + pending_count + skipped_count + invalid_count = row_count)
);
create index if not exists roster_import_batches_class_idx
  on public.roster_import_batches (class_id, created_at desc);

create table if not exists public.class_roster_entries (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete restrict,
  email_normalized text not null check (
    email_normalized = lower(btrim(email_normalized))
    and length(email_normalized) between 3 and 254
    and position('@' in email_normalized) > 1
  ),
  student_id text check (student_id is null or (student_id = btrim(student_id) and length(student_id) between 1 and 64)),
  last_name text not null check (length(btrim(last_name)) between 1 and 120),
  first_name text not null check (length(btrim(first_name)) between 1 and 120),
  course_section text check (course_section is null or length(btrim(course_section)) between 1 and 120),
  status text not null default 'pending' check (status in ('pending', 'enrolled', 'cancelled')),
  import_batch_id uuid references public.roster_import_batches(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  claimed_user_id uuid references auth.users(id) on delete restrict,
  claimed_at timestamptz,
  constraint class_roster_entries_class_email_key unique (class_id, email_normalized),
  constraint class_roster_entries_claim_check
    check (status <> 'enrolled' or (claimed_user_id is not null and claimed_at is not null))
);
create index if not exists class_roster_entries_class_status_idx
  on public.class_roster_entries (class_id, status);
create index if not exists class_roster_entries_pending_email_idx
  on public.class_roster_entries (email_normalized) where status = 'pending';

-- Imports and sign-up claims look accounts up by normalized email.
create index if not exists profiles_email_normalized_idx
  on public.profiles (lower(btrim(email)));

drop trigger if exists trg_class_roster_entries_updated_at on public.class_roster_entries;
create trigger trg_class_roster_entries_updated_at
  before update on public.class_roster_entries
  for each row execute function public.set_updated_at();

comment on table public.class_roster_entries is
  'Imported class roster rows. pending = no account yet (claimed on sign-up with the same email); enrolled = claimed or enrolled by import; cancelled = withdrawn by the instructor. Client read-only.';
comment on table public.roster_import_batches is
  'One row per confirmed roster import with its summary counts. Client read-only.';

alter table public.roster_import_batches enable row level security;
alter table public.class_roster_entries enable row level security;

drop policy if exists roster_import_batches_select_scoped on public.roster_import_batches;
create policy roster_import_batches_select_scoped
  on public.roster_import_batches for select to authenticated
  using (public.is_admin() or public.instructor_owns_class(class_id));

drop policy if exists class_roster_entries_select_scoped on public.class_roster_entries;
create policy class_roster_entries_select_scoped
  on public.class_roster_entries for select to authenticated
  using (public.is_admin() or public.instructor_owns_class(class_id));

revoke all on public.roster_import_batches, public.class_roster_entries from public, anon, authenticated;
grant select on public.roster_import_batches, public.class_roster_entries to authenticated;
grant all on public.roster_import_batches, public.class_roster_entries to service_role;

-- Text cell normalisation shared by preview and import: strings or numbers
-- only, whitespace collapsed and trimmed, empty -> null.
create or replace function private.roster_text(p_value jsonb)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select case
    when jsonb_typeof(p_value) in ('string', 'number')
      then nullif(btrim(regexp_replace(p_value #>> '{}', '[[:space:]]+', ' ', 'g')), '')
  end
$$;

-- Pragmatic address check (HTML living-standard local part, dotted domain).
create or replace function private.roster_email_valid(p_email text)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select p_email is not null
    and length(p_email) <= 254
    and p_email ~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$'
$$;

-- One classification for preview (p_apply = false) and import (true).
create or replace function private.process_class_roster(
  p_actor uuid,
  p_class_id uuid,
  p_rows jsonb,
  p_file_name text,
  p_apply boolean
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_class public.classes;
  v_count integer;
  v_rows jsonb;
  v_item jsonb;
  v_results jsonb := '[]'::jsonb;
  v_batch public.roster_import_batches;
  v_batch_id uuid;
  v_membership public.class_memberships;
  v_profile public.profiles;
  v_assigned boolean;
  v_needs_id boolean;
  v_summary jsonb;
  v_file_name text := nullif(left(btrim(coalesce(p_file_name, '')), 255), '');
  v_now timestamptz := clock_timestamp();
begin
  if p_actor is null or not exists (
    select 1 from public.profiles
    where user_id = p_actor
      and role = 'instructor'::public.user_role
      and status = 'active'::public.account_status
  ) then
    raise exception 'INSTRUCTOR_CLASS_SCOPE_REQUIRED' using errcode = '42501';
  end if;

  if p_apply then
    -- Serialise imports per class so concurrent confirmations cannot race.
    select * into v_class from public.classes
    where id = p_class_id and instructor_id = p_actor and status = 'active'::public.class_status
    for update;
  else
    select * into v_class from public.classes
    where id = p_class_id and instructor_id = p_actor and status = 'active'::public.class_status;
  end if;
  if not found then
    raise exception 'INSTRUCTOR_CLASS_SCOPE_REQUIRED' using errcode = '42501';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'ROSTER_ROWS_INVALID' using errcode = '22023';
  end if;
  v_count := jsonb_array_length(p_rows);
  if v_count = 0 then
    raise exception 'ROSTER_EMPTY' using errcode = '22023';
  end if;
  if v_count > 1000 then
    raise exception 'ROSTER_TOO_MANY_ROWS' using errcode = '22023';
  end if;

  with input as (
    select t.ord::integer as ordinal, t.r as raw
    from jsonb_array_elements(p_rows) with ordinality as t(r, ord)
  ),
  cleaned as (
    select
      i.ordinal,
      case
        when jsonb_typeof(i.raw -> 'row_number') = 'number'
          and (i.raw ->> 'row_number')::numeric between 1 and 10000000
        then floor((i.raw ->> 'row_number')::numeric)::integer
        else i.ordinal
      end as row_number,
      jsonb_typeof(i.raw) = 'object' as readable,
      private.roster_text(i.raw -> 'student_id') as student_id,
      private.roster_text(i.raw -> 'last_name') as last_name,
      private.roster_text(i.raw -> 'first_name') as first_name,
      lower(private.roster_text(i.raw -> 'email')) as email,
      private.roster_text(i.raw -> 'course_section') as course_section
    from input i
  ),
  checked as (
    select c.*,
      case
        when not c.readable then 'Row could not be read.'
        when c.last_name is null or c.first_name is null or c.email is null then
          'Missing required field' ||
          case when (c.last_name is null)::int + (c.first_name is null)::int + (c.email is null)::int > 1 then 's' else '' end ||
          ': ' || array_to_string(array_remove(array[
            case when c.last_name is null then 'last_name' end,
            case when c.first_name is null then 'first_name' end,
            case when c.email is null then 'email' end
          ], null), ', ') || '.'
        when not private.roster_email_valid(c.email) then 'Email address is not valid.'
        when length(c.student_id) > 64 then 'Student ID is longer than 64 characters.'
        when length(c.last_name) > 120 or length(c.first_name) > 120 then 'Name is longer than 120 characters.'
        when length(c.course_section) > 120 then 'Course/section is longer than 120 characters.'
      end as field_error
    from cleaned c
  ),
  ranked as (
    select k.*,
      first_value(k.row_number) over (partition by k.email order by k.ordinal) as email_first_row,
      row_number() over (partition by k.email order by k.ordinal) as email_rank,
      first_value(k.row_number) over (partition by lower(k.student_id) order by k.ordinal) as sid_first_row,
      row_number() over (partition by lower(k.student_id) order by k.ordinal) as sid_rank
    from checked k
  ),
  validated as (
    select r.*,
      coalesce(
        r.field_error,
        case
          when r.email is not null and r.email_rank > 1 then format('Duplicate email: same as row %s.', r.email_first_row)
          when r.student_id is not null and r.sid_rank > 1 then format('Duplicate student ID: same as row %s.', r.sid_first_row)
        end
      ) as file_error
    from ranked r
  ),
  matched as (
    select v.*,
      acct.user_id as account_id,
      acct.role as account_role,
      acct.status as account_status,
      acct.full_name as account_name,
      acct.learner_id as account_student_id,
      coalesce(acct.matches, 0) as account_matches
    from validated v
    left join lateral (
      select p.user_id, p.role, p.status, p.full_name, p.learner_id, count(*) over () as matches
      from public.profiles p
      where v.file_error is null
        and lower(btrim(p.email)) = v.email
      order by (p.role = 'learner'::public.user_role), p.created_at
      limit 1
    ) acct on true
  ),
  reasoned as (
    select m.*,
      case
        when m.file_error is not null then 'file_error'
        when m.account_matches > 1 then 'multiple_accounts'
        when m.account_id is not null and m.account_role <> 'learner'::public.user_role then 'staff'
        when m.account_id is not null and m.account_status <> 'active'::public.account_status then 'inactive_account'
        when m.account_id is not null and exists (
          select 1 from public.class_memberships cm
          where cm.class_id = p_class_id
            and cm.learner_id = m.account_id
            and cm.status = 'active'::public.membership_status
        ) then 'enrolled'
        when m.student_id is not null and exists (
          select 1 from public.profiles o
          where o.role = 'learner'::public.user_role
            and o.user_id is distinct from m.account_id
            and lower(btrim(o.learner_id)) = lower(m.student_id)
        ) then 'sid_other_learner'
        when m.account_id is not null and m.student_id is not null
          and nullif(btrim(m.account_student_id), '') is not null
          and lower(btrim(m.account_student_id)) <> lower(m.student_id) then 'sid_profile_mismatch'
        when m.student_id is not null and exists (
          select 1 from public.class_roster_entries e
          where e.class_id = p_class_id
            and e.status = 'pending'
            and e.email_normalized <> m.email
            and lower(e.student_id) = lower(m.student_id)
        ) then 'sid_pending_entry'
        when m.account_id is not null then 'account'
        else 'no_account'
      end as reason
    from matched m
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'row_number', x.row_number,
      'student_id', x.student_id,
      'last_name', x.last_name,
      'first_name', x.first_name,
      'email', x.email,
      'course_section', x.course_section,
      'status', case x.reason
        when 'file_error' then 'invalid'
        when 'multiple_accounts' then 'invalid'
        when 'inactive_account' then 'invalid'
        when 'staff' then 'staff_account'
        when 'enrolled' then 'already_enrolled'
        when 'sid_other_learner' then 'conflict_student_id'
        when 'sid_profile_mismatch' then 'conflict_student_id'
        when 'sid_pending_entry' then 'conflict_student_id'
        when 'account' then 'enroll_now'
        else 'pending'
      end,
      'message', case x.reason
        when 'file_error' then x.file_error
        when 'multiple_accounts' then 'Several accounts use this email. Ask an administrator to resolve it before importing.'
        when 'inactive_account' then 'The learner account for this email is not active. Ask an administrator to reactivate it before importing.'
        when 'staff' then 'This email belongs to a staff account. Staff accounts are never enrolled as learners.'
        when 'enrolled' then 'Already enrolled in this class.'
        when 'sid_other_learner' then 'Student ID already belongs to another learner account.'
        when 'sid_profile_mismatch' then 'The learner account for this email has a different student ID. Correct the file or ask an administrator to update the profile.'
        when 'sid_pending_entry' then 'Student ID is already used by another pending roster entry in this class.'
        when 'account' then 'Registered learner account found. Enrolls when you confirm.'
        else 'No account yet. Enrolls automatically when this email signs up.'
      end,
      'learner_name', case when x.reason in ('enrolled', 'account') then x.account_name end,
      'account_id', case when x.reason = 'account' then x.account_id end
    ) order by x.ordinal), '[]'::jsonb)
  into v_rows
  from reasoned x;

  if not p_apply then
    v_results := v_rows;
  else
    insert into public.roster_import_batches (
      class_id, instructor_id, file_name, row_count, enrolled_count, pending_count, skipped_count, invalid_count
    )
    select p_class_id, p_actor, v_file_name, v_count,
      count(*) filter (where r ->> 'status' = 'enroll_now'),
      count(*) filter (where r ->> 'status' = 'pending'),
      count(*) filter (where r ->> 'status' in ('already_enrolled', 'conflict_student_id', 'staff_account')),
      count(*) filter (where r ->> 'status' = 'invalid')
    from jsonb_array_elements(v_rows) r
    returning * into v_batch;

    for v_item in select r from jsonb_array_elements(v_rows) r loop
      if v_item ->> 'status' = 'enroll_now' then
        v_membership := null;
        insert into public.class_memberships (class_id, learner_id, status, enrolled_by)
        values (p_class_id, (v_item ->> 'account_id')::uuid, 'active'::public.membership_status, p_actor)
        on conflict (class_id, learner_id) where status = 'active'::public.membership_status do nothing
        returning * into v_membership;

        if v_membership.id is null then
          -- Enrolled concurrently after classification: report it, change nothing.
          v_item := v_item || jsonb_build_object('status', 'already_enrolled', 'message', 'Already enrolled in this class.');
        else
          v_assigned := false;
          if v_item ->> 'student_id' is not null then
            select * into v_profile from public.profiles where user_id = v_membership.learner_id for update;
            -- Assign when the profile has no student ID, or confirm (mark
            -- managed, trimmed) a matching self-entered one. A different ID was
            -- already classified as a conflict and never reaches this point.
            v_needs_id := nullif(btrim(v_profile.learner_id), '') is null
              or (lower(btrim(v_profile.learner_id)) = lower(v_item ->> 'student_id')
                  and (not v_profile.learner_id_managed or v_profile.learner_id <> btrim(v_profile.learner_id)));
            if v_needs_id
               and not exists (
                 select 1 from public.profiles o
                 where o.role = 'learner'::public.user_role
                   and o.user_id <> v_profile.user_id
                   and lower(btrim(o.learner_id)) = lower(v_item ->> 'student_id')
               ) then
              update public.profiles
              set learner_id = coalesce(nullif(btrim(learner_id), ''), v_item ->> 'student_id'),
                  learner_id_managed = true
              where user_id = v_profile.user_id;
              v_assigned := true;
              insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, old_value, new_value, metadata)
              values (
                p_actor, 'instructor'::public.user_role, 'profile.student_id_set', 'profile', v_profile.user_id,
                jsonb_build_object('learner_id', v_profile.learner_id, 'learner_id_managed', v_profile.learner_id_managed),
                jsonb_build_object('learner_id', coalesce(nullif(btrim(v_profile.learner_id), ''), v_item ->> 'student_id'), 'learner_id_managed', true),
                jsonb_build_object('source', 'roster_import', 'class_id', p_class_id, 'import_batch_id', v_batch.id)
              );
            end if;
          end if;

          update public.class_roster_entries
          set status = 'enrolled', claimed_user_id = v_membership.learner_id, claimed_at = v_now, import_batch_id = v_batch.id
          where class_id = p_class_id and email_normalized = v_item ->> 'email' and status <> 'enrolled';

          insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, old_value, new_value, metadata)
          values (
            p_actor, 'instructor'::public.user_role, 'class_membership.enrolled', 'class_membership', v_membership.id,
            null, to_jsonb(v_membership),
            jsonb_build_object(
              'class_id', p_class_id, 'learner_id', v_membership.learner_id, 'source', 'roster_import',
              'import_batch_id', v_batch.id, 'row_number', v_item -> 'row_number', 'student_id_assigned', v_assigned
            )
          );
          v_item := v_item || jsonb_build_object('student_id_assigned', v_assigned);
        end if;
      elsif v_item ->> 'status' = 'pending' then
        insert into public.class_roster_entries (
          class_id, email_normalized, student_id, last_name, first_name, course_section, status, import_batch_id, created_by
        )
        values (
          p_class_id, v_item ->> 'email', v_item ->> 'student_id', v_item ->> 'last_name', v_item ->> 'first_name',
          v_item ->> 'course_section', 'pending', v_batch.id, p_actor
        )
        on conflict (class_id, email_normalized) do update
          set student_id = excluded.student_id,
              last_name = excluded.last_name,
              first_name = excluded.first_name,
              course_section = excluded.course_section,
              status = 'pending',
              import_batch_id = excluded.import_batch_id
          where public.class_roster_entries.status <> 'enrolled';
      end if;
      v_results := v_results || jsonb_build_array(v_item);
    end loop;

    -- Keep the batch summary exact if a concurrent enrollment changed a row.
    v_batch_id := v_batch.id;
    update public.roster_import_batches b
    set enrolled_count = s.enrolled, skipped_count = s.skipped
    from (
      select
        count(*) filter (where r ->> 'status' = 'enroll_now') as enrolled,
        count(*) filter (where r ->> 'status' in ('already_enrolled', 'conflict_student_id', 'staff_account')) as skipped
      from jsonb_array_elements(v_results) r
    ) s
    where b.id = v_batch_id and (b.enrolled_count <> s.enrolled or b.skipped_count <> s.skipped);
    select * into v_batch from public.roster_import_batches where id = v_batch_id;
  end if;

  select jsonb_build_object(
    'total', count(*),
    'enroll_now', count(*) filter (where r ->> 'status' = 'enroll_now'),
    'already_enrolled', count(*) filter (where r ->> 'status' = 'already_enrolled'),
    'pending', count(*) filter (where r ->> 'status' = 'pending'),
    'conflict_student_id', count(*) filter (where r ->> 'status' = 'conflict_student_id'),
    'staff_account', count(*) filter (where r ->> 'status' = 'staff_account'),
    'invalid', count(*) filter (where r ->> 'status' = 'invalid')
  )
  into v_summary
  from jsonb_array_elements(v_results) r;

  if p_apply then
    insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, new_value, metadata)
    values (
      p_actor, 'instructor'::public.user_role, 'class_roster.imported', 'roster_import_batch', v_batch.id,
      to_jsonb(v_batch), jsonb_build_object('class_id', p_class_id, 'summary', v_summary)
    );
  end if;

  return jsonb_build_object(
    'class_id', v_class.id,
    'class_title', v_class.title,
    'applied', p_apply,
    'batch_id', v_batch.id,
    'file_name', v_file_name,
    'summary', v_summary,
    'rows', coalesce((select jsonb_agg(r - 'account_id' order by ord) from jsonb_array_elements(v_results) with ordinality t(r, ord)), '[]'::jsonb)
  );
end
$$;

create or replace function public.preview_class_roster(
  p_actor uuid,
  p_class_id uuid,
  p_rows jsonb
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.process_class_roster(p_actor, p_class_id, p_rows, null, false)
$$;

create or replace function public.import_class_roster(
  p_actor uuid,
  p_class_id uuid,
  p_rows jsonb,
  p_file_name text
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.process_class_roster(p_actor, p_class_id, p_rows, p_file_name, true)
$$;

-- The owning instructor withdraws a pending entry (for example a mistyped
-- email) so that nobody can claim it later. History is kept; audited.
create or replace function public.cancel_class_roster_entry(
  p_actor uuid,
  p_entry_id uuid
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_entry public.class_roster_entries;
  v_old jsonb;
begin
  select e.* into v_entry
  from public.class_roster_entries e
  join public.classes c on c.id = e.class_id
  join public.profiles p on p.user_id = p_actor
  where e.id = p_entry_id
    and c.instructor_id = p_actor
    and c.status = 'active'::public.class_status
    and p.role = 'instructor'::public.user_role
    and p.status = 'active'::public.account_status
  for update of e;
  if not found then
    raise exception 'INSTRUCTOR_CLASS_SCOPE_REQUIRED' using errcode = '42501';
  end if;
  if v_entry.status = 'cancelled' then
    return to_jsonb(v_entry);
  end if;
  if v_entry.status <> 'pending' then
    raise exception 'PENDING_ROSTER_ENTRY_REQUIRED' using errcode = '55000';
  end if;
  v_old := to_jsonb(v_entry);
  update public.class_roster_entries set status = 'cancelled' where id = v_entry.id returning * into v_entry;
  insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, old_value, new_value, metadata)
  values (p_actor, 'instructor'::public.user_role, 'class_roster_entry.cancelled', 'class_roster_entry', v_entry.id,
    v_old, to_jsonb(v_entry), jsonb_build_object('class_id', v_entry.class_id));
  return to_jsonb(v_entry);
end
$$;

revoke all on function private.roster_text(jsonb) from public, anon, authenticated;
revoke all on function private.roster_email_valid(text) from public, anon, authenticated;
revoke all on function private.process_class_roster(uuid, uuid, jsonb, text, boolean) from public, anon, authenticated;
revoke all on function public.preview_class_roster(uuid, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.import_class_roster(uuid, uuid, jsonb, text) from public, anon, authenticated;
revoke all on function public.cancel_class_roster_entry(uuid, uuid) from public, anon, authenticated;
grant execute on function private.roster_text(jsonb) to service_role;
grant execute on function private.roster_email_valid(text) to service_role;
grant execute on function private.process_class_roster(uuid, uuid, jsonb, text, boolean) to service_role;
grant execute on function public.preview_class_roster(uuid, uuid, jsonb) to service_role;
grant execute on function public.import_class_roster(uuid, uuid, jsonb, text) to service_role;
grant execute on function public.cancel_class_roster_entry(uuid, uuid) to service_role;

comment on function public.preview_class_roster(uuid, uuid, jsonb) is
  'Service-only: classify roster rows for the owning instructor''s active class without changing anything.';
comment on function public.import_class_roster(uuid, uuid, jsonb, text) is
  'Service-only: apply enroll_now (audited) and pending rows of a roster; idempotent; invalid rows are never imported.';
comment on function public.cancel_class_roster_entry(uuid, uuid) is
  'Service-only: the owning instructor cancels a pending roster entry so it is never claimed. Audited.';

commit;
