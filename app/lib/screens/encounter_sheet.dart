import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/kin_stats.dart';
import '../core/economy.dart';
import '../core/species.dart';
import '../core/theme.dart';
import '../data/spawn_engine.dart';
import '../widgets/kin_widgets.dart';
import 'bond_screen.dart';

/// Tapping a Kin in the world: its fixed stats, Trait, ability and live
/// modifiers, and how far you still have to walk.
class EncounterSheet extends StatelessWidget {
  const EncounterSheet({super.key, required this.spawn});
  final Spawn spawn;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([location, weather]),
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final s = spawn;
    final sp = s.species;
    final c = conditions;
    final d = location.distanceTo(s.point);
    final reach = bondReach();
    final inReach = d <= reach && location.live;
    final bonded = collection.isBonded(s.id);
    final stats = s.genes.stats();
    final mods = liveModifiers(s.genes, c, metresFromOrigin: d);
    final live = (stats.power * combined(mods)).round();
    final until = TimeOfDay.fromDateTime(s.expiresAt.toLocal()).format(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: TK.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: s.grade.color, width: 6)),
        ),
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(color: TK.paperShade, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Bobbing(child: KinSprite(sp, size: 120)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Image.asset(sp.affinity.emblem, width: 22),
                        const SizedBox(width: 6),
                        Flexible(child: Text(sp.name, style: TK.display(26, color: TK.ink))),
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        GradeGems(s.grade, size: 15),
                        const SizedBox(width: 6),
                        Text(s.grade.label, style: TK.body(13, color: TK.ink, bold: true)),
                      ]),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        if (s.landmark) const Tag('Landmark', icon: Icons.flag_rounded),
                        if (s.kind == SpawnKind.weather) Tag('${c.sky.label} spawn', icon: c.sky.icon),
                        if (isBoosted(s)) const Tag('Boosted', icon: Icons.cyclone_rounded),
                      ]),
                      const SizedBox(height: 8),
                      Text.rich(TextSpan(children: [
                        TextSpan(text: '$live', style: TK.display(28, color: TK.ink)),
                        TextSpan(
                          text: live == stats.power ? '  power' : '  power now (base ${stats.power})',
                          style: TK.body(12, color: TK.ink.withValues(alpha: 0.6), bold: true),
                        ),
                      ])),
                    ],
                  ),
                ),
              ],
            ),
            if (mods.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in mods)
                  Tag('${m.label} ${fmtFactor(m.factor)}', color: m.factor >= 1 ? const Color(0xFF3E9150) : TK.danger),
              ]),
            ],
            const SizedBox(height: 12),
            StatPanel(stats, color: sp.affinity.shade),
            const SizedBox(height: 10),
            _line(Icons.auto_awesome_rounded, sp.ability.label, sp.ability.description),
            _line(Icons.fingerprint_rounded, s.genes.trait.label, s.genes.trait.description),
            _line(Icons.place_rounded, 'Fixed spot',
                '${s.point.latitude.toStringAsFixed(5)}, ${s.point.longitude.toStringAsFixed(5)} · '
                    'every player finds this exact Kin here until $until.'),
            const SizedBox(height: 16),
            if (bonded)
              FilledButton(onPressed: null, child: const Text('Already bonded'))
            else if (inReach)
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => BondScreen(spawn: s)));
                },
                child: Text('Bond · up to ${(catchChance(s, 1, Orb.seed) * 100).round()}% per Seed Orb'),
              )
            else
              FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.directions_walk_rounded),
                label: Text(location.live
                    ? 'Walk ${fmtDistance(d - reach)} closer'
                    : 'Turn on location to bond'),
              ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                '${fmtDistance(d)} away · your reach is ${reach.round()} m',
                style: TK.body(12, color: TK.ink.withValues(alpha: 0.6)),
              ),
            ),
            if (s.grade.index >= Grade.epic.index && !s.landmark) ...[
              const SizedBox(height: 6),
              Center(child: Text('Epic and Mythic Kin are hard to hold. Hit the glow.', style: TK.body(12, color: TK.ink))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: TK.ink),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '$title  ', style: TK.body(13, color: TK.ink, bold: true)),
                TextSpan(text: body, style: TK.body(13, color: TK.ink.withValues(alpha: 0.75))),
              ])),
            ),
          ],
        ),
      );
}
