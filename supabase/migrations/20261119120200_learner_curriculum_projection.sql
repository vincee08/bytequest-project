-- Re-defense revision WS3 (slice A2.3): one learner projection for Learn,
-- Practice and Progress. SECURITY INVOKER: everything is read with the
-- caller's own RLS, and every number is computed from learner_module_states
-- (the same function the evidence gate and the unlock refresh use).
--
-- progress = completed required items / required items, where required items
-- are the module's published topics and primary-linked practice missions;
-- the COC adds its practice quiz as one more item. Performance scores
-- (quizzes, assessments, homework) are never mixed into these numbers.

begin;

create function public.get_learner_curriculum()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_learner uuid := (select auth.uid());
  v_result jsonb;
begin
  if v_learner is null or not exists (
    select 1 from public.profiles p
    where p.user_id = v_learner
      and p.role = 'learner'::public.user_role
      and p.status = 'active'::public.account_status
  ) then
    raise exception 'ACTIVE_LEARNER_REQUIRED' using errcode = '42501';
  end if;

  with st as materialized (
    select * from public.learner_module_states(v_learner)
  ),
  topic_rows as (
    select t.module_id, t.id, t.sequence_order, r.id as revision_id, r.title, r.summary, r.published_at,
      exists (select 1 from public.learner_topic_progress tp
              where tp.learner_id = v_learner and tp.topic_id = t.id) as completed
    from public.curriculum_topics t
    join lateral (
      select x.id, x.title, x.summary, x.published_at
      from public.curriculum_topic_revisions x
      where x.topic_id = t.id and x.status = 'published'::public.content_publication_status
      order by x.revision_number desc
      limit 1
    ) r on true
    where t.archived_at is null
  ),
  mission_rows as (
    select l.module_id, l.mission_code, l.sequence_order,
      coalesce(m.title, l.mission_code) as title,
      coalesce(m.mission_number, nullif(regexp_replace(l.mission_code, '^coc[1-4]_m', ''), '')::integer) as mission_number,
      exists (select 1 from public.practice_mission_completions c
              where c.learner_id = v_learner and c.mission_id = l.mission_code
                and public.practice_completion_accepted(c.mission_id, c.contract_version)) as verified,
      (select count(*) from public.practice_mission_runs pr
        where pr.learner_id = v_learner and pr.mission_id = l.mission_code) as runs,
      (select min(pr.duration_seconds) from public.practice_mission_runs pr
        where pr.learner_id = v_learner and pr.mission_id = l.mission_code and pr.outcome = 'verified') as best_seconds
    from public.mission_curriculum_links l
    left join public.missions m on m.mission_code = l.mission_code
  ),
  module_rows as (
    select s.coc_code, s.sequence_order, s.completed, s.coc_unlocked, s.coc_chain_unlocked,
      s.topics_done + s.missions_done as done,
      s.topics_total + s.missions_total as total,
      s.missions_total, s.missions_done,
      jsonb_build_object(
        'id', s.module_id,
        'code', s.code,
        'title', s.title,
        'sequence_order', s.sequence_order,
        'source_reference', cm.source_reference,
        'unlocked', s.unlocked,
        'completed', s.completed,
        'lock_reason', case
          when s.unlocked then null
          when not s.coc_unlocked then null
          when prev.module_id is not null then
            'Complete Module ' || prev.sequence_order || ' · ' || prev.code || ' ' || prev.title || ' to unlock.'
          else 'Complete the previous module to unlock.'
        end,
        'no_required_items', s.topics_total + s.missions_total = 0,
        'progress', jsonb_build_object(
          'done', s.topics_done + s.missions_done,
          'total', s.topics_total + s.missions_total,
          'percent', case
            when s.topics_total + s.missions_total = 0 then case when s.completed then 100 else 0 end
            else ((s.topics_done + s.missions_done) * 100) / (s.topics_total + s.missions_total)
          end),
        'new_content', s.stored_completion and not s.requirements_met,
        'topics', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', tr.id, 'revision_id', tr.revision_id, 'title', tr.title, 'summary', tr.summary,
            'sequence_order', tr.sequence_order, 'published_at', tr.published_at, 'completed', tr.completed)
            order by tr.sequence_order, tr.id)
          from topic_rows tr where tr.module_id = s.module_id), '[]'::jsonb),
        'outcomes', coalesce((
          select jsonb_agg(jsonb_build_object('id', o.id, 'code', o.code, 'statement', o.statement)
            order by o.sequence_order)
          from public.learning_outcomes o where o.module_id = s.module_id), '[]'::jsonb),
        'missions', coalesce((
          select jsonb_agg(jsonb_build_object(
            'mission_code', mr.mission_code, 'mission_number', mr.mission_number, 'title', mr.title,
            'unlocked', s.unlocked, 'verified', mr.verified, 'runs', mr.runs, 'best_seconds', mr.best_seconds)
            order by mr.sequence_order)
          from mission_rows mr where mr.module_id = s.module_id), '[]'::jsonb)
      ) as body
    from st s
    join public.curriculum_modules cm on cm.id = s.module_id
    left join st prev on prev.module_id = s.previous_module_id
  ),
  coc_rows as (
    select c.coc_code, c.title, c.order_index,
      exists (select 1 from public.practice_coc_progress pcp
              where pcp.learner_id = v_learner and pcp.coc_code = c.coc_code) as quiz_passed,
      bool_or(mr.coc_unlocked) as unlocked,
      bool_or(mr.coc_chain_unlocked) as chain_unlocked,
      bool_and(mr.completed) as modules_completed,
      sum(mr.missions_done) = sum(mr.missions_total) as missions_verified,
      sum(mr.done)::integer as done,
      sum(mr.total)::integer as total,
      jsonb_agg(mr.body order by mr.sequence_order) as modules
    from public.coc_modules c
    join module_rows mr on mr.coc_code = c.coc_code
    group by c.coc_code, c.title, c.order_index
  )
  select jsonb_build_object(
    'generated_at', now(),
    'cocs', coalesce(jsonb_agg(jsonb_build_object(
      'coc_code', cr.coc_code,
      'title', cr.title,
      'order', cr.order_index,
      'unlocked', cr.unlocked,
      'completed', cr.modules_completed and cr.quiz_passed,
      'lock_reason', case when cr.unlocked then null else
        'Complete COC ' || (cr.order_index - 1) || ' and pass the COC ' || (cr.order_index - 1) || ' practice quiz to unlock.' end,
      'progress', jsonb_build_object(
        'done', cr.done + case when cr.quiz_passed then 1 else 0 end,
        'total', cr.total + 1,
        'percent', ((cr.done + case when cr.quiz_passed then 1 else 0 end) * 100) / (cr.total + 1)),
      'quiz', jsonb_build_object(
        'eligible', cr.chain_unlocked and cr.modules_completed and cr.missions_verified,
        'passed', cr.quiz_passed),
      'modules', cr.modules
    ) order by cr.order_index), '[]'::jsonb)
  )
  into v_result
  from coc_rows cr;

  -- Modules of a locked COC repeat the COC prerequisite.
  select jsonb_set(v_result, '{cocs}', coalesce(jsonb_agg(
    case when (c->>'unlocked')::boolean then c
    else jsonb_set(c, '{modules}', (
      select coalesce(jsonb_agg(m || jsonb_build_object('lock_reason', c->'lock_reason') order by ord), '[]'::jsonb)
      from jsonb_array_elements(c->'modules') with ordinality as mm(m, ord)))
    end order by o), '[]'::jsonb))
  into v_result
  from jsonb_array_elements(v_result->'cocs') with ordinality as cc(c, o);

  return v_result;
end
$$;

revoke all on function public.get_learner_curriculum() from public, anon;
grant execute on function public.get_learner_curriculum() to authenticated, service_role;

comment on function public.get_learner_curriculum() is
  'Learner Learn/Practice/Progress projection: COC -> module -> topics, official outcomes and practice missions, with unlock state, prerequisite text and progress (completed required items / required items). Invoker; reads with the caller''s RLS.';

notify pgrst, 'reload schema';

commit;
