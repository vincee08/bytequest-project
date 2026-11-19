-- Re-defense revision foundation (WS1/WS3 shared schema).
--
-- Curriculum hierarchy COC -> Module -> Topic -> Learning outcome, where (owner
-- decision 2026-11-19) a Module is an official curriculum learning outcome of
-- the CSS NC II Training Regulations and the selectable learning outcomes are
-- the official performance criteria. All official text is copied from
-- docs/reference/tesda_sources/TR_current.txt (TR Computer Systems Servicing
-- NC II, Amended December 2013); PDF extraction artefacts that split single
-- words were removed, nothing else was reworded.
--
-- Also adds the shared tables later slices build on (topic progress, durable
-- module unlocks, practice run metrics), the initial practice unlock wrapper,
-- and keeps the dashboard mission catalog synchronised with the published
-- practice contracts so mobile and web never show different mission names.

begin;

create type public.content_publication_status as enum (
  'draft', 'submitted', 'needs_revision', 'evaluated', 'finalized',
  'approved', 'published', 'unpublished', 'archived'
);

-- ---------------------------------------------------------------------------
-- Modules (official curriculum learning outcomes)
-- ---------------------------------------------------------------------------
create table public.curriculum_modules (
  id uuid primary key default gen_random_uuid(),
  coc_module_id uuid not null references public.coc_modules(id) on delete restrict,
  coc_code text not null,
  code text not null,
  title text not null check (btrim(title) <> ''),
  element_title text,
  sequence_order integer not null check (sequence_order > 0),
  source_reference text not null check (btrim(source_reference) <> ''),
  created_at timestamptz not null default now(),
  unique (coc_code, code),
  unique (coc_code, sequence_order)
);

insert into public.curriculum_modules (coc_module_id, coc_code, code, title, element_title, sequence_order, source_reference)
select c.id, v.coc_code, v.code, v.title, v.element_title, v.sequence_order, v.source_reference
from (values
  ('coc1', 'LO1.1', 'Assemble computer hardware', null, 1,
   'TR CSS NC II (Amended Dec 2013) curriculum LO 1.1, TR_current.txt L3038-3039; Element 1, L1924-1939'),
  ('coc1', 'LO1.2', 'Install operating system and drivers for peripherals/devices', null, 2,
   'TR curriculum LO 1.2, L3040-3042; Element 3, L1947-1961; Element 2 "Prepare installer" (no curriculum LO), L1940-1946'),
  ('coc1', 'LO1.3', 'Install the computer application software', 'Install application software', 3,
   'TR curriculum LO 1.3, L3043-3044; Element 4, L1967-1976'),
  ('coc1', 'LO1.4', 'Conduct testing and documentation', null, 4,
   'TR curriculum LO 1.4, L3045-3046; Element 5, L1977-1988'),
  ('coc2', 'LO2.1', 'Install network cables', null, 1,
   'TR curriculum LO 2.1, L3059; Element 1, L2147-2172'),
  ('coc2', 'LO2.2', 'Set network configuration', null, 2,
   'TR curriculum LO 2.2, L3060; Element 2, L2173-2185'),
  ('coc2', 'LO2.3', 'Set router/Wi-Fi/wireless access point/repeater configuration', null, 3,
   'TR curriculum LO 2.3, L3061-3063; Element 3, L2191-2209'),
  ('coc2', 'LO2.4', 'Inspect and test the configured computer networks', null, 4,
   'TR curriculum LO 2.4, L3064-3066; Element 4, L2211-2221'),
  -- COC3 teaching sequence approved by the owner: LO3.2 before LO3.1.
  ('coc3', 'LO3.1', 'Set-up user access', null, 2,
   'TR curriculum LO 3.1, L3083; Element 1, L2360-2367'),
  ('coc3', 'LO3.2', 'Configure network services', null, 1,
   'TR curriculum LO 3.2, L3084; Element 2, L2369-2379'),
  ('coc3', 'LO3.3', 'Perform testing, documentation and pre-deployment practices',
   'Perform testing, documentation and pre-deployment procedures', 3,
   'TR curriculum LO 3.3, L3085-3087; Element 3, L2381-2389'),
  ('coc4', 'LO4.1', 'Plan and prepare for maintenance and repair', null, 1,
   'TR curriculum LO 4.1, L3104-3105; Element 1, L2481-2495'),
  ('coc4', 'LO4.2', 'Maintain computer systems and networks', null, 2,
   'TR curriculum LO 4.2, L3106-3107; Element 2, L2497-2509'),
  ('coc4', 'LO4.3', 'Diagnose faults of computer systems', 'Diagnose faults of computer systems and networks', 3,
   'TR curriculum LO 4.3, L3108-3109; Element 3, L2511-2523'),
  ('coc4', 'LO4.4', 'Rectify/correct defects in computer systems', 'Rectify/correct defects in computer systems and networks', 4,
   'TR curriculum LO 4.4, L3110-3111; Element 4, L2530-2541'),
  ('coc4', 'LO4.5', 'Inspect and test the computer systems and networks', null, 5,
   'TR curriculum LO 4.5, L3112-3114; Element 5, L2543-2560')
) as v(coc_code, code, title, element_title, sequence_order, source_reference)
join public.coc_modules c on c.coc_code = v.coc_code;

-- ---------------------------------------------------------------------------
-- Learning outcomes (official performance criteria)
-- ---------------------------------------------------------------------------
create table public.learning_outcomes (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.curriculum_modules(id) on delete restrict,
  code text not null,
  statement text not null check (btrim(statement) <> ''),
  sequence_order integer not null check (sequence_order > 0),
  source_reference text not null,
  created_at timestamptz not null default now(),
  unique (module_id, code)
);

insert into public.learning_outcomes (module_id, code, statement, sequence_order, source_reference)
select m.id, v.code, v.statement, v.sequence_order, v.source_reference
from (values
  ('coc1', 'LO1.1', '1.1', 'Unit assembly is planned and prepared to ensure OH&S policies and procedures are followed in accordance with systems requirements', 1, 'TR L1926-1928'),
  ('coc1', 'LO1.1', '1.2', 'Materials necessary to complete the work are identified and obtained in accordance with established procedures and checked against systems requirements', 2, 'TR L1929-1931'),
  ('coc1', 'LO1.1', '1.3', 'Tools, equipment and testing devices needed to carry out the installation work are obtained in accordance with established procedures and checked for correct operation and safety', 3, 'TR L1932-1935'),
  ('coc1', 'LO1.1', '1.4', 'Computer hardware is assembled in accordance with established procedures and systems requirements', 4, 'TR L1936-1937'),
  ('coc1', 'LO1.1', '1.5', 'Basic-input-output-system (BIOS) configuration is performed in accordance with hardware requirements.', 5, 'TR L1938-1939'),
  ('coc1', 'LO1.2', '2.1', 'Portable bootable devices are created in accordance with software manufacturer instruction', 1, 'TR L1940-1941 (Element 2 Prepare installer; no curriculum LO)'),
  ('coc1', 'LO1.2', '2.2', 'Customized installers are prepared in accordance with software utilization guide and end user agreement.', 2, 'TR L1942-1943 (Element 2 Prepare installer; no curriculum LO)'),
  ('coc1', 'LO1.2', '2.3', 'Installation of portable applications are carried out in accordance with software user guide and software license', 3, 'TR L1944-1946 (Element 2 Prepare installer; no curriculum LO)'),
  ('coc1', 'LO1.2', '3.1', 'Operating system (OS) is installed in accordance with established installation procedures and to comply with end-user requirements', 4, 'TR L1951-1953'),
  ('coc1', 'LO1.2', '3.2', 'Peripherals/devices drivers are installed and configured in accordance with manufacturer’s instructions and/or OS installation procedures.', 5, 'TR L1954-1956'),
  ('coc1', 'LO1.2', '3.3', 'OS and drivers updates/patches are accessed and installed in accordance with manufacturer’s recommendations and requirements', 6, 'TR L1957-1959'),
  ('coc1', 'LO1.2', '3.4', 'On-going checks of the quality of the work are undertaken in accordance with established procedures', 7, 'TR L1960-1961'),
  ('coc1', 'LO1.3', '4.1', 'Application software are installed based on software installation guides, end-user requirements and software license agreement', 1, 'TR L1969-1971'),
  ('coc1', 'LO1.3', '4.2', 'Variation to application software installation is carried out in accordance to customer/client requirements', 2, 'TR L1972-1973'),
  ('coc1', 'LO1.3', '4.3', 'Software updates are accessed and installed in accordance with manufacturer’s recommendations and requirements', 3, 'TR L1974-1976'),
  ('coc1', 'LO1.4', '5.1', 'Devices / systems and/or installation is tested to determine whether it conforms to requirements', 1, 'TR L1979-1980'),
  ('coc1', 'LO1.4', '5.2', 'Stress test is conducted to ensure reliability of equipment in accordance with manufacturer’s instructions and system requirements', 2, 'TR L1981-1983'),
  ('coc1', 'LO1.4', '5.3', '5S and 3Rs are followed according to environmental policies', 3, 'TR L1984-1985'),
  ('coc1', 'LO1.4', '5.4', 'Documentation in relation to the test is forwarded to appropriate personnel and/or authority in accordance with requirements', 4, 'TR L1986-1988'),
  ('coc2', 'LO2.1', '1.1', 'Cable routes are determined and planned in accordance with network design and actual installation site.', 1, 'TR L2149-2150'),
  ('coc2', 'LO2.1', '1.2', 'Network materials necessary to complete the work are identified and obtained in accordance with established procedures and checked against systems requirements', 2, 'TR L2151-2153'),
  ('coc2', 'LO2.1', '1.3', 'Tools, equipment and testing devices needed to carry out the installation work are obtained in accordance with established procedures and checked for correct operation and safety', 3, 'TR L2154-2157'),
  ('coc2', 'LO2.1', '1.4', 'Appropriate personal protective equipment is used and OHS policies and procedures are followed', 4, 'TR L2158-2159'),
  ('coc2', 'LO2.1', '1.5', 'Copper cable splicing is performed based on Electronic Industries Alliance/Telecommunications Industry Association (EIA/TIA) standards', 5, 'TR L2160-2163'),
  ('coc2', 'LO2.1', '1.6', 'Network cables and cable raceway are installed in accordance with established procedures and installation requirements', 6, 'TR L2164-2166'),
  ('coc2', 'LO2.1', '1.7', 'Installation work is performed and is checked to ensure no unnecessary damage has occurred and complies with requirements', 7, 'TR L2167-2168'),
  ('coc2', 'LO2.1', '1.8', 'OHS standards and 5S principles are followed according to enterprise requirements', 8, 'TR L2169-2170'),
  ('coc2', 'LO2.1', '1.9', 'Excess components and materials are disposed of based on WEEE directives and 3Rs waste management program.', 9, 'TR L2171-2172'),
  ('coc2', 'LO2.2', '2.1', 'Network connectivity of each terminal is checked in accordance with network design.', 1, 'TR L2175-2176'),
  ('coc2', 'LO2.2', '2.2', 'Any fault or problem in the network system is diagnosed and remedied in line with the standard operating procedures.', 2, 'TR L2177-2179'),
  ('coc2', 'LO2.2', '2.3', 'Network interface card (NIC) settings are configured in accordance with network design.', 3, 'TR L2180-2181'),
  ('coc2', 'LO2.2', '2.4', 'Communication checking between terminals are carried out in accordance with OS network configuration guides', 4, 'TR L2182-2183'),
  ('coc2', 'LO2.2', '2.5', 'Unplanned events or conditions are responded to in accordance with established procedures', 5, 'TR L2184-2185'),
  ('coc2', 'LO2.3', '3.1', 'Client Device systems settings are configured in accordance with manufacturers’ instructions and end-user preferences', 1, 'TR L2195-2197'),
  ('coc2', 'LO2.3', '3.2', 'Local area network (LAN) port is configured in accordance with manufacturers’ instructions and network design', 2, 'TR L2198-2200'),
  ('coc2', 'LO2.3', '3.3', 'Wide area network (WAN) port is configured in accordance with manufacturers’ instructions and network design', 3, 'TR L2201-2203'),
  ('coc2', 'LO2.3', '3.4', 'Wireless settings are configured in accordance manufacturers’ instructions, network design and end-user preferences', 4, 'TR L2204-2206'),
  ('coc2', 'LO2.3', '3.5', 'Security/Firewall/Advance settings are configured in accordance with manufacturers’ instructions and end-user preferences', 5, 'TR L2207-2209'),
  ('coc2', 'LO2.4', '4.1', 'Final inspections are undertaken to ensure that the configuration done on the computer networks conforms with the manufacturer’s instruction/manual', 1, 'TR L2215-2217'),
  ('coc2', 'LO2.4', '4.2', 'Computer networks are checked to ensure safe operation.', 2, 'TR L2218-2219'),
  ('coc2', 'LO2.4', '4.3', 'Reports are prepared/completed according to company requirements.', 3, 'TR L2220-2221'),
  ('coc3', 'LO3.1', '1.1', 'User folder is created in accordance with network operating system (NOS) features', 1, 'TR L2360-2361'),
  ('coc3', 'LO3.1', '1.2', 'User access level is configured based on NOS features and established network access policies/end-user requirements.', 2, 'TR L2362-2364'),
  ('coc3', 'LO3.1', '1.3', 'Security check is performed in accordance with established network access policies/end-user requirements.', 3, 'TR L2365-2367'),
  ('coc3', 'LO3.2', '2.1', 'Normal functions of server are checked in accordance with manufacturer’s instructions', 1, 'TR L2369-2370'),
  ('coc3', 'LO3.2', '2.2', 'Required modules/add-ons are installed/updated based on NOS installation procedures', 2, 'TR L2371-2372'),
  ('coc3', 'LO3.2', '2.3', 'Network services to be configured are confirmed based on user/system requirements', 3, 'TR L2373-2374'),
  ('coc3', 'LO3.2', '2.4', 'Operation of network services are checked based on user/system requirements', 4, 'TR L2375-2376'),
  ('coc3', 'LO3.2', '2.5', 'Unplanned events or conditions are responded to in accordance with established procedures', 5, 'TR L2377-2379'),
  ('coc3', 'LO3.3', '3.1', 'Pre-deployment procedures is undertaken based on enterprise policies and procedures', 1, 'TR L2384-2385'),
  ('coc3', 'LO3.3', '3.2', 'Operation and security check are undertaken based on end-user requirements', 2, 'TR L2386-2387'),
  ('coc3', 'LO3.3', '3.3', 'Reports are prepared/completed according to enterprise policies and procedures.', 3, 'TR L2388-2389'),
  ('coc4', 'LO4.1', '1.1', 'Maintenance and/or Diagnosis of faults is planned and prepared in line with job requirements.', 1, 'TR L2483-2484'),
  ('coc4', 'LO4.1', '1.2', 'Tools, equipment and testing devices needed for the maintenance are obtained and checked for correct operation and safety', 2, 'TR L2485-2487'),
  ('coc4', 'LO4.1', '1.3', 'Materials necessary to complete the work are obtained in accordance with established procedures and checked against job requirements.', 3, 'TR L2488-2490'),
  ('coc4', 'LO4.1', '1.4', 'OHS policies and procedures are followed in line with job requirements.', 4, 'TR L2491-2492'),
  ('coc4', 'LO4.1', '1.5', 'Computer systems and networks for maintenance are checked against job/service order or instructions and specifications.', 5, 'TR L2493-2495'),
  ('coc4', 'LO4.2', '2.1', 'Appropriate personal protective equipment is used in line with standard procedures.', 1, 'TR L2499-2500'),
  ('coc4', 'LO4.2', '2.2', 'Normal function of computer systems and networks are checked in accordance with manufacturer’s instructions.', 2, 'TR L2501-2503'),
  ('coc4', 'LO4.2', '2.3', 'Scheduled/periodic maintenance is performed in accordance with manufacturer’s requirements.', 3, 'TR L2504-2505'),
  ('coc4', 'LO4.2', '2.4', 'Where necessary, needed repairs/replacements are made in accordance with established procedures.', 4, 'TR L2506-2507'),
  ('coc4', 'LO4.2', '2.5', 'Unplanned events or conditions are responded to in accordance with established procedures', 5, 'TR L2508-2509'),
  ('coc4', 'LO4.3', '3.1', 'Appropriate personal protective equipment is used in line with standard procedures.', 1, 'TR L2514-2515'),
  ('coc4', 'LO4.3', '3.2', 'Faults or problems in the computer systems and networks are diagnosed according to requirements and in line with the standard procedures.', 2, 'TR L2516-2518'),
  ('coc4', 'LO4.3', '3.3', 'Contingency measures are managed and implemented in accordance with established procedures', 3, 'TR L2519-2521'),
  ('coc4', 'LO4.3', '3.4', 'Unplanned events or conditions are responded to in accordance with established procedures', 4, 'TR L2522-2523'),
  ('coc4', 'LO4.4', '4.1', 'Appropriate personal protective equipment is used in line with standard procedures.', 1, 'TR L2533-2534'),
  ('coc4', 'LO4.4', '4.2', 'Defective components or parts are replaced or corrected without damage to the surrounding environment or services', 2, 'TR L2535-2537'),
  ('coc4', 'LO4.4', '4.3', 'Adjustments, if necessary are made in accordance with established procedures', 3, 'TR L2538-2539'),
  ('coc4', 'LO4.4', '4.4', 'Unplanned events or conditions are responded to in accordance with established procedures.', 4, 'TR L2540-2541'),
  ('coc4', 'LO4.5', '5.1', 'Final inspections are undertaken to ensure that the testing conducted on the device conforms with the manufacturer’s instruction/manual', 1, 'TR L2546-2548'),
  ('coc4', 'LO4.5', '5.2', 'Computer systems and networks are checked/tested to ensure safe operation.', 2, 'TR L2549-2550'),
  ('coc4', 'LO4.5', '5.3', 'OHS standards and 5S principles are followed according to enterprise policies', 3, 'TR L2551-2552'),
  ('coc4', 'LO4.5', '5.4', 'Work site is cleaned and cleared of all debris and left in safe condition in accordance with company procedures', 4, 'TR L2553-2555'),
  ('coc4', 'LO4.5', '5.5', 'Excess components and materials are disposed of based on WEEE directives and 3Rs waste management program.', 5, 'TR L2556-2558'),
  ('coc4', 'LO4.5', '5.6', 'Report is prepared and completed according to company requirements', 6, 'TR L2559-2560')
) as v(coc_code, module_code, code, statement, sequence_order, source_reference)
join public.curriculum_modules m on m.coc_code = v.coc_code and m.code = v.module_code;

-- ---------------------------------------------------------------------------
-- Topics (admin-managed lessons) and their publication workflow
-- ---------------------------------------------------------------------------
create table public.curriculum_topics (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.curriculum_modules(id) on delete restrict,
  sequence_order integer not null default 1 check (sequence_order > 0),
  created_by uuid references public.profiles(user_id) on delete set null,
  created_at timestamptz not null default now(),
  archived_at timestamptz
);
create index curriculum_topics_module_idx on public.curriculum_topics(module_id, sequence_order);

create table public.curriculum_topic_revisions (
  id uuid primary key default gen_random_uuid(),
  topic_id uuid not null references public.curriculum_topics(id) on delete restrict,
  revision_number integer not null check (revision_number > 0),
  title text not null check (btrim(title) <> '' and length(title) <= 200),
  summary text check (summary is null or length(summary) <= 1000),
  body_markdown text not null default '' check (length(body_markdown) <= 60000),
  outcome_ids uuid[] not null default '{}',
  status public.content_publication_status not null default 'draft',
  author_id uuid references public.profiles(user_id) on delete set null,
  submitted_at timestamptz,
  evaluated_by uuid references public.profiles(user_id) on delete set null,
  evaluated_at timestamptz,
  evaluation_notes text,
  finalized_by uuid references public.profiles(user_id) on delete set null,
  finalized_at timestamptz,
  approved_by uuid references public.profiles(user_id) on delete set null,
  approved_at timestamptz,
  published_by uuid references public.profiles(user_id) on delete set null,
  published_at timestamptz,
  unpublished_by uuid references public.profiles(user_id) on delete set null,
  unpublished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (topic_id, revision_number)
);
create index curriculum_topic_revisions_status_idx on public.curriculum_topic_revisions(topic_id, status);
create trigger trg_curriculum_topic_revisions_updated_at
  before update on public.curriculum_topic_revisions
  for each row execute function public.set_updated_at();

create table public.content_publication_events (
  id bigint generated always as identity primary key,
  entity_type text not null check (entity_type in ('topic')),
  entity_id uuid not null,
  revision_id uuid,
  from_status public.content_publication_status,
  to_status public.content_publication_status not null,
  actor_id uuid references public.profiles(user_id) on delete set null,
  note text,
  occurred_at timestamptz not null default now()
);
create index content_publication_events_entity_idx on public.content_publication_events(entity_type, entity_id, occurred_at);
create trigger trg_content_publication_events_append_only
  before update or delete on public.content_publication_events
  for each row execute function private.prevent_append_only_mutation();

-- ---------------------------------------------------------------------------
-- Mission and assessment-activity placement in the curriculum
-- ---------------------------------------------------------------------------
create table public.mission_curriculum_links (
  mission_code text primary key references public.missions(mission_code) on delete restrict,
  module_id uuid not null references public.curriculum_modules(id) on delete restrict,
  pc_codes text[] not null default '{}',
  sequence_order integer not null check (sequence_order > 0)
);

insert into public.mission_curriculum_links (mission_code, module_id, pc_codes, sequence_order)
select v.mission_code, m.id, v.pc_codes, v.sequence_order
from (values
  ('coc1_m1', 'coc1', 'LO1.1', array['1.1','1.2','1.3'], 1),
  ('coc1_m2', 'coc1', 'LO1.1', array['1.4'], 2),
  ('coc1_m3', 'coc1', 'LO1.2', array['1.5','2.1','3.1'], 1),
  ('coc1_m4', 'coc1', 'LO1.2', array['3.2','3.3'], 2),
  ('coc1_m5', 'coc1', 'LO1.4', array['5.1','5.2','5.4'], 1),
  ('coc2_m1', 'coc2', 'LO2.1', array['1.1','1.2','1.3','1.4'], 1),
  ('coc2_m2', 'coc2', 'LO2.1', array['1.5','1.7'], 2),
  ('coc2_m3', 'coc2', 'LO2.1', array['1.6','1.8','2.1'], 3),
  ('coc2_m4', 'coc2', 'LO2.2', array['2.1','2.3','2.4'], 1),
  ('coc2_m5', 'coc2', 'LO2.4', array['2.2','4.1','4.2'], 1),
  ('coc3_m1', 'coc3', 'LO3.2', array['2.1','2.3'], 1),
  ('coc3_m2', 'coc3', 'LO3.2', array['2.2'], 2),
  ('coc3_m3', 'coc3', 'LO3.1', array['1.1','1.2','1.3'], 1),
  ('coc3_m4', 'coc3', 'LO3.2', array['2.3','2.4'], 3),
  ('coc3_m5', 'coc3', 'LO3.3', array['3.1','3.2','3.3'], 1),
  ('coc4_m1', 'coc4', 'LO4.1', array['1.1','1.2','1.3','1.4','1.5'], 1),
  ('coc4_m2', 'coc4', 'LO4.3', array['3.1','3.2','4.2'], 1),
  ('coc4_m3', 'coc4', 'LO4.3', array['3.2','3.3'], 2),
  ('coc4_m4', 'coc4', 'LO4.4', array['4.1','4.2','4.3'], 1),
  ('coc4_m5', 'coc4', 'LO4.5', array['5.1','5.2','5.3','5.4','5.5','5.6'], 1)
) as v(mission_code, coc_code, module_code, pc_codes, sequence_order)
join public.curriculum_modules m on m.coc_code = v.coc_code and m.code = v.module_code;

create table public.activity_curriculum_links (
  activity_version_id uuid primary key references public.activity_versions(id) on delete restrict,
  module_id uuid not null references public.curriculum_modules(id) on delete restrict,
  delivery_kind text not null check (delivery_kind in ('simulation', 'form_based', 'protected_reference')),
  linked_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Learner progression records shared by later slices
-- ---------------------------------------------------------------------------
create table public.learner_topic_progress (
  learner_id uuid not null references public.profiles(user_id) on delete restrict,
  topic_id uuid not null references public.curriculum_topics(id) on delete restrict,
  revision_id uuid references public.curriculum_topic_revisions(id) on delete restrict,
  completed_at timestamptz not null default now(),
  primary key (learner_id, topic_id)
);

create table public.learner_module_unlocks (
  learner_id uuid not null references public.profiles(user_id) on delete restrict,
  module_id uuid not null references public.curriculum_modules(id) on delete restrict,
  unlocked_at timestamptz not null default now(),
  reason text not null check (reason in ('sequence', 'bypass', 'migration')),
  primary key (learner_id, module_id)
);

create table public.practice_mission_runs (
  id uuid primary key default gen_random_uuid(),
  learner_id uuid not null references public.profiles(user_id) on delete restrict,
  mission_id text not null,
  contract_version text not null,
  run_number integer not null check (run_number > 0),
  started_at timestamptz,
  ended_at timestamptz,
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),
  action_count integer not null default 0 check (action_count >= 0),
  invalid_count integer not null default 0 check (invalid_count >= 0),
  correction_count integer not null default 0 check (correction_count >= 0),
  outcome text not null check (outcome in ('verified', 'incomplete')),
  step_results jsonb not null default '{}'::jsonb,
  failure_code text,
  created_at timestamptz not null default now()
);
create index practice_mission_runs_learner_idx on public.practice_mission_runs(learner_id, mission_id, created_at);
create trigger trg_practice_mission_runs_append_only
  before update or delete on public.practice_mission_runs
  for each row execute function private.prevent_append_only_mutation();

-- Initial practice unlock rule: identical to the current COC-level rule.
-- The sequential-unlocking slice replaces this body with module-level logic.
create function public.practice_mission_unlocked(p_mission text, p_learner uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select public.practice_coc_unlocked(left(p_mission, 4), p_learner)
$$;
revoke all on function public.practice_mission_unlocked(text, uuid) from public, anon;
grant execute on function public.practice_mission_unlocked(text, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Canonical mission catalog: the dashboard catalog follows the published
-- practice contracts (the missions learners actually run).
-- ---------------------------------------------------------------------------
create table public.mission_catalog_history (
  id bigint generated always as identity primary key,
  mission_code text not null,
  previous jsonb not null,
  replaced_at timestamptz not null default now()
);
create trigger trg_mission_catalog_history_append_only
  before update or delete on public.mission_catalog_history
  for each row execute function private.prevent_append_only_mutation();

create function public.sync_mission_catalog_from_contract()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_mission public.missions;
  v_title text := nullif(btrim(new.definition->>'title'), '');
  v_scenario text := nullif(btrim(new.definition->>'scenario'), '');
  v_guidance text := nullif(btrim(new.definition->>'practiceGuidance'), '');
  v_skills text[];
begin
  select * into v_mission from public.missions where mission_code = new.mission_id;
  if not found or v_title is null then
    return new;
  end if;
  select coalesce(array_agg(phase->>'title' order by ordinality), '{}')
  into v_skills
  from jsonb_array_elements(new.definition->'phases') with ordinality as p(phase, ordinality)
  where coalesce(phase->>'primaryInteraction', '') <> 'review'
    and nullif(btrim(phase->>'title'), '') is not null;
  if v_mission.title is distinct from v_title or v_mission.scenario is distinct from v_scenario then
    insert into public.mission_catalog_history (mission_code, previous)
    values (v_mission.mission_code, jsonb_build_object(
      'title', v_mission.title, 'scenario', v_mission.scenario,
      'objective', v_mission.objective, 'skills_assessed', to_jsonb(v_mission.skills_assessed),
      'contract_version', new.version));
    update public.missions
    set title = v_title,
        scenario = coalesce(v_scenario, scenario),
        objective = case when v_mission.title is distinct from v_title then coalesce(v_guidance, objective) else objective end,
        skills_assessed = case when v_mission.title is distinct from v_title and cardinality(v_skills) > 0 then v_skills else skills_assessed end,
        updated_at = now()
    where id = v_mission.id;
  end if;
  return new;
end
$$;
revoke all on function public.sync_mission_catalog_from_contract() from public, anon, authenticated;

create trigger trg_practice_contract_syncs_catalog
  after insert or update of definition on public.practice_mission_contracts
  for each row execute function public.sync_mission_catalog_from_contract();

-- Apply once to the currently published contracts.
update public.practice_mission_contracts set definition = definition;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------
alter table public.curriculum_modules enable row level security;
alter table public.learning_outcomes enable row level security;
alter table public.curriculum_topics enable row level security;
alter table public.curriculum_topic_revisions enable row level security;
alter table public.content_publication_events enable row level security;
alter table public.mission_curriculum_links enable row level security;
alter table public.activity_curriculum_links enable row level security;
alter table public.learner_topic_progress enable row level security;
alter table public.learner_module_unlocks enable row level security;
alter table public.practice_mission_runs enable row level security;
alter table public.mission_catalog_history enable row level security;

-- Official curriculum structure is readable by every active signed-in user.
create policy curriculum_modules_read on public.curriculum_modules
  for select to authenticated using (public.is_active_user());
create policy learning_outcomes_read on public.learning_outcomes
  for select to authenticated using (public.is_active_user());
create policy mission_curriculum_links_read on public.mission_curriculum_links
  for select to authenticated using (public.is_active_user());
create policy activity_curriculum_links_read on public.activity_curriculum_links
  for select to authenticated using (public.is_staff());

-- Topics: staff see every topic; learners see topics that have a published revision.
create policy curriculum_topics_read on public.curriculum_topics
  for select to authenticated using (
    public.is_staff()
    or (public.is_active_user() and archived_at is null and exists (
      select 1 from public.curriculum_topic_revisions r
      where r.topic_id = curriculum_topics.id and r.status = 'published'))
  );
create policy curriculum_topic_revisions_read on public.curriculum_topic_revisions
  for select to authenticated using (
    public.is_staff() or (public.is_active_user() and status = 'published')
  );
create policy content_publication_events_read on public.content_publication_events
  for select to authenticated using (public.is_staff());

-- Learner progression: own rows, owning instructor, admin.
create policy learner_topic_progress_read on public.learner_topic_progress
  for select to authenticated using (
    learner_id = (select auth.uid()) or public.is_admin()
    or private.current_instructor_teaches_learner(learner_id)
  );
create policy learner_module_unlocks_read on public.learner_module_unlocks
  for select to authenticated using (
    learner_id = (select auth.uid()) or public.is_admin()
    or private.current_instructor_teaches_learner(learner_id)
  );
create policy practice_mission_runs_read on public.practice_mission_runs
  for select to authenticated using (
    learner_id = (select auth.uid()) or public.is_admin()
    or private.current_instructor_teaches_learner(learner_id)
  );
create policy mission_catalog_history_read on public.mission_catalog_history
  for select to authenticated using (public.is_staff());

-- Clients read only; all writes come from service-only functions and triggers.
grant select on public.curriculum_modules, public.learning_outcomes, public.curriculum_topics,
  public.curriculum_topic_revisions, public.content_publication_events, public.mission_curriculum_links,
  public.activity_curriculum_links, public.learner_topic_progress, public.learner_module_unlocks,
  public.practice_mission_runs, public.mission_catalog_history to authenticated;
grant all on public.curriculum_modules, public.learning_outcomes, public.curriculum_topics,
  public.curriculum_topic_revisions, public.content_publication_events, public.mission_curriculum_links,
  public.activity_curriculum_links, public.learner_topic_progress, public.learner_module_unlocks,
  public.practice_mission_runs, public.mission_catalog_history to service_role;

comment on table public.curriculum_modules is
  'Official CSS NC II curriculum learning outcomes (TR Amended Dec 2013) used as ByteQuest modules. sequence_order is the teaching/unlock order.';
comment on table public.learning_outcomes is
  'Official performance criteria under each module; selectable intended learning outcomes for quizzes and assessments.';
comment on table public.practice_mission_runs is
  'Server-computed practice run metrics (attempt number, duration, invalid actions, corrections, per-step results). Append-only.';

notify pgrst, 'reload schema';

commit;
