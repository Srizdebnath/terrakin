import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrakin/world/world_data.dart';

void main() {
  for (final f in Directory('test/fixtures').listSync().whereType<File>()) {
    test('decodes ${f.path}', () {
      final p = f.uri.pathSegments.last.split('.').first.split('_').map(int.parse).toList();
      final id = TileId(p[1], p[2], p[0]);
      final lat = TileId.latOf(id.y + 0.5, 14), lng = TileId.lngOf(id.x + 0.5, 14);
      final sw = Stopwatch()..start();
      final t = buildTile(f.readAsBytesSync(), id, lat, lng);
      debugPrint('${f.path}: ${sw.elapsedMilliseconds} ms');
      debugPrint('  ground: ${t.ground.map((k, v) => MapEntry(k.name, v.length))}');
      debugPrint('  roads: ${t.roads.map((k, v) => MapEntry(k.name, v.length))}');
      debugPrint('  buildings: ${t.buildings.length}, trees: ${t.trees.length ~/ 3}');
      expect(t.roads, isNotEmpty);
      // Tile spans roughly 2.2 km; every road vertex should sit inside +-1.3 km.
      for (final s in t.roads.values.expand((e) => e)) {
        expect(s.cx.abs(), lessThan(1400));
        expect(s.cy.abs(), lessThan(1400));
      }
    });
  }
}
