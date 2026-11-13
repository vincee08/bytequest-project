-- Retain the existing one-row-per-quiz projection and its authorization.
-- Add only entitled assignment/class references for notification resolution;
-- quiz version tables, answer contracts, claims and deadlines remain private.
begin;
set local lock_timeout='5s';
create or replace function public.get_available_learner_quizzes()
returns jsonb language sql volatile security definer set search_path='' as $$
  select case when not public.is_learner() then jsonb_build_object('error','LEARNER_REQUIRED')
  else coalesce((
    select jsonb_agg(payload order by class_title,title) from (
      select distinct on (q.id) jsonb_build_object(
        'assignment_id',a.id,
        'eligible_assignments',(
          select coalesce(jsonb_agg(jsonb_build_object('assignment_id',link.id,'class_id',link.class_id) order by link.id),'[]'::jsonb)
          from public.quiz_assignments link join public.quiz_versions linked_version on linked_version.id=link.quiz_version_id
          join public.classes linked_class on linked_class.id=link.class_id and linked_class.status='active'
          join public.class_memberships member on member.class_id=link.class_id and member.learner_id=(select auth.uid()) and member.status='active'
          where linked_version.quiz_id=q.id and link.status='active'
            and (linked_version.status='published' or link.id=latest.quiz_assignment_id)
        ),
        'quiz_version_id',coalesce(latest.quiz_version_id,a.quiz_version_id),
        'quiz_id',q.id,'title',q.title,'description',q.description,'topic',q.topic,
        'instructions',coalesce(a.instructions,qv.instructions),'class_id',c.id,'class_title',c.title,
        'coc_code',cm.coc_code,'coc_title',cm.title,
        'question_count',(select count(*) from public.quiz_items qi where qi.quiz_version_id=coalesce(latest.quiz_version_id,qv.id)
          and qi.removed_at is null and qi.review_status='approved'),
        'available_at',a.available_at,'due_at',effective.due_at,'server_now',private.activity_server_now(),
        'closed_reason',case when effective.due_at<=private.activity_server_now() then 'deadline_passed' else null end,
        'attempts_allowed',1,
        'is_available',private.quiz_assignment_is_available(coalesce(latest.quiz_assignment_id,a.id),(select auth.uid())),
        'attempt_id',latest.id,'attempt_status',latest.status,'answered_count',coalesce(latest.answered_count,0),
        'started_at',latest.started_at,'completed_at',latest.completed_at
      ) payload,c.title class_title,q.title title
      from public.quiz_assignments a join public.quiz_versions qv on qv.id=a.quiz_version_id
      join public.quizzes q on q.id=qv.quiz_id join public.classes c on c.id=a.class_id
      join public.class_memberships membership on membership.class_id=a.class_id and membership.learner_id=(select auth.uid()) and membership.status='active'
      left join public.coc_modules cm on cm.id=q.coc_module_id
      left join lateral (
        select qa.id,qa.quiz_version_id,qa.quiz_assignment_id,qa.status,qa.started_at,qa.completed_at,
          (select count(*) from public.quiz_answers ans where ans.quiz_attempt_id=qa.id) answered_count
        from private.quiz_attempt_claims claim join public.quiz_attempts qa on qa.id=claim.attempt_id
        where claim.quiz_id=q.id and qa.learner_id=(select auth.uid())
        order by (qa.status='in_progress') desc,qa.started_at desc limit 1
      ) latest on true
      join public.quiz_assignments effective on effective.id=coalesce(latest.quiz_assignment_id,a.id)
      where a.status='active' and (qv.status='published' or exists(
        select 1 from private.quiz_attempt_claims claim join public.quiz_attempts attempt on attempt.id=claim.attempt_id
        where claim.learner_id=(select auth.uid()) and claim.quiz_id=q.id and attempt.quiz_assignment_id=a.id))
        and q.archived_at is null and c.status='active'
      order by q.id,(latest.quiz_assignment_id=a.id) desc nulls last,qv.version_number desc,c.title,a.id
    ) scoped
  ),'[]'::jsonb) end
$$;
commit;
