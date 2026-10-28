import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'bazaar_screen.dart';
import '../chain/game_chain.dart';
import '../core/economy.dart';
import '../core/species.dart';
import '../core/theme.dart';
import '../widgets/kin_widgets.dart';
import '../widgets/orb_painter.dart';
import 'mint_screen.dart';

/// Spend MON on orbs and characters (real Monad testnet transactions), see
/// how to earn more, and every transaction you sent.
class MarketScreen extends StatelessWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: TK.night,
          title: Text('Market', style: TK.display(22)),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BazaarScreen())),
              icon: const Icon(Icons.storefront_rounded),
              label: const Text('Bazaar'),
            ),
          ],
        ),
        body: ListenableBuilder(
          listenable: Listenable.merge([chain, profile]),
          builder: (context, _) {
            final p = chain.prices;
            return RefreshIndicator(
              onRefresh: chain.sync,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _balance(context),
                  const SizedBox(height: 20),
                  Text('Orbs', style: TK.display(20)),
                  const SizedBox(height: 4),
                  Text('Throw them to bond Kin. Thrown orbs are burned when the bond is sealed.',
                      style: TK.body(12, color: TK.mist)),
                  const SizedBox(height: 10),
                  if (p == null)
                    const Center(child: CircularProgressIndicator(color: TK.signal))
                  else
                    for (final o in Orb.values) _OrbRow(o, p.orb[o.index]),
                  const SizedBox(height: 16),
                  Text('Characters', style: TK.display(20)),
                  const SizedBox(height: 8),
                  Material(
                    color: TK.dusk,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MintScreen())),
                      leading: AvatarView(profile.style, size: 56, walking: false),
                      title: Text('Mint a new Wayfinder', style: TK.display(16)),
                      subtitle: Text(
                        '${profile.avatars.length} owned${p == null ? '' : ' · ${fmtMon(p.nextCharacter)} each'}',
                        style: TK.body(12, color: TK.mist),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: TK.mist),
                    ),
                  ),
                  if (p != null) ...[
                    const SizedBox(height: 20),
                    Text('Earn MON', style: TK.display(20)),
                    const SizedBox(height: 8),
                    _earnTable(p),
                  ],
                  const SizedBox(height: 20),
                  Text('Your transactions', style: TK.display(20)),
                  const SizedBox(height: 6),
                  if (chain.txs.isEmpty) Text('None yet.', style: TK.body(13, color: TK.mist)),
                  for (final t in chain.txs) _TxRow(t),
                ],
              ),
            );
          },
        ),
      );

  Widget _balance(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: TK.paper,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: TK.signal, width: 4),
        ),
        child: Row(children: [
          const Icon(Icons.account_balance_wallet_rounded, color: TK.ink, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fmtMon(chain.balance), style: TK.display(30, color: TK.ink)),
              GestureDetector(
                onTap: () => Clipboard.setData(ClipboardData(text: chain.address ?? '')),
                child: Text(
                  'Monad testnet · ${shortAddress(chain.address)} (tap to copy)',
                  style: TK.body(11, color: TK.ink.withValues(alpha: 0.6)),
                ),
              ),
              Text('Every action also pays a little gas.', style: TK.body(11, color: TK.ink.withValues(alpha: 0.6))),
            ]),
          ),
        ]),
      );

  Widget _earnTable(ChainPrices p) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: TK.dusk, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          for (final g in Grade.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                GradeGems(g, size: 13),
                const SizedBox(width: 8),
                Text('Bond a ${g.label}', style: TK.body(13)),
                const Spacer(),
                Text('+${fmtMon(p.catchReward[g.index])}', style: TK.body(13, color: TK.signal, bold: true)),
              ]),
            ),
          const Divider(color: TK.slate),
          Row(children: [
            const Icon(Icons.flag_rounded, size: 16, color: TK.signal),
            const SizedBox(width: 8),
            Text('Landmark Kin', style: TK.body(13)),
            const Spacer(),
            Text('double', style: TK.body(13, color: TK.signal, bold: true)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.swap_horiz_rounded, size: 16, color: TK.signal),
            const SizedBox(width: 8),
            Expanded(child: Text('Complete a trade (first ${p.tradesPerDay} a day)', style: TK.body(13))),
            Text('+${fmtMon(p.tradeReward)}', style: TK.body(13, color: TK.signal, bold: true)),
          ]),
        ]),
      );
}

class _TxRow extends StatelessWidget {
  const _TxRow(this.t);
  final TxRecord t;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: chain.txUrl(t.hash)));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: TK.dusk,
              content: Text('Explorer link copied', style: TK.body(14)),
            ));
          },
          child: Row(children: [
            const Icon(Icons.bolt_rounded, size: 16, color: TK.signal),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.memo, style: TK.body(13)),
                Text('${shortAddress(t.hash)} · confirmed in ${(t.confirmMs / 1000).toStringAsFixed(1)} s',
                    style: TK.body(11, color: TK.mist)),
              ]),
            ),
            Text('gas ${fmtMon(t.feeWei)}', style: TK.body(12, color: TK.mist)),
          ]),
        ),
      );
}

class _OrbRow extends StatefulWidget {
  const _OrbRow(this.orb, this.price);
  final Orb orb;
  final BigInt price;

  @override
  State<_OrbRow> createState() => _OrbRowState();
}

class _OrbRowState extends State<_OrbRow> {
  bool _busy = false;

  Future<void> _buy(int n) async {
    setState(() => _busy = true);
    String msg;
    try {
      final t = await chain.buyOrbs(widget.orb.index, n, widget.orb.label);
      msg = 'Bought $n× ${widget.orb.label} · confirmed in ${(t.confirmMs / 1000).toStringAsFixed(1)} s';
    } catch (e) {
      msg = e.toString();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(backgroundColor: TK.dusk, content: Text(msg, style: TK.body(14))));
  }

  @override
  Widget build(BuildContext context) {
    final orb = widget.orb;
    final have = profile.orbsLeft(orb);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TK.paper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: orb.top, width: 3),
      ),
      child: Row(children: [
        OrbIcon(orb, size: 56),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(orb.label, style: TK.display(18, color: TK.ink))),
              const SizedBox(width: 8),
              Text('×$have', style: TK.body(13, color: TK.ink.withValues(alpha: 0.6), bold: true)),
            ]),
            Text(orb.guaranteed ? 'Always bonds' : '${orb.catchMultiplier}× catch chance',
                style: TK.body(12, color: TK.ink, bold: true)),
            Text(orb.blurb, style: TK.body(12, color: TK.ink.withValues(alpha: 0.7))),
          ]),
        ),
        const SizedBox(width: 8),
        if (_busy)
          const SizedBox(width: 96, child: Center(child: CircularProgressIndicator(color: TK.ink)))
        else
          Column(children: [
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(96, 38), textStyle: TK.display(13, color: TK.ink)),
              onPressed: chain.balance >= widget.price ? () => _buy(1) : null,
              child: Text(fmtMon(widget.price)),
            ),
            if (orb != Orb.crown) ...[
              const SizedBox(height: 6),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(96, 34)),
                onPressed: chain.balance >= widget.price * BigInt.from(10) ? () => _buy(10) : null,
                child: Text('×10', style: TK.body(13, color: TK.ink, bold: true)),
              ),
            ],
          ]),
      ]),
    );
  }
}
