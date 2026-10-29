import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../chain/adventures.dart';
import '../core/economy.dart';
import '../core/sound.dart';
import '../core/species.dart';
import '../core/theme.dart';
import '../data/collection.dart';
import '../widgets/kin_widgets.dart';
import 'hex_sheet.dart';

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

String _countdown(Duration d) {
  if (d.isNegative) return 'now';
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

Widget _card({required Color accent, required IconData icon, required String title, required List<Widget> children}) =>
    Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TK.night,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: TK.display(19, color: accent))),
        ]),
        const SizedBox(height: 8),
        ...children,
      ]),
    );

/// The three things you can only do by being somewhere: Loop Capture,
/// Convergence and Dead Drops.
class AdventureSheet extends StatefulWidget {
  const AdventureSheet({super.key, required this.onStartLoop});

  /// Closes the sheet and starts recording a loop on the map.
  final VoidCallback onStartLoop;

  @override
  State<AdventureSheet> createState() => _AdventureSheetState();
}

class _AdventureSheetState extends State<AdventureSheet> {
  late final Timer _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    final p = location.position;
    adventures.refreshConvergences(p).catchError((Object _) {});
    adventures.refreshDrops(p).catchError((Object _) {});
    adventures.refreshMyDrops().catchError((Object _) {});
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: ListenableBuilder(
          listenable: adventures,
          builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 16), children: [
            Text('Adventures', style: TK.display(26)),
            Text('Things you can only do by actually being somewhere.', style: TK.body(13, color: TK.mist)),
            const SizedBox(height: 14),
            _loopCard(),
            _convergenceCard(context),
            _dropsCard(context),
          ]),
        ),
      ),
    );
  }

  Widget _loopCard() {
    final per = territory.prices?.loopPerHex;
    return _card(accent: TK.loop, icon: Icons.all_inclusive_rounded, title: 'Loop Capture', children: [
      Text(
        'Walk a closed loop through the real city. Every free hex on your trail and inside it becomes yours, '
        'and rivals\' undefended hexes inside get surrounded and flip to you. '
        'If a rival takes a hex on your trail before you close it, your loop is cut.',
        style: TK.body(13, color: TK.mist),
      ),
      const SizedBox(height: 6),
      Text(
        'At least 6 hexes, back to where you started, within 2 hours, on foot.'
        '${per == null ? '' : ' ${fmtMon(per)} per hex taken.'}',
        style: TK.body(12, color: TK.paper),
      ),
      const SizedBox(height: 10),
      if (adventures.looping)
        Row(children: [
          Expanded(
            child: Text('Walking: ${adventures.distinctHexes} hexes so far',
                style: TK.body(13, bold: true, color: TK.loop)),
          ),
          TextButton(onPressed: adventures.cancelLoop, child: const Text('Abandon')),
        ])
      else
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: TK.loop),
          onPressed: territory.enabled ? widget.onStartLoop : null,
          icon: const Icon(Icons.directions_walk_rounded),
          label: const Text('Start a loop here'),
        ),
    ]);
  }

  Widget _convergenceCard(BuildContext context) {
    final c = adventures.nextConvergence;
    final accent = Grade.mythic.color;
    return _card(accent: accent, icon: Icons.blur_circular_rounded, title: 'Convergence', children: [
      Text(
        'Once a day a Mythic appears at a real park near you for 20 minutes. Nobody can bond it alone: '
        'it answers only when ${Convergence.circle} or more players stand there within 5 minutes of each other. '
        'Everyone in the circle gets one.',
        style: TK.body(13, color: TK.mist),
      ),
      const SizedBox(height: 10),
      if (c == null)
        Text(
          adventures.convergences.isEmpty && chain.convergence.isNotEmpty
              ? 'No public park mapped in your area yet.'
              : 'Checking the schedule…',
          style: TK.body(13),
        )
      else
        InkWell(
          onTap: () => openConvergence(context, c),
          child: Row(children: [
            Image.asset(species[c.species].sprite, width: 52, height: 52),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Mythic ${species[c.species].name}', style: TK.body(14, bold: true, color: accent)),
                Text('${c.name} · ${fmtDistance(location.distanceTo(c.at))} ${compassPoint(location.position, c.at)}',
                    style: TK.body(12)),
                Text(
                  c.open
                      ? 'OPEN NOW · closes in ${_countdown(c.closesAt.difference(DateTime.now()))}'
                      : 'Opens in ${_countdown(c.opensAt.difference(DateTime.now()))}',
                  style: TK.body(12, bold: true, color: c.open ? TK.signal : TK.mist),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: TK.mist),
          ]),
        ),
    ]);
  }

  Widget _dropsCard(BuildContext context) {
    final near = adventures.nearbyDrops;
    final mine = adventures.myDrops.where((d) => !d.done).toList();
    return _card(accent: TK.drop, icon: Icons.inventory_2_rounded, title: 'Dead Drops', children: [
      Text(
        'Lock MON or a Kin at the exact spot you stand, with a riddle. Only someone who stands within 25 m '
        'can take it. The map only shows which hex a drop is in.',
        style: TK.body(13, color: TK.mist),
      ),
      const SizedBox(height: 10),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: TK.drop),
        onPressed: adventures.dropsEnabled ? () => _leaveDrop(context) : null,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Leave a drop here'),
      ),
      const SizedBox(height: 10),
      Text(near.isEmpty ? 'No drops in the hexes around you.' : 'Near you', style: TK.body(13, bold: true)),
      for (final d in near) _dropRow(context, d),
      if (mine.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Your drops', style: TK.body(13, bold: true)),
        for (final d in mine)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Expanded(
                child: Text(
                  '“${d.riddle}” · ${_prize(d)} · ${d.expired ? 'expired' : 'until ${_date(d.expiresAt)}'}',
                  style: TK.body(12, color: TK.mist),
                ),
              ),
              if (d.expired)
                TextButton(
                  onPressed: () => _act(context, () => adventures.reclaim(d), done: 'Back in your wallet'),
                  child: const Text('Take back'),
                ),
            ]),
          ),
      ],
    ]);
  }

  Widget _dropRow(BuildContext context, DeadDrop d) => InkWell(
        onTap: () => openDrop(context, d),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            const Icon(Icons.help_center_rounded, color: TK.drop),
            const SizedBox(width: 8),
            Expanded(
              child: Text('“${d.riddle}” · ${_prize(d)} · by @${d.dropperName}',
                  style: TK.body(12), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            Text(fmtDistance(location.distanceTo(d.area)), style: TK.body(12, color: TK.mist)),
          ]),
        ),
      );

  Future<void> _leaveDrop(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: TK.dusk,
        builder: (_) => const LeaveDropSheet(),
      );
}

String _prize(DeadDrop d) => [
      if (d.mon > BigInt.zero) fmtMon(d.mon),
      if (d.kinId != null) 'a Kin',
    ].join(' + ');

String _date(DateTime t) => '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

Future<void> openConvergence(BuildContext context, Convergence c) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TK.dusk,
      builder: (_) => ConvergenceSheet(event: c),
    );

Future<void> openDrop(BuildContext context, DeadDrop d) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TK.dusk,
      builder: (_) => DropSheet(drop: d),
    );

// ---------------------------------------------------------------- convergence

class ConvergenceSheet extends StatefulWidget {
  const ConvergenceSheet({super.key, required this.event});
  final Convergence event;

  @override
  State<ConvergenceSheet> createState() => _ConvergenceSheetState();
}

class _ConvergenceSheetState extends State<ConvergenceSheet> {
  Circle? _circle;
  bool _busy = false;
  String? _error;
  int _poll = 0;
  late final Timer _tick = Timer.periodic(const Duration(seconds: 1), (_) {
    if (!mounted) return;
    setState(() {});
    // While it's open, watch the circle fill up.
    if (widget.event.open && ++_poll % 8 == 0) _load();
  });

  Convergence get c => widget.event;

  @override
  void initState() {
    super.initState();
    _tick;
    _load();
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await adventures.circle(c);
      if (mounted) setState(() => _circle = r);
    } catch (_) {}
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (together, bonded, _) = await adventures.join(c, location.position);
      if (!mounted) return;
      if (bonded) {
        sound.play(Sfx.crown);
        HapticFeedback.heavyImpact();
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(bonded
            ? 'The circle held. A Mythic ${species[c.species].name} bonded with you! 👑'
            : 'You\'re in. $together of ${Convergence.circle} here now: get more people to ${c.name}!'),
      ));
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sp = species[c.species];
    final accent = Grade.mythic.color;
    final dist = location.distanceTo(c.at);
    final circle = _circle;
    final now = DateTime.now();
    final inReach = dist <= Convergence.reachM;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Convergence', style: TK.display(24, color: accent)),
          const SizedBox(height: 10),
          Row(children: [
            Bobbing(child: Image.asset(sp.sprite, width: 96, height: 96)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Mythic ${sp.name}', style: TK.display(20)),
                Text(c.name, style: TK.body(14, bold: true)),
                Text('${fmtDistance(dist)} ${compassPoint(location.position, c.at)}', style: TK.body(13, color: TK.mist)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: TK.night, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Text(
                c.open
                    ? 'Open · closes in ${_countdown(c.closesAt.difference(now))}'
                    : now.isAfter(c.closesAt)
                        ? 'This one is over'
                        : 'Opens in ${_countdown(c.opensAt.difference(now))}',
                style: TK.display(20, color: c.open ? TK.signal : TK.paper),
              ),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < Convergence.circle; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.person_rounded,
                      size: 36,
                      color: i < (circle?.recent ?? 0) ? accent : TK.slate,
                    ),
                  ),
              ]),
              const SizedBox(height: 6),
              Text(
                circle == null
                    ? 'Counting the circle…'
                    : '${circle.recent} standing together now · ${circle.joined} came today',
                style: TK.body(12, color: TK.mist),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Text(
            'Be within ${Convergence.reachM.round()} m of ${c.name} while it\'s open, then step in. When '
            '${Convergence.circle} players have stepped in within 5 minutes of each other, everyone in the circle '
            'bonds their own Mythic, with vigor 10-15 in every stat. Bring friends: it\'s the only way.',
            style: TK.body(12, color: TK.mist),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TK.body(13, color: TK.danger)),
            ),
          const SizedBox(height: 12),
          if (circle?.iBonded == true)
            Text('You bonded this one. 👑', textAlign: TextAlign.center, style: TK.display(18, color: accent))
          else if (circle?.iJoined == true)
            Text('You\'re in the circle. Waiting for ${Convergence.circle} together…',
                textAlign: TextAlign.center, style: TK.body(14, bold: true, color: accent))
          else
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: accent),
              onPressed: c.open && inReach && !_busy ? _join : null,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: TK.ink))
                  : Text(!c.open
                      ? 'Not open yet'
                      : inReach
                          ? 'Step into the circle'
                          : 'Get within ${Convergence.reachM.round()} m'),
            ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------- drops

class DropSheet extends StatefulWidget {
  const DropSheet({super.key, required this.drop});
  final DeadDrop drop;

  @override
  State<DropSheet> createState() => _DropSheetState();
}

class _DropSheetState extends State<DropSheet> {
  DropSearch? _last;
  bool _busy = false;
  String? _error;

  DeadDrop get d => widget.drop;

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (r, _) = await adventures.search(d, location.position);
      if (!mounted) return;
      setState(() => _last = r);
      if (r == DropSearch.found) {
        sound.play(Sfx.jackpot);
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = chain.address?.toLowerCase();
    final mine = d.dropper.toLowerCase() == me;
    final notForMe = d.forWho != null && d.forWho!.toLowerCase() != me;
    final (msg, colour) = switch (_last) {
      DropSearch.found => ('Found it! ${_prize(d)} is yours.', TK.signal),
      DropSearch.warm => ('Warm… it\'s within about 60 m. Keep looking.', TK.signal),
      DropSearch.cold => ('Cold. Not around here.', TK.mist),
      null => ('Somewhere in this hex (${fmtDistance(location.distanceTo(d.area))} away). Read the riddle.', TK.mist),
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.inventory_2_rounded, color: TK.drop, size: 28),
            const SizedBox(width: 8),
            Text('Dead drop', style: TK.display(24, color: TK.drop)),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: TK.night, borderRadius: BorderRadius.circular(16)),
            child: Text('“${d.riddle}”', style: TK.display(20)),
          ),
          const SizedBox(height: 8),
          Text('Inside: ${_prize(d)} · left by @${d.dropperName} · until ${_date(d.expiresAt)}',
              style: TK.body(13, color: TK.mist)),
          if (d.forWho != null)
            Text(notForMe ? 'Addressed to someone else.' : 'Addressed to you.',
                style: TK.body(13, bold: true, color: TK.drop)),
          const SizedBox(height: 12),
          Text(msg, style: TK.body(14, bold: true, color: colour)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!, style: TK.body(13, color: TK.danger)),
            ),
          const SizedBox(height: 12),
          if (_last != DropSearch.found)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: TK.drop),
              onPressed: _busy || mine || notForMe ? null : _search,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: TK.ink))
                  : const Icon(Icons.search_rounded),
              label: Text(mine ? 'Your own drop' : 'Search here'),
            ),
        ]),
      ),
    );
  }
}

class LeaveDropSheet extends StatefulWidget {
  const LeaveDropSheet({super.key});

  @override
  State<LeaveDropSheet> createState() => _LeaveDropSheetState();
}

class _LeaveDropSheetState extends State<LeaveDropSheet> {
  final _riddle = TextEditingController();
  final _mon = TextEditingController(text: '0.01');
  final _to = TextEditingController();
  Kin? _kin;
  int _days = 3;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _riddle.dispose();
    _mon.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _pickKin() async {
    final picked = await showModalBottomSheet<List<Kin>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TK.dusk,
      builder: (_) => const SquadPicker(title: 'Hide a Kin in the drop', action: 'Hide', max: 1, exact: true),
    );
    if (picked != null && picked.isNotEmpty && mounted) setState(() => _kin = picked.first);
  }

  Future<void> _leave() async {
    final riddle = _riddle.text.trim();
    final mon = double.tryParse(_mon.text.trim()) ?? 0;
    if (riddle.isEmpty) return setState(() => _error = 'Write a riddle or a hint.');
    if (mon < 0.001 && _kin == null) return setState(() => _error = 'Put at least 0.001 MON or a Kin inside.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String? to;
      if (_to.text.trim().isNotEmpty) {
        to = await adventures.addressOfName(_to.text.trim());
        if (to == null) throw Exception('No player called ${_to.text.trim()}.');
      }
      await adventures.leaveDrop(
        at: location.position,
        mon: BigInt.from((mon * 1e6).round()) * BigInt.from(10).pow(12),
        kinId: _kin?.uid,
        riddle: riddle,
        forWho: to,
        life: Duration(days: _days),
      );
      if (!mounted) return;
      sound.play(Sfx.coin);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Drop hidden. Only this exact spot unlocks it.')));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Leave a drop here', style: TK.display(24, color: TK.drop)),
              Text('Locked to the spot you stand on now (GPS ±${location.accuracy.round()} m). '
                  'Finders must come within 25 m.', style: TK.body(12, color: TK.mist)),
              const SizedBox(height: 14),
              TextField(
                controller: _riddle,
                maxLength: 140,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Riddle or hint', hintText: 'Under the bench nobody sits on'),
              ),
              TextField(
                controller: _mon,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'MON inside', suffixText: 'MON'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickKin,
                icon: const Icon(Icons.pets_rounded),
                label: Text(_kin == null
                    ? 'Hide a Kin too (optional)'
                    : 'Hiding ${_kin!.grade.label} ${_kin!.species.name} · tap to change'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _to,
                decoration: const InputDecoration(labelText: 'Only for (IGN, optional)', hintText: 'leave empty: anyone'),
              ),
              const SizedBox(height: 12),
              Text('Lasts $_days ${_days == 1 ? 'day' : 'days'}, then you can take it back',
                  style: TK.body(13, bold: true)),
              Slider(
                value: _days.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                onChanged: (v) => setState(() => _days = v.round()),
              ),
              if (_error != null) Text(_error!, style: TK.body(13, color: TK.danger)),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: TK.drop),
                onPressed: _busy ? null : _leave,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: TK.ink))
                    : const Text('Hide it'),
              ),
            ]),
          ),
        ),
      );
}
