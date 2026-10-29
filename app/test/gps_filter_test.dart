import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrakin/core/gps_filter.dart';

void main() {
  const home = LatLng(22.5448, 88.3426);
  const dist = Distance();
  final t0 = DateTime(2026, 10, 29, 12);

  LatLng offset(LatLng p, double north, double east) => LatLng(
        p.latitude + north / 111320,
        p.longitude + east / (111320 * math.cos(p.latitude * math.pi / 180)),
      );

  test('standing still: 15 m jitter barely moves the estimate', () {
    final f = GpsFilter();
    final rng = math.Random(7);
    var maxDrift = 0.0;
    for (var i = 0; i < 120; i++) {
      final raw = offset(home, (rng.nextDouble() - .5) * 30, (rng.nextDouble() - .5) * 30);
      f.add(raw.latitude, raw.longitude, 15, t0.add(Duration(seconds: i)), speedMps: 0);
      if (i > 10) maxDrift = math.max(maxDrift, dist(home, f.position!));
    }
    expect(maxDrift, lessThan(6));
    expect(f.speedKmh, lessThan(2));
  });

  test('walking: estimate follows a straight 1.4 m/s walk', () {
    final f = GpsFilter();
    final rng = math.Random(3);
    for (var i = 0; i < 60; i++) {
      final truth = offset(home, 1.4 * i, 0);
      final raw = offset(truth, (rng.nextDouble() - .5) * 10, (rng.nextDouble() - .5) * 10);
      f.add(raw.latitude, raw.longitude, 8, t0.add(Duration(seconds: i)), speedMps: 1.4);
    }
    expect(dist(offset(home, 1.4 * 59, 0), f.position!), lessThan(8));
  });

  test('a single 400 m glitch is ignored, a real relocation is accepted', () {
    final f = GpsFilter();
    for (var i = 0; i < 10; i++) {
      f.add(home.latitude, home.longitude, 5, t0.add(Duration(seconds: i)));
    }
    final far = offset(home, 400, 0);
    expect(f.add(far.latitude, far.longitude, 5, t0.add(const Duration(seconds: 10))), isFalse);
    expect(dist(home, f.position!), lessThan(1));
    for (var i = 11; i < 15; i++) {
      f.add(far.latitude, far.longitude, 5, t0.add(Duration(seconds: i)));
    }
    expect(dist(far, f.position!), lessThan(10));
  });

  test('indoors: a stream of ±90 m fixes still yields a position', () {
    final f = GpsFilter();
    for (var i = 0; i < 5; i++) {
      expect(f.add(home.latitude, home.longitude, 90, t0.add(Duration(seconds: i))), isTrue);
    }
    expect(f.position, isNotNull);
  });

  test('standing with ±35 m jitter and no phone speed never reads as driving', () {
    final f = GpsFilter();
    final rng = math.Random(11);
    var maxKmh = 0.0;
    for (var i = 0; i < 300; i++) {
      final raw = offset(home, (rng.nextDouble() - .5) * 70, (rng.nextDouble() - .5) * 70);
      f.add(raw.latitude, raw.longitude, 36, t0.add(Duration(seconds: i)));
      maxKmh = math.max(maxKmh, f.speedKmh);
    }
    expect(maxKmh, lessThan(10));
  });

  test('walking with 36 m fixes and no phone speed: the dot keeps up', () {
    final f = GpsFilter();
    final rng = math.Random(5);
    for (var i = 0; i < 30; i++) {
      final raw = offset(home, (rng.nextDouble() - .5) * 20, (rng.nextDouble() - .5) * 20);
      f.add(raw.latitude, raw.longitude, 36, t0.add(Duration(seconds: i)));
    }
    for (var i = 0; i < 180; i++) {
      final truth = offset(home, 1.3 * i, 0);
      final raw = offset(truth, (rng.nextDouble() - .5) * 20, (rng.nextDouble() - .5) * 20);
      f.add(raw.latitude, raw.longitude, 36, t0.add(Duration(seconds: 30 + i)));
    }
    expect(dist(offset(home, 1.3 * 179, 0), f.position!), lessThan(30));
    expect(f.speedKmh, lessThan(25));
  });
}
