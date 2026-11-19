-- Re-defense revision WS3 (slice A2.1): sequential module unlocking enforced
-- on the backend, with one documented completion methodology.
--
-- Methodology (shared by the learner app, the dashboard and analytics):
--   * Topic complete   : a learner_topic_progress row exists for the topic.
--   * Mission complete : a server-verified practice completion of an accepted
--                        contract version (current version, or a legacy
--                        version the practice quiz gate also accepts).
--   * Module complete  : every published (non-archived) topic and every
--                        primary-linked mission of the module is complete; a
--                        module with no required items completes as soon as it
--                        unlocks ("No required activities yet"). A durable
--                        learner_module_completions row keeps it complete when
--                        content is added later ("New content available").
--   * COC complete     : every module complete and the COC practice quiz
--                        passed (practice_coc_progress).
--   * Unlocked         : COC unlocked (every earlier COC has a
--                        practice_coc_progress row, or an active instructor COC
--                        bypass) AND (first module of the COC by sequence_order,
--                        or the previous module is complete, or a stored
--                        learner_module_unlocks row, or the active bypass).
--                        Earned unlocks and completions are stored and never
--                        deleted, so content changes never re-lock a learner;
--                        bypass access is evaluated live, so revoking a bypass
--                        ends bypass-only access without touching earned work.
--
-- No SECURITY DEFINER function is added. Learner-context calls (the RLS gate
-- and the learner projection) read through the caller's RLS; refresh writes run
-- only as service_role (trusted routes, service-only workflow functions and
-- the practice verifier) or as the migration owner.

begin;

-- ---------------------------------------------------------------------------
-- Contract versions become readable (never the definitions) so the accepted
-- version rule can be evaluated with the learner's own privileges.
-- ---------------------------------------------------------------------------
grant select (mission_id, version) on public.practice_mission_contracts to authenticated;
create policy practice_mission_contracts_version_read on public.practice_mission_contracts
  for select to authenticated using (public.is_active_user());

-- Accepted contract versions: the rule used by the practice quiz gate
-- (20261109120000): the current version, plus the COC1 M1 v1/v2 legacy versions
-- under v3 and, once the COC1 M2 assembly contract v3 is published, the COC1 M2
-- versions that count today.
-- The helpers below are PL/pgSQL on purpose: their queries go through the
-- RLS-aware plan cache. A SQL-language helper evaluated inside a PL/pgSQL
-- simple expression keeps its first plan for the whole transaction, including
-- row-security quals planned for another role.
create function public.practice_completion_accepted(p_mission text, p_version text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return exists (
    select 1
    from public.practice_mission_contracts d
    where d.mission_id = p_mission
      and (
        d.version = p_version
        or (d.mission_id = 'coc1_m1' and d.version = 'css-sag-20261109-v3'
            and p_version in ('css-sag-20261009-v1', 'css-sag-20261011-v2'))
        or (d.mission_id = 'coc1_m2' and d.version = 'css-assembly-20261119-v3'
            and p_version in ('css-sag-20261009-v1', 'css-sag-20261011-v2'))
      )
  );
end
$$;

-- Active instructor COC bypass: not revoked, active class, active membership,
-- published module version of that COC (same scope as get_bypassed_activities).
create function public.learner_coc_bypass_active(p_coc text, p_learner uuid)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return exists (
    select 1
    from public.coc_bypasses cb
    join public.module_versions mv on mv.id = cb.module_version_id
      and mv.status = 'published'::public.content_version_status
    join public.coc_modules cm on cm.id = mv.module_id and cm.coc_code = p_coc
    join public.classes c on c.id = cb.class_id and c.status = 'active'::public.class_status
    join public.class_memberships ms on ms.class_id = cb.class_id and ms.learner_id = p_learner
      and ms.status = 'active'::public.membership_status
    where cb.learner_id = p_learner
      and cb.revoked_at is null
  );
end
$$;

-- The single function that determines module unlock and completion state.
-- Topic visibility is filtered explicitly (published, not archived) so the
-- result is identical under learner RLS and under service_role.
create function public.learner_module_states(p_learner uuid, p_coc text default null)
returns table (
  module_id uuid,
  coc_code text,
  code text,
  title text,
  sequence_order integer,
  previous_module_id uuid,
  coc_chain_unlocked boolean,
  bypass_active boolean,
  coc_unlocked boolean,
  sequence_unlocked boolean,
  unlocked boolean,
  requirements_met boolean,
  completed boolean,
  stored_unlock boolean,
  stored_completion boolean,
  topics_total integer,
  topics_done integer,
  missions_total integer,
  missions_done integer
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  r record;
  v_coc text;
  v_chain boolean;
  v_bypass boolean;
  v_prev_id uuid;
  v_prev_completed boolean := false;
begin
  if p_learner is null then
    return;
  end if;
  for r in
    select
      m.id as m_id, m.coc_code as m_coc, m.code as m_code, m.title as m_title, m.sequence_order as m_seq,
      exists (select 1 from public.learner_module_unlocks u
              where u.learner_id = p_learner and u.module_id = m.id) as has_unlock,
      exists (select 1 from public.learner_module_completions mc
              where mc.learner_id = p_learner and mc.module_id = m.id) as has_completion,
      (select count(*)::integer from public.curriculum_topics t
        where t.module_id = m.id and t.archived_at is null
          and exists (select 1 from public.curriculum_topic_revisions tr
                      where tr.topic_id = t.id and tr.status = 'published'::public.content_publication_status)) as t_total,
      (select count(*)::integer from public.curriculum_topics t
        join public.learner_topic_progress tp on tp.topic_id = t.id and tp.learner_id = p_learner
        where t.module_id = m.id and t.archived_at is null
          and exists (select 1 from public.curriculum_topic_revisions tr
                      where tr.topic_id = t.id and tr.status = 'published'::public.content_publication_status)) as t_done,
      (select count(*)::integer from public.mission_curriculum_links l where l.module_id = m.id) as ms_total,
      (select count(*)::integer from public.mission_curriculum_links l
        join public.practice_mission_completions pc on pc.mission_id = l.mission_code and pc.learner_id = p_learner
        where l.module_id = m.id
          and public.practice_completion_accepted(pc.mission_id, pc.contract_version)) as ms_done
    from public.curriculum_modules m
    where p_coc is null or m.coc_code = p_coc
    order by m.coc_code, m.sequence_order
  loop
    if v_coc is distinct from r.m_coc then
      v_coc := r.m_coc;
      -- A full statement (not a simple expression), so the SQL-language
      -- practice_coc_unlocked is planned for the current role every time.
      select public.practice_coc_unlocked(r.m_coc, p_learner), public.learner_coc_bypass_active(r.m_coc, p_learner)
        into v_chain, v_bypass;
      v_prev_id := null;
      v_prev_completed := false;
    end if;
    module_id := r.m_id;
    coc_code := r.m_coc;
    code := r.m_code;
    title := r.m_title;
    sequence_order := r.m_seq;
    previous_module_id := v_prev_id;
    coc_chain_unlocked := coalesce(v_chain, false);
    bypass_active := coalesce(v_bypass, false);
    coc_unlocked := coc_chain_unlocked or bypass_active;
    sequence_unlocked := coc_unlocked and (v_prev_id is null or v_prev_completed);
    unlocked := coc_unlocked and (sequence_unlocked or r.has_unlock or bypass_active);
    stored_unlock := r.has_unlock;
    stored_completion := r.has_completion;
    topics_total := r.t_total;
    topics_done := r.t_done;
    missions_total := r.ms_total;
    missions_done := r.ms_done;
    requirements_met := r.t_done >= r.t_total and r.ms_done >= r.ms_total;
    completed := r.has_completion or (unlocked and requirements_met);
    v_prev_id := r.m_id;
    v_prev_completed := completed;
    return next;
  end loop;
end
$$;

-- Same signature, invoker and stable; now module-level (PL/pgSQL for the
-- plan-cache reason above; the verifier calls it from PL/pgSQL).
create or replace function public.practice_mission_unlocked(p_mission text, p_learner uuid)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if p_mission is null or p_learner is null or p_mission !~ '^coc[1-4]_m[1-5]$' then
    return false;
  end if;
  return coalesce((
    select s.unlocked
    from public.mission_curriculum_links l
    join public.learner_module_states(p_learner, left(p_mission, 4)) s on s.module_id = l.module_id
    where l.mission_code = p_mission
  ), false);
end
$$;
revoke all on function public.practice_mission_unlocked(text, uuid) from public, anon;
grant execute on function public.practice_mission_unlocked(text, uuid) to authenticated, service_role;

-- Restrictive evidence gate: same checks as before, module-level unlock rule.
drop policy practice_actions_progression_gate on public.practice_mission_actions;
create policy practice_actions_progression_gate on public.practice_mission_actions as restrictive
  for insert to authenticated with check (
    mission_id ~ '^coc[1-4]_m[1-5]$'
    and public.practice_mission_unlocked(mission_id, (select auth.uid()))
    and octet_length(value::text) <= 131072
  );

-- ---------------------------------------------------------------------------
-- Durable unlock and completion records (never deleted)
-- ---------------------------------------------------------------------------
create function public.refresh_learner_unlocks(p_learner uuid)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  s record;
begin
  if p_learner is null or not exists (
    select 1 from public.profiles p where p.user_id = p_learner and p.role = 'learner'::public.user_role
  ) then
    return;
  end if;
  -- Serialise concurrent refreshes for one learner so each sees the other's
  -- committed completions (READ COMMITTED takes a new snapshot per statement).
  perform pg_advisory_xact_lock(hashtextextended('bytequest.module_unlocks:' || p_learner::text, 0));
  for s in select * from public.learner_module_states(p_learner) loop
    if s.sequence_unlocked and not s.stored_unlock then
      insert into public.learner_module_unlocks(learner_id, module_id, reason)
      values (p_learner, s.module_id, 'sequence')
      on conflict (learner_id, module_id) do nothing;
    end if;
    if s.completed and not s.stored_completion then
      insert into public.learner_module_completions(learner_id, module_id)
      values (p_learner, s.module_id)
      on conflict (learner_id, module_id) do nothing;
    end if;
  end loop;
end
$$;

create function public.refresh_learner_unlocks_trigger()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform public.refresh_learner_unlocks(new.learner_id);
  return null;
end
$$;

create trigger trg_practice_completion_refreshes_unlocks
  after insert or update on public.practice_mission_completions
  for each row execute function public.refresh_learner_unlocks_trigger();
create trigger trg_topic_progress_refreshes_unlocks
  after insert or update on public.learner_topic_progress
  for each row execute function public.refresh_learner_unlocks_trigger();
create trigger trg_coc_progress_refreshes_unlocks
  after insert or update on public.practice_coc_progress
  for each row execute function public.refresh_learner_unlocks_trigger();

-- The COC practice quiz (the gate to the next COC) starts only when every
-- module of the COC is complete. With no published topics this is exactly the
-- previous five-verified-missions rule; existing attempts are unaffected.
create function public.practice_quiz_requires_complete_modules()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.learner_module_states(new.learner_id, new.coc_code) s where not s.completed
  ) then
    raise exception 'PRACTICAL_COMPLETION_REQUIRED' using errcode = '22023';
  end if;
  return new;
end
$$;

create trigger trg_practice_quiz_requires_complete_modules
  before insert on public.practice_quiz_attempts
  for each row execute function public.practice_quiz_requires_complete_modules();

-- ---------------------------------------------------------------------------
-- Cutover backfill (reason 'migration'), reusable for the hosted rollout.
-- ---------------------------------------------------------------------------
create function private.backfill_learner_module_unlocks()
returns integer
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_learner uuid;
  v_inserted integer := 0;
  v_rows integer;
begin
  -- Every module containing a completed mission or any recorded practice
  -- action, and every earlier module of the same COC.
  insert into public.learner_module_unlocks(learner_id, module_id, reason)
  select distinct e.learner_id, earlier.id, 'migration'
  from (
    select c.learner_id, c.mission_id from public.practice_mission_completions c
    union
    select a.learner_id, a.mission_id from public.practice_mission_actions a
  ) e
  join public.profiles p on p.user_id = e.learner_id and p.role = 'learner'::public.user_role
  join public.mission_curriculum_links l on l.mission_code = e.mission_id
  join public.curriculum_modules target on target.id = l.module_id
  join public.curriculum_modules earlier on earlier.coc_code = target.coc_code
    and earlier.sequence_order <= target.sequence_order
  on conflict (learner_id, module_id) do nothing;
  get diagnostics v_rows = row_count;
  v_inserted := v_inserted + v_rows;

  -- The first module of every COC that is unlocked today.
  insert into public.learner_module_unlocks(learner_id, module_id, reason)
  select p.user_id, m.id, 'migration'
  from public.profiles p
  join public.curriculum_modules m on m.sequence_order = (
    select min(x.sequence_order) from public.curriculum_modules x where x.coc_code = m.coc_code)
  where p.role = 'learner'::public.user_role
    and public.practice_coc_unlocked(m.coc_code, p.user_id)
  on conflict (learner_id, module_id) do nothing;
  get diagnostics v_rows = row_count;
  v_inserted := v_inserted + v_rows;

  -- Completions for modules already complete, and the unlocks that follow.
  for v_learner in select p.user_id from public.profiles p where p.role = 'learner'::public.user_role loop
    perform public.refresh_learner_unlocks(v_learner);
  end loop;
  return v_inserted;
end
$$;

select private.backfill_learner_module_unlocks();

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------
revoke all on function public.practice_completion_accepted(text, text) from public, anon;
revoke all on function public.learner_coc_bypass_active(text, uuid) from public, anon;
revoke all on function public.learner_module_states(uuid, text) from public, anon;
grant execute on function public.practice_completion_accepted(text, text) to authenticated, service_role;
grant execute on function public.learner_coc_bypass_active(text, uuid) to authenticated, service_role;
grant execute on function public.learner_module_states(uuid, text) to authenticated, service_role;

revoke all on function public.refresh_learner_unlocks(uuid) from public, anon, authenticated;
grant execute on function public.refresh_learner_unlocks(uuid) to service_role;
revoke all on function public.refresh_learner_unlocks_trigger() from public, anon, authenticated;
revoke all on function public.practice_quiz_requires_complete_modules() from public, anon, authenticated;
grant execute on function public.refresh_learner_unlocks_trigger(), public.practice_quiz_requires_complete_modules() to service_role;
revoke all on function private.backfill_learner_module_unlocks() from public, anon, authenticated;

-- Curriculum and progression tables were created with the schema default
-- privileges, which also give clients TRUNCATE/REFERENCES/TRIGGER/MAINTAIN.
-- Clients only ever need SELECT (writes come from service-only functions).
revoke truncate, references, trigger, maintain on
  public.curriculum_modules, public.learning_outcomes, public.curriculum_topics,
  public.curriculum_topic_revisions, public.content_publication_events, public.mission_curriculum_links,
  public.activity_curriculum_links, public.learner_topic_progress, public.learner_module_unlocks,
  public.learner_module_completions, public.practice_mission_runs, public.mission_catalog_history
  from anon, authenticated;

comment on function public.learner_module_states(uuid, text) is
  'Module unlock/completion state per learner (re-defense methodology). Used by the practice evidence gate, the unlock refresh, the COC quiz guard, topic completion and the learner projection.';
comment on function public.refresh_learner_unlocks(uuid) is
  'Service-only. Stores newly earned sequence unlocks and module completions for one learner. Never deletes.';
comment on function public.practice_completion_accepted(text, text) is
  'Accepted practice contract versions (same rule as the practice quiz gate).';

notify pgrst, 'reload schema';

commit;
