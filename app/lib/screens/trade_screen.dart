import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_state.dart';
import '../core/trade_rules.dart';
import '../core/theme.dart';
import '../data/collection.dart';
import '../trade/nearby_link.dart';
import '../trade/trade_session.dart';
import '../widgets/kin_widgets.dart';

/// Kin trading: find a player standing next to you, put up a Kin each, both
/// lock in within 8 m, and the swapped Kin arrive with shaken-up stats.
class TradeScreen extends StatefulWidget {
  const TradeScreen({super.key});

  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen> {
  final _link = NearbyLink();
  TradeSession? _session;

  @override
  void initState() {
    super.initState();
    _link.addListener(_onLink);
    _link.start(TradeSession.myName);
  }

  @override
  void dispose() {
    _link.removeListener(_onLink);
    _session?.dispose();
    _link.stop();
    _link.dispose();
    super.dispose();
  }

  void _onLink() {
    final p = _link.peer;
    if (p != null && _session == null) {
      _session = TradeSession(p);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _session?.leave();
      },
      child: Scaffold(
        appBar: AppBar(backgroundColor: TK.night, title: Text('Trade Kin', style: TK.display(22))),
        body: s == null
            ? _searching()
            : ListenableBuilder(
                listenable: Listenable.merge([s, location]),
                builder: (_, _) => s.result != null ? _resultView(s.result!, s) : _table(s),
              ),
      ),
    );
  }

  // ---- 1. Finding someone ---------------------------------------------------

  Widget _searching() {
    final incoming = _link.incoming;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _rules(),
        const SizedBox(height: 20),
        if (!location.live)
          _banner(Icons.gps_off_rounded, 'Trading needs live GPS so we can check you are within '
              '${tradeRangeMetres.round()} m. Turn on location and step outside.', TK.danger),
        if (_link.error != null)
          _banner(Icons.error_outline_rounded, _link.error!, TK.danger,
              action: _link.permanentlyDenied ? ('Open settings', openAppSettings) : ('Try again', () => _link.start(TradeSession.myName))),
        if (incoming != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TK.paper,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: TK.signal, width: 3),
            ),
            child: Column(children: [
              Text('${incoming.$2} wants to trade', style: TK.display(20, color: TK.ink)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: _link.declineIncoming, child: const Text('Decline'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: _link.acceptIncoming, child: const Text('Accept'))),
              ]),
            ]),
          ),
        Row(children: [
          if (_link.running)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: TK.signal)),
          const SizedBox(width: 10),
          Text(_link.running ? 'Looking for Wayfinders nearby…' : 'Not searching', style: TK.display(17)),
        ]),
        const SizedBox(height: 4),
        Text('Ask your friend to open Trade too. You are visible as ${TradeSession.myName}.',
            style: TK.body(12, color: TK.mist)),
        const SizedBox(height: 12),
        for (final e in _link.found.entries)
          Card(
            color: TK.dusk,
            child: ListTile(
              leading: const Icon(Icons.person_pin_circle_rounded, color: TK.signal, size: 32),
              title: Text(e.value, style: TK.display(17)),
              subtitle: Text('Close by', style: TK.body(12, color: TK.mist)),
              trailing: FilledButton(onPressed: () => _link.connect(e.key), child: const Text('Trade')),
            ),
          ),
        if (_link.found.isEmpty && _link.running)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Nobody yet. Keep both phones unlocked with Trade open.',
                style: TK.body(13, color: TK.mist)),
          ),
      ],
    );
  }

  Widget _rules() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: TK.dusk, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.swap_horiz_rounded, color: TK.signal),
            const SizedBox(width: 8),
            Text('How trading works', style: TK.display(17)),
          ]),
          const SizedBox(height: 8),
          Text(
            '• Stand within ${tradeRangeMetres.round()} m of the other player (checked with both phones\' GPS).\n'
            '• Each of you puts up one Kin, then both lock in. The swap settles on Monad: '
            'one of you proposes, the other accepts, and both Kin change hands at once.\n'
            '• The journey shakes a traded Kin: HP, ATK, DEF and SPD each shift by up to '
            '±${(tradeSwing * 100).round()}%, up or down. Over many trades a stat stays within '
            '${((modFloor - 1) * 100).round()}% to +${((modCeil - 1) * 100).round()}%.',
            style: TK.body(13, color: TK.mist),
          ),
        ]),
      );

  Widget _banner(IconData icon, String text, Color color, {(String, VoidCallback)? action}) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color),
        ),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TK.body(13, bold: true))),
          if (action != null) TextButton(onPressed: action.$2, child: Text(action.$1)),
        ]),
      );

  // ---- 2. The trade table ---------------------------------------------------

  Widget _table(TradeSession s) {
    final d = s.distance;
    final allowance = gpsAllowance(location.accuracy, s.partnerAccuracy);
    final ended = s.endedReason;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          AvatarView(s.partnerStyle, size: 70),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.partnerName ?? 'Connecting…', style: TK.display(20)),
              const SizedBox(height: 4),
              _distanceMeter(d, s.inRange, allowance),
            ]),
          ),
        ]),
        if (ended != null) ...[
          const SizedBox(height: 12),
          _banner(Icons.link_off_rounded, ended, TK.danger),
        ],
        if (s.settling != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: TK.signal)),
            const SizedBox(width: 8),
            Expanded(child: Text(s.settling!, style: TK.body(13, color: TK.signal, bold: true))),
          ]),
        ],
        if (s.notice != null && ended == null) ...[
          const SizedBox(height: 10),
          Text(s.notice!, style: TK.body(12, color: TK.signal, bold: true)),
        ],
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _offerSlot('You give', s.myOffer, s.myLock,
                onTap: s.myLock || s.busy ? null : () => _pickKin(s)),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Icon(Icons.swap_horiz_rounded, color: TK.signal, size: 30),
          ),
          Expanded(child: _offerSlot('You get', s.theirOffer, s.theirLock)),
        ]),
        const SizedBox(height: 14),
        Text(
          'Stats shown are before the trade. Each will shift by up to ±${(tradeSwing * 100).round()}% when it arrives.',
          style: TK.body(12, color: TK.mist),
        ),
        const SizedBox(height: 14),
        if (ended == null)
          s.myLock
              ? OutlinedButton(
                  onPressed: s.theirLock ? null : s.unlock,
                  child: Text(s.theirLock ? 'Trading…' : 'Locked in · waiting for ${s.partnerName ?? 'partner'} (tap to unlock)'),
                )
              : FilledButton(
                  onPressed: s.canLock ? s.lock : null,
                  child: Text(s.myOffer == null
                      ? 'Choose a Kin to give'
                      : s.theirOffer == null
                          ? 'Waiting for their offer'
                          : !s.inRange
                              ? 'Get within ${tradeRangeMetres.round()} m to trade'
                              : 'Lock in trade'),
                )
        else
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
      ],
    );
  }

  Widget _distanceMeter(double? d, bool ok, double allowance) {
    if (d == null) return Text('Measuring distance…', style: TK.body(12, color: TK.mist));
    final color = ok ? const Color(0xFF5FBF6A) : TK.danger;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.directions_walk_rounded, size: 16, color: color),
        const SizedBox(width: 6),
        Text('${d.toStringAsFixed(1)} m apart', style: TK.body(13, color: color, bold: true)),
        Text('  (need ≤ ${tradeRangeMetres.round()} m)', style: TK.body(11, color: TK.mist)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: (1 - d / 40).clamp(0.02, 1.0),
          minHeight: 6,
          color: color,
          backgroundColor: TK.slate,
        ),
      ),
      const SizedBox(height: 2),
      Text('GPS ±${location.accuracy.round()} m here · +${allowance.toStringAsFixed(1)} m slack for GPS error',
          style: TK.body(10, color: TK.mist)),
    ]);
  }

  Widget _offerSlot(String title, Kin? k, bool locked, {VoidCallback? onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 260),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: k == null ? TK.dusk : TK.paper,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: locked ? TK.signal : (k?.grade.color ?? TK.slate), width: locked ? 4 : 2),
          ),
          child: Column(children: [
            Row(children: [
              Text(title, style: TK.body(12, color: k == null ? TK.mist : TK.ink, bold: true)),
              const Spacer(),
              if (locked) const Icon(Icons.lock_rounded, size: 16, color: TK.signal),
            ]),
            if (k == null) ...[
              const SizedBox(height: 70),
              Icon(onTap != null ? Icons.add_circle_outline_rounded : Icons.hourglass_empty_rounded,
                  color: TK.mist, size: 36),
              const SizedBox(height: 6),
              Text(onTap != null ? 'Tap to choose' : 'Waiting…', style: TK.body(12, color: TK.mist)),
            ] else ...[
              Image.asset(k.species.sprite, width: 90, height: 90),
              Text(k.species.name, style: TK.display(18, color: TK.ink)),
              const SizedBox(height: 2),
              GradeGems(k.grade, size: 12),
              const SizedBox(height: 4),
              Text('Lv ${k.level} · ${k.genes.trait.label}', style: TK.body(11, color: TK.ink.withValues(alpha: 0.7))),
              const SizedBox(height: 6),
              StatPanel(k.stats, color: k.species.affinity.shade),
              if (k.trades > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Traded ${k.trades}×', style: TK.body(10, color: TK.ink.withValues(alpha: 0.6))),
                ),
            ],
          ]),
        ),
      );

  void _pickKin(TradeSession s) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: TK.dusk,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('Choose a Kin to give', style: TK.display(20)),
          ),
          if (collection.all.isEmpty)
            Padding(padding: const EdgeInsets.all(16), child: Text('You have no Kin yet.', style: TK.body(14))),
          for (final k in collection.all)
            ListTile(
              onTap: () {
                Navigator.pop(ctx);
                s.offer(k);
              },
              leading: Image.asset(k.species.sprite, width: 44),
              title: Text('${k.species.name}  Lv ${k.level}', style: TK.display(16)),
              subtitle: Row(children: [
                GradeGems(k.grade, size: 12),
                const SizedBox(width: 6),
                if (profile.buddyUid == k.uid) Text('buddy', style: TK.body(11, color: TK.signal, bold: true)),
              ]),
              trailing: Text('${k.power}', style: TK.display(18, color: TK.signal)),
            ),
        ],
      ),
    );
  }

  // ---- 3. Result ------------------------------------------------------------

  Widget _resultView(TradeResult r, TradeSession s) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: Text('Trade complete!', style: TK.display(30, color: TK.signal))),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'With ${s.partnerName ?? 'your partner'} · settled on Monad '
              '(${shortAddress(r.txHash)}) · trade reward paid for your first '
              '${chain.prices?.tradesPerDay ?? 3} trades a day',
              textAlign: TextAlign.center,
              style: TK.body(13, color: TK.mist),
            ),
          ),
          const SizedBox(height: 16),
          _shiftCard('You received', r.gotBefore, r.gotAfter),
          const SizedBox(height: 12),
          _shiftCard('You gave', r.gaveBefore, r.gaveAfter, muted: true),
          const SizedBox(height: 20),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Back to the world')),
        ],
      );

  Widget _shiftCard(String title, Kin before, Kin? afterOrNull, {bool muted = false}) {
    final after = afterOrNull ?? before;
    final a = before.stats, b = after.stats;
    Widget row(String label, int x, int y) {
      final diff = y - x;
      final color = diff > 0 ? const Color(0xFF3E9150) : (diff < 0 ? TK.danger : TK.ink);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 40, child: Text(label, style: TK.body(13, color: TK.ink, bold: true))),
          Text('$x', style: TK.body(13, color: TK.ink.withValues(alpha: 0.6))),
          const Icon(Icons.arrow_right_alt_rounded, size: 18, color: TK.ink),
          Text('$y', style: TK.body(14, color: TK.ink, bold: true)),
          const SizedBox(width: 8),
          Icon(diff > 0 ? Icons.arrow_upward_rounded : (diff < 0 ? Icons.arrow_downward_rounded : Icons.remove_rounded),
              size: 15, color: color),
          Text(diff == 0 ? '' : '${diff > 0 ? '+' : ''}$diff', style: TK.body(13, color: color, bold: true)),
        ]),
      );
    }

    return Opacity(
      opacity: muted ? 0.75 : 1,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TK.paper,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: after.grade.color, width: 4),
        ),
        child: Row(children: [
          Column(children: [
            Text(title, style: TK.body(12, color: TK.ink, bold: true)),
            Image.asset(after.species.sprite, width: 96, height: 96),
            Text(after.species.name, style: TK.display(18, color: TK.ink)),
            GradeGems(after.grade, size: 12),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              row('HP', a.hp, b.hp),
              row('ATK', a.atk, b.atk),
              row('DEF', a.def, b.def),
              row('SPD', a.spd, b.spd),
              const Divider(height: 12),
              row('PWR', a.power, b.power),
            ]),
          ),
        ]),
      ),
    );
  }
}
