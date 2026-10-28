import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'species.dart';

enum Tone { normal, unhinged }

/// Every line of game copy that has a personality lives here, so slang can be
/// refreshed each season in one place. Unhinged lines rotate at random.
class Copy extends ChangeNotifier {
  Copy._();
  static final instance = Copy._();
  static final _rng = Random();

  Tone tone = Tone.normal;
  bool get unhinged => tone == Tone.unhinged;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    tone = Tone.values.byName(p.getString('tone.v1') ?? Tone.normal.name);
    notifyListeners();
  }

  Future<void> setTone(Tone t) async {
    tone = t;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('tone.v1', t.name);
  }

  String _pick(String normal, List<String> wild) => unhinged ? wild[_rng.nextInt(wild.length)] : normal;

  // ---- Catching -------------------------------------------------------------

  String caught(Grade g) => _pick('Bonded!', [
        if (g.index >= Grade.epic.index) ...["it's giving ${g.label} ✨", 'ABSOLUTE CINEMA', 'main character catch'],
        'W catch 🔥',
        'bonded. no cap',
        'secured the bag',
        'Kin said yes 💚',
      ]);

  String brokeFree() => _pick('It broke free. Throw again!', [
        'skill issue. throw again',
        'Kin said nah 💀',
        'so close. run it back',
        'it dodged like rent day',
      ]);

  String fled(String name) => _pick('$name slipped away', [
        '$name left you on read',
        '$name ghosted 👻',
        '$name touched grass (elsewhere)',
        'ratio’d by $name',
      ]);

  String fledHint() => _pick('Better timing and stronger orbs make Kin stay.', [
        'lock in on the timing, or bring a Crown Orb.',
        'it’s not you, it’s your orbs. (it’s you)',
      ]);

  String outOfOrbs() => _pick('Out of orbs. Visit the Market.', ['out of orbs. touch the Market', 'bag empty. restock fr']);

  // ---- Territory ------------------------------------------------------------

  String claimed() => _pick('Hex claimed. It’s yours.', ['this turf is ours now 🏴', 'new land unlocked. landlord era', 'planted the flag. gg']);

  String captured() => _pick('Hex captured!', ['hex diff 😤', 'you cooked them', 'turf taken. rent’s due', 'ABSOLUTE CINEMA']);

  String defended() => _pick('Defence held', ['you got cooked 💀', 'defended like a final boss', 'their Kin were built different', 'L. run it back']);

  String capturedSub() => _pick('Your squad now defends it. Shielded for 30 minutes.',
      ['your squad’s on guard now. 30 min shield so nobody snipes it.']);

  String defendedSub(String owner) => _pick('Your fee went to @$owner. Train up and run it back.',
      ['@$owner just ate your fee. level up and run it back.', 'fee donated to @$owner. respectfully, ngmi (yet)']);

  String shieldedBtn() => _pick('Shielded', ['shielded. touch grass and come back']);

  String rent(String amount) => _pick('+$amount from your hexes', ['rent’s due 💸 +$amount', 'landlord money: +$amount']);

  // ---- Auctions -------------------------------------------------------------

  String winningBid() => _pick('You’re winning', ['you’re top bid. diamond hands 💎', 'leading. stay locked in']);

  String outbid() => _pick('You were outbid', ['outbid. ngmi?', 'someone mogged your bid']);

  String withdrawOutbid(String amount) => _pick('Withdraw $amount outbid', ['run it back: reclaim $amount']);

  String whale() => _pick('Big bid', ['whale alert 🐋']);

  // ---- Lab ------------------------------------------------------------------

  String fusionJackpot() => _pick('Jackpot! A grade up', ['JACKPOT 🎰 grade up', 'WE\'RE SO BACK', 'the lab blessed you']);
  String fusionNormal() => _pick('Fused', ['fused. clean.', 'solid pull', 'not bad not bad']);
  String fusionDud() => _pick('A dud: the weaker grade won', ['it\'s a dud 💀', 'down bad', 'the lab said no', 'it\'s so over']);

  String rerollUp(int delta) => _pick('Vigor +$delta', ['rolled a W 📈 +$delta', 'stats said 🆙 +$delta']);
  String rerollDown(int delta) => _pick('Vigor $delta', ['rolled an L 📉 $delta', 'it\'s so over ($delta)']);

  String crownPull() => _pick('Crown Orb!', ['CROWN PULL 👑 no way', 'god pull 👑']);
  String packOpened() => _pick('Pack opened', ['pack ripped', 'let\'s see the pulls']);

  String duelWon() => _pick('You won the duel!', ['duel diff 😤', 'took their bag 💰', 'you cooked']);
  String duelLost() => _pick('You lost the duel', ['you got cooked 💀', 'bag fumbled', 'L + ratio']);

  // ---- Daily ----------------------------------------------------------------

  String gm(String name) => _pick('Welcome back, $name', ['gm $name ☀️ Kin are out', 'gm. wagmi, $name', 'gm. go touch grass (and catch it)']);
}

final copy = Copy.instance;
