import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../app_state.dart';
import '../chain/commerce.dart';
import '../core/economy.dart';
import '../core/sound.dart';
import '../core/species.dart';
import '../core/theme.dart';
import '../data/collection.dart';
import '../widgets/kin_widgets.dart';
import 'hex_sheet.dart';

BigInt _wei(double mon) => BigInt.from((mon * 1e6).round()) * BigInt.from(10).pow(12);

String _left(DateTime t) {
  final d = t.difference(DateTime.now());
  if (d.isNegative) return 'expired';
  return d.inDays > 0 ? '${d.inDays}d ${d.inHours % 24}h left' : '${d.inHours}h ${d.inMinutes % 60}m left';
}

Future<void> _act(BuildContext context, Future<void> Function() f, {String? done}) async {
  final m = ScaffoldMessenger.of(context);
  try {
    await f();
    if (done != null) {
      sound.play(Sfx.coin);
      m.showSnackBar(SnackBar(content: Text(done)));
    }
  } catch (e) {
    m.showSnackBar(SnackBar(content: Text(e.toString())));
  }
}

/// Peer-to-peer Kin market and the bounty board.
class BazaarScreen extends StatefulWidget {
  const BazaarScreen({super.key});

  @override
  State<BazaarScreen> createState() => _BazaarScreenState();
}

class _BazaarScreenState extends State<BazaarScreen> {
  @override
  void initState() {
    super.initState();
    commerce.refreshMarket().catchError((Object _) {});
    commerce.refreshBounties().catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: TK.night,
          appBar: AppBar(
            backgroundColor: TK.night,
            title: Text('Bazaar', style: TK.display(22)),
            bottom: const TabBar(
              indicatorColor: TK.signal,
              labelColor: TK.signal,
              unselectedLabelColor: TK.mist,
              tabs: [Tab(text: 'Kin market'), Tab(text: 'Bounties')],
            ),
          ),
          body: ListenableBuilder(
            listenable: Listenable.merge([commerce, collection]),
            builder: (context, _) => const TabBarView(children: [_MarketTab(), _BountyTab()]),
          ),
        ),
      );
}

// ---- Market -----------------------------------------------------------------

class _MarketTab extends StatelessWidget {
  const _MarketTab();

  Future<void> _sell(BuildContext context) async {
    final picked = await showModalBottomSheet<List<Kin>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TK.dusk,
      builder: (_) => const SquadPicker(title: 'Pick a Kin to sell', action: 'Sell', max: 1, exact: true),
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    final price = await showDialog<double>(context: context, builder: (_) => _PriceDialog(picked.first));
    if (price == null || !context.mounted) return;
    await _act(context, () => commerce.list(picked.first.uid, _wei(price)), done: 'Listed for ${price.toString()} MON');
  }

  @override
  Widget build(BuildContext context) {
    final me = chain.address?.toLowerCase();
    return RefreshIndicator(
      onRefresh: commerce.refreshMarket,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Buy and sell Kin with anyone. 3% of each sale goes to the reward pool.',
            style: TK.body(13, color: TK.mist)),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: collection.all.isEmpty ? null : () => _sell(context),
          icon: const Icon(Icons.sell_rounded),
          label: const Text('Sell a Kin'),
        ),
        if (commerce.proceeds > BigInt.zero)
          OutlinedButton(
            onPressed: () => _act(context, commerce.withdrawProceeds, done: 'Withdrawn'),
            child: Text('Withdraw ${fmtMon(commerce.proceeds)} from sales'),
          ),
        const SizedBox(height: 12),
        if (commerce.listings.isEmpty) Text('Nothing listed yet.', style: TK.body(13, color: TK.mist)),
        for (final l in commerce.listings)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: TK.dusk, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Image.asset(species[l.species].sprite, width: 52, height: 52),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${Grade.values[l.grade].label} ${species[l.species].name}',
                      style: TK.body(14, bold: true, color: Grade.values[l.grade].color)),
                  Text('HP ${l.fighter.hp} · ATK ${l.fighter.atk} · DEF ${l.fighter.def} · SPD ${l.fighter.spd}',
                      style: TK.body(11, color: TK.mist)),
                  Text(l.seller == me ? 'Your listing' : 'by @${l.sellerName}', style: TK.body(11, color: TK.mist)),
                ]),
              ),
              l.seller == me
                  ? TextButton(onPressed: () => _act(context, () => commerce.delist(l.kinId)), child: const Text('Delist'))
                  : FilledButton(
                      onPressed: () => _act(context, () => commerce.buy(l), done: 'Bought! It\'s in your Atlas.'),
                      child: Text(fmtMon(l.price)),
                    ),
            ]),
          ),
      ]),
    );
  }
}

class _PriceDialog extends StatefulWidget {
  const _PriceDialog(this.kin);
  final Kin kin;
  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  final _c = TextEditingController(text: '0.1');

  @override
  Widget build(BuildContext context) {
    final v = double.tryParse(_c.text);
    return AlertDialog(
      backgroundColor: TK.dusk,
      title: Text('Price for ${widget.kin.grade.label} ${widget.kin.species.name}', style: TK.display(18)),
      content: TextField(
        controller: _c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(suffixText: 'MON'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: v == null || v <= 0 ? null : () => Navigator.pop(context, v),
          child: const Text('List it'),
        ),
      ],
    );
  }
}

// ---- Bounties -----------------------------------------------------------------

class _BountyTab extends StatelessWidget {
  const _BountyTab();

  Future<void> _claim(BuildContext context, Bounty b) async {
    // Only offer Kin the contract will accept.
    final candidates = <Kin>[];
    for (final k in collection.all) {
      if (await commerce.matches(b, k.uid)) candidates.add(k);
    }
    if (!context.mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('None of your Kin match yet: it must be caught inside the circle after the bounty went up.')));
      return;
    }
    final k = candidates.first;
    await _act(context, () => commerce.claimBounty(b, k.uid),
        done: 'Delivered your ${k.species.name}: +${fmtMon(b.reward * BigInt.from(97) ~/ BigInt.from(100))}');
  }

  @override
  Widget build(BuildContext context) {
    final me = chain.address?.toLowerCase();
    const dist = Distance();
    return RefreshIndicator(
      onRefresh: commerce.refreshBounties,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Post MON for a Kin caught somewhere. The first hunter to deliver one wins it (3% fee).',
            style: TK.body(13, color: TK.mist)),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: TK.dusk,
            builder: (_) => const _PostBounty(),
          ),
          icon: const Icon(Icons.campaign_rounded),
          label: const Text('Post a bounty'),
        ),
        const SizedBox(height: 12),
        if (commerce.bounties.isEmpty) Text('No bounties yet. Be the first.', style: TK.body(13, color: TK.mist)),
        for (final b in commerce.bounties)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TK.dusk,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: TK.signal.withValues(alpha: 0.35)),
            ),
            child: Row(children: [
              b.species == 255
                  ? const SizedBox(width: 48, child: Icon(Icons.help_rounded, color: TK.mist, size: 36))
                  : Image.asset(species[b.species].sprite, width: 48, height: 48),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${Grade.values[b.minGrade].label}+ ${b.species == 255 ? 'any Kin' : species[b.species].name}',
                    style: TK.body(14, bold: true),
                  ),
                  Text(
                    'within ${b.radiusM >= 1000 ? '${(b.radiusM / 1000).toStringAsFixed(1)} km' : '${b.radiusM} m'} · '
                    '${fmtDistance(dist.as(LengthUnit.Meter, location.position, b.center))} from you',
                    style: TK.body(11, color: TK.mist),
                  ),
                  Text('${_left(b.deadline)} · by @${b.posterName}', style: TK.body(11, color: TK.mist)),
                ]),
              ),
              Column(children: [
                Text(fmtMon(b.reward), style: TK.body(14, color: TK.signal, bold: true)),
                if (b.poster == me)
                  TextButton(
                    onPressed: b.deadline.isBefore(DateTime.now())
                        ? () => _act(context, () => commerce.cancelBounty(b), done: 'Refunded')
                        : null,
                    child: const Text('Refund'),
                  )
                else
                  TextButton(onPressed: () => _claim(context, b), child: const Text('Deliver')),
              ]),
            ]),
          ),
      ]),
    );
  }
}

class _PostBounty extends StatefulWidget {
  const _PostBounty();
  @override
  State<_PostBounty> createState() => _PostBountyState();
}

class _PostBountyState extends State<_PostBounty> {
  int _species = 255, _grade = 2, _radius = 2000, _days = 3;
  double _reward = 0.1;
  bool _busy = false;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 12 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Post a bounty', style: TK.display(20)),
            const SizedBox(height: 4),
            Text('Centred on where you stand now.', style: TK.body(12, color: TK.mist)),
            const SizedBox(height: 12),
            SizedBox(
              height: 64,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final s in [255, ...List.generate(species.length, (i) => i)])
                  GestureDetector(
                    onTap: () => setState(() => _species = s),
                    child: Container(
                      width: 56,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: _species == s ? TK.signal.withValues(alpha: 0.25) : TK.night,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _species == s ? TK.signal : TK.slate),
                      ),
                      child: s == 255
                          ? Center(child: Text('Any', style: TK.body(12, bold: true)))
                          : Image.asset(species[s].sprite),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              for (final g in Grade.values)
                ChoiceChip(
                  label: Text('${g.label}+'),
                  selected: _grade == g.index,
                  onSelected: (_) => setState(() => _grade = g.index),
                ),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              for (final r in [500, 2000, 10000])
                ChoiceChip(
                  label: Text(r >= 1000 ? '${r ~/ 1000} km' : '$r m'),
                  selected: _radius == r,
                  onSelected: (_) => setState(() => _radius = r),
                ),
              for (final d in [1, 3, 7])
                ChoiceChip(label: Text('${d}d'), selected: _days == d, onSelected: (_) => setState(() => _days = d)),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              for (final m in [0.05, 0.1, 0.5, 1.0])
                ChoiceChip(label: Text('$m MON'), selected: _reward == m, onSelected: (_) => setState(() => _reward = m)),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        final nav = Navigator.of(context);
                        await _act(
                          context,
                          () => commerce.postBounty(
                            species: _species,
                            minGrade: _grade,
                            center: location.position,
                            radiusM: _radius,
                            within: Duration(days: _days),
                            reward: _wei(_reward),
                          ),
                          done: 'Bounty posted',
                        );
                        if (mounted) nav.pop();
                      },
                child: Text('Post · $_reward MON'),
              ),
            ),
          ]),
        ),
      );
}
