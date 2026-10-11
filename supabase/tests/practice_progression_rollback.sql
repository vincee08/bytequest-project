begin;
select plan(8);
select is((select count(*)::integer from public.practice_mission_contracts),20,'all twenty work orders have server practice contracts');
select ok(not has_table_privilege('authenticated','public.practice_quiz_attempts','SELECT'),'learners cannot read answer keys');
select ok(not has_table_privilege('authenticated','public.practice_coc_progress','UPDATE'),'learners cannot alter COC completion');
select ok(not has_table_privilege('authenticated','public.practice_mission_completions','INSERT'),'learners cannot award practical completion');
select ok(not has_function_privilege('authenticated','public.practice_submit_quiz(uuid,uuid,jsonb)','EXECUTE'),'quiz grading is server-only');
select is((select count(*)::integer from pg_proc where oid in (
  'public.practice_verify_mission(uuid,text)'::regprocedure,
  'public.practice_submit_quiz(uuid,uuid,jsonb)'::regprocedure,
  'public.practice_begin_quiz(uuid,text,uuid,jsonb)'::regprocedure
) and prosecdef),0,'practice evaluators introduce no SECURITY DEFINER function');
select ok(exists(select 1 from pg_policies where tablename='practice_mission_actions' and policyname='practice_actions_progression_gate' and permissive='RESTRICTIVE'),'locked practice evidence has a restrictive RLS gate');
select ok(
  has_table_privilege('authenticated','public.practice_mission_actions','SELECT')
  and has_table_privilege('authenticated','public.practice_mission_actions','INSERT')
  and not has_table_privilege('authenticated','public.practice_mission_actions','UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
  and has_sequence_privilege('authenticated','public.practice_mission_actions_id_seq','USAGE')
  and not has_sequence_privilege('authenticated','public.practice_mission_actions_id_seq','SELECT,UPDATE'),
  'learner practice evidence grants remain append-only');
select * from finish();
rollback;
