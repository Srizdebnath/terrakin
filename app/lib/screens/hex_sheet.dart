import 'package:flutter/material.dart';

import '../app_state.dart';
import '../chain/territory.dart';
import '../core/battle.dart';
import '../core/copy.dart';
import '../core/sound.dart';
import '../core/economy.dart';
import '../core/hexgrid.dart';
import '../core/species.dart';
import '../core/theme.dart';
import '../data/collection.dart';
import '../data/spawn_engine.dart';
import '../widgets/kin_widgets.dart';
import '../widgets/meme_card.dart';
import 'battle_screen.dart';

/// Stable colour for a hex holder, from their address.
Color holderColor(String owner) {
  final h = int.parse(owner.substring(2, 8), radix: 16) % 360;
  return HSLColor.fromAHSL(1, h.toDouble(), 0.7, 0.58).toColor();
}

/// A collection Kin as it would fight for its owner.
Fighter fighterOf(Kin k, {bool home = false}) => Fighter.of(
      species.indexOf(k.species),
      k.grade.index,
      k.genes.vigor.toList(),
      [for (final m in k.tradeMods) (m * 10000).round()],
      home: home,
    );

String _countdown(Duration d) =>
    d.inHours > 0 ? '${d.inHours}h ${d.inMinutes % 60}m' : '${d.inMinutes}m ${d.inSeconds % 60}s';

/// The hex under the player: who holds it, its defenders, and claim / attack /
/// defend; plus tomorrow's auction for the Landmark zone around it.
class HexSheet extends StatefulWidget {
  const HexSheet({super.key});

  @override
  State<HexSheet> createState() => _HexSheetState();
}

class _HexSheetState extends State<HexSheet> {
  HexDetail? _hex;
  Auction? _auction, _today;
  (int, Spawn)? _landmark;
  String? _error, _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = location.position;
    final id = HexGrid.idAt(p);
    try {
      if (territory.prices == null) await territory.refresh();
      final lm = TerritoryService.tomorrowsLandmark(p);
      final day = TerritoryService.utcDay(DateTime.now());
      final r = await Future.wait([
        territory.detail(id),
        if (lm != null) territory.auction(lm.$1, day + 1),
        if (lm != null) territory.auction(lm.$1, day),
      ]);
      if (!mounted) return;
      setState(() {
        _hex = r[0] as HexDetail;
        _landmark = lm;
        if (lm != null) {
          _auction = r[1] as Auction;
          _today = r[2] as Auction;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    setState(() {
      _busy = label;
      _error = null;
    });
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<List<Kin>?> _pickSquad(String title, String action) => showModalBottomSheet<List<Kin>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: TK.dusk,
        builder: (_) => SquadPicker(title: title, action: action),
      );

  Future<void> _claim() async {
    final squad = await _pickSquad('Pick up to 3 defenders', 'Claim');
    if (squad == null || squad.isEmpty) return;
    await _run('Claiming…', () async {
      await territory.claim(location.position, [for (final k in squad) k.uid]);
      sound.play(Sfx.claim);
      if (!mounted) return;
      final line = copy.claimed();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(line),
        action: SnackBarAction(
          label: 'Share',
          onPressed: () => showMemeCard(
            context,
            MemeCardData(
              headline: line,
              subtitle: '@${chain.name} now owns a hex',
              art: squad.first.species.sprite,
              accent: TK.signal,
              chips: ['${territory.mine.length} hexes', '${territory.prices!.cutBps ~/ 100}% of every catch'],
              footer: weather.place == null ? '@${chain.name}' : '@${chain.name} · ${weather.place}',
              shareText: 'Claimed my turf on Terrakin 🏴 #Terrakin #Monad',
            ),
          ),
        ),
      ));
    });
  }

  Future<void> _station(HexDetail h) async {
    final squad = await _pickSquad('New defenders', 'Station');
    if (squad == null || squad.isEmpty) return;
    await _run('Stationing…', () => territory.station(h.id, [for (final k in squad) k.uid]));
  }

  Future<void> _attack(HexDetail h) async {
    final squad = await _pickSquad('Pick your squad (up to 3)', 'Attack');
    if (squad == null || squad.isEmpty) return;
    await _run('Battling on Monad…', () async {
      final out = await territory.attack(
          location.position, [for (final k in squad) k.uid], [for (final k in squad) fighterOf(k)], h.defenders);
      if (!mounted) return;
      final title = out.won ? copy.captured() : copy.defended();
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BattleScreen(
            heading: 'Hex battle',
            me: ReplaySide('You', [for (final k in squad) k.species], out.attackers),
            them: ReplaySide('@${h.ownerName}', [for (final d in out.defenders) species[d.species]],
                [for (final d in out.defenders) d.fighter]),
            meAttacked: true,
            result: out.result,
            won: out.won,
            title: title,
            subtitle: out.won ? copy.capturedSub() : copy.defendedSub(h.ownerName),
            hash: out.hash,
            share: MemeCardData(
              headline: title,
              subtitle: out.won ? '@${chain.name} took @${h.ownerName}\'s hex' : '@${h.ownerName}\'s hex held',
              art: squad.first.species.sprite,
              accent: out.won ? TK.signal : TK.danger,
              chips: ['${out.result.turns} turns', '${out.result.hpLeft} HP left', '${territory.mine.length} hexes'],
              footer: chain.txUrl(out.hash).replaceFirst('https://', ''),
              shareText: out.won
                  ? 'Took a hex on Terrakin 🏴 settled on Monad: ${chain.txUrl(out.hash)} #Terrakin'
                  : 'Got cooked attacking a hex on Terrakin 💀 #Terrakin',
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([territory, chain]),
        builder: (context, _) {
          final h = _hex;
          final prices = territory.prices;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (h == null || prices == null)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: _error == null
                              ? const CircularProgressIndicator(color: TK.signal)
                              : Text(_error!, style: TK.body(13, color: TK.danger)),
                        ),
                      )
                    else ...[
                      _header(h),
                      const SizedBox(height: 14),
                      _defenders(h),
                      const SizedBox(height: 14),
                      _actions(h, prices),
                      if (_landmark != null && _auction != null) ...[
                        const SizedBox(height: 20),
                        _auctionCard(prices),
                      ],
                      if (territory.refunds > BigInt.zero) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _busy != null ? null : () => _run('Withdrawing…', territory.withdrawRefund),
                          icon: const Icon(Icons.undo_rounded),
                          label: Text(copy.withdrawOutbid(fmtMon(territory.refunds))),
                        ),
                      ],
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(_error!, style: TK.body(13, color: TK.danger)),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );

  Widget _header(HexDetail h) {
    final s = h.state;
    final mine = territory.isMine(s);
    final colour = s.owner == null ? TK.slate : holderColor(s.owner!);
    final c = HexGrid.center(h.id);
    return Row(children: [
      Icon(Icons.hexagon_rounded, color: mine ? TK.signal : colour, size: 40),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            s.owner == null
                ? 'Unclaimed hex'
                : (mine ? 'Your hex' : '@${h.ownerName}${_tag(s.owner!)}\'s hex'),
            style: TK.display(22),
          ),
          Text(
            '${c.latitude.toStringAsFixed(4)}, ${c.longitude.toStringAsFixed(4)}'
            '${h.since != null ? ' · held since ${_ago(h.since!)}' : ''}',
            style: TK.body(12, color: TK.mist),
          ),
        ]),
      ),
      if (s.shielded) Tag('Shield ${_countdown(s.shieldUntil.difference(DateTime.now()))}', icon: Icons.shield_rounded, dark: true),
    ]);
  }

  String _tag(String owner) {
    final t = social.tagOf(social.crewOfOwner[owner] ?? 0);
    return t == null ? '' : ' [$t]';
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inDays > 0) return '${d.inDays}d ago';
    if (d.inHours > 0) return '${d.inHours}h ago';
    return '${d.inMinutes}m ago';
  }

  Widget _defenders(HexDetail h) {
    if (h.state.owner == null) {
      return Text(
        'Stand here and claim it. You\'ll take ${territory.prices!.cutBps ~/ 100}% of every catch reward '
        'anyone earns in this hex.',
        style: TK.body(13, color: TK.mist),
      );
    }
    if (h.defenders.isEmpty) {
      return Text('No defenders! Any Kin can take this hex.', style: TK.body(13, color: TK.signal, bold: true));
    }
    return Row(children: [
      for (final d in h.defenders)
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: TK.night, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Image.asset(species[d.species].sprite, width: 48, height: 48),
              Text(species[d.species].name, style: TK.body(12, bold: true)),
              Text(Grade.values[d.grade].label, style: TK.body(10, color: Grade.values[d.grade].color)),
              const SizedBox(height: 4),
              Text('HP ${d.fighter.hp} · ATK ${d.fighter.atk}', style: TK.body(10, color: TK.mist)),
              Text('DEF ${d.fighter.def} · SPD ${d.fighter.spd}', style: TK.body(10, color: TK.mist)),
            ]),
          ),
        ),
    ]);
  }

  Widget _actions(HexDetail h, TerritoryPrices prices) {
    final s = h.state;
    final busy = _busy != null;
    Widget button(String label, VoidCallback? onTap) => SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: busy ? null : onTap,
            child: busy
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: TK.ink)),
                    const SizedBox(width: 10),
                    Text(_busy!),
                  ])
                : Text(label),
          ),
        );
    final noKin = collection.all.isEmpty;
    if (noKin) return Text('Bond a Kin first: hexes are held by Kin.', style: TK.body(13, color: TK.mist));
    if (s.owner == null) return button('Claim · ${fmtMon(prices.claim)}', _claim);
    if (territory.isMine(s)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('You take ${prices.cutBps ~/ 100}% of every catch reward here.', style: TK.body(13, color: TK.mist)),
        const SizedBox(height: 8),
        button('Change defenders', () => _station(h)),
      ]);
    }
    if (social.isAlly(s.owner!)) {
      return Text('A crewmate holds this hex. It counts toward your crew\'s turf.',
          style: TK.body(13, color: TK.mist));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'Beat the defenders in an on-chain battle to take the hex. If you lose, '
        'your ${fmtMon(prices.attackFee)} fee goes to @${h.ownerName}.',
        style: TK.body(13, color: TK.mist),
      ),
      const SizedBox(height: 8),
      button(s.shielded ? copy.shieldedBtn() : 'Attack · ${fmtMon(prices.attackFee)}', s.shielded ? null : () => _attack(h)),
    ]);
  }

  Widget _auctionCard(TerritoryPrices prices) {
    final a = _auction!;
    final today = _today;
    final spawn = _landmark!.$2;
    final min = territory.minimumBid(a);
    final mine = a.bidder != null && a.bidder == chain.address?.toLowerCase();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TK.night,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TK.signal.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.gavel_rounded, color: TK.signal, size: 20),
          const SizedBox(width: 8),
          Text('Landmark zone auction', style: TK.display(17)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Image.asset(spawn.species.sprite, width: 40, height: 40),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tomorrow: ${spawn.grade.label} ${spawn.species.name}. The winner takes '
              '${prices.landmarkCutBps ~/ 100}% of every Landmark catch in this zone all day.',
              style: TK.body(12, color: TK.mist),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text(
              a.bidder == null ? 'No bids yet' : 'Top bid ${fmtMon(a.amount)} by ${mine ? 'you' : '@${a.bidderName}'}',
              style: TK.body(13, bold: true),
            ),
          ),
          if (a.amount >= BigInt.from(5) * BigInt.from(10).pow(16)) Tag(copy.whale(), dark: true), // 0.05 MON+
        ]),
        if (!mine && territory.refunds > BigInt.zero) Text(copy.outbid(), style: TK.body(11, color: TK.danger)),
        if (today?.bidder != null)
          Text('Today\'s winner: @${today!.bidderName}', style: TK.body(11, color: TK.mist)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _busy != null || mine
                ? null
                : () => _run('Bidding…', () => territory.bid(a.zone, a.day, min)),
            child: Text(mine ? copy.winningBid() : 'Bid ${fmtMon(min)}'),
          ),
        ),
      ]),
    );
  }
}

/// Pick up to [max] Kin, strongest first.
class SquadPicker extends StatefulWidget {
  const SquadPicker({super.key, required this.title, required this.action, this.max = 3, this.exact = false});
  final String title, action;
  final int max;

  /// Require exactly [max] picks.
  final bool exact;

  @override
  State<SquadPicker> createState() => _SquadPickerState();
}

class _SquadPickerState extends State<SquadPicker> {
  final _picked = <Kin>[];

  @override
  Widget build(BuildContext context) {
    int power(Kin k) {
      final f = fighterOf(k);
      return f.hp ~/ 2 + f.atk * 2 + f.def + f.spd;
    }

    final all = [...collection.all]..sort((a, b) => power(b).compareTo(power(a)));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Row(children: [
              Expanded(child: Text(widget.title, style: TK.display(20))),
              Text('${_picked.length}/${widget.max}', style: TK.body(14, color: TK.signal, bold: true)),
            ]),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final k in all)
                  () {
                    final f = fighterOf(k);
                    final order = _picked.indexOf(k);
                    return ListTile(
                      leading: Image.asset(k.species.sprite, width: 44, height: 44),
                      title: Text('${k.grade.label} ${k.species.name}', style: TK.body(14, bold: true)),
                      subtitle: Text('HP ${f.hp} · ATK ${f.atk} · DEF ${f.def} · SPD ${f.spd}',
                          style: TK.body(12, color: TK.mist)),
                      trailing: order >= 0
                          ? CircleAvatar(
                              radius: 13,
                              backgroundColor: TK.signal,
                              child: Text('${order + 1}', style: TK.body(12, color: TK.ink, bold: true)))
                          : const Icon(Icons.add_circle_outline_rounded, color: TK.mist),
                      onTap: () => setState(() {
                        if (order >= 0) {
                          _picked.remove(k);
                        } else if (_picked.length < widget.max) {
                          _picked.add(k);
                        }
                      }),
                    );
                  }(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _picked.isEmpty || (widget.exact && _picked.length < widget.max)
                    ? null
                    : () => Navigator.pop(context, _picked),
                child: Text(_picked.isEmpty
                    ? 'Pick ${widget.exact ? widget.max : 'at least one'}'
                    : widget.exact && _picked.length < widget.max
                        ? 'Pick ${widget.max - _picked.length} more'
                        : '${widget.action} with ${_picked.length}'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
