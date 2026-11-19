part of '../mission_simulation_definitions.dart';

// COC1 M2 realistic assembly bench (practice contract css-assembly-20261119-v3).
//
// Physically impossible actions (a part in a socket of another type, a keyed
// part in the wrong orientation, a CPU under a closed load plate, an I/O
// shield behind an installed motherboard) are refused. Physically possible
// mistakes (memory in the wrong DIMM pair, an open lever or latch, missing
// screws, compound or cables) are accepted and surface as realistic symptoms
// at the power-on self-test, where the fix panels let the learner correct the
// assembly and test again. Practice equipment rules only; the simulation
// assessment rubric is generated from this contract by the server.

const _quarterTurns = ['0', '90', '180', '270'];
const _postTarget = 'coc1_m2_post';

Map<String, dynamic> _absent(String path) => {
      'path': path,
      'operator': 'one_of',
      'value': [null],
    };
Map<String, dynamic> _absentOr(String path, String value) => {
      'path': path,
      'operator': 'one_of',
      'value': [null, value],
    };

Map<String, dynamic> _benchStep(String id, String label,
        List<Map<String, dynamic>> done, Map<String, String> focus) =>
    {'id': id, 'label': label, 'done': done, 'focus': focus};

final _cpuItem = {
  'id': 'cpu',
  'label': 'Processor',
  'category': 'lga_cpu',
  'orientations': _quarterTurns,
  'seating_orientation': '0',
  'initial_orientation': '90',
  'requires': [_eq('setting.cpu_lever', 'open')],
};
final _coolerItem = {
  'id': 'cooler',
  'label': 'CPU cooler',
  'category': 'cpu_cooler',
  'requires': [_present('placed.cpu')],
};
Map<String, dynamic> _memoryItem(int number) => {
      'id': 'ram_$number',
      'label': 'Memory module $number',
      'category': 'ddr4_dimm',
      'orientations': _quarterTurns,
      'seating_orientation': '0',
      'initial_orientation': '180',
      'requires': [_eq('setting.dimm_latches', 'open')],
    };
final _boardDestinations = [
  {
    'id': 'cpu_socket',
    'label': 'CPU socket (LGA)',
    'socket_categories': ['lga_cpu'],
  },
  {
    'id': 'cooler_mount',
    'label': 'Cooler mounting holes',
    'socket_categories': ['cpu_cooler'],
  },
  for (final slot in ['a1', 'a2', 'b1', 'b2'])
    {
      'id': 'dimm_$slot',
      'label': 'DIMM_${slot.toUpperCase()}',
      'socket_categories': ['ddr4_dimm'],
    },
];

final _fanCable = {
  'id': 'cooler_fan',
  'label': 'Cooler fan cable',
  'interfaces': ['fan_4pin'],
  'required': false,
};
final _fanHeaders = [
  {'id': 'cpu_fan_header', 'label': 'CPU_FAN header', 'interface': 'fan_4pin'},
  {'id': 'sys_fan_header', 'label': 'SYS_FAN header', 'interface': 'fan_4pin'},
];
final _powerDataCables = [
  {
    'id': 'atx_24pin',
    'label': '24-pin ATX power cable',
    'interfaces': ['atx24'],
  },
  {
    'id': 'eps_8pin',
    'label': '8-pin EPS CPU power cable',
    'interfaces': ['eps8'],
    'required': false,
  },
  {
    'id': 'sata_power',
    'label': 'SATA power cable',
    'interfaces': ['sata_power'],
    'required': false,
  },
  {
    'id': 'sata_data',
    'label': 'SATA data cable',
    'interfaces': ['sata_data'],
    'required': false,
  },
  {
    'id': 'front_panel',
    'label': 'Front-panel connector',
    'interfaces': ['front_panel'],
    'required': false,
  },
];
final _powerDataHeaders = [
  {'id': 'board_atx24', 'label': '24-pin ATX header', 'interface': 'atx24'},
  {'id': 'board_eps8', 'label': '8-pin CPU power header', 'interface': 'eps8'},
  {
    'id': 'drive_power',
    'label': 'Drive SATA power port',
    'interface': 'sata_power',
  },
  {
    'id': 'drive_data',
    'label': 'Drive SATA data port',
    'interface': 'sata_data',
  },
  {
    'id': 'board_front_panel',
    'label': 'Front-panel header (F_PANEL)',
    'interface': 'front_panel',
  },
];

List<Map<String, dynamic>> _motherboardOperations() => [
      _operation('open_cpu_lever', 'Open the CPU socket lever',
          {'cpu_lever': 'open'},
          requires: [_absentOr('setting.cpu_lever', 'closed')]),
      _operation('close_cpu_lever', 'Close the CPU socket lever',
          {'cpu_lever': 'closed'},
          requires: [_eq('setting.cpu_lever', 'open')]),
      _operation('apply_thermal_compound', 'Apply thermal compound to the CPU',
          {'thermal_compound': true},
          requires: [_present('placed.cpu'), _absent('placed.cooler')]),
      _operation('open_dimm_latches', 'Open the DIMM latches',
          {'dimm_latches': 'open'},
          requires: [_absentOr('setting.dimm_latches', 'closed')]),
      _operation('close_dimm_latches', 'Lock the DIMM latches',
          {'dimm_latches': 'closed'},
          requires: [_eq('setting.dimm_latches', 'open')]),
    ];

List<Map<String, dynamic>> _caseOperations() => [
      _operation('pick_screwdriver', 'Pick up the Phillips screwdriver',
          {'hand_tool': 'screwdriver'}),
      _operation('fasten_psu', 'Fasten the power-supply screws',
          {'psu_fastened': true},
          requires: [
            _present('placed.psu'),
            _eq('setting.hand_tool', 'screwdriver')
          ]),
      _operation('fasten_motherboard', 'Fasten the motherboard screws',
          {'board_fastened': true},
          requires: [
            _present('placed.motherboard'),
            _eq('setting.hand_tool', 'screwdriver')
          ]),
      _operation('fasten_drive', 'Fasten the drive screws',
          {'drive_fastened': true},
          requires: [
            _present('placed.storage'),
            _eq('setting.hand_tool', 'screwdriver')
          ]),
    ];

/// One POST check. [counts] is the assessment target (an item, operation or
/// cable key of the replay) that a failing check charges: every completed
/// POST with this check failing adds one incorrect attempt to the step that
/// owns the target, so a mistake fixed after a failed POST still counts.
Map<String, dynamic> _postCheck(
        String id,
        String label,
        List<Map<String, dynamic>> requires,
        String counts,
        String nominal,
        String fault) =>
    {..._reading(id, label, requires, nominal, fault), 'counts': counts};

List<Map<String, dynamic>> _postChecks() => [
      _postCheck(
          'psu_mounting',
          'Power-supply mounting',
          [_eq('setting.psu_fastened', true)],
          'operation:fasten_psu',
          'Power supply fastened in its bay.',
          'Pre-power inspection: the power supply moves in its bay. Its screws are not fastened.'),
      _postCheck(
          'board_mounting',
          'Motherboard mounting',
          [_eq('setting.board_fastened', true)],
          'operation:fasten_motherboard',
          'Motherboard fastened on its standoffs.',
          'Pre-power inspection: the motherboard moves on its standoffs. Its screws are not fastened.'),
      _postCheck(
          'drive_mounting',
          'Drive mounting',
          [_eq('setting.drive_fastened', true)],
          'operation:fasten_drive',
          'Drive fastened in its bay.',
          'Pre-power inspection: the drive moves in its bay. Its screws are not fastened.'),
      _postCheck(
          'power_switch',
          'Power button',
          [_eq('link.front_panel>board_front_panel', true)],
          'connection:front_panel',
          'The case power button starts the system; the power LED lights.',
          'No power-on: pressing the case power button does nothing. The front-panel switch is not connected to F_PANEL.'),
      _postCheck(
          'cpu_power',
          'CPU power',
          [_eq('link.eps_8pin>board_eps8', true)],
          'connection:eps_8pin',
          '8-pin EPS CPU power present.',
          'No POST — CPU power not detected. Fans spin but the CPU debug LED stays lit.'),
      _postCheck(
          'cpu_detection',
          'Processor detection',
          [_eq('setting.cpu_lever', 'closed')],
          'operation:close_cpu_lever',
          'Processor detected.',
          'No POST — CPU debug LED lit. The processor is not held against the socket contacts.'),
      _postCheck(
          'cpu_fan',
          'CPU fan',
          [_eq('link.cooler_fan>cpu_fan_header', true)],
          'connection:cooler_fan',
          'CPU_FAN reports 1450 RPM.',
          'CPU fan error — the CPU_FAN header reports 0 RPM.'),
      _postCheck(
          'cpu_temperature',
          'CPU temperature',
          [_eq('setting.thermal_compound', true)],
          'operation:apply_thermal_compound',
          'CPU temperature stable at 38 °C.',
          'CPU over-temperature warning — 96 °C within 20 seconds of power-on.'),
      _postCheck(
          'memory_detection',
          'Memory detection',
          [_eq('setting.dimm_latches', 'closed')],
          'operation:close_dimm_latches',
          '16 GB DDR4 detected.',
          'Memory not detected — DRAM debug LED lit and the board repeats its memory beep code.'),
      _postCheck(
          'memory_channels',
          'Memory configuration',
          [
            {
              'path': 'placed.ram_1',
              'operator': 'one_of',
              'value': ['dimm_a2', 'dimm_b2'],
            },
            {
              'path': 'placed.ram_2',
              'operator': 'one_of',
              'value': ['dimm_a2', 'dimm_b2'],
            },
          ],
          'item:ram_1',
          'Dual-channel mode: modules in DIMM_A2 and DIMM_B2 as the board manual specifies.',
          'Memory running in single-channel mode — the modules are not in the DIMM_A2 and DIMM_B2 slots the board manual specifies for two modules.'),
      _postCheck(
          'drive_power',
          'Drive power',
          [_eq('link.sata_power>drive_power', true)],
          'connection:sata_power',
          'The drive spins up.',
          'No boot device found — the drive does not spin up. SATA power is not connected.'),
      _postCheck(
          'boot_device',
          'Boot device',
          [_eq('link.sata_data>drive_data', true)],
          'connection:sata_data',
          'SATA drive detected on port 0; ready to boot installation media.',
          'No boot device found — the drive spins but is not detected. The SATA data cable is not connected.'),
    ];

/// Fills one assembly-bench phase. [p] is the phase presentation and
/// [equipment] its equipment panel; both are mutated in place.
void _assemblyBenchPhase(int number, Map<String, dynamic> p,
    Map<String, dynamic> equipment, Map<String, String> objects) {
  switch (number) {
    case 1:
      equipment['operations'] = [
        _operation('wear_wrist_strap', 'Wear the anti-static wrist strap',
            {'wrist_strap_worn': true}),
        _operation('ground_wrist_strap', 'Clip the strap to the mat ground',
            {'esd_grounded': true},
            requires: [_eq('setting.wrist_strap_worn', true)]),
      ];
      equipment['completion'] = [
        for (final part in objects.keys) _eq('inspected.$part', true),
        _eq('operation.wear_wrist_strap', true),
        _eq('operation.ground_wrist_strap', true),
      ];
      p['bench_steps'] = [
        _benchStep(
            'inspect',
            'Inspect each part on the anti-static mat',
            [for (final part in objects.keys) _eq('inspected.$part', true)],
            {'kind': 'part', 'id': objects.keys.first}),
        _benchStep(
            'wear_strap',
            'Wear the anti-static wrist strap',
            [_eq('operation.wear_wrist_strap', true)],
            {'kind': 'operation', 'id': 'wear_wrist_strap'}),
        _benchStep(
            'ground_strap',
            'Clip the strap to the mat ground point',
            [_eq('operation.ground_wrist_strap', true)],
            {'kind': 'operation', 'id': 'ground_wrist_strap'}),
      ];
    case 2:
      p['items'] = [_cpuItem, _coolerItem, _memoryItem(1), _memoryItem(2)];
      p['destinations'] = _boardDestinations;
      equipment['operations'] = _motherboardOperations();
      equipment['connection'] = {
        'sources': [_fanCable],
        'destinations': _fanHeaders,
      };
      equipment['completion'] = [
        for (final part in ['cpu', 'cooler', 'ram_1', 'ram_2'])
          _present('placed.$part'),
      ];
      p['bench_steps'] = [
        _benchStep('open_lever', 'Open the CPU socket load lever',
            [_eq('operation.open_cpu_lever', true)],
            {'kind': 'operation', 'id': 'open_cpu_lever'}),
        _benchStep(
            'seat_cpu',
            'Seat the CPU — rotate it until its gold triangle matches the socket mark',
            [_present('placed.cpu')],
            {'kind': 'part', 'id': 'cpu'}),
        _benchStep('close_lever', 'Close the load lever under its retention tab',
            [_eq('setting.cpu_lever', 'closed')],
            {'kind': 'operation', 'id': 'close_cpu_lever'}),
        _benchStep('compound', 'Apply a pea-sized dot of thermal compound',
            [_eq('setting.thermal_compound', true)],
            {'kind': 'operation', 'id': 'apply_thermal_compound'}),
        _benchStep('mount_cooler', 'Mount the cooler over the CPU',
            [_present('placed.cooler')], {'kind': 'part', 'id': 'cooler'}),
        _benchStep('fan_cable', 'Connect the cooler fan cable to CPU_FAN',
            [_present('connected.cooler_fan')],
            {'kind': 'cable', 'id': 'cooler_fan'}),
        _benchStep('open_latches', 'Open the DIMM latches',
            [_eq('operation.open_dimm_latches', true)],
            {'kind': 'operation', 'id': 'open_dimm_latches'}),
        _benchStep(
            'seat_memory',
            'Seat both modules, notch aligned — the manual specifies DIMM_A2 and DIMM_B2 for two modules',
            [_present('placed.ram_1'), _present('placed.ram_2')],
            {'kind': 'part', 'id': 'ram_1'}),
        _benchStep('lock_latches', 'Press each module down until the latches lock',
            [_eq('setting.dimm_latches', 'closed')],
            {'kind': 'operation', 'id': 'close_dimm_latches'}),
      ];
    case 3:
      p['items'] = [
        {
          'id': 'psu',
          'label': 'Power supply',
          'category': 'atx_psu',
          'orientations': _quarterTurns,
          'seating_orientation': '0',
          'initial_orientation': '180',
          'removal_effects': {'psu_fastened': false},
        },
        {
          'id': 'io_shield',
          'label': 'I/O shield',
          'category': 'io_shield',
          'requires': [_absent('placed.motherboard')],
        },
        {
          'id': 'motherboard',
          'label': 'Motherboard assembly',
          'category': 'atx_board',
          'removal_effects': {'board_fastened': false},
        },
        {
          'id': 'storage',
          'label': 'Hard disk drive',
          'category': 'sata_drive',
          'removal_effects': {'drive_fastened': false},
        },
      ];
      p['destinations'] = [
        {
          'id': 'psu_bay',
          'label': 'Power-supply bay',
          'socket_categories': ['atx_psu'],
        },
        {
          'id': 'io_cutout',
          'label': 'Rear I/O cutout',
          'socket_categories': ['io_shield'],
        },
        {
          'id': 'board_standoffs',
          'label': 'Motherboard standoffs',
          'socket_categories': ['atx_board'],
        },
        {
          'id': 'drive_bay',
          'label': 'Drive bay',
          'socket_categories': ['sata_drive'],
        },
      ];
      equipment['operations'] = _caseOperations();
      equipment['completion'] = [
        for (final part in ['psu', 'io_shield', 'motherboard', 'storage'])
          _present('placed.$part'),
      ];
      p['bench_steps'] = [
        _benchStep(
            'seat_psu',
            'Seat the power supply in the bottom bay, fan facing the intake vent',
            [_present('placed.psu')],
            {'kind': 'part', 'id': 'psu'}),
        _benchStep('screwdriver', 'Pick up the Phillips screwdriver',
            [_eq('setting.hand_tool', 'screwdriver')],
            {'kind': 'operation', 'id': 'pick_screwdriver'}),
        _benchStep('fasten_psu', 'Fasten the power-supply screws',
            [_eq('setting.psu_fastened', true)],
            {'kind': 'operation', 'id': 'fasten_psu'}),
        _benchStep('io_shield', 'Snap the I/O shield into the rear cutout',
            [_present('placed.io_shield')],
            {'kind': 'part', 'id': 'io_shield'}),
        _benchStep('seat_board', 'Lower the motherboard onto the standoffs',
            [_present('placed.motherboard')],
            {'kind': 'part', 'id': 'motherboard'}),
        _benchStep('fasten_board', 'Fasten the motherboard screws',
            [_eq('setting.board_fastened', true)],
            {'kind': 'operation', 'id': 'fasten_motherboard'}),
        _benchStep('seat_drive', 'Slide the drive into the drive bay',
            [_present('placed.storage')], {'kind': 'part', 'id': 'storage'}),
        _benchStep('fasten_drive', 'Fasten the drive screws',
            [_eq('setting.drive_fastened', true)],
            {'kind': 'operation', 'id': 'fasten_drive'}),
      ];
    case 4:
      p['sources'] = _powerDataCables;
      p['destinations'] = _powerDataHeaders;
      equipment['completion'] = [_eq('link.atx_24pin>board_atx24', true)];
      p['bench_steps'] = [
        for (final cable in _powerDataCables)
          _benchStep(
              'connect_${cable['id']}',
              'Connect the ${(cable['label'] as String).replaceFirst(' cable', '')}',
              [_present('connected.${cable['id']}')],
              {'kind': 'cable', 'id': cable['id'] as String}),
      ];
    case 5:
      p['target'] = _postTarget;
      p['requires_interpretation'] = true;
      p['evidenceActionType'] = 'power_on_self_test';
      equipment['checks'] = _postChecks();
      equipment['completion'] = [_eq('result.$_postTarget', true)];
      equipment['placement'] = {
        'items': [_coolerItem, _memoryItem(1), _memoryItem(2)],
        'destinations': _boardDestinations
            .where((slot) => slot['id'] != 'cpu_socket')
            .toList(),
      };
      equipment['connection'] = {
        'sources': [_fanCable, ..._powerDataCables],
        'destinations': [..._fanHeaders, ..._powerDataHeaders],
      };
      equipment['operations'] = [
        ..._motherboardOperations(),
        ..._caseOperations(),
      ];
      p['bench_steps'] = [
        _benchStep('run_post', 'Power on and run the POST',
            [_present('tested.$_postTarget')],
            {'kind': 'controls', 'id': 'test-run-start'}),
        _benchStep(
            'clear_faults',
            'Correct each reported fault on the bench, then run the POST again',
            [_eq('result.$_postTarget', true)],
            {'kind': 'controls', 'id': 'test-run-start'}),
        _benchStep(
            'interpret',
            'Record your interpretation of the POST result',
            [_present('interpretation.coc1_m2_p5')],
            {'kind': 'controls', 'id': 'test-interpretation-coc1_m2_p5'}),
      ];
  }
}

const _assemblyImageAssets = {
  'system_case': 'assets/COC1/Mission 2/empty_system_unit_case.png',
  'motherboard': 'assets/COC1/Mission 2/motherboard.png',
  'cpu': 'assets/COC1/Mission 2/cpu.png',
  'cooler': 'assets/COC1/Mission 2/cooling_fan.png',
  'ram': 'assets/COC1/Mission 2/ram.png',
  'ram_1': 'assets/COC1/Mission 2/ram.png',
  'ram_2': 'assets/COC1/Mission 2/ram.png',
  'psu': 'assets/COC1/Mission 2/psu.png',
  'storage': 'assets/COC1/Mission 2/hdd.png',
  'atx_24pin': 'assets/COC1/Mission 3/24 Pin ATX.png',
  'eps_8pin': 'assets/COC1/Mission 3/CPU Power.png',
  'sata_power': 'assets/COC1/Mission 3/Sata Power.png',
  'sata_data': 'assets/COC1/Mission 3/Sata Cable.png',
  'front_panel': 'assets/COC1/Mission 3/Front Panel.png',
};

const _assemblyInspection = {
  'system_case':
      'ATX mid-tower, side panel removed. Motherboard standoffs, rear I/O cutout, bottom power-supply bay and a drive bay are visible.',
  'motherboard':
      'ATX board resting on the anti-static mat. LGA CPU socket with load lever, four DIMM slots (A1, A2, B1, B2), CPU_FAN and SYS_FAN headers, 24-pin ATX and 8-pin EPS power headers, SATA ports and the F_PANEL header.',
  'cpu':
      'LGA processor in its tray. A gold triangle marks pin 1; it must match the triangle printed on the socket. Never touch the contacts.',
  'cooler':
      'Tower cooler without pre-applied thermal compound. Its 4-pin fan cable must reach the CPU_FAN header.',
  'ram':
      'Two identical DDR4 modules. The off-centre notch only lines up with the slot key one way round.',
  'psu':
      'ATX power supply, switched off and unplugged. Modular 24-pin, 8-pin EPS and SATA power cables are attached.',
  'storage':
      '3.5-inch SATA hard disk drive with separate keyed SATA power and SATA data ports.',
};
