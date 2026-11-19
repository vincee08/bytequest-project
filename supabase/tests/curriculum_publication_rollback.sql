-- Curriculum content publication workflow (re-defense slice A2.2). Rollback-only.
-- Draft -> Submitted -> Evaluated -> Finalized -> Approved -> Published, with
-- needs-revision, unpublish/republish and archive; plus learner topic completion.
begin;
select plan(57);

create function pg_temp.cp_learner(p_tag text) returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users(instance_id, id, aud, role, email, encrypted_password,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000'::uuid, v_id, 'authenticated', 'authenticated',
    'cp-' || p_tag || '-' || v_id || '@bytequest.invalid', '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', 'CP ' || p_tag), now(), now());
  return v_id;
end $$;

create temporary table cp_ctx (key text primary key, id uuid);
grant select, insert, update on cp_ctx to authenticated, service_role;
insert into cp_ctx values
  ('admin', (select user_id from public.profiles where email = 'qa.admin@bytequest.local')),
  ('author', (select user_id from public.profiles where email = 'qa.instructor@bytequest.local')),
  ('other', (select user_id from public.profiles where email = 'qa.instructor2@bytequest.local')),
  ('learner', pg_temp.cp_learner('reader')),
  ('lo11', (select id from public.curriculum_modules where coc_code = 'coc1' and code = 'LO1.1')),
  ('lo12', (select id from public.curriculum_modules where coc_code = 'coc1' and code = 'LO1.2')),
  ('pc14', (select o.id from public.learning_outcomes o join public.curriculum_modules m on m.id = o.module_id
            where m.coc_code = 'coc1' and m.code = 'LO1.1' and o.code = '1.4')),
  ('pc31', (select o.id from public.learning_outcomes o join public.curriculum_modules m on m.id = o.module_id
            where m.coc_code = 'coc1' and m.code = 'LO1.2' and o.code = '3.1'));
create function pg_temp.cp(p_key text) returns uuid language sql stable as $$ select id from cp_ctx where key = p_key $$;

-- Calls the service-only workflow function exactly as the trusted route does.
create function pg_temp.cp_do(p_actor text, p_action text, p_payload jsonb) returns jsonb language sql as $$
  select public.manage_curriculum_content(pg_temp.cp(p_actor), p_action, p_payload)
$$;
create function pg_temp.cp_status(p_revision uuid) returns text language sql stable as $$
  select status::text from public.curriculum_topic_revisions where id = p_revision
$$;

select has_function('public', 'manage_curriculum_content', array['uuid', 'text', 'jsonb'], 'manage_curriculum_content exists');
select ok(not has_function_privilege('authenticated', 'public.manage_curriculum_content(uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.manage_curriculum_content(uuid,text,jsonb)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.manage_curriculum_content(uuid,text,jsonb)', 'EXECUTE'),
  'the workflow function is service-only');
select is((select prosecdef from pg_proc where oid = 'public.manage_curriculum_content(uuid,text,jsonb)'::regprocedure), false,
  'the workflow function is SECURITY INVOKER');

set local role service_role;

-- ---------------------------------------------------------------------------
-- Create and edit a draft
-- ---------------------------------------------------------------------------
insert into cp_ctx
select 'topic', (r->'topic'->>'id')::uuid from (select pg_temp.cp_do('author', 'create_topic', jsonb_build_object(
  'module_id', pg_temp.cp('lo11'), 'title', 'Electrostatic discharge precautions',
  'summary', 'Why the wrist strap and anti-static mat come first.',
  'body_markdown', '# ESD\n\nWear the **wrist strap**.', 'outcome_ids', jsonb_build_array(pg_temp.cp('pc14')))) r) s;
insert into cp_ctx select 'rev1', id from public.curriculum_topic_revisions where topic_id = pg_temp.cp('topic');
select is(pg_temp.cp_status(pg_temp.cp('rev1')), 'draft', 'an instructor creates a topic as a draft revision 1');
select is((select created_by from public.curriculum_topics where id = pg_temp.cp('topic')), pg_temp.cp('author'),
  'the topic records its author');
select is((select outcome_ids from public.curriculum_topic_revisions where id = pg_temp.cp('rev1')), array[pg_temp.cp('pc14')],
  'selected learning outcomes are stored on the revision');
select throws_ok($$select pg_temp.cp_do('author', 'create_topic', jsonb_build_object('module_id', pg_temp.cp('lo11'),
  'title', 'Cross-module outcome', 'outcome_ids', jsonb_build_array(pg_temp.cp('pc31'))))$$,
  '22023', 'OUTCOME_NOT_IN_MODULE', 'a learning outcome from another module is rejected');
select throws_ok($$select pg_temp.cp_do('learner', 'create_topic', jsonb_build_object('module_id', pg_temp.cp('lo11'), 'title', 'Learner topic'))$$,
  '42501', null, 'learners cannot author curriculum topics');
select lives_ok($$select pg_temp.cp_do('author', 'edit_revision', jsonb_build_object('revision_id', pg_temp.cp('rev1'),
  'title', 'ESD precautions before assembly'))$$, 'the author edits a draft in place');
select is((select title || ':' || revision_number from public.curriculum_topic_revisions where id = pg_temp.cp('rev1')),
  'ESD precautions before assembly:1', 'editing a draft keeps revision 1');
select throws_ok($$select pg_temp.cp_do('other', 'edit_revision', jsonb_build_object('revision_id', pg_temp.cp('rev1'), 'title', 'Hijack'))$$,
  '42501', null, 'another instructor cannot edit the draft');

-- ---------------------------------------------------------------------------
-- Stages cannot be skipped and roles are enforced
-- ---------------------------------------------------------------------------
select throws_ok($$select pg_temp.cp_do('admin', 'publish', jsonb_build_object('revision_id', pg_temp.cp('rev1')))$$,
  '55000', 'TRANSITION_NOT_ALLOWED', 'draft -> published is impossible even for an admin');
select throws_ok($$select pg_temp.cp_do('admin', 'approve', jsonb_build_object('revision_id', pg_temp.cp('rev1')))$$,
  '55000', 'TRANSITION_NOT_ALLOWED', 'draft -> approved is impossible');
select throws_ok($$select pg_temp.cp_do('author', 'publish', jsonb_build_object('revision_id', pg_temp.cp('rev1')))$$,
  '42501', null, 'an instructor cannot publish');
select throws_ok($$select pg_temp.cp_do('other', 'submit', jsonb_build_object('revision_id', pg_temp.cp('rev1')))$$,
  '42501', null, 'only the author submits');
select lives_ok($$select pg_temp.cp_do('author', 'submit', jsonb_build_object('revision_id', pg_temp.cp('rev1')))$$,
  'the author submits the draft');
select is(pg_temp.cp_status(pg_temp.cp('rev1')), 'submitted', 'draft -> submitted');
select throws_ok($$select pg_temp.cp_do('author', 'edit_revision', jsonb_build_object('revision_id', pg_temp.cp('rev1'), 'title', 'Late edit'))$$,
  '55000', 'REVISION_LOCKED', 'submitted content is locked');
select throws_ok($$select pg_temp.cp_do('author', 'evaluate', jsonb_build_object('revision_id', pg_temp.cp('rev1'),
  'result', 'passed', 'notes', 'Looks complete and accurate.'))$$, '42501', null, 'an instructor cannot evaluate');
select throws_ok($$select pg_temp.cp_do('admin', 'evaluate', jsonb_build_object('revision_id', pg_temp.cp('rev1'),
  'result', 'passed', 'notes', 'Short'))$$, '22023', 'EVALUATION_NOTES_REQUIRED', 'evaluation needs notes of at least 10 characters');
select throws_ok($$select pg_temp.cp_do('admin', 'evaluate', jsonb_build_object('revision_id', pg_temp.cp('rev1'),
  'result', 'maybe', 'notes', 'Not a valid evaluation result.'))$$, '22023', 'EVALUATION_RESULT_INVALID', 'evaluation result must be passed or needs_revision');
select throws_ok($$select pg_temp.cp_do('author', 'finalize', jsonb_build_object('revision_id', pg_temp.cp('rev1')))$$,
  '55000', 'TRANSITION_NOT_ALLOWED', 'submitted -> finalized skips evaluation and is impossible');

-- Needs revision loop
select lives_ok($$select pg_temp.cp_do('admin', 'evaluate', jsonb_build_object('revision_id', pg_temp.cp('rev1'),
  'result', 'needs_revision', 'notes', 'Add the grounding point and the mat placement.'))$$, 'the admin returns the draft for revision');
select is(pg_temp.cp_status(pg_temp.cp('rev1')), 'needs_revision', 'submitted -> needs_revision');
select lives_ok($$select pg_temp.cp_do('author', 'edit_revision', jsonb_build_object('revision_id', pg_temp.cp('rev1'),
  'body_markdown', '# ESD\n\nWear the **wrist strap** and ground it to the mat.'))$$, 'the author edits a returned revision');
select lives_ok($$select pg_temp.cp_do('author', 'submit', jsonb_build_object('revision_id', pg_temp.cp('rev1')))$$,
  'needs_revision -> submitted');
select lives_ok($$select pg_temp.cp_do('admin', 'evaluate', jsonb_build_object('revision_id', pg_temp.cp('rev1'),
  'result', 'passed', 'notes', 'Accurate and aligned with PC 1.4.'))$$, 'the admin evaluates the revision as passed');
select is(pg_temp.cp_status(pg_temp.cp('rev1')), 'evaluated', 'submitted -> evaluated');
select throws_ok($$select pg_temp.cp_do('admin', 'publish', jsonb_build_object('revision_id', pg_temp.cp('rev1')))$$,
  '55000', 'TRANSITION_NOT_ALLOWED', 'evaluated -> published skips finalize and approve');
select lives_ok($$select pg_temp.cp_do('author', 'finalize', jsonb_build_object('revision_id', pg_temp.cp('rev1')))$$,
  'the author finalizes the evaluated revision');
select throws_ok($$select pg_temp.cp_do('author', 'edit_revision', jsonb_build_object('revision_id', pg_temp.cp('rev1'), 'title', 'After finalize'))$$,
  '55000', 'REVISION_LOCKED', 'finalized content is locked');
select throws_ok($$select pg_temp.cp_do('author', 'approve', jsonb_build_object('revision_id', pg_temp.cp('rev1')))$$,
  '42501', null, 'an instructor cannot approve');
select lives_ok($$select pg_temp.cp_do('admin', 'approve', jsonb_build_object('revision_id', pg_temp.cp('rev1')))$$,
  'the admin approves the finalized revision');
select lives_ok($$select pg_temp.cp_do('admin', 'publish', jsonb_build_object('revision_id', pg_temp.cp('rev1')))$$,
  'the admin publishes the approved revision');
select is(pg_temp.cp_status(pg_temp.cp('rev1')), 'published', 'approved -> published');
select is((select string_agg(coalesce(from_status::text, '-') || '>' || to_status::text, ',' order by id)
  from public.content_publication_events where entity_id = pg_temp.cp('topic')),
  '->draft,draft>submitted,submitted>needs_revision,needs_revision>submitted,submitted>evaluated,evaluated>finalized,finalized>approved,approved>published',
  'every transition appended one publication event in order');
select ok((select count(*) from public.audit_events where target_id = pg_temp.cp('rev1') and action like 'curriculum.%') >= 9,
  'every workflow action wrote an audit event');

-- ---------------------------------------------------------------------------
-- Learners see only the published revision, also while a new draft exists
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claim.sub', pg_temp.cp('learner')::text, true);
set local role authenticated;
select is((select string_agg(id::text, ',') from public.curriculum_topic_revisions where topic_id = pg_temp.cp('topic')),
  pg_temp.cp('rev1')::text, 'a learner sees the published revision');
reset role;
set local role service_role;
insert into cp_ctx select 'rev2', (pg_temp.cp_do('author', 'edit_revision', jsonb_build_object('revision_id', pg_temp.cp('rev1'),
  'title', 'ESD precautions (2026 update)'))->'revision'->>'id')::uuid;
select is((select revision_number || ':' || status::text from public.curriculum_topic_revisions where id = pg_temp.cp('rev2')),
  '2:draft', 'editing a published topic creates a new draft revision');
select is(pg_temp.cp_status(pg_temp.cp('rev1')), 'published', 'the published revision is untouched by the new draft');
select throws_ok($$select pg_temp.cp_do('author', 'edit_revision', jsonb_build_object('revision_id', pg_temp.cp('rev1'), 'title', 'Third'))$$,
  '55000', 'REVISION_IN_PROGRESS', 'only one revision of a topic can be in progress');
reset role;
set local role authenticated;
select is((select string_agg(id::text, ',') from public.curriculum_topic_revisions where topic_id = pg_temp.cp('topic')),
  pg_temp.cp('rev1')::text, 'a new draft keeps the published revision visible and the draft hidden');
reset role;
set local role service_role;
select pg_temp.cp_do('author', 'submit', jsonb_build_object('revision_id', pg_temp.cp('rev2')));
select pg_temp.cp_do('admin', 'evaluate', jsonb_build_object('revision_id', pg_temp.cp('rev2'), 'result', 'passed', 'notes', 'Update reviewed and accurate.'));
select pg_temp.cp_do('admin', 'finalize', jsonb_build_object('revision_id', pg_temp.cp('rev2')));
select pg_temp.cp_do('admin', 'approve', jsonb_build_object('revision_id', pg_temp.cp('rev2')));
select pg_temp.cp_do('admin', 'publish', jsonb_build_object('revision_id', pg_temp.cp('rev2')));
select is(pg_temp.cp_status(pg_temp.cp('rev1')) || '/' || pg_temp.cp_status(pg_temp.cp('rev2')), 'unpublished/published',
  'publishing revision 2 unpublishes revision 1');
reset role;
set local role authenticated;
select is((select string_agg(id::text, ',') from public.curriculum_topic_revisions where topic_id = pg_temp.cp('topic')),
  pg_temp.cp('rev2')::text, 'learners now see only revision 2');
reset role;

-- ---------------------------------------------------------------------------
-- Learner topic completion
-- ---------------------------------------------------------------------------
set local role service_role;
select is((pg_temp.cp_do('learner', 'complete_topic', jsonb_build_object('topic_id', pg_temp.cp('topic')))->>'already_completed'),
  'false', 'a learner completes a published topic in an unlocked module');
select is((pg_temp.cp_do('learner', 'complete_topic', jsonb_build_object('topic_id', pg_temp.cp('topic')))->>'already_completed'),
  'true', 'completing the same topic again is idempotent');
select is((select count(*)::integer || ':' || max(revision_id::text) from public.learner_topic_progress
  where learner_id = pg_temp.cp('learner') and topic_id = pg_temp.cp('topic')), '1:' || pg_temp.cp('rev2')::text,
  'one progress row referencing the published revision');
insert into cp_ctx select 'locked_topic', (pg_temp.cp_do('admin', 'create_topic', jsonb_build_object('module_id', pg_temp.cp('lo12'),
  'title', 'Bootable installer media', 'body_markdown', 'Create UEFI media.'))->'topic'->>'id')::uuid;
insert into cp_ctx select 'locked_rev', id from public.curriculum_topic_revisions where topic_id = pg_temp.cp('locked_topic');
select throws_ok($$select pg_temp.cp_do('learner', 'complete_topic', jsonb_build_object('topic_id', pg_temp.cp('locked_topic')))$$,
  'P0002', 'TOPIC_NOT_PUBLISHED', 'an unpublished topic cannot be completed');
select pg_temp.cp_do('admin', 'submit', jsonb_build_object('revision_id', pg_temp.cp('locked_rev')));
select pg_temp.cp_do('admin', 'evaluate', jsonb_build_object('revision_id', pg_temp.cp('locked_rev'), 'result', 'passed', 'notes', 'Ready for learners.'));
select pg_temp.cp_do('admin', 'finalize', jsonb_build_object('revision_id', pg_temp.cp('locked_rev')));
select pg_temp.cp_do('admin', 'approve', jsonb_build_object('revision_id', pg_temp.cp('locked_rev')));
select pg_temp.cp_do('admin', 'publish', jsonb_build_object('revision_id', pg_temp.cp('locked_rev')));
select throws_ok($$select pg_temp.cp_do('learner', 'complete_topic', jsonb_build_object('topic_id', pg_temp.cp('locked_topic')))$$,
  '42501', 'MODULE_LOCKED', 'complete_topic requires an unlocked module');
select throws_ok($$select pg_temp.cp_do('author', 'complete_topic', jsonb_build_object('topic_id', pg_temp.cp('topic')))$$,
  '42501', null, 'staff accounts cannot record learner topic completion');

-- ---------------------------------------------------------------------------
-- Unpublish, republish and archive
-- ---------------------------------------------------------------------------
select throws_ok($$select pg_temp.cp_do('author', 'unpublish', jsonb_build_object('revision_id', pg_temp.cp('rev2')))$$,
  '42501', null, 'an instructor cannot unpublish');
select pg_temp.cp_do('admin', 'unpublish', jsonb_build_object('revision_id', pg_temp.cp('rev2')));
select is(pg_temp.cp_status(pg_temp.cp('rev2')), 'unpublished', 'published -> unpublished');
select pg_temp.cp_do('admin', 'publish', jsonb_build_object('revision_id', pg_temp.cp('rev2')));
select is(pg_temp.cp_status(pg_temp.cp('rev2')), 'published', 'an admin republishes an unpublished revision');
select throws_ok($$select pg_temp.cp_do('author', 'archive_topic', jsonb_build_object('topic_id', pg_temp.cp('topic')))$$,
  '42501', null, 'an instructor cannot archive a topic');
select pg_temp.cp_do('admin', 'archive_topic', jsonb_build_object('topic_id', pg_temp.cp('topic')));
select ok((select archived_at is not null from public.curriculum_topics where id = pg_temp.cp('topic'))
  and pg_temp.cp_status(pg_temp.cp('rev2')) = 'archived', 'archiving retires the topic and its revisions');
reset role;
set local role authenticated;
select is((select count(*)::integer from public.curriculum_topic_revisions where topic_id = pg_temp.cp('topic')), 0,
  'learners no longer see an archived topic');
reset role;
select throws_ok($$update public.content_publication_events set note = 'rewritten' where entity_id = pg_temp.cp('topic')$$,
  '55000', null, 'publication history is append-only');

select * from finish();
rollback;
