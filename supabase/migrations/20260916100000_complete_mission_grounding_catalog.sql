-- Complete the authoritative mission catalog with the scenario metadata that
-- already ships in ByteQuest-Mobile-App/lib/data/mission_scenarios_data.dart.
-- Existing nonblank database content is preserved so this migration cannot
-- overwrite later Instructor/Admin curation.

with mission_grounding (
  mission_code,
  scenario,
  objective,
  skills_assessed
) as (
  values
    (
      'coc1_m1',
      'You are hired as a junior technician in a computer repair shop. Your supervisor asks you to organize the parts and tools inventory. To complete this task, you must correctly identify all computer components and tools used in PC assembly and maintenance.',
      'Correctly identify 10 computer parts, peripherals, and tools by selecting the matching images.',
      array['Hardware component recognition', 'Tool identification', 'Visual analysis and matching', 'Technical vocabulary knowledge']::text[]
    ),
    (
      'coc1_m2',
      'A newly delivered computer unit must be assembled before it can be used in a computer laboratory. As the assigned technician, you must install the internal components properly inside the system unit case.',
      'Install the motherboard, CPU, RAM, storage device, cooling fan/heatsink, and PSU into their correct locations inside the computer case.',
      array['Component installation procedures', 'Proper handling of sensitive parts', 'Correct placement and orientation', 'Task sequencing and completion']::text[]
    ),
    (
      'coc1_m3',
      'The internal components are now installed. Your next task is to connect all power and data cables to ensure the system receives power and components can communicate with each other.',
      'Connect the 24-pin ATX cable, CPU power cable, SATA data cable, SATA power cable, and front panel connectors to their correct ports.',
      array['Cable identification', 'Port recognition', 'Proper cable management', 'Connection procedures']::text[]
    ),
    (
      'coc1_m4',
      'The hardware is fully assembled. Now you must access the BIOS/UEFI firmware, verify hardware detection, configure boot priority, and guide the operating system installation process.',
      'Configure BIOS settings correctly and follow the proper sequence for operating system installation.',
      array['BIOS/UEFI navigation', 'Boot configuration', 'Hardware verification', 'OS installation procedures']::text[]
    ),
    (
      'coc1_m5',
      'The operating system is installed, but the computer needs device drivers to function properly. As the final step, you must install all necessary drivers and perform system tests to ensure everything works correctly.',
      'Install LAN, audio, graphics, and chipset drivers, then test all hardware components (display, keyboard, mouse, audio, network) to verify functionality.',
      array['Driver installation procedures', 'Hardware testing methods', 'System verification', 'Troubleshooting basics']::text[]
    ),
    (
      'coc2_m1',
      'You are assigned to set up a local area network in a small office. Before starting, you must identify all networking devices, cables, connectors, and tools required for the installation.',
      'Correctly identify routers, switches, modems, cables, connectors, and networking tools.',
      array['Network device recognition', 'Cable and connector identification', 'Tool identification', 'Network terminology']::text[]
    ),
    (
      'coc2_m2',
      'The office needs custom-length network cables. You must create straight-through Ethernet cables by arranging the wires in the correct T568B standard sequence.',
      'Arrange the 8 Ethernet cable wires in the correct color sequence following the T568B standard.',
      array['T568B wiring standard', 'Cable termination', 'Wire sequencing', 'Attention to detail']::text[]
    ),
    (
      'coc2_m3',
      'After creating the network cables, you must verify their functionality using a LAN cable tester before installation.',
      'Use the LAN cable tester to verify cable connectivity and identify any wiring faults.',
      array['Cable testing procedures', 'Result interpretation', 'Quality assurance', 'Fault identification']::text[]
    ),
    (
      'coc2_m4',
      'With working cables ready, you must now physically connect all network devices to create a functional local area network topology.',
      'Connect computers to the switch, switch to the router, and router to the modem to establish network connectivity.',
      array['Network topology understanding', 'Device interconnection', 'Physical layer setup', 'Network architecture']::text[]
    ),
    (
      'coc2_m5',
      'The physical network is set up. Now you must configure the network settings on a client computer and test connectivity to ensure proper communication.',
      'Configure IP address, subnet mask, default gateway, and DNS server, then test the network connection.',
      array['IP configuration', 'Network parameters understanding', 'Connectivity testing', 'Troubleshooting basics']::text[]
    ),
    (
      'coc3_m1',
      'Your company needs a file server for centralized data storage and sharing. You must prepare and verify all requirements before beginning the server installation.',
      'Identify and confirm all required hardware, software, documentation, and infrastructure for server setup.',
      array['Server hardware recognition', 'Requirement analysis', 'Pre-installation planning', 'Documentation awareness']::text[]
    ),
    (
      'coc3_m2',
      'With hardware ready, you must install the server operating system following proper procedures to ensure a stable and secure server environment.',
      'Complete the server OS installation by following all required steps in the correct sequence.',
      array['OS installation procedures', 'Server configuration basics', 'Administrator account setup', 'System initialization']::text[]
    ),
    (
      'coc3_m3',
      'The server OS is installed. Now you must configure network settings with a static IP address so the server can be reliably accessed by client computers.',
      'Configure static IP address, subnet mask, default gateway, and DNS server for the server.',
      array['Static IP configuration', 'Server network setup', 'Network addressing', 'DNS configuration']::text[]
    ),
    (
      'coc3_m4',
      'Multiple employees need access to the server with different permission levels. You must create user accounts, organize them into groups, and assign appropriate permissions to shared folders.',
      'Create user accounts, assign them to groups, create shared folders, and configure access permissions.',
      array['User account management', 'Group administration', 'Permission configuration', 'Security principles']::text[]
    ),
    (
      'coc3_m5',
      'The server is configured. You must now verify that client computers can successfully access the server and complete the setup documentation.',
      'Test client connectivity, verify file access permissions, and ensure the server setup meets all requirements.',
      array['Client connectivity testing', 'Access verification', 'Troubleshooting', 'Documentation procedures']::text[]
    ),
    (
      'coc4_m1',
      'Users are reporting various computer and network issues. As a technician, you must correctly identify the root cause of each problem based on the symptoms described.',
      'Match each symptom to its correct root cause to demonstrate diagnostic skills.',
      array['Problem identification', 'Symptom analysis', 'Root cause determination', 'Diagnostic reasoning']::text[]
    ),
    (
      'coc4_m2',
      'To prevent hardware failures and extend system life, you must perform regular preventive maintenance on a computer system following proper safety procedures.',
      'Complete all preventive maintenance steps in the correct sequence, including safety precautions.',
      array['Preventive maintenance procedures', 'Safety protocols', 'Component inspection', 'Cleaning techniques']::text[]
    ),
    (
      'coc4_m3',
      'Several computers are experiencing critical hardware and software failures. You must diagnose the exact fault for each system to determine the appropriate repair action.',
      'Identify the correct hardware or software fault causing each system failure.',
      array['Hardware diagnostics', 'Software fault analysis', 'Systematic troubleshooting', 'Decision-making skills']::text[]
    ),
    (
      'coc4_m4',
      'Multiple users are experiencing network connectivity problems. You must systematically troubleshoot and identify the cause of each network issue.',
      'Troubleshoot network problems and identify the correct root cause for each connectivity issue.',
      array['Network troubleshooting', 'Connectivity diagnosis', 'Systematic problem-solving', 'Network fault identification']::text[]
    ),
    (
      'coc4_m5',
      'After diagnosing various problems, you must select the correct repair solution for each issue and document the troubleshooting process in a service report.',
      'Choose the appropriate repair action for each problem and complete proper documentation.',
      array['Solution selection', 'Repair procedures', 'Technical documentation', 'Service reporting']::text[]
    )
)
update public.missions as mission
set
  scenario = case
    when nullif(btrim(mission.scenario), '') is null then grounding.scenario
    else mission.scenario
  end,
  objective = case
    when nullif(btrim(mission.objective), '') is null then grounding.objective
    else mission.objective
  end,
  skills_assessed = case
    when cardinality(mission.skills_assessed) = 0 then grounding.skills_assessed
    else mission.skills_assessed
  end,
  updated_at = timezone('utc', now())
from mission_grounding as grounding
where mission.mission_code = grounding.mission_code;

do $$
declare
  catalog_count integer;
  incomplete_count integer;
begin
  select count(*)
  into catalog_count
  from public.missions
  where mission_code ~ '^coc[1-4]_m[1-5]$';

  select count(*)
  into incomplete_count
  from public.missions
  where mission_code ~ '^coc[1-4]_m[1-5]$'
    and (
      nullif(btrim(scenario), '') is null
      or nullif(btrim(objective), '') is null
      or cardinality(skills_assessed) = 0
    );

  if catalog_count <> 20 then
    raise exception
      'Expected 20 ByteQuest mission catalog rows, found %.',
      catalog_count;
  end if;

  if incomplete_count <> 0 then
    raise exception
      'Mission grounding catalog remains incomplete for % rows.',
      incomplete_count;
  end if;
end
$$;
