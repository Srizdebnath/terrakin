import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrakin/core/economy.dart';
import 'package:terrakin/widgets/orb_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final out = Platform.environment['RENDER_OUT'];
  if (out == null) return;
  test('orb sheet', () async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, 480, 140), Paint()..color = const Color(0xFF1F1B30));
    for (final (i, o) in Orb.values.indexed) {
      paintOrb(c, Offset(60 + i * 120.0, 70), 44, o, glow: i == 3 ? 1 : 0);
    }
    final img = await rec.endRecording().toImage(480, 140);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$out/orbs.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}
