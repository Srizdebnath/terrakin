import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrakin/core/hexgrid.dart';

const _places = [
  (22.5726, 88.3639), // Kolkata
  (23.1750, 88.5650), // Ranaghat
  (-33.8688, 151.2093), // Sydney
  (64.1466, -21.9426), // Reykjavik
  (-54.8019, -68.3030), // Ushuaia
  (0.0001, -0.0001), // null island
  (51.4769, -0.0005), // Greenwich
  (-17.7134, 179.9990), // Fiji, near the date line
  (84.9, 12.0), // near the clamp
];

void main() {
  const dist = Distance();

  test('cos fixed point is accurate', () {
    for (var lat = -85; lat <= 85; lat += 5) {
      final want = cos(lat * pi / 180);
      expect(HexGrid.cosE6(lat * 1000000) / 1e6, closeTo(want, 2e-6), reason: '$lat');
    }
  });

  test('hexes are regular, ~150 m apart, and contain their points', () {
    for (final (lat, lng) in _places) {
      final id = HexGrid.idAt(LatLng(lat, lng));
      final c = HexGrid.center(id);
      expect(dist(LatLng(lat, lng), c), lessThan(95), reason: 'point lies within its hex');
      if (c.longitude > lng.floorToDouble() && c.longitude < lng.floorToDouble() + 1) {
        expect(HexGrid.idAt(c), id, reason: '$lat,$lng'); // unless cut by a strip seam
      }
      final (cell, q, r) = HexGrid.unpack(id);
      for (final (dq, dr) in const [(1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1)]) {
        final m = dist(c, HexGrid.center(HexGrid.idOf(cell, q + dq, r + dr)));
        expect(m, inInclusiveRange(148, 152), reason: 'neighbour spacing at $lat,$lng');
      }
    }
  });

  test('seam hexes are clipped to their strip', () {
    final id = HexGrid.idAt(const LatLng(51.4769, -0.0005)); // Greenwich, just west of 0°
    for (final p in HexGrid.corners(id)) {
      expect(p.longitude, lessThanOrEqualTo(0.0));
    }
    expect(HexGrid.idAt(const LatLng(51.4769, 0.0005)), isNot(id));
  });

  test('ids round-trip and pack like the contract', () {
    for (final (cell, q, r) in const [(0, 0, 0), (-180, -5, 7), (179, 38000, -77000), (88, -41000, 19293)]) {
      final id = HexGrid.idOf(cell, q, r);
      expect(HexGrid.unpack(id), (cell, q, r));
      expect(HexGrid.fromUint64(HexGrid.toUint64(id)), id);
    }
    expect(HexGrid.toUint64(HexGrid.idOf(0, 0, 0)), BigInt.parse('8000800000800000', radix: 16));
    final near = HexGrid.around(const LatLng(22.57, 88.36), 160);
    expect(near.length, inInclusiveRange(7, 19)); // own hex plus at least the first ring
  });

  test('landmark zones parse from spawn ids', () {
    expect(HexGrid.zoneOfSpawn('L563:2208:20389'), HexGrid.zoneOf(563, 2208));
    expect(HexGrid.zoneOfSpawn('L-5:-7:1'), HexGrid.zoneOf(-5, -7));
    expect(HexGrid.zoneOfSpawn('12:3:4'), isNull);
  });

  /// Writes vectors for backend/test/hexgrid.test.ts. Run with
  /// HEX_VECTORS_OUT=../backend/test/hexgrid.json.
  test('export hex vectors', () {
    final rng = Random(7);
    final out = <Map<String, Object>>[];
    for (final (lat, lng) in _places) {
      for (var i = 0; i < 60; i++) {
        // Points scattered around each place, many near hex edges.
        final la = (lat * 1e6).round() + rng.nextInt(20000) - 10000;
        final ln = ((lng * 1e6).round() + rng.nextInt(20000) - 10000).clamp(-180000000, 180000000);
        out.add({'lat': la, 'lng': ln, 'hex': HexGrid.toUint64(HexGrid.idAtE6(la, ln)).toString()});
      }
    }
    final path = Platform.environment['HEX_VECTORS_OUT'];
    if (path != null) File(path).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
    expect(out.length, _places.length * 60);
  });
}
