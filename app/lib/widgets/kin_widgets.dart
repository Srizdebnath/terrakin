import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/avatars.dart';
import '../core/conditions.dart';
import '../core/kin_stats.dart';
import '../core/species.dart';
import '../core/theme.dart';
import '../data/collection.dart';
import '../world/avatar_painter.dart';

class GradeGems extends StatelessWidget {
  const GradeGems(this.grade, {super.key, this.size = 18});
  final Grade grade;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < grade.gems; i++)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Image.asset(grade.gem, width: size, height: size),
            ),
        ],
      );
}

/// Idle bob from DESIGN.md section 7 (2 px, 1.6 s loop), scaled up a little for sprites.
class Bobbing extends StatefulWidget {
  const Bobbing({super.key, required this.child, this.amplitude = 4, this.phase = 0});
  final Widget child;
  final double amplitude;
  final double phase;

  @override
  State<Bobbing> createState() => _BobbingState();
}

class _BobbingState extends State<Bobbing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )
    ..value = widget.phase
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, -widget.amplitude * Curves.easeInOut.transform(_c.value)),
          child: child,
        ),
        child: widget.child,
      );
}

/// Kin sprite standing on a soft Affinity-coloured glow disc (map spawn look).
class KinSprite extends StatelessWidget {
  const KinSprite(this.species, {super.key, this.size = 64, this.glow = true});
  final Species species;
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (glow)
              Positioned(
                bottom: size * 0.02,
                child: Container(
                  width: size * 0.8,
                  height: size * 0.26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.elliptical(size, size * 0.3)),
                    color: species.affinity.color.withValues(alpha: 0.35),
                    boxShadow: [
                      BoxShadow(
                        color: species.affinity.color.withValues(alpha: 0.5),
                        blurRadius: size * 0.25,
                      ),
                    ],
                  ),
                ),
              ),
            Image.asset(species.sprite, width: size, height: size),
          ],
        ),
      );
}

class Silhouette extends StatelessWidget {
  const Silhouette(this.species, {super.key, this.size = 72});
  final Species species;
  final double size;

  @override
  Widget build(BuildContext context) => ColorFiltered(
        colorFilter: const ColorFilter.mode(TK.slate, BlendMode.srcIn),
        child: Image.asset(species.sprite, width: size, height: size),
      );
}

/// A character walking (or idling) on the spot, for menus.
class AvatarView extends StatefulWidget {
  const AvatarView(this.style, {super.key, this.size = 120, this.walking = true});
  final AvatarStyle style;
  final double size;
  final bool walking;

  @override
  State<AvatarView> createState() => _AvatarViewState();
}

class _AvatarViewState extends State<AvatarView> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          size: Size(widget.size * 100 / 140, widget.size),
          painter: AvatarPainter(
            style: widget.style,
            phase: _c.value * 2 * pi,
            moving: widget.walking,
          ),
        ),
      );
}

/// HP / ATK / DEF / SPD bars on paper.
class StatPanel extends StatelessWidget {
  const StatPanel(this.stats, {super.key, this.color = TK.ink, this.dark = false});
  final StatBlock stats;
  final Color color;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? TK.paper : TK.ink;
    final track = dark ? TK.slate : TK.paperShade;
    Widget bar(String label, int v, double max) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.5),
          child: Row(
            children: [
              SizedBox(width: 38, child: Text(label, style: TK.body(12, color: fg, bold: true))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: (v / max).clamp(0, 1),
                    minHeight: 8,
                    color: color,
                    backgroundColor: track,
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text('$v', textAlign: TextAlign.right, style: TK.body(12, color: fg, bold: true)),
              ),
            ],
          ),
        );
    return Column(
      children: [
        bar('HP', stats.hp, 420),
        bar('ATK', stats.atk, 200),
        bar('DEF', stats.def, 200),
        bar('SPD', stats.spd, 200),
      ],
    );
  }
}

/// Small rounded label, e.g. "Attuned · Rain ×1.20".
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color = TK.signal, this.icon, this.dark = false});
  final String text;
  final Color color;
  final IconData? icon;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: dark ? 0.22 : 0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: dark ? color : TK.ink),
              const SizedBox(width: 4),
            ],
            Text(text, style: TK.body(11, color: dark ? TK.paper : TK.ink, bold: true)),
          ],
        ),
      );
}

String fmtFactor(double f) => '×${f.toStringAsFixed(2)}';

String fmtDistance(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0)} km';

String shortAddress(String? a) =>
    a == null || a.length < 12 ? '…' : '${a.substring(0, 6)}…${a.substring(a.length - 4)}';

String compassPoint(LatLng from, LatLng to) {
  final b = (const Distance().bearing(from, to) + 360) % 360;
  const names = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  return names[((b + 22.5) % 360 ~/ 45)];
}

/// The paper bond card: Imprint photo, Kin, Grade gems, stats and live modifiers.
class KinCard extends StatelessWidget {
  const KinCard(this.kin, {super.key, required this.conditions, required this.player, this.footer});
  final Kin kin;
  final Conditions conditions;
  final LatLng player;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final sp = kin.species;
    final photo = kin.imprintPath;
    final mods = kin.modifiers(conditions, player);
    final live = kin.livePower(conditions, player);
    final level = kin.level;
    final nextAt = strideForLevel(level + 1);
    final prevAt = strideForLevel(level);
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: TK.paper,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kin.grade.color, width: 5),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10))],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 190,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: photo != null && File(photo).existsSync()
                        ? Image.file(File(photo), fit: BoxFit.cover)
                        : DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [sp.affinity.color, sp.affinity.shade],
                              ),
                            ),
                          ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -18,
                  child: Center(child: Image.asset(sp.sprite, width: 140, height: 140)),
                ),
                Positioned(top: 10, left: 10, child: Image.asset(sp.affinity.emblem, width: 32, height: 32)),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: TK.ink.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(10)),
                    child: Text('Lv $level', style: TK.display(14, color: TK.signal)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(sp.name, style: TK.display(26, color: TK.ink)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GradeGems(kin.grade, size: 16),
              const SizedBox(width: 8),
              Text(kin.grade.label, style: TK.body(13, color: TK.ink, bold: true)),
              if (kin.landmark) ...[
                const SizedBox(width: 8),
                const Tag('Landmark', icon: Icons.flag_rounded),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$live', style: TK.display(30, color: TK.ink)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(live == kin.power ? 'power' : 'power now  (base ${kin.power})',
                    style: TK.body(12, color: TK.ink.withValues(alpha: 0.6), bold: true)),
              ),
            ],
          ),
          if (mods.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final m in mods)
                  Tag('${m.label} ${fmtFactor(m.factor)}', color: m.factor >= 1 ? const Color(0xFF3E9150) : TK.danger),
              ],
            ),
          ],
          const SizedBox(height: 8),
          StatPanel(kin.stats, color: sp.affinity.shade),
          const SizedBox(height: 8),
          _AbilityRow(Icons.auto_awesome_rounded, sp.ability.label, sp.ability.description),
          _AbilityRow(Icons.fingerprint_rounded, kin.genes.trait.label, kin.genes.trait.description),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('Stride', style: TK.body(12, color: TK.ink, bold: true)),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: ((kin.stride - prevAt) / max(1, nextAt - prevAt)).clamp(0, 1),
                    minHeight: 8,
                    color: TK.signal,
                    backgroundColor: TK.paperShade,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${fmtDistance(kin.stride)} / ${fmtDistance(nextAt)}',
                  style: TK.body(11, color: TK.ink.withValues(alpha: 0.7), bold: true)),
            ],
          ),
          if (kin.trades > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Traded ${kin.trades}× · last from ${kin.tradedFrom ?? 'a Wayfinder'}',
              style: TK.body(11, color: TK.ink.withValues(alpha: 0.7), bold: true),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'From ${kin.lat.toStringAsFixed(4)}, ${kin.lng.toStringAsFixed(4)} · Homeground within 1 km',
            style: TK.body(11, color: TK.ink.withValues(alpha: 0.6)),
          ),
          if (footer != null) ...[const SizedBox(height: 10), footer!],
        ],
      ),
    );
  }
}

class _AbilityRow extends StatelessWidget {
  const _AbilityRow(this.icon, this.title, this.body);
  final IconData icon;
  final String title, body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: TK.ink),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '$title  ', style: TK.body(12, color: TK.ink, bold: true)),
                  TextSpan(text: body, style: TK.body(12, color: TK.ink.withValues(alpha: 0.75))),
                ]),
              ),
            ),
          ],
        ),
      );
}
