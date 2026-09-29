part of '../mission_simulation_definitions.dart';

// Practice equipment constraints are not official rubric or scoring rules.
// The dedicated assessment contracts and PostgreSQL evaluators are unchanged.
const _equipmentTitles = {
  'coc1_m3': 'Install and Configure a Workstation OS',
  'coc1_m4': 'Connect and Configure Peripheral Devices',
  'coc2_m3': 'Construct and Verify a Network Topology',
  'coc2_m4': 'Configure Network Devices',
  'coc2_m5': 'Troubleshoot Network Connectivity',
  'coc3_m3': 'Manage Users, Groups, and Permissions',
  'coc3_m4': 'Configure and Test Server Services',
  'coc4_m2': 'Diagnose and Repair Hardware Faults',
  'coc4_m4': 'Replace and Reconfigure a Component',
};

const _equipmentScenarios = {
  'coc1_m1':
      'Inspect a de-energized desktop before servicing. The memory latch is open. Identify component roles, isolate abnormalities, and record a safe work plan.',
  'coc1_m3':
      'Install a workstation OS on a blank GPT drive using UEFI installation media. Configure storage mode, install the network driver, restart, and verify boot and device readiness.',
  'coc1_m4':
      'Connect a 1920 × 1080 HDMI monitor, USB keyboard and mouse, and Ethernet adapter. Configure native resolution and automatic network addressing before testing.',
  'coc2_m3':
      'Build a switched star: both workstations and the router connect to the switch; the switch connects to the server. A damaged cable segment must be isolated and repaired.',
  'coc2_m4':
      'Configure the managed switch at 192.168.10.2 with mask 255.255.255.0 and gateway 192.168.10.1. A client at 192.168.10.24 must reach the management service.',
  'coc3_m1':
      'Prepare a file server for the Support team. Verify conditioned power, a live network drop, 16 GB memory, 100 GB free storage, and approved installation media.',
  'coc3_m2':
      'Install a file server named BQ-FS01 at 192.168.30.10. Save configuration before installation and restart before verifying the service.',
  'coc3_m3':
      'Create the technician account for the Support team. The technician must modify the shared maintenance folder; Learners must retain read-only access.',
  'coc3_m4':
      'Operate the file service on TCP port 445 with automatic startup. Start, stop, and restart the service and verify the response from a client.',
  'coc4_m1':
      'Triage a workstation that powers on and displays the desktop but cannot reach the file server. Record observations before prioritizing a diagnostic path.',
  'coc4_m4':
      'Replace a failed Ethernet adapter with a compatible PCIe adapter. Isolate power, use ESD protection, fit and fasten the card, install its driver, and test automatic addressing.',
};

Map<String, dynamic> _eq(String path, Object? value) =>
    {'path': path, 'value': value};
Map<String, dynamic> _present(String path) =>
    {'path': path, 'operator': 'present'};
Map<String, dynamic> _reading(String id, String label,
        List<Map<String, dynamic>> requires, String nominal, String fault) =>
    {
      'id': id,
      'label': label,
      'requires': requires,
      'nominal': nominal,
      'fault': fault
    };
Map<String, dynamic> _operation(
        String id, String label, Map<String, dynamic> effects,
        {List<Map<String, dynamic>> requires = const []}) =>
    {'id': id, 'label': label, 'effects': effects, 'requires': requires};
Map<String, dynamic> _choice(
        String id, String label, Map<String, dynamic> effects) =>
    {'id': id, 'label': label, 'equipment_effects': effects};
Map<String, dynamic> _field(String id, String label, {String? format}) =>
    {'id': id, 'label': label, if (format != null) 'format': format};
Map<String, dynamic> _dropdown(
        String id, String label, Map<String, String> options) =>
    {
      'id': id,
      'label': label,
      'type': 'dropdown',
      'options': [
        for (final option in options.entries)
          {'id': option.key, 'label': option.value}
      ],
    };

List<Map<String, dynamic>> _networkFields() => [
      _field('interface_address', 'Interface IPv4 address', format: 'ipv4'),
      _field('subnet_mask', 'Subnet mask', format: 'ipv4'),
      _field('default_gateway', 'Default gateway', format: 'ipv4'),
    ];

_PhaseSpec _equipmentPhase(String missionId, int number, _PhaseSpec original,
    Map<String, String> objects) {
  final id = '${missionId}_p$number';
  var title = original.title;
  var instruction = original.instruction;
  var family = original.family;
  final p = Map<String, dynamic>.from(original.presentation);
  final equipment = <String, dynamic>{'single_connection': true};
  var resolved = MissionPhasePresentation.familyForComponent(
          p['component'] as String? ?? '') ??
      family;

  void component(String name, InteractionFamily kind) {
    p['component'] = name;
    family = kind;
    resolved = kind;
  }

  void sequence(Map<String, String> steps) {
    component('sequencing', InteractionFamily.sequence);
    final entries = steps.entries.toList();
    p['items'] = [
      for (final entry in entries.reversed)
        {'id': entry.key, 'label': entry.value}
    ];
    equipment['precedence'] = [
      for (var i = 1; i < entries.length; i++)
        {'before': entries[i - 1].key, 'after': entries[i].key}
    ];
  }

  void test(List<Map<String, dynamic>> checks, {bool finalCheck = false}) {
    equipment['checks'] = checks;
    p['target'] ??= '${missionId}_test_$number';
    if (finalCheck) {
      equipment['completion'] = [_eq('result.${p['target']}', true)];
    }
  }

  void configuration(List<Map<String, dynamic>> fields) {
    component('configuration', InteractionFamily.configure);
    p['fields'] = fields;
  }

  void decisions(List<Map<String, dynamic>> choices) {
    component('scenario_decision', InteractionFamily.decide);
    p['choices'] = choices;
  }

  switch (missionId) {
    case 'coc1_m1':
      if (number == 2) {
        p['options'] = [
          {'id': 'esd_protection', 'label': 'Wrist strap — ESD protection'},
          {
            'id': 'open_memory_latch',
            'label': 'Memory latch requires attention'
          },
          {'id': 'service_live', 'label': 'Service while energized'},
        ];
        equipment['selection_groups'] = [
          for (final group in {
            'processing': 'Classify: processing',
            'memory': 'Classify: volatile memory',
            'power': 'Classify: power conversion'
          }.entries)
            {
              'id': group.key,
              'label': group.value,
              'options': [
                {'id': 'cpu', 'label': 'Processor'},
                {'id': 'ram', 'label': 'Memory module'},
                {'id': 'psu', 'label': 'Power supply'},
              ]
            },
        ];
        equipment['tools'] = [
          {
            'id': 'anti_static_strap',
            'label': 'Anti-static wrist strap',
            'compatible_categories': ['esd_ground']
          },
          {
            'id': 'screwdriver',
            'label': 'Phillips screwdriver',
            'compatible_categories': ['fastener']
          },
        ];
        equipment['targets'] = [
          {
            'id': 'chassis_ground',
            'label': 'Bare chassis ground point',
            'category': 'esd_ground'
          },
          {
            'id': 'case_fastener',
            'label': 'Case fastener',
            'category': 'fastener'
          },
        ];
        equipment['completion'] = [
          _present('selection.$id'),
          for (final group in ['processing', 'memory', 'power'])
            _present('classification.$group'),
          _eq('tool.chassis_ground', 'anti_static_strap'),
          _eq('tool.case_fastener', 'screwdriver')
        ];
        p.remove('choices');
      }
      if (number == 4) {
        test([
          _reading(
              'inspection',
              'Inspection record',
              [
                for (final part in [
                  'motherboard',
                  'cpu',
                  'ram',
                  'psu',
                  'cpu_socket',
                  'dimm_slot',
                  'atx_power_port'
                ])
                  _eq('inspected.$part', true)
              ],
              'Components, sockets, slots, and the ATX power header were inspected.',
              'A component, socket, slot, or power-header inspection remains incomplete.'),
          _reading(
              'classification',
              'Component roles',
              [
                for (final group in {
                  'processing': 'cpu',
                  'memory': 'ram',
                  'power': 'psu'
                }.entries)
                  {
                    'path': 'classification.${group.key}',
                    'operator': 'set_equals',
                    'value': [group.value]
                  },
              ],
              'Processing, volatile memory, and power-conversion components classified.',
              'At least one component role conflicts with the inspected specification.'),
          _reading(
              'safe_work',
              'Safe work plan',
              [
                {
                  'path': 'selection.coc1_m1_p2',
                  'operator': 'set_equals',
                  'value': ['esd_protection', 'open_memory_latch']
                }
              ],
              'ESD controls and the unseated memory latch are recorded.',
              'The work plan omits an observed hazard or permits energized servicing.'),
          _reading(
              'notes',
              'Observation record',
              [_present('observation.coc1_m1_p3')],
              'Inspection notes attached.',
              'No inspection notes recorded.'),
        ], finalCheck: true);
      }
      break;
    case 'coc1_m2':
      if (number == 2) {
        p['items'] = [
          for (final raw in p['items'] as List)
            {
              ...Map<String, dynamic>.from(raw as Map),
              'orientations': ['aligned', 'rotated'],
              'seating_orientation': 'aligned',
              'requires_placements': switch (raw['id']) {
                'cpu' || 'ram' => ['motherboard'],
                'cooling_fan' => ['cpu'],
                _ => <String>[],
              }
            }
        ];
        const categories = {
          'motherboard_area': 'board',
          'cpu_socket': 'socketed',
          'ram_slot': 'slotted',
          'drive_bay': 'drive',
          'fan_area': 'cooling',
          'psu_bay': 'power'
        };
        p['destinations'] = [
          for (final raw in p['destinations'] as List)
            {
              ...Map<String, dynamic>.from(raw as Map),
              'socket_categories': [categories[raw['id']]]
            }
        ];
      }
      if (number == 3) {
        sequence({
          'isolate': 'Isolate power and prepare ESD controls',
          'board': 'Fit board and processor',
          'cooling': 'Secure cooling and memory',
          'power': 'Connect power and storage data'
        });
        equipment['connection'] = _internalCablePanel;
        equipment['completion'] = [
          for (final pair in _internalCablePairs) _eq('link.$pair', true)
        ];
      }
      if (number == 4) {
        test([
          _reading(
              'assembly',
              'POST component inventory',
              [for (final part in objects.keys) _present('placed.$part')],
              'CPU, memory, storage, cooling, and power assemblies seated.',
              'An installed component is missing from the inventory.'),
          _reading(
              'power_data',
              'Power and storage path',
              [for (final pair in _internalCablePairs) _eq('link.$pair', true)],
              'Power rails and storage data path available.',
              'Power or storage connection is incomplete.'),
          _reading(
              'sequence',
              'Assembly safety record',
              [_eq('sequence.coc1_m2_p3', true)],
              'Isolation, assembly, cooling, and wiring chronology recorded.',
              'Assembly chronology violates a safety prerequisite.'),
        ], finalCheck: true);
      }
      break;
    case 'coc1_m3':
      if (number == 1) {
        title = 'Inspect and configure setup';
        instruction =
            'The boot console reports a blank GPT disk and UEFI media. Configure firmware and select the installation target.';
        configuration([
          _dropdown('boot_mode', 'Firmware boot mode',
              {'uefi': 'UEFI', 'legacy': 'Legacy BIOS'}),
          _dropdown('storage_mode', 'Storage controller mode',
              {'ahci': 'AHCI', 'disabled': 'Disabled'}),
          _dropdown('install_target', 'Installation target', {
            'system_disk': 'Internal GPT system disk',
            'usb_media': 'Installation USB media'
          }),
        ]);
      }
      if (number == 2) {
        title = 'Install the operating system';
        instruction =
            'Sequence the installation operations before applying them.';
        sequence({
          'boot_media': 'Boot installation media',
          'select_disk': 'Select the internal target disk',
          'copy_files': 'Copy operating-system files',
          'configure_device': 'Configure device drivers'
        });
        p.remove('action_type');
        equipment['operations'] = [
          _operation('install_os', 'Run installation', {
            'os_installed': true
          }, requires: [
            _eq('config.boot_mode', 'uefi'),
            _eq('config.storage_mode', 'ahci'),
            _eq('config.install_target', 'system_disk'),
            _eq('sequence.$id', true),
          ])
        ];
        equipment['completion'] = [_eq('operation.install_os', true)];
      }
      if (number == 3) {
        title = 'Configure drivers and restart';
        instruction =
            'Select the adapter driver, apply configuration, and restart the installed system.';
        configuration([
          _dropdown('network_driver', 'Network adapter driver', {
            'ethernet': 'Ethernet driver for this adapter',
            'wireless': 'Wireless adapter driver'
          })
        ]);
        equipment['operations'] = [
          _operation(
              'restart_workstation', 'Restart workstation', {'restarted': true},
              requires: [_eq('setting.os_installed', true)])
        ];
        equipment['completion'] = [_eq('operation.restart_workstation', true)];
      }
      if (number == 4) {
        title = 'Verify and interpret startup';
        instruction =
            'Run startup verification and interpret the boot and device statuses. Return to setup if a failure is reported.';
        component('test_with_interpretation', InteractionFamily.testRun);
        p['requires_interpretation'] = true;
        test([
          _reading(
              'boot',
              'Boot status',
              [
                _eq('setting.os_installed', true),
                _eq('setting.restarted', true),
                _eq('config.boot_mode', 'uefi'),
                _eq('config.storage_mode', 'ahci')
              ],
              'OS loader started from the GPT system disk.',
              'No usable installed system or firmware/storage configuration is incompatible.'),
          _reading(
              'adapter',
              'Network adapter',
              [_eq('config.network_driver', 'ethernet')],
              'Ethernet adapter initialized.',
              'No matching driver can initialize the Ethernet adapter.'),
        ], finalCheck: true);
      }
      break;
    case 'coc1_m4':
      if (number == 3) {
        p['sources'] = [
          for (final entry in {
            'monitor': 'HDMI monitor',
            'keyboard': 'USB keyboard',
            'mouse': 'USB mouse',
            'network_adapter': 'Ethernet adapter'
          }.entries)
            {
              'id': entry.key,
              'label': entry.value,
              'interfaces': [
                entry.key == 'monitor'
                    ? 'hdmi'
                    : entry.key == 'network_adapter'
                        ? 'ethernet'
                        : 'usb'
              ]
            }
        ];
        p['destinations'] = [
          for (final entry in {
            'hdmi_port': 'hdmi',
            'usb_port': 'usb',
            'ethernet_port': 'ethernet'
          }.entries)
            {
              'id': entry.key,
              'label': entry.key.replaceAll('_', ' '),
              'interface': entry.value
            }
        ];
        equipment['configuration'] = {
          'fields': [
            _dropdown('display_resolution', 'Display resolution',
                {'1920x1080': '1920 × 1080', '800x600': '800 × 600'}),
            _dropdown('address_mode', 'Network address mode', {
              'automatic': 'Automatic (DHCP)',
              'disabled': 'Adapter disabled'
            }),
          ]
        };
        equipment['completion'] = [
          _present('config.display_resolution'),
          _present('config.address_mode')
        ];
      }
      if (number == 4) {
        test([
          _reading(
              'display',
              'Display signal',
              [
                _eq('link.monitor>hdmi_port', true),
                _eq('config.display_resolution', '1920x1080')
              ],
              '1920 × 1080 native signal detected.',
              'Native display signal unavailable; inspect input and resolution.'),
          _reading(
              'input',
              'USB input devices',
              [
                _eq('link.keyboard>usb_port', true),
                _eq('link.mouse>usb_port', true)
              ],
              'Keyboard and pointer respond.',
              'A USB input device is not connected.'),
          _reading(
              'network',
              'Network adapter',
              [
                _eq('link.network_adapter>ethernet_port', true),
                _eq('config.address_mode', 'automatic')
              ],
              'Link up; DHCP lease acquired.',
              'No active link or address lease.'),
        ], finalCheck: true);
      }
      break;
    case 'coc1_m5':
      if (number == 2) {
        equipment['tools'] = [
          {
            'id': 'firmware_inventory',
            'label': 'Firmware storage console',
            'compatible_categories': ['storage']
          },
          {
            'id': 'display_calibrator',
            'label': 'Display calibrator',
            'compatible_categories': ['display']
          },
        ];
        equipment['targets'] = [
          {
            'id': 'storage',
            'label': 'Storage controller',
            'category': 'storage'
          },
        ];
        p['diagnostic_actions'] = [
          for (final raw in p['diagnostic_actions'] as List)
            {
              ...Map<String, dynamic>.from(raw as Map),
              'requires': [_eq('tool.storage', 'firmware_inventory')]
            },
        ];
        equipment['completion'] = [_eq('tool.storage', 'firmware_inventory')];
      }
      if (number == 4) {
        decisions([
          _choice(
              'replace_storage_cable',
              'Isolate power and replace the unstable SATA data cable',
              {'storage_link_stable': true}),
          _choice('install_display_driver', 'Reinstall the display driver',
              {'storage_link_stable': false}),
          _choice('format_storage', 'Format the storage volume',
              {'storage_link_stable': false}),
        ]);
      }
      if (number == 5) {
        test([
          _reading(
              'storage',
              'Storage read probe',
              [_eq('setting.storage_link_stable', true)],
              'Volume readable; 0 link resets during the probe.',
              'Read timed out; storage-link reset remains present.')
        ], finalCheck: true);
      }
      break;
    case 'coc2_m1':
      if (number == 3) {
        sequence({
          'measure': 'Measure and cut cable',
          'strip': 'Strip the outer jacket',
          'arrange': 'Arrange and trim conductors',
          'terminate': 'Insert and crimp connectors',
          'inspect': 'Inspect both terminations'
        });
      }
      if (number == 5) {
        test([
          _reading(
              'wiremap',
              'Wire-map tester',
              [
                _eq('sequence.coc2_m1_p3', true),
                _eq('link.copper_cable>lan_cable_tester', true)
              ],
              'Pins 1–8 show continuity; no open conductors.',
              'Tester has no complete prepared link; continuity cannot be established.'),
        ], finalCheck: true);
      }
      break;
    case 'coc2_m2':
      // This only enriches practice; the validated cable assessment is separate.
      if (number == 2) {
        p['items'] = p['conductors'];
        const wireOrder = [
          'white_orange',
          'orange',
          'white_green',
          'blue',
          'white_blue',
          'green',
          'white_brown',
          'brown'
        ];
        equipment['precedence'] = [
          for (var i = 1; i < wireOrder.length; i++)
            {'before': wireOrder[i - 1], 'after': wireOrder[i]}
        ];
      }
      if (number == 5) {
        p['component'] = 'test_with_interpretation';
        p['requires_interpretation'] = true;
        test([
          _reading(
              'wiremap',
              'Cable wire map',
              [_eq('sequence.coc2_m2_p2', true)],
              'All eight conductors form the requested T568B termination.',
              'Wire-map order does not form the requested termination.'),
          _reading(
              'topology',
              'Topology path',
              [
                _eq('link.workstation>switch', true),
                _eq('link.switch>router', true)
              ],
              'Workstation → switch → router link path present.',
              'Topology path is incomplete or bypasses the requested switch.'),
          _reading(
              'interface',
              'Interface negotiation',
              [
                _eq('config.workstation_interface', 'ethernet_auto'),
                _eq('config.physical_link_inspected', true)
              ],
              'Ethernet link negotiated; physical inspection recorded.',
              'Interface negotiation or physical inspection is incomplete.'),
        ], finalCheck: true);
      }
      break;
    case 'coc2_m3':
      if (number == 4) {
        decisions([
          _choice('isolate_invalid_link', 'Isolate and re-seat both endpoints',
              {'link_segment_repaired': false}),
          _choice(
              'replace_link_segment',
              'Replace the cable with the measured open conductor',
              {'link_segment_repaired': true}),
        ]);
      }
      if (number == 3 || number == 5) {
        test([
          _reading(
              'links',
              'Star topology',
              [
                for (final pair in [
                  'router>switch',
                  'workstation_a>switch',
                  'workstation_b>switch',
                  'switch>server'
                ])
                  _eq('link.$pair', true)
              ],
              'All requested star links are present.',
              'A requested star link is missing or attached to the wrong node.'),
          _reading(
              'segment',
              'Cable segment continuity',
              [_eq('setting.link_segment_repaired', true)],
              'All pairs continuous.',
              'Open conductor persists in the workstation cable segment.'),
        ], finalCheck: number == 5);
      }
      break;
    case 'coc2_m4':
      if (number == 2) configuration(_networkFields());
      if (number == 5) {
        component('test_with_interpretation', InteractionFamily.testRun);
        p['requires_interpretation'] = true;
        equipment['configuration'] = {'fields': _networkFields()};
      }
      if (number == 3 || number == 5) {
        test(_networkChecks('192.168.10.2'), finalCheck: number == 5);
      }
      break;
    case 'coc2_m5':
      if (number == 4) configuration(_networkFields());
      if (number == 2 || number == 5) {
        test(_networkChecks('192.168.10.24'), finalCheck: number == 5);
      }
      break;
    case 'coc3_m1':
      if (number == 4) {
        sequence({
          'power': 'Verify conditioned power',
          'network': 'Verify the network drop',
          'capacity': 'Confirm memory and storage capacity',
          'media': 'Validate installation media'
        });
        title = 'Sequence preparation';
      }
      if (number == 5) {
        component('test_run', InteractionFamily.testRun);
        title = 'Validate setup readiness';
        test([
          _reading(
              'role',
              'Requested service role',
              [_eq('decision.coc3_m1_p3', 'file_service')],
              'File-service role matches the Support work request.',
              'Selected service role does not provide the requested shared storage.'),
          _reading(
              'preparation',
              'Preparation checks',
              [
                _eq('sequence.coc3_m1_p4', true),
                for (final object in objects.keys)
                  _eq('inspected.$object', true)
              ],
              'Power, network, capacity, and media checks recorded.',
              'A workspace inspection or preparation prerequisite is incomplete.'),
        ], finalCheck: true);
      }
      break;
    case 'coc3_m2':
      if (number == 1) {
        p['fields'] = [
          for (final raw in p['fields'] as List)
            {
              ...Map<String, dynamic>.from(raw as Map),
              if (raw['id'] == 'management_address') 'format': 'ipv4'
            }
        ];
      }
      if (number == 2) {
        sequence({
          'validate': 'Validate hardware and media',
          'partition': 'Prepare the system volume',
          'install': 'Install the server operating system',
          'role': 'Apply the saved service role'
        });
      }
      if (number == 3) {
        decisions([
          _choice(
              'restart_after_configuration',
              'Save and restart the configured server',
              {'server_restarted': true}),
          _choice('defer_restart', 'Leave the restart pending',
              {'server_restarted': false}),
        ]);
      }
      if (number == 4) {
        test([
          _reading(
              'role',
              'File service',
              [
                _eq('config.server_role', 'file_service'),
                _eq('sequence.coc3_m2_p2', true),
                _eq('setting.server_restarted', true)
              ],
              'File service initialized after installation and restart.',
              'File service unavailable; inspect role, installation chronology, and restart status.'),
          _reading(
              'identity',
              'Management endpoint',
              [
                _eq('config.host_name', 'BQ-FS01'),
                _eq('config.management_address', '192.168.30.10')
              ],
              'BQ-FS01 reachable at 192.168.30.10.',
              'Management endpoint does not match the deployment request.'),
        ], finalCheck: true);
      }
      break;
    case 'coc3_m3':
      if (number == 3) {
        equipment['fact_readings'] = {
          'group_membership_fact': _reading(
              'membership',
              'Membership',
              [_eq('config.group_assignment', 'support')],
              'Current account token includes Support.',
              'Current account token does not include Support.'),
          'effective_permission_fact': _reading(
              'permission',
              'Permission',
              [
                _eq('config.resource_permission', 'modify'),
                _eq('config.group_assignment', 'support')
              ],
              'Effective access permits Modify on the shared folder.',
              'Effective access does not permit Modify on the shared folder.'),
        };
      }
      if (number == 4) {
        configuration([
          _field('account_name', 'Account name'),
          _dropdown('group_assignment', 'Group membership',
              {'learners': 'Learners', 'support': 'Support'}),
          _dropdown('resource_permission', 'Shared-folder permission',
              {'read': 'Read', 'modify': 'Modify'}),
        ]);
      }
      if (number == 2 || number == 5) {
        test([
          _reading(
              'identity',
              'Account lookup',
              [_eq('config.account_name', 'technician')],
              'technician account found.',
              'Requested technician account not found.'),
          _reading(
              'access',
              'Effective Modify access',
              [
                _eq('config.group_assignment', 'support'),
                _eq('config.resource_permission', 'modify')
              ],
              'Modify allowed for Support; Learners remain read-only.',
              'Modify denied by membership or resource scope.'),
        ], finalCheck: number == 5);
      }
      break;
    case 'coc3_m4':
      if (number == 2) {
        p['fields'] = [
          for (final raw in p['fields'] as List)
            {
              ...Map<String, dynamic>.from(raw as Map),
              if (raw['id'] == 'listen_port') 'format': 'port'
            }
        ];
      }
      if (number == 4) {
        test([
          _reading(
              'listener',
              'TCP client request',
              [
                _eq('config.service_name', 'file'),
                _eq('config.listen_port', '445'),
                _eq('setting.service_running', true)
              ],
              'TCP 445 connected; file-service response received.',
              'Connection refused; inspect service name, listener port, and running state.'),
          _reading(
              'startup',
              'Startup policy',
              [_eq('config.startup_mode', 'automatic')],
              'Service will start automatically.',
              'Service will not start automatically after reboot.'),
        ], finalCheck: true);
      }
      break;
    case 'coc3_m5':
      if (number == 4) {
        decisions([
          _choice(
              'restore_support_membership',
              'Restore the authorized technician to the Support group',
              {'authorized_access': true}),
          _choice('restart_service', 'Restart the running file service',
              {'authorized_access': false}),
          _choice('grant_everyone', 'Grant Modify to all users',
              {'authorized_access': false}),
        ]);
      }
      if (number == 5) {
        test([
          _reading(
              'authorization',
              'Client write request',
              [_eq('setting.authorized_access', true)],
              'Authorized technician can modify; Learners remain read-only.',
              'Requested least-privilege access is not restored.')
        ], finalCheck: true);
      }
      break;
    case 'coc4_m1':
      if (number == 5) {
        test([
          _reading(
              'priority',
              'Diagnostic priority',
              [_eq('decision.coc4_m1_p3', 'prioritize_network_path')],
              'Network-path checks address the reported loss of service.',
              'Power and display are operational; selected priority does not isolate the reported fault.'),
          _reading(
              'hypothesis',
              'Preliminary fault domain',
              [_eq('decision.coc4_m1_p4', 'preliminary_network_path')],
              'Network-path hypothesis retained pending link and address testing.',
              'Hardware hypothesis is not supported by the visible observations.'),
        ], finalCheck: true);
      }
      break;
    case 'coc4_m2':
      if (number == 4) {
        decisions([
          _choice(
              'replace_storage',
              'Back up readable data and replace the degraded storage drive',
              {'storage_replaced': true}),
          _choice('replace_memory', 'Replace memory modules',
              {'storage_replaced': false}),
          _choice('replace_supply', 'Replace the power supply',
              {'storage_replaced': false}),
        ]);
      }
      if (number == 5) {
        test([
          _reading(
              'health',
              'Storage health and load test',
              [_eq('setting.storage_replaced', true)],
              'Replacement drive: 0 pending sectors; sustained read completes.',
              '18 pending sectors remain; storage retries reproduce the stop.')
        ], finalCheck: true);
      }
      break;
    case 'coc4_m3':
      if (number == 2) {
        p['diagnostic_actions'] = [
          ...(p['diagnostic_actions'] as List),
          {
            'id': 'inspect_adapter_status',
            'label': 'Inspect adapter status',
            'reveals_fact_id': 'adapter_status_fact'
          },
          {
            'id': 'inspect_service_status',
            'label': 'Inspect local service status',
            'reveals_fact_id': 'local_service_fact'
          },
        ];
        p['facts'] = {
          ...Map<String, dynamic>.from(p['facts'] as Map),
          'adapter_status_fact':
              'The Ethernet adapter reports link up at 1 Gbps; no local link error is recorded.',
          'local_service_fact':
              'The local application service is running and listening on its configured port.',
        };
      }
      if (number == 4) {
        p['component'] = 'test_with_interpretation';
        p['requires_interpretation'] = true;
        p['test_reveals_fact_id'] = 'route_trace_fact';
        test([
          _reading(
              'route',
              'Route trace',
              [_eq('fact.application_log_fact', true)],
              'Gateway 192.168.1.1 replies; hop 2 times out. Inspect upstream routing before changing the application.',
              'No application request evidence yet; correlate the request before tracing its route.')
        ]);
      }
      break;
    case 'coc4_m4':
      if (number == 1) {
        component('sequencing', InteractionFamily.sequence);
        sequence({
          'isolate': 'Disconnect power and prepare ESD protection',
          'remove': 'Remove and isolate the failed Ethernet adapter',
          'inspect': 'Inspect PCIe socket and replacement keying'
        });
        equipment['tools'] = [
          {
            'id': 'esd_driver',
            'label': 'ESD-safe screwdriver',
            'compatible_categories': ['retaining_screw']
          },
          {
            'id': 'wire_cutter',
            'label': 'Wire cutter',
            'compatible_categories': ['wire']
          },
        ];
        equipment['targets'] = [
          {
            'id': 'retaining_screw',
            'label': 'Adapter retaining screw',
            'category': 'retaining_screw'
          }
        ];
        equipment['completion'] = [_eq('tool.retaining_screw', 'esd_driver')];
      }
      if (number == 2) {
        p['items'] = [
          {
            'id': 'replacement_component',
            'label': 'PCIe Ethernet adapter',
            'category': 'pcie',
            'orientations': ['aligned', 'rotated'],
            'seating_orientation': 'aligned'
          }
        ];
        p['destinations'] = [
          {
            'id': 'workstation',
            'label': 'PCIe slot',
            'socket_categories': ['pcie']
          }
        ];
      }
      if (number == 3) {
        configuration([
          _dropdown('device_mode', 'Address mode',
              {'automatic': 'Automatic addressing', 'disabled': 'Disabled'}),
          _field('device_identifier', 'Adapter identifier'),
          _dropdown('driver_state', 'Driver state',
              {'installed': 'Installed', 'pending_restart': 'Pending restart'}),
        ]);
      }
      if (number == 4) {
        sequence({
          'seat': 'Seat and latch the replacement adapter',
          'fasten': 'Fasten the retaining screw',
          'configure': 'Install driver and configure addressing',
          'restore': 'Close the enclosure and restore power'
        });
      }
      if (number == 5) {
        test([
          _reading(
              'hardware',
              'Adapter enumeration',
              [
                _eq('placed.replacement_component', 'workstation'),
                _eq('tool.retaining_screw', 'esd_driver'),
                _eq('sequence.coc4_m4_p1', true),
                _eq('sequence.coc4_m4_p4', true)
              ],
              'PCIe adapter enumerated; retention and close-out recorded.',
              'Adapter installation or safe repair chronology is incomplete.'),
          _reading(
              'driver',
              'Adapter functional test',
              [
                _eq('config.driver_state', 'installed'),
                _eq('config.device_mode', 'automatic'),
                _present('config.device_identifier')
              ],
              'Driver loaded; link and DHCP lease available.',
              'Adapter not operational; inspect driver and address mode.'),
        ], finalCheck: true);
      }
      break;
    case 'coc4_m5':
      if (number == 2) {
        decisions([
          _choice(
              'service_verified_faults',
              'Isolate the damaged USB port before software changes',
              {'maintenance_priority': 'isolate_usb'}),
          _choice(
              'replace_unverified_hardware',
              'Replace the printer before checking the USB fault',
              {'maintenance_priority': 'replace_printer'}),
          _choice(
              'close_requests_without_test',
              'Start system updates before isolating the damaged port',
              {'maintenance_priority': 'updates_first'}),
        ]);
        equipment['tools'] = [
          {
            'id': 'device_manager',
            'label': 'Device management console',
            'compatible_categories': ['driver']
          },
          {
            'id': 'port_tester',
            'label': 'Known-good port tester',
            'compatible_categories': ['port']
          },
          {
            'id': 'cable_tester',
            'label': 'Signal cable tester',
            'compatible_categories': ['cable']
          },
        ];
        equipment['targets'] = [
          {
            'id': 'driver_inventory',
            'label': 'Driver inventory',
            'category': 'driver'
          },
          {'id': 'usb_interface', 'label': 'USB interface', 'category': 'port'},
          {'id': 'video_link', 'label': 'Video cable', 'category': 'cable'},
        ];
        equipment['completion'] = [
          _eq('tool.driver_inventory', 'device_manager'),
          _eq('tool.usb_interface', 'port_tester'),
          _eq('tool.video_link', 'cable_tester')
        ];
      }
      if (number == 3) {
        decisions([
          _choice('open_service_console', 'Open the maintenance work order',
              {'work_order_open': true})
        ]);
        equipment['operations'] = [
          _operation(
              'usb_port',
              'Isolate the damaged USB port and move the device to a tested port',
              {
                'usb_ready': true
              },
              requires: [
                _eq('fact.usb_port_finding', true),
                _eq('setting.maintenance_priority', 'isolate_usb')
              ]),
          _operation('printer_driver', 'Install the matching printer driver', {
            'printer_ready': true
          }, requires: [
            _eq('fact.printer_driver_finding', true),
            _eq('setting.usb_ready', true)
          ]),
          _operation('audio_driver', 'Install the matching audio driver', {
            'audio_ready': true
          }, requires: [
            _eq('fact.audio_driver_finding', true),
            _eq('setting.usb_ready', true)
          ]),
          _operation('video_cable', 'De-energize and secure the monitor cable',
              {'video_ready': true},
              requires: [_eq('fact.video_cable_finding', true)]),
          _operation('windows_update',
              'Schedule updates for the approved maintenance window', {
            'updates_ready': true
          }, requires: [
            _eq('fact.windows_update_finding', true),
            _eq('setting.usb_ready', true)
          ]),
        ];
        equipment['completion'] = [
          for (final item in [
            'printer_driver',
            'usb_port',
            'audio_driver',
            'video_cable',
            'windows_update'
          ])
            _eq('operation.$item', true)
        ];
      }
      if (number == 4) {
        test([
          _reading(
              'priority',
              'Safety priority',
              [_eq('setting.maintenance_priority', 'isolate_usb')],
              'The damaged port was isolated before software maintenance.',
              'The work order does not prioritize the exposed physical fault.'),
          for (final entry in {
            'printer': 'Print test page',
            'usb': 'USB enumeration',
            'audio': 'Audio output',
            'video': 'Display signal',
            'updates': 'Foreground responsiveness'
          }.entries)
            _reading(
                entry.key,
                entry.value,
                [_eq('setting.${entry.key}_ready', true)],
                'Service responds after the recorded corrective action.',
                'Service request remains unresolved.'),
        ], finalCheck: true);
      }
      break;
  }

  if (resolved == InteractionFamily.inspect && p['objects'] is List) {
    p['objects'] = [
      for (final raw in p['objects'] as List)
        {
          ...Map<String, dynamic>.from(raw as Map),
          'inspection': _inspectionContent(
              missionId, raw['id'] as String, raw['label'] as String)
        }
    ];
  }
  if (resolved == InteractionFamily.sequence && p['items'] == null) {
    sequence({for (final entry in objects.entries) entry.key: entry.value});
  }
  p['equipment'] = equipment;
  return _PhaseSpec(
      title: title,
      instruction: instruction,
      family: family,
      mechanic: original.mechanic,
      presentation: p);
}

List<Map<String, dynamic>> _networkChecks(String address) => [
      _reading(
          'address',
          'IPv4 interface',
          [
            _eq('config.interface_address', address),
            _eq('config.subnet_mask', '255.255.255.0')
          ],
          '$address/24 is active on the requested interface.',
          'Interface address or mask does not match the assigned segment.'),
      _reading(
          'gateway',
          'Gateway probe',
          [_eq('config.default_gateway', '192.168.10.1')],
          '192.168.10.1 replies; remote service path available.',
          'Gateway is outside the intended segment or is not configured.'),
    ];

const _internalCablePairs = ['atx>board_power', 'sata>storage_data'];
const _internalCablePanel = {
  'sources': [
    {
      'id': 'atx',
      'label': '24-pin ATX power',
      'interfaces': ['atx']
    },
    {
      'id': 'sata',
      'label': 'SATA data cable',
      'interfaces': ['sata']
    },
  ],
  'destinations': [
    {
      'id': 'board_power',
      'label': 'Motherboard power header',
      'interface': 'atx'
    },
    {'id': 'storage_data', 'label': 'Storage data port', 'interface': 'sata'},
  ],
};

String _inspectionContent(String missionId, String objectId, String label) {
  const details = {
    'motherboard':
        'ATX board. CPU socket, keyed DIMM slots, and 24-pin power header are visible. No swollen capacitors are visible.',
    'cpu':
        'Processor contacts are intact. The alignment mark must match the socket mark; do not force the package.',
    'ram':
        'DDR memory module. The notch is offset; one retaining latch is open. Isolate power before reseating.',
    'psu':
        'Power supply converts mains to regulated DC rails. Disconnect mains before touching internal connectors.',
    'anti_static_strap':
        'ESD wrist strap provides a controlled discharge path to the workbench grounding point.',
    'cpu_socket':
        'The keyed CPU socket is empty and its alignment marker is visible. No contacts appear bent.',
    'dimm_slot':
        'The DIMM slot key and retaining latches are visible; one latch remains open.',
    'atx_power_port':
        'The 24-pin ATX header is keyed and clear of debris. It must remain de-energized during inspection.',
    'storage':
        'Storage drive has separate keyed SATA data and power connectors.',
    'cooling_fan':
        'Cooling assembly must be seated on the processor and connected to its fan header.',
    'monitor':
        'Monitor accepts HDMI and has a native 1920 × 1080 panel. No signal appears until the input path is connected.',
    'keyboard':
        'USB keyboard: inspect the keyed plug and the host port before connection.',
    'mouse':
        'USB pointing device: the optical sensor and USB connector are unobstructed.',
    'network_adapter':
        'Ethernet adapter has an RJ45 port with separate link and activity indicators.',
    'server_chassis':
        'Server inventory reports 16 GB memory and 100 GB available system storage.',
    'network_drop':
        'The network drop reports link up at 1 Gbps to the managed switch.',
    'power_conditioner':
        'Conditioned output is stable; the load indicator is below rated capacity.',
    'installation_media':
        'Approved installation media is readable and its checksum matches the deployment record.',
    'setup_document':
        'The Support team requires a file service with controlled write access.',
    'service_console':
        'File service is installed but stopped. The client requests TCP port 445.',
    'status_monitor':
        'Service status changes only after an applied start, stop, or restart command.',
    'application_log':
        'Application requests time out. Open the diagnostic log to collect a timestamped record.',
    'route_monitor':
        'No route measurement has been made. Trace the request path before proposing a routing change.',
    'event_console':
        'Desktop startup completed. The client reports that the file-server path is unavailable.',
    'display': 'The desktop is visible and the power indicator is steady.',
  };
  return details[objectId] ??
      '$label is available in the $missionId workspace. Inspect its status using the phase controls before changing its configuration.';
}
