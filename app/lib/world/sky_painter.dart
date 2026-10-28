import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../core/conditions.dart';
import 'camera.dart';
import 'palette.dart';

/// Sky dome behind the world: gradient, sun or moon at its real arc, clouds
/// that drift and turn with the camera, stars on clear nights.
class SkyPainter extends CustomPainter {
  SkyPainter({
    required this.cam,
    required this.palette,
    required this.conditions,
    required this.time,
  }) : super(repaint: time);

  final WorldCamera cam;
  final Palette palette;
  final Conditions conditions;
  final ValueListenable<double> time;

  static final _stars = List.generate(90, (i) {
    final r = Random(i * 7919);
    return (r.nextDouble(), r.nextDouble(), 0.6 + r.nextDouble() * 1.4, r.nextDouble() * 6);
  });

  static final _clouds = List.generate(12, (i) {
    final r = Random(1000 + i);
    return (r.nextDouble(), 0.15 + r.nextDouble() * 0.75, 0.7 + r.nextDouble() * 0.8, r.nextDouble());
  });

  @override
  void paint(Canvas canvas, Size size) {
    cam.update(size);
    final t = time.value;
    final horizon = cam.horizonY;
    final bottom = max(horizon + 2, 1.0);
    canvas.drawRect(
      Rect.fromLTRB(0, 0, size.width, bottom),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, min(0, horizon - size.height * 0.5)),
          Offset(0, bottom),
          [palette.skyTop, palette.skyHorizon],
        ),
    );
    if (horizon <= 0) return;

    // Stars.
    if (palette.stars > 0.02) {
      final p = Paint();
      for (final (x, y, s, ph) in _stars) {
        final sy = y * horizon * 0.95;
        final sx = ((x - cam.yaw / (2 * pi)) % 1) * size.width;
        final tw = 0.55 + 0.45 * sin(t * 1.7 + ph);
        p.color = Color.fromRGBO(255, 248, 230, palette.stars * tw * (1 - sy / horizon * 0.6));
        canvas.drawCircle(Offset(sx, sy), s, p);
      }
    }

    // Sun or moon, placed by the real day arc: rises east, sets west.
    final arc = conditions.dayArc;
    final isSun = arc >= 0 && arc <= 1;
    final a = isSun ? arc : ((arc < 0 ? arc + 1 : arc - 1) + 1) % 1;
    final south = conditions.latitude < 0;
    final az = (south ? 90 - a * 180 : 90 + a * 180) * pi / 180;
    final peak = (90 - conditions.latitude.abs() + 10).clamp(12, 75);
    final el = sin(a * pi) * peak * pi / 180 + 0.02;
    const far = 1e6;
    final pos = cam.project(
      cam.tx + sin(az) * cos(el) * far,
      cam.ty + cos(az) * cos(el) * far,
      far * tan(el),
    );
    final cover = switch (conditions.sky) {
      Sky.clear => 1.0,
      Sky.partlyCloudy => 0.8,
      Sky.cloudy || Sky.drizzle || Sky.snow => 0.25,
      Sky.fog => 0.15,
      Sky.rain || Sky.storm => 0.0,
    };
    if (pos != null && pos.dy < horizon && cover > 0) {
      if (isSun) {
        canvas.drawCircle(pos, 46, Paint()..color = Color.fromRGBO(255, 230, 160, 0.25 * cover));
        canvas.drawCircle(pos, 22, Paint()..color = Color.fromRGBO(255, 244, 205, cover));
      } else {
        canvas.drawCircle(pos, 30, Paint()..color = Color.fromRGBO(200, 210, 255, 0.12 * cover));
        canvas.drawCircle(pos, 15, Paint()..color = Color.fromRGBO(240, 236, 220, 0.95 * cover));
        canvas.drawCircle(pos + const Offset(6, -4), 13, Paint()..color = palette.skyTop.withValues(alpha: cover));
      }
    }

    // Clouds.
    final count = switch (conditions.sky) {
      Sky.clear => 2,
      Sky.partlyCloudy => 6,
      Sky.fog => 4,
      _ => 12,
    };
    final day = conditions.daylight;
    final base = switch (conditions.sky) {
      Sky.storm => Color.lerp(const Color(0xFF15151F), const Color(0xFF5A5C70), day)!,
      Sky.rain || Sky.drizzle => Color.lerp(const Color(0xFF1C1C2A), const Color(0xFF9096A8), day)!,
      Sky.cloudy || Sky.fog || Sky.snow => Color.lerp(const Color(0xFF24223A), const Color(0xFFC9CED9), day)!,
      _ => Color.lerp(const Color(0xFF2A2650), const Color(0xFFFFFFFF), day)!,
    };
    final drift = t * (0.004 + conditions.windKmh / 6000);
    for (final (x, y, s, _) in _clouds.take(count)) {
      final cx = ((x + drift - cam.yaw / (2 * pi)) % 1.3 - 0.15) * size.width;
      final cy = y * horizon * 0.9;
      final w = 70 * s * (size.width / 400);
      final p = Paint()..color = base.withValues(alpha: 0.8);
      final shade = Paint()..color = Color.lerp(base, const Color(0xFF000000), 0.18)!.withValues(alpha: 0.6);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy + w * 0.12), width: w * 2.2, height: w * 0.5), shade);
      canvas.drawCircle(Offset(cx - w * 0.55, cy), w * 0.38, p);
      canvas.drawCircle(Offset(cx, cy - w * 0.15), w * 0.5, p);
      canvas.drawCircle(Offset(cx + w * 0.55, cy), w * 0.36, p);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy + w * 0.06), width: w * 2, height: w * 0.45), p);
    }
  }

  @override
  bool shouldRepaint(SkyPainter old) => true;
}

/// Weather particles over everything: rain streaks, snow, fog haze, lightning.
class WeatherFxPainter extends CustomPainter {
  WeatherFxPainter({required this.conditions, required this.time}) : super(repaint: time);

  final Conditions conditions;
  final ValueListenable<double> time;

  static final _drops = List.generate(220, (i) {
    final r = Random(i * 31 + 5);
    return (r.nextDouble(), r.nextDouble(), 0.7 + r.nextDouble() * 0.6);
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final sky = conditions.sky;
    final slant = (conditions.windKmh / 40).clamp(0.05, 0.6);

    if (sky == Sky.fog) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [
            const Color(0x99D8DCE6),
            const Color(0x44D8DCE6),
          ]),
      );
    }

    if (sky.wet) {
      final (n, len, speed, alpha) = switch (sky) {
        Sky.drizzle => (70, 10.0, 0.9, 0.35),
        Sky.rain => (150, 18.0, 1.4, 0.45),
        _ => (220, 24.0, 1.9, 0.55),
      };
      final p = Paint()
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..color = Color.fromRGBO(210, 225, 255, alpha);
      for (final (x0, y0, s) in _drops.take(n)) {
        final y = ((y0 + t * speed * s) % 1.1 - 0.05) * size.height;
        final x = ((x0 + y / size.height * slant * 0.3) % 1) * size.width;
        canvas.drawLine(Offset(x, y), Offset(x - slant * len, y - len * s), p);
      }
    }

    if (sky == Sky.snow) {
      final p = Paint()..color = const Color(0xDDFFFFFF);
      for (final (x0, y0, s) in _drops.take(120)) {
        final y = ((y0 + t * 0.12 * s) % 1.05) * size.height;
        final x = ((x0 + sin(t * 0.8 + y0 * 20) * 0.015 + y / size.height * slant * 0.1) % 1) * size.width;
        canvas.drawCircle(Offset(x, y), 1.6 + s * 1.6, p);
      }
    }

    if (sky == Sky.storm) {
      // A flash every 5-11 s, seeded per cycle so it feels irregular.
      final cycle = (t / 8).floor();
      final r = Random(cycle);
      final at = r.nextDouble() * 5;
      final since = t - cycle * 8 - at;
      if (since >= 0 && since < 0.5) {
        final double flash = since < 0.08 ? 0.55 : (since < 0.16 ? 0.15 : (since < 0.24 ? 0.4 : 0.4 * (1 - (since - 0.24) / 0.26)));
        canvas.drawRect(Offset.zero & size, Paint()..color = Color.fromRGBO(235, 240, 255, flash.clamp(0, 1)));
        if (since < 0.24) {
          final bolt = Path();
          var x = size.width * (0.2 + r.nextDouble() * 0.6);
          var y = 0.0;
          bolt.moveTo(x, y);
          while (y < size.height * 0.3) {
            x += (r.nextDouble() - 0.5) * 40;
            y += 18 + r.nextDouble() * 22;
            bolt.lineTo(x, y);
          }
          canvas.drawPath(
            bolt,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = const Color(0xFFF4F0FF),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(WeatherFxPainter old) => true;
}
