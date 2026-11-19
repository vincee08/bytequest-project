-- Re-defense slice A1, fix round 1 (integration item b): one accepted-version
-- rule for verified practice completions.
--
-- public.practice_completion_accepted(mission, version) (20261119120000,
-- slice A2) is the single source of truth: the module states, the learner
-- curriculum projection and the analytics already call it. The practice quiz
-- functions now call it too, and the A1 helper
-- public.practice_completion_version_accepted (20261119110000), which encoded
-- the same versions, is dropped.
--
-- PL/pgSQL resolves the helper when the functions run, not when they are
-- created, so this migration may precede 20261119120000 in timestamp order;
-- the quiz functions are first called after every migration has run.
-- Bodies are otherwise unchanged from 20261119110000; grants are kept by
-- create or replace.

begin;

create or replace function public.practice_begin_quiz(p_learner uuid,p_coc text,p_id uuid,p_questions jsonb)
returns public.practice_quiz_attempts language plpgsql security invoker set search_path='' as $$
declare attempt public.practice_quiz_attempts;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_learner::text||p_coc,0));
  if not exists(select 1 from public.profiles where user_id=p_learner and role='learner' and status='active')
    or not public.practice_coc_unlocked(p_coc,p_learner) then raise exception 'PRACTICE_COC_LOCKED' using errcode='42501'; end if;
  if (select count(*) from public.practice_mission_completions c
      where c.learner_id=p_learner and left(c.mission_id,4)=p_coc
        and public.practice_completion_accepted(c.mission_id, c.contract_version))<>5 then
    raise exception 'PRACTICAL_COMPLETION_REQUIRED' using errcode='22023'; end if;
  select q.* into attempt from public.practice_coc_progress p
    join public.practice_quiz_attempts q on q.id=p.quiz_attempt_id
    where p.learner_id=p_learner and p.coc_code=p_coc;
  if found then return attempt; end if;
  select * into attempt from public.practice_quiz_attempts where learner_id=p_learner and coc_code=p_coc and status<>'submitted' for update;
  if found then
    if attempt.status='generating' and attempt.created_at<now()-interval '60 seconds' then
      update public.practice_quiz_attempts set status='active' where id=attempt.id returning * into attempt;
    end if;
    return attempt;
  end if;
  if (select count(*) from public.practice_quiz_attempts where learner_id=p_learner and created_at>now()-interval '24 hours')>=8 then
    raise exception 'PRACTICE_QUIZ_DAILY_LIMIT' using errcode='54000'; end if;
  insert into public.practice_quiz_attempts(id,learner_id,coc_code,questions) values(p_id,p_learner,p_coc,p_questions) returning * into attempt;
  return attempt;
end $$;

create or replace function public.practice_submit_quiz(p_learner uuid,p_attempt uuid,p_answers jsonb)
returns public.practice_quiz_attempts language plpgsql security invoker set search_path='' as $$
declare attempt public.practice_quiz_attempts; total integer;
begin
  if not exists(select 1 from public.profiles where user_id=p_learner and role='learner' and status='active') then
    raise exception 'ACTIVE_LEARNER_REQUIRED' using errcode='42501';
  end if;
  select * into strict attempt from public.practice_quiz_attempts where id=p_attempt and learner_id=p_learner for update;
  if attempt.status='submitted' then return attempt; end if;
  if attempt.status<>'active' or not public.practice_coc_unlocked(attempt.coc_code,p_learner) then raise exception 'QUIZ_NOT_ACTIVE'; end if;
  if jsonb_typeof(p_answers)<>'object' or (select count(*) from jsonb_each(p_answers))<>5
    or exists(select 1 from jsonb_array_elements(attempt.questions) q where p_answers->(q->>'id') is null
      or jsonb_typeof(p_answers->(q->>'id'))<>'number' or p_answers->>(q->>'id') !~ '^[0-3]$') then
    raise exception 'ANSWER_ALL_QUESTIONS' using errcode='22023'; end if;
  select count(*) into total from jsonb_array_elements(attempt.questions) q where p_answers->(q->>'id')=q->'answer';
  update public.practice_quiz_attempts set answers=p_answers, score=total, passed=total*100>=5*passing_percent,
    status='submitted',submitted_at=now() where id=p_attempt returning * into attempt;
  if attempt.passed then
    if (select count(*) from public.practice_mission_completions c
      where c.learner_id=p_learner and left(c.mission_id,4)=attempt.coc_code
        and public.practice_completion_accepted(c.mission_id, c.contract_version))<>5 then
      raise exception 'PRACTICAL_COMPLETION_REQUIRED'; end if;
    insert into public.practice_coc_progress(learner_id,coc_code,quiz_attempt_id) values(p_learner,attempt.coc_code,p_attempt) on conflict do nothing;
  end if;
  return attempt;
end $$;

drop function public.practice_completion_version_accepted(text, text, text);

notify pgrst, 'reload schema';

commit;
