-- Re-defense WS4 (slice A3.1): quizzes organised COC -> module -> topic ->
-- learning outcome with a stated focus; quiz settings (type, difficulty,
-- time limit, result release mode); scenario essay items scored against a
-- rubric by the instructor.
--
-- Additive only. Existing quizzes, versions, items and attempts stay valid
-- with null curriculum values ("not mapped to a module"). Published versions
-- and their items stay immutable. The SECURITY DEFINER functions changed here
-- are exactly those approved in the design (Section 9): create_instructor_quiz,
-- update_instructor_quiz, upsert_quiz_item and publish_quiz_version. Every
-- other new function is SECURITY INVOKER.
begin;
set local lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- 1. Quiz curriculum metadata
-- ---------------------------------------------------------------------------
alter table public.quizzes
  add column focus text,
  add column quiz_type text,
  add column difficulty text,
  add column topic_id uuid references public.curriculum_topics(id) on delete restrict;
alter table public.quizzes
  add constraint quizzes_focus_check check (focus is null or length(btrim(focus)) between 3 and 1000),
  add constraint quizzes_quiz_type_check check (quiz_type is null or quiz_type in ('pre_assessment', 'formative', 'summative')),
  add constraint quizzes_difficulty_check check (difficulty is null or difficulty in ('foundation', 'intermediate', 'advanced')),
  add constraint quizzes_topic_requires_coc_check check (topic_id is null or coc_module_id is not null);
create index quizzes_topic_idx on public.quizzes(topic_id) where topic_id is not null;
comment on column public.quizzes.focus is
  'What the quiz assesses. Required for curriculum-mapped quizzes; null marks a legacy quiz that is not yet mapped to a module.';
comment on column public.quizzes.coc_module_id is
  'The COC the quiz belongs to (required for new quizzes). No quiz_modules rows = whole-COC scope.';

create table public.quiz_modules (
  quiz_id uuid not null references public.quizzes(id) on delete restrict,
  module_id uuid not null references public.curriculum_modules(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (quiz_id, module_id)
);
create index quiz_modules_module_idx on public.quiz_modules(module_id);

create table public.quiz_learning_outcomes (
  quiz_id uuid not null references public.quizzes(id) on delete restrict,
  outcome_id uuid not null references public.learning_outcomes(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (quiz_id, outcome_id)
);
create index quiz_learning_outcomes_outcome_idx on public.quiz_learning_outcomes(outcome_id);

comment on table public.quiz_modules is
  'Curriculum modules (official learning outcomes) a quiz covers; they must belong to the quiz COC. No rows = whole COC.';
comment on table public.quiz_learning_outcomes is
  'Official performance criteria a quiz assesses; they must belong to the quiz scope.';

-- Defence in depth: links always stay inside the quiz COC, whatever the writer.
create function private.enforce_quiz_curriculum_link()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_coc uuid;
begin
  select q.coc_module_id into v_coc from public.quizzes q where q.id = new.quiz_id;
  if tg_table_name = 'quiz_modules' then
    if v_coc is null or not exists (
      select 1 from public.curriculum_modules m where m.id = new.module_id and m.coc_module_id = v_coc
    ) then
      raise exception 'QUIZ_MODULE_SCOPE_INVALID' using errcode = '22023';
    end if;
  elsif v_coc is null or not exists (
    select 1 from public.learning_outcomes o
    join public.curriculum_modules m on m.id = o.module_id
    where o.id = new.outcome_id and m.coc_module_id = v_coc
  ) then
    raise exception 'QUIZ_OUTCOME_SCOPE_INVALID' using errcode = '22023';
  end if;
  return new;
end
$$;
revoke all on function private.enforce_quiz_curriculum_link() from public, anon, authenticated;
create trigger quiz_modules_enforce_scope before insert or update on public.quiz_modules
  for each row execute function private.enforce_quiz_curriculum_link();
create trigger quiz_learning_outcomes_enforce_scope before insert or update on public.quiz_learning_outcomes
  for each row execute function private.enforce_quiz_curriculum_link();

alter table public.quiz_modules enable row level security;
alter table public.quiz_learning_outcomes enable row level security;
create policy quiz_modules_staff_select on public.quiz_modules for select to authenticated
using (exists (
  select 1 from public.quizzes q
  where q.id = quiz_modules.quiz_id and (q.instructor_id = (select auth.uid()) or public.is_admin())
));
create policy quiz_learning_outcomes_staff_select on public.quiz_learning_outcomes for select to authenticated
using (exists (
  select 1 from public.quizzes q
  where q.id = quiz_learning_outcomes.quiz_id and (q.instructor_id = (select auth.uid()) or public.is_admin())
));
revoke all on public.quiz_modules, public.quiz_learning_outcomes from public, anon, authenticated;
grant select on public.quiz_modules, public.quiz_learning_outcomes to authenticated;
grant all on public.quiz_modules, public.quiz_learning_outcomes to service_role;

-- ---------------------------------------------------------------------------
-- 2. Version settings: time limit and result release mode
-- ---------------------------------------------------------------------------
alter table public.quiz_versions
  add column time_limit_minutes integer,
  add column result_release_mode text not null default 'immediate';
alter table public.quiz_versions
  add constraint quiz_versions_time_limit_check check (time_limit_minutes is null or time_limit_minutes between 1 and 240),
  add constraint quiz_versions_release_mode_check check (result_release_mode in ('immediate', 'instructor_release'));
comment on column public.quiz_versions.result_release_mode is
  'immediate: learners see objective results at submission. instructor_release: results appear only after the instructor finalizes and releases them. Forced at publication when the version has an essay.';

-- Published and retired versions keep the settings learners took them under.
create function private.protect_quiz_version_settings()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.status <> 'draft'::public.content_version_status
     and (new.time_limit_minutes is distinct from old.time_limit_minutes
          or new.result_release_mode is distinct from old.result_release_mode) then
    raise exception 'PUBLISHED_QUIZ_SETTINGS_ARE_IMMUTABLE' using errcode = '55000';
  end if;
  return new;
end
$$;
revoke all on function private.protect_quiz_version_settings() from public, anon, authenticated;
create trigger quiz_versions_protect_settings
  before update of time_limit_minutes, result_release_mode on public.quiz_versions
  for each row execute function private.protect_quiz_version_settings();

-- A new draft created through the existing create_quiz_version RPC continues
-- with the settings of the previous version until the instructor edits them.
create function private.inherit_quiz_version_settings()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_previous public.quiz_versions;
begin
  if new.time_limit_minutes is null and new.result_release_mode = 'immediate' then
    select qv.* into v_previous from public.quiz_versions qv
    where qv.quiz_id = new.quiz_id order by qv.version_number desc limit 1;
    if found then
      new.time_limit_minutes := v_previous.time_limit_minutes;
      new.result_release_mode := v_previous.result_release_mode;
    end if;
  end if;
  return new;
end
$$;
revoke all on function private.inherit_quiz_version_settings() from public, anon, authenticated;
create trigger quiz_versions_inherit_settings
  before insert on public.quiz_versions
  for each row execute function private.inherit_quiz_version_settings();

-- ---------------------------------------------------------------------------
-- 3. Scenario essay items: scenario, rubric, points and word guidance
-- ---------------------------------------------------------------------------
alter table public.quiz_items
  add column scenario text,
  add column rubric jsonb,
  add column points numeric not null default 1,
  add column min_words integer,
  add column max_words integer;
comment on column public.quiz_items.rubric is
  'Scenario essays only: [{id, criterion, description, max_points}] (1-10 criteria, each 0 < max_points <= 100).';
comment on column public.quiz_items.points is
  'Objective items: points for a correct answer (default 1). Essays: the sum of the rubric max_points.';
comment on column public.quiz_items.correct_answer is
  'Objective items: the answer key. Essays: optional instructor-only scoring guide (never sent to learners).';

-- Returns the normalised rubric, or null when it is not a valid rubric.
create function private.normalize_quiz_rubric(p_rubric jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_item jsonb;
  v_index integer := 0;
  v_out jsonb := '[]'::jsonb;
  v_id text;
  v_points numeric;
  v_ids text[] := '{}';
begin
  if p_rubric is null or jsonb_typeof(p_rubric) <> 'array'
     or jsonb_array_length(p_rubric) not between 1 and 10 then
    return null;
  end if;
  for v_item in select value from jsonb_array_elements(p_rubric) loop
    v_index := v_index + 1;
    if jsonb_typeof(v_item) <> 'object' then return null; end if;
    if coalesce(jsonb_typeof(v_item->'max_points'), '') <> 'number'
       or length(btrim(coalesce(v_item->>'criterion', ''))) not between 2 and 200
       or coalesce(jsonb_typeof(v_item->'description'), 'null') not in ('string', 'null')
       or length(coalesce(v_item->>'description', '')) > 1000
       or coalesce(jsonb_typeof(v_item->'id'), 'null') not in ('string', 'null') then
      return null;
    end if;
    v_points := (v_item->>'max_points')::numeric;
    if v_points <= 0 or v_points > 100 then return null; end if;
    v_id := coalesce(nullif(btrim(v_item->>'id'), ''), 'C' || v_index);
    if v_id !~ '^[A-Za-z0-9_-]{1,40}$' or v_id = any(v_ids) then return null; end if;
    v_ids := v_ids || v_id;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'id', v_id,
      'criterion', btrim(v_item->>'criterion'),
      'description', coalesce(btrim(v_item->>'description'), ''),
      'max_points', v_points));
  end loop;
  return v_out;
end
$$;

create function private.quiz_rubric_total(p_rubric jsonb)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_rubric jsonb := private.normalize_quiz_rubric(p_rubric);
begin
  if v_rubric is null then return null; end if;
  return (select sum((c->>'max_points')::numeric) from jsonb_array_elements(v_rubric) c);
end
$$;

create or replace function private.validate_quiz_item(
  p_item_type public.quiz_item_type,
  p_options jsonb,
  p_correct_answer jsonb
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select
    jsonb_typeof(coalesce(p_options, 'null'::jsonb)) = 'array'
    and jsonb_typeof(p_correct_answer) = 'string'
    and case
      when p_item_type in ('multiple_choice'::public.quiz_item_type, 'scenario_based'::public.quiz_item_type)
        then jsonb_array_length(p_options) between 2 and 6
             and p_options @> jsonb_build_array(p_correct_answer)
      when p_item_type = 'true_false'::public.quiz_item_type
        then jsonb_array_length(p_options) = 0
             and lower(p_correct_answer #>> '{}') in ('true', 'false')
      when p_item_type = 'identification'::public.quiz_item_type
        then jsonb_array_length(p_options) = 0
             and length(btrim(p_correct_answer #>> '{}')) between 1 and 500
      -- Essays have no answer key; the optional string is an instructor scoring guide.
      when p_item_type = 'scenario_essay'::public.quiz_item_type
        then jsonb_array_length(p_options) = 0
             and length(p_correct_answer #>> '{}') <= 2000
      else false
    end
$$;

revoke all on function private.normalize_quiz_rubric(jsonb) from public, anon, authenticated;
revoke all on function private.quiz_rubric_total(jsonb) from public, anon, authenticated;
revoke all on function private.validate_quiz_item(public.quiz_item_type, jsonb, jsonb) from public, anon, authenticated;
-- Server-only writers (service role) insert items through invoker functions;
-- the table constraints below must be evaluable for them.
grant execute on function private.normalize_quiz_rubric(jsonb) to service_role;
grant execute on function private.quiz_rubric_total(jsonb) to service_role;
grant execute on function private.validate_quiz_item(public.quiz_item_type, jsonb, jsonb) to service_role;

alter table public.quiz_items
  add constraint quiz_items_points_check check (points > 0 and points <= 1000),
  add constraint quiz_items_word_guidance_check check (
    (min_words is null or min_words between 1 and 5000)
    and (max_words is null or max_words between 1 and 5000)
    and (min_words is null or max_words is null or min_words <= max_words)),
  add constraint quiz_items_essay_contract_check check (
    case when item_type = 'scenario_essay'::public.quiz_item_type
      then length(btrim(coalesce(scenario, ''))) between 10 and 4000
        and private.normalize_quiz_rubric(rubric) is not null
        and points = private.quiz_rubric_total(rubric)
      else rubric is null and scenario is null and min_words is null and max_words is null
    end);

-- ---------------------------------------------------------------------------
-- 4. Shared validation helpers (called by the definer RPCs below)
-- ---------------------------------------------------------------------------
create function private.assert_quiz_curriculum(
  p_coc_module_id uuid,
  p_module_ids uuid[],
  p_topic_id uuid,
  p_outcome_ids uuid[]
)
returns void
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_modules uuid[] := coalesce(p_module_ids, '{}');
  v_outcomes uuid[] := coalesce(p_outcome_ids, '{}');
begin
  if p_coc_module_id is null or not exists (select 1 from public.coc_modules c where c.id = p_coc_module_id) then
    raise exception 'QUIZ_COC_REQUIRED' using errcode = '22023';
  end if;
  if array_position(v_modules, null) is not null or cardinality(v_modules) > 16
     or exists (
       select 1 from unnest(v_modules) requested(id)
       where not exists (
         select 1 from public.curriculum_modules m
         where m.id = requested.id and m.coc_module_id = p_coc_module_id))
  then
    raise exception 'QUIZ_MODULE_SCOPE_INVALID' using errcode = '22023';
  end if;
  if p_topic_id is not null and not exists (
    select 1 from public.curriculum_topics t
    join public.curriculum_modules m on m.id = t.module_id
    where t.id = p_topic_id
      and t.archived_at is null
      and m.coc_module_id = p_coc_module_id
      and (cardinality(v_modules) = 0 or t.module_id = any(v_modules))
      and exists (
        select 1 from public.curriculum_topic_revisions r
        where r.topic_id = t.id and r.status = 'published'::public.content_publication_status))
  then
    raise exception 'QUIZ_TOPIC_SCOPE_INVALID' using errcode = '22023';
  end if;
  if array_position(v_outcomes, null) is not null or cardinality(v_outcomes) > 100
     or exists (
       select 1 from unnest(v_outcomes) requested(id)
       where not exists (
         select 1 from public.learning_outcomes o
         join public.curriculum_modules m on m.id = o.module_id
         where o.id = requested.id
           and m.coc_module_id = p_coc_module_id
           and (cardinality(v_modules) = 0 or o.module_id = any(v_modules))))
  then
    raise exception 'QUIZ_OUTCOME_SCOPE_INVALID' using errcode = '22023';
  end if;
end
$$;

create function private.assert_quiz_settings(
  p_focus text,
  p_quiz_type text,
  p_difficulty text,
  p_time_limit_minutes integer,
  p_result_release_mode text
)
returns void
language plpgsql
immutable
security invoker
set search_path = ''
as $$
begin
  if length(btrim(coalesce(p_focus, ''))) not between 3 and 1000 then
    raise exception 'QUIZ_FOCUS_REQUIRED' using errcode = '22023';
  end if;
  if p_quiz_type is null or p_quiz_type not in ('pre_assessment', 'formative', 'summative') then
    raise exception 'QUIZ_TYPE_INVALID' using errcode = '22023';
  end if;
  if p_difficulty is null or p_difficulty not in ('foundation', 'intermediate', 'advanced') then
    raise exception 'QUIZ_DIFFICULTY_INVALID' using errcode = '22023';
  end if;
  if p_time_limit_minutes is not null and p_time_limit_minutes not between 1 and 240 then
    raise exception 'QUIZ_TIME_LIMIT_INVALID' using errcode = '22023';
  end if;
  if p_result_release_mode is null or p_result_release_mode not in ('immediate', 'instructor_release') then
    raise exception 'QUIZ_RELEASE_MODE_INVALID' using errcode = '22023';
  end if;
end
$$;

-- Curriculum snapshot used in audit events.
create function private.quiz_curriculum_snapshot(p_quiz_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'module_ids', coalesce((select jsonb_agg(m.module_id order by m.module_id) from public.quiz_modules m where m.quiz_id = p_quiz_id), '[]'::jsonb),
    'outcome_ids', coalesce((select jsonb_agg(o.outcome_id order by o.outcome_id) from public.quiz_learning_outcomes o where o.quiz_id = p_quiz_id), '[]'::jsonb))
$$;

revoke all on function private.assert_quiz_curriculum(uuid, uuid[], uuid, uuid[]) from public, anon, authenticated;
revoke all on function private.assert_quiz_settings(text, text, text, integer, text) from public, anon, authenticated;
revoke all on function private.quiz_curriculum_snapshot(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Authoring RPCs (definer functions approved in design Section 9)
-- ---------------------------------------------------------------------------
-- New parameters have defaults; the old shorter signatures are dropped so no
-- ambiguous overload remains. Callers that pass parameters by name keep working.
drop function public.create_instructor_quiz(text, text, text, uuid, text);
create function public.create_instructor_quiz(
  p_title text,
  p_topic text,
  p_description text default null,
  p_coc_module_id uuid default null,
  p_instructions text default null,
  p_focus text default null,
  p_quiz_type text default null,
  p_difficulty text default null,
  p_topic_id uuid default null,
  p_module_ids uuid[] default null,
  p_outcome_ids uuid[] default null,
  p_time_limit_minutes integer default null,
  p_result_release_mode text default null
)
returns public.quizzes
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quiz public.quizzes;
  v_version public.quiz_versions;
  v_type text := coalesce(nullif(btrim(p_quiz_type), ''), 'formative');
  v_difficulty text := coalesce(nullif(btrim(p_difficulty), ''), 'foundation');
  v_mode text := coalesce(nullif(btrim(p_result_release_mode), ''), 'immediate');
  v_modules uuid[];
  v_outcomes uuid[];
begin
  if not public.is_instructor() then
    raise exception 'INSTRUCTOR_REQUIRED' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_title, ''))) not between 3 and 200
     or length(btrim(coalesce(p_topic, ''))) not between 2 and 240 then
    raise exception 'QUIZ_TITLE_AND_TOPIC_REQUIRED' using errcode = '22023';
  end if;
  -- New quizzes are always placed in the curriculum and state their focus.
  perform private.assert_quiz_curriculum(p_coc_module_id, p_module_ids, p_topic_id, p_outcome_ids);
  perform private.assert_quiz_settings(p_focus, v_type, v_difficulty, p_time_limit_minutes, v_mode);
  select coalesce(array_agg(distinct x), '{}') into v_modules from unnest(coalesce(p_module_ids, '{}')) x;
  select coalesce(array_agg(distinct x), '{}') into v_outcomes from unnest(coalesce(p_outcome_ids, '{}')) x;

  insert into public.quizzes (
    instructor_id, coc_module_id, title, description, topic, created_by,
    focus, quiz_type, difficulty, topic_id
  ) values (
    (select auth.uid()), p_coc_module_id, btrim(p_title), nullif(btrim(p_description), ''), btrim(p_topic), (select auth.uid()),
    btrim(p_focus), v_type, v_difficulty, p_topic_id
  ) returning * into v_quiz;

  insert into public.quiz_versions (
    quiz_id, version_number, instructions, change_summary, created_by,
    time_limit_minutes, result_release_mode
  ) values (
    v_quiz.id, 1, nullif(btrim(p_instructions), ''), 'Initial draft', (select auth.uid()),
    p_time_limit_minutes, v_mode
  ) returning * into v_version;

  insert into public.quiz_modules (quiz_id, module_id) select v_quiz.id, m from unnest(v_modules) m;
  insert into public.quiz_learning_outcomes (quiz_id, outcome_id) select v_quiz.id, o from unnest(v_outcomes) o;

  perform private.write_audit_event('quiz.created', 'quiz', v_quiz.id, null,
    to_jsonb(v_quiz) || private.quiz_curriculum_snapshot(v_quiz.id)
      || jsonb_build_object('time_limit_minutes', v_version.time_limit_minutes, 'result_release_mode', v_version.result_release_mode));
  return v_quiz;
end
$$;

drop function public.update_instructor_quiz(uuid, text, text, text, uuid);
create function public.update_instructor_quiz(
  p_quiz_id uuid,
  p_title text,
  p_topic text,
  p_description text default null,
  p_coc_module_id uuid default null,
  p_focus text default null,
  p_quiz_type text default null,
  p_difficulty text default null,
  p_topic_id uuid default null,
  p_module_ids uuid[] default null,
  p_outcome_ids uuid[] default null,
  p_time_limit_minutes integer default null,
  p_result_release_mode text default null,
  p_instructions text default null
)
returns public.quizzes
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quiz public.quizzes;
  v_old jsonb;
  v_draft public.quiz_versions;
  v_latest public.quiz_versions;
  v_type text;
  v_difficulty text;
  v_mode text;
  v_modules uuid[];
  v_outcomes uuid[];
  v_instructions text := nullif(btrim(p_instructions), '');
begin
  if not public.is_instructor() then raise exception 'INSTRUCTOR_REQUIRED' using errcode = '42501'; end if;
  select q.* into v_quiz from public.quizzes q where q.id = p_quiz_id for update;
  if not found then raise exception 'QUIZ_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_quiz.instructor_id <> (select auth.uid()) then raise exception 'QUIZ_SCOPE_DENIED' using errcode = '42501'; end if;
  if v_quiz.archived_at is not null then raise exception 'QUIZ_ARCHIVED' using errcode = '22023'; end if;
  if length(btrim(coalesce(p_title, ''))) not between 3 and 200
     or length(btrim(coalesce(p_topic, ''))) not between 2 and 240 then
    raise exception 'QUIZ_TITLE_AND_TOPIC_REQUIRED' using errcode = '22023';
  end if;
  v_old := to_jsonb(v_quiz) || private.quiz_curriculum_snapshot(v_quiz.id);

  if p_focus is null then
    -- Legacy metadata edit (title, topic, description, COC). A mapped quiz
    -- can change COC only together with its curriculum fields.
    if p_coc_module_id is not null and not exists (select 1 from public.coc_modules cm where cm.id = p_coc_module_id) then
      raise exception 'COC_MODULE_NOT_FOUND' using errcode = 'P0002';
    end if;
    if v_quiz.focus is not null and p_coc_module_id is distinct from v_quiz.coc_module_id then
      raise exception 'QUIZ_CURRICULUM_UPDATE_REQUIRED' using errcode = '22023';
    end if;
    update public.quizzes
    set title = btrim(p_title), topic = btrim(p_topic), description = nullif(btrim(p_description), ''), coc_module_id = p_coc_module_id
    where id = p_quiz_id returning * into v_quiz;
    perform private.write_audit_event('quiz.updated', 'quiz', v_quiz.id, v_old, to_jsonb(v_quiz) || private.quiz_curriculum_snapshot(v_quiz.id));
    return v_quiz;
  end if;

  -- Curriculum and settings edit: every field is authoritative.
  select qv.* into v_draft from public.quiz_versions qv
  where qv.quiz_id = p_quiz_id and qv.status = 'draft'::public.content_version_status for update;
  select qv.* into v_latest from public.quiz_versions qv where qv.quiz_id = p_quiz_id order by qv.version_number desc limit 1;
  v_type := coalesce(nullif(btrim(p_quiz_type), ''), v_quiz.quiz_type, 'formative');
  v_difficulty := coalesce(nullif(btrim(p_difficulty), ''), v_quiz.difficulty, 'foundation');
  v_mode := coalesce(nullif(btrim(p_result_release_mode), ''), coalesce(v_draft.result_release_mode, v_latest.result_release_mode), 'immediate');
  perform private.assert_quiz_curriculum(p_coc_module_id, p_module_ids, p_topic_id, p_outcome_ids);
  perform private.assert_quiz_settings(p_focus, v_type, v_difficulty, p_time_limit_minutes, v_mode);
  select coalesce(array_agg(distinct x), '{}') into v_modules from unnest(coalesce(p_module_ids, '{}')) x;
  select coalesce(array_agg(distinct x), '{}') into v_outcomes from unnest(coalesce(p_outcome_ids, '{}')) x;

  if v_draft.id is null and v_latest.id is not null and (
       v_latest.time_limit_minutes is distinct from p_time_limit_minutes
       or v_latest.result_release_mode is distinct from v_mode
       or v_latest.instructions is distinct from v_instructions) then
    -- Published versions keep the settings learners took them under.
    raise exception 'CREATE_DRAFT_TO_CHANGE_SETTINGS' using errcode = '22023';
  end if;

  update public.quizzes
  set title = btrim(p_title), topic = btrim(p_topic), description = nullif(btrim(p_description), ''),
      coc_module_id = p_coc_module_id, focus = btrim(p_focus), quiz_type = v_type,
      difficulty = v_difficulty, topic_id = p_topic_id
  where id = p_quiz_id returning * into v_quiz;
  delete from public.quiz_modules where quiz_id = p_quiz_id and module_id <> all(v_modules);
  insert into public.quiz_modules (quiz_id, module_id) select p_quiz_id, m from unnest(v_modules) m on conflict do nothing;
  delete from public.quiz_learning_outcomes where quiz_id = p_quiz_id and outcome_id <> all(v_outcomes);
  insert into public.quiz_learning_outcomes (quiz_id, outcome_id) select p_quiz_id, o from unnest(v_outcomes) o on conflict do nothing;

  if v_draft.id is not null then
    update public.quiz_versions
    set instructions = v_instructions, time_limit_minutes = p_time_limit_minutes, result_release_mode = v_mode
    where id = v_draft.id;
  end if;

  perform private.write_audit_event('quiz.updated', 'quiz', v_quiz.id, v_old,
    to_jsonb(v_quiz) || private.quiz_curriculum_snapshot(v_quiz.id)
      || jsonb_build_object('time_limit_minutes', p_time_limit_minutes, 'result_release_mode', v_mode,
        'draft_version_id', v_draft.id));
  return v_quiz;
end
$$;

drop function public.upsert_quiz_item(uuid, public.quiz_item_type, text, jsonb, jsonb, text, integer, uuid);
create function public.upsert_quiz_item(
  p_quiz_version_id uuid,
  p_item_type public.quiz_item_type,
  p_prompt text,
  p_options jsonb,
  p_correct_answer jsonb,
  p_explanation text default null,
  p_order_index integer default null,
  p_item_id uuid default null,
  p_rubric jsonb default null,
  p_points numeric default null,
  p_scenario text default null,
  p_min_words integer default null,
  p_max_words integer default null
)
returns public.quiz_items
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version public.quiz_versions;
  v_quiz public.quizzes;
  v_item public.quiz_items;
  v_old jsonb;
  v_order integer;
  v_essay boolean := p_item_type = 'scenario_essay'::public.quiz_item_type;
  v_rubric jsonb;
  v_points numeric;
  v_scenario text := nullif(btrim(p_scenario), '');
  v_rubric_supplied boolean := nullif(nullif(p_rubric, 'null'::jsonb), '[]'::jsonb) is not null;
begin
  if not public.is_instructor() then raise exception 'INSTRUCTOR_REQUIRED' using errcode='42501'; end if;
  select qv.* into v_version from public.quiz_versions qv where qv.id=p_quiz_version_id for update;
  if not found then raise exception 'QUIZ_VERSION_NOT_FOUND' using errcode='P0002'; end if;
  select q.* into v_quiz from public.quizzes q where q.id=v_version.quiz_id;
  if v_quiz.instructor_id <> (select auth.uid()) then raise exception 'QUIZ_SCOPE_DENIED' using errcode='42501'; end if;
  if v_version.status <> 'draft'::public.content_version_status then raise exception 'DRAFT_QUIZ_VERSION_REQUIRED' using errcode='22023'; end if;
  if length(btrim(coalesce(p_prompt,''))) not between 5 and 2000
     or not coalesce(private.validate_quiz_item(p_item_type,p_options,p_correct_answer), false) then
    raise exception 'INVALID_QUIZ_ITEM' using errcode='22023';
  end if;
  if v_essay then
    v_rubric := private.normalize_quiz_rubric(p_rubric);
    if v_rubric is null then raise exception 'QUIZ_ESSAY_RUBRIC_REQUIRED' using errcode='22023'; end if;
    if length(coalesce(v_scenario, '')) not between 10 and 4000 then
      raise exception 'QUIZ_ESSAY_SCENARIO_REQUIRED' using errcode='22023';
    end if;
    if (p_min_words is not null and p_min_words not between 1 and 5000)
       or (p_max_words is not null and p_max_words not between 1 and 5000)
       or (p_min_words is not null and p_max_words is not null and p_min_words > p_max_words) then
      raise exception 'QUIZ_WORD_GUIDANCE_INVALID' using errcode='22023';
    end if;
    v_points := private.quiz_rubric_total(v_rubric);
  elsif v_rubric_supplied or v_scenario is not null or p_min_words is not null or p_max_words is not null then
    raise exception 'INVALID_QUIZ_ITEM' using errcode='22023';
  end if;

  if p_item_id is null then
    v_points := coalesce(v_points, p_points, 1);
    if not v_essay and (v_points <= 0 or v_points > 100) then raise exception 'QUIZ_ITEM_POINTS_INVALID' using errcode='22023'; end if;
    select coalesce(p_order_index, coalesce(max(qi.order_index),0)+1) into v_order from public.quiz_items qi where qi.quiz_version_id=p_quiz_version_id;
    if exists(select 1 from public.quiz_items qi where qi.quiz_version_id=p_quiz_version_id and qi.order_index=v_order) then
      raise exception 'QUIZ_ITEM_ORDER_IN_USE' using errcode='23505';
    end if;
    insert into public.quiz_items(quiz_version_id,item_code,item_type,prompt,options,correct_answer,explanation,order_index,created_by,
      scenario,rubric,points,min_words,max_words)
    values(p_quiz_version_id,'ITEM-'||lpad(v_order::text,3,'0'),p_item_type,btrim(p_prompt),p_options,p_correct_answer,
      nullif(btrim(p_explanation),''),v_order,(select auth.uid()),
      case when v_essay then v_scenario end, v_rubric, v_points,
      case when v_essay then p_min_words end, case when v_essay then p_max_words end)
    returning * into v_item;
    perform private.write_audit_event('quiz_item.created','quiz_item',v_item.id,null,to_jsonb(v_item));
  else
    select qi.* into v_item from public.quiz_items qi where qi.id=p_item_id and qi.quiz_version_id=p_quiz_version_id for update;
    if not found then raise exception 'QUIZ_ITEM_NOT_FOUND' using errcode='P0002'; end if;
    if v_item.removed_at is not null then raise exception 'QUIZ_ITEM_REMOVED' using errcode='22023'; end if;
    v_points := coalesce(v_points, p_points,
      case when v_item.item_type = 'scenario_essay'::public.quiz_item_type then 1 else v_item.points end);
    if not v_essay and (v_points <= 0 or v_points > 100) then raise exception 'QUIZ_ITEM_POINTS_INVALID' using errcode='22023'; end if;
    v_old:=to_jsonb(v_item);
    v_order:=coalesce(p_order_index,v_item.order_index);
    if v_order<>v_item.order_index and exists(select 1 from public.quiz_items qi where qi.quiz_version_id=p_quiz_version_id and qi.order_index=v_order and qi.id<>v_item.id) then
      raise exception 'QUIZ_ITEM_ORDER_IN_USE' using errcode='23505';
    end if;
    update public.quiz_items set item_type=p_item_type,prompt=btrim(p_prompt),options=p_options,correct_answer=p_correct_answer,
      explanation=nullif(btrim(p_explanation),''),order_index=v_order,review_status='draft'::public.quiz_item_review_status,
      review_notes=null,reviewed_by=null,reviewed_at=null,
      scenario=case when v_essay then v_scenario end, rubric=v_rubric, points=v_points,
      min_words=case when v_essay then p_min_words end, max_words=case when v_essay then p_max_words end
    where id=p_item_id returning * into v_item;
    perform private.write_audit_event('quiz_item.updated','quiz_item',v_item.id,v_old,to_jsonb(v_item));
  end if;
  return v_item;
end
$$;

create or replace function public.publish_quiz_version(p_quiz_version_id uuid,p_reason text default null)
returns public.quiz_versions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version public.quiz_versions;
  v_quiz public.quizzes;
  v_old jsonb;
  v_essays integer;
begin
  if not public.is_instructor() then raise exception 'INSTRUCTOR_REQUIRED' using errcode='42501'; end if;
  select qv.* into v_version from public.quiz_versions qv where qv.id=p_quiz_version_id for update;
  if not found then raise exception 'QUIZ_VERSION_NOT_FOUND' using errcode='P0002'; end if;
  select q.* into v_quiz from public.quizzes q where q.id=v_version.quiz_id for update;
  if v_quiz.instructor_id<>(select auth.uid()) then raise exception 'QUIZ_SCOPE_DENIED' using errcode='42501'; end if;
  if v_version.status='published'::public.content_version_status and v_quiz.archived_at is null then return v_version; end if;
  if v_quiz.archived_at is not null or v_version.status<>'draft'::public.content_version_status then raise exception 'DRAFT_ACTIVE_QUIZ_REQUIRED' using errcode='22023'; end if;
  if not exists(select 1 from public.quiz_items qi where qi.quiz_version_id=v_version.id and qi.removed_at is null and qi.review_status='approved'::public.quiz_item_review_status) then
    raise exception 'APPROVED_QUIZ_ITEM_REQUIRED' using errcode='22023';
  end if;
  if exists(select 1 from public.quiz_items qi where qi.quiz_version_id=v_version.id and qi.removed_at is null and qi.review_status<>'approved'::public.quiz_item_review_status) then
    raise exception 'ALL_QUIZ_ITEMS_REQUIRE_APPROVAL' using errcode='22023';
  end if;
  if exists(select 1 from public.quiz_items qi where qi.quiz_version_id=v_version.id and qi.removed_at is null
      and qi.item_type='scenario_essay'::public.quiz_item_type
      and (private.normalize_quiz_rubric(qi.rubric) is null or qi.points is distinct from private.quiz_rubric_total(qi.rubric))) then
    raise exception 'QUIZ_ESSAY_RUBRIC_INVALID' using errcode='22023';
  end if;
  select count(*) into v_essays from public.quiz_items qi
  where qi.quiz_version_id=v_version.id and qi.removed_at is null and qi.item_type='scenario_essay'::public.quiz_item_type;
  v_old:=to_jsonb(v_version);
  update public.quiz_versions set status='retired'::public.content_version_status,retired_at=now()
  where quiz_id=v_quiz.id and status='published'::public.content_version_status;
  -- Essays are scored by the instructor, so their results are always released by the instructor.
  update public.quiz_versions set status='published'::public.content_version_status,published_by=(select auth.uid()),published_at=now(),
    result_release_mode=case when v_essays>0 then 'instructor_release' else result_release_mode end
  where id=v_version.id returning * into v_version;
  perform private.write_audit_event('quiz_version.published','quiz_version',v_version.id,v_old,to_jsonb(v_version),nullif(btrim(p_reason),''),
    jsonb_build_object('quiz_id',v_quiz.id,
      'approved_items',(select count(*) from public.quiz_items qi where qi.quiz_version_id=v_version.id and qi.removed_at is null),
      'essay_items',v_essays,'result_release_mode',v_version.result_release_mode,'time_limit_minutes',v_version.time_limit_minutes));
  return v_version;
end
$$;

-- Reordering re-saves each item through upsert_quiz_item; pass the essay data through.
create or replace function public.reorder_quiz_items(p_quiz_version_id uuid,p_item_ids uuid[])
returns void language plpgsql security invoker set search_path='' as $$
declare v_item public.quiz_items; v_id uuid; v_max integer; v_slots integer[]; v_index integer:=0;
begin
  if not public.is_instructor() then raise exception 'INSTRUCTOR_REQUIRED' using errcode='42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_quiz_version_id::text,1));
  if not exists(select 1 from public.quiz_versions v join public.quizzes q on q.id=v.quiz_id
    where v.id=p_quiz_version_id and v.status='draft'::public.content_version_status
      and q.instructor_id=(select auth.uid()) and q.archived_at is null) then
    raise exception 'DRAFT_ACTIVE_QUIZ_REQUIRED' using errcode='42501';
  end if;
  if p_item_ids is null or array_position(p_item_ids,null) is not null
    or cardinality(p_item_ids)<>(select count(distinct id) from unnest(p_item_ids) id)
    or cardinality(p_item_ids)<>(select count(*) from public.quiz_items where quiz_version_id=p_quiz_version_id and removed_at is null)
    or exists(select 1 from unnest(p_item_ids) requested(item_id) where not exists(select 1 from public.quiz_items qi where qi.id=requested.item_id and qi.quiz_version_id=p_quiz_version_id and qi.removed_at is null)) then
    raise exception 'QUIZ_ORDER_CHANGED_REFRESH_REQUIRED' using errcode='22023';
  end if;
  select coalesce(max(order_index),0) into v_max from public.quiz_items where quiz_version_id=p_quiz_version_id;
  select array_agg(order_index order by order_index) into v_slots from public.quiz_items where quiz_version_id=p_quiz_version_id and removed_at is null;
  foreach v_id in array p_item_ids loop
    v_index:=v_index+1;
    select * into v_item from public.quiz_items where id=v_id;
    perform public.upsert_quiz_item(p_quiz_version_id,v_item.item_type,v_item.prompt,v_item.options,v_item.correct_answer,v_item.explanation,
      v_max+v_index,v_item.id,v_item.rubric,v_item.points,v_item.scenario,v_item.min_words,v_item.max_words);
  end loop;
  -- Keep removed items' reserved slots intact.
  v_index:=0;
  foreach v_id in array p_item_ids loop
    v_index:=v_index+1;
    select * into v_item from public.quiz_items where id=v_id;
    perform public.upsert_quiz_item(p_quiz_version_id,v_item.item_type,v_item.prompt,v_item.options,v_item.correct_answer,v_item.explanation,
      v_slots[v_index],v_item.id,v_item.rubric,v_item.points,v_item.scenario,v_item.min_words,v_item.max_words);
  end loop;
end $$;

revoke all on function public.create_instructor_quiz(text,text,text,uuid,text,text,text,text,uuid,uuid[],uuid[],integer,text) from public, anon;
revoke all on function public.update_instructor_quiz(uuid,text,text,text,uuid,text,text,text,uuid,uuid[],uuid[],integer,text,text) from public, anon;
revoke all on function public.upsert_quiz_item(uuid,public.quiz_item_type,text,jsonb,jsonb,text,integer,uuid,jsonb,numeric,text,integer,integer) from public, anon;
grant execute on function public.create_instructor_quiz(text,text,text,uuid,text,text,text,text,uuid,uuid[],uuid[],integer,text) to authenticated;
grant execute on function public.update_instructor_quiz(uuid,text,text,text,uuid,text,text,text,uuid,uuid[],uuid[],integer,text,text) to authenticated;
grant execute on function public.upsert_quiz_item(uuid,public.quiz_item_type,text,jsonb,jsonb,text,integer,uuid,jsonb,numeric,text,integer,integer) to authenticated;

notify pgrst, 'reload schema';
commit;
