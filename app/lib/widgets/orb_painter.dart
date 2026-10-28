import 'dart:math';

import 'package:flutter/material.dart';

import '../core/economy.dart';

const _ink = Color(0xFF231A2E);

/// Draws an orb in the Kin art style: a glass sphere bound by two woven
/// seams, with a glowing core and a tier emblem. Shared by Flutter widgets and
/// the Flame Tether game.
void paintOrb(Canvas canvas, Offset c, double r, Orb orb, {double glow = 0}) {
  if (glow > 0) {
    canvas.drawCircle(c, r * 1.5, Paint()..color = orb.top.withValues(alpha: 0.35 * glow));
  }
  final outline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1.5, r * 0.11)
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round
    ..color = _ink;

  canvas.drawCircle(c, r, Paint()..color = Color.lerp(orb.top, _ink, 0.12)!);
  canvas.drawCircle(c + Offset(-r * 0.08, -r * 0.08), r * 0.8, Paint()..color = orb.top);
  canvas.drawCircle(c, r * 0.5, Paint()..color = Color.lerp(orb.top, Colors.white, 0.55)!);

  // Two woven seams wrapping the sphere.
  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
  final seam = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1.5, r * 0.13)
    ..color = orb.band;
  for (final a in const [0.6, -0.6]) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(a);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 2.1, height: r * 0.9), seam);
    canvas.restore();
  }
  canvas.restore();

  _emblem(canvas, c, r * 0.32, orb);
  canvas.drawCircle(c + Offset(-r * 0.42, -r * 0.48), r * 0.16, Paint()..color = Colors.white.withValues(alpha: 0.8));
  canvas.drawCircle(c, r, outline);
}

void _emblem(Canvas canvas, Offset c, double s, Orb orb) {
  final fill = Paint()..color = _ink.withValues(alpha: 0.85);
  switch (orb) {
    case Orb.seed:
      final leaf = Path()
        ..moveTo(c.dx, c.dy + s)
        ..quadraticBezierTo(c.dx - s * 1.1, c.dy - s * 0.1, c.dx, c.dy - s)
        ..quadraticBezierTo(c.dx + s * 1.1, c.dy - s * 0.1, c.dx, c.dy + s)
        ..close();
      canvas.drawPath(leaf, fill);
    case Orb.bloom:
      for (var i = 0; i < 5; i++) {
        final a = i / 5 * 2 * pi - pi / 2;
        canvas.drawCircle(c + Offset(cos(a), sin(a)) * s * 0.6, s * 0.42, fill);
      }
      canvas.drawCircle(c, s * 0.35, Paint()..color = orb.band);
    case Orb.aurora:
      final wave = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.3
        ..strokeCap = StrokeCap.round
        ..color = _ink.withValues(alpha: 0.85);
      for (final dy in [-0.5, 0.0, 0.5]) {
        final p = Path()..moveTo(c.dx - s, c.dy + dy * s);
        p.cubicTo(c.dx - s * 0.4, c.dy + (dy - 0.45) * s, c.dx + s * 0.4, c.dy + (dy + 0.45) * s, c.dx + s,
            c.dy + dy * s);
        canvas.drawPath(p, wave);
      }
    case Orb.crown:
      final p = Path()
        ..moveTo(c.dx - s, c.dy + s * 0.6)
        ..lineTo(c.dx - s, c.dy - s * 0.5)
        ..lineTo(c.dx - s * 0.5, c.dy)
        ..lineTo(c.dx, c.dy - s * 0.9)
        ..lineTo(c.dx + s * 0.5, c.dy)
        ..lineTo(c.dx + s, c.dy - s * 0.5)
        ..lineTo(c.dx + s, c.dy + s * 0.6)
        ..close();
      canvas.drawPath(p, fill);
  }
}

class OrbIcon extends StatelessWidget {
  const OrbIcon(this.orb, {super.key, this.size = 40, this.glow = 0});
  final Orb orb;
  final double size;
  final double glow;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _OrbPainter(orb, glow));
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.orb, this.glow);
  final Orb orb;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) =>
      paintOrb(canvas, size.center(Offset.zero), size.shortestSide / 2 * (glow > 0 ? 0.66 : 0.92), orb, glow: glow);

  @override
  bool shouldRepaint(_OrbPainter old) => old.orb != orb || old.glow != glow;
}
