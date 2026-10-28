import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrakin/core/conditions.dart';
import 'package:terrakin/data/spawn_engine.dart';
import 'package:terrakin/world/world_data.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27, 16, 30);
  const cond = Conditions(sky: Sky.storm, tempC: 24, windKmh: 30, daylight: 0, twilight: 0);
  Habitat land(LatLng _) => Habitat.land;

  const places = {
    'Ranaghat': LatLng(23.1760, 88.5670),
    'Reykjavik': LatLng(64.1466, -21.9426),
    'Sydney': LatLng(-33.8688, 151.2093),
    'Sao Paulo': LatLng(-23.5505, -46.6333),
    'Fiji (date line)': LatLng(-16.5, 179.999),
    'Tromso': LatLng(69.6492, 18.9553),
  };

  for (final e in places.entries) {
    test('${e.key}: same Kin for every player, sane density', () {
      final a = SpawnEngine.wild(e.value, 300, now: now, conditions: cond, habitat: land);
      // A second player 20 m away sees the overlapping Kin identically.
      final other = LatLng(e.value.latitude + 0.00018, e.value.longitude);
      final b = SpawnEngine.wild(other, 300, now: now, conditions: cond, habitat: land);
      final byId = {for (final s in b) s.id: s};
      var shared = 0;
      for (final s in a) {
        final t = byId[s.id];
        if (t == null) continue;
        shared++;
        expect(t.point, s.point);
        expect(t.species.id, s.species.id);
        expect(t.grade, s.grade);
        expect(t.genes.vigor.toList(), s.genes.vigor.toList());
        expect(t.genes.trait, s.genes.trait);
        expect(t.genes.stats().power, s.genes.stats().power);
      }
      expect(shared, greaterThan(0));
      // ~10 cells cover a 300 m disc at any latitude, so expect about 8-15 Kin everywhere.
      expect(a.length, inInclusiveRange(5, 30), reason: '${a.length} spawns');
      for (final s in a) {
        expect(s.point.longitude, inInclusiveRange(-180, 180));
        expect(const Distance().as(LengthUnit.Meter, e.value, s.point), lessThanOrEqualTo(300));
      }
      final lm = SpawnEngine.landmarks(e.value, now: now);
      expect(lm, hasLength(9));
      expect(SpawnEngine.landmarks(other, now: now).map((s) => s.id).toSet(), lm.map((s) => s.id).toSet());
    });
  }

  test('habitat steers Kin: water leans Tide', () {
    const p = LatLng(23.1760, 88.5670);
    final water = SpawnEngine.wild(p, 400, now: now, conditions: cond, habitat: (_) => Habitat.water);
    final wild = water.where((s) => s.kind == SpawnKind.wild);
    final tide = wild.where((s) => s.species.id == 'ripplet').length;
    expect(tide / wild.length, greaterThan(0.5));
    // Pending terrain hides spawns instead of guessing.
    expect(SpawnEngine.wild(p, 400, now: now, conditions: cond, habitat: (_) => null), isEmpty);
  });
}
