-- Appended INSIDE homework_quiz_deadlines_rollback's transaction by the strict
-- isolated-QA runner. Reuses only its temporary actors/records and server clock.
select pg_temp.assert((select count(*)=6 from public.notifications where event_key like 'quiz.assigned:%' and metadata->>'class_id' in(class_a::text,class_b::text)), 'quiz assignments notify exactly eligible class learners') from activity_test;
select pg_temp.assert((select count(*)=3 from public.notifications where event_key='homework.publish:'||homework::text), 'homework publication notifies enrolled learners') from activity_test;
select pg_temp.assert((select count(*)=1 from public.notifications where event_key='homework.graded:'||submission_b::text and user_id=learner_b), 'grading notifies only the submitted learner') from activity_test;
select pg_temp.assert((select count(*)=3 from public.notifications where event_key like 'quiz.reopened:'||assignment_a::text||':%' and metadata->>'class_id'=class_a::text), 'reopening notifies only the selected class') from activity_test;
select pg_temp.assert((select count(*)=0 from public.notifications where user_id in(outsider,teacher,foreign_teacher)), 'no unrelated learner or instructor notifications') from activity_test;
-- Duplicate delivery/repeated publication does not create another notification.
insert into public.audit_events(actor_id,actor_role,action,target_type,target_id,new_value)
select teacher,'instructor','quiz.assigned','quiz_assignment',assignment_a,'{}'::jsonb from activity_test;
set local role service_role;
select public.manage_homework(teacher,'publish',jsonb_build_object('assignment_id',homework)) from activity_test;
reset role;
select pg_temp.assert((select count(*)=3 from public.notifications where event_key='quiz.assigned:'||assignment_a::text),'retry is idempotent for each recipient') from activity_test;
select pg_temp.assert((select count(*)=3 from public.notifications where event_key='homework.publish:'||homework::text),'repeated publication is idempotent') from activity_test;
select set_config('request.jwt.claim.sub',(select learner_b::text from activity_test),true);
set local role authenticated;
select pg_temp.assert((select jsonb_array_length(payload->'eligible_assignments')=2 from jsonb_array_elements(public.get_available_learner_quizzes()) payload where payload->>'quiz_id'=quiz::text),'canonical quiz includes both authorized class assignment references') from activity_test;
select pg_temp.assert((select count(*)=0 from public.quiz_versions),'notification links must not broaden staff-only version access');
reset role;
select set_config('request.jwt.claim.sub',(select learner_a::text from activity_test),true);
set local role authenticated;
select pg_temp.assert((select count(*)>0 and bool_and(user_id=(select learner_a from activity_test)) from public.notifications),'RLS selects own notifications only');
select pg_temp.denied('insert into public.notifications(user_id,title,message) values(auth.uid(),''Forged'',''Fake assignment'')','permission denied');
select pg_temp.denied('update public.notifications set title=''Spoofed title''','permission denied');
update public.notifications set is_read=true,read_at='1900-01-01' where event_key='quiz.assigned:'||(select assignment_a::text from activity_test);
select pg_temp.assert((select read_at>'2026-01-01' and is_read from public.notifications where event_key='quiz.assigned:'||assignment_a::text),'read timestamp is authoritative') from activity_test;
create temp table saved_notification_time as select id,read_at from public.notifications where is_read;
update public.notifications set is_read=true,read_at='1900-01-01' where is_read;
select pg_temp.assert(not exists(select 1 from public.notifications n join saved_notification_time s using(id) where n.read_at<>s.read_at),'read retry preserves original read time');
update public.notifications set is_read=true where user_id=(select learner_b from activity_test);
select pg_temp.assert((select count(*)>0 from public.notifications where not is_read),'another recipient cannot mark my notifications');
update public.notifications set is_read=true where not is_read;
select pg_temp.assert((select count(*)=0 from public.notifications where not is_read),'mark-all clears own unread count');
reset role;
select pg_temp.assert((select count(*)>0 from public.notifications where user_id=learner_b and not is_read),'mark-all does not affect other learners') from activity_test;
-- Notification history remains readable by its recipient after revocation;
-- the destination independently rejects access. No notification grants rights.
update public.class_memberships set status='deactivated',deactivated_at=now(),deactivated_by=(select teacher from activity_test),deactivation_reason='Notification access regression'
where learner_id=(select learner_a from activity_test);
select set_config('request.jwt.claim.sub',(select learner_a::text from activity_test),true);
set local role authenticated;
select pg_temp.assert((select count(*)=0 from public.homework_assignments),'revoked homework link cannot load instructions');
select pg_temp.assert(jsonb_array_length(public.get_available_learner_quizzes())=0,'revoked quiz link cannot load a quiz');
select pg_temp.assert((select count(*)>0 from public.notifications),'own read history persists independently of access');
reset role;
-- Late-join policy: lists use live membership, no retrospective alert batch.
insert into public.class_memberships(class_id,learner_id,enrolled_by)
select class_a,outsider,teacher from activity_test;
select set_config('request.jwt.claim.sub',(select outsider::text from activity_test),true);
set local role authenticated;
select pg_temp.assert((select count(*)>0 from public.homework_assignments),'late join sees current published homework');
select pg_temp.assert((select count(*)=0 from public.notifications),'late join does not receive misleading historical new alerts');
reset role;
