import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrakin/core/conditions.dart';
import 'package:terrakin/world/camera.dart';
import 'package:terrakin/world/palette.dart';
import 'package:terrakin/world/sky_painter.dart';
import 'package:terrakin/world/world_data.dart';
import 'package:terrakin/world/world_painter.dart';

/// Renders the world to PNGs for eyeballing. Set RENDER_OUT to enable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final out = Platform.environment['RENDER_OUT'];
  if (out == null) return;

  const size = Size(400, 860);
  final cases = {
    'ranaghat_day': ('14_12222_7107', 23.1707, 88.5608, const Conditions(sky: Sky.partlyCloudy, tempC: 30, windKmh: 8, daylight: 1, twilight: 0, dayArc: 0.35), 0.3, 0.0),
    'kolkata_day': ('14_12212_7138', 22.5500, 88.3480, const Conditions(sky: Sky.clear, tempC: 31, windKmh: 6, daylight: 1, twilight: 0, dayArc: 0.6), 0.25, 0.7),
    'kolkata_storm': ('14_12212_7138', 22.5500, 88.3480, const Conditions(sky: Sky.storm, tempC: 24, windKmh: 30, daylight: 0.8, twilight: 0, dayArc: 0.7), 0.3, 0.7),
    'ranaghat_night': ('14_12222_7107', 23.1707, 88.5608, const Conditions(sky: Sky.cloudy, tempC: 26, windKmh: 3, daylight: 0, twilight: 0, dayArc: 1.3), 0.3, 0.0),
    'kolkata_dusk_far': ('14_12212_7138', 22.5500, 88.3480, const Conditions(sky: Sky.clear, tempC: 28, windKmh: 6, daylight: 0.5, twilight: 1, dayArc: 0.98), 0.8, 2.0),
  };
  for (final e in cases.entries) {
    test('render ${e.key}', () async {
      final (file, lat, lng, cond, zoom, yaw) = e.value;
      final p = file.split('_').map(int.parse).toList();
      final tile = buildTile(File('test/fixtures/$file.pbf').readAsBytesSync(), TileId(p[1], p[2], p[0]), lat, lng);
      final cam = WorldCamera()
        ..zoom = zoom
        ..yaw = yaw;
      final pal = Palette.of(cond);
      final time = ValueNotifier(3.3);
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      final sw = Stopwatch()..start();
      SkyPainter(cam: cam, palette: pal, conditions: cond, time: time).paint(c, size);
      WorldPainter(tiles: () => [tile], cam: cam, palette: pal, player: () => (0, 0), reach: 40, ringColor: const Color(0xFFFFB547)).paint(c, size);
      WeatherFxPainter(conditions: cond, time: time).paint(c, size);
      debugPrint('${e.key}: record ${sw.elapsedMilliseconds} ms');
      final img = await rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$out/${e.key}.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }
}
