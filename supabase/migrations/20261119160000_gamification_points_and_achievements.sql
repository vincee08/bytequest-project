-- Slice A6 (Objective 2): "Use points, levels, rewards, achievements and
-- tracking progress in the learning process to motivate and engage the
-- learner."
--
-- Points are awarded by the server from real learning records only, exactly
-- once per (learner, event type, source record). Gamification stays separate
-- from competency: nothing here reads or changes scores, criterion results or
-- released outcomes, and no competency logic reads points.
--
-- Additive only:
-- * gamification_point_rules, learner_point_events (append-only) and
--   gamification_levels are new.
-- * The legacy achievement catalog (public.achievements) and its award table
--   (public.user_achievements) are extended in place, following the recorded
--   direction in docs/LEGACY_SCHEMA_REASSESSMENT.md ("event-driven award
--   policy" / "event-driven award projection"). The existing Profile >
--   Earned achievements screen and its realtime subscription therefore keep
--   working. Legacy catalog rows without a rule stay dormant and are never
--   evaluated. public.learner_achievements exposes (learner_id, code,
--   earned_at) for readers.
-- * Legacy gamification_events, levels, badges, leaderboard_entries and the
--   legacy profile counters are not touched.
-- * Award triggers are SECURITY INVOKER. Every source record is written by
--   service-role server code or by an existing SECURITY DEFINER RPC, so the
--   triggers run with those trusted privileges. Clients have no write path to
--   any gamification table. No new SECURITY DEFINER function.
-- * Every gamification trigger fails open: a fault raises a WARNING and the
--   learning record that fired it still commits. A failed award leaves no
--   partial rows and is repaired, exactly once, by gamification_backfill().
-- * Safe on existing production data: duplicate legacy award rows are kept in
--   place (the earliest row per key is the award) instead of failing the
--   unique index, and award history still allows the declared ON DELETE
--   CASCADE of the guarded admin account removal.

begin;
set local lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- Point rules
-- ---------------------------------------------------------------------------
create table public.gamification_point_rules (
  event_type text primary key check (event_type ~ '^[a-z][a-z0-9_]{2,62}$'),
  points integer not null check (points > 0),
  label text not null check (length(btrim(label)) between 2 and 120),
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_gamification_point_rules_updated_at
  before update on public.gamification_point_rules
  for each row execute function public.set_updated_at();

insert into public.gamification_point_rules (event_type, points, label, sort_order) values
  ('practice_mission_verified', 50, 'Practice mission verified', 1),
  ('topic_completed', 10, 'Topic completed', 2),
  ('module_completed', 100, 'Module completed', 3),
  ('coc_completed', 300, 'COC completed', 4),
  ('quiz_submitted', 20, 'Quiz submitted', 5),
  ('homework_submitted_on_time', 15, 'Homework submitted on time', 6),
  ('assessment_released', 40, 'Assessment result released', 7);

-- ---------------------------------------------------------------------------
-- Point events: one row per learner, event type and source record
-- ---------------------------------------------------------------------------
create table public.learner_point_events (
  id uuid primary key default gen_random_uuid(),
  learner_id uuid not null references auth.users(id) on delete restrict,
  event_type text not null references public.gamification_point_rules(event_type) on delete restrict,
  source_id text not null check (length(btrim(source_id)) between 1 and 200),
  points integer not null check (points > 0),
  detail text check (detail is null or length(detail) <= 300),
  awarded_at timestamptz not null default now(),
  unique (learner_id, event_type, source_id)
);

create index learner_point_events_learner_awarded_idx
  on public.learner_point_events (learner_id, awarded_at desc);
create index learner_point_events_event_type_idx
  on public.learner_point_events (event_type);

create trigger trg_learner_point_events_append_only
  before update or delete on public.learner_point_events
  for each row execute function private.prevent_append_only_mutation();

-- Stored points always equal the active rule and inactive rules award nothing,
-- whichever trusted code path performs the insert.
create function private.gamification_point_event_guard()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_points integer;
begin
  select r.points into v_points
  from public.gamification_point_rules r
  where r.event_type = new.event_type and r.active;
  if v_points is null then
    return null;
  end if;
  new.points := v_points;
  new.source_id := btrim(new.source_id);
  new.detail := left(nullif(btrim(new.detail), ''), 300);
  return new;
end
$$;

create trigger trg_learner_point_events_guard
  before insert on public.learner_point_events
  for each row execute function private.gamification_point_event_guard();

-- ---------------------------------------------------------------------------
-- Levels from cumulative points
-- ---------------------------------------------------------------------------
create table public.gamification_levels (
  level integer primary key check (level > 0),
  min_points integer not null unique check (min_points >= 0),
  title text not null check (length(btrim(title)) between 2 and 80)
);

insert into public.gamification_levels (level, min_points, title) values
  (1, 0, 'Trainee'),
  (2, 100, 'Apprentice'),
  (3, 300, 'Junior Technician'),
  (4, 600, 'Technician'),
  (5, 1000, 'Senior Technician'),
  (6, 1500, 'Lead Technician');

create function public.gamification_level_for_points(p_points integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with total as (
    select greatest(coalesce(p_points, 0), 0) as points
  ),
  current_level as (
    select l.level, l.title, l.min_points
    from public.gamification_levels l, total t
    where l.min_points <= t.points
    order by l.min_points desc, l.level desc
    limit 1
  ),
  next_level as (
    select l.level, l.min_points
    from public.gamification_levels l, total t
    where l.min_points > t.points
    order by l.min_points, l.level
    limit 1
  )
  select jsonb_build_object(
    'level', c.level,
    'title', c.title,
    'min_points', c.min_points,
    'next_level', n.level,
    'next_min_points', n.min_points,
    'progress_percent', case
      when n.min_points is null then 100
      else floor(100.0 * (t.points - coalesce(c.min_points, 0)) / (n.min_points - coalesce(c.min_points, 0)))::integer
    end)
  from total t
  left join current_level c on true
  left join next_level n on true
$$;

-- ---------------------------------------------------------------------------
-- Achievements: extend the legacy catalog with server-evaluated rules
-- ---------------------------------------------------------------------------
alter table public.achievements
  add column if not exists rule jsonb,
  add column if not exists icon text,
  add column if not exists sort_order integer not null default 0;

alter table public.achievements
  add constraint achievements_rule_check check (
    rule is null or (
      jsonb_typeof(rule) = 'object'
      and coalesce(rule->>'event_type', '') ~ '^[a-z][a-z0-9_]{2,62}$'
      and case rule->>'type'
        when 'count' then jsonb_typeof(rule->'min') = 'number' and coalesce(rule->>'min', '') ~ '^[1-9][0-9]{0,5}$'
        when 'source' then length(btrim(coalesce(rule->>'source_id', ''))) between 1 and 200
        else false
      end
    )
  ),
  add constraint achievements_icon_check check (icon is null or icon ~ '^[a-z][a-z0-9_]{1,63}$');

insert into public.achievements (achievement_code, title, description, icon, condition_type, condition_value, rule, sort_order)
values
  ('first_mission', 'First Verified Mission', 'Verify your first practice mission.', 'verified',
    'mission_count', '{}', '{"type":"count","event_type":"practice_mission_verified","min":1}', 1),
  ('assembly_ready', 'Assembly Ready', 'Verify the COC 1 Mission 2 hardware assembly practice mission.', 'memory',
    'special', '{}', '{"type":"source","event_type":"practice_mission_verified","source_id":"coc1_m2"}', 2),
  ('five_missions', 'Five Missions Verified', 'Verify five different practice missions.', 'military_tech',
    'mission_count', '{}', '{"type":"count","event_type":"practice_mission_verified","min":5}', 3),
  ('ten_missions', 'Ten Missions Verified', 'Verify ten different practice missions.', 'workspace_premium',
    'mission_count', '{}', '{"type":"count","event_type":"practice_mission_verified","min":10}', 4),
  ('first_module', 'First Module Complete', 'Complete every required item in one learning module.', 'school',
    'special', '{}', '{"type":"count","event_type":"module_completed","min":1}', 5),
  ('coc1_complete', 'COC 1 Complete', 'Complete COC 1: Install and Configure Computer Systems.', 'computer',
    'coc_completion', '{}', '{"type":"source","event_type":"coc_completed","source_id":"coc1"}', 6),
  ('coc2_complete', 'COC 2 Complete', 'Complete COC 2: Set-up Computer Networks.', 'lan',
    'coc_completion', '{}', '{"type":"source","event_type":"coc_completed","source_id":"coc2"}', 7),
  ('coc3_complete', 'COC 3 Complete', 'Complete COC 3: Set-up Computer Servers.', 'dns',
    'coc_completion', '{}', '{"type":"source","event_type":"coc_completed","source_id":"coc3"}', 8),
  ('coc4_complete', 'COC 4 Complete', 'Complete COC 4: Maintain and Repair Computer Systems and Networks.', 'build',
    'coc_completion', '{}', '{"type":"source","event_type":"coc_completed","source_id":"coc4"}', 9),
  ('quiz_taker', 'Quiz Taker', 'Submit five assigned quizzes.', 'quiz',
    'special', '{}', '{"type":"count","event_type":"quiz_submitted","min":5}', 10),
  ('on_time', 'On Time', 'Submit five homework assignments on or before the deadline.', 'schedule',
    'special', '{}', '{"type":"count","event_type":"homework_submitted_on_time","min":5}', 11),
  ('first_release', 'First Released Result', 'Receive your first assessment result released by your instructor.', 'assignment_turned_in',
    'special', '{}', '{"type":"count","event_type":"assessment_released","min":1}', 12)
on conflict (achievement_code) do update
  set title = excluded.title,
      description = excluded.description,
      icon = excluded.icon,
      condition_type = excluded.condition_type,
      condition_value = excluded.condition_value,
      rule = excluded.rule,
      sort_order = excluded.sort_order
  -- Never redefine a legacy achievement that someone has already earned.
  where not exists (select 1 from public.user_achievements ua where ua.achievement_id = achievements.id);

do $$
declare
  v_configured integer;
begin
  select count(*) into v_configured from public.achievements where rule is not null;
  if v_configured < 12 then
    raise warning 'A6 gamification: only % rule-based achievements are configured; a legacy achievement with earned history kept its definition.', v_configured;
  end if;
end
$$;

-- Earned achievements: one award per learner and achievement, append-only.
-- Legacy award rows are never deleted or rewritten. The unique index is only
-- created when the legacy table holds no duplicate (user_id, achievement_id)
-- keys; otherwise every reader treats the earliest row per key as the award
-- and private.gamification_award_achievements keeps awarding exactly once on
-- its own (per-learner lock and existence check).
create function private.gamification_ensure_award_index()
returns text
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_duplicate_keys bigint;
begin
  if to_regclass('public.user_achievements_user_achievement_key') is not null then
    return 'exists';
  end if;
  select count(*) into v_duplicate_keys
  from (
    select 1
    from public.user_achievements
    group by user_id, achievement_id
    having count(*) > 1
  ) duplicates;
  if v_duplicate_keys > 0 then
    raise notice 'user_achievements holds % duplicate (user_id, achievement_id) keys. History is kept in place, the earliest row per key is the award, and the unique index is not created.', v_duplicate_keys;
    return 'skipped_duplicates';
  end if;
  create unique index user_achievements_user_achievement_key
    on public.user_achievements (user_id, achievement_id);
  return 'created';
end
$$;

select private.gamification_ensure_award_index();

-- Append-only, except the declared ON DELETE CASCADE from auth.users when the
-- guarded admin account removal deletes an identity. That delete is a nested
-- foreign-key action (trigger depth > 1), the same rule the audit history
-- uses (private.protect_audit_event_history). Every direct UPDATE or DELETE,
-- including by service-role code, is rejected.
create function private.gamification_achievement_history_guard()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and pg_catalog.pg_trigger_depth() > 1 then
    return old;
  end if;
  raise exception 'user_achievements is append-only' using errcode = '55000';
end
$$;

create trigger trg_user_achievements_append_only
  before update or delete on public.user_achievements
  for each row execute function private.gamification_achievement_history_guard();

-- One row per learner and achievement; the earliest award wins.
create view public.learner_achievements
with (security_invoker = true)
as
select ua.user_id as learner_id, a.achievement_code as code, min(ua.earned_at) as earned_at
from public.user_achievements ua
join public.achievements a on a.id = ua.achievement_id
group by ua.user_id, a.achievement_code;

-- ---------------------------------------------------------------------------
-- Award path
-- ---------------------------------------------------------------------------
-- Human-readable context for a point event, captured at award time by the
-- trusted writer (learners cannot read every source table directly).
create function private.gamification_source_detail(p_event_type text, p_source_id text)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
  v_detail text;
begin
  if p_source_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_id := p_source_id::uuid;
  end if;
  case p_event_type
    when 'practice_mission_verified' then
      select m.title into v_detail from public.missions m where m.mission_code = p_source_id;
    when 'coc_completed' then
      select c.module_name into v_detail from public.coc_modules c where c.coc_code = p_source_id;
    when 'topic_completed' then
      select r.title into v_detail
      from public.curriculum_topic_revisions r
      where r.topic_id = v_id and r.status = 'published'::public.content_publication_status
      order by r.revision_number desc
      limit 1;
    when 'module_completed' then
      select m.code || ' ' || m.title into v_detail from public.curriculum_modules m where m.id = v_id;
    when 'quiz_submitted' then
      select q.title into v_detail
      from public.quiz_attempts a
      join public.quiz_versions v on v.id = a.quiz_version_id
      join public.quizzes q on q.id = v.quiz_id
      where a.id = v_id;
    when 'homework_submitted_on_time' then
      select h.title into v_detail
      from public.homework_submissions s
      join public.homework_assignments h on h.id = s.assignment_id
      where s.id = v_id;
    when 'assessment_released' then
      select av.title into v_detail
      from public.attempts a
      join public.activity_versions av on av.id = a.activity_version_id
      where a.id = v_id;
    else
      v_detail := null;
  end case;
  return left(nullif(btrim(v_detail), ''), 300);
end
$$;

-- Awards one event exactly once. Returns true only when a new event was
-- recorded (unknown or inactive rules, non-learners and repeats return false).
create function private.gamification_award(
  p_learner uuid,
  p_event_type text,
  p_source_id text,
  p_awarded_at timestamptz
)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_source text := btrim(p_source_id);
  v_id uuid;
begin
  if p_learner is null or coalesce(v_source, '') = '' then
    return false;
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.user_id = p_learner and p.role = 'learner'::public.user_role
  ) then
    return false;
  end if;
  if exists (
    select 1 from public.learner_point_events e
    where e.learner_id = p_learner and e.event_type = p_event_type and e.source_id = v_source
  ) then
    return false;
  end if;
  insert into public.learner_point_events (learner_id, event_type, source_id, points, detail, awarded_at)
  select p_learner, r.event_type, v_source, r.points,
         private.gamification_source_detail(r.event_type, v_source),
         coalesce(p_awarded_at, now())
  from public.gamification_point_rules r
  where r.event_type = p_event_type and r.active
  on conflict (learner_id, event_type, source_id) do nothing
  returning id into v_id;
  return v_id is not null;
end
$$;

-- Awards every achievement whose rule becomes true for this event type. The
-- earned time is the time of the event that satisfied the rule, so awards are
-- correct regardless of insertion order (live, repair or backfill).
-- Evaluation is serialised per learner and checks for an existing award, so
-- each achievement is recorded once even where the legacy table could not
-- receive its unique index (no ON CONFLICT dependency on that index).
create function private.gamification_award_achievements(p_learner uuid, p_event_type text)
returns integer
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_awarded integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('bytequest.gamification.achievements:' || p_learner::text, 0));
  insert into public.user_achievements (user_id, achievement_id, earned_at)
  select p_learner, a.id, crossing.awarded_at
  from public.achievements a
  cross join lateral (
    select ranked.awarded_at
    from (
      select e.awarded_at, row_number() over (order by e.awarded_at, e.id) as position
      from public.learner_point_events e
      where e.learner_id = p_learner
        and e.event_type = a.rule->>'event_type'
        and (a.rule->>'type' = 'count' or e.source_id = a.rule->>'source_id')
    ) ranked
    where ranked.position = case when a.rule->>'type' = 'count' then (a.rule->>'min')::integer else 1 end
  ) crossing
  where a.rule is not null
    and a.rule->>'event_type' = p_event_type
    and not exists (
      select 1 from public.user_achievements ua
      where ua.user_id = p_learner and ua.achievement_id = a.id
    );
  get diagnostics v_awarded = row_count;
  return v_awarded;
end
$$;

-- Fails open: the points stay recorded even if achievements cannot be
-- evaluated now; they are re-evaluated on the learner's next event of this
-- type and by private.gamification_backfill().
create function private.gamification_point_event_awarded()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  begin
    perform private.gamification_award_achievements(new.learner_id, new.event_type);
  exception when others then
    raise warning 'gamification achievements deferred (event %, learner %, source %): % [%]',
      new.event_type, new.learner_id, new.source_id, sqlerrm, sqlstate;
  end;
  return null;
end
$$;

create trigger trg_learner_point_events_award_achievements
  after insert on public.learner_point_events
  for each row execute function private.gamification_point_event_awarded();

-- One dispatcher for every source table. Each branch keys on the recorded
-- fact, so later additive columns or status values do not change awards.
-- Fails open: points are motivational, so a fault anywhere in the award path
-- (rules, point event, achievements, leaderboard) must never block the
-- learning record that fired it. The inner block is a subtransaction, so a
-- failed award leaves no partial rows; private.gamification_backfill() awards
-- the record later, still exactly once.
create function private.gamification_award_from_source()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_learner uuid;
  v_event_type text;
  v_source text;
  v_at timestamptz;
begin
  begin
    if tg_table_name = 'practice_mission_completions' then
      -- The verifier upserts on re-verification; only the first insert awards.
      v_learner := new.learner_id;
      v_event_type := 'practice_mission_verified';
      v_source := new.mission_id;
      v_at := new.verified_at;
    elsif tg_table_name = 'learner_topic_progress' then
      v_learner := new.learner_id;
      v_event_type := 'topic_completed';
      v_source := new.topic_id::text;
      v_at := new.completed_at;
    elsif tg_table_name = 'learner_module_completions' then
      v_learner := new.learner_id;
      v_event_type := 'module_completed';
      v_source := new.module_id::text;
      v_at := new.completed_at;
    elsif tg_table_name = 'practice_coc_progress' then
      v_learner := new.learner_id;
      v_event_type := 'coc_completed';
      v_source := new.coc_code;
      v_at := new.completed_at;
    elsif tg_table_name = 'quiz_attempts' then
      -- First transition into submitted or completed.
      if tg_op = 'UPDATE' then
        if old.status::text in ('submitted', 'completed') then
          return null;
        end if;
      end if;
      if new.status::text not in ('submitted', 'completed') then
        return null;
      end if;
      v_learner := new.learner_id;
      v_event_type := 'quiz_submitted';
      v_source := new.id::text;
      v_at := coalesce(new.submitted_at, new.completed_at, now());
    elsif tg_table_name = 'homework_submissions' then
      if new.lateness_seconds is distinct from 0 then
        return null;
      end if;
      v_learner := new.learner_id;
      v_event_type := 'homework_submitted_on_time';
      v_source := new.id::text;
      v_at := new.submitted_at;
    elsif tg_table_name = 'result_releases' then
      if new.is_current is not true then
        return null;
      end if;
      v_event_type := 'assessment_released';
      v_source := new.attempt_id::text;
      v_at := new.released_at;
      select a.learner_id into v_learner from public.attempts a where a.id = new.attempt_id;
    else
      return null;
    end if;
    perform private.gamification_award(v_learner, v_event_type, v_source, v_at);
  exception when others then
    raise warning 'gamification award skipped (event %, learner %, source %, table %): % [%]',
      v_event_type, v_learner, v_source, tg_table_name, sqlerrm, sqlstate;
  end;
  return null;
end
$$;

create trigger trg_practice_mission_completions_award_points
  after insert on public.practice_mission_completions
  for each row execute function private.gamification_award_from_source();
create trigger trg_learner_topic_progress_award_points
  after insert on public.learner_topic_progress
  for each row execute function private.gamification_award_from_source();
create trigger trg_learner_module_completions_award_points
  after insert on public.learner_module_completions
  for each row execute function private.gamification_award_from_source();
create trigger trg_practice_coc_progress_award_points
  after insert on public.practice_coc_progress
  for each row execute function private.gamification_award_from_source();
create trigger trg_quiz_attempts_award_points
  after insert or update of status on public.quiz_attempts
  for each row execute function private.gamification_award_from_source();
create trigger trg_homework_submissions_award_points
  after insert on public.homework_submissions
  for each row when (new.lateness_seconds = 0)
  execute function private.gamification_award_from_source();
create trigger trg_result_releases_award_points
  after insert on public.result_releases
  for each row when (new.is_current)
  execute function private.gamification_award_from_source();

-- Awards every qualifying record not yet awarded, in chronological order and
-- with the record's original time, then re-evaluates achievements that were
-- deferred. Idempotent and fail open per record (a failing record is skipped
-- with a warning, so the migration and repairs never abort on one bad row).
-- Used once below and available to trusted maintenance code as the repair.
create function private.gamification_backfill()
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  r record;
  v_awarded integer := 0;
  v_skipped integer := 0;
  v_achievements integer := 0;
begin
  for r in
    select s.learner_id, s.event_type, s.source_id, s.occurred_at
    from (
      select c.learner_id, 'practice_mission_verified'::text as event_type, c.mission_id as source_id,
             c.verified_at as occurred_at
      from public.practice_mission_completions c
      union all
      select p.learner_id, 'topic_completed', p.topic_id::text, p.completed_at
      from public.learner_topic_progress p
      union all
      select m.learner_id, 'module_completed', m.module_id::text, m.completed_at
      from public.learner_module_completions m
      union all
      select p.learner_id, 'coc_completed', p.coc_code, p.completed_at
      from public.practice_coc_progress p
      union all
      select q.learner_id, 'quiz_submitted', q.id::text, coalesce(q.submitted_at, q.completed_at, q.created_at)
      from public.quiz_attempts q
      where q.status::text in ('submitted', 'completed')
      union all
      select h.learner_id, 'homework_submitted_on_time', h.id::text, h.submitted_at
      from public.homework_submissions h
      where h.lateness_seconds = 0
      union all
      -- Every release row was current when it was inserted.
      select a.learner_id, 'assessment_released', a.id::text, min(rr.released_at)
      from public.result_releases rr
      join public.attempts a on a.id = rr.attempt_id
      group by a.learner_id, a.id
    ) s
    order by s.occurred_at, s.event_type, s.source_id
  loop
    begin
      if private.gamification_award(r.learner_id, r.event_type, r.source_id, r.occurred_at) then
        v_awarded := v_awarded + 1;
      end if;
    exception when others then
      v_skipped := v_skipped + 1;
      raise warning 'gamification backfill skipped (event %, learner %, source %): % [%]',
        r.event_type, r.learner_id, r.source_id, sqlerrm, sqlstate;
    end;
  end loop;
  for r in
    select distinct e.learner_id, e.event_type
    from public.learner_point_events e
    order by e.learner_id, e.event_type
  loop
    begin
      v_achievements := v_achievements + private.gamification_award_achievements(r.learner_id, r.event_type);
    exception when others then
      v_skipped := v_skipped + 1;
      raise warning 'gamification backfill could not evaluate achievements (event %, learner %): % [%]',
        r.event_type, r.learner_id, sqlerrm, sqlstate;
    end;
  end loop;
  return jsonb_build_object('awarded', v_awarded, 'achievements', v_achievements, 'skipped', v_skipped);
end
$$;

-- ---------------------------------------------------------------------------
-- Row level security and grants
-- ---------------------------------------------------------------------------
alter table public.gamification_point_rules enable row level security;
alter table public.learner_point_events enable row level security;
alter table public.gamification_levels enable row level security;

create policy gamification_point_rules_read on public.gamification_point_rules
  for select to authenticated using (public.is_active_user());
create policy gamification_levels_read on public.gamification_levels
  for select to authenticated using (public.is_active_user());
-- Own events; owning instructors and admins read them for analytics.
create policy learner_point_events_read on public.learner_point_events
  for select to authenticated using (
    learner_id = (select auth.uid())
    or public.is_admin()
    or private.current_instructor_teaches_learner(learner_id)
  );

revoke all on public.gamification_point_rules, public.learner_point_events, public.gamification_levels
  from public, anon, authenticated;
grant select on public.gamification_point_rules, public.learner_point_events, public.gamification_levels
  to authenticated;
grant all on public.gamification_point_rules, public.learner_point_events, public.gamification_levels
  to service_role;

revoke all on public.learner_achievements from public, anon, authenticated;
grant select on public.learner_achievements to authenticated, service_role;

revoke all on function private.gamification_point_event_guard() from public, anon, authenticated;
revoke all on function private.gamification_source_detail(text, text) from public, anon, authenticated;
revoke all on function private.gamification_award(uuid, text, text, timestamptz) from public, anon, authenticated;
revoke all on function private.gamification_award_achievements(uuid, text) from public, anon, authenticated;
revoke all on function private.gamification_point_event_awarded() from public, anon, authenticated;
revoke all on function private.gamification_award_from_source() from public, anon, authenticated;
revoke all on function private.gamification_backfill() from public, anon, authenticated;
revoke all on function private.gamification_ensure_award_index() from public, anon, authenticated;
revoke all on function private.gamification_achievement_history_guard() from public, anon, authenticated;
grant execute on function
  private.gamification_source_detail(text, text),
  private.gamification_award(uuid, text, text, timestamptz),
  private.gamification_award_achievements(uuid, text),
  private.gamification_backfill(),
  private.gamification_ensure_award_index()
  to service_role;

revoke all on function public.gamification_level_for_points(integer) from public, anon;
grant execute on function public.gamification_level_for_points(integer) to authenticated, service_role;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'learner_point_events'
     ) then
    alter publication supabase_realtime add table public.learner_point_events;
  end if;
end
$$;

comment on table public.gamification_point_rules is
  'Objective 2 point rules. Motivational only; never part of competency evaluation. Inactive rules award nothing.';
comment on table public.learner_point_events is
  'Append-only server-awarded points, one per learner, event type and source record (source_id = mission code, topic/module/attempt/submission id or COC code).';
comment on table public.gamification_levels is
  'Objective 2 levels derived from cumulative points.';
comment on column public.achievements.rule is
  'Server-evaluated rule: {"type":"count","event_type":...,"min":n} or {"type":"source","event_type":...,"source_id":...}. Rows without a rule are dormant legacy entries.';
comment on view public.learner_achievements is
  'Earned achievements as (learner_id, code, earned_at), backed by the append-only public.user_achievements.';

-- Award the records that already exist, with their original timestamps.
select private.gamification_backfill();

notify pgrst, 'reload schema';

commit;
