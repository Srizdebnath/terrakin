import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrakin/core/species.dart';
import 'package:terrakin/core/theme.dart';
import 'package:terrakin/widgets/meme_card.dart';

/// Renders a sample meme card. Run with `RENDER_OUT=dir`.
void main() {
  final out = Platform.environment['RENDER_OUT'];
  if (out == null) return;

  Future<void> loadFont(String family, String path) async {
    final loader = FontLoader(family)..addFont(rootBundle.load(path));
    await loader.load();
  }

  testWidgets('meme card', (tester) async {
    await tester.runAsync(() async {
      await loadFont('Fredoka', 'assets/fonts/Fredoka.ttf');
      await loadFont('Inter', 'assets/fonts/Inter.ttf');
    });
    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(360, 450));
    await tester.pumpWidget(MaterialApp(
      theme: TK.theme(),
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: MemeCard(MemeCardData(
            headline: "it's giving Mythic ✨",
            subtitle: 'Mythic Glyphlet · Landmark',
            art: species[3].sprite,
            accent: Grade.mythic.color,
            chips: const ['+1.6 MON', 'first throw', 'Ranaghat'],
            footer: '@sriz',
          )),
        ),
      ),
    ));
    await tester.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$out/meme-card.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
