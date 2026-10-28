import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../core/conditions.dart';
import '../core/kin_stats.dart';
import '../core/rng.dart';
import '../core/species.dart';
import '../world/world_data.dart' show Habitat;

enum SpawnKind { wild, weather, landmark }

class Spawn {
  Spawn(this.id, this.genes, this.point, this.expiresAt, this.kind);
  final String id;
  final Genes genes;
  final LatLng point;
  final DateTime expiresAt;
  final SpawnKind kind;

  Species get species => genes.species;
  Grade get grade => genes.grade;
  bool get landmark => kind == SpawnKind.landmark;
}

/// Deterministic, server-free spawns for the whole planet (SRS FR-SPN-01..03).
///
/// The Earth is cut into ~165 m cells (narrower in longitude degrees towards
/// the poles so every cell covers about the same ground) and 15-minute
/// windows. Each (cell, window) seeds its own RNG, so everyone standing at the
/// same coordinate at the same time meets the same Kin with the same Grade,
/// stats and Trait. Landmark Kin live a whole UTC day in ~4.5 km zones.
class SpawnEngine {
  static const cellDeg = 0.0015;
  static const window = Duration(minutes: 15);
  static const zoneDeg = 0.04;

  static int windowIndex(DateTime t) => t.millisecondsSinceEpoch ~/ window.inMilliseconds;
  static int dayIndex(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  /// Longitude step for a row so cells stay roughly square on the ground.
  static double _lngStep(double deg, int row) {
    final lat = (row + 0.5) * deg;
    return deg / max(0.15, cos(lat * pi / 180));
  }

  /// Wild and weather spawns within [radiusM] of [center].
  ///
  /// [habitat] reports the ground at a point (null while terrain is loading);
  /// Kin standing in water lean Tide, in green spaces lean Grove.
  static List<Spawn> wild(
    LatLng center,
    double radiusM, {
    required DateTime now,
    required Conditions conditions,
    required Habitat? Function(LatLng) habitat,
  }) {
    final w = windowIndex(now);
    final expires = DateTime.fromMillisecondsSinceEpoch((w + 1) * window.inMilliseconds);
    final rows = (radiusM / 165).ceil() + 1;
    final r0 = (center.latitude / cellDeg).floor();
    final boosted = conditions.boosted.toList()..sort((a, b) => a.index.compareTo(b.index));
    final out = <Spawn>[];
    const dist = Distance();
    for (var row = r0 - rows; row <= r0 + rows; row++) {
      final step = _lngStep(cellDeg, row);
      final c0 = (center.longitude / step).floor();
      final cols = (rows * cellDeg / step).ceil() + 1;
      for (var col = c0 - cols; col <= c0 + cols; col++) {
        for (final s in _cell(row, col, step, w, expires, boosted, conditions.sky, habitat)) {
          if (dist.as(LengthUnit.Meter, center, s.point) <= radiusM) out.add(s);
        }
      }
    }
    return out;
  }

  static List<Spawn> _cell(int row, int col, double step, int w, DateTime expires,
      List<Affinity> boosted, Sky sky, Habitat? Function(LatLng) habitat) {
    final out = <Spawn>[];
    final rng = Mulberry32(hash32(row, col, w, 1));
    final roll = rng.nextInt(100);
    final count = roll < 35 ? 0 : (roll < 80 ? 1 : 2);
    for (var i = 0; i < count; i++) {
      final lat = (row + rng.nextDouble()) * cellDeg;
      final lng = _wrap((col + rng.nextDouble()) * step);
      var sp = species[rng.nextInt(species.length)];
      final grade = _rollGrade(rng);
      final genes = Genes.roll(rng, sp, grade);
      final hRoll = rng.nextDouble();
      final p = LatLng(lat, lng);
      final h = habitat(p);
      if (h == null) continue; // wait for terrain so every player sees the same Kin
      if (h == Habitat.water && sp.affinity != Affinity.tide && hRoll < 0.6) {
        sp = speciesOf(Affinity.tide);
      } else if (h == Habitat.green && sp.affinity != Affinity.grove && hRoll < 0.35) {
        sp = speciesOf(Affinity.grove);
      }
      out.add(Spawn('$row:$col:$w:$i', Genes(sp, genes.grade, genes.vigor, genes.trait), p, expires,
          SpawnKind.wild));
    }

    // Weather spawn: an extra Kin of a boosted Affinity in about one cell in five.
    if (boosted.isNotEmpty) {
      final wr = Mulberry32(hash32(row, col, w, 100 + sky.index));
      if (wr.nextDouble() < 0.22) {
        final lat = (row + wr.nextDouble()) * cellDeg;
        final lng = _wrap((col + wr.nextDouble()) * step);
        final sp = speciesOf(boosted[wr.nextInt(boosted.length)]);
        var grade = _rollGrade(wr);
        if (grade == Grade.common) grade = Grade.uncommon;
        final p = LatLng(lat, lng);
        if (habitat(p) != null) {
          out.add(Spawn('w$row:$col:$w:${sky.name}', Genes.roll(wr, sp, grade, minVigor: 4), p, expires,
              SpawnKind.weather));
        }
      }
    }
    return out;
  }

  /// Landmark Kin in the zones around [center]: one per zone per UTC day,
  /// Epic or Mythic, always at the same coordinate for everyone.
  static List<Spawn> landmarks(LatLng center, {required DateTime now, int ring = 1}) {
    final day = dayIndex(now);
    final expires = DateTime.fromMillisecondsSinceEpoch((day + 1) * Duration.millisecondsPerDay, isUtc: true);
    final r0 = (center.latitude / zoneDeg).floor();
    final out = <Spawn>[];
    for (var row = r0 - ring; row <= r0 + ring; row++) {
      final step = _lngStep(zoneDeg, row);
      final c0 = (center.longitude / step).floor();
      for (var col = c0 - ring; col <= c0 + ring; col++) {
        final rng = Mulberry32(hash32(row, col, day, 7));
        final lat = (row + 0.1 + rng.nextDouble() * 0.8) * zoneDeg;
        final lng = _wrap((col + 0.1 + rng.nextDouble() * 0.8) * step);
        final sp = species[rng.nextInt(species.length)];
        final grade = rng.nextDouble() < 0.2 ? Grade.mythic : Grade.epic;
        out.add(Spawn('L$row:$col:$day', Genes.roll(rng, sp, grade, minVigor: 10), LatLng(lat, lng), expires,
            SpawnKind.landmark));
      }
    }
    return out;
  }

  static double _wrap(double lng) => lng > 180 ? lng - 360 : (lng < -180 ? lng + 360 : lng);

  static Grade _rollGrade(Random rng) {
    final total = Grade.values.fold<double>(0, (a, g) => a + g.weight);
    var roll = rng.nextDouble() * total;
    for (final g in Grade.values) {
      roll -= g.weight;
      if (roll <= 0) return g;
    }
    return Grade.common;
  }
}
