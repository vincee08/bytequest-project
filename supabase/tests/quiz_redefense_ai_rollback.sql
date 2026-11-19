-- Slice A3.4: AI drafts may include scenario essays with rubrics (still
-- review-gated) and "Regenerate this question" replaces one draft question in
-- one audited step while the original stays in history. Rollback-only.
begin;
select plan(18);

create temp table qai as select
  gen_random_uuid() teacher, gen_random_uuid() other_teacher,
  (select id from public.coc_modules where coc_code = 'coc1') coc1,
  (select id from public.curriculum_modules where coc_code = 'coc1' and code = 'LO1.1') lo11,
  null::uuid quiz, null::uuid version, null::uuid manual_item, null::uuid gen1, null::uuid gen2, null::uuid replacement,
  null::uuid published_quiz, null::uuid published_version, null::uuid gen3;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',id||'@quiz-ai.invalid','',
  '{"provider":"email","providers":["email"]}'::jsonb,'{"full_name":"Quiz AI fixture"}'::jsonb,now(),now()
from qai cross join lateral (values (teacher),(other_teacher)) ids(id);
update public.profiles set role = 'instructor' where user_id in (select teacher from qai union select other_teacher from qai);
grant all on qai to authenticated, service_role;

select set_config('request.jwt.claim.sub', (select teacher::text from qai), true);
set local role authenticated;
update qai set quiz = (public.create_instructor_quiz('AI assembly check', 'Assembly', p_coc_module_id => coc1,
  p_focus => 'Explain safe component installation', p_module_ids => array[lo11])).id;
update qai set version = (select id from public.quiz_versions where quiz_id = qai.quiz);
update qai set manual_item = (public.upsert_quiz_item(version, 'true_false', 'A wrist strap reduces ESD risk.', '[]', '"true"')).id;
update qai set gen1 = (public.begin_ai_quiz_generation(version, 'openrouter', 'qa-model',
  jsonb_build_object('request_id', gen_random_uuid(), 'source_mode', 'curriculum'), 2)).id;
reset role;

select ok(not has_function_privilege('authenticated', 'public.complete_ai_quiz_draft(uuid,uuid,text,text,jsonb,uuid,text)', 'EXECUTE'),
  'AI draft completion is service-only');

set local role service_role;
select throws_ok(format('select public.complete_ai_quiz_draft(%L,%L,%L,%L,%L)', teacher, gen1, 'openrouter', 'qa-model',
  '[{"item_type":"scenario_essay","prompt":"Explain how you would seat the CPU.","options":[],"correct_answer":"","explanation":"Scoring notes.","scenario":"A workstation arrived unassembled on the bench."}]'),
  '22023', 'AI_ITEM_CONTRACT_INVALID', 'an AI essay without a rubric is rejected') from qai;
select throws_ok(format('select public.complete_ai_quiz_draft(%L,%L,%L,%L,%L)', other_teacher, gen1, 'openrouter', 'qa-model',
  '[{"item_type":"true_false","prompt":"Thermal paste improves heat transfer.","options":[],"correct_answer":"true","explanation":"It fills gaps."}]'),
  '22023', 'AI_GENERATION_STATE_DENIED', 'another instructor cannot complete this generation') from qai;
select is((public.complete_ai_quiz_draft(teacher, gen1, 'openrouter', 'qa-model', jsonb_build_array(
  jsonb_build_object('item_type', 'scenario_essay', 'prompt', 'Explain how you would seat the CPU safely.', 'options', '[]'::jsonb,
    'correct_answer', 'Mentions lever, alignment triangle and ESD strap.', 'explanation', 'Instructor scoring notes.',
    'scenario', 'A workstation arrived unassembled on your bench with an anti-static mat.',
    'min_words', 40, 'max_words', 200,
    'rubric', '[{"criterion":"Safety","description":"ESD precautions","max_points":4},{"criterion":"Procedure","description":"Correct seating","max_points":6}]'::jsonb),
  jsonb_build_object('item_type', 'multiple_choice', 'prompt', 'Which part holds the CPU?', 'options', '["Socket","PCIe slot"]'::jsonb,
    'correct_answer', 'Socket', 'explanation', 'The CPU sits in its socket.')))->>'generated_count')::int, 2,
  'curriculum AI drafts can include an essay with a rubric') from qai;
reset role;
select is((select points || ':' || jsonb_array_length(rubric) || ':' || min_words || '-' || max_words || ':' || origin::text || ':' || review_status::text
  from public.quiz_items where quiz_version_id = qai.version and item_type = 'scenario_essay'),
  '10:2:40-200:ai_generated_draft:draft', 'the AI essay keeps its rubric points and still needs instructor review') from qai;
select is((select status::text from public.ai_quiz_generations where id = qai.gen1), 'completed', 'the generation is completed') from qai;
select is((select status::text from public.quiz_versions where id = qai.version), 'draft', 'nothing is published automatically') from qai;

-- Regenerate the manual question: replaced in one step, original kept in history.
select set_config('request.jwt.claim.sub', (select teacher::text from qai), true);
set local role authenticated;
update qai set gen2 = (public.begin_ai_quiz_generation(version, 'openrouter', 'qa-model',
  jsonb_build_object('request_id', gen_random_uuid(), 'source_mode', 'curriculum', 'replace_item_id', manual_item), 1)).id;
reset role;
set local role service_role;
select throws_ok(format('select public.complete_ai_quiz_draft(%L,%L,%L,%L,%L,%L)', teacher, gen2, 'openrouter', 'qa-model',
  '[{"item_type":"true_false","prompt":"An ESD wrist strap must touch bare skin.","options":[],"correct_answer":"true","explanation":"Contact grounds the body."}]', manual_item),
  '22023', 'REMOVAL_REASON_REQUIRED', 'regeneration needs a reason') from qai;
select throws_ok(format('select public.complete_ai_quiz_draft(%L,%L,%L,%L,%L,%L,%L)', teacher, gen2, 'openrouter', 'qa-model',
  '[{"item_type":"true_false","prompt":"An ESD wrist strap must touch bare skin.","options":[],"correct_answer":"true","explanation":"Contact grounds the body."},{"item_type":"true_false","prompt":"A second replacement prompt.","options":[],"correct_answer":"true","explanation":"Extra."}]',
  manual_item, 'Ambiguous wording'),
  '22023', 'AI_ITEM_COUNT_INVALID', 'a regeneration replaces exactly one question') from qai;
update qai set replacement = ((public.complete_ai_quiz_draft(teacher, gen2, 'openrouter', 'qa-model',
  '[{"item_type":"true_false","prompt":"An ESD wrist strap must touch bare skin.","options":[],"correct_answer":"true","explanation":"Contact grounds the body."}]',
  manual_item, 'Ambiguous wording'))->'item_ids'->>0)::uuid;
reset role;
select is((select removal_reason || '|' || review_status::text || '|' || prompt from public.quiz_items where id = qai.manual_item),
  'Ambiguous wording|rejected|A wrist strap reduces ESD risk.', 'the original is removed with its reason and its text kept') from qai;
select is((select order_index from public.quiz_items where id = qai.replacement), 1,
  'the replacement takes the original position') from qai;
select is((select string_agg(prompt, ' / ' order by order_index) from public.quiz_items where quiz_version_id = qai.version and removed_at is null),
  'An ESD wrist strap must touch bare skin. / Explain how you would seat the CPU safely. / Which part holds the CPU?',
  'the active question order is preserved') from qai;
select is((select count(*)::int from public.quiz_items where quiz_version_id = qai.version), 4, 'history keeps every question row') from qai;
select is((select count(*)::int from public.audit_events where action = 'quiz_item.regenerated' and target_id = qai.replacement
  and new_value->>'original_item_id' = qai.manual_item::text and reason = 'Ambiguous wording'), 1, 'the regeneration is audited once') from qai;
select is((select count(*)::int from public.audit_events where action = 'quiz_item.removed' and target_id = qai.manual_item), 1,
  'the removal of the original is audited') from qai;
select is((select origin::text || ':' || review_status::text from public.quiz_items where id = qai.replacement), 'ai_generated_draft:draft',
  'the replacement still requires review') from qai;

-- Published content is never changed by AI.
select set_config('request.jwt.claim.sub', (select teacher::text from qai), true);
set local role authenticated;
update qai set published_quiz = (public.create_instructor_quiz('Published AI check', 'Assembly', p_coc_module_id => coc1,
  p_focus => 'Identify CPU parts')).id;
update qai set published_version = (select id from public.quiz_versions where quiz_id = qai.published_quiz);
select public.review_quiz_item((public.upsert_quiz_item(published_version, 'true_false', 'The CPU socket has a retention lever.', '[]', '"true"')).id, 'approved') from qai;
update qai set gen3 = (public.begin_ai_quiz_generation(published_version, 'openrouter', 'qa-model',
  jsonb_build_object('request_id', gen_random_uuid()), 1)).id;
select public.publish_quiz_version(published_version) from qai;
reset role;
set local role service_role;
select throws_ok(format('select public.complete_ai_quiz_draft(%L,%L,%L,%L,%L)', teacher, gen3, 'openrouter', 'qa-model',
  '[{"item_type":"true_false","prompt":"A late AI draft for a published version.","options":[],"correct_answer":"true","explanation":"Late."}]'),
  '22023', 'DRAFT_QUIZ_VERSION_REQUIRED', 'AI drafts never change a published version') from qai;
reset role;
select is((select count(*)::int from public.quiz_items where quiz_version_id = qai.published_version), 1, 'the published version is unchanged') from qai;

select * from finish();
rollback;
