import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/battle.dart';
import '../core/sound.dart';
import '../core/species.dart';
import '../core/theme.dart';
import '../widgets/meme_card.dart';

/// One side of a replayed battle.
class ReplaySide {
  const ReplaySide(this.name, this.species, this.fighters);
  final String name;
  final List<Species> species;
  final List<Fighter> fighters;
}

/// Replays a battle blow by blow: hex battles and staked duels. The result
/// was settled on Monad; the replay is re-simulated locally from the event's
/// seed, so it always matches.
class BattleScreen extends StatefulWidget {
  const BattleScreen({
    super.key,
    required this.me,
    required this.them,
    required this.meAttacked,
    required this.result,
    required this.won,
    required this.title,
    required this.subtitle,
    required this.heading,
    required this.hash,
    required this.share,
  });
  final ReplaySide me, them;

  /// Whether [me] was the simulation's attacking side (`a`).
  final bool meAttacked;
  final BattleResult result;
  final bool won;
  final String title, subtitle, heading, hash;
  final MemeCardData share;

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> {
  int _step = 0; // strikes shown so far
  Timer? _timer;

  List<Strike> get _strikes => widget.result.strikes;
  bool get _done => _step >= _strikes.length;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (_done) {
        _timer?.cancel();
        HapticFeedback.heavyImpact();
        sound.play(widget.won ? Sfx.win : Sfx.lose);
        return setState(() {});
      }
      if (_strikes[_step].fainted) HapticFeedback.mediumImpact();
      sound.play(_strikes[_step].fainted ? Sfx.ko : Sfx.hit);
      setState(() => _step++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Active fighter index and HP of the simulation's attacker (a) and
  /// defender (d) after [_step] strikes.
  (int, int, int, int) _state(List<Fighter> a, List<Fighter> d) {
    var ai = 0, di = 0;
    var hpA = a.first.hp, hpD = d.isEmpty ? 0 : d.first.hp;
    for (final s in _strikes.take(_step)) {
      if (s.byAttacker) {
        if (s.fainted) {
          di++;
          hpD = di < d.length ? d[di].hp : 0;
        } else {
          hpD = s.hpAfter;
        }
      } else if (s.fainted) {
        ai++;
        hpA = ai < a.length ? a[ai].hp : 0;
      } else {
        hpA = s.hpAfter;
      }
    }
    return (ai, hpA, di, hpD);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final a = w.meAttacked ? w.me : w.them;
    final d = w.meAttacked ? w.them : w.me;
    final (ai, hpA, di, hpD) = _state(a.fighters, d.fighters);
    final (myIdx, myHp, theirIdx, theirHp) = w.meAttacked
        ? (ai, hpA, di, hpD)
        : (di, hpD, ai, hpA);
    final last = _step > 0 ? _strikes[_step - 1] : null;
    final iHit = last != null && last.byAttacker == w.meAttacked;
    int maxHp(ReplaySide s, int i) => s.fighters.isEmpty
        ? 1
        : s.fighters[i.clamp(0, s.fighters.length - 1)].hp;
    return SceneMusic(
      Scene.battle,
      child: Scaffold(
        backgroundColor: TK.night,
        appBar: AppBar(
          backgroundColor: TK.night,
          title: Text(w.heading, style: TK.display(22)),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _side(
                  w.them,
                  theirIdx,
                  theirHp,
                  maxHp(w.them, theirIdx),
                  shaken: last != null && iHit,
                ),
                const Spacer(),
                if (last != null)
                  Text(
                    '${iHit ? 'You hit' : 'They hit'} for ${last.damage}${last.fainted ? ' · KO!' : ''}',
                    style: TK.display(20, color: iHit ? TK.signal : TK.danger),
                  ),
                const Spacer(),
                _side(
                  w.me,
                  myIdx,
                  myHp,
                  maxHp(w.me, myIdx),
                  shaken: last != null && !iHit,
                ),
                const SizedBox(height: 24),
                AnimatedOpacity(
                  opacity: _done ? 1 : 0,
                  duration: const Duration(milliseconds: 400),
                  child: Column(
                    children: [
                      Text(
                        w.title,
                        textAlign: TextAlign.center,
                        style: TK.display(
                          32,
                          color: w.won ? TK.signal : TK.danger,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        w.subtitle,
                        textAlign: TextAlign.center,
                        style: TK.body(13, color: TK.mist),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => showMemeCard(context, w.share),
                              icon: const Icon(Icons.ios_share_rounded),
                              label: const Text('Share'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Done'),
                            ),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: chain.txUrl(w.hash)),
                        ),
                        child: const Text('Copy tx link'),
                      ),
                    ],
                  ),
                ),
                if (!_done)
                  TextButton(
                    onPressed: () => setState(() => _step = _strikes.length),
                    child: const Text('Skip'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _side(
    ReplaySide s,
    int active,
    int hp,
    int maxHp, {
    required bool shaken,
  }) {
    final team = s.species;
    final out = active >= team.length;
    return Column(
      children: [
        Row(
          children: [
            Text(s.name, style: TK.display(18)),
            const Spacer(),
            for (var i = 0; i < team.length; i++)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Opacity(
                  opacity: i < active ? 0.25 : 1,
                  child: Image.asset(team[i].sprite, width: 28, height: 28),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedSlide(
          offset: shaken ? const Offset(0.04, 0) : Offset.zero,
          duration: const Duration(milliseconds: 120),
          child: SizedBox(
            height: 120,
            child: out || team.isEmpty
                ? Center(
                    child: Text(
                      team.isEmpty ? 'No defenders' : 'Out of Kin',
                      style: TK.body(14, color: TK.mist),
                    ),
                  )
                : Image.asset(team[active].sprite),
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: maxHp == 0 ? 0 : (hp / maxHp).clamp(0.0, 1.0),
            minHeight: 10,
            backgroundColor: TK.slate,
            color: hp / (maxHp == 0 ? 1 : maxHp) > 0.3
                ? const Color(0xFF5FBF6A)
                : TK.danger,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text('$hp HP', style: TK.body(11, color: TK.mist)),
        ),
      ],
    );
  }
}
