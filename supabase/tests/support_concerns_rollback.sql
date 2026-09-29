-- Role-scoped concern intake, transitions, and retained history.
-- The whole test is rollback-only and never persists fixture changes.
\echo 1..1
begin;

create temporary table bytequest_concern_context as
select
  (select user_id from public.profiles where role = 'instructor' and status = 'active' limit 1) instructor_id,
  (select user_id from public.profiles where role = 'admin' and status = 'active' limit 1) admin_id,
  (select user_id from public.profiles where role = 'learner' and status = 'active' limit 1) learner_id,
  null::uuid class_id,
  null::uuid training_id,
  null::uuid system_id;
grant select, update on bytequest_concern_context to authenticated;

do $$
declare
  v_class_id uuid;
begin
  if (select instructor_id is null or admin_id is null or learner_id is null
      from bytequest_concern_context) then
    raise exception 'SUPPORT_CONCERN_FIXTURE_PREREQUISITES_MISSING';
  end if;
  insert into public.classes(title, instructor_id, created_by)
  select 'Rollback-only training concern class', instructor_id, instructor_id
  from bytequest_concern_context
  returning id into v_class_id;
  update bytequest_concern_context set class_id = v_class_id;
end
$$;

select set_config('request.jwt.claim.sub',
  (select instructor_id::text from bytequest_concern_context), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

with opened as (
  insert into public.support_concerns(scope, class_id, title, details)
  select 'training', class_id, 'Learner equipment concern',
    'The training workstation requires a safe equipment inspection.'
  from bytequest_concern_context
  returning id
)
update bytequest_concern_context set training_id = opened.id from opened;

do $$
begin
  if not exists (
    select 1 from public.support_concerns c
    where c.id = (select training_id from bytequest_concern_context)
      and c.opened_by = (select instructor_id from bytequest_concern_context)
      and jsonb_array_length(c.history) = 1
      and c.history->0->>'actor_id' =
          (select instructor_id::text from bytequest_concern_context)
  ) then raise exception 'INSTRUCTOR_CONCERN_OPEN_HISTORY_MISSING'; end if;

  begin
    insert into public.support_concerns(scope, title, details)
    values ('system', 'Forbidden platform incident',
      'Instructor must not create an administrator-only platform incident.');
    raise exception 'INSTRUCTOR_CREATED_SYSTEM_INCIDENT';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.support_concerns
    set history = '[]'::jsonb
    where id = (select training_id from bytequest_concern_context);
    raise exception 'HISTORY_DIRECT_REWRITE_ALLOWED';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.support_concerns
    set status = 'resolved', status_reason = 'Bad'
    where id = (select training_id from bytequest_concern_context);
    raise exception 'MISSING_TRANSITION_REASON_ALLOWED';
  exception when invalid_parameter_value then null;
  end;
end
$$;

update public.support_concerns
set status = 'in_progress', status_reason = 'Instructor is reviewing the training equipment.'
where id = (select training_id from bytequest_concern_context);

reset role;
select set_config('request.jwt.claim.sub',
  (select admin_id::text from bytequest_concern_context), true);
set local role authenticated;

with opened as (
  insert into public.support_concerns(scope, title, details)
  values ('system', 'Platform account incident',
    'Administrator will investigate the account configuration incident.')
  returning id
)
update bytequest_concern_context set system_id = opened.id from opened;

do $$
begin
  if not exists (
    select 1 from public.support_concerns
    where id = (select training_id from bytequest_concern_context)
  ) then raise exception 'ADMIN_OVERSIGHT_TRAINING_CONCERN_MISSING'; end if;

  begin
    insert into public.support_concerns(scope, class_id, title, details)
    select 'training', class_id, 'Forbidden training concern',
      'Administrator must not create a routine Instructor training concern.'
    from bytequest_concern_context;
    raise exception 'ADMIN_CREATED_TRAINING_CONCERN';
  exception when insufficient_privilege then null;
  end;

  if (select count(*) from public.support_concerns
      where id = (select training_id from bytequest_concern_context)
      and scope = 'system') <> 0 then
    raise exception 'TRAINING_SCOPE_CHANGED';
  end if;
end
$$;

update public.support_concerns
set status = 'resolved', status_reason = 'Administrator corrected the platform configuration.'
where id = (select system_id from bytequest_concern_context);

reset role;
select set_config('request.jwt.claim.sub',
  (select learner_id::text from bytequest_concern_context), true);
set local role authenticated;

do $$
begin
  if exists (select 1 from public.support_concerns) then
    raise exception 'LEARNER_READ_SUPPORT_CONCERNS';
  end if;
  begin
    insert into public.support_concerns(scope, class_id, title, details)
    select 'training', class_id, 'Forbidden learner concern',
      'Learner must not create an Instructor-managed training concern.'
    from bytequest_concern_context;
    raise exception 'LEARNER_CREATED_SUPPORT_CONCERN';
  exception when insufficient_privilege then null;
  end;
end
$$;

reset role;
do $$
begin
  if not exists (
    select 1 from public.support_concerns
    where id = (select training_id from bytequest_concern_context)
      and status = 'in_progress'
      and jsonb_array_length(history) = 2
      and history->1->>'actor_role' = 'instructor'
  ) then raise exception 'TRAINING_TRANSITION_HISTORY_INVALID'; end if;
  if not exists (
    select 1 from public.support_concerns
    where id = (select system_id from bytequest_concern_context)
      and status = 'resolved' and resolved_at is not null
      and jsonb_array_length(history) = 2
      and history->1->>'actor_role' = 'admin'
  ) then raise exception 'SYSTEM_TRANSITION_HISTORY_INVALID'; end if;
end
$$;

rollback;
\echo ok 1 - support concerns role and history rollback
