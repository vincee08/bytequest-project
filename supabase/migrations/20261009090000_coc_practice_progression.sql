-- Educational practice progression only. Official assessment/release is unchanged.
-- All evaluators are SECURITY INVOKER, callable only by the trusted server.
begin;

create table public.practice_mission_contracts (
  mission_id text primary key check (mission_id ~ '^coc[1-4]_m[1-5]$'),
  version text not null,
  definition jsonb not null check (jsonb_typeof(definition) = 'object')
);
create table public.practice_mission_completions (
  learner_id uuid not null references public.profiles(user_id),
  mission_id text not null references public.practice_mission_contracts(mission_id),
  contract_version text not null,
  evidence_through_id bigint not null references public.practice_mission_actions(id),
  verified_at timestamptz not null default now(),
  primary key (learner_id, mission_id)
);
create table public.practice_coc_progress (
  learner_id uuid not null references public.profiles(user_id),
  coc_code text not null check (coc_code ~ '^coc[1-4]$'),
  completed_at timestamptz not null default now(),
  quiz_attempt_id uuid not null,
  primary key (learner_id, coc_code)
);
create table public.practice_quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  learner_id uuid not null references public.profiles(user_id),
  coc_code text not null check (coc_code ~ '^coc[1-4]$'),
  status text not null default 'generating' check (status in ('generating','active','submitted')),
  questions jsonb not null check (jsonb_typeof(questions) = 'array' and jsonb_array_length(questions) = 5),
  answers jsonb not null default '{}'::jsonb,
  source text not null default 'bank' check (source in ('bank','ai')),
  score integer check (score between 0 and 5),
  passing_percent integer not null default 80 check (passing_percent = 80),
  passed boolean,
  created_at timestamptz not null default now(),
  submitted_at timestamptz
);
alter table public.practice_coc_progress add constraint practice_progress_quiz_fk
  foreign key (quiz_attempt_id) references public.practice_quiz_attempts(id);
create unique index practice_quiz_one_open on public.practice_quiz_attempts(learner_id,coc_code)
  where status <> 'submitted';
create index practice_quiz_rate_limit on public.practice_quiz_attempts(learner_id,created_at);
alter table public.practice_mission_contracts enable row level security;
alter table public.practice_mission_completions enable row level security;
alter table public.practice_coc_progress enable row level security;
alter table public.practice_quiz_attempts enable row level security;
revoke all on public.practice_mission_contracts, public.practice_mission_completions,
  public.practice_coc_progress, public.practice_quiz_attempts from public,anon,authenticated;
grant all on public.practice_mission_contracts, public.practice_mission_completions,
  public.practice_coc_progress, public.practice_quiz_attempts to service_role;
grant select on public.practice_mission_completions, public.practice_coc_progress to authenticated;
create policy practice_completion_read_own on public.practice_mission_completions for select to authenticated
  using ((select public.is_learner()) and learner_id = (select auth.uid()));
create policy practice_progress_read_own on public.practice_coc_progress for select to authenticated
  using ((select public.is_learner()) and learner_id = (select auth.uid()));

create function public.practice_coc_unlocked(p_coc text, p_learner uuid default auth.uid())
returns boolean language sql stable security invoker set search_path = '' as $$
  select p_coc ~ '^coc[1-4]$' and not exists (
    select 1 from generate_series(1,4) n
    where n < case when p_coc ~ '^coc[1-4]$' then right(p_coc,1)::integer else 0 end
      and not exists (select 1 from public.practice_coc_progress p
        where p.learner_id = p_learner and p.coc_code = 'coc' || n)
  );
$$;
revoke all on function public.practice_coc_unlocked(text,uuid) from public,anon;
grant execute on function public.practice_coc_unlocked(text,uuid) to authenticated,service_role;
create function public.get_practice_learning_path()
returns table(coc_code text, unlocked boolean, completed boolean, completed_missions jsonb)
language sql stable security invoker set search_path='' as $$
  select 'coc'||n, public.practice_coc_unlocked('coc'||n),
    exists(select 1 from public.practice_coc_progress p where p.learner_id=auth.uid() and p.coc_code='coc'||n),
    coalesce((select jsonb_agg(c.mission_id order by c.mission_id) from public.practice_mission_completions c
      where c.learner_id=auth.uid() and left(c.mission_id,4)='coc'||n),'[]')
  from generate_series(1,4) n where public.is_learner();
$$;
revoke all on function public.get_practice_learning_path() from public,anon;
grant execute on function public.get_practice_learning_path() to authenticated;
-- Restrictive policy also applies to future permissive INSERT policies.
create policy practice_actions_progression_gate on public.practice_mission_actions as restrictive
  for insert to authenticated with check (
    mission_id ~ '^coc[1-4]_m[1-5]$'
    and public.practice_coc_unlocked(left(mission_id,4))
    and octet_length(value::text) <= 131072
  );

create function public.practice_conditions_met(p_conditions jsonb, p_state jsonb)
returns boolean language plpgsql stable security invoker set search_path = '' as $$
declare c jsonb; actual jsonb; wanted jsonb; valid boolean;
begin
  for c in select value from jsonb_array_elements(coalesce(p_conditions,'[]')) loop
    actual := p_state -> (c->>'path'); wanted := c->'value';
    if left(c->>'path',7) = 'result.' then
      actual := to_jsonb(coalesce((actual->>'operating')::boolean,false)
        and (actual->>'revision')::integer = coalesce((p_state->>'revision')::integer,0));
    end if;
    valid := case coalesce(c->>'operator','equals')
      when 'present' then actual is not null and actual <> 'null' and actual <> 'false'
        and actual <> '""' and actual <> '[]'
      when 'contains' then jsonb_typeof(actual) = 'array' and actual @> jsonb_build_array(wanted)
      when 'set_equals' then jsonb_typeof(actual) = 'array' and actual @> wanted and wanted @> actual
      when 'one_of' then jsonb_typeof(wanted) = 'array' and wanted @> jsonb_build_array(actual)
      when 'not_equals' then actual is not null and actual <> wanted
      when 'minimum' then case when actual #>> '{}' ~ '^[0-9]+(\.[0-9]+)?$'
        then (actual #>> '{}')::numeric >= (wanted #>> '{}')::numeric else false end
      else actual = wanted end;
    if not coalesce(valid,false) then return false; end if;
  end loop;
  return true;
end $$;

create function public.practice_verify_mission(p_learner uuid,p_mission text)
returns void language plpgsql security invoker set search_path = '' as $$
declare contract public.practice_mission_contracts; a public.practice_mission_actions;
  phase jsonb; p jsonb; eq jsonb; panel jsonb; item jsonb; destination jsonb;
  field jsonb; v jsonb; state jsonb := '{"revision":0}'::jsonb; done jsonb := '{}'::jsonb;
  family text; kind text; key text; actual jsonb; valid boolean; terminal boolean;
  revision integer := 0; first_id bigint; last_id bigint;
begin
  if not exists(select 1 from public.profiles where user_id=p_learner and role='learner' and status='active')
    or not public.practice_coc_unlocked(left(p_mission,4),p_learner) then
    raise exception 'PRACTICE_COC_LOCKED' using errcode='42501';
  end if;
  select * into strict contract from public.practice_mission_contracts where mission_id=p_mission;
  select coalesce(max(id),0) into first_id from public.practice_mission_actions
    where learner_id=p_learner and mission_id=p_mission and action_type='practice_progress_discarded';
  for a in select * from public.practice_mission_actions
    where learner_id=p_learner and mission_id=p_mission and id>first_id order by id loop
    last_id := a.id;
    select value into phase from jsonb_array_elements(contract.definition->'phases') where value->>'id'=a.phase_id;
    if phase is null then continue; end if;
    p := phase->'presentation'; eq := p->'equipment'; v := a.value;
    family := phase->>'primaryInteraction'; kind := coalesce(v->>'runtime_action_type',a.action_type);
    valid := true; terminal := false;
    -- Client compatibility flags, snapshots, measured results and phase_completed are never trusted.
    case kind
    when 'object_inspected' then
      valid := exists(select 1 from jsonb_array_elements(contract.definition->'scene'->'objects') where value->>'id'=a.target);
      if valid then state := state || jsonb_build_object('inspected.'||a.target,true); end if;
      if family='inspect' then terminal := not exists(select 1 from jsonb_array_elements(p->'objects') o
        where coalesce(state->>('inspected.'||(o->>'id')),'false') <> 'true'); end if;
    when 'placement_attempted' then
      panel := coalesce(eq->'placement',p);
      select value into item from jsonb_array_elements(panel->'items') where value->>'id'=v->>'item_id';
      select value into destination from jsonb_array_elements(panel->'destinations') where value->>'id'=v->>'destination_id';
      valid := item is not null and destination is not null
        and coalesce(destination->'socket_categories',destination->'accepted_categories') @> jsonb_build_array(item->'category')
        and (item->>'seating_orientation' is null or item->>'seating_orientation'=v->>'orientation')
        and not exists(select 1 from jsonb_array_elements_text(coalesce(item->'requires_placements','[]')) x
          where state->('placed.'||x) is null)
        and not exists(select 1 from jsonb_each(state) s where s.key like 'placed.%'
          and s.key <> 'placed.'||(v->>'item_id') and s.value=v->'destination_id');
      if valid then state := state || jsonb_build_object('placed.'||(v->>'item_id'),v->'destination_id'); end if;
      if family='place' then terminal := not exists(select 1 from jsonb_array_elements(panel->'items') o
        where state->('placed.'||(o->>'id')) is null); end if;
    when 'connection_created' then
      panel := coalesce(eq->'connection',p);
      select value into item from jsonb_array_elements(panel->'sources') where value->>'id'=v->>'source_id';
      select value into destination from jsonb_array_elements(panel->'destinations') where value->>'id'=v->>'destination_id';
      valid := item is not null and destination is not null and item->>'id'<>destination->>'id'
        and (coalesce(item->'interfaces','[]')='[]' or item->'interfaces' @> jsonb_build_array(destination->'interface'));
      if valid then
        if eq->>'single_connection'='true' then
          select coalesce(jsonb_object_agg(s.key,s.value),'{}') into state from jsonb_each(state) s
            where left(s.key,length('link.'||(v->>'source_id')||'>')) <> 'link.'||(v->>'source_id')||'>';
        end if;
        state := state || jsonb_build_object('link.'||(v->>'source_id')||'>'||(v->>'destination_id'),true);
      end if;
      if family='connect' then terminal := not exists(select 1 from jsonb_array_elements(panel->'sources') o
        where not exists(select 1 from jsonb_each(state) s where s.key like 'link.'||(o->>'id')||'>%' and s.value='true')); end if;
    when 'configuration_applied' then
      panel := coalesce(eq->'configuration',p);
      for field in select value from jsonb_array_elements(panel->'fields') loop
        actual := v->'values'->(field->>'id'); key := actual #>> '{}';
        if actual is null or actual='null' or btrim(key)='' then valid := false;
        elsif field->>'type'='toggle' and jsonb_typeof(actual)<>'boolean' then valid := false;
        elsif field->>'type'='dropdown' and not exists(select 1 from jsonb_array_elements(field->'options') where value->'id'=actual) then valid := false;
        elsif field->>'format'='ipv4' and not (key ~ '^(0|[1-9][0-9]{0,2})(\.(0|[1-9][0-9]{0,2})){3}$'
          and not exists(select 1 from unnest(string_to_array(key,'.')) octet where octet::integer>255)) then valid:=false;
        elsif field->>'format'='port' and not (key ~ '^[0-9]{1,5}$' and key::integer between 1 and 65535) then valid:=false;
        end if;
        if actual is not null then state := state || jsonb_build_object('config.'||(field->>'id'),actual); end if;
      end loop;
      if state ? 'setting.restarted' then state := state || '{"setting.restarted":false}'; end if;
      if v->'values' ? 'service_control' then state:= state || jsonb_build_object('setting.service_running',v->'values'->>'service_control'<>'stop'); end if;
      terminal := family='configure' and valid;
    when 'sequence_reordered' then
      valid := jsonb_typeof(v->'order')='array' and
        jsonb_array_length(v->'order')=jsonb_array_length(p->'items')
        and not exists(select 1 from jsonb_array_elements(p->'items') o where not v->'order' @> jsonb_build_array(o->'id'))
        and not exists(select 1 from jsonb_array_elements(eq->'precedence') edge
          where (select ordinality from jsonb_array_elements_text(v->'order') with ordinality where value=edge->>'before')
            >= (select ordinality from jsonb_array_elements_text(v->'order') with ordinality where value=edge->>'after'));
      state := state || jsonb_build_object('sequence.'||a.phase_id,coalesce(valid,false),'order.'||a.phase_id,v->'order');
      terminal := family='sequence' and valid;
    when 'tool_attempted' then
      select value into item from jsonb_array_elements(coalesce(eq->'tools',p->'tools')) where value->>'id'=v->>'tool_id';
      select value into destination from jsonb_array_elements(coalesce(eq->'targets',p->'targets')) where value->>'id'=a.target;
      valid := item is not null and destination is not null and
        (coalesce(item->'compatible_categories','[]')='[]' or item->'compatible_categories' @> jsonb_build_array(destination->'category'));
      if valid then state:=state || jsonb_build_object('tool.'||a.target,v->'tool_id'); end if;
      terminal := family='tool' and valid;
    when 'selection_confirmed' then
      if v->>'selection_group' is not null then
        select value into panel from jsonb_array_elements(eq->'selection_groups') where value->>'id'=v->>'selection_group';
        key:='classification.'||(v->>'selection_group');
      else panel:=p; key:='selection.'||a.phase_id; end if;
      valid := panel is not null and jsonb_typeof(v->'selected_ids')='array' and jsonb_array_length(v->'selected_ids')>0
        and not exists(select 1 from jsonb_array_elements(v->'selected_ids') id where not exists(
          select 1 from jsonb_array_elements(coalesce(panel->'options',to_jsonb(array(select jsonb_build_object('id',x) from jsonb_array_elements_text(phase->'availableObjectIds') x)))) o where o->'id'=id));
      if valid then state:=state||jsonb_build_object(key,v->'selected_ids'); end if;
      terminal:=family='select' and valid and v->>'selection_group' is null;
    when 'scenario_decision' then
      select value into item from jsonb_array_elements(p->'choices') where value->>'id'=a.target;
      valid:=item is not null;
      if valid then
        state:=state||jsonb_build_object('decision.'||a.phase_id,a.target);
        for key,actual in select * from jsonb_each(coalesce(item->'equipment_effects','{}')) loop state:=state||jsonb_build_object('setting.'||key,actual); end loop;
      end if;
      terminal:=family='decide' and valid;
    when 'diagnostic_action' then
      select value into item from jsonb_array_elements(p->'diagnostic_actions') where value->>'id'=a.target;
      valid:=item is not null and public.practice_conditions_met(item->'requires',state);
      if valid then state:=state||jsonb_build_object('fact.'||(item->>'reveals_fact_id'),true); end if;
      terminal:=family='troubleshoot' and not exists(select 1 from jsonb_array_elements_text(p->'required_fact_ids') f where state->('fact.'||f)<>'true' or state->('fact.'||f) is null);
    when 'equipment_operation' then
      select value into item from jsonb_array_elements(eq->'operations') where value->>'id'=a.target;
      valid:=item is not null and public.practice_conditions_met(item->'requires',state);
      if valid then
        for key,actual in select * from jsonb_each(coalesce(item->'effects','{}')) loop state:=state||jsonb_build_object('setting.'||key,actual); end loop;
        state:=state||jsonb_build_object('operation.'||a.target,true);
      end if;
    when 'test_started' then
      valid:=a.target=coalesce(p->>'target',a.phase_id);
      if valid then state:=state||jsonb_build_object('test_started.'||a.target,true); end if;
    when 'test_completed' then
      valid:=a.target=coalesce(p->>'target',a.phase_id) and state->>('test_started.'||a.target)='true';
      if valid then
        terminal:=jsonb_array_length(eq->'checks')>0 and not exists(select 1 from jsonb_array_elements(eq->'checks') c where not public.practice_conditions_met(c->'requires',state));
        state:=state||jsonb_build_object('result.'||a.target,jsonb_build_object('operating',terminal,'revision',revision));
        if p->>'test_reveals_fact_id' is not null then state:=state||jsonb_build_object('fact.'||(p->>'test_reveals_fact_id'),true); end if;
        terminal:=family='testRun' and (coalesce(p->>'requires_interpretation','false')='false');
      end if;
    when 'observation_recorded' then
      valid:=length(btrim(v->>'observation'))>0 and a.target=a.phase_id;
      if valid then state:=state||jsonb_build_object('observation.'||a.phase_id,v->'observation'); end if;
      terminal:=family='observe' and valid;
    when 'result_interpreted' then
      valid:=length(btrim(v->>'interpretation'))>0 and a.target=a.phase_id;
      if valid then state:=state||jsonb_build_object('interpretation.'||a.phase_id,v->'interpretation'); end if;
      terminal:=valid and (family='interpret' or family='testRun' and state ? ('result.'||coalesce(p->>'target',a.phase_id)));
    else continue;
    end case;
    if (coalesce(valid,false) or kind='configuration_applied') and kind in ('connection_created','configuration_applied','placement_attempted','sequence_reordered','scenario_decision','selection_confirmed','equipment_operation','tool_attempted') then
      revision:=revision+1; state:=state||jsonb_build_object('revision',revision);
    end if;
    if not coalesce(valid,false) and
       (kind='configuration_applied' and family='configure' or kind='sequence_reordered' and family='sequence') then
      done:=done-a.phase_id;
    elsif coalesce(valid,false) and terminal then
      done:=done||jsonb_build_object(a.phase_id,true);
    end if;
  end loop;
  for phase in select value from jsonb_array_elements(contract.definition->'phases') loop
    if phase->>'primaryInteraction'='review' then continue; end if;
    if coalesce(done->>(phase->>'id'),'false')<>'true'
      or not public.practice_conditions_met(phase->'presentation'->'equipment'->'completion',state) then
      raise exception 'PRACTICE_WORK_INCOMPLETE:%',phase->>'id' using errcode='22023';
    end if;
  end loop;
  if last_id is null then raise exception 'PRACTICE_EVIDENCE_REQUIRED'; end if;
  insert into public.practice_mission_completions(learner_id,mission_id,contract_version,evidence_through_id)
    values(p_learner,p_mission,contract.version,last_id)
    on conflict(learner_id,mission_id) do update set contract_version=excluded.contract_version,
      evidence_through_id=excluded.evidence_through_id, verified_at=now();
end $$;

create function public.practice_begin_quiz(p_learner uuid,p_coc text,p_id uuid,p_questions jsonb)
returns public.practice_quiz_attempts language plpgsql security invoker set search_path='' as $$
declare attempt public.practice_quiz_attempts;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_learner::text||p_coc,0));
  if not exists(select 1 from public.profiles where user_id=p_learner and role='learner' and status='active')
    or not public.practice_coc_unlocked(p_coc,p_learner) then raise exception 'PRACTICE_COC_LOCKED' using errcode='42501'; end if;
  if (select count(*) from public.practice_mission_completions c join public.practice_mission_contracts d using(mission_id)
      where c.learner_id=p_learner and left(c.mission_id,4)=p_coc and c.contract_version=d.version)<>5 then
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

create function public.practice_submit_quiz(p_learner uuid,p_attempt uuid,p_answers jsonb)
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
    if (select count(*) from public.practice_mission_completions c join public.practice_mission_contracts d using(mission_id)
      where c.learner_id=p_learner and left(c.mission_id,4)=attempt.coc_code and c.contract_version=d.version)<>5 then raise exception 'PRACTICAL_COMPLETION_REQUIRED'; end if;
    insert into public.practice_coc_progress(learner_id,coc_code,quiz_attempt_id) values(p_learner,attempt.coc_code,p_attempt) on conflict do nothing;
  end if;
  return attempt;
end $$;

revoke all on function public.practice_conditions_met(jsonb,jsonb), public.practice_verify_mission(uuid,text),
  public.practice_begin_quiz(uuid,text,uuid,jsonb), public.practice_submit_quiz(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.practice_conditions_met(jsonb,jsonb), public.practice_verify_mission(uuid,text),
  public.practice_begin_quiz(uuid,text,uuid,jsonb), public.practice_submit_quiz(uuid,uuid,jsonb) to service_role;
do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    alter publication supabase_realtime add table public.practice_mission_completions, public.practice_coc_progress;
  end if;
end $$;
notify pgrst,'reload schema';
commit;
