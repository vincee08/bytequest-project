-- Panel revision (2026-11-23): a learner belongs to at most one active class.
-- Enforced in the database for every enrollment path: enroll_learner and
-- enroll_learner_by_email, the roster import and the sign-up roster claim.
-- Memberships that are deactivated, or that belong to an archived class, are
-- previous enrollments and do not count. Existing rows are not rewritten: a
-- learner who is already active in two classes keeps both memberships, but no
-- new second active membership can be created. Instructors are unaffected.
-- The trigger is SECURITY INVOKER: only postgres and service_role can write
-- class_memberships, and both read every row. No new SECURITY DEFINER function.
begin;
set local lock_timeout = '5s';

-- True when the learner has an active membership in another active class.
create or replace function private.learner_active_class_elsewhere(
  p_learner_id uuid,
  p_class_id uuid,
  p_membership_id uuid default null
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1
    from public.class_memberships cm
    join public.classes c on c.id = cm.class_id
    where cm.learner_id = p_learner_id
      and cm.status = 'active'::public.membership_status
      and c.status = 'active'::public.class_status
      and cm.class_id <> p_class_id
      and (p_membership_id is null or cm.id <> p_membership_id)
  )
$$;

create or replace function private.enforce_one_active_class_per_learner()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  if new.status <> 'active'::public.membership_status then
    return new;
  end if;
  -- Rewriting a row that is already active in the same class is not a new enrollment.
  if tg_op = 'UPDATE'
     and old.status = 'active'::public.membership_status
     and old.learner_id = new.learner_id
     and old.class_id = new.class_id then
    return new;
  end if;
  -- An archived class is not a current class, so it neither counts nor is checked.
  if not exists (
    select 1 from public.classes c
    where c.id = new.class_id and c.status = 'active'::public.class_status
  ) then
    return new;
  end if;
  -- Serialise every activation for this learner until commit, so two concurrent
  -- enrollments into different classes cannot both pass the check below. The
  -- check runs as a new statement after the lock, so it sees committed rows.
  perform pg_advisory_xact_lock(
    hashtextextended('bytequest:class_membership:learner:' || new.learner_id::text, 0)
  );
  if private.learner_active_class_elsewhere(new.learner_id, new.class_id, new.id) then
    -- The message is a stable code; it never names the other class.
    raise exception 'LEARNER_ALREADY_IN_ANOTHER_CLASS'
      using errcode = '23505',
            hint = 'A learner can belong to only one class at a time.';
  end if;
  return new;
end
$$;

drop trigger if exists trg_class_memberships_one_active_class on public.class_memberships;
create trigger trg_class_memberships_one_active_class
  before insert or update of status, class_id, learner_id on public.class_memberships
  for each row
  when (new.status = 'active'::public.membership_status)
  execute function private.enforce_one_active_class_per_learner();

revoke all on function private.learner_active_class_elsewhere(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function private.enforce_one_active_class_per_learner() from public, anon, authenticated;
grant execute on function private.learner_active_class_elsewhere(uuid, uuid, uuid) to service_role;
grant execute on function private.enforce_one_active_class_per_learner() to service_role;

comment on function private.learner_active_class_elsewhere(uuid, uuid, uuid) is
  'True when the learner has an active membership in another active class (deactivated memberships and archived classes do not count).';
comment on function private.enforce_one_active_class_per_learner() is
  'class_memberships trigger: at most one active membership per learner across active classes; raises LEARNER_ALREADY_IN_ANOTHER_CLASS (23505).';

-- A pending roster entry whose email signed up and joined another class.
alter table public.class_roster_entries drop constraint if exists class_roster_entries_status_check;
alter table public.class_roster_entries add constraint class_roster_entries_status_check
  check (status in ('pending', 'enrolled', 'cancelled', 'enrolled_elsewhere'));

comment on table public.class_roster_entries is
  'Imported class roster rows. pending = no account yet (claimed on sign-up with the same email); enrolled = claimed or enrolled by import; enrolled_elsewhere = the learner signed up and joined another class (one active class per learner); cancelled = withdrawn by the instructor. Client read-only.';

-- Roster import: learners already active in another class, and new emails
-- already waiting to join another class, are skipped rows. Neither ever
-- aborts the import. Otherwise unchanged from 20261119150200.
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
  v_elsewhere_message constant text := 'This learner is already enrolled in another class. A learner can belong to only one class at a time.';
  v_pending_elsewhere_message constant text := 'This email is already waiting to join another class. A learner can belong to only one class at a time.';
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
        when m.account_id is not null
          and private.learner_active_class_elsewhere(m.account_id, p_class_id) then 'enrolled_elsewhere'
        when m.account_id is null and exists (
          select 1 from public.class_roster_entries e
          join public.classes c on c.id = e.class_id
          where e.email_normalized = m.email
            and e.status = 'pending'
            and e.class_id <> p_class_id
            and c.status = 'active'::public.class_status
        ) then 'pending_elsewhere'
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
        when 'enrolled_elsewhere' then 'enrolled_elsewhere'
        when 'pending_elsewhere' then 'pending_elsewhere'
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
        when 'enrolled_elsewhere' then v_elsewhere_message
        when 'pending_elsewhere' then v_pending_elsewhere_message
        when 'sid_other_learner' then 'Student ID already belongs to another learner account.'
        when 'sid_profile_mismatch' then 'The learner account for this email has a different student ID. Correct the file or ask an administrator to update the profile.'
        when 'sid_pending_entry' then 'Student ID is already used by another pending roster entry in this class.'
        when 'account' then 'Registered learner account found. Enrolls when you confirm.'
        else 'No account yet. Enrolls automatically when this email signs up.'
      end,
      'learner_name', case when x.reason in ('enrolled', 'enrolled_elsewhere', 'account') then x.account_name end,
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
      count(*) filter (where r ->> 'status' in ('already_enrolled', 'enrolled_elsewhere', 'pending_elsewhere', 'conflict_student_id', 'staff_account')),
      count(*) filter (where r ->> 'status' = 'invalid')
    from jsonb_array_elements(v_rows) r
    returning * into v_batch;

    for v_item in select r from jsonb_array_elements(v_rows) r loop
      if v_item ->> 'status' = 'enroll_now' then
        v_membership := null;
        begin
          insert into public.class_memberships (class_id, learner_id, status, enrolled_by)
          values (p_class_id, (v_item ->> 'account_id')::uuid, 'active'::public.membership_status, p_actor)
          on conflict (class_id, learner_id) where status = 'active'::public.membership_status do nothing
          returning * into v_membership;
        exception when unique_violation then
          -- Enrolled in another class after classification: skip this row only.
          if sqlerrm <> 'LEARNER_ALREADY_IN_ANOTHER_CLASS' then
            raise;
          end if;
          v_membership := null;
          v_item := v_item || jsonb_build_object('status', 'enrolled_elsewhere', 'message', v_elsewhere_message);
        end;

        if v_item ->> 'status' = 'enrolled_elsewhere' then
          null;
        elsif v_membership.id is null then
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
        count(*) filter (where r ->> 'status' in ('already_enrolled', 'enrolled_elsewhere', 'pending_elsewhere', 'conflict_student_id', 'staff_account')) as skipped
      from jsonb_array_elements(v_results) r
    ) s
    where b.id = v_batch_id and (b.enrolled_count <> s.enrolled or b.skipped_count <> s.skipped);
    select * into v_batch from public.roster_import_batches where id = v_batch_id;
  end if;

  select jsonb_build_object(
    'total', count(*),
    'enroll_now', count(*) filter (where r ->> 'status' = 'enroll_now'),
    'already_enrolled', count(*) filter (where r ->> 'status' = 'already_enrolled'),
    'enrolled_elsewhere', count(*) filter (where r ->> 'status' = 'enrolled_elsewhere'),
    'pending_elsewhere', count(*) filter (where r ->> 'status' = 'pending_elsewhere'),
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

revoke all on function private.process_class_roster(uuid, uuid, jsonb, text, boolean) from public, anon, authenticated;
grant execute on function private.process_class_roster(uuid, uuid, jsonb, text, boolean) to service_role;

-- Sign-up claim: the learner joins only the oldest eligible pending class; the
-- other pending entries for that email become enrolled_elsewhere. As before,
-- the claim runs in its own subtransaction and can never fail the sign-up.
-- Otherwise unchanged from 20261119150300.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(btrim(coalesce(new.email, '')));
  v_meta_student_id text := coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'learner_id'), ''),
    nullif(btrim(new.raw_user_meta_data ->> 'student_id'), '')
  );
  v_profile public.profiles;
  v_entry record;
  v_membership public.class_memberships;
  v_joined boolean;
  v_distinct_ids integer;
  v_student_id text;
begin
  insert into public.profiles (user_id, email, full_name, role, status)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    'learner'::public.user_role,
    'active'::public.account_status
  )
  on conflict (user_id) do update
    set email = excluded.email;

  if v_email = '' then
    return new;
  end if;

  begin
    select * into v_profile from public.profiles where user_id = new.id;

    if v_profile.role = 'learner'::public.user_role
       and v_profile.status = 'active'::public.account_status then
      v_joined := exists (
        select 1 from public.class_memberships cm
        join public.classes c on c.id = cm.class_id
        where cm.learner_id = new.id
          and cm.status = 'active'::public.membership_status
          and c.status = 'active'::public.class_status
      );

      for v_entry in
        select e.id, e.class_id, e.student_id, coalesce(e.created_by, c.instructor_id) as enrolled_by
        from public.class_roster_entries e
        join public.classes c on c.id = e.class_id
        where e.email_normalized = v_email
          and e.status = 'pending'
          and c.status = 'active'::public.class_status
          and (v_meta_student_id is null or e.student_id is null or lower(e.student_id) = lower(v_meta_student_id))
        order by e.created_at, e.id
        for update of e
      loop
        v_membership := null;
        if not v_joined then
          begin
            insert into public.class_memberships (class_id, learner_id, status, enrolled_by)
            values (v_entry.class_id, new.id, 'active'::public.membership_status, v_entry.enrolled_by)
            on conflict (class_id, learner_id) where status = 'active'::public.membership_status do nothing
            returning * into v_membership;
            v_joined := true;
          exception when unique_violation then
            if sqlerrm <> 'LEARNER_ALREADY_IN_ANOTHER_CLASS' then
              raise;
            end if;
            v_membership := null;
            v_joined := true;
            -- Joined another class concurrently: this entry is not enrolled.
            update public.class_roster_entries
            set status = 'enrolled_elsewhere', claimed_user_id = new.id, claimed_at = clock_timestamp()
            where id = v_entry.id;
            insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, metadata)
            values (
              new.id, 'learner'::public.user_role, 'class_roster_entry.claim_skipped', 'class_roster_entry', v_entry.id,
              jsonb_build_object('class_id', v_entry.class_id, 'learner_id', new.id, 'reason', 'one_active_class')
            );
            continue;
          end;

          update public.class_roster_entries
          set status = 'enrolled', claimed_user_id = new.id, claimed_at = clock_timestamp()
          where id = v_entry.id;

          if v_membership.id is not null then
            insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, old_value, new_value, metadata)
            values (
              new.id, 'learner'::public.user_role, 'class_membership.enrolled', 'class_membership', v_membership.id,
              null, to_jsonb(v_membership),
              jsonb_build_object('class_id', v_entry.class_id, 'learner_id', new.id, 'source', 'roster_claim', 'roster_entry_id', v_entry.id)
            );
          end if;

          insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, metadata)
          values (
            new.id, 'learner'::public.user_role, 'class_roster_entry.claimed', 'class_roster_entry', v_entry.id,
            jsonb_build_object('class_id', v_entry.class_id, 'learner_id', new.id, 'membership_id', v_membership.id)
          );
        else
          -- One active class per learner: later pending entries are not enrolled.
          update public.class_roster_entries
          set status = 'enrolled_elsewhere', claimed_user_id = new.id, claimed_at = clock_timestamp()
          where id = v_entry.id;
          insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, metadata)
          values (
            new.id, 'learner'::public.user_role, 'class_roster_entry.claim_skipped', 'class_roster_entry', v_entry.id,
            jsonb_build_object('class_id', v_entry.class_id, 'learner_id', new.id, 'reason', 'one_active_class')
          );
        end if;
      end loop;

      -- Set the student ID only when every claimed entry agrees on one value,
      -- the profile has none and no other learner already uses it.
      select count(distinct lower(e.student_id)), (array_agg(e.student_id order by e.created_at, e.id))[1]
      into v_distinct_ids, v_student_id
      from public.class_roster_entries e
      where e.claimed_user_id = new.id
        and e.status = 'enrolled'
        and e.student_id is not null;

      if v_distinct_ids = 1
         and nullif(btrim(v_profile.learner_id), '') is null
         and not exists (
           select 1 from public.profiles o
           where o.role = 'learner'::public.user_role
             and o.user_id <> new.id
             and lower(btrim(o.learner_id)) = lower(v_student_id)
         ) then
        update public.profiles
        set learner_id = v_student_id, learner_id_managed = true
        where user_id = new.id;

        insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, old_value, new_value, metadata)
        values (
          new.id, 'learner'::public.user_role, 'profile.student_id_set', 'profile', new.id,
          jsonb_build_object('learner_id', v_profile.learner_id, 'learner_id_managed', v_profile.learner_id_managed),
          jsonb_build_object('learner_id', v_student_id, 'learner_id_managed', true),
          jsonb_build_object('source', 'roster_claim')
        );
      end if;
    end if;
  exception when others then
    raise warning 'ROSTER_CLAIM_FAILED user=% sqlstate=% message=%', new.id, sqlstate, sqlerrm;
    begin
      insert into public.audit_events (actor_id, actor_role, action, target_type, target_id, metadata, outcome)
      values (
        new.id, 'learner'::public.user_role, 'class_roster_entry.claim_failed', 'profile', new.id,
        jsonb_build_object('sqlstate', sqlstate), 'failed'
      );
    exception when others then
      raise warning 'ROSTER_CLAIM_AUDIT_FAILED user=%', new.id;
    end;
  end;

  return new;
end
$$;

-- Auth signup invokes this function through the auth.users trigger only.
revoke execute on function public.handle_new_user() from public, anon, authenticated, service_role;

comment on function public.handle_new_user() is
  'Auth profile provisioning trigger helper (fixed search_path, no client EXECUTE). Also claims pending class roster entries for the new email: joins only the oldest eligible class (one active class per learner) and marks later entries enrolled_elsewhere. Claim errors are logged and audited, never raised.';

commit;
