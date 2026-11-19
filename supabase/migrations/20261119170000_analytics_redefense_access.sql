-- Slice A7 (Objective 6): read access needed by the SECURITY INVOKER
-- analytics functions, realtime publication entries, and supporting indexes.
-- Additive only: no learner policy is loosened, no data is rewritten, and
-- practice_quiz_attempts (answer keys) gains no client policy.
begin;
set local lock_timeout = '5s';

-- Instructors aggregate practice completions and COC practice progress of the
-- learners they teach (active membership in an active owned class); admins
-- read all. The existing learner-own policies are unchanged.
drop policy if exists practice_completion_read_staff on public.practice_mission_completions;
create policy practice_completion_read_staff on public.practice_mission_completions
  for select to authenticated
  using ((select public.is_admin()) or private.current_instructor_teaches_learner(learner_id));

drop policy if exists practice_progress_read_staff on public.practice_coc_progress;
create policy practice_progress_read_staff on public.practice_coc_progress
  for select to authenticated
  using ((select public.is_admin()) or private.current_instructor_teaches_learner(learner_id));

-- Learner competency view: a learner may read the label rows of rubric
-- criteria that were evaluated in their own released attempts. The learner
-- can already read those attempts' criterion_results (including the
-- expected_rule snapshot) under criterion_results_select_scoped, so this adds
-- no evaluator information; criteria of unreleased attempts stay hidden.
drop policy if exists rubric_criteria_learner_released_select on public.rubric_criteria;
create policy rubric_criteria_learner_released_select on public.rubric_criteria
  for select to authenticated
  using (
    (select public.is_learner())
    and exists (
      select 1
      from public.criterion_results cr
      join public.attempts a on a.id = cr.attempt_id
      join public.result_releases rr on rr.attempt_id = a.id and rr.is_current
      where cr.rubric_criterion_id = rubric_criteria.id
        and a.learner_id = (select auth.uid())
    )
  );

-- Realtime invalidation for analytics and the learner performance section.
-- Row visibility stays enforced by RLS; clients only refetch on events.
do $$
declare
  v_table text;
begin
  foreach v_table in array array['practice_mission_runs', 'learner_topic_progress', 'learner_module_completions'] loop
    if to_regclass(format('public.%I', v_table)) is null then
      raise exception 'Required realtime table public.% is missing', v_table;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = v_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', v_table);
    end if;
  end loop;
end
$$;

-- Supporting indexes for class- and period-scoped aggregation.
create index if not exists practice_mission_completions_mission_verified_idx
  on public.practice_mission_completions (mission_id, verified_at);
create index if not exists practice_mission_runs_mission_created_idx
  on public.practice_mission_runs (mission_id, created_at);
create index if not exists quiz_attempts_class_submitted_idx
  on public.quiz_attempts (class_id, submitted_at)
  where submitted_at is not null;

commit;
