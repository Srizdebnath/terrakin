import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrakin/core/conditions.dart';
import 'package:terrakin/core/species.dart';
import 'package:terrakin/data/spawn_engine.dart';
import 'package:terrakin/world/world_data.dart';

/// Writes spawn vectors the backend's TypeScript port is checked against.
/// Run with VECTORS_OUT=../backend/test/vectors.json.
void main() {
  final out = Platform.environment['VECTORS_OUT'];
  if (out == null) return;
  test('export spawn vectors', () {
    final rows = <Map<String, dynamic>>[];
    const places = [
      LatLng(23.1760, 88.5670),
      LatLng(64.1466, -21.9426),
      LatLng(-33.8688, 151.2093),
      LatLng(-16.5, 179.999),
      LatLng(40.7128, -74.0060),
    ];
    final times = [DateTime.utc(2026, 10, 27, 16, 30), DateTime.utc(2027, 3, 1, 4, 5)];
    for (final p in places) {
      for (final t in times) {
        for (final sky in [Sky.storm, Sky.clear]) {
          final cond = Conditions(sky: sky, tempC: 24, windKmh: 5, daylight: 1, twilight: 0);
          for (final s in [
            ...SpawnEngine.wild(p, 400, now: t, conditions: cond, habitat: (_) => Habitat.land),
            ...SpawnEngine.landmarks(p, now: t),
          ]) {
            rows.add({
              'id': s.id,
              'kind': s.kind.name,
              'species': species.indexOf(s.species),
              'grade': s.grade.index,
              'vigor': s.genes.vigor.toList(),
              'trait': s.genes.trait.index,
              'lat': s.point.latitude,
              'lng': s.point.longitude,
              'expires': s.expiresAt.millisecondsSinceEpoch,
              'boosted': sky == Sky.storm ? ['volt', 'tide'] : ['forge', 'grove'],
            });
          }
        }
      }
    }
    File(out).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rows));
    expect(rows.length, greaterThan(100));
  });
}
