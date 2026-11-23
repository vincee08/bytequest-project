import 'package:flutter/painting.dart';

import '../../../../data/mission_content_data.dart';
import '../../runtime/mission_runtime_models.dart';
import 'physical_surface.dart';

enum PlugShape { hdmi, usb, ethernet }

typedef CableLead = ({Rect reach, Offset root, Offset tip, PlugShape shape});
typedef SocketBank = ({PlugShape shape, List<Offset> sockets});
typedef BenchDevice = ({String id, Rect photo, Rect name});
typedef BenchPlate = ({Rect body, String legend});

/// Dimensions are measured on a 360 × 216 drawing; the scene's camera uses 1200 × 720.
class PortBenchLayout {
  const PortBenchLayout(
      this.title, this.devices, this.plates, this.leads, this.banks);

  final String title;
  final List<BenchDevice> devices;
  final List<BenchPlate> plates;
  final Map<String, CableLead> leads;
  final Map<String, SocketBank> banks;
  static const drawing = Size(360, 216);
  static const scale = 1200 / 360;
  static Rect world(Rect r) => Rect.fromLTRB(
      r.left * scale, r.top * scale, r.right * scale, r.bottom * scale);

  static PortBenchLayout? resolve(
      String mission,
      MissionPhaseDefinition phase,
      List<Map<String, dynamic>> sources,
      List<Map<String, dynamic>> destinations) {
    if (!phase.id.startsWith('${mission}_') ||
        phase.resolvedInteraction != InteractionFamily.connect) {
      return null;
    }
    final layout = _registry[phase.id];
    if (layout == null ||
        !_matches(layout.leads.keys, sources) ||
        !_matches(layout.banks.keys, destinations)) {
      return null;
    }
    return layout;
  }

  static bool _matches(
          Iterable<String> keys, List<Map<String, dynamic>> panel) =>
      keys.length == panel.length &&
      keys.every((id) => panel.any((e) => e['id'] == id));

  // Socket and finger geometry are independent. The object picker supplies full-size controls for dense jack banks.
  PhysicalMount mount(String bank, int index) {
    final spec = banks[bank]!;
    final p = spec.sockets[index];
    final w = spec.shape == PlugShape.hdmi ? 25.0 : 17.0;
    return PhysicalMount(
        '$bank:$index', Rect.fromCenter(center: p, width: w, height: 12),
        capture: Rect.fromCenter(center: p, width: w + 18, height: 32));
  }

  static const _registry = {
    'coc1_m4_p3': _rearIo,
    'coc2_m1_p4': _tester,
    'coc2_m2_p3': _chain,
    'coc2_m3_p2': _star,
  };

  static const _rearIo = PortBenchLayout(MissionContentData.portBenchRear, [
    (
      id: 'monitor',
      photo: Rect.fromLTWH(9, 12, 66, 55),
      name: Rect.fromLTWH(4, 71, 99, 16)
    ),
    (
      id: 'keyboard',
      photo: Rect.fromLTWH(106, 12, 77, 55),
      name: Rect.fromLTWH(102, 71, 98, 16)
    ),
    (
      id: 'mouse',
      photo: Rect.fromLTWH(12, 117, 65, 58),
      name: Rect.fromLTWH(3, 181, 92, 16)
    ),
    (
      id: 'network_adapter',
      photo: Rect.fromLTWH(105, 120, 81, 53),
      name: Rect.fromLTWH(100, 181, 100, 16)
    ),
  ], [
    (
      body: Rect.fromLTWH(216, 8, 134, 199),
      legend: MissionContentData.portBenchRearPlate
    ),
  ], {
    'monitor': (
      reach: Rect.fromLTWH(4, 10, 94, 79),
      root: Offset(59, 54),
      tip: Offset(88, 60),
      shape: PlugShape.hdmi
    ),
    'keyboard': (
      reach: Rect.fromLTWH(102, 10, 99, 79),
      root: Offset(165, 53),
      tip: Offset(194, 60),
      shape: PlugShape.usb
    ),
    'mouse': (
      reach: Rect.fromLTWH(4, 117, 93, 84),
      root: Offset(60, 153),
      tip: Offset(88, 167),
      shape: PlugShape.usb
    ),
    'network_adapter': (
      reach: Rect.fromLTWH(101, 117, 99, 84),
      root: Offset(159, 155),
      tip: Offset(194, 167),
      shape: PlugShape.ethernet
    ),
  }, {
    'hdmi_port': (shape: PlugShape.hdmi, sockets: [Offset(283, 49)]),
    'usb_port': (
      shape: PlugShape.usb,
      sockets: [Offset(259, 106), Offset(306, 106)]
    ),
    'ethernet_port': (shape: PlugShape.ethernet, sockets: [Offset(283, 166)]),
  });

  static const _tester = PortBenchLayout(MissionContentData.portBenchTester, [
    (
      id: 'copper_cable',
      photo: Rect.fromLTWH(20, 39, 128, 108),
      name: Rect.fromLTWH(4, 163, 180, 19)
    ),
    (
      id: 'lan_cable_tester',
      photo: Rect.fromLTWH(220, 8, 100, 110),
      name: Rect.fromLTWH(190, 179, 160, 19)
    ),
  ], [
    (
      body: Rect.fromLTWH(210, 116, 120, 60),
      legend: MissionContentData.portBenchTesterJack
    ),
  ], {
    'copper_cable': (
      reach: Rect.fromLTWH(10, 38, 158, 133),
      root: Offset(96, 124),
      tip: Offset(153, 141),
      shape: PlugShape.ethernet
    ),
  }, {
    'lan_cable_tester': (
      shape: PlugShape.ethernet,
      sockets: [Offset(269, 151)]
    ),
  });

  static const _chain = PortBenchLayout(MissionContentData.portBenchNetwork, [
    (
      id: 'workstation',
      photo: Rect.fromLTWH(6, 62, 80, 73),
      name: Rect.fromLTWH(4, 149, 95, 18)
    ),
    (
      id: 'switch',
      photo: Rect.fromLTWH(124, 20, 93, 51),
      name: Rect.fromLTWH(109, 7, 119, 14)
    ),
    (
      id: 'router',
      photo: Rect.fromLTWH(254, 83, 88, 57),
      name: Rect.fromLTWH(246, 185, 103, 16)
    ),
  ], [
    (
      body: Rect.fromLTWH(112, 69, 126, 46),
      legend: MissionContentData.portBenchLan
    ),
    (
      body: Rect.fromLTWH(250, 136, 100, 44),
      legend: MissionContentData.portBenchLan
    ),
  ], {
    'workstation': (
      reach: Rect.fromLTWH(4, 60, 95, 90),
      root: Offset(63, 116),
      tip: Offset(92, 134),
      shape: PlugShape.ethernet
    ),
    'switch': (
      reach: Rect.fromLTWH(185, 60, 57, 62),
      root: Offset(202, 96),
      tip: Offset(231, 109),
      shape: PlugShape.ethernet
    ),
  }, {
    'switch': (shape: PlugShape.ethernet, sockets: [Offset(137, 96)]),
    'router': (
      shape: PlugShape.ethernet,
      sockets: [Offset(275, 161), Offset(323, 161)]
    ),
  });

  static const _star = PortBenchLayout(MissionContentData.portBenchNetwork, [
    (
      id: 'router',
      photo: Rect.fromLTWH(4, 16, 81, 52),
      name: Rect.fromLTWH(3, 79, 96, 16)
    ),
    (
      id: 'workstation_a',
      photo: Rect.fromLTWH(7, 122, 68, 58),
      name: Rect.fromLTWH(2, 184, 98, 16)
    ),
    (
      id: 'workstation_b',
      photo: Rect.fromLTWH(105, 122, 68, 58),
      name: Rect.fromLTWH(100, 184, 98, 16)
    ),
    (
      id: 'switch',
      photo: Rect.fromLTWH(139, 11, 95, 43),
      name: Rect.fromLTWH(119, 1, 122, 12)
    ),
    (
      id: 'server',
      photo: Rect.fromLTWH(243, 107, 95, 44),
      name: Rect.fromLTWH(236, 197, 113, 14)
    ),
  ], [
    (
      body: Rect.fromLTWH(111, 51, 153, 44),
      legend: MissionContentData.portBenchLan
    ),
    (
      body: Rect.fromLTWH(224, 149, 130, 46),
      legend: MissionContentData.portBenchLan
    ),
  ], {
    'router': (
      reach: Rect.fromLTWH(2, 13, 96, 83),
      root: Offset(60, 52),
      tip: Offset(90, 70),
      shape: PlugShape.ethernet
    ),
    'workstation_a': (
      reach: Rect.fromLTWH(2, 117, 95, 85),
      root: Offset(47, 158),
      tip: Offset(89, 175),
      shape: PlugShape.ethernet
    ),
    'workstation_b': (
      reach: Rect.fromLTWH(100, 117, 96, 85),
      root: Offset(146, 158),
      tip: Offset(187, 175),
      shape: PlugShape.ethernet
    ),
    'switch': (
      reach: Rect.fromLTWH(210, 49, 56, 61),
      root: Offset(224, 76),
      tip: Offset(250, 101),
      shape: PlugShape.ethernet
    ),
  }, {
    'switch': (
      shape: PlugShape.ethernet,
      sockets: [Offset(128, 77), Offset(157, 77), Offset(186, 77)]
    ),
    'server': (
      shape: PlugShape.ethernet,
      sockets: [
        Offset(240, 177),
        Offset(270, 177),
        Offset(300, 177),
        Offset(330, 177)
      ]
    ),
  });
}
