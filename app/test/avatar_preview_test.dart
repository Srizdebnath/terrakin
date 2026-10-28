import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrakin/core/avatars.dart';
import 'package:terrakin/world/avatar_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final out = Platform.environment['RENDER_OUT'];
  if (out == null) return;
  test('avatar sheet', () async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, 600, 540), Paint()..color = const Color(0xFF9BD27F));
    for (final (i, s) in avatarStyles.indexed) {
      for (final (j, (phase, moving, back, look)) in [(0.0, false, false, 0.0), (pi / 2, true, false, 0.6), (pi / 2, true, true, 0.0)].indexed) {
        c.save();
        c.translate(i * 100.0, j * 180.0);
        AvatarPainter(style: s, phase: phase, moving: moving, back: back, look: look).paint(c, const Size(100, 170));
        c.restore();
      }
    }
    final img = await rec.endRecording().toImage(600, 540);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$out/avatars.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}
