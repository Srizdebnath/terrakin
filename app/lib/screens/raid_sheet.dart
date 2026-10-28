import 'package:flutter/material.dart';

import '../app_state.dart';
import '../chain/commerce.dart';
import '../core/copy.dart';
import '../core/economy.dart';
import '../core/hexgrid.dart';
import '../core/species.dart';
import '../core/theme.dart';
import '../data/collection.dart';
import '../data/spawn_engine.dart';
import '../widgets/meme_card.dart';
import 'battle_screen.dart';
import 'hex_sheet.dart';

/// Today's raid boss at a Landmark: one HP bar everyone chips at, the pot
/// split by damage, orbs for felling it. Also claims yesterday's loot.
class RaidSheet extends StatefulWidget {
  const RaidSheet({super.key, required this.landmark});
  final Spawn landmark;

  @override
  State<RaidSheet> createState() => _RaidSheetState();
}

class _RaidSheetState extends State<RaidSheet> {
  RaidState? _today, _yesterday;
  String? _error;
  bool _busy = false;

  late final int _zone = HexGrid.zoneOfSpawn(widget.landmark.id)!;
  late final int _day = int.parse(widget.landmark.id.split(':').last);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([commerce.raid(_zone, _day), commerce.raid(_zone, _day - 1)]);
      if (mounted) {
        setState(() {
          _today = r[0];
          _yesterday = r[1];
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _attack() async {
    final squad = await showModalBottomSheet<List<Kin>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TK.dusk,
      builder: (_) => const SquadPicker(title: 'Raid squad (up to 3)', action: 'Attack'),
    );
    if (squad == null || squad.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final mine = [for (final k in squad) fighterOf(k)];
      final hit = await commerce.attackRaid(location.position, [for (final k in squad) k.uid], mine);
      if (!mounted) return;
      final boss = species[_today!.species];
      final title = hit.felled ? 'BOSS DOWN 👑' : (copy.unhinged ? '-${hit.damage} HP. chip damage era' : '${hit.damage} damage');
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BattleScreen(
            heading: 'Raid · ${boss.name}',
            me: ReplaySide('You', [for (final k in squad) k.species], mine),
            them: ReplaySide('Raid boss', [boss], [hit.boss]),
            meAttacked: true,
            result: hit.result,
            won: hit.felled,
            title: title,
            subtitle: hit.felled
                ? 'You landed the final blow: a Crown Orb is yours, and everyone who hit it gets an Aurora Orb.'
                : 'Boss at ${hit.hpBefore - hit.damage}/${_today!.hpMax} HP. Your share of the pot grows with your damage.',
            hash: hit.hash,
            share: MemeCardData(
              headline: title,
              subtitle: '@${chain.name} vs the ${boss.name} raid boss',
              art: boss.sprite,
              accent: Grade.mythic.color,
              chips: ['${hit.damage} damage', 'Landmark raid', 'on Monad'],
              footer: '@${chain.name}',
              shareText: hit.felled ? 'Took down a Terrakin raid boss 👑 #Terrakin #Monad' : 'Raiding on Terrakin ⚔️ #Terrakin',
            ),
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claim(RaidState r) async {
    setState(() => _busy = true);
    try {
      await commerce.claimRaid(r.zone, r.day);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _today;
    final y = _yesterday;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: r == null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: _error == null
                      ? const CircularProgressIndicator(color: TK.signal)
                      : Text(_error!, style: TK.body(13, color: TK.danger)),
                ),
              )
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Image.asset(species[r.species].sprite, width: 64, height: 64),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Raid boss: ${species[r.species].name}', style: TK.display(20)),
                      Text('At this Landmark, today only. Everyone shares one HP bar.',
                          style: TK.body(12, color: TK.mist)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: r.hpLeft / r.hpMax,
                    minHeight: 16,
                    backgroundColor: TK.slate,
                    color: TK.danger,
                  ),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  Text(r.cleared ? 'Felled!' : '${r.hpLeft}/${r.hpMax} HP', style: TK.body(12, bold: true)),
                  const Spacer(),
                  Text('Pot ${fmtMon(r.pot)}', style: TK.body(12, color: TK.signal, bold: true)),
                ]),
                if (r.myDamage > 0)
                  Text(
                    'Your damage ${r.myDamage} (${(r.myDamage * 100 / r.totalDamage).toStringAsFixed(1)}% of the pot)',
                    style: TK.body(12, color: TK.mist),
                  ),
                const SizedBox(height: 12),
                if (!r.cleared)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy || collection.all.isEmpty ? null : _attack,
                      child: Text(_busy ? 'Fighting on Monad…' : 'Attack · 0.01 MON entry'),
                    ),
                  ),
                if (r.cleared && r.myDamage > 0 && !r.claimed)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: _busy ? null : () => _claim(r), child: const Text('Claim loot + Aurora Orb')),
                  ),
                if (y != null && y.myDamage > 0 && !y.claimed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _claim(y),
                      child: Text('Claim yesterday\'s loot (${fmtMon(y.pot * BigInt.from(y.myDamage) ~/ BigInt.from(y.totalDamage))})'),
                    ),
                  ),
                Text('You need to be within 150 m of the Landmark to attack.', style: TK.body(11, color: TK.mist)),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: TK.body(12, color: TK.danger)),
                  ),
              ]),
      ),
    );
  }
}
