-- Rollback-only proof for final review SQL-A I3 (free trial and error) and I4
-- (definition version), on the COC4 M2 troubleshooting showcase.
--
-- The package is built inline the way the corrected publisher builds it:
--   * the snapshot's final verification test (coc4_m2_p5, retest_component)
--     gives each check "counts", keyed to the step that owns the state it
--     requires: health (setting.storage_replaced, set by the coc4_m2_p4
--     repair choice) charges step:coc4_m2_p4; close_out (the p5 close-out
--     operations) charges step:coc4_m2_p5. Those keys are added to the
--     owning step's counted_targets;
--   * the decide criterion S4 requires decision.coc4_m2_p4 one_of the choices
--     whose effects satisfy the downstream checks (replace_storage).
-- The replay change (20261120100300): in an assessment, changing a recorded
-- decision on a decide step is one correction of phase:<id>. Practice keeps
-- free revision. A failed test run still charges each step at most once.
-- Outcomes: the happy path is competent with 0 incorrect; one wrong repair,
-- a failed retest and the fix stay within the threshold (2 of 2); brute force
-- (two wrong repairs, two failed retests, then the right one) leaves S4
-- unsatisfied and the attempt not yet competent. Evidence stamped with another
-- definition version is routed to instructor review (requires_review).
begin;
select plan(20);
-- Learner calls identify as the 1.2.0 app (client version guard, 20261120100000).
select set_config('request.headers', '{"x-bytequest-app-version":"1.2.0"}', true);

create temp table dc_ctx (
  admin uuid not null default gen_random_uuid(),
  instructor uuid not null default gen_random_uuid(),
  learner uuid not null default gen_random_uuid(),
  source uuid, module_version uuid, activity uuid, rubric uuid, class uuid, assignment uuid, practice_assignment uuid
) on commit drop;
insert into dc_ctx default values;
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select '00000000-0000-0000-0000-000000000000'::uuid, id, 'authenticated', 'authenticated',
  'decision-corrections-' || id || '@bytequest.invalid', '', '{"provider":"email","providers":["email"]}'::jsonb,
  '{"full_name":"Decision corrections rollback fixture"}'::jsonb, now(), now()
from dc_ctx cross join lateral (values (admin), (instructor), (learner)) u(id);
update public.profiles set role = 'admin' where user_id = (select admin from dc_ctx);
update public.profiles set role = 'instructor' where user_id = (select instructor from dc_ctx);

-- The COC4 M2 contract snapshot with counts on the final verification test.
create temp table dc_snapshot on commit drop as
select c.version,
  jsonb_set(c.definition, '{phases}', (
    select jsonb_agg(case when p->>'id' = 'coc4_m2_p5' then
        jsonb_set(p, '{presentation,equipment,checks}', (
          select jsonb_agg(case ch->>'id'
              when 'health' then ch || '{"counts":"step:coc4_m2_p4"}'::jsonb
              when 'close_out' then ch || '{"counts":"step:coc4_m2_p5"}'::jsonb
              else ch end order by o)
          from jsonb_array_elements(p->'presentation'->'equipment'->'checks') with ordinality x(ch, o)))
      else p end order by po)
    from jsonb_array_elements(c.definition->'phases') with ordinality y(p, po))) as definition
from public.practice_mission_contracts c where c.mission_id = 'coc4_m2';

-- The five step criteria as the publisher generates them for COC4 M2, with
-- the decision condition on S4 and the check keys in S4/S5 counted targets.
create temp table dc_criteria(criteria jsonb) on commit drop;
insert into dc_criteria
select jsonb_agg(jsonb_build_object(
    'criterion_code', code, 'title', title, 'description', title || '.',
    'source_trace', 'LO4.3 Diagnose faults of computer systems · PC 3.1, 3.2 · Rollback fixture.',
    'evidence_rule', jsonb_build_object('operator', 'simulation_condition', 'phase_ids', jsonb_build_array(phase),
      'conditions', conditions, 'counted_targets', counted, 'max_incorrect', 2),
    'scoring_rule', '{"status":"APPROVED","method":"binary","satisfied_value":1,"not_satisfied_value":0,"classification":"TECHNICAL_BINARY_ENCODING","note":"1/0 encodes SATISFIED/NOT SATISFIED only; it is not a TESDA percentage or criterion weight."}'::jsonb,
    'max_value', 1, 'order_index', n, 'is_required', true) order by n)
from (values
  (1, 'COC4_M2_S1', 'Inspect symptom and component', 'coc4_m2_p1',
    '[{"path":"setting.contingency_ready","value":true},{"path":"fact.component_seating_fact","value":true},{"path":"fact.event_indicator_fact","value":true}]'::jsonb,
    '["phase:coc4_m2_p1","operation:protect_service_data"]'::jsonb),
  (2, 'COC4_M2_S2', 'Select tool and run test', 'coc4_m2_p2', '[]'::jsonb, '["phase:coc4_m2_p2"]'::jsonb),
  (3, 'COC4_M2_S3', 'Interpret result', 'coc4_m2_p3', '[]'::jsonb, '["phase:coc4_m2_p3"]'::jsonb),
  (4, 'COC4_M2_S4', 'Identify fault', 'coc4_m2_p4',
    '[{"path":"decision.coc4_m2_p4","operator":"one_of","value":["replace_storage"]}]'::jsonb,
    '["phase:coc4_m2_p4","step:coc4_m2_p4"]'::jsonb),
  (5, 'COC4_M2_S5', 'Repair and verify', 'coc4_m2_p5', '[{"path":"result.retest_component","value":true}]'::jsonb,
    '["phase:coc4_m2_p5","operation:close_work_area","operation:prepare_service_report","step:coc4_m2_p5"]'::jsonb)
) t(n, code, title, phase, conditions, counted);

with s as (
  insert into public.tesda_sources(qualification_code, title, edition, source_reference, status,
    validation_notes, created_by, approved_by, approved_at, activated_by, activated_at)
  select 'ROLLBACK-' || left(gen_random_uuid()::text, 8), 'Rollback-only decision corrections source',
    'TEST_ONLY', 'Rollback fixture; never a production TESDA source', 'active', 'TEST_ONLY_ROLLBACK_FIXTURE',
    admin, admin, now(), admin, now() from dc_ctx
  returning id)
update dc_ctx set source = s.id from s;
with m as (
  insert into public.module_versions(module_id, tesda_source_id, version_number, title, source_trace,
    content_metadata, status, created_by, published_by, published_at)
  select c.id, x.source, coalesce((select max(version_number) from public.module_versions mv where mv.module_id = c.id), 0) + 1,
    'Rollback decision corrections module',
    jsonb_build_object('source_classification', 'TEST_ONLY', 'note', 'Rollback fixture'),
    jsonb_build_object('assessment_engine', 'simulation_replay_v1'), 'draft', x.admin, null, null
  from dc_ctx x cross join public.coc_modules c where c.coc_code = 'coc4'
  returning id)
update dc_ctx set module_version = m.id from m;
with a as (
  insert into public.activity_versions(mission_id, module_version_id, version_number, title, delivery_mode,
    learner_payload, evaluator_config, status, created_by, published_by, published_at)
  select ms.id, x.module_version,
    coalesce((select max(version_number) from public.activity_versions av where av.mission_id = ms.id), 0) + 1,
    'Diagnose and Repair Hardware Faults — simulation assessment', 'assessment',
    jsonb_build_object('mission_id', 'coc4_m2', 'definition_version', s.version, 'mode', 'assessment'),
    jsonb_build_object('engine', 'simulation_replay_v1', 'simulation_definition', s.definition,
      'contract_version', s.version, 'scoring_method', 'binary_sum', 'competency_method', 'all_required',
      'client_score_authoritative', false),
    'draft', x.admin, null, null
  from dc_ctx x cross join dc_snapshot s cross join public.missions ms
  where ms.mission_code = 'coc4_m2'
  returning id)
update dc_ctx set activity = a.id from a;
with r as (
  insert into public.rubric_versions(activity_version_id, tesda_source_id, version_number, title, status, created_by)
  select activity, source, 1, 'COC4_M2 simulation step rubric', 'draft', admin from dc_ctx
  returning id)
update dc_ctx set rubric = r.id from r;
insert into public.rubric_criteria(rubric_version_id, criterion_code, title, description, source_trace,
  evidence_rule, scoring_rule, max_value, order_index, is_required)
select x.rubric, c->>'criterion_code', c->>'title', c->>'description', c->>'source_trace',
  c->'evidence_rule', c->'scoring_rule', (c->>'max_value')::numeric, (c->>'order_index')::integer,
  (c->>'is_required')::boolean
from dc_ctx x, dc_criteria s, jsonb_array_elements(s.criteria) c;
insert into public.activity_curriculum_links(activity_version_id, module_id, delivery_kind)
select x.activity, l.module_id, 'simulation'
from dc_ctx x join public.mission_curriculum_links l on l.mission_code = 'coc4_m2';

-- Published and approved through the governed RPCs; approval validates every rule.
create temp table dc_approval(error text) on commit drop;
grant select on dc_ctx to authenticated, service_role;
grant insert on dc_approval to authenticated;
select set_config('request.jwt.claim.sub', (select admin::text from dc_ctx), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
do $$
begin
  perform public.publish_module_version((select module_version from dc_ctx),
    'Rollback publication of the decision corrections module');
  perform public.publish_activity_version((select activity from dc_ctx),
    'Rollback publication of the COC4 M2 simulation assessment');
  perform public.approve_rubric_version((select rubric from dc_ctx), 'binary_sum',
    jsonb_build_object('status', 'APPROVED', 'method', 'all_required',
      'classification', 'PROJECT_APPROVED_OPERATIONAL_RULE', 'official_numeric_threshold', null,
      'step_threshold', 'At most two incorrect attempts per step; safety-critical steps none (owner decision 7).'),
    'Rollback approval of the COC4 M2 step rubric with counts and the decision condition');
exception when others then
  insert into dc_approval values (sqlerrm);
end $$;
reset role;
select is((select status::text || coalesce((select ' ' || string_agg(error, ',') from dc_approval), '')
    from public.rubric_versions where id = (select rubric from dc_ctx)),
  'approved', 'the package with check counts and the decision condition passes governed approval');

with c as (
  insert into public.classes(title, instructor_id, created_by)
  select 'Rollback decision corrections class', instructor, instructor from dc_ctx returning id)
update dc_ctx set class = c.id from c;
insert into public.class_memberships(class_id, learner_id, enrolled_by)
select class, learner, instructor from dc_ctx;
with s as (
  insert into public.assignments(class_id, activity_version_id, rubric_version_id, assignment_type, title, assigned_by)
  select class, activity, rubric, t::public.assignment_type, n, instructor
  from dc_ctx cross join lateral (values ('assessment', 'COC4 M2 simulation assessment'),
    ('practice', 'COC4 M2 class practice')) v(t, n)
  returning id, assignment_type)
update dc_ctx set assignment = (select id from s where assignment_type = 'assessment'),
  practice_assignment = (select id from s where assignment_type = 'practice');

create temp table dc_step(name text primary key, phase text, kind text, target text, value jsonb) on commit drop;
insert into dc_step values
('seating', 'coc4_m2_p1', 'diagnostic_action', 'inspect_component_seating', '{}'),
('indicator', 'coc4_m2_p1', 'diagnostic_action', 'inspect_event_indicator', '{}'),
('backup', 'coc4_m2_p1', 'equipment_operation', 'protect_service_data', '{}'),
('memory_probe', 'coc4_m2_p2', 'diagnostic_action', 'run_memory_probe', '{}'),
('storage_health', 'coc4_m2_p2', 'diagnostic_action', 'inspect_storage_health', '{}'),
('power_state', 'coc4_m2_p2', 'diagnostic_action', 'measure_power_state', '{}'),
('interpret', 'coc4_m2_p3', 'result_interpreted', 'coc4_m2_p3',
  '{"interpretation":"Storage health reports 18 pending sectors; memory and power measure normal."}'),
('replace_storage', 'coc4_m2_p4', 'scenario_decision', 'replace_storage', '{}'),
('replace_memory', 'coc4_m2_p4', 'scenario_decision', 'replace_memory', '{}'),
('replace_supply', 'coc4_m2_p4', 'scenario_decision', 'replace_supply', '{}'),
('close_area', 'coc4_m2_p5', 'equipment_operation', 'close_work_area', '{}'),
('report', 'coc4_m2_p5', 'equipment_operation', 'prepare_service_report', '{}'),
('retest_start', 'coc4_m2_p5', 'test_started', 'retest_component', '{"test_status":"running"}'),
('retest_done', 'coc4_m2_p5', 'test_completed', 'retest_component', '{"test_status":"completed"}'),
('revise_p4', 'coc4_m2_p5', 'review_returned', 'coc4_m2_p4', '{"input_method":"phase_menu"}');

create temp table dc_run(name text primary key, steps text[], attempt uuid, stamp text,
  practice boolean not null default false) on commit drop;
create function pg_temp.dc_steps(variadic p_tail text[]) returns text[] language sql immutable as $$
  select array['seating','indicator','backup','memory_probe','storage_health','power_state','interpret'] || p_tail
$$;
insert into dc_run(name, steps) values
('happy', pg_temp.dc_steps('replace_storage','close_area','report','retest_start','retest_done')),
('one_wrong_repair', pg_temp.dc_steps('replace_memory','close_area','report','retest_start','retest_done',
  'revise_p4','replace_storage','retest_start','retest_done')),
('brute_force', pg_temp.dc_steps('replace_memory','close_area','report','retest_start','retest_done',
  'revise_p4','replace_supply','retest_start','retest_done',
  'revise_p4','replace_storage','retest_start','retest_done')),
('changed_before_test', pg_temp.dc_steps('replace_memory','replace_storage','close_area','report','retest_start','retest_done')),
('same_decision_again', pg_temp.dc_steps('replace_storage','replace_storage','close_area','report','retest_start','retest_done')),
('wrong_repair_submitted', pg_temp.dc_steps('replace_memory','close_area','report','retest_start','retest_done'));
insert into dc_run(name, steps, stamp)
select 'foreign_version', steps, 'css-sag-20261009-v0' from dc_run where name = 'happy'
union all
select 'stamped_current', steps, (select version from dc_snapshot) from dc_run where name = 'happy';
insert into dc_run(name, steps, practice)
select 'practice_brute_force', steps, true from dc_run where name = 'brute_force';
grant select, update on dc_run, dc_step to authenticated;
grant select on dc_run to service_role;

-- The learner takes the assessment once per run through the normal RPCs, as
-- the app records it (attempt_started first, then the simulation actions).
select set_config('request.jwt.claim.sub', (select learner::text from dc_ctx), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
do $$
declare v_run record; v_attempt uuid; v_key uuid;
begin
  for v_run in select name, steps, stamp, practice from dc_run order by name loop
    v_key := gen_random_uuid();
    select id into v_attempt from public.start_attempt(
      case when v_run.practice then (select practice_assignment from dc_ctx) else (select assignment from dc_ctx) end, v_key);
    perform public.append_attempt_action(v_attempt, 1, 'attempt_started', (select activity::text from dc_ctx),
      jsonb_build_object('assignment_type', case when v_run.practice then 'practice' else 'assessment' end,
        'client_start_key', v_key), clock_timestamp());
    for i in 1..array_length(v_run.steps, 1) loop
      perform public.append_attempt_action(v_attempt, i + 1, s.kind, s.target,
        s.value || jsonb_build_object('phase_id', s.phase, 'mission_id', 'coc4_m2',
          'runtime_action_type', coalesce(s.value->>'runtime_action_type', s.kind),
          'client_action_id', v_run.name || '-' || i)
        || case when v_run.stamp is null then '{}'::jsonb else jsonb_build_object('definition_version', v_run.stamp) end,
        clock_timestamp())
      from dc_step s where s.name = v_run.steps[i];
    end loop;
    perform public.submit_attempt(v_attempt, gen_random_uuid(), 600);
    update dc_run set attempt = v_attempt where name = v_run.name;
  end loop;
end $$;
reset role;
-- Class practice is evaluated on request by the server (service role).
set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select count(public.evaluate_submitted_attempt(attempt)) from dc_run where practice;
reset role;
select set_config('request.jwt.claim.role', '', true);

create function pg_temp.dc_not_satisfied(p_run text) returns text[] language sql stable as $$
  select coalesce(array_agg(rc.criterion_code order by rc.order_index), '{}')
  from public.criterion_results cr join public.rubric_criteria rc on rc.id = cr.rubric_criterion_id
  where cr.attempt_id = (select attempt from dc_run where name = p_run) and cr.observation <> 'satisfied'
$$;
create function pg_temp.dc_outcome(p_run text) returns text language sql stable as $$
  select sr.outcome::text from public.score_revisions sr
  where sr.attempt_id = (select attempt from dc_run where name = p_run) and sr.revision_type = 'automated_provisional'
$$;
create function pg_temp.dc_s4(p_run text) returns jsonb language sql stable as $$
  select jsonb_build_object('observation', cr.observation,
    'incorrect_total', cr.observed_evidence->'incorrect_total',
    'decision', cr.observed_evidence->'incorrect_by_target'->'phase:coc4_m2_p4',
    'checks', cr.observed_evidence->'incorrect_by_target'->'step:coc4_m2_p4')
  from public.criterion_results cr join public.rubric_criteria rc on rc.id = cr.rubric_criterion_id
  where cr.attempt_id = (select attempt from dc_run where name = p_run) and rc.criterion_code = 'COC4_M2_S4'
$$;
create function pg_temp.dc_actions(p_run text) returns jsonb language sql stable as $$
  select jsonb_agg(jsonb_build_object('action_type', s.kind, 'target', s.target, 'phase_id', s.phase,
      'value', s.value || jsonb_build_object('runtime_action_type', s.kind), 'occurred_at', now()) order by u.n)
  from dc_run r cross join lateral unnest(r.steps) with ordinality u(step, n) join dc_step s on s.name = u.step
  where r.name = p_run
$$;

select is(pg_temp.dc_not_satisfied('happy') || array[pg_temp.dc_outcome('happy')], array['competent'],
  'the happy path satisfies every step and is competent');
select is((select sum((cr.observed_evidence->>'incorrect_total')::integer)::integer from public.criterion_results cr
    where cr.attempt_id = (select attempt from dc_run where name = 'happy')), 0,
  'the happy path records 0 incorrect attempts');
select is(pg_temp.dc_not_satisfied('one_wrong_repair') || array[pg_temp.dc_outcome('one_wrong_repair')], array['competent'],
  'one wrong repair, a failed retest and the fix stay within the threshold');
select is(pg_temp.dc_s4('one_wrong_repair'), jsonb_build_object('observation', 'satisfied', 'incorrect_total', 2,
    'decision', '{"invalid": 0, "corrections": 1, "failed_checks": 0}'::jsonb,
    'checks', '{"invalid": 0, "corrections": 0, "failed_checks": 1}'::jsonb),
  'the fix is one correction of the decide step and the failed retest charges it once (2 of 2)');
select is(pg_temp.dc_not_satisfied('brute_force'), array['COC4_M2_S4'],
  'brute force (two wrong repairs, two failed retests, then the right one) leaves S4 unsatisfied');
select is(pg_temp.dc_outcome('brute_force'), 'not_yet_competent', 'brute force is not yet competent');
select is(pg_temp.dc_s4('brute_force'), jsonb_build_object('observation', 'not_satisfied', 'incorrect_total', 4,
    'decision', '{"invalid": 0, "corrections": 2, "failed_checks": 0}'::jsonb,
    'checks', '{"invalid": 0, "corrections": 0, "failed_checks": 2}'::jsonb),
  'each changed decision is one correction and each failed retest charges the step once');
select is(pg_temp.dc_s4('changed_before_test')->'incorrect_total', '1'::jsonb,
  'changing the decision before any retest is one correction');
select is(pg_temp.dc_outcome('changed_before_test'), 'competent', 'one changed decision stays within the threshold');
select is(pg_temp.dc_s4('same_decision_again')->'incorrect_total', '0'::jsonb,
  'confirming the same decision again is not a correction');
select is(pg_temp.dc_not_satisfied('wrong_repair_submitted'), array['COC4_M2_S4', 'COC4_M2_S5'],
  'a wrong repair submitted as is fails the decision condition and the verification');

-- Practice keeps free revision; the pure replay shows the difference.
select is(pg_temp.dc_s4('practice_brute_force'), jsonb_build_object('observation', 'satisfied', 'incorrect_total', 2,
    'decision', '{"invalid": 0, "corrections": 0, "failed_checks": 0}'::jsonb,
    'checks', '{"invalid": 0, "corrections": 0, "failed_checks": 2}'::jsonb),
  'a class practice attempt does not count changed decisions (practice unchanged)');
select is(private.simulation_replay((select definition from dc_snapshot), pg_temp.dc_actions('brute_force'))->'corrections',
  '{}'::jsonb, 'practice replay (two arguments) counts no decision correction');
select is(private.simulation_replay((select definition from dc_snapshot), pg_temp.dc_actions('brute_force'), true)->'corrections',
  '{"phase:coc4_m2_p4": 2}'::jsonb, 'assessment replay counts each changed decision once');
select is(private.simulation_replay((select definition from dc_snapshot), pg_temp.dc_actions('brute_force'), false),
  private.simulation_replay((select definition from dc_snapshot), pg_temp.dc_actions('brute_force')),
  'the practice replay is the two-argument replay, unchanged');
select is(private.simulation_replay((select definition from dc_snapshot), pg_temp.dc_actions('brute_force'), true)->'failed_checks',
  '{"step:coc4_m2_p4": 2}'::jsonb, 'two failed retests charge the decide step twice, once per run');

-- I4: evidence from another definition version goes to instructor review.
select is((select string_agg(distinct cr.observation::text, ',') from public.criterion_results cr
    where cr.attempt_id = (select attempt from dc_run where name = 'foreign_version')),
  'requires_review', 'evidence stamped with another definition version is routed to instructor review');
select is((select cr.observed_evidence->'definition_version_mismatch' from public.criterion_results cr
    join public.rubric_criteria rc on rc.id = cr.rubric_criterion_id
    where cr.attempt_id = (select attempt from dc_run where name = 'foreign_version') and rc.criterion_code = 'COC4_M2_S1'),
  jsonb_build_object('contract_version', (select version from dc_snapshot), 'foreign_action_count', 12),
  'the review reason names the contract version and the foreign actions');
select is(pg_temp.dc_not_satisfied('stamped_current') || array[pg_temp.dc_outcome('stamped_current')], array['competent'],
  'evidence stamped with the snapshot''s own version is evaluated normally');

select * from finish();
rollback;
