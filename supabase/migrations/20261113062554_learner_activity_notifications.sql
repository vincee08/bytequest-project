-- In-app delivery from existing authorized mutation/audit transactions.
-- No new elevated endpoint; no historical alerts or membership backfill.
begin;
set local lock_timeout = '5s';
alter table public.notifications add column event_key text;
create unique index notifications_recipient_event_idx on public.notifications(user_id,event_key) where event_key is not null;
create index notifications_recipient_created_idx on public.notifications(user_id,created_at desc,id desc);
create index notifications_unread_idx on public.notifications(user_id) where not is_read;

create function private.deliver_activity_notification() returns trigger
language plpgsql security invoker set search_path='' as $$
declare
  v_class uuid; v_activity uuid; v_kind text; v_title text; v_heading text;
  v_message text; v_key text; v_recipient uuid; v_class_title text;
begin
  -- The audit row is written only by the existing trusted mutation boundary.
  -- Never accept notification payloads/titles or recipients from the caller.
  if new.actor_role <> 'instructor' or not exists (
    select 1 from public.profiles where user_id=new.actor_id and role='instructor' and status='active'
  ) then return new; end if;
  if new.action='quiz.assigned' then
    select a.class_id,a.id,q.title into v_class,v_activity,v_title
    from public.quiz_assignments a join public.quiz_versions v on v.id=a.quiz_version_id
    join public.quizzes q on q.id=v.quiz_id
    where a.id=new.target_id and a.status='active' and v.status='published' and q.instructor_id=new.actor_id and q.archived_at is null;
    v_kind:='quiz'; v_heading:='New Quiz Assigned';
  elsif new.action='assignment.created' then
    select a.class_id,a.id,a.title into v_class,v_activity,v_title
    from public.assignments a join public.activity_versions v on v.id=a.activity_version_id
    where a.id=new.target_id and a.status='active' and v.status='published';
    v_kind:='technical'; v_heading:='Technical Activity Assigned';
  elsif new.action in ('homework.publish','homework.deadline') then
    if new.action='homework.deadline' and new.old_value->'deadline_at' is not distinct from new.new_value->'deadline_at' then return new; end if;
    select class_id,id,title into v_class,v_activity,v_title from public.homework_assignments
    where id=new.target_id and status='published' and instructor_id=new.actor_id;
    v_kind:='homework'; v_heading:=case when new.action='homework.publish' then 'New Homework Assignment' else 'Homework Deadline Updated' end;
  elsif new.action='homework.graded' then
    select h.class_id,h.id,h.title,s.learner_id into v_class,v_activity,v_title,v_recipient
    from public.homework_submissions s join public.homework_assignments h on h.id=s.assignment_id
    where s.id=new.target_id and s.status='graded' and s.graded_by=new.actor_id and h.instructor_id=new.actor_id;
    v_kind:='homework'; v_heading:='Assignment Graded';
  elsif new.action in ('quiz.reopened','quiz.deadline_changed') then
    if new.old_value->'deadline' is not distinct from new.new_value->'deadline' then return new; end if;
    select a.class_id,a.id,q.title into v_class,v_activity,v_title
    from public.quiz_assignments a join public.quiz_versions v on v.id=a.quiz_version_id
    join public.quizzes q on q.id=v.quiz_id where a.id=new.target_id and a.status='active'
    and v.status='published' and q.instructor_id=new.actor_id and q.archived_at is null;
    v_kind:='quiz'; v_heading:=case when new.action='quiz.reopened' then 'Quiz Reopened' else 'Quiz Deadline Updated' end;
  else return new; end if;
  select title into v_class_title from public.classes where id=v_class and instructor_id=new.actor_id and status='active';
  if not found or v_activity is null then return new; end if;
  v_message:=case
    when new.action='homework.graded' then 'Your instructor has graded '||v_title||'.'
    when new.action='quiz.reopened' then v_title||' has been reopened. Check the updated deadline and your current attempt status.'
    when new.action in ('quiz.deadline_changed','homework.deadline') then 'Your instructor updated the deadline for '||v_title||'. Open the activity for current availability.'
    else 'Your instructor assigned '||v_title||' to '||v_class_title||'.' end;
  v_key:=new.action||':'||new.target_id::text;
  if new.action in ('quiz.reopened','quiz.deadline_changed','homework.deadline') then v_key:=v_key||':'||new.id::text; end if;
  insert into public.notifications(user_id,title,message,type,event_key,metadata,created_at)
  select m.learner_id,v_heading,v_message,'system',v_key,
    jsonb_build_object('event_type',new.action,'activity_type',v_kind,'activity_id',v_activity,'class_id',v_class,'class_title',v_class_title),
    clock_timestamp()
  from public.class_memberships m join public.profiles p on p.user_id=m.learner_id
  where m.class_id=v_class and m.status='active' and p.role='learner' and p.status='active'
    and (v_recipient is null or m.learner_id=v_recipient)
  on conflict(user_id,event_key) where event_key is not null do nothing;
  return new;
end $$;
revoke all on function private.deliver_activity_notification() from public,anon,authenticated,service_role;
create trigger deliver_activity_notification after insert on public.audit_events
for each row when (new.action in ('quiz.assigned','assignment.created','homework.publish','homework.deadline','homework.graded','quiz.reopened','quiz.deadline_changed'))
execute function private.deliver_activity_notification();

-- Read time is authoritative and idempotent, including direct REST updates.
create function private.stamp_notification_read() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  new.read_at:=case when new.is_read then coalesce(old.read_at,clock_timestamp()) else null end;
  return new;
end $$;
revoke all on function private.stamp_notification_read() from public,anon,authenticated,service_role;
create trigger stamp_notification_read before update of is_read,read_at on public.notifications
for each row execute function private.stamp_notification_read();
commit;
