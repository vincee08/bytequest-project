part of '../mission_simulation_definitions.dart';

// Equipment deployment work orders from the supplied TESDA SAG:
// computer assembly/installation (pp. 1-2), networks (pp. 3-4), servers (p. 5).
// These placements supplement inspection, configuration and measured checks.
Map<String, dynamic> _practiceWorkspacePanel(String missionId) {
  final devices = switch (missionId) {
    'coc1_m1' => const [
        ('motherboard', 'Motherboard', 'ESD inspection mat'),
        ('cpu', 'Processor', 'Processor inspection tray'),
        ('ram', 'Memory module', 'Memory inspection mat'),
        ('psu', 'Power supply', 'Isolated electrical bench'),
      ],
    'coc1_m2' => const [
        ('service_chassis', 'Empty computer chassis', 'Assembly bench'),
        ('esd_mat', 'Anti-static mat', 'Grounded work area'),
      ],
    'coc1_m3' => const [
        ('system_unit', 'Workstation', 'OS installation bench'),
        ('boot_usb', 'Bootable USB device', 'Installation media station'),
      ],
    'coc1_m4' => const [
        ('monitor', 'Monitor', 'Display position'),
        ('keyboard', 'USB keyboard', 'Keyboard position'),
        ('mouse', 'USB mouse', 'Pointer position'),
      ],
    'coc1_m5' => const [
        ('system_unit', 'Workstation', 'Monitored system test bench'),
        ('storage', 'Storage drive', 'Storage test station'),
      ],
    'coc2_m1' => const [
        ('copper_cable', 'Copper cable', 'Cable preparation bench'),
        ('rj45_connector', 'RJ45 connector', 'Termination station'),
        ('lan_cable_tester', 'LAN tester', 'Continuity test station'),
      ],
    'coc2_m2' => const [
        ('copper_cable', 'Copper cable', 'T568B termination bench'),
        ('switch', 'LAN switch', 'LAN distribution position'),
        ('router', 'Router', 'Gateway position'),
      ],
    'coc2_m4' => const [
        ('router', 'Wireless router', 'Gateway position'),
        ('switch', 'Managed switch', 'LAN distribution position'),
        ('repeater', 'Wireless repeater', 'Coverage extension position'),
      ],
    'coc2_m5' => const [
        ('workstation', 'Client workstation', 'Terminal test position'),
        ('switch', 'LAN switch', 'Local network position'),
      ],
    'coc3_m2' => const [
        ('server_node', 'Server', 'NOS installation rack'),
        ('client_node', 'Client workstation', 'Deployment test position'),
      ],
    'coc3_m3' => const [
        ('server_node', 'File server', 'Protected user-folder server'),
        ('client_node', 'Client workstation', 'User access test position'),
      ],
    'coc3_m4' => const [
        ('server_node', 'Service host', 'Network service rack'),
        ('client_node', 'Client workstation', 'File-sharing test position'),
        ('network_printer', 'Network printer', 'Printer-sharing test position'),
      ],
    'coc3_m5' => const [
        ('server_node', 'File server', 'Server service position'),
        ('client_node', 'Client workstation', 'Access verification position'),
      ],
    _ => throw ArgumentError.value(missionId, 'missionId'),
  };
  return {
    'items': [
      for (final device in devices)
        {
          'id': device.$1,
          'label': device.$2,
          'category': device.$1,
          'imageAsset': _imageAssetForObject(missionId, device.$1),
        },
    ],
    'destinations': [
      for (final device in devices)
        {
          'id': '${device.$1}_position',
          'label': device.$3,
          'socket_categories': [device.$1],
        },
    ],
  };
}
