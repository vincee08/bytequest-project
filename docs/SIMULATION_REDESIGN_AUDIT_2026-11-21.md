# ByteQuest simulation redesign: Phase 1 audit and mission-to-simulation mapping

Date: 2026-11-21. Scope: all 20 missions (COC1–COC4). No code was changed for this audit.

## 1. Method and sources

Every fact below comes from the application or the published assessment data, not from memory:

- **Mission definitions.** The 20 `MissionSimulationDefinition`s were extracted from the running Flutter code: phase ids, titles, instructions, interaction family, component, objects, equipment and checks.
- **Assessment packages.** The 20 published simulation assessment packages supplied the 106 criteria. They are identical, byte for byte, to production (verified 2026-11-20).
- **Curriculum links.** Each mission's curriculum module comes from production (`activity_curriculum_links`).
- **Renderers.** The screens that draw each phase are in `lib/screens/simulation/components/` and `lib/screens/simulation/interactions/`.

## 2. Constraints the redesign must respect

1. **Scoring contracts are pinned.**
   - Each mission is scored on the server from evidence keyed by phase id and simulation state. Examples: `placed.cpu = cpu_socket`, `setting.cpu_lever = closed`, `link.sata_data>drive_data`, `config.device_mode = automatic`, `sequence.coc4_m4_p1 = true`, `result.<test> = true`, `interpretation.<phase>`.
   - Allowed mistakes are fixed per criterion. Safety-critical criteria allow 0 mistakes: COC1 M1 S2_SAFETY, COC1 M2 C1/C3, COC2 M2 S1_SAFETY, COC4 M4 S1_SAFETY and COC4 M5 S2_SAFETY. All others allow 2.
   - The app refuses an assessment whose contract version differs from its own:

     | Contract | Missions |
     |---|---|
     | `css-sag-20261109-v3` | COC1 M1 |
     | `css-assembly-20261119-v3` | COC1 M2 |
     | `css-sag-20261011-v2` | COC1 M3 – COC3 M5 |
     | `css-sag-20261009-v1` | COC4 |

2. **Labs are presentation-only.**
   - A realistic lab is a new way to perform the **same** actions: the same phase ids, object ids, operations, connections, configuration fields, sequences, tests and interpretations.
   - This keeps every contract, rubric, recorded attempt and the instructor Evaluation Center unchanged, and needs no database change.
   - A lab that needs new steps or different conditions needs a new contract version, republishing in production and a new APK. Each such case is flagged below and needs approval.
3. **Assessment mode.** Positions, slots, ports and stations must not reveal answers. Wrong actions are recorded rather than corrected, and practice-only guidance stays hidden.
4. **Orientation.** The app allows portrait and landscape (`main.dart`), so labs can use a side inventory in landscape and a bottom drawer in portrait.
5. **APK.** Neither original signing key (`a4d01056…` learners' build, `dc85ef75…` 11-13 production key) is on this PC, so per the owner's rule no release APK will be produced. Debug builds are used for emulator testing.

## 3. How the missions run today

- **COC1 M2 is a realistic lab.** The 2D assembly bench (since 2026-11-19) has photos of real parts on a mat and an open case. Learners drag or tap parts into place, rotate them, operate the CPU lever, latches and screwdriver, connect cables to headers, and run POST with faults that must be fixed on the bench.
- **The other 19 use a generic pattern.** A tile grid (photo or icon) with *Place equipment / Connect ports / Inspect* modes sits above a task panel that changes per phase:
  - an inspect list;
  - multi-select or tool chips;
  - dropdown and text configuration forms;
  - a reorder list with arrows;
  - option cards for decisions;
  - buttons that reveal diagnostic facts;
  - a *Run test* readout with a typed interpretation.
- **The task is real, the look is not.** The procedures are realistic (for example, COC4 M4 requires isolating power before removing a card). But the screens look like forms and grids: positions and stations are plain boxes, and software tasks are dropdowns rather than the software itself.

## 4. Summary mapping

Lab types (from the brief): **A** PC assembly, **B** hardware installation or replacement, **C** cable connection, **D** network configuration, **E** troubleshooting, **F** software installation or configuration, **G** other mission-specific.

| Mission | LO | Practical task (from the mission) | Today | Proposed lab | Effort |
|---|---|---|---|---|---|
| COC1 M1 Identify Computer Parts and Tools | 1.1 | Inspect a de-energized desktop, identify part roles, notice the open memory latch, pick a safe tool set, write observations | tile grid + inspect list + multi-select + text | **B** motherboard inspection bench with real hotspots and a tool tray | M |
| COC1 M2 Install Internal Components | 1.1 | Build a desktop from parts and pass POST | **realistic bench (A)** | **A** keep; polish (landscape inventory) | S |
| COC1 M3 Install and Configure a Workstation OS | 1.2 | UEFI/AHCI setup, install the OS to a GPT disk from USB, install the network driver, restart, verify | tile grid + dropdowns + reorder list | **F** UEFI setup utility, OS installer wizard, Device Manager, plus plugging in the USB | L |
| COC1 M4 Connect and Configure Peripheral Devices | 1.2 | Connect HDMI monitor, USB keyboard and mouse, Ethernet; set 1920×1080 and automatic addressing; test | tile grid + tool chips + port boxes | **C** rear I/O panel with real cable ends, then **F** display and adapter settings | M |
| COC1 M5 Install Drivers and Test the System | 1.4 | Storage subsystem unavailable after assembly: diagnose, correct, load-test | tile grid + fact buttons + options | **E** + **F** BIOS storage view, Disk Management or Device Manager, cable log, reseat the link | M–L |
| COC2 M1 Identify Network Devices and Tools | 2.1 | Identify cable materials and tools, prepare and terminate a run, test the wire map | tile grid + tool chips + reorder list | **G** cable preparation bench (cutter, stripper, crimper, tester) | M |
| COC2 M2 Create Network Cables | 2.1 | PPE, T568B termination, connect the topology, configure the interface, verify | tile grid + form + colour reorder list | **G** RJ45 T568B crimping lab, then **D** topology links | L |
| COC2 M3 Construct and Verify a Network Topology | 2.1 | Build a switched star, test links, repair the damaged segment, verify | tile grid + selection + boxes | **D** topology canvas with device photos and port-to-port cables | M |
| COC2 M4 Configure Network Devices | 2.2 | Place the router, switch and repeater; set IP, mask, gateway, SSID and WPA2/AES; ping; correct and retest | tile grid + forms | **D** + **F** device admin pages and a ping console | L |
| COC2 M5 Troubleshoot Network Connectivity | 2.4 | Client cannot reach a service: inspect, test, diagnose progressively, fix IP settings, retest | tile grid + fact buttons + form | **E** topology with link LEDs and a client console (`ipconfig`/`ping`/`tracert`) | M |
| COC3 M1 Prepare Server Setup Requirements | 3.2 | Verify power conditioning, network drop, RAM and storage, media; decide the role; readiness checks | tile grid + options + reorder list | **G** server-room readiness walk-through with readable device panels | M |
| COC3 M2 Install and Configure Server OS | 3.2 | Choose the role, host name BQ-FS01 and IP 192.168.30.10; install; restart; verify services | tile grid + form + reorder list | **F** server OS installer and first-boot configuration | L |
| COC3 M3 Manage Users, Groups, and Permissions | 3.1 | Create the technician account, Support group and Modify on the share; diagnose a denied action; fix; retest | tile grid + forms + fact buttons | **F** users and groups console, folder Security tab, client session test | L |
| COC3 M4 Configure and Test Server Services | 3.2 | File service on TCP 445 with automatic start; start, stop, restart; client test; interpret | tile grid + forms | **F** Services console (properties, start/stop/restart) and a client share test | M–L |
| COC3 M5 Test Client Access and Document Setup | 3.3 | Client lost access: inspect client, server, service, permissions and path; correct; retest | tile grid + fact buttons + options | **E** client/server troubleshooting with real error and console views | M |
| COC4 M1 Identify System and Network Problems | 4.1 | Triage a PC that cannot reach the file server: inspect, observe, prioritize, preliminary diagnosis, verify | inspect list + text + options | **E** service-desk triage scene (desk PC, tray status, Event Viewer) | M |
| COC4 M2 Diagnose and Repair Hardware Faults | 4.3 | Intermittent stops: inspect seating and indicators; memory, storage and power tests; interpret; repair; verify | fact buttons + options | **E** open-case bench with multimeter, memory and storage diagnostics | L |
| COC4 M3 Diagnose Hardware and Software Faults | 4.3 | Application and network symptoms: logs, adapter, service, route trace; two interpretations | inspect list + fact buttons + text | **E** + **F** Event Viewer, Device Manager, Services, `tracert` | M |
| COC4 M4 Replace and Reconfigure a Component | 4.4 | Isolate power and use ESD protection; remove the failed NIC; fit, align and fasten the PCIe NIC; driver and automatic addressing; test | reorder list + select-and-confirm dialog ("aligned / rotated") + form | **B** PCIe card replacement on the bench engine (physical removal, alignment, screw), then **F** | M–L |
| COC4 M5 Apply Repair Action and Create Report | 4.5 | Five service tickets: diagnose each with the right tool, repair, test, final verify and report | fact buttons + options + text | **G/E** service-desk lab: ticket board, port and cable testers, driver installs, report form | L |

Effort: S ≈ under half a day, M ≈ about a day, L ≈ 1.5–2 days, each including tests and an emulator check.

## 5. Per-mission detail

For each mission:
- **Rubric** lists the published criteria. "≤n" is the allowed number of mistakes; "SAFETY" marks a zero-tolerance criterion.
- **Contract notes** say what evidence the new lab must keep producing.

### COC1 M1 — Identify Computer Parts and Tools (LO1.1, `css-sag-20261109-v3`)
- **Task:** inspect a de-energized desktop before servicing. The memory latch is open. Identify component roles, isolate abnormalities, and record a safe work plan.
- **Parts and tools:** motherboard, processor, memory module, power supply, CPU socket, DIMM slot, 24-pin ATX header, anti-static wrist strap, Phillips screwdriver.
- **Today:**
  1. Inspect hardware (tap list).
  2. Select a safe set (multi-select).
  3. Record observations (text).
  4. Verify readiness (test).
  5. Review.
- **Lab B:**
  - A motherboard and open-case photo with hotspots on the real socket, DIMM slots (one latch visibly open) and 24-pin header. Tapping a hotspot opens a magnified view with the condition.
  - A tool tray with the wrist strap, screwdriver and plausible distractors.
  - Observation notes written beside the inspected part.
- **Correct:** every part inspected, ESD strap plus screwdriver chosen, observation limited to what is visible.
- **Incorrect:** a powered or unsafe tool choice; an inferred fault that was not observed.
- **Rubric:** S1 Inspect hardware ≤2, S2 Select a safe set ≤2, **S2_SAFETY ESD protection and a de-energized safe work set (0)**, S3 Record observations ≤2, S4 Verify readiness ≤2.
- **Contract notes:** keep `inspected.<part>` for the seven parts, the same selection ids and the observation record.

### COC1 M2 — Install Internal Components (LO1.1, `css-assembly-20261119-v3`)
- **Task:** build a working desktop from inspected parts: prepare the motherboard on the anti-static mat, install it in the case, connect power and data, then pass the power-on self-test.
- **Parts and tools:** case, motherboard, CPU, cooler and thermal compound, two DDR4 modules, PSU, HDD, I/O shield, Phillips screwdriver, wrist strap, the cables (24-pin, EPS 8-pin, SATA power, SATA data, front panel, CPU fan).
- **Today:** the realistic bench (lab A) across six phases: work area, motherboard, case, cables, POST, review.
- **Proposal:** keep the bench as is. Polish the landscape layout (inventory on the right) and the portrait inventory drawer.
- **Rubric:** **C1 ESD (0)**, C2 Inspect ≤2, **C3 CPU orientation and lever (0)**, C4 Cooler and CPU_FAN ≤2, C5 DIMM_A2/B2 and latches ≤2, C6 PSU ≤2, C7 Board, standoffs and I/O shield ≤2, C8 Drive ≤2, C9 Power cables ≤2, C10 SATA data and front panel ≤2, C11 POST and interpretation ≤2.
- **Contract notes:** no change.

### COC1 M3 — Install and Configure a Workstation OS (LO1.2, `css-sag-20261011-v2`)
- **Task:** install a workstation OS on a blank GPT drive using UEFI installation media. Configure the storage mode, install the network driver, restart, and verify boot and device readiness.
- **Hardware and software:** workstation, bootable USB, GPT system disk, driver media, firmware (UEFI) setup, OS installer, network adapter driver, application and updates.
- **Today:**
  1. Configure setup (dropdowns: boot mode, storage controller, install target; plus the place-equipment grid).
  2. Install the OS (reorder list).
  3. Driver and restart (dropdown and buttons).
  4. Verify and interpret.
  5. Review.
- **Lab F (plus a small B step):**
  - Plug the bootable USB into the workstation's front port.
  - A UEFI setup utility with tabs and arrow-key-style lists: Boot Mode UEFI, SATA Mode AHCI, boot order with USB first.
  - An installer wizard: select the internal GPT disk (the USB is also listed as a trap), copy files with progress, configure.
  - A Device Manager-style driver install: Ethernet versus wireless driver.
  - Restart, then a boot and device status screen to interpret.
- **Correct and incorrect:** from the fields and checks. For example, Legacy BIOS boot mode or the USB as install target is wrong; the wrong driver fails the "Network adapter" check.
- **Rubric:** S1–S4, each ≤2.
- **Contract notes:**
  - Keep the configuration field ids and values (boot mode, storage controller mode, installation target, network adapter driver).
  - Keep the sequence ids `boot_media / select_disk / copy_files / configure_device`.
  - Keep the operations (run installation, create verified bootable USB, restart, install application, apply updates) and the test.

### COC1 M4 — Connect and Configure Peripheral Devices (LO1.2, `css-sag-20261011-v2`)
- **Task:** connect a 1920 × 1080 HDMI monitor, a USB keyboard and mouse, and an Ethernet adapter. Configure the native resolution and automatic network addressing before testing.
- **Today:**
  1. Inspect peripherals (plus place-equipment grid).
  2. Choose a tool.
  3. Connect devices (boxes for "hdmi port / usb port / ethernet port").
  4. Run and interpret the device test.
  5. Review.
- **Lab C, then F:**
  - A photo of the system unit's rear I/O panel with real ports.
  - Cables with real connector ends (HDMI, USB-A from the keyboard and mouse, RJ45). Drag or tap a cable end to a port: a wrong port shows a red state and is refused or recorded.
  - Then Display settings (resolution list) and adapter properties (obtain an address automatically), followed by the device test.
- **Rubric:** S1–S4, each ≤2.
- **Contract notes:**
  - Keep the link ids `monitor>hdmi_port`, `keyboard/mouse>usb_port` and `network_adapter>ethernet_port`, the tool targets, and the test checks (display signal, USB input, network adapter, safety and documentation).
  - Resolution and addressing are already carried by the test conditions. If they need separate fields, that is a contract change and needs approval.

### COC1 M5 — Install Drivers and Test the System (LO1.4, `css-sag-20261011-v2`)
- **Task:** a newly assembled workstation reports an integration fault: it starts, but the storage subsystem is unavailable.
- **Today:**
  1. Inspect the symptom (fact button plus place grid).
  2. Choose a diagnostic tool (firmware storage console versus display calibrator).
  3. Troubleshoot progressively (three fact buttons).
  4. Apply the correction (options).
  5. Verify integration (load test).
  6. Review.
- **Lab E/F:**
  - A desk scene with the PC booting.
  - Firmware storage page showing the drive missing or detected.
  - Device Manager and Disk Management views.
  - A cable/connection log.
  - The correction is done physically: reseat the SATA data link inside the case (bench view). Then a monitored load-test window.
- **Rubric:** S1–S5, each ≤2.
- **Contract notes:** keep the diagnostic action ids (each reveals one fact), the tool ids, the correction option id, and the operations and checks.

### COC2 M1 — Identify Network Devices and Tools (LO2.1, `css-sag-20261011-v2`)
- **Task:** prepare a cable run for a small workstation network using the protected route and PVC raceway.
- **Materials and tools:** copper cable, RJ45 connectors, wire stripper, crimping tool, LAN cable tester.
- **Today:**
  1. Identify materials (tool chips plus place grid).
  2. Select tools.
  3. Sequence preparation (reorder list: measure and cut, strip, arrange and trim, insert and crimp, inspect).
  4. Connect the cable to the tester.
  5. Test and interpret.
  6. Review.
- **Lab G (cable preparation bench):**
  - Real tool photos on a bench.
  - Pick the right tool for each step, then perform the steps on a cable graphic: cut to length, strip the jacket, untwist and arrange, insert and crimp, inspect.
  - Plug both ends into the tester and read the wire-map LEDs.
- **Rubric:** S1–S5, each ≤2.
- **Contract notes:** the order in which the learner performs the steps must produce the same `sequence.coc2_m1_p3` evidence as the current list. Keep the tool target ids and the tester link.

### COC2 M2 — Create Network Cables (LO2.1, `css-sag-20261011-v2`)
- **Task:** prepare a standards-based (T568B) cable and use it in a device topology.
- **Today:**
  1. Inspect topology (PPE/ESD check, termination tool choice: crimping versus punch-down; plus place grid).
  2. Prepare the golden cable (reorder eight colour names).
  3. Connect devices (workstation → switch → router).
  4. Configure devices (auto-negotiate, physical link inspected).
  5. Verify connectivity (tester).
  6. Review.
- **Lab G, then D (RJ45 crimping lab):**
  - Put on PPE first.
  - Pick the crimping tool.
  - Drag each of the eight coloured conductors into the connector's pin channels 1–8 (the T568B order is not shown in assessment mode). Then insert and crimp.
  - The wire-map tester shows 1–8 lights, with a crossed or split pair visible.
  - Then cable the workstation to the switch to the router, and set auto-negotiation.
- **Rubric:** S1 Inspect topology ≤2, **S1_SAFETY PPE and ESD before cable work (0)**, S2 Prepare golden cable ≤2, S3 Connect devices ≤2, S4 Configure devices ≤2, S5 Verify connectivity ≤2.
- **Contract notes:** filling pins 1–8 must emit the same colour-order evidence (`white_orange, orange, white_green, blue, white_blue, green, white_brown, brown`) that the reorder list emits today.

### COC2 M3 — Construct and Verify a Network Topology (LO2.1, `css-sag-20261011-v2`)
- **Task:** build a switched star in which both workstations and the router connect to the switch and the switch connects to the server. Then isolate and repair a damaged cable segment.
- **Today:**
  1. Select nodes (plus place grid).
  2. Connect topology (source and destination boxes).
  3. Test links.
  4. Fix the invalid link (options).
  5. Verify topology.
  6. Review.
- **Lab D:**
  - A topology canvas with real device photos (router, switch, two workstations, server), each with visible ports.
  - Drag a cable from port to port. Link LEDs come on after testing, and the damaged segment shows a fault.
  - Replace or re-terminate the cable, then verify.
- **Rubric:** S1–S5, each ≤2.
- **Contract notes:** keep the link pairs (each workstation and the router to the switch, the switch to the server), the test ids and the repair option id.

### COC2 M4 — Configure Network Devices (LO2.2, `css-sag-20261011-v2`)
- **Task:**
  - Configure the managed switch with IP 192.168.10.2, mask 255.255.255.0 and gateway 192.168.10.1.
  - Configure the router and a bridged repeater with SSID BQ-LAB, WPA2/AES, a DHCP WAN uplink and inbound filtering.
  - A client at 192.168.10.24 must then reach the management service.
- **Today:**
  1. Select the device (plus place grid: router, switch, repeater).
  2. Configure the network (form).
  3. Test.
  4. Interpret.
  5. Correct and retest.
  6. Review.
- **Lab D/F:**
  - Place the devices in the room plan.
  - Open each device's admin page: a switch management IP page, and router wireless and security pages.
  - Run `ping` from the client's command prompt, read the output, correct the wrong value, and run it again.
- **Rubric:** S1–S5, each ≤2.
- **Contract notes:** keep the configuration field ids (interface IPv4, mask, gateway, SSID, wireless security, corrected value), the test checks and the interpretation record.

### COC2 M5 — Troubleshoot Network Connectivity (LO2.4, `css-sag-20261011-v2`)
- **Task:** a workstation cannot reach a service across the local topology.
- **Today:**
  1. Inspect the topology and configuration (facts plus place grid).
  2. Test.
  3. Troubleshoot progressively (link state, interface configuration, route probe).
  4. Apply the network fix (IP, mask, gateway form).
  5. Retest.
  6. Review.
- **Lab E:**
  - A topology view with link LEDs.
  - A client command prompt in which `ipconfig`, `ping` and `tracert` are the diagnostic actions, each revealing one fact.
  - The fix is made in the adapter's IPv4 properties dialog, followed by a retest.
- **Rubric:** S1–S5, each ≤2.
- **Contract notes:** each command must map to the existing diagnostic action id. Keep the fields and checks.

### COC3 M1 — Prepare Server Setup Requirements (LO3.2, `css-sag-20261011-v2`)
- **Task:** prepare a file server for the Support team. Verify conditioned power, a live network drop, 16 GB of memory, 100 GB of free storage, and approved installation media.
- **Today:**
  1. Inspect the workspace (plus place and connect grid).
  2. Identify requirements (options).
  3. Decide the server role.
  4. Sequence the readiness checks.
  5. Validate readiness.
  6. Review.
- **Lab G (server-room readiness):**
  - The rack and server, a UPS showing its load and battery, a wall jack with link LED, the server's spec label (RAM and disk) and the installation media.
  - Inspect each to read the values, then decide the requirements and role, and run the checks in order.
- **Rubric:** S1–S5, each ≤2.
- **Contract notes:** keep `inspected.*`, the requirement and role option ids, and the readiness sequence `power → network → capacity → media`.

### COC3 M2 — Install and Configure Server OS (LO3.2, `css-sag-20261011-v2`)
- **Task:** install a file server named BQ-FS01 at 192.168.30.10. Save the configuration before installation and restart before verifying the service.
- **Today:**
  1. Roles and configuration (form plus place grid).
  2. Installation sequence.
  3. Restart (options).
  4. Verify services.
  5. Review.
- **Lab F:**
  - A server OS installer: hardware and media check, prepare the system volume, install, apply the saved role.
  - First-boot configuration: host name and static IP.
  - Restart animation and a service status page.
- **Rubric:** S1–S4, each ≤2.
- **Contract notes:** keep the field ids (server role, host name, management address), the sequence ids, the restart option id and the checks.

### COC3 M3 — Manage Users, Groups, and Permissions (LO3.1, `css-sag-20261011-v2`)
- **Task:** create the technician account for the Support team. The technician must be able to modify the shared maintenance folder, while Learners keep read-only access.
- **Today:**
  1. Configure accounts, groups and permissions (form plus place grid).
  2. Inspect and test access.
  3. Diagnose the permission problem (facts).
  4. Correct access.
  5. Retest.
  6. Review.
- **Lab F:**
  - A Users and Groups console: new user, add to group.
  - The folder's Properties → Security tab: Modify for Support, Read for Learners.
  - A client session that tries to save a file and shows "Access denied" or success.
  - Diagnose using group membership, effective permission and resource scope views.
- **Rubric:** S1–S5, each ≤2.
- **Contract notes:** keep the field ids (account, group, permission), the diagnostic ids and the user-folder operation.

### COC3 M4 — Configure and Test Server Services (LO3.2, `css-sag-20261011-v2`)
- **Task:** operate the file service on TCP port 445 with automatic startup. Start, stop and restart the service, and verify the response from a client.
- **Today:**
  1. Inspect the service (plus place grid).
  2. Configure the service (form).
  3. Start, stop and inspect status (dropdown).
  4. Client test.
  5. Interpret.
  6. Review.
- **Lab F:**
  - A Services console with a service list. The Properties dialog holds the name, port and startup type, with Start, Stop and Restart buttons that change the live status.
  - A client file-sharing and printer-sharing test window, then the interpretation.
- **Rubric:** S1–S5, each ≤2.
- **Contract notes:** keep the field ids (service name, port, startup mode, service control, status inspected), the operations and the checks.

### COC3 M5 — Test Client Access and Document Setup (LO3.3, `css-sag-20261011-v2`)
- **Task:** a client has lost access to a previously available server resource.
- **Today:** three troubleshooting phases (facts), a correction (options), a retest, and review.
- **Lab E:**
  - The client's error dialog.
  - The server console (listener state, permission summary, access scope).
  - A network probe from the client.
  - Correct the cause, then retest by writing a file.
- **Rubric:** S1–S5, each ≤2.
- **Contract notes:** keep the diagnostic and correction ids and the checks.

### COC4 M1 — Identify System and Network Problems (LO4.1, `css-sag-20261009-v1`)
- **Task:** triage a workstation that powers on and shows the desktop but cannot reach the file server. Record observations before prioritizing a diagnostic path.
- **Today:**
  1. Inspect (list, plus backup/contingency).
  2. Observation (text).
  3. Prioritize (options).
  4. Preliminary diagnosis (options).
  5. Verify.
  6. Review.
- **Lab E (service-desk triage):**
  - A desk PC with a tray network icon showing no access, the adapter LEDs and an Event Viewer.
  - Record the backup and contingency plan first, write the observation, then choose a priority and preliminary diagnosis, and verify.
- **Rubric:** S1–S5, each ≤2.
- **Contract notes:** keep the inspect ids, the observation record, the option ids, the operations and the checks.

### COC4 M2 — Diagnose and Repair Hardware Faults (LO4.3, `css-sag-20261009-v1`)
- **Task:** a workstation intermittently stops during sustained operation.
- **Today:**
  1. Inspect the symptom and component (facts plus contingency).
  2. Select a tool and run the test (memory probe, storage health, power measurement).
  3. Interpret.
  4. Identify the fault (options).
  5. Repair and verify.
  6. Review.
- **Lab E:**
  - The open case on the bench.
  - A multimeter on the PSU connector pins showing voltages.
  - A memory diagnostic screen and a storage health (SMART) panel; each tool reveals one fact.
  - The interpretation, then the repair performed physically (replace or reseat the faulty part), and a load test.
- **Rubric:** S1–S5, each ≤2.
- **Contract notes:** each tool use must map to the existing diagnostic action ids. Keep the fault and repair option ids.

### COC4 M3 — Diagnose Hardware and Software Faults (LO4.3, `css-sag-20261009-v1`)
- **Task:** a workstation has application and network symptoms with no confirmed root cause.
- **Today:**
  1. Inspect the symptoms.
  2. Software diagnostic (application log, adapter status, local service).
  3. Interpret.
  4. Network diagnostic (route trace).
  5. Interpret.
  6. Review.
- **Lab E/F:**
  - Event Viewer (application log), Device Manager (adapter), the Services list and a `tracert` console.
  - The learner opens each tool, which reveals one fact, then records the interpretations.
- **Rubric:** S1–S5, each ≤2.
- **Contract notes:** keep the diagnostic ids, the two interpretation records and the route-trace test.

### COC4 M4 — Replace and Reconfigure a Component (LO4.4, `css-sag-20261009-v1`)
- **Task:** replace a failed Ethernet adapter with a compatible PCIe adapter. Isolate power, use ESD protection, fit and fasten the card, install its driver, and test automatic addressing.
- **Today:**
  1. Select the component and tool (reorder list plus tool choice plus contingency).
  2. Replace (select-and-confirm with an "aligned / rotated" dialog).
  3. Reconfigure (form).
  4. Sequence the repair (reorder list).
  5. Post-repair test.
  6. Review.
- **Lab B (on the bench engine):**
  - The open case with PCIe slots and the failed NIC installed.
  - Isolate power and clip on the wrist strap.
  - Unscrew the bracket with the ESD screwdriver and lift the failed card out.
  - Align the new card with the slot key (a physical rotation replaces the dialog), seat and latch it, and fasten the screw.
  - Then Device Manager (driver) and adapter properties (automatic addressing), and the test.
- **Rubric:** S1 ≤2, **S1_SAFETY power isolated and ESD-safe tool before removal (0)**, S2–S5, each ≤2.
- **Contract notes:**
  - The physical alignment must emit the existing orientation values (`aligned` / `rotated`).
  - The removal and fastening order must produce the same sequence evidence (`isolate → remove → inspect`, `seat → fasten → configure → restore`), with tool `esd_driver` on the retaining screw.

### COC4 M5 — Apply Repair Action and Create Report (LO4.5, `css-sag-20261009-v1`)
- **Task:** complete a prioritized maintenance request covering five service requests and prepare its service report.
- **Today:**
  1. Inspect the requests (five diagnose buttons plus contingency).
  2. Prioritize the issue and tool (options).
  3. Maintain and repair (operations).
  4. Test and interpret.
  5. Final verify (observation).
  6. Review.
- **Lab G/E (service-desk lab):**
  - A ticket board with five requests: printer, USB, audio, monitor "No Signal", slow after update.
  - The right tool for each: device management console, known-good port tester, signal cable tester.
  - The repair actions: isolate the damaged USB port, install the printer and audio drivers, de-energize and secure the monitor cable, and so on.
  - The tests: test page, USB enumeration, audio output, display signal. Then the service report form.
- **Rubric:** S1 ≤2, S2 ≤2, **S2_SAFETY damaged USB port isolated before software maintenance (0)**, S3–S5, each ≤2.
- **Contract notes:** keep the diagnostic, tool, operation, option and check ids, and the observation record.

## 6. Shared building blocks

1. **Lab scene engine.** Generalize the COC1 M2 bench into data-driven scenes:
   - a photographic workspace with named mount points, ports and slots taken from mission data;
   - an inventory drawer (bottom in portrait, right in landscape);
   - drag or tap placement with rotation and snap, red "invalid" states, removal, and cable endpoints.
   - Needed by COC1 M1/M4/M5, COC2 M1/M2/M3, COC3 M1 and COC4 M2/M4.
2. **Software-lab shell.** Desktop and window frames, a setup-wizard pager, property dialogs with tabs, a services list, a users and groups tree, a command prompt with scripted outputs, and router admin pages.
   - Each control writes the existing configuration, operation or diagnostic evidence.
   - Needed by COC1 M3, COC2 M4/M5, COC3 M2/M3/M4/M5 and COC4 M1/M3/M5.
3. **Instrument kit.**
   - LAN tester with wire-map LEDs.
   - Multimeter.
   - POST/boot screen (exists).
   - Event Viewer.
   - Storage health panel.
4. **Contract-equivalence tests.** For each redesigned mission, a test performs the correct and some incorrect actions through the new lab and checks that the produced evidence matches what the current UI produces for the same actions. That protects scoring and the published packages.

## 7. Recommended order

The full redesign is roughly 15–20 working days including testing; the re-defense is Monday 2026-11-23. Recommended:

1. **Before the defense (about 2 days):**
   - one showcase lab per COC that does not have one yet;
   - COC4 M4 (on the bench engine);
   - COC2 M2 (crimping lab);
   - one software lab (COC3 M4 Services console);
   - COC1 M4 (rear I/O panel), time permitting.
   - COC1 M2 is already the COC1 showcase.
2. **After the defense:** the shared engines first, then the remaining missions COC by COC, each with contract-equivalence tests and an emulator pass.

## 8. Decisions needed from the owner

1. Which missions to build before the defense (the recommendation is in §7).
2. Whether any mission may change its steps or criteria. That means a new contract version, republishing in production and a new APK. The default is no: presentation-only.
3. APK: a release build cannot be made with the original key, which is not on this PC. Debug builds are used for testing unless the owner again approves a fresh-install key.

## 9. Implemented before the defense (2026-11-21/22): COC4 M4 and COC2 M2 labs

The owner chose **COC4 M4 PCIe NIC swap** and **COC2 M2 RJ45 crimping lab**. Both are UI-layer labs.
Mission definitions, practice contracts, assessment contracts, rubrics, scoring and the database are
unchanged; no migration, no new scoring rule.

### What the learner does

| Phase | Before (standard panels) | After (lab) | Evidence recorded (unchanged contract) |
|---|---|---|---|
| COC2 M2 p2 | Reorder list of 8 colour names with up/down arrows | RJ45 front view: drag a conductor into a pin channel (or tap conductor, then channel), tap a filled channel to take it out, **Insert and crimp**; re-terminate after a bad crimp. Practice shows a T568B reference card; assessment does not. | One confirmed `sequence_reordered` (pins 1–8), only at the crimp |
| COC4 M4 p1 | Reorder list + tool tray + operation button | Service bench on a motherboard photo: unplug the power cord, wear the wrist strap, pick a tool and tap the bracket screw, lift the failed adapter, inspect the slot, verify the backup | `tool_attempted` on `retaining_screw`, `equipment_operation` `protect_service_data`, one confirmed `sequence_reordered` with the steps **in the order performed** |
| COC4 M4 p2 | Tap-only placement panel | Turn the replacement adapter around if needed, drag it onto the PCIe slot (or tap adapter, then slot) | `placement_attempted` with the adapter's orientation |
| COC4 M4 p4 | Reorder list | Latch the adapter, fasten the screw with the screwdriver, configure, refit the panel and restore power | One confirmed `sequence_reordered` in the order performed |

Unsafe or wrong work is recorded as performed, never corrected by the lab. Practice shows the
existing technical feedback (for example "The keyed connector is not aligned…", "This tool cannot
engage the selected interface…") and offers a restart; assessment shows a neutral "Procedure
recorded." and always offers a restart, so the screen never reveals correctness.

### Assessment integrity

- The bench lists its step controls in the phase's listed (scrambled) order, the same order the
  standard reorder list starts from, so reading it top to bottom never spells out the safe order.
- A resumed assessment shows every recorded step as performed, whatever its order.
- Guidance (top hint, "Show me where", the How-to panel) names the lab's controls only, never the
  expected order, tool, wiring or orientation. The T568B card and its guidance exist in practice only.

### Files

- `ByteQuest-Mobile-App/lib/screens/simulation/components/labs/` (`mission_labs.dart`,
  `cable_termination_lab.dart`, `pcie_replacement_lab.dart`).
- `ByteQuest-Mobile-App/lib/data/mission_lab_phases.dart`: the lab-owned phases and their guidance.
- `mission_simulation_screen.dart` (the lab replaces the scene and panel controls for its phases),
  `mission_phase_guidance.dart` (lab guidance), `mission_content_data.dart` (all lab strings).
- Tests: `test/mission_labs_test.dart` (26 tests, some generated per phase and mode), `test/support/mission_lab_driver.dart`; the
  screen, assessment, layout and guidance suites drive the lab phases through the labs.

### Verification

- Flutter suite (Docker, Flutter 3.44.0): **764 passed, 1 skipped (pre-existing), 0 failed**.
  `flutter analyze`: 0 errors, 0 warnings (210 infos, all pre-existing).
- `assessment_mode_test`: a correct run through the labs records the same counted evidence as the
  exported happy path, except that the bench records the contingency operation once (the exporter
  taps every operation twice to prove idempotence).
- Server scoring (local stack, rollback only): `supabase/tests/simulation_assessment_all_missions_rollback.sql`
  passes 24/24 both as committed and with the COC4 M4 fixture reduced to one contingency row; every
  criterion is satisfied and every run is competent.
- Android emulator (`padala_pixel7`, 411 dp, debug APK against the local stack, local QA learner):
  - COC4 M4 practice run from phase 1 to submission by touch, with a wrong tool, an unsafe order
    and a reversed-adapter drag on the way. The server stored all 18 evidence rows (3 invalid) and
    verified the run.
  - COC2 M2 phase 2 by real drag and taps: a miswired crimp was recorded as invalid with the T568B
    message; the re-terminated T568B crimp was valid. The state survived a rotation to landscape.
- Screenshots: `docs/qa-labs-2026-11-21/` (`before-*` = HEAD `a32ef60` standard panels, `after-*` =
  labs, same harness at 411 dp; `device-*` = emulator).

### Limitations

- Assessment mode was verified by widget tests and the server replay suite, not on the device: the
  local QA learner has no class or published assessment.
- Phones narrower than about 410 dp show the RJ45 plug on its side (one 48 dp row per channel). Tap
  insertion works everywhere; a drag to the top channels may need a scroll first.
- The remaining 18 missions keep their standard panels (§7, after the defense).
