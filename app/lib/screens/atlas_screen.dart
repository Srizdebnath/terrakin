import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/species.dart';
import '../core/theme.dart';
import '../data/collection.dart';
import '../widgets/kin_widgets.dart';

/// Atlas (SRS 3.10): species discovered, plus every Kin the player has bonded.
class AtlasScreen extends StatelessWidget {
  const AtlasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TK.night,
        title: Text('Atlas', style: TK.display(24)),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([collection, profile, weather]),
        builder: (context, _) {
          final kin = collection.all;
          final found = species.where((s) => collection.hasSpecies(s.id)).length;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Text('Species found: $found / ${species.length}',
                      style: TK.body(14, color: TK.mist, bold: true)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid.count(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final s in species)
                      _SpeciesSlot(s, collection.hasSpecies(s.id)),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Text('Your Kin (${kin.length})', style: TK.display(20)),
                ),
              ),
              if (kin.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverToBoxAdapter(
                    child: Text('Walk to a Kin in the world and tap it to bond.',
                        style: TK.body(14, color: TK.mist)),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList.separated(
                  itemCount: kin.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _KinRow(kin[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SpeciesSlot extends StatelessWidget {
  const _SpeciesSlot(this.species, this.found);
  final Species species;
  final bool found;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: TK.dusk,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: found ? species.affinity.color : TK.slate, width: 2),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Expanded(
              child: found
                  ? Image.asset(species.sprite)
                  : Silhouette(species),
            ),
            Text(found ? species.name : '???',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TK.body(10, bold: true)),
          ],
        ),
      );
}

class _KinRow extends StatelessWidget {
  const _KinRow(this.kin);
  final Kin kin;

  @override
  Widget build(BuildContext context) => Material(
        color: TK.dusk,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showDialog(
            context: context,
            builder: (ctx) => Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Center(
                  child: KinCard(
                    kin,
                    conditions: conditions,
                    player: location.position,
                    footer: ListenableBuilder(
                      listenable: profile,
                      builder: (_, _) => SizedBox(
                        width: double.infinity,
                        child: profile.buddyUid == kin.uid
                            ? OutlinedButton(
                                onPressed: () => profile.setBuddy(null),
                                child: Text('Walking together · tap to rest', style: TK.body(14, color: TK.ink, bold: true)),
                              )
                            : FilledButton.icon(
                                onPressed: () {
                                  profile.setBuddy(kin.uid);
                                  Navigator.pop(ctx);
                                },
                                icon: const Icon(Icons.directions_walk_rounded),
                                label: const Text('Make buddy'),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Image.asset(kin.species.sprite, width: 56, height: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(child: Text(kin.species.name, style: TK.display(18))),
                        const SizedBox(width: 6),
                        Text('Lv ${kin.level}', style: TK.body(12, color: TK.signal, bold: true)),
                        if (profile.buddyUid == kin.uid) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.directions_walk_rounded, size: 16, color: TK.signal),
                        ],
                        if (kin.landmark) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.flag_rounded, size: 16, color: TK.signal),
                        ],
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        GradeGems(kin.grade, size: 14),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(kin.genes.trait.label,
                              overflow: TextOverflow.ellipsis, style: TK.body(11, color: TK.mist)),
                        ),
                      ]),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${kin.livePower(conditions, location.position)}', style: TK.display(20, color: TK.signal)),
                    Text('HP ${kin.stats.hp}', style: TK.body(11, color: TK.mist)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}
