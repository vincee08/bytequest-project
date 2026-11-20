import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// The three physical views of the assembly bench.
enum BenchView { mat, board, chassis }

/// The physical key a learner lines up before seating a keyed part.
enum BenchMarkerKind { triangle, notch, fan }

/// Where a keyed part's marker sits on its photograph at 0°, the seating
/// orientation. The marker is drawn inside the part's rotation, so it turns
/// with the part in the tray, the preview, the drag ghost and the slot.
final class BenchMarker {
  const BenchMarker(this.kind, this.box, {this.baseTurns = 0});

  final BenchMarkerKind kind;

  /// Marker box as fractions of the square part image.
  final Rect box;

  /// Quarter turns applied to the photograph itself so that 0° shows the
  /// seating orientation (the power-supply photo is taken fan-up).
  final int baseTurns;

  /// Fan circle of the power supply at 0°, as fractions of the image.
  static const fanCentre = Offset(.5, .67);
  static const fanRadius = .2;
}

/// Fixed geometry of the COC1 M2 bench in the shared 1200 × 720 logical
/// canvas of the simulation scene. Positions are traced from the real part
/// photographs (motherboard 500 × 500 px, open case 1086 × 1448 px), so a
/// part snaps into the slot printed on the image, not into a labelled box.
abstract final class AssemblyBenchLayout {
  static const canvas = Size(1200, 720);

  static const caseAsset = 'assets/COC1/Mission 2/empty_system_unit_case.png';
  static const boardAsset = 'assets/COC1/Mission 2/motherboard.png';
  static const strapAsset = 'assets/COC1/Mission 1/anti_static_wrist_strap.png';
  static const screwdriverAsset = 'assets/COC1/Mission 1/screwdriver.png';

  // --- Motherboard close-up on the anti-static mat (board view). ----------
  // Board image pixel (u, v) maps to canvas (boardOrigin + (u, v) * scale).
  static const boardScale = 3.18;
  static const boardOrigin = Offset(250 - 190 * boardScale, 10 - 25 * boardScale);
  static Rect boardImageRect(BenchView view) => view == BenchView.board
      ? Rect.fromLTWH(boardOrigin.dx, boardOrigin.dy, 500 * boardScale,
          500 * boardScale)
      : Rect.fromLTWH(_chassisBoardOrigin.dx, _chassisBoardOrigin.dy,
          500 * _chassisBoardScale, 500 * _chassisBoardScale);

  /// Board-image pixels between neighbouring memory slots.
  static const dimmPitch = 12.5;

  static double _boardScaleIn(BenchView view) =>
      view == BenchView.board ? boardScale : _chassisBoardScale;

  static Rect _board(BenchView view, double u, double v, double w, double h) {
    final scale = _boardScaleIn(view);
    final origin = view == BenchView.board ? boardOrigin : _chassisBoardOrigin;
    return Rect.fromLTWH(
        origin.dx + u * scale, origin.dy + v * scale, w * scale, h * scale);
  }

  // --- Open case (chassis view). Case pixel (u, v) → x + u * s, v * s. ---
  static const _caseScale = 720 / 1448;
  static const caseRect =
      Rect.fromLTWH(330, 0, 1086 * _caseScale, 1448 * _caseScale);
  static Rect _case(double u, double v, double w, double h) => Rect.fromLTWH(
      caseRect.left + u * _caseScale,
      v * _caseScale,
      w * _caseScale,
      h * _caseScale);

  // The installed board PCB (image pixels 76..428 × 37..458) fills the tray.
  static final Rect _tray = _case(197, 228, 443, 530);
  static final _chassisBoardScale = _tray.width / 352;
  static final Offset _chassisBoardOrigin = Offset(
      _tray.left - 76 * _chassisBoardScale, _tray.top - 37 * _chassisBoardScale);

  /// Board-level destinations exist in the close-up and, once the
  /// motherboard is installed, at the same physical spot in the case.
  static const boardDestinations = {
    'cpu_socket',
    'cooler_mount',
    'dimm_a1',
    'dimm_a2',
    'dimm_b1',
    'dimm_b2',
    'cpu_fan_header',
    'sys_fan_header',
    'board_atx24',
    'board_eps8',
    'board_front_panel',
  };

  static Rect? slot(String id, BenchView view) {
    if (view == BenchView.mat) return null;
    if (view == BenchView.chassis) {
      switch (id) {
        case 'psu_bay':
          return _case(150, 1022, 300, 228);
        case 'io_cutout':
          return _case(170, 226, 40, 254);
        case 'board_standoffs':
          return _tray;
        case 'drive_bay':
          return _case(745, 600, 170, 330);
        case 'drive_power':
          return _case(745, 760, 34, 60);
        case 'drive_data':
          return _case(745, 690, 34, 50);
      }
    }
    return switch (id) {
      'cpu_socket' => _board(view, 229, 137, 60, 60),
      'cooler_mount' => _board(view, 204, 112, 110, 110),
      'dimm_a1' => _board(view, 329, 48, 7, 224),
      'dimm_a2' => _board(view, 341.5, 48, 7, 224),
      'dimm_b1' => _board(view, 354, 48, 7, 224),
      'dimm_b2' => _board(view, 366.5, 48, 7, 224),
      'cpu_fan_header' => _board(view, 300, 38, 16, 9),
      'sys_fan_header' => _board(view, 392, 228, 9, 16),
      'board_atx24' => _board(view, 410, 103, 14, 92),
      'board_eps8' => _board(view, 132, 38, 33, 15),
      'board_front_panel' => _board(view, 330, 440, 22, 12),
      _ => null,
    };
  }

  /// Slots that occupy the same physical spot (the cooler sits on the CPU).
  /// A drop there snaps to the layer that accepts the dragged part.
  static const stacked = [
    {'cpu_socket', 'cooler_mount'},
  ];

  /// Cable headers and ports. Where two neighbours' padded touch areas would
  /// overlap, each stops halfway between the two ports, so the highlighted
  /// area of one port never takes a tap or a drop meant for it on behalf of
  /// its neighbour. (In the case the drive's SATA data port covered the top
  /// of the SATA power port, and SYS_FAN overlapped the 24-pin header.)
  static const cableHeaders = [
    'cpu_fan_header',
    'sys_fan_header',
    'board_atx24',
    'board_eps8',
    'board_front_panel',
    'drive_power',
    'drive_data',
  ];

  /// Touch area for a slot: never thinner than [minimum] logical units, and
  /// memory slots claim exactly the pitch between neighbours (a magnetic
  /// snap that never overlaps the next slot, in the close-up and the case).
  /// Cable headers likewise never overlap one another ([cableHeaders]).
  static Rect? target(String id, BenchView view, {double minimum = 64}) {
    final rect = slot(id, view);
    if (rect == null) return null;
    var area = _padded(id, rect, view, minimum);
    if (!cableHeaders.contains(id)) return area;
    for (final other in cableHeaders) {
      if (other == id) continue;
      final port = slot(other, view);
      if (port == null || !_padded(other, port, view, minimum).overlaps(area)) {
        continue;
      }
      area = _awayFrom(area, rect, port);
    }
    return area;
  }

  static Rect _padded(String id, Rect rect, BenchView view, double minimum) {
    final width = id.startsWith('dimm_')
        ? dimmPitch * _boardScaleIn(view)
        : math.max(rect.width, minimum);
    return Rect.fromCenter(
        center: rect.center,
        width: width,
        height: math.max(rect.height, minimum));
  }

  /// [area], the padded touch area of the port [own], trimmed back to the
  /// line halfway between [own] and the neighbouring [port], across the
  /// wider of the two gaps. Both neighbours trim to the same line.
  static Rect _awayFrom(Rect area, Rect own, Rect port) {
    final gapX = own.right <= port.left
        ? port.left - own.right
        : port.right <= own.left
            ? own.left - port.right
            : -1.0;
    final gapY = own.bottom <= port.top
        ? port.top - own.bottom
        : port.bottom <= own.top
            ? own.top - port.bottom
            : -1.0;
    if (gapY >= 0 && gapY >= gapX) {
      if (own.bottom <= port.top) {
        final mid = (own.bottom + port.top) / 2;
        return Rect.fromLTRB(
            area.left, area.top, area.right, math.min(area.bottom, mid));
      }
      final mid = (port.bottom + own.top) / 2;
      return Rect.fromLTRB(
          area.left, math.max(area.top, mid), area.right, area.bottom);
    }
    if (gapX >= 0) {
      if (own.right <= port.left) {
        final mid = (own.right + port.left) / 2;
        return Rect.fromLTRB(
            area.left, area.top, math.min(area.right, mid), area.bottom);
      }
      final mid = (port.right + own.left) / 2;
      return Rect.fromLTRB(
          math.max(area.left, mid), area.top, area.right, area.bottom);
    }
    return area; // The ports themselves overlap: nothing to split.
  }

  /// Where a cable leaves its source (power supply, case front, cooler).
  static Offset? cableOrigin(String id, BenchView view) {
    if (view == BenchView.board) {
      return id == 'cooler_fan' ? slot('cooler_mount', view)!.center : null;
    }
    if (view != BenchView.chassis) return null;
    final psu = slot('psu_bay', view)!;
    return switch (id) {
      'atx_24pin' => psu.topCenter + const Offset(30, 0),
      'eps_8pin' => psu.topLeft + const Offset(20, 0),
      'sata_power' => psu.topRight + const Offset(-12, 0),
      'sata_data' => _board(view, 404, 380, 10, 10).center,
      'front_panel' => _case(980, 1180, 10, 10).center,
      'cooler_fan' => slot('cooler_mount', view)!.center,
      _ => null,
    };
  }

  /// Hotspots that operate the equipment, at the physical part they move.
  static Rect? operation(String id, BenchView view) {
    if (view == BenchView.mat) {
      return switch (id) {
        'wear_wrist_strap' => const Rect.fromLTWH(930, 470, 150, 150),
        'ground_wrist_strap' => const Rect.fromLTWH(40, 600, 90, 90),
        _ => null,
      };
    }
    if (id == 'fasten_psu') {
      return view == BenchView.chassis ? slot('psu_bay', view) : null;
    }
    if (id == 'fasten_drive') {
      return view == BenchView.chassis ? slot('drive_bay', view) : null;
    }
    if (id == 'fasten_motherboard') {
      return view == BenchView.chassis ? _case(197, 228, 90, 90) : null;
    }
    return switch (id) {
      'open_cpu_lever' || 'close_cpu_lever' => _board(view, 292, 112, 18, 112),
      'apply_thermal_compound' => _board(view, 240, 148, 38, 38),
      'open_dimm_latches' ||
      'close_dimm_latches' =>
        _board(view, 325, 30, 54, 16),
      _ => null,
    };
  }

  /// Name plates beside the wrist strap (under it) and the mat ground stud
  /// (right of it), clear of the parts on the mat.
  static Rect? hotspotLabel(String id) => switch (id) {
        'wear_wrist_strap' => const Rect.fromLTWH(880, 626, 250, 44),
        'ground_wrist_strap' => const Rect.fromLTWH(136, 623, 290, 44),
        _ => null,
      };

  /// Parts laid out on the anti-static mat for inspection (mat view).
  static const matParts = {
    'system_case': Rect.fromLTWH(860, 40, 260, 346),
    'motherboard': Rect.fromLTWH(70, 60, 300, 300),
    'cpu': Rect.fromLTWH(410, 70, 150, 150),
    'cooler': Rect.fromLTWH(600, 60, 200, 200),
    'ram': Rect.fromLTWH(410, 250, 190, 190),
    'psu': Rect.fromLTWH(170, 400, 230, 230),
    'storage': Rect.fromLTWH(440, 450, 200, 200),
  };
  static const matRect = Rect.fromLTWH(24, 24, 800, 672);

  /// Real images for the parts of each placement panel.
  static const partAssets = {
    'cpu': 'assets/COC1/Mission 2/cpu.png',
    'cooler': 'assets/COC1/Mission 2/cooling_fan.png',
    'ram_1': 'assets/COC1/Mission 2/ram.png',
    'ram_2': 'assets/COC1/Mission 2/ram.png',
    'psu': 'assets/COC1/Mission 2/psu.png',
    'motherboard': boardAsset,
    'storage': 'assets/COC1/Mission 2/hdd.png',
    'atx_24pin': 'assets/COC1/Mission 3/24 Pin ATX.png',
    'eps_8pin': 'assets/COC1/Mission 3/CPU Power.png',
    'sata_power': 'assets/COC1/Mission 3/Sata Power.png',
    'sata_data': 'assets/COC1/Mission 3/Sata Cable.png',
    'front_panel': 'assets/COC1/Mission 3/Front Panel.png',
    'cooler_fan': 'assets/COC1/Mission 2/cooling_fan.png',
  };

  /// Orientation markers of the keyed parts, traced from their photographs:
  /// the CPU's pin-1 triangle (bottom-left corner of the substrate), the
  /// memory module's notch (on the contact edge) and the power-supply fan
  /// (facing the intake vent in the bay floor).
  static const markers = {
    'cpu': BenchMarker(
        BenchMarkerKind.triangle, Rect.fromLTWH(.124, .64, .24, .24)),
    'ram_1':
        BenchMarker(BenchMarkerKind.notch, Rect.fromLTWH(.2, .395, .19, .19)),
    'ram_2':
        BenchMarker(BenchMarkerKind.notch, Rect.fromLTWH(.2, .395, .19, .19)),
    'psu': BenchMarker(BenchMarkerKind.fan, Rect.fromLTWH(.39, .9, .22, .1),
        baseTurns: 2),
  };

  /// Height of the memory slot key (and the module notch) along the slot.
  static const dimmKeyFraction = .49;

  /// Visible part of a bay part's photograph at its seating orientation, as
  /// fractions of the square image; the rest is transparent margin. A part
  /// seated in a case bay is drawn so this box, not the margin, fills the
  /// bay. Measured from the alpha channel of the photographs (the power
  /// supply after its base half turn).
  static const bayContent = {
    'psu': Rect.fromLTRB(.264, .098, .734, .906),
    'storage': Rect.fromLTRB(.194, .056, .808, .936),
  };

  /// Smallest touch area of a ring on the bench, in canvas units: with the
  /// whole bench in view, 160 units are 48 dp on a 360 dp wide phone and
  /// 55 dp on a 412 dp one. The ring keeps its drawn size; a tap in the area
  /// around it goes to the nearest ring.
  static const ringReach = 160.0;

  /// The default view for a phase; [selection] can bring the close-up.
  static BenchView viewFor(String phaseId, {bool closeUp = false}) {
    if (phaseId.endsWith('_p1')) return BenchView.mat;
    if (phaseId.endsWith('_p2')) return BenchView.board;
    return closeUp ? BenchView.board : BenchView.chassis;
  }
}
