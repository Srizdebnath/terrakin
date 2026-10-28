import 'dart:math';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/avatars.dart';
import '../core/economy.dart';
import '../core/theme.dart';
import '../widgets/kin_widgets.dart';

/// Swipeable character cards with a walking preview and perk.
class CharacterCarousel extends StatefulWidget {
  const CharacterCarousel({super.key, required this.onChanged, this.burst});
  final ValueChanged<int> onChanged;

  /// Plays a mint burst on the focused card while running.
  final Animation<double>? burst;

  @override
  State<CharacterCarousel> createState() => _CharacterCarouselState();
}

class _CharacterCarouselState extends State<CharacterCarousel> {
  final _pages = PageController(viewportFraction: 0.78);
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: avatarStyles.length,
            onPageChanged: (i) {
              setState(() => _index = i);
              widget.onChanged(i);
            },
            itemBuilder: (_, i) => _card(avatarStyles[i], i == _index),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < avatarStyles.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                width: i == _index ? 18 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _index ? TK.signal : TK.slate,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ]);

  Widget _card(AvatarStyle s, bool focused) => AnimatedScale(
        scale: focused ? 1 : 0.88,
        duration: const Duration(milliseconds: 220),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          decoration: BoxDecoration(
            color: TK.paper,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: s.top, width: 5),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10))],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: RadialGradient(colors: [s.top.withValues(alpha: 0.45), TK.paper]),
                        ),
                      ),
                    ),
                    if (focused && widget.burst != null)
                      AnimatedBuilder(
                        animation: widget.burst!,
                        builder: (_, _) => widget.burst!.value == 0
                            ? const SizedBox.shrink()
                            : CustomPaint(size: const Size(260, 260), painter: _BurstPainter(widget.burst!.value, s.accent)),
                      ),
                    LayoutBuilder(
                      builder: (_, box) => AvatarView(s, size: min(box.maxHeight * 0.9, 260), walking: focused),
                    ),
                    if (profile.owns(s.id))
                      const Positioned(top: 8, right: 8, child: Tag('Owned', icon: Icons.verified_rounded)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(s.name, style: TK.display(28, color: TK.ink)),
              Text(s.title, style: TK.body(14, color: TK.ink.withValues(alpha: 0.6), bold: true)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: TK.paperShade, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Icon(Icons.bolt_rounded, color: s.top),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${s.perk.label}  ', style: TK.body(13, color: TK.ink, bold: true)),
                      TextSpan(text: s.perk.description, style: TK.body(13, color: TK.ink)),
                    ])),
                  ),
                ]),
              ),
            ],
          ),
        ),
      );
}

/// Mint another character with MON (the first one comes with your profile).
class MintScreen extends StatefulWidget {
  const MintScreen({super.key});

  @override
  State<MintScreen> createState() => _MintScreenState();
}

class _MintScreenState extends State<MintScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _burst =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  int _index = 0;
  bool _minting = false;
  String? _error;

  AvatarStyle get _style => avatarStyles[_index];

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  Future<void> _mint() async {
    setState(() {
      _minting = true;
      _error = null;
    });
    try {
      await chain.mintCharacter(_index);
      await chain.sync();
      final minted = profile.avatars.lastWhere((a) => a.styleId == _style.id);
      await profile.setActive(minted.tokenId);
      await _burst.forward(from: 0);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _minting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = chain.prices?.nextCharacter;
    return Scaffold(
      backgroundColor: TK.night,
      appBar: AppBar(backgroundColor: TK.night, title: Text('Characters', style: TK.display(22))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([chain, profile]),
          builder: (context, _) {
            final owned = profile.owns(_style.id);
            final affordable = price != null && chain.balance >= price;
            return Column(children: [
              Expanded(child: CharacterCarousel(onChanged: (i) => setState(() => _index = i), burst: _burst)),
              const SizedBox(height: 8),
              Text('Balance ${fmtMon(chain.balance)}', style: TK.body(13, color: TK.mist, bold: true)),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Text(_error!, textAlign: TextAlign.center, style: TK.body(13, color: TK.danger)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: owned
                      ? FilledButton(
                          onPressed: profile.active?.styleId == _style.id
                              ? null
                              : () async {
                                  final token = profile.avatars.firstWhere((a) => a.styleId == _style.id).tokenId;
                                  await profile.setActive(token);
                                  if (context.mounted) Navigator.pop(context);
                                },
                          child: Text(profile.active?.styleId == _style.id
                              ? 'Walking as ${_style.name}'
                              : 'Walk as ${_style.name}'),
                        )
                      : FilledButton(
                          onPressed: affordable && !_minting ? _mint : null,
                          child: _minting
                              ? const SizedBox(
                                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: TK.ink))
                              : Text(price == null
                                  ? 'Loading price…'
                                  : affordable
                                      ? 'Mint ${_style.name} · ${fmtMon(price)}'
                                      : 'Need ${fmtMon(price)} + gas'),
                        ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..color = color.withValues(alpha: (1 - t).clamp(0, 1))
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 14; i++) {
      final a = i / 14 * 2 * pi;
      final r0 = 40 + t * 60, r1 = 60 + t * 110;
      canvas.drawLine(c + Offset(cos(a), sin(a)) * r0, c + Offset(cos(a), sin(a)) * r1, p);
    }
    canvas.drawCircle(
        c,
        30 + t * 120,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = TK.signal.withValues(alpha: (1 - t) * 0.8));
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}
