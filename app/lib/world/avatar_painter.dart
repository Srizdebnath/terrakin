import 'dart:math';

import 'package:flutter/rendering.dart';

import '../core/avatars.dart';

const _ink = Color(0xFF231A2E);

/// Chibi player character in the Kin art style: thick ink outline, flat
/// shading, big head. Drawn in a 100 x 140 box (feet at y = 134) and scaled.
class AvatarPainter extends CustomPainter {
  AvatarPainter({
    required this.style,
    this.phase = 0,
    this.moving = false,
    this.back = false,
    this.look = 0,
  });

  final AvatarStyle style;

  /// Walk cycle angle in radians.
  final double phase;
  final bool moving;

  /// Walking away from the camera.
  final bool back;

  /// -1 looks left, 1 looks right.
  final double look;

  @override
  void paint(Canvas canvas, Size size) {
    final k = min(size.width / 100, size.height / 140);
    canvas.translate((size.width - 100 * k) / 2, size.height - 140 * k);
    canvas.scale(k);

    final swing = moving ? sin(phase) : 0.0;
    final bob = moving ? (cos(phase * 2) * 2.2).abs() : 0.0;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = _ink;
    void fill(Path p, Color c) {
      canvas.drawPath(p, Paint()..color = c);
      canvas.drawPath(p, outline);
    }

    // Ground shadow.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 134), width: 46 - bob * 2, height: 10),
      Paint()..color = _ink.withValues(alpha: 0.22),
    );

    canvas.save();
    canvas.translate(0, -bob);

    // Legs (pivot at the hip) with shoes.
    void leg(double hipX, double angle) {
      canvas.save();
      canvas.translate(hipX, 100);
      canvas.rotate(angle);
      fill(Path()..addRRect(RRect.fromLTRBR(-6.5, -4, 6.5, 26, const Radius.circular(6))), style.bottom);
      fill(Path()..addOval(Rect.fromCenter(center: const Offset(0, 28), width: 16, height: 10)), style.accent);
      canvas.restore();
    }

    leg(42, swing * 0.45);
    leg(58, -swing * 0.45);

    // Arms behind the body when walking away.
    void arm(double shoulderX, double angle, bool left) {
      canvas.save();
      canvas.translate(shoulderX, 74);
      canvas.rotate(angle + (left ? 0.22 : -0.22));
      fill(Path()..addRRect(RRect.fromLTRBR(-5, -3, 5, 22, const Radius.circular(5))), style.top);
      fill(Path()..addOval(Rect.fromCenter(center: const Offset(0, 24), width: 10, height: 10)), style.skin);
      canvas.restore();
    }

    if (back) {
      arm(31, -swing * 0.55, true);
      arm(69, swing * 0.55, false);
    }

    // Body.
    final body = Path()..addRRect(RRect.fromLTRBR(30, 66, 70, 106, const Radius.circular(13)));
    fill(body, style.top);
    if (back) {
      // Explorer's satchel.
      fill(Path()..addRRect(RRect.fromLTRBR(36, 72, 64, 98, const Radius.circular(7))), style.accent);
      canvas.drawLine(const Offset(40, 80), const Offset(60, 80), outline..strokeWidth = 2.4);
      outline.strokeWidth = 3.4;
    } else {
      canvas.drawLine(const Offset(50, 70), const Offset(50, 104), outline..strokeWidth = 2);
      outline.strokeWidth = 3.4;
      fill(Path()..addOval(Rect.fromCircle(center: const Offset(58, 82), radius: 4)), style.accent);
    }

    if (!back) {
      arm(31, -swing * 0.55, true);
      arm(69, swing * 0.55, false);
    }

    // Head.
    final head = Path()..addOval(Rect.fromCircle(center: const Offset(50, 42), radius: 27));
    if (style.hair == Hair.hood) {
      fill(Path()..addOval(Rect.fromCircle(center: const Offset(50, 41), radius: 33)), style.top);
    }
    if (back) {
      fill(head, style.hairColor);
      _hairBack(canvas, fill);
    } else {
      fill(head, style.skin);
      _face(canvas);
      _hairFront(canvas, fill);
    }

    canvas.restore();
  }

  void _face(Canvas canvas) {
    final dx = look * 5;
    final eye = Paint()..color = _ink;
    for (final x in [39.0, 61.0]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(x + dx, 46), width: 7, height: 9.5), eye);
      canvas.drawCircle(Offset(x + dx - 1.4, 43.6), 1.6, Paint()..color = const Color(0xFFFFFFFF));
    }
    final blush = Paint()..color = const Color(0xFFFF8A8A).withValues(alpha: 0.45);
    canvas.drawOval(Rect.fromCenter(center: Offset(32 + dx, 54), width: 9, height: 5), blush);
    canvas.drawOval(Rect.fromCenter(center: Offset(68 + dx, 54), width: 9, height: 5), blush);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(50 + dx, 54), width: 8, height: 6),
      0.2,
      pi - 0.4,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = _ink,
    );
  }

  void _hairFront(Canvas canvas, void Function(Path, Color) fill) {
    final c = style.hairColor;
    switch (style.hair) {
      case Hair.spiky:
        fill(
          Path()
            ..moveTo(22, 42)
            ..lineTo(20, 22)
            ..lineTo(32, 26)
            ..lineTo(34, 10)
            ..lineTo(46, 20)
            ..lineTo(54, 6)
            ..lineTo(60, 20)
            ..lineTo(72, 12)
            ..lineTo(70, 26)
            ..lineTo(82, 24)
            ..lineTo(77, 40)
            ..quadraticBezierTo(64, 28, 50, 32)
            ..quadraticBezierTo(34, 28, 22, 42)
            ..close(),
          c,
        );
      case Hair.bob:
        fill(
          Path()
            ..moveTo(22, 58)
            ..quadraticBezierTo(14, 16, 50, 12)
            ..quadraticBezierTo(86, 16, 78, 58)
            ..lineTo(70, 58)
            ..quadraticBezierTo(72, 36, 60, 30)
            ..quadraticBezierTo(48, 38, 30, 34)
            ..quadraticBezierTo(28, 46, 30, 58)
            ..close(),
          c,
        );
      case Hair.cap:
        fill(
          Path()
            ..moveTo(22, 36)
            ..quadraticBezierTo(24, 12, 50, 12)
            ..quadraticBezierTo(76, 12, 78, 36)
            ..close(),
          style.accent,
        );
        fill(
          Path()
            ..moveTo(18, 36)
            ..quadraticBezierTo(50, 28, 84, 36)
            ..quadraticBezierTo(50, 44, 18, 36)
            ..close(),
          style.accent,
        );
        fill(Path()..addOval(Rect.fromCircle(center: const Offset(50, 22), radius: 5)), style.top);
      case Hair.bun:
        fill(Path()..addOval(Rect.fromCircle(center: const Offset(50, 10), radius: 10)), c);
        fill(
          Path()
            ..moveTo(23, 40)
            ..quadraticBezierTo(24, 15, 50, 15)
            ..quadraticBezierTo(76, 15, 77, 40)
            ..quadraticBezierTo(66, 26, 52, 30)
            ..quadraticBezierTo(36, 24, 23, 40)
            ..close(),
          c,
        );
      case Hair.curly:
        for (final (x, y, r) in const [
          (28.0, 30.0, 9.0), (38.0, 20.0, 10.0), (50.0, 16.0, 10.0), (62.0, 20.0, 10.0), (72.0, 30.0, 9.0),
          (24.0, 42.0, 7.0), (76.0, 42.0, 7.0),
        ]) {
          fill(Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r)), c);
        }
      case Hair.hood:
        fill(
          Path()
            ..moveTo(20, 40)
            ..quadraticBezierTo(22, 14, 50, 13)
            ..quadraticBezierTo(78, 14, 80, 40)
            ..quadraticBezierTo(66, 24, 50, 26)
            ..quadraticBezierTo(34, 24, 20, 40)
            ..close(),
          style.top,
        );
        // Little ear tufts on the hood.
        fill(Path()..addPolygon(const [Offset(26, 22), Offset(24, 6), Offset(36, 15)], true), style.accent);
        fill(Path()..addPolygon(const [Offset(74, 22), Offset(76, 6), Offset(64, 15)], true), style.accent);
    }
  }

  void _hairBack(Canvas canvas, void Function(Path, Color) fill) {
    switch (style.hair) {
      case Hair.cap:
        fill(
          Path()
            ..moveTo(22, 36)
            ..quadraticBezierTo(24, 12, 50, 12)
            ..quadraticBezierTo(76, 12, 78, 36)
            ..close(),
          style.accent,
        );
      case Hair.bun:
        fill(Path()..addOval(Rect.fromCircle(center: const Offset(50, 10), radius: 10)), style.hairColor);
      case Hair.hood:
        fill(Path()..addOval(Rect.fromCircle(center: const Offset(50, 42), radius: 27)), style.top);
        fill(Path()..addPolygon(const [Offset(26, 22), Offset(24, 6), Offset(36, 15)], true), style.accent);
        fill(Path()..addPolygon(const [Offset(74, 22), Offset(76, 6), Offset(64, 15)], true), style.accent);
      case Hair.bob:
        fill(
          Path()
            ..moveTo(22, 58)
            ..quadraticBezierTo(14, 16, 50, 12)
            ..quadraticBezierTo(86, 16, 78, 58)
            ..close(),
          style.hairColor,
        );
      case Hair.spiky:
      case Hair.curly:
        break;
    }
  }

  @override
  bool shouldRepaint(AvatarPainter old) =>
      old.phase != phase || old.moving != moving || old.back != back || old.look != look || old.style != style;
}
