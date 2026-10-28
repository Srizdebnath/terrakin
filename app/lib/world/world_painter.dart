import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';

import 'camera.dart';
import 'palette.dart';
import 'world_data.dart';

/// Draws the ground, roads, water, trees and extruded buildings in perspective.
/// Ground layers are batched into one path per colour; buildings and trees are
/// depth-sorted and drawn back to front.
class WorldPainter extends CustomPainter {
  WorldPainter({
    required this.tiles,
    required this.cam,
    required this.palette,
    required this.player,
    required this.reach,
    required this.ringColor,
    this.hexes,
    super.repaint,
  });

  /// Read on every paint, so repaints between rebuilds see fresh data.
  final List<WorldTile> Function() tiles;
  final (double, double) Function() player;
  final WorldCamera cam;
  final Palette palette;
  final double reach;
  final Color ringColor;

  /// Territory hexes on the ground: corners in local metres (x, y pairs),
  /// fill and outline. Read on every paint.
  final List<(Float32List, Color, Color, double)> Function()? hexes;

  static const _buildingRadius = 360.0;
  static const _treeRadius = 280.0;

  // Scratch buffers for near-plane clipping, reused across rings.
  static var _vx = Float64List(256), _vy = Float64List(256), _vz = Float64List(256);

  @override
  void paint(Canvas canvas, Size size) {
    cam.update(size);
    final tiles = this.tiles();
    final (playerX, playerY) = player();
    final horizon = cam.horizonY;
    final reachR = cam.groundReach + 150;

    // 1. Base land below the horizon.
    canvas.drawRect(
      Rect.fromLTRB(0, max(horizon, 0), size.width, size.height),
      Paint()..color = palette.land,
    );

    // 2. Ground fills and water.
    for (final g in Ground.values) {
      final path = Path();
      var any = false;
      for (final t in tiles) {
        for (final s in t.ground[g] ?? const <Shape>[]) {
          if (!_visible(s, reachR)) continue;
          for (final r in s.rings) {
            any = _addRing(path, r, 0) || any;
          }
        }
      }
      if (!any) continue;
      canvas.drawPath(path, Paint()..color = palette.ground[g]!);
      if (g == Ground.water) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = palette.waterEdge.withValues(alpha: 0.7),
        );
      }
    }

    // 3. Roads, smallest class first so big roads sit on top at junctions.
    for (final rc in Road.values) {
      final path = Path();
      var any = false;
      for (final t in tiles) {
        for (final s in t.roads[rc] ?? const <Shape>[]) {
          if (!_visible(s, reachR)) continue;
          for (final r in s.rings) {
            any = _addRing(path, r, 0) || any;
          }
        }
      }
      if (any) canvas.drawPath(path, Paint()..color = palette.roads[rc]!);
    }

    // 4. Territory hexes, over the roads and under the reach ring.
    for (final (pts, fill, stroke, width) in hexes?.call() ?? const <(Float32List, Color, Color, double)>[]) {
      final path = Path();
      if (!_addRing(path, pts, 0.1)) continue;
      if (fill.a > 0) canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round
          ..color = stroke,
      );
    }

    // 5. Bond-reach ring on the ground.
    final ring = Path();
    const steps = 48;
    final pts = Float32List(steps * 2);
    for (var i = 0; i < steps; i++) {
      final a = i / steps * 2 * pi;
      pts[i * 2] = playerX + cos(a) * reach;
      pts[i * 2 + 1] = playerY + sin(a) * reach;
    }
    if (_addRing(ring, pts, 0.2)) {
      canvas.drawPath(ring, Paint()..color = ringColor.withValues(alpha: 0.12));
      canvas.drawPath(
        ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = ringColor.withValues(alpha: 0.65),
      );
    }

    // 6. Trees and buildings, back to front.
    final items = <(double, int, int, int)>[]; // depth, kind (0 tree, 1 building), tile, index
    for (final (ti, t) in tiles.indexed) {
      final tr = t.trees;
      for (var i = 0; i < tr.length; i += 3) {
        final dx = tr[i] - cam.tx, dy = tr[i + 1] - cam.ty;
        if (dx * dx + dy * dy > _treeRadius * _treeRadius) continue;
        final d = cam.depthOf(tr[i], tr[i + 1]);
        if (d < WorldCamera.near + 4) continue;
        items.add((d, 0, ti, i));
      }
      for (final (bi, b) in t.buildings.indexed) {
        final dx = b.cx - cam.tx, dy = b.cy - cam.ty;
        if (sqrt(dx * dx + dy * dy) - b.radius > _buildingRadius) continue;
        final d = cam.depthOf(b.cx, b.cy);
        if (d - b.radius < WorldCamera.near) continue;
        items.add((d, 1, ti, bi));
      }
    }
    items.sort((a, b) => b.$1.compareTo(a.$1));
    for (final (_, kind, ti, i) in items) {
      if (kind == 0) {
        _tree(canvas, tiles[ti].trees, i);
      } else {
        _building(canvas, tiles[ti].buildings[i]);
      }
    }

    // 6. Distance fog into the horizon colour.
    final fogFar = max(horizon, 0.0);
    final fogNear = _screenYAtDistance(reachR * 0.55);
    if (fogNear > fogFar + 1) {
      canvas.drawRect(
        Rect.fromLTRB(0, fogFar, size.width, fogNear),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, fogFar),
            Offset(0, fogNear),
            [palette.skyHorizon, palette.skyHorizon.withValues(alpha: 0)],
          ),
      );
    }
  }

  double _screenYAtDistance(double d) {
    final p = cam.project(cam.tx + sin(cam.yaw) * d, cam.ty + cos(cam.yaw) * d);
    return p?.dy ?? cam.size.height;
  }

  bool _visible(Shape s, double reachR) {
    final dx = s.cx - cam.tx, dy = s.cy - cam.ty;
    final d = sqrt(dx * dx + dy * dy) - s.radius;
    if (d > reachR) return false;
    // Entirely behind the camera?
    return cam.depthOf(s.cx, s.cy) + s.radius > WorldCamera.near;
  }

  /// Projects a ring at height [z] into [path], clipping against the near plane.
  bool _addRing(Path path, Float32List r, double z) {
    final n = r.length ~/ 2;
    if (n < 3) return false;
    if (_vx.length < n * 2 + 4) {
      _vx = Float64List(n * 2 + 4);
      _vy = Float64List(n * 2 + 4);
      _vz = Float64List(n * 2 + 4);
    }
    var front = 0;
    for (var i = 0; i < n; i++) {
      cam.view(r[i * 2], r[i * 2 + 1], z);
      _vx[i] = cam.vx;
      _vy[i] = cam.vy;
      _vz[i] = cam.vz;
      if (cam.vz >= WorldCamera.near) front++;
    }
    if (front == 0) return false;
    var started = false;
    void emit(double x, double y, double zz) {
      final sx = cam.sx(x, zz), sy = cam.sy(y, zz);
      if (started) {
        path.lineTo(sx, sy);
      } else {
        path.moveTo(sx, sy);
        started = true;
      }
    }

    if (front == n) {
      for (var i = 0; i < n; i++) {
        emit(_vx[i], _vy[i], _vz[i]);
      }
    } else {
      const zn = WorldCamera.near;
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        final ai = _vz[i] >= zn, aj = _vz[j] >= zn;
        if (ai) emit(_vx[i], _vy[i], _vz[i]);
        if (ai != aj) {
          final t = (zn - _vz[i]) / (_vz[j] - _vz[i]);
          emit(_vx[i] + (_vx[j] - _vx[i]) * t, _vy[i] + (_vy[j] - _vy[i]) * t, zn);
        }
      }
    }
    if (started) path.close();
    return started;
  }

  void _building(Canvas canvas, Shape b) {
    final r = b.rings.first;
    final n = r.length ~/ 2;
    final lit = Path(), mid = Path(), dark = Path();
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final ax = r[i * 2], ay = r[i * 2 + 1], bx = r[j * 2], by = r[j * 2 + 1];
      final nx = by - ay, ny = -(bx - ax);
      // Back-face cull: only walls whose outward normal faces the camera.
      if ((cam.camX - ax) * nx + (cam.camY - ay) * ny <= 0) continue;
      final len = sqrt(nx * nx + ny * ny);
      if (len < 0.05) continue;
      final light = (nx * 0.55 + ny * 0.83) / len; // sun from the north-north-east
      final p = light > 0.35 ? lit : (light > -0.35 ? mid : dark);
      final a0 = cam.project(ax, ay, b.minHeight), b0 = cam.project(bx, by, b.minHeight);
      final b1 = cam.project(bx, by, b.height), a1 = cam.project(ax, ay, b.height);
      if (a0 == null || b0 == null || b1 == null || a1 == null) continue;
      p
        ..moveTo(a0.dx, a0.dy)
        ..lineTo(b0.dx, b0.dy)
        ..lineTo(b1.dx, b1.dy)
        ..lineTo(a1.dx, a1.dy)
        ..close();
    }
    canvas.drawPath(dark, Paint()..color = palette.wallDark);
    canvas.drawPath(mid, Paint()..color = Color.lerp(palette.wallDark, palette.wallLight, 0.5)!);
    canvas.drawPath(lit, Paint()..color = palette.wallLight);
    final roof = Path();
    if (_addRing(roof, r, b.height)) {
      canvas.drawPath(roof, Paint()..color = palette.roof);
      canvas.drawPath(
        roof,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeJoin = StrokeJoin.round
          ..color = palette.edge.withValues(alpha: 0.8),
      );
    }
  }

  void _tree(Canvas canvas, Float32List t, int i) {
    final x = t[i], y = t[i + 1], s = t[i + 2];
    final h = 9.0 * s, crownR = 4.2 * s;
    final base = cam.project(x, y, 0);
    final top = cam.project(x, y, h);
    if (base == null || top == null) return;
    final px = cam.scaleAt(cam.depthOf(x, y, h));
    final r = crownR * px;
    if (r < 0.8) return;
    canvas.drawOval(
      Rect.fromCenter(center: base, width: r * 1.8, height: r * 0.7),
      Paint()..color = const Color(0x22000000),
    );
    canvas.drawLine(
      base,
      top,
      Paint()
        ..color = palette.trunk
        ..strokeWidth = max(1.0, r * 0.28)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(top, r, Paint()..color = palette.crown);
    canvas.drawCircle(top + Offset(-r * 0.25, -r * 0.28), r * 0.6, Paint()..color = palette.crownLight);
    if (r > 4) {
      canvas.drawCircle(
        top,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.0, r * 0.08)
          ..color = palette.edge.withValues(alpha: 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(WorldPainter old) => true;
}
