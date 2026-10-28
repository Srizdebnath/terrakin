import 'dart:math';
import 'dart:typed_data';

import 'mvt.dart';

/// Flat local frame in metres around an origin (x east, y north). Accurate to
/// well under a metre across the few kilometres the world renderer keeps loaded.
class GeoFrame {
  GeoFrame(this.lat0, this.lng0)
      : mLat = 110574.0,
        mLng = 111320.0 * cos(lat0 * pi / 180);
  final double lat0, lng0, mLat, mLng;

  double x(double lng) {
    var d = lng - lng0;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d * mLng;
  }
  double y(double lat) => (lat - lat0) * mLat;
  double lat(double y) => lat0 + y / mLat;
  double lng(double x) {
    final v = lng0 + x / mLng;
    return v > 180 ? v - 360 : (v < -180 ? v + 360 : v);
  }
}

/// Web-mercator tile helpers (OpenMapTiles is cut at z14).
class TileId {
  const TileId(this.x, this.y, [this.z = 14]);
  final int x, y, z;

  static TileId at(double lat, double lng, [int z = 14]) {
    final n = 1 << z;
    final x = ((lng + 180) / 360 * n).floor() % n;
    final r = lat * pi / 180;
    final y = ((1 - log(tan(r) + 1 / cos(r)) / pi) / 2 * n).floor().clamp(0, n - 1);
    return TileId(x, y, z);
  }

  static double lngOf(double tx, int z) => tx / (1 << z) * 360 - 180;
  static double latOf(double ty, int z) {
    final n = pi * (1 - 2 * ty / (1 << z));
    return atan((exp(n) - exp(-n)) / 2) * 180 / pi;
  }

  String get key => '${z}_${x}_$y';

  @override
  bool operator ==(Object other) => other is TileId && other.x == x && other.y == y && other.z == z;
  @override
  int get hashCode => Object.hash(x, y, z);
}

/// Ground fills in draw order (later ones paint over earlier ones).
enum Ground { residential, urban, farmland, grass, park, wood, wetland, sand, pitch, water }

enum Road { rail, path, minor, medium, major }

enum Habitat { land, green, water }

class Shape {
  Shape(this.rings, {this.height = 0, this.minHeight = 0}) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final r in rings) {
      for (var i = 0; i < r.length; i += 2) {
        minX = min(minX, r[i]);
        maxX = max(maxX, r[i]);
        minY = min(minY, r[i + 1]);
        maxY = max(maxY, r[i + 1]);
      }
    }
    cx = (minX + maxX) / 2;
    cy = (minY + maxY) / 2;
    radius = sqrt(pow(maxX - minX, 2) + pow(maxY - minY, 2)) / 2;
    this.minX = minX;
    this.maxX = maxX;
    this.minY = minY;
    this.maxY = maxY;
  }

  /// Local-metre rings, x/y interleaved.
  final List<Float32List> rings;
  final double height;
  final double minHeight;
  late final double cx, cy, radius, minX, maxX, minY, maxY;

  bool contains(double x, double y) {
    if (x < minX || x > maxX || y < minY || y > maxY) return false;
    var inside = false;
    for (final r in rings) {
      final n = r.length ~/ 2;
      for (var i = 0, j = n - 1; i < n; j = i++) {
        final xi = r[i * 2], yi = r[i * 2 + 1], xj = r[j * 2], yj = r[j * 2 + 1];
        if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
      }
    }
    return inside;
  }
}

class WorldTile {
  WorldTile(this.id, this.ground, this.roads, this.buildings, this.trees);
  final TileId id;
  final Map<Ground, List<Shape>> ground;

  /// Each road line is pre-expanded into overlapping quads (one ring each).
  final Map<Road, List<Shape>> roads;
  final List<Shape> buildings;

  /// x, y, scale triples.
  final Float32List trees;

  Habitat habitatAt(double x, double y) {
    for (final s in ground[Ground.water] ?? const <Shape>[]) {
      if (s.contains(x, y)) return Habitat.water;
    }
    for (final g in const [Ground.park, Ground.wood, Ground.grass, Ground.wetland]) {
      for (final s in ground[g] ?? const <Shape>[]) {
        if (s.contains(x, y)) return Habitat.green;
      }
    }
    return Habitat.land;
  }
}

const _layers = {'water', 'waterway', 'landcover', 'landuse', 'park', 'transportation', 'building'};

/// Decodes one z14 OpenMapTiles tile into local-metre geometry. Pure, so it
/// runs inside `Isolate.run`.
WorldTile buildTile(Uint8List bytes, TileId id, double lat0, double lng0) {
  final frame = GeoFrame(lat0, lng0);
  final layers = decodeMvt(bytes, only: _layers);
  final ground = <Ground, List<Shape>>{};
  final roads = <Road, List<Shape>>{};
  final buildings = <Shape>[];

  List<Float32List> toLocal(MvtFeature f, int extent) => [
        for (final ring in f.rings)
          Float32List.fromList([
            for (var i = 0; i < ring.length; i += 2) ...[
              frame.x(TileId.lngOf(id.x + ring[i] / extent, id.z)),
              frame.y(TileId.latOf(id.y + ring[i + 1] / extent, id.z)),
            ],
          ]),
      ];

  void addGround(Ground g, MvtFeature f, int extent) {
    if (f.type != 3) return;
    (ground[g] ??= []).add(Shape(toLocal(f, extent)));
  }

  void addLine(Map<Road, List<Shape>> into, Road key, MvtFeature f, int extent, double width) {
    for (final line in toLocal(f, extent)) {
      final quads = _expand(line, width / 2);
      if (quads.isNotEmpty) (into[key] ??= []).add(Shape(quads));
    }
  }

  for (final f in layers['landcover']?.features ?? const <MvtFeature>[]) {
    final g = switch ((f.tags['class'], f.tags['subclass'])) {
      (_, 'park' || 'garden' || 'village_green' || 'recreation_ground') => Ground.park,
      ('wood', _) => Ground.wood,
      ('grass', _) => Ground.grass,
      ('farmland', _) => Ground.farmland,
      ('wetland', _) => Ground.wetland,
      ('sand' || 'rock' || 'ice', _) => Ground.sand,
      _ => null,
    };
    if (g != null) addGround(g, f, layers['landcover']!.extent);
  }
  for (final f in layers['landuse']?.features ?? const <MvtFeature>[]) {
    final g = switch (f.tags['class']) {
      'residential' || 'suburb' || 'neighbourhood' || 'quarter' => Ground.residential,
      'commercial' || 'retail' || 'industrial' || 'railway' || 'garages' || 'bus_station' =>
        Ground.urban,
      'school' || 'university' || 'college' || 'kindergarten' || 'hospital' => Ground.urban,
      'pitch' || 'stadium' || 'playground' || 'track' => Ground.pitch,
      'cemetery' => Ground.grass,
      _ => null,
    };
    if (g != null) addGround(g, f, layers['landuse']!.extent);
  }
  for (final f in layers['park']?.features ?? const <MvtFeature>[]) {
    addGround(Ground.park, f, layers['park']!.extent);
  }
  for (final f in layers['water']?.features ?? const <MvtFeature>[]) {
    if (f.tags['brunnel'] == 'tunnel') continue;
    addGround(Ground.water, f, layers['water']!.extent);
  }
  final waterways = layers['waterway'];
  for (final f in waterways?.features ?? const <MvtFeature>[]) {
    if (f.type != 2 || f.tags['brunnel'] == 'tunnel') continue;
    final w = switch (f.tags['class']) {
      'river' => 16.0,
      'canal' => 9.0,
      'stream' => 4.0,
      _ => 2.5,
    };
    for (final line in toLocal(f, waterways!.extent)) {
      final quads = _expand(line, w / 2);
      if (quads.isNotEmpty) (ground[Ground.water] ??= []).add(Shape(quads));
    }
  }
  final transport = layers['transportation'];
  for (final f in transport?.features ?? const <MvtFeature>[]) {
    if (f.tags['brunnel'] == 'tunnel') continue;
    final cls = f.tags['class'];
    if (f.type == 3) {
      final ext = transport!.extent;
      (roads[Road.minor] ??= []).add(Shape(toLocal(f, ext)));
      continue;
    }
    if (f.type != 2) continue;
    final (Road key, double width) = switch (cls) {
      'motorway' || 'trunk' || 'primary' => (Road.major, 15.0),
      'secondary' || 'tertiary' => (Road.medium, 11.0),
      'minor' || 'raceway' || 'busway' => (Road.minor, 7.5),
      'service' => (Road.minor, 5.0),
      'track' || 'path' => (Road.path, 3.0),
      'rail' || 'transit' => (Road.rail, 3.5),
      _ => (Road.path, 0.0),
    };
    if (width == 0) continue;
    addLine(roads, key, f, transport!.extent, width);
  }
  final bl = layers['building'];
  for (final f in bl?.features ?? const <MvtFeature>[]) {
    if (f.type != 3) continue;
    final h = ((f.tags['render_height'] as num?)?.toDouble() ?? 6).clamp(3.0, 250.0);
    final mh = ((f.tags['render_min_height'] as num?)?.toDouble() ?? 0).clamp(0.0, h - 1);
    for (final ring in toLocal(f, bl!.extent)) {
      if (ring.length < 6) continue;
      final a = _signedArea(ring);
      // Exterior rings come out clockwise once the tile's y axis is flipped;
      // keep only those and store them counter-clockwise so wall normals face out.
      if (a >= 0) continue;
      buildings.add(Shape([_reversed(ring)], height: h, minHeight: mh));
    }
  }

  final x0 = frame.x(TileId.lngOf(id.x.toDouble(), id.z)), x1 = frame.x(TileId.lngOf(id.x + 1.0, id.z));
  final y0 = frame.y(TileId.latOf(id.y + 1.0, id.z)), y1 = frame.y(TileId.latOf(id.y.toDouble(), id.z));
  final trees = _scatterTrees(ground, roads, buildings, x0, y0, x1, y1);
  return WorldTile(id, ground, roads, buildings, trees);
}

double _signedArea(Float32List r) {
  var a = 0.0;
  final n = r.length ~/ 2;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    a += r[j * 2] * r[i * 2 + 1] - r[i * 2] * r[j * 2 + 1];
  }
  return a / 2;
}

Float32List _reversed(Float32List r) {
  final out = Float32List(r.length);
  final n = r.length ~/ 2;
  for (var i = 0; i < n; i++) {
    out[i * 2] = r[(n - 1 - i) * 2];
    out[i * 2 + 1] = r[(n - 1 - i) * 2 + 1];
  }
  return out;
}

/// Turns a polyline into one quad per segment, each extended by a half-width at
/// both ends so neighbouring quads overlap and cover the joints.
List<Float32List> _expand(Float32List line, double hw) {
  final out = <Float32List>[];
  for (var i = 0; i + 3 < line.length; i += 2) {
    final ax = line[i], ay = line[i + 1], bx = line[i + 2], by = line[i + 3];
    final dx = bx - ax, dy = by - ay;
    final len = sqrt(dx * dx + dy * dy);
    if (len < 0.01) continue;
    final ux = dx / len * hw, uy = dy / len * hw;
    final nx = -uy, ny = ux;
    final sx = ax - ux, sy = ay - uy, ex = bx + ux, ey = by + uy;
    out.add(Float32List.fromList([
      sx + nx, sy + ny, sx - nx, sy - ny, //
      ex - nx, ey - ny, ex + nx, ey + ny,
    ]));
  }
  return out;
}

/// Deterministic tree scatter: dense in woods and parks, sparse on open land,
/// never on roads, water or buildings.
Float32List _scatterTrees(
  Map<Ground, List<Shape>> ground,
  Map<Road, List<Shape>> roads,
  List<Shape> buildings,
  double x0,
  double y0,
  double x1,
  double y1,
) {
  const cell = 5.0;
  final cols = ((x1 - x0) / cell).ceil() + 1, rows = ((y1 - y0) / cell).ceil() + 1;
  final blocked = Uint8List(cols * rows);
  void mark(double x, double y, double r) {
    final c0 = max(0, ((x - r - x0) / cell).floor()), c1 = min(cols - 1, ((x + r - x0) / cell).floor());
    final r0 = max(0, ((y - r - y0) / cell).floor()), r1 = min(rows - 1, ((y + r - y0) / cell).floor());
    for (var c = c0; c <= c1; c++) {
      for (var w = r0; w <= r1; w++) {
        blocked[w * cols + c] = 1;
      }
    }
  }

  bool free(double x, double y) {
    final c = ((x - x0) / cell).floor(), r = ((y - y0) / cell).floor();
    return c >= 0 && r >= 0 && c < cols && r < rows && blocked[r * cols + c] == 0;
  }

  // Roads: walk each quad's centre line.
  for (final s in roads.values.expand((e) => e)) {
    for (final q in s.rings) {
      if (q.length != 8) {
        mark(s.cx, s.cy, s.radius);
        continue;
      }
      final ax = (q[0] + q[2]) / 2, ay = (q[1] + q[3]) / 2;
      final bx = (q[4] + q[6]) / 2, by = (q[5] + q[7]) / 2;
      final hw = sqrt(pow(q[0] - q[2], 2) + pow(q[1] - q[3], 2)) / 2 + 2.5;
      final len = sqrt(pow(bx - ax, 2) + pow(by - ay, 2));
      final steps = max(1, (len / cell).ceil());
      for (var i = 0; i <= steps; i++) {
        mark(ax + (bx - ax) * i / steps, ay + (by - ay) * i / steps, hw);
      }
    }
  }
  for (final b in buildings) {
    for (var x = b.minX; x <= b.maxX + cell; x += cell) {
      for (var y = b.minY; y <= b.maxY + cell; y += cell) {
        mark(min(x, b.maxX), min(y, b.maxY), 2);
      }
    }
  }
  final water = ground[Ground.water] ?? const <Shape>[];
  final built = [...?ground[Ground.urban], ...?ground[Ground.pitch]];

  final out = <double>[];
  void plant(double x, double y, int h) {
    out
      ..add(x)
      ..add(y)
      ..add(0.75 + ((h >> 16) & 0xff) / 255 * 0.6);
    mark(x, y, 3);
  }

  for (final (g, spacing) in const [(Ground.wood, 12.0), (Ground.park, 18.0), (Ground.grass, 30.0)]) {
    for (final s in ground[g] ?? const <Shape>[]) {
      for (var x = (s.minX / spacing).floor() * spacing; x < s.maxX; x += spacing) {
        for (var y = (s.minY / spacing).floor() * spacing; y < s.maxY; y += spacing) {
          final h = _hash(x, y);
          final px = x + (h & 0xff) / 255 * spacing * 0.8;
          final py = y + ((h >> 8) & 0xff) / 255 * spacing * 0.8;
          if (free(px, py) && s.contains(px, py)) plant(px, py, h);
          if (out.length >= 3000 * 3) return Float32List.fromList(out);
        }
      }
    }
  }
  // Open land: sparse groves so quiet areas don't look empty.
  const spacing = 24.0;
  for (var x = (x0 / spacing).ceil() * spacing; x < x1; x += spacing) {
    for (var y = (y0 / spacing).ceil() * spacing; y < y1; y += spacing) {
      final h = _hash(x + 7, y - 3);
      if ((h >> 24) % 100 > 38) continue;
      final px = x + (h & 0xff) / 255 * spacing * 0.9;
      final py = y + ((h >> 8) & 0xff) / 255 * spacing * 0.9;
      if (!free(px, py)) continue;
      if (water.any((w) => w.contains(px, py)) || built.any((u) => u.contains(px, py))) continue;
      plant(px, py, h);
      if (out.length >= 5000 * 3) return Float32List.fromList(out);
    }
  }
  return Float32List.fromList(out);
}

int _hash(double x, double y) {
  var h = (x.round() * 73856093) ^ (y.round() * 19349663);
  h = (h ^ (h >> 13)) * 0x5bd1e995;
  return (h ^ (h >> 15)) & 0x7fffffff;
}
