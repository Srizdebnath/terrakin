import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';

/// What goes on a shareable card.
class MemeCardData {
  const MemeCardData({
    required this.headline,
    required this.subtitle,
    required this.art,
    required this.accent,
    this.chips = const [],
    this.footer = '',
    this.shareText = '',
  });
  final String headline, subtitle, footer, shareText;
  final String art; // asset path of the hero image
  final Color accent;
  final List<String> chips;
}

/// Previews a 4:5 card for X / Telegram / Instagram and shares it as a PNG.
Future<void> showMemeCard(BuildContext context, MemeCardData data) =>
    showDialog<void>(context: context, builder: (_) => _MemeCardDialog(data));

class _MemeCardDialog extends StatefulWidget {
  const _MemeCardDialog(this.data);
  final MemeCardData data;

  @override
  State<_MemeCardDialog> createState() => _MemeCardDialogState();
}

class _MemeCardDialogState extends State<_MemeCardDialog> {
  final _key = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary =
          _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      // 360 x 450 logical at 3x: a 1080 x 1350 PNG.
      final image = await boundary.toImage(
        pixelRatio: 1080 / boundary.size.width,
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/terrakin-${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: widget.data.shareText),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          child: RepaintBoundary(key: _key, child: MemeCard(widget.data)),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _share,
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// The card itself, 360 x 450 logical pixels.
class MemeCard extends StatelessWidget {
  const MemeCard(this.d, {super.key});
  final MemeCardData d;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SizedBox(
      width: 360,
      height: 450,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.25),
                    radius: 0.9,
                    colors: [d.accent.withValues(alpha: 0.45), TK.night],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(painter: _HexBackdrop(d.accent)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/images/brand/logo-mark.png',
                        width: 30,
                      ),
                      const SizedBox(width: 6),
                      Text('TERRAKIN', style: TK.display(16, color: TK.signal)),
                      const Spacer(),
                      Text(
                        'on Monad ⚡',
                        style: TK.body(11, color: TK.mist, bold: true),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: d.accent.withValues(alpha: 0.4),
                          blurRadius: 90,
                        ),
                      ],
                    ),
                    child: Image.asset(d.art, width: 170, height: 170),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    d.headline,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TK
                        .display(32, color: TK.signal)
                        .copyWith(
                          shadows: const [
                            Shadow(
                              color: Color(0xAA000000),
                              offset: Offset(0, 3),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    d.subtitle,
                    textAlign: TextAlign.center,
                    style: TK.body(14, color: TK.paper, bold: true),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final c in d.chips)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: TK.night.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: d.accent.withValues(alpha: 0.7),
                            ),
                          ),
                          child: Text(c, style: TK.body(11, bold: true)),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          d.footer,
                          overflow: TextOverflow.ellipsis,
                          style: TK.body(11, color: TK.mist, bold: true),
                        ),
                      ),
                      Text(
                        'own the map',
                        style: TK.display(12, color: TK.signal),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Faint territory hexes behind the art.
class _HexBackdrop extends CustomPainter {
  _HexBackdrop(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 26.0;
    final w = sqrt(3) * r;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = accent.withValues(alpha: 0.16);
    for (var row = -1; row * r * 1.5 < size.height + r; row++) {
      for (var col = -1; col * w < size.width + w; col++) {
        final cx = col * w + (row.isOdd ? w / 2 : 0), cy = row * r * 1.5;
        final path = Path();
        for (var k = 0; k < 6; k++) {
          final a = pi / 180 * (60 * k - 90);
          final pt = Offset(cx + r * cos(a), cy + r * sin(a));
          k == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
        }
        canvas.drawPath(path..close(), p);
      }
    }
  }

  @override
  bool shouldRepaint(_HexBackdrop old) => old.accent != accent;
}
