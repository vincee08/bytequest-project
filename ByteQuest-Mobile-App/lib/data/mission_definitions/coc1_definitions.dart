part of '../mission_simulation_definitions.dart';

final List<MissionSimulationDefinition> _coc1Definitions = [
  _mission(
    id: 'coc1_m1',
    title: 'Identify Computer Parts and Tools',
    scenario: 'Prepare a desktop workstation for safe servicing.',
    environmentLabel: 'Hardware inspection bench',
    practiceGuidance:
        'Inspect labels and visible conditions before recording any decision.',
    objects: const {
      'motherboard': 'Motherboard',
      'cpu': 'Processor',
      'ram': 'Memory module',
      'psu': 'Power supply',
      'cpu_socket': 'CPU socket',
      'dimm_slot': 'DIMM slot',
      'atx_power_port': '24-pin ATX power header',
      'anti_static_strap': 'Anti-static wrist strap',
    },
    phases: [
      _phase(
        'Inspect hardware',
        'Inspect each component and its visible condition.',
        InteractionFamily.inspect,
        'inspect_hardware',
        presentation: const {
          'component': 'tap_inspect',
          'objects': [
            {'id': 'motherboard', 'label': 'Motherboard'},
            {'id': 'cpu', 'label': 'Processor'},
            {'id': 'ram', 'label': 'Memory module'},
            {'id': 'psu', 'label': 'Power supply'},
            {'id': 'cpu_socket', 'label': 'CPU socket'},
            {'id': 'dimm_slot', 'label': 'DIMM slot'},
            {'id': 'atx_power_port', 'label': '24-pin ATX power header'},
          ],
        },
      ),
      _phase(
        'Select a safe set',
        'Record the components and safety equipment needed for the work.',
        InteractionFamily.decide,
        'select_safe_set',
        presentation: const {
          'component': 'multi_select',
          'choices': [
            {
              'id': 'inspect_components',
              'label': 'Inspect selected components'
            },
            {'id': 'prepare_esd', 'label': 'Prepare ESD protection'},
          ],
        },
      ),
      _phase(
        'Record observations',
        'Describe the inspected condition without inferring an unobserved fault.',
        InteractionFamily.inspect,
        'record_observation',
        presentation: const {'component': 'observation'},
      ),
      _phase(
        'Verify readiness',
        'Run the readiness check against the recorded inspection.',
        InteractionFamily.testRun,
        'verify_readiness',
        presentation: const {'evidenceActionType': 'hardware_readiness_test'},
      ),
      _phase(
        'Review evidence',
        'Review the safe-set decision and readiness evidence.',
        InteractionFamily.review,
        'review_evidence',
      ),
    ],
  ),
  _mission(
    id: 'coc1_m2',
    title: 'Install Internal Components',
    scenario: 'Assemble a compatible workstation from inspected parts.',
    environmentLabel: 'Component assembly bench',
    practiceGuidance:
        'Check compatibility and orientation before each controlled placement.',
    objects: const {
      'motherboard': 'Motherboard',
      'cpu': 'Processor',
      'ram': 'Memory module',
      'storage': 'Storage drive',
      'cooling_fan': 'Cooling assembly',
      'psu': 'Power supply',
    },
    phases: [
      _phase(
        'Inspect compatibility',
        'Inspect socket, slot, clearance, and power compatibility.',
        InteractionFamily.place,
        'inspect_compatibility',
        presentation: const {'component': 'tap_inspect'},
      ),
      _phase(
        'Place components',
        'Select a component, destination, and orientation before placement.',
        InteractionFamily.place,
        'place_with_orientation',
        presentation: const {
          'component': 'controlled_placement',
          'action_type': 'component_drop_attempted',
          'accessibleControl': 'select_then_confirm',
          'items': [
            {'id': 'motherboard', 'label': 'Motherboard', 'category': 'board'},
            {'id': 'cpu', 'label': 'Processor', 'category': 'socketed'},
            {'id': 'ram', 'label': 'Memory module', 'category': 'slotted'},
            {'id': 'storage', 'label': 'Storage drive', 'category': 'drive'},
            {
              'id': 'cooling_fan',
              'label': 'Cooling assembly',
              'category': 'cooling'
            },
            {'id': 'psu', 'label': 'Power supply', 'category': 'power'},
          ],
          'destinations': [
            {'id': 'motherboard_area', 'label': 'Motherboard area'},
            {'id': 'cpu_socket', 'label': 'CPU socket'},
            {'id': 'ram_slot', 'label': 'RAM slot'},
            {'id': 'drive_bay', 'label': 'Drive bay'},
            {'id': 'fan_area', 'label': 'Cooling area'},
            {'id': 'psu_bay', 'label': 'Power-supply bay'},
          ],
          'orientations': ['aligned', 'rotated'],
        },
      ),
      _phase(
        'Sequence assembly',
        'Record the installation chronology before final inspection.',
        InteractionFamily.decide,
        'sequence_assembly',
        presentation: const {'component': 'sequencing'},
      ),
      _phase(
        'Verify installation',
        'Run seating, fastening, and clearance checks.',
        InteractionFamily.testRun,
        'verify_installation',
        presentation: const {
          'evidenceActionType': 'installation_test_requested'
        },
      ),
      _phase(
        'Review evidence',
        'Review compatibility, placement, sequence, and inspection records.',
        InteractionFamily.review,
        'review_evidence',
      ),
    ],
  ),
  _mission(
    id: 'coc1_m3',
    title: 'Install and Configure a Workstation OS',
    scenario: 'Install an operating system on the blank GPT workstation.',
    environmentLabel: 'Workstation installation bench',
    practiceGuidance:
        'Inspect firmware and storage requirements, then verify the driver after restarting.',
    objects: const {
      'firmware_console': 'UEFI setup console',
      'system_disk': 'GPT system disk',
      'installation_media': 'OS installation media',
      'driver_media': 'Device driver media',
      'boot_monitor': 'Startup status monitor',
    },
    phases: [
      _phase(
        'Inspect and configure setup',
        'Inspect the blank GPT disk and apply the required firmware, storage, and installation-target settings.',
        InteractionFamily.configure,
        'configure_installation',
        presentation: const {'component': 'configuration'},
      ),
      _phase(
        'Install the operating system',
        'Perform the operating-system installation operations in their required order.',
        InteractionFamily.sequence,
        'install_operating_system',
        presentation: const {'component': 'sequencing'},
      ),
      _phase(
        'Configure drivers and restart',
        'Select the matching network driver, apply it, and restart the workstation.',
        InteractionFamily.configure,
        'configure_driver_restart',
        presentation: const {'component': 'configuration'},
      ),
      _phase(
        'Verify and interpret startup',
        'Run startup and adapter verification, then interpret the measured outputs.',
        InteractionFamily.testRun,
        'verify_and_interpret',
        presentation: const {'component': 'test_with_interpretation'},
      ),
      _phase(
        'Review evidence',
        'Review setup, installation, driver, restart, test, and interpretation records.',
        InteractionFamily.review,
        'review_evidence',
      ),
    ],
  ),
  _mission(
    id: 'coc1_m4',
    title: 'Connect and Configure Peripheral Devices',
    scenario: 'Prepare workstation peripherals for functional testing.',
    environmentLabel: 'Peripheral connection station',
    practiceGuidance:
        'Inspect interfaces and select tools before creating a connection.',
    objects: const {
      'system_unit': 'System unit',
      'monitor': 'Monitor',
      'keyboard': 'Keyboard',
      'mouse': 'Mouse',
      'network_adapter': 'Network adapter',
    },
    phases: [
      _phase(
          'Inspect peripherals',
          'Inspect each device interface and cable condition.',
          InteractionFamily.connect,
          'inspect_peripherals',
          presentation: const {'component': 'tap_inspect'}),
      _phase(
          'Choose a tool',
          'Choose the tool appropriate to the inspected interface.',
          InteractionFamily.decide,
          'choose_tool',
          presentation: const {
            'component': 'tool_selection',
            'targets': [
              {
                'id': 'monitor',
                'label': 'Monitor video interface',
                'category': 'video_interface',
              },
              {
                'id': 'network_adapter',
                'label': 'Network adapter port',
                'category': 'network_interface',
              },
            ],
            'tools': [
              {
                'id': 'interface_inspection_light',
                'label': 'Inspection light',
                'category': 'inspection',
                'compatible_categories': [
                  'video_interface',
                  'network_interface',
                ],
              },
              {
                'id': 'lan_loopback_adapter',
                'label': 'LAN loopback adapter',
                'category': 'network_test',
                'compatible_categories': ['network_interface'],
              },
            ],
          }),
      _phase(
        'Connect devices',
        'Select a device and then confirm its destination interface.',
        InteractionFamily.connect,
        'connect_devices',
        presentation: const {
          'component': 'connection',
          'accessibleControl': 'select_then_confirm',
          'sources': [
            {'id': 'monitor', 'label': 'Monitor'},
            {'id': 'keyboard', 'label': 'Keyboard'},
            {'id': 'mouse', 'label': 'Mouse'},
            {'id': 'network_adapter', 'label': 'Network adapter'},
          ],
          'destinations': [
            {'id': 'system_unit', 'label': 'System-unit interfaces'},
          ],
        },
      ),
      _phase(
        'Run and interpret device test',
        'Run the peripheral device test, then record an interpretation of the displayed status.',
        InteractionFamily.testRun,
        'run_device_test_and_interpret',
        presentation: const {
          'component': 'test_with_interpretation',
          'target': 'peripheral_device_test',
          'requires_interpretation': true,
        },
      ),
      _phase(
          'Review evidence',
          'Review inspection, connection, and device-test records.',
          InteractionFamily.review,
          'review_evidence'),
    ],
  ),
  _mission(
    id: 'coc1_m5',
    title: 'Install Drivers and Test the System',
    scenario: 'A newly assembled workstation reports an integration fault.',
    environmentLabel: 'Workstation diagnostic bay',
    practiceGuidance:
        'Reveal facts progressively and apply a correction only after recording diagnostics.',
    objects: const {
      'workstation': 'Workstation',
      'display': 'Display subsystem',
      'storage': 'Storage subsystem',
      'network': 'Network subsystem',
    },
    phases: [
      _phase(
          'Inspect symptom',
          'Inspect the reported symptom and visible system state.',
          InteractionFamily.troubleshoot,
          'inspect_symptom',
          presentation: _progressiveDiagnostics(
            symptom:
                'The workstation starts, but the storage subsystem remains unavailable.',
            actions: const [
              (
                'inspect_startup_indicators',
                'Inspect startup indicators',
                'startup_indicator_fact',
                'The power indicator remains steady while the storage activity LED stays amber after three startup flashes.'
              ),
            ],
          )),
      _phase(
          'Choose diagnostic tool',
          'Choose a diagnostic action that can reveal a new fact.',
          InteractionFamily.troubleshoot,
          'choose_diagnostic_tool',
          presentation: _progressiveDiagnostics(
            symptom:
                'Select a diagnostic action that can distinguish device detection from operating-system access.',
            actions: const [
              (
                'open_storage_inventory',
                'Open storage inventory',
                'storage_inventory_fact',
                'The firmware storage inventory lists one device on SATA port 1, and the port status is up.'
              ),
            ],
          )),
      _phase(
        'Troubleshoot progressively',
        'Record diagnostic facts before unlocking the corrective action.',
        InteractionFamily.troubleshoot,
        'troubleshoot_progressively',
        presentation: _progressiveDiagnostics(
          symptom:
              'The workstation starts, but one subsystem remains unavailable.',
          actions: const [
            (
              'inspect_device_status',
              'Inspect device status',
              'device_status_fact',
              'Firmware inventory lists the storage device, while the operating system reports it unavailable.'
            ),
            (
              'run_subsystem_probe',
              'Run subsystem probe',
              'subsystem_probe_fact',
              'The storage probe returns a 1.8-second timeout with no readable volume.'
            ),
            (
              'inspect_connection_log',
              'Inspect connection log',
              'connection_log_fact',
              'The connection log records three storage-link resets during startup.'
            ),
          ],
        ),
      ),
      _phase(
        'Apply correction',
        'Apply the correction supported by the recorded facts.',
        InteractionFamily.decide,
        'apply_correction',
        presentation: const {
          'choices': [
            {
              'id': 'apply_integration_correction',
              'label': 'Apply the documented integration correction',
            },
          ],
        },
      ),
      _phase(
        'Verify integration',
        'Run the full integration verification.',
        InteractionFamily.testRun,
        'verify_integration',
        presentation: const {
          'evidenceActionType': 'retest_requested',
          'target': 'retest_integration',
        },
      ),
      _phase(
          'Review evidence',
          'Review symptoms, diagnostics, correction, and verification.',
          InteractionFamily.review,
          'review_evidence'),
    ],
  ),
];
