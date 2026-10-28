import 'dart:math';

import 'package:latlong2/latlong.dart';

/// Territory hexes, ~150 m across, covering the whole globe.
///
/// The id of the hex containing a point is pure integer maths so the backend
/// (backend/lib/hexgrid.ts) reproduces it bit for bit before signing it; the
/// contract only ever sees signed ids. Coordinates are micro-degrees.
///
/// The globe is cut into 1°-wide longitude strips. Each strip holds its own
/// pointy-top axial grid over (x, y) = ((lng - strip west edge) x cos(lat),
/// lat): the cos keeps hexes ~150 m at every latitude, and measuring from the
/// strip's own edge keeps the shear that cos introduces under a metre. Hexes
/// on a strip seam are cut in two, each half its own hex.
class HexGrid {
  /// Circumradius in micro-degrees of latitude (~87 m), so ~150 m flat to flat.
  static const size = 780;
  static const strip = 1000000; // 1° of longitude
  static const _fp = 1000000;

  /// Id of the hex containing ([latE6], [lngE6]).
  static int idAtE6(int latE6, int lngE6) {
    final cell = _floorDiv(lngE6, strip);
    final x = (lngE6 - cell * strip) * cosE6(latE6) ~/ _fp;
    final y = latE6;
    final qf = (577350 * x - 333333 * y) ~/ size; // sqrt(3)/3, 1/3 in 1e6 fixed point
    final rf = 666667 * y ~/ size; // 2/3
    final sf = -qf - rf;
    var q = _roundFp(qf), r = _roundFp(rf);
    final s = _roundFp(sf);
    final dq = (q * _fp - qf).abs(), dr = (r * _fp - rf).abs(), ds = (s * _fp - sf).abs();
    if (dq > dr && dq > ds) {
      q = -r - s;
    } else if (dr > ds) {
      r = -q - s;
    }
    return idOf(cell, q, r);
  }

  static int idAt(LatLng p) => idAtE6((p.latitude * 1e6).round(), (p.longitude * 1e6).round());

  /// Packs (strip, q, r) as the contract's uint64:
  /// (strip + 2^15) << 48 | (q + 2^23) << 24 | (r + 2^23).
  /// Dart ints are 64-bit, so ids above 2^63 read as negative; [toUint64]
  /// gives the unsigned value for ABI encoding and JSON.
  static int idOf(int cell, int q, int r) =>
      ((cell + 0x8000) << 48) | (((q + 0x800000) & 0xffffff) << 24) | ((r + 0x800000) & 0xffffff);

  static (int, int, int) unpack(int id) =>
      (((id >>> 48) & 0xffff) - 0x8000, ((id >>> 24) & 0xffffff) - 0x800000, (id & 0xffffff) - 0x800000);

  static BigInt toUint64(int id) => BigInt.from(id).toUnsigned(64);
  static int fromUint64(BigInt v) => v.toSigned(64).toInt();

  /// cos(latitude) in 1e6 fixed point: Taylor series to x^12, clamped to
  /// +-85 degrees. Every division truncates toward zero, like BigInt in TS.
  static int cosE6(int latE6) {
    final lat = latE6.clamp(-85000000, 85000000);
    final rad = lat * 17453293 ~/ 1000000000; // pi/180 in 1e9
    final x2 = rad * rad ~/ _fp;
    var term = _fp, c = _fp;
    for (var k = 1; k <= 6; k++) {
      term = -((term * x2 ~/ _fp) ~/ ((2 * k - 1) * (2 * k)));
      c += term;
    }
    return c;
  }

  static int _roundFp(int v) => _floorDiv(v + _fp ~/ 2, _fp);
  static int _floorDiv(int a, int b) => (a - a % b) ~/ b; // Dart's % is never negative for b > 0

  /// Centre of a hex's full (unclipped) shape, for drawing.
  static LatLng center(int id) {
    final (cell, q, r) = unpack(id);
    return _toLatLng(cell, size * sqrt(3) * (q + r / 2), size * 1.5 * r);
  }

  /// Corners of a hex for drawing, clipped to its strip so seam halves don't
  /// overlap. Each corner uses its own latitude's cos, matching [idAtE6].
  static List<LatLng> corners(int id) {
    final (cell, q, r) = unpack(id);
    final cy = size * 1.5 * r;
    final cx = size * sqrt(3) * (q + r / 2);
    final pts = [
      for (var k = 0; k < 6; k++)
        _toLatLng(cell, cx + size * cos(pi / 180 * (30 + 60 * k)), cy + size * sin(pi / 180 * (30 + 60 * k))),
    ];
    final west = cell.toDouble(), east = cell + 1.0;
    if (pts.every((p) => p.longitude >= west && p.longitude <= east)) return pts;
    return _clip(_clip(pts, west, keepEast: true), east, keepEast: false);
  }

  /// Sutherland-Hodgman against the meridian [lng].
  static List<LatLng> _clip(List<LatLng> poly, double lng, {required bool keepEast}) {
    bool inside(LatLng p) => keepEast ? p.longitude >= lng : p.longitude <= lng;
    final out = <LatLng>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      if (inside(a)) out.add(a);
      if (inside(a) != inside(b)) {
        final t = (lng - a.longitude) / (b.longitude - a.longitude);
        out.add(LatLng(a.latitude + (b.latitude - a.latitude) * t, lng));
      }
    }
    return out;
  }

  static LatLng _toLatLng(int cell, double x, double y) {
    final lat = y / 1e6;
    final c = cos(lat.clamp(-85.0, 85.0) * pi / 180);
    return LatLng(lat, cell + x / c / 1e6);
  }

  /// Every hex within [metres] of [p], found by sampling (works across strip
  /// seams, where the two grids don't line up).
  static List<int> around(LatLng p, double metres) {
    final ids = <int>{};
    final stepLat = 300 / 1e6; // ~33 m, well under a hex's inradius
    final stepLng = stepLat / max(0.05, cos(p.latitude * pi / 180));
    final n = (metres / 33).ceil();
    for (var i = -n; i <= n; i++) {
      for (var j = -n; j <= n; j++) {
        if (i * i + j * j > n * n) continue;
        ids.add(idAt(LatLng(p.latitude + i * stepLat, p.longitude + j * stepLng)));
      }
    }
    return ids.toList();
  }

  /// Landmark zone id for the spawn engine's zone (row, col), as the contract's
  /// uint64: (row + 2^31) << 32 | (col + 2^31). Matches backend zoneOf.
  static int zoneOf(int row, int col) => ((row + (1 << 31)) << 32) | ((col + (1 << 31)) & 0xffffffff);

  /// Zone of a Landmark spawn id (`L<row>:<col>:<day>`), or null.
  static int? zoneOfSpawn(String spawnId) {
    if (!spawnId.startsWith('L')) return null;
    final p = spawnId.substring(1).split(':');
    if (p.length != 3) return null;
    final row = int.tryParse(p[0]), col = int.tryParse(p[1]);
    return row == null || col == null ? null : zoneOf(row, col);
  }
}
