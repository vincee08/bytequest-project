import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'port_bench_layout.dart';

const _ink = Color(0xff172736);
const _metal = Color(0xffa5b3bf);
const _socket = Color(0xff10212d);
const _contact = Color(0xffdebd70);
const _focus = Color(0xff2861ac);

typedef PortLeadPose = ({
  Offset root,
  Offset tip,
  PlugShape shape,
  bool seated
});

/// A connector viewed head-on; loose lead tips and receptacles use the same keyed profile.
void _connector(Canvas c, Offset at, PlugShape shape, {bool male = false}) {
  c.save();
  c.translate(at.dx, at.dy);
  final edge = Paint()..color = _metal;
  final inside = Paint()..color = _socket;
  final pins = Paint()..color = _contact;
  final lip = Path();
  switch (shape) {
    case PlugShape.hdmi:
      lip.addPolygon(const [
        Offset(-12, -5),
        Offset(12, -5),
        Offset(12, 1),
        Offset(8, 5),
        Offset(-8, 5),
        Offset(-12, 1)
      ], true);
    case PlugShape.usb:
      lip.addRect(const Rect.fromLTWH(-9, -5, 18, 10));
    case PlugShape.ethernet:
      lip.addPolygon(const [
        Offset(-8, -6),
        Offset(8, -6),
        Offset(8, 3),
        Offset(4, 3),
        Offset(4, 6),
        Offset(-4, 6),
        Offset(-4, 3),
        Offset(-8, 3)
      ], true);
  }
  c.drawPath(lip, edge);
  c.save();
  c.scale(.84, .78);
  c.drawPath(lip, inside);
  c.restore();
  if (shape == PlugShape.usb) {
    c.drawRect(Rect.fromLTWH(-7, male ? -2 : .5, 14, 2.4),
        Paint()..color = const Color(0xff88adc8));
    for (final x in [-5.0, -2.0, 2.0, 5.0]) {
      c.drawLine(Offset(x, 0), Offset(x, 1), pins);
    }
  } else if (shape == PlugShape.hdmi) {
    c.drawRect(const Rect.fromLTWH(-8, -1, 16, 1.6), pins);
  } else {
    for (var i = 0; i < 8; i++) {
      final x = -5.6 + i * 1.6;
      c.drawLine(Offset(x, -4), Offset(x + .3, -.6), pins);
    }
  }
  c.restore();
}

class PortPlugPainter extends CustomPainter {
  const PortPlugPainter(this.shape);
  final PlugShape shape;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(1.55);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(-9, 0, 18, 11), const Radius.circular(2)),
        Paint()..color = _ink);
    _connector(canvas, Offset.zero, shape, male: true);
    canvas.restore();
  }

  @override
  bool shouldRepaint(PortPlugPainter oldDelegate) => oldDelegate.shape != shape;
}

class PortPlatePainter extends CustomPainter {
  const PortPlatePainter(this.layout);
  final PortBenchLayout layout;
  @override
  void paint(Canvas c, Size size) {
    c.save();
    c.scale(size.width / PortBenchLayout.drawing.width,
        size.height / PortBenchLayout.drawing.height);
    c.drawRect(Offset.zero & PortBenchLayout.drawing,
        Paint()..color = const Color(0xffe3ecee));
    final rule = Paint()
      ..color = const Color(0xffcedadf)
      ..strokeWidth = .45;
    for (var i = 12.0; i < 360; i += 12) {
      c.drawLine(Offset(i, 0), Offset(i, 216), rule);
    }
    for (var i = 12.0; i < 216; i += 12) {
      c.drawLine(Offset(0, i), Offset(360, i), rule);
    }
    for (final plate in layout.plates) {
      final body =
          RRect.fromRectAndRadius(plate.body, const Radius.circular(3));
      c.drawRRect(body, Paint()..color = const Color(0xff596875));
      c.drawRRect(body.deflate(1.2), Paint()..color = const Color(0xffc0cbd1));
      c.drawRRect(
          body.deflate(3),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .7
            ..color = const Color(0xffe6ecef));
      for (final corner in [
        plate.body.topLeft + const Offset(5, 5),
        plate.body.bottomRight - const Offset(5, 5)
      ]) {
        c.drawCircle(corner, 2, Paint()..color = const Color(0xff56626b));
        c.drawLine(
            corner - const Offset(1, 0),
            corner + const Offset(1, 0),
            Paint()
              ..color = Colors.white
              ..strokeWidth = .65);
      }
    }
    for (final bank in layout.banks.values) {
      for (final p in bank.sockets) {
        _connector(c, p, bank.shape);
      }
    }
    c.restore();
  }

  @override
  bool shouldRepaint(PortPlatePainter oldDelegate) =>
      oldDelegate.layout != layout;
}

class PortCablePainter extends CustomPainter {
  const PortCablePainter(this.leads, {this.hover});
  final Map<String, PortLeadPose> leads;
  final Offset? hover;
  @override
  void paint(Canvas c, Size size) {
    c.save();
    c.scale(size.width / PortBenchLayout.drawing.width,
        size.height / PortBenchLayout.drawing.height);
    for (final lead in leads.values) {
      final a = lead.root;
      final b = lead.tip;
      if (lead.shape == PlugShape.ethernet) {
        _connector(c, a, lead.shape);
      }
      c.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: a, width: 8, height: 5),
              const Radius.circular(1)),
          Paint()..color = _ink);
      final sag = math.min(26.0, (b - a).distance * .22);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(a.dx + 10, a.dy + sag, b.dx - 14, b.dy + sag, b.dx, b.dy);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      c.drawPath(
          path.shift(const Offset(.6, 1.0)),
          stroke
            ..color = const Color(0x380e202a)
            ..strokeWidth = 3.3);
      c.drawPath(
          path,
          stroke
            ..color = _ink
            ..strokeWidth = 3.3);
      c.drawPath(
          path,
          stroke
            ..color = (lead.shape == PlugShape.ethernet
                ? const Color(0xff487397)
                : const Color(0xff626d75))
            ..strokeWidth = 1.25);
      if (lead.seated) {
        final boot = RRect.fromRectAndRadius(
            Rect.fromCenter(center: b, width: 15, height: 8),
            const Radius.circular(1.7));
        c.drawRRect(boot, Paint()..color = _ink);
        for (final x in [-4.0, -1.0, 2.0]) {
          c.drawLine(
              b + Offset(x, -2),
              b + Offset(x, 2),
              stroke
                ..color = _metal
                ..strokeWidth = .7);
        }
      } else {
        _connector(c, b, lead.shape, male: true);
      }
    }
    if (hover case final p?) {
      c.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: p, width: 30, height: 21),
              const Radius.circular(3)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = _focus);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(PortCablePainter oldDelegate) =>
      hover != oldDelegate.hover || !mapEquals(leads, oldDelegate.leads);
}
