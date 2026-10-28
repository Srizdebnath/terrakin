import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../chain/lab.dart';
import '../chain/territory.dart';
import '../core/copy.dart';
import '../core/sound.dart';
import '../core/economy.dart';
import '../core/species.dart';
import '../core/theme.dart';
import '../data/collection.dart';
import '../widgets/meme_card.dart';
import '../widgets/orb_painter.dart';
import 'battle_screen.dart';
import 'hex_sheet.dart';

/// The Lab: fusion, re-rolls, orb packs and staked duels. Every roll is
/// settled on Monad from the block's randomness.
class LabScreen extends StatefulWidget {
  const LabScreen({super.key});

  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  @override
  void initState() {
    super.initState();
    lab.refresh().catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) => SceneMusic(
    Scene.lab,
    child: DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: TK.night,
        appBar: AppBar(
          backgroundColor: TK.night,
          title: Text('The Lab', style: TK.display(22)),
          actions: [
            ListenableBuilder(
              listenable: chain,
              builder: (_, _) => Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    fmtMon(chain.balance),
                    style: TK.body(13, color: TK.signal, bold: true),
                  ),
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: TK.signal,
            labelColor: TK.signal,
            unselectedLabelColor: TK.mist,
            tabs: [
              Tab(icon: Icon(Icons.merge_type_rounded), text: 'Fuse'),
              Tab(icon: Icon(Icons.casino_rounded), text: 'Re-roll'),
              Tab(icon: Icon(Icons.inventory_2_rounded), text: 'Packs'),
              Tab(icon: Icon(Icons.sports_mma_rounded), text: 'Duels'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: lab,
          builder: (context, _) => lab.prices == null
              ? const Center(child: CircularProgressIndicator(color: TK.signal))
              : const TabBarView(
                  children: [_FuseTab(), _RerollTab(), _PackTab(), _DuelTab()],
                ),
        ),
      ),
    ),
  );
}

/// Busy / error plumbing shared by the tabs.
mixin _Action<T extends StatefulWidget> on State<T> {
  bool busy = false;
  String? error;

  Future<void> run(Future<void> Function() f) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget actionButton(String label, VoidCallback? onTap) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: busy ? null : onTap,
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: TK.ink),
            )
          : Text(label),
    ),
  );

  Widget errorText() => error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            error!,
            textAlign: TextAlign.center,
            style: TK.body(13, color: TK.danger),
          ),
        );

  Future<List<Kin>?> pick(
    String title,
    String action, {
    int max = 3,
    bool exact = false,
  }) => showModalBottomSheet<List<Kin>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TK.dusk,
    builder: (_) =>
        SquadPicker(title: title, action: action, max: max, exact: exact),
  );
}

Widget _kinTile(Species sp, Grade g, {double size = 72, String? caption}) =>
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(sp.sprite, width: size, height: size),
        Text(sp.name, style: TK.body(12, bold: true)),
        Text(
          caption ?? g.label,
          style: TK.body(11, color: g.color, bold: true),
        ),
      ],
    );

// ---- Fuse ---------------------------------------------------------------------

class _FuseTab extends StatefulWidget {
  const _FuseTab();
  @override
  State<_FuseTab> createState() => _FuseTabState();
}

class _FuseTabState extends State<_FuseTab> with _Action {
  List<Kin> _pair = [];
  (int, int, FusionOutcome, String)? _result; // species, grade, outcome, line

  Future<void> _choose() async {
    final p = await pick('Pick two Kin to fuse', 'Fuse', max: 2, exact: true);
    if (p != null && p.length == 2) setState(() => _pair = p);
  }

  Future<void> _fuse() => run(() async {
    final (id, outcome, grade, _) = await lab.fuse(_pair[0].uid, _pair[1].uid);
    final (sp, _, _, _) = TerritoryService.unpackKin(
      (await territory.kinPacked([id])).first.$2,
    );
    final line = switch (outcome) {
      FusionOutcome.jackpot => copy.fusionJackpot(),
      FusionOutcome.normal => copy.fusionNormal(),
      FusionOutcome.dud => copy.fusionDud(),
    };
    HapticFeedback.heavyImpact();
    sound.play(switch (outcome) {
      FusionOutcome.jackpot => Sfx.jackpot,
      FusionOutcome.normal => Sfx.reveal,
      FusionOutcome.dud => Sfx.dud,
    });
    setState(() {
      _result = (sp, grade, outcome, line);
      _pair = [];
    });
  });

  @override
  Widget build(BuildContext context) {
    final p = lab.prices!;
    final r = _result;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Burn two Kin, roll one.', style: TK.display(20)),
        const SizedBox(height: 4),
        Text(
          '${p.jackpotPct}% jackpot: one grade above the better parent · '
          '${100 - p.jackpotPct - p.dudPct}% keeps the better grade · ${p.dudPct}% dud: the worse grade. '
          'Stats land between the parents, with a mutation.',
          style: TK.body(13, color: TK.mist),
        ),
        const SizedBox(height: 18),
        if (r != null) ...[
          _Reveal(
            key: ValueKey(r),
            child: Column(
              children: [
                Text(
                  r.$4,
                  textAlign: TextAlign.center,
                  style: TK.display(
                    28,
                    color: r.$3 == FusionOutcome.dud ? TK.danger : TK.signal,
                  ),
                ),
                const SizedBox(height: 8),
                _kinTile(species[r.$1], Grade.values[r.$2], size: 120),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => showMemeCard(
                    context,
                    MemeCardData(
                      headline: r.$4,
                      subtitle:
                          'Fused a ${Grade.values[r.$2].label} ${species[r.$1].name}',
                      art: species[r.$1].sprite,
                      accent: Grade.values[r.$2].color,
                      chips: [r.$3.name.toUpperCase(), 'the Lab', 'on Monad'],
                      footer: '@${chain.name}',
                      shareText:
                          'Fusion ${r.$3.name} on Terrakin 🎰 #Terrakin #Monad',
                    ),
                  ),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Share'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
        GestureDetector(
          onTap: busy ? null : _choose,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TK.dusk,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < 2; i++)
                  i < _pair.length
                      ? _kinTile(_pair[i].species, _pair[i].grade)
                      : const SizedBox(
                          width: 72,
                          height: 100,
                          child: Icon(
                            Icons.add_circle_outline_rounded,
                            color: TK.mist,
                            size: 36,
                          ),
                        ),
                if (_pair.length == 2)
                  const Icon(Icons.add_rounded, color: TK.signal)
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        actionButton(
          'Fuse · ${fmtMon(p.fuse)}',
          _pair.length == 2 ? _fuse : null,
        ),
        errorText(),
      ],
    );
  }
}

// ---- Re-roll -------------------------------------------------------------------

class _RerollTab extends StatefulWidget {
  const _RerollTab();
  @override
  State<_RerollTab> createState() => _RerollTabState();
}

class _RerollTabState extends State<_RerollTab> with _Action {
  Kin? _kin;
  (List<int>, List<int>, String)? _result;

  static const _stats = ['HP', 'ATK', 'DEF', 'SPD'];

  Future<void> _choose() async {
    final p = await pick(
      'Pick a Kin to re-roll',
      'Choose',
      max: 1,
      exact: true,
    );
    if (p != null && p.isNotEmpty) setState(() => _kin = p.first);
  }

  Future<void> _reroll() => run(() async {
    final (before, after, _) = await lab.reroll(_kin!.uid);
    final delta =
        after.fold<int>(0, (a, b) => a + b) -
        before.fold<int>(0, (a, b) => a + b);
    HapticFeedback.mediumImpact();
    sound.play(delta >= 0 ? Sfx.coin : Sfx.dud);
    setState(
      () => _result = (
        before,
        after,
        delta >= 0 ? copy.rerollUp(delta) : copy.rerollDown(delta),
      ),
    );
  });

  @override
  Widget build(BuildContext context) {
    final k = _kin;
    final r = _result;
    final vig = r?.$2 ?? k?.genes.vigor.toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Re-roll hidden stats', style: TK.display(20)),
        const SizedBox(height: 4),
        Text(
          'All four vigor stats re-roll from 0 to 15. Could be perfect, could be zero.',
          style: TK.body(13, color: TK.mist),
        ),
        const SizedBox(height: 18),
        GestureDetector(
          onTap: busy ? null : _choose,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TK.dusk,
              borderRadius: BorderRadius.circular(18),
            ),
            child: k == null
                ? const SizedBox(
                    height: 100,
                    child: Icon(
                      Icons.add_circle_outline_rounded,
                      color: TK.mist,
                      size: 36,
                    ),
                  )
                : Row(
                    children: [
                      _kinTile(k.species, k.grade),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [
                            for (var i = 0; i < 4; i++)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 36,
                                      child: Text(
                                        _stats[i],
                                        style: TK.body(
                                          11,
                                          color: TK.mist,
                                          bold: true,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: TweenAnimationBuilder<double>(
                                          tween: Tween(end: vig![i] / 15),
                                          duration: const Duration(
                                            milliseconds: 700,
                                          ),
                                          curve: Curves.easeOutBack,
                                          builder: (_, v, _) =>
                                              LinearProgressIndicator(
                                                value: v.clamp(0.0, 1.0),
                                                minHeight: 8,
                                                backgroundColor: TK.slate,
                                                color: TK.signal,
                                              ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 54,
                                      child: Text(
                                        r == null
                                            ? ' ${vig[i]}'
                                            : ' ${r.$1[i]}→${r.$2[i]}',
                                        textAlign: TextAlign.right,
                                        style: TK.body(
                                          11,
                                          bold: true,
                                          color: r == null
                                              ? TK.paper
                                              : r.$2[i] >= r.$1[i]
                                              ? const Color(0xFF5FBF6A)
                                              : TK.danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (r != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: _Reveal(
              key: ValueKey(r),
              child: Text(
                r.$3,
                textAlign: TextAlign.center,
                style: TK.display(26, color: TK.signal),
              ),
            ),
          ),
        const SizedBox(height: 16),
        actionButton(
          'Re-roll · ${fmtMon(lab.prices!.reroll)}',
          k == null ? null : _reroll,
        ),
        errorText(),
      ],
    );
  }
}

// ---- Packs ---------------------------------------------------------------------

class _PackTab extends StatefulWidget {
  const _PackTab();
  @override
  State<_PackTab> createState() => _PackTabState();
}

class _PackTabState extends State<_PackTab> with _Action {
  List<Orb> _pulls = [];
  int _shown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _open() => run(() async {
    final (counts, _) = await lab.openPack();
    // Reveal the best last.
    final pulls = [
      for (var t = 0; t < 4; t++)
        for (var i = 0; i < counts[t]; i++) Orb.values[t],
    ];
    setState(() {
      _pulls = pulls;
      _shown = 0;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 420), (t) {
      if (_shown >= _pulls.length) return t.cancel();
      if (_pulls[_shown] == Orb.crown) HapticFeedback.heavyImpact();
      sound.play(_pulls[_shown] == Orb.crown ? Sfx.crown : Sfx.reveal);
      setState(() => _shown++);
    });
  });

  @override
  Widget build(BuildContext context) {
    final p = lab.prices!;
    final done = _pulls.isNotEmpty && _shown >= _pulls.length;
    final crown = _pulls.contains(Orb.crown);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Orb pack', style: TK.display(20)),
        const SizedBox(height: 4),
        Text(
          '${p.packSize} random orbs: 70% Seed · 20% Bloom · 8% Aurora · 2% Crown (never misses).',
          style: TK.body(13, color: TK.mist),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 110,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (
                var i = 0;
                i < (_pulls.isEmpty ? p.packSize : _pulls.length);
                i++
              )
                AnimatedScale(
                  scale: i < _shown ? 1 : 0.6,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  child: i < _shown
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OrbIcon(
                              _pulls[i],
                              size: 56,
                              glow: _pulls[i] == Orb.crown ? 1 : 0,
                            ),
                            Text(
                              _pulls[i].label.split(' ').first,
                              style: TK.body(10, color: TK.mist, bold: true),
                            ),
                          ],
                        )
                      : Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: TK.dusk,
                            shape: BoxShape.circle,
                            border: Border.all(color: TK.slate),
                          ),
                          child: const Icon(
                            Icons.question_mark_rounded,
                            color: TK.mist,
                          ),
                        ),
                ),
            ],
          ),
        ),
        if (done)
          _Reveal(
            child: Text(
              crown ? copy.crownPull() : copy.packOpened(),
              textAlign: TextAlign.center,
              style: TK.display(26, color: TK.signal),
            ),
          ),
        const SizedBox(height: 20),
        actionButton('Open pack · ${fmtMon(p.pack)}', _open),
        errorText(),
      ],
    );
  }
}

// ---- Duels ---------------------------------------------------------------------

class _DuelTab extends StatefulWidget {
  const _DuelTab();
  @override
  State<_DuelTab> createState() => _DuelTabState();
}

class _DuelTabState extends State<_DuelTab> with _Action {
  static final _stakes = [
    for (final m in ['0.01', '0.05', '0.1', '0.25']) _wei(m),
  ];
  late BigInt _stake = _stakes[0];

  static BigInt _wei(String mon) {
    final [whole, frac] = '$mon.0'.split('.').take(2).toList();
    return BigInt.parse(whole) * BigInt.from(10).pow(18) +
        BigInt.parse(frac.padRight(18, '0').substring(0, 18));
  }

  Future<void> _create() async {
    final squad = await pick('Your duel squad', 'Open duel');
    if (squad == null || squad.isEmpty) return;
    await run(() => lab.createDuel([for (final k in squad) k.uid], _stake));
  }

  Future<void> _accept(OpenDuel d) async {
    final squad = await pick(
      'Fight @${d.creatorName} for ${fmtMon(d.stake)}',
      'Fight',
    );
    if (squad == null || squad.isEmpty) return;
    await run(() async {
      final mine = [for (final k in squad) fighterOf(k)];
      final r = await lab.acceptDuel(d, [for (final k in squad) k.uid], mine);
      if (!mounted) return;
      final title = r.won ? copy.duelWon() : copy.duelLost();
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BattleScreen(
            heading: 'Duel · ${fmtMon(d.stake * BigInt.two)} pot',
            me: ReplaySide('You', [for (final k in squad) k.species], mine),
            them: ReplaySide(
              '@${d.creatorName}',
              [for (final x in d.squad) species[x.species]],
              [for (final x in d.squad) x.fighter],
            ),
            meAttacked: r.meAttacked,
            result: r.result,
            won: r.won,
            title: title,
            subtitle: r.won
                ? 'You took ${fmtMon(r.payout)}.'
                : '@${d.creatorName} took the pot.',
            hash: r.hash,
            share: MemeCardData(
              headline: title,
              subtitle: r.won
                  ? '@${chain.name} beat @${d.creatorName}'
                  : '@${d.creatorName} beat @${chain.name}',
              art: squad.first.species.sprite,
              accent: r.won ? TK.signal : TK.danger,
              chips: [
                '${fmtMon(d.stake * BigInt.two)} pot',
                '${r.result.turns} turns',
                'settled on Monad',
              ],
              footer: chain.txUrl(r.hash).replaceFirst('https://', ''),
              shareText: r.won
                  ? 'Won a staked duel on Terrakin 💰 #Terrakin #Monad'
                  : 'Lost a duel on Terrakin 💀 run it back',
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = chain.address?.toLowerCase();
    final fee = lab.prices!.duelFeeBps / 100;
    return RefreshIndicator(
      onRefresh: lab.refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Staked duels', style: TK.display(20)),
          const SizedBox(height: 4),
          Text(
            'Stake MON on a 1-3 Kin auto-battle against anyone, anywhere. Who attacks is a coin flip. '
            'Winner takes the pot minus ${fee.toStringAsFixed(fee % 1 == 0 ? 0 : 1)}%.',
            style: TK.body(13, color: TK.mist),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: [
              for (final s in _stakes)
                ChoiceChip(
                  label: Text(fmtMon(s)),
                  selected: _stake == s,
                  onSelected: (_) => setState(() => _stake = s),
                ),
            ],
          ),
          const SizedBox(height: 10),
          actionButton('Open a duel · stake ${fmtMon(_stake)}', _create),
          if (lab.winnings > BigInt.zero)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                onPressed: busy ? null : () => run(lab.withdrawWinnings),
                child: Text('Withdraw ${fmtMon(lab.winnings)} winnings'),
              ),
            ),
          errorText(),
          const SizedBox(height: 20),
          Text('Open challenges', style: TK.display(17)),
          const SizedBox(height: 8),
          if (lab.duels.isEmpty)
            Text(
              'None yet. Open one and send the link to your friends.',
              style: TK.body(13, color: TK.mist),
            ),
          for (final d in lab.duels)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TK.dusk,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  for (final x in d.squad)
                    Image.asset(
                      species[x.species].sprite,
                      width: 36,
                      height: 36,
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.creator == me ? 'Your duel' : '@${d.creatorName}',
                          style: TK.body(14, bold: true),
                        ),
                        Text(
                          'Stake ${fmtMon(d.stake)} · ${d.squad.map((x) => Grade.values[x.grade].label).join(', ')}',
                          style: TK.body(12, color: TK.mist),
                        ),
                      ],
                    ),
                  ),
                  d.creator == me
                      ? TextButton(
                          onPressed: busy
                              ? null
                              : () => run(() => lab.cancelDuel(d.id)),
                          child: const Text('Cancel'),
                        )
                      : FilledButton(
                          onPressed: busy ? null : () => _accept(d),
                          child: const Text('Fight'),
                        ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Pops content in with a little overshoot.
class _Reveal extends StatelessWidget {
  const _Reveal({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 550),
    curve: Curves.easeOutBack,
    builder: (_, v, c) => Transform.scale(
      scale: 0.6 + 0.4 * v,
      child: Opacity(opacity: v.clamp(0.0, 1.0), child: c),
    ),
    child: child,
  );
}
