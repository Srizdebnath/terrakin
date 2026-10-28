import 'package:flutter/material.dart';

import '../app_state.dart';
import '../chain/social.dart';
import '../core/economy.dart';
import '../core/species.dart';
import '../core/theme.dart';
import '../widgets/meme_card.dart';

/// Season banner (capped Mythics), leaderboards, and crews.
class SeasonScreen extends StatefulWidget {
  const SeasonScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<SeasonScreen> createState() => _SeasonScreenState();
}

class _SeasonScreenState extends State<SeasonScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Enrol first (free, backend-paid) so you're on the board you open.
      await social.enrollOnce().catchError((Object _) {});
      await Future.wait([social.refreshSeason(), social.refreshLeaderboard(), social.refreshCrews()]);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        initialIndex: widget.initialTab,
        child: Scaffold(
          backgroundColor: TK.night,
          appBar: AppBar(
            backgroundColor: TK.night,
            title: ListenableBuilder(
              listenable: social,
              builder: (_, _) => Text('Season ${social.season?.season ?? ''}', style: TK.display(22)),
            ),
            bottom: const TabBar(
              indicatorColor: TK.signal,
              labelColor: TK.signal,
              unselectedLabelColor: TK.mist,
              tabs: [Tab(text: 'Players'), Tab(text: 'Crews'), Tab(text: 'My crew')],
            ),
          ),
          body: ListenableBuilder(
            listenable: social,
            builder: (context, _) => Column(children: [
              if (social.season != null) _SeasonBanner(social.season!),
              if (_error != null) Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!, style: TK.body(12, color: TK.danger)),
              ),
              const Expanded(child: TabBarView(children: [_Players(), _Crews(), _MyCrew()])),
            ]),
          ),
        ),
      );
}

class _SeasonBanner extends StatelessWidget {
  const _SeasonBanner(this.s);
  final SeasonInfo s;

  @override
  Widget build(BuildContext context) {
    final left = s.left;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TK.dusk,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Grade.mythic.color.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Mythics this season', style: TK.display(15, color: Grade.mythic.color)),
          const Spacer(),
          Text(left.isNegative ? 'Season over' : 'ends in ${left.inDays}d ${left.inHours % 24}h',
              style: TK.body(12, color: TK.mist, bold: true)),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (var i = 0; i < species.length; i++)
            Column(children: [
              Opacity(
                opacity: s.minted[i] >= s.cap ? 0.35 : 1,
                child: Image.asset(species[i].sprite, width: 32, height: 32),
              ),
              Text(s.minted[i] >= s.cap ? 'SOLD OUT' : '${s.minted[i]}/${s.cap}',
                  style: TK.body(9.5, bold: true, color: s.minted[i] >= s.cap ? TK.danger : TK.paper)),
            ]),
        ]),
      ]),
    );
  }
}

enum _Sort { hexes, mythics, wins, kin }

class _Players extends StatefulWidget {
  const _Players();
  @override
  State<_Players> createState() => _PlayersState();
}

class _PlayersState extends State<_Players> {
  _Sort _sort = _Sort.hexes;

  int _score(PlayerRow p) => switch (_sort) {
        _Sort.hexes => p.hexes,
        _Sort.mythics => p.mythics,
        _Sort.wins => p.wins,
        _Sort.kin => p.kin,
      };

  String _unit(int n) => switch (_sort) {
        _Sort.hexes => n == 1 ? 'hex' : 'hexes',
        _Sort.mythics => n == 1 ? 'Mythic' : 'Mythics',
        _Sort.wins => n == 1 ? 'duel win' : 'duel wins',
        _Sort.kin => 'Kin',
      };

  @override
  Widget build(BuildContext context) {
    final me = chain.address?.toLowerCase();
    final rows = [...social.players.where((p) => p.name.isNotEmpty)]
      ..sort((a, b) => _score(b).compareTo(_score(a)));
    final myRank = rows.indexWhere((p) => p.address == me);
    return RefreshIndicator(
      onRefresh: social.refreshLeaderboard,
      child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), children: [
        Wrap(spacing: 8, children: [
          for (final s in _Sort.values)
            ChoiceChip(
              label: Text(switch (s) {
                _Sort.hexes => 'Turf',
                _Sort.mythics => 'Mythics',
                _Sort.wins => 'Duels',
                _Sort.kin => 'Kin',
              }),
              selected: _sort == s,
              onSelected: (_) => setState(() => _sort = s),
            ),
        ]),
        if (myRank >= 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.ios_share_rounded),
              label: Text('You\'re #${myRank + 1} · share it'),
              onPressed: () => showMemeCard(
                context,
                MemeCardData(
                  headline: '#${myRank + 1} in Season ${social.season?.season ?? 1}',
                  subtitle: '@${rows[myRank].name} · ${_score(rows[myRank])} ${_unit(_score(rows[myRank]))}',
                  art: 'assets/images/brand/logo-mark.png',
                  accent: TK.signal,
                  chips: [
                    '${rows[myRank].hexes} hexes',
                    '${rows[myRank].mythics} Mythics',
                    '${rows[myRank].wins} duel wins',
                  ],
                  footer: '@${rows[myRank].name}',
                  shareText: 'Ranked #${myRank + 1} on the Terrakin leaderboard 🏆 #Terrakin #Monad',
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (rows.isEmpty) Text('No players yet.', style: TK.body(13, color: TK.mist)),
        for (final (i, p) in rows.indexed)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: p.address == me ? TK.signal.withValues(alpha: 0.14) : TK.dusk,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              SizedBox(
                width: 34,
                child: Text(i < 3 ? ['🥇', '🥈', '🥉'][i] : '#${i + 1}', style: TK.body(i < 3 ? 18 : 13, bold: true)),
              ),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '@${p.name}', style: TK.body(14, bold: true)),
                  if (social.tagOf(p.crew) != null)
                    TextSpan(
                      text: '  [${social.tagOf(p.crew)}]',
                      style: TK.body(12, bold: true, color: SocialService.crewColour(p.crew)),
                    ),
                ])),
              ),
              Text('${_score(p)} ${_unit(_score(p))}', style: TK.body(13, color: TK.signal, bold: true)),
            ]),
          ),
      ]),
    );
  }
}

class _Crews extends StatelessWidget {
  const _Crews();

  @override
  Widget build(BuildContext context) {
    // Crew turf: the sum of members' hexes, from the leaderboard rows.
    final turf = <int, int>{};
    for (final p in social.players) {
      if (p.crew != 0) turf[p.crew] = (turf[p.crew] ?? 0) + p.hexes;
    }
    final rows = [...social.crews.where((c) => c.size > 0)]
      ..sort((a, b) => (turf[b.id] ?? 0).compareTo(turf[a.id] ?? 0));
    return RefreshIndicator(
      onRefresh: social.refreshCrews,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (rows.isEmpty) Text('No crews yet. Found the first one in My crew.', style: TK.body(13, color: TK.mist)),
        for (final (i, c) in rows.indexed)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TK.dusk,
              borderRadius: BorderRadius.circular(14),
              border: Border(left: BorderSide(color: SocialService.crewColour(c.id), width: 5)),
            ),
            child: Row(children: [
              SizedBox(width: 32, child: Text('#${i + 1}', style: TK.body(13, bold: true))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('[${c.tag}] ${c.name}', style: TK.body(14, bold: true)),
                  Text('${c.size}/30 members · treasury ${fmtMon(c.treasury)}', style: TK.body(12, color: TK.mist)),
                ]),
              ),
              Text('${turf[c.id] ?? 0} hexes', style: TK.body(13, color: TK.signal, bold: true)),
              if (social.myCrew == null && c.size < 30)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: FilledButton(
                    onPressed: () => _act(context, () => social.join(c.id)),
                    child: const Text('Join'),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}

Future<void> _act(BuildContext context, Future<void> Function() f) async {
  final m = ScaffoldMessenger.of(context);
  try {
    await f();
  } catch (e) {
    m.showSnackBar(SnackBar(content: Text(e.toString())));
  }
}

class _MyCrew extends StatefulWidget {
  const _MyCrew();
  @override
  State<_MyCrew> createState() => _MyCrewState();
}

class _MyCrewState extends State<_MyCrew> {
  final _name = TextEditingController();
  final _tag = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _tag.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    await _act(context, f);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = social.myCrew;
    return c == null ? _found() : _crew(c);
  }

  Widget _found() {
    final fee = social.createFee;
    final tag = _tag.text.trim().toUpperCase();
    final ok = _name.text.trim().length >= 3 &&
        _name.text.trim().length <= 20 &&
        RegExp(r'^[A-Z0-9]{2,4}$').hasMatch(tag);
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Found a crew', style: TK.display(20)),
      const SizedBox(height: 4),
      Text('A shared treasury, a tag on the leaderboard, and your members\' hexes painted in one colour. '
          'Or join one from the Crews tab.', style: TK.body(13, color: TK.mist)),
      const SizedBox(height: 16),
      TextField(
        controller: _name,
        maxLength: 20,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Crew name'),
      ),
      TextField(
        controller: _tag,
        maxLength: 4,
        textCapitalization: TextCapitalization.characters,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Tag (2-4 letters or numbers)'),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: !ok || _busy || fee == null ? null : () => _run(() => social.create(_name.text.trim(), tag)),
        child: Text(fee == null ? 'Loading…' : 'Found [${tag.isEmpty ? '?' : tag}] · ${fmtMon(fee)}'),
      ),
    ]);
  }

  Widget _crew(CrewDetail c) {
    final me = chain.address?.toLowerCase();
    final captain = c.captain == me;
    final names = {for (final p in social.players) p.address: p};
    final colour = SocialService.crewColour(c.id);
    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(8)),
          child: Text(c.tag, style: TK.display(18, color: TK.ink)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(c.name, style: TK.display(22))),
      ]),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: TK.dusk, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Treasury', style: TK.body(12, color: TK.mist, bold: true)),
          Text(fmtMon(c.treasury), style: TK.display(28, color: TK.signal)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final amt in ['0.01', '0.05', '0.1'])
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => social.deposit(BigInt.from(double.parse(amt) * 1e6) * BigInt.from(10).pow(12))),
                child: Text('+$amt'),
              ),
            if (captain)
              FilledButton(
                onPressed: _busy || c.treasury == BigInt.zero ? null : () => _run(social.payout),
                child: Text('Split to ${c.members.length}'),
              ),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      Text('Members · ${c.members.length}/30', style: TK.display(17)),
      const SizedBox(height: 6),
      for (final m in c.members)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(m == c.captain ? Icons.star_rounded : Icons.person_rounded, color: m == c.captain ? TK.signal : TK.mist),
          title: Text('@${names[m]?.name ?? '${m.substring(0, 8)}…'}${m == me ? ' (you)' : ''}',
              style: TK.body(14, bold: true)),
          subtitle: Text('${names[m]?.hexes ?? 0} hexes · ${names[m]?.mythics ?? 0} Mythics',
              style: TK.body(12, color: TK.mist)),
          trailing: captain && m != me
              ? IconButton(
                  icon: const Icon(Icons.person_remove_rounded, color: TK.mist),
                  onPressed: _busy ? null : () => _run(() => social.kick(m)),
                )
              : null,
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _busy ? null : () => _run(social.leave),
        icon: const Icon(Icons.logout_rounded),
        label: Text(c.members.length == 1 ? 'Leave (you take the treasury)' : 'Leave crew'),
      ),
    ]);
  }
}
