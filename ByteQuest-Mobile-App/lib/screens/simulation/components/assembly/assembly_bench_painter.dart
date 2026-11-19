import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/mission_content_data.dart';
import 'assembly_bench_layout.dart';

/// Physical details drawn over the part photographs: socket keys, levers,
/// latches, headers, screws, the anti-static mat and routed cables. Purely
/// visual; hit testing is done by the bench widgets.
class AssemblyBenchPainter extends CustomPainter {
  AssemblyBenchPainter({
    required this.view,
    required this.settings,
    required this.placements,
    required this.links,
    required this.highlighted,
    required this.boardInstalled,
  });

  final BenchView view;
  final Map<String, dynamic> settings;
  final Map<String, String> placements;
  final Set<String> links;
  final Set<String> highlighted;
  final bool boardInstalled;

  static const _silk = Color(0xFFE8EEF8);
  static const _metal = Color(0xFF9AA6B8);
  static const _key = Color(0xFFF2B640);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / AssemblyBenchLayout.canvas.width,
        size.height / AssemblyBenchLayout.canvas.height);
    switch (view) {
      case BenchView.mat:
        _paintMat(canvas);
      case BenchView.board:
        _paintBoardDetails(canvas);
      case BenchView.chassis:
        _paintChassis(canvas);
        if (boardInstalled) _paintBoardDetails(canvas);
    }
    canvas.restore();
  }

  /// Routed cables and guide highlights, drawn above the part photographs.
  void paintWiring(Canvas canvas) {
    _paintCables(canvas);
    _paintHighlights(canvas);
  }

  void _paintMat(Canvas canvas) {
    const mat = AssemblyBenchLayout.matRect;
    canvas.drawRRect(RRect.fromRectAndRadius(mat, const Radius.circular(18)),
        Paint()..color = const Color(0xFF2E3A4D));
    final grid = Paint()
      ..color = const Color(0x334C7DFF)
      ..strokeWidth = 2;
    for (var x = mat.left + 40; x < mat.right; x += 40) {
      canvas.drawLine(Offset(x, mat.top), Offset(x, mat.bottom), grid);
    }
    for (var y = mat.top + 40; y < mat.bottom; y += 40) {
      canvas.drawLine(Offset(mat.left, y), Offset(mat.right, y), grid);
    }
    final ground = AssemblyBenchLayout.operation('ground_wrist_strap', view)!;
    canvas.drawCircle(ground.center, 22, Paint()..color = _metal);
    canvas.drawCircle(ground.center, 9, Paint()..color = const Color(0xFF2E3A4D));
    if (settings['esd_grounded'] == true) {
      final strap = AssemblyBenchLayout.operation('wear_wrist_strap', view)!;
      final cord = Path()
        ..moveTo(strap.center.dx, strap.center.dy)
        ..cubicTo(strap.center.dx - 260, strap.bottom + 60, ground.center.dx + 220,
            ground.center.dy + 60, ground.center.dx, ground.center.dy);
      canvas.drawPath(
          cord,
          Paint()
            ..color = AppTheme.accentGreen
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.round);
    }
  }

  void _paintBoardDetails(Canvas canvas) {
    final socket = AssemblyBenchLayout.slot('cpu_socket', view)!;
    final unit = socket.width / 60;
    final frame = Paint()
      ..color = _metal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4 * unit;
    canvas.drawRect(socket.inflate(3 * unit), frame);
    // Pin-1 triangle printed on the socket corner (bottom-left).
    final corner = socket.bottomLeft + Offset(-3 * unit, 3 * unit);
    canvas.drawPath(
        Path()
          ..moveTo(corner.dx, corner.dy)
          ..lineTo(corner.dx + 11 * unit, corner.dy)
          ..lineTo(corner.dx, corner.dy - 11 * unit)
          ..close(),
        Paint()..color = _key);
    final lever = AssemblyBenchLayout.operation('close_cpu_lever', view)!;
    final open = settings['cpu_lever'] == 'open';
    final pivot = lever.bottomCenter;
    final angle = open ? -math.pi / 2.6 : -math.pi / 2;
    final tip = pivot + Offset.fromDirection(angle, lever.height * .95);
    canvas.drawLine(
        pivot,
        tip,
        Paint()
          ..color = const Color(0xFFCBD3E0)
          ..strokeWidth = 3.2 * unit
          ..strokeCap = StrokeCap.round);
    if (settings['thermal_compound'] == true &&
        placements['cpu'] != null &&
        placements['cooler'] == null) {
      canvas.drawCircle(socket.center, 7 * unit,
          Paint()..color = const Color(0xFFD9DDE3));
    }
    final latchesOpen = settings['dimm_latches'] == 'open';
    for (final id in const ['dimm_a1', 'dimm_a2', 'dimm_b1', 'dimm_b2']) {
      final slot = AssemblyBenchLayout.slot(id, view)!;
      final s = slot.width / 7;
      // Slot key, off centre like the module notch.
      canvas.drawRect(
          Rect.fromLTWH(slot.left, slot.top + slot.height * .42, slot.width,
              2.2 * s),
          Paint()..color = _key);
      final latch = Paint()
        ..color = const Color(0xFFD7DEE9)
        ..strokeWidth = 2.2 * s
        ..strokeCap = StrokeCap.round;
      for (final end in [slot.topCenter, slot.bottomCenter]) {
        final direction = end == slot.topCenter ? -1.0 : 1.0;
        final reach = Offset(latchesOpen ? 4 * s : 0, direction * 6 * s);
        canvas.drawLine(end, end + reach, latch);
      }
      final module = placements.entries
          .where((entry) => entry.value == id)
          .map((entry) => entry.key)
          .firstOrNull;
      if (module != null) {
        final body = slot.inflate(1.2 * s);
        canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(s)),
            Paint()..color = const Color(0xFF14181F));
        canvas.drawRect(
            Rect.fromLTWH(body.left, body.top, body.width, 3 * s),
            Paint()..color = const Color(0xFFC9A227));
      }
      _label(canvas, id.substring(5).toUpperCase(),
          slot.topCenter - Offset(0, 9 * s), 4.4 * s);
    }
    for (final header in const [
      ('cpu_fan_header', MissionContentData.benchSilkscreenCpuFan),
      ('sys_fan_header', MissionContentData.benchSilkscreenSysFan),
      ('board_atx24', MissionContentData.benchSilkscreenAtx24),
      ('board_eps8', MissionContentData.benchSilkscreenEps8),
      ('board_front_panel', MissionContentData.benchSilkscreenFrontPanel),
    ]) {
      final rect = AssemblyBenchLayout.slot(header.$1, view)!;
      final s = socket.width / 60;
      canvas.drawRect(
          rect,
          Paint()
            ..color = _silk
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2 * s);
      _label(canvas, header.$2, rect.bottomCenter + Offset(0, 6 * s), 5 * s);
    }
  }

  void _paintChassis(Canvas canvas) {
    final outline = Paint()
      ..color = const Color(0x99E8EEF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final id in const ['psu_bay', 'drive_bay', 'io_cutout']) {
      final occupied = placements.values.contains(id);
      if (!occupied) {
        canvas.drawRect(AssemblyBenchLayout.slot(id, view)!, outline);
      }
    }
    if (placements['io_shield'] == 'io_cutout') {
      final shield = AssemblyBenchLayout.slot('io_cutout', view)!;
      canvas.drawRect(shield, Paint()..color = _metal);
      final hole = Paint()..color = const Color(0xFF384252);
      for (var y = shield.top + 8; y < shield.bottom - 8; y += 18) {
        canvas.drawRect(
            Rect.fromLTWH(shield.left + 4, y, shield.width - 8, 9), hole);
      }
    }
    if (!boardInstalled) {
      final tray = AssemblyBenchLayout.slot('board_standoffs', view)!;
      final standoff = Paint()..color = const Color(0xFFC9A227);
      for (final corner in [
        tray.topLeft,
        tray.topRight,
        tray.centerLeft,
        tray.centerRight,
        tray.bottomLeft,
        tray.bottomRight
      ]) {
        canvas.drawCircle(
            Offset.lerp(corner, tray.center, .06)!, 5, standoff);
      }
    }
    final screw = Paint()..color = const Color(0xFFDFE5EE);
    final slotLine = Paint()
      ..color = const Color(0xFF384252)
      ..strokeWidth = 1.6;
    void screws(Rect rect) {
      for (final corner in [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight
      ]) {
        final at = Offset.lerp(corner, rect.center, .12)!;
        canvas.drawCircle(at, 6, screw);
        canvas.drawLine(at - const Offset(4, 0), at + const Offset(4, 0),
            slotLine);
        canvas.drawLine(at - const Offset(0, 4), at + const Offset(0, 4),
            slotLine);
      }
    }

    if (settings['psu_fastened'] == true && placements['psu'] != null) {
      screws(AssemblyBenchLayout.slot('psu_bay', view)!);
    }
    if (settings['drive_fastened'] == true && placements['storage'] != null) {
      screws(AssemblyBenchLayout.slot('drive_bay', view)!);
    }
    if (settings['board_fastened'] == true && boardInstalled) {
      screws(AssemblyBenchLayout.slot('board_standoffs', view)!);
    }
  }

  void _paintCables(Canvas canvas) {
    for (final pair in links) {
      final split = pair.indexOf('>');
      if (split <= 0) continue;
      final source = pair.substring(0, split);
      final destination = pair.substring(split + 1);
      final from = AssemblyBenchLayout.cableOrigin(source, view);
      final to = AssemblyBenchLayout.slot(destination, view)?.center;
      if (from == null || to == null) continue;
      final colour = switch (source) {
        'atx_24pin' => const Color(0xFF20242B),
        'eps_8pin' => const Color(0xFF8A1C2B),
        'sata_power' => const Color(0xFF4B2E83),
        'sata_data' => const Color(0xFFB54708),
        'front_panel' => const Color(0xFF1F5EFF),
        _ => const Color(0xFF3A4556),
      };
      final bend = (to - from).distance * .35;
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..cubicTo(from.dx, from.dy - bend, to.dx + bend * .4, to.dy + bend * .2,
            to.dx, to.dy);
      canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white.withValues(alpha: .55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 11
            ..strokeCap = StrokeCap.round);
      canvas.drawPath(
          path,
          Paint()
            ..color = colour
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.round);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: to, width: 18, height: 12),
              const Radius.circular(3)),
          Paint()..color = colour);
    }
  }

  void _paintHighlights(Canvas canvas) {
    final paint = Paint()
      ..color = AppTheme.primaryBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    for (final id in highlighted) {
      final rect = AssemblyBenchLayout.slot(id, view) ??
          AssemblyBenchLayout.operation(id, view) ??
          AssemblyBenchLayout.matParts[id];
      if (rect == null) continue;
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(6), const Radius.circular(8)),
          paint);
    }
  }

  void _label(Canvas canvas, String text, Offset center, double fontSize) {
    final painter = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: _silk,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: .4)),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas,
        center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant AssemblyBenchPainter oldDelegate) =>
      oldDelegate.view != view ||
      oldDelegate.boardInstalled != boardInstalled ||
      !_same(oldDelegate.settings, settings) ||
      !_same(oldDelegate.placements, placements) ||
      oldDelegate.links.length != links.length ||
      !oldDelegate.links.containsAll(links) ||
      oldDelegate.highlighted.length != highlighted.length ||
      !oldDelegate.highlighted.containsAll(highlighted);

  static bool _same(Map<String, dynamic> a, Map<String, dynamic> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
}
