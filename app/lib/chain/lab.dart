import 'package:flutter/foundation.dart';

import '../core/battle.dart';
import 'abi.dart';
import 'game_chain.dart';
import 'territory.dart';

enum FusionOutcome { dud, normal, jackpot }

class LabPrices {
  LabPrices(AbiReader r)
      : fuse = r.big(0),
        reroll = r.big(1),
        pack = r.big(2),
        minStake = r.big(3),
        duelFeeBps = r.uint(4),
        jackpotPct = r.uint(5),
        dudPct = r.uint(6),
        packSize = r.uint(7);
  final BigInt fuse, reroll, pack, minStake;
  final int duelFeeBps, jackpotPct, dudPct, packSize;
}

/// An open challenge, with the creator's squad as it would fight.
class OpenDuel {
  const OpenDuel(this.id, this.creator, this.creatorName, this.stake, this.squad);
  final String id, creator, creatorName;
  final BigInt stake;
  final List<Defender> squad; // creator's Kin (no home bonus in duels)
}

class DuelResult {
  const DuelResult(this.won, this.payout, this.meAttacked, this.result, this.hash);
  final bool won, meAttacked;
  final BigInt payout;
  final BattleResult result;
  final String hash;
}

/// Fusion, re-rolls, orb packs and staked duels (TerrakinLab.sol).
class LabService extends ChangeNotifier {
  LabService(this.chain, this.territory);
  final GameChain chain;
  final TerritoryService territory;

  static const _fuse = '0xf68858e4';
  static const _reroll = '0x1c19c215';
  static const _openPack = '0x3c4ea385';
  static const _createDuel = '0x4ef0ca9e';
  static const _cancelDuel = '0xd9c312f4';
  static const _acceptDuel = '0x10b39a9f';
  static const _withdrawWinnings = '0xcc42e83a';
  static const _openDuels = '0xcf5fa125';
  static const _duelKin = '0xe1d0f5ff';
  static const _winnings = '0xea3a1499';
  static const _prices = '0xd3419bf3';
  static const _topicFused = '0xaef93e8f6d37187bf0a354fbe071d7e2149d505d1654ae346eb417161733636b';
  static const _topicRerolled = '0x43b57ff1c3d2bd112fab6273556fdf7742b884f828b7e155325cc75ce766458d';
  static const _topicPack = '0x7a1e2e63b4ef245e18b9df6985b3bfefb0bf053642999ba491fcd2488069126d';
  static const _topicDuelSettled = '0x9018fb855f505efb0868b388cee000a0f64803d6a01bc0c43c0e5e21dac29ef4';

  LabPrices? prices;
  List<OpenDuel> duels = [];
  BigInt winnings = BigInt.zero;

  bool get enabled => chain.lab.isNotEmpty;
  String get _lab => chain.lab;
  String get _me => chain.address!.toLowerCase();

  Future<void> refresh() async {
    if (!enabled || chain.address == null) return;
    final r = await Future.wait([
      chain.read(_lab, _openDuels),
      chain.read(_lab, '$_winnings${Abi.address(chain.address!)}'),
      if (prices == null) chain.read(_lab, _prices),
    ]);
    final d = r[0];
    final ids = d.arrayAt(0), creators = d.arrayAt(1), stakes = d.arrayAt(2);
    final n = d.uint(ids);
    final out = <OpenDuel>[];
    for (var i = 0; i < n; i++) {
      final id = d.bytes32(ids + 1 + i);
      final creator = d.address(creators + 1 + i).toLowerCase();
      final k = await chain.read(_lab, '$_duelKin${Abi.bytes32(id)}');
      final ka = k.arrayAt(0);
      final kinIds = [for (var j = 0; j < k.uint(ka); j++) k.bytes32(ka + 1 + j)];
      final packed = await territory.kinPacked(kinIds);
      final squad = [
        for (var j = 0; j < kinIds.length; j++)
          () {
            final (sp, gr, vig, mods) = TerritoryService.unpackKin(packed[j].$2);
            return Defender(kinIds[j], sp, gr, Fighter.of(sp, gr, vig, mods, home: false));
          }(),
      ];
      out.add(OpenDuel(id, creator, await chain.nameOf(creator), d.big(stakes + 1 + i), squad));
    }
    duels = out.reversed.toList(); // newest first
    winnings = r[1].big(0);
    if (r.length > 2) prices = LabPrices(r[2]);
    notifyListeners();
  }

  /// Gas for random paths varies between estimate and inclusion.
  static const _margin = 30;

  Future<(String, FusionOutcome, int, TxRecord)> fuse(String a, String b) async {
    final (tx, logs) = await chain.sendTo(_lab, 'Fused two Kin', Abi.call(_fuse, [Abi.bytes32(a), Abi.bytes32(b)]),
        value: prices!.fuse, marginPct: _margin);
    final ev = logs.firstWhere((l) => (l['topics'] as List).first == _topicFused);
    final d = AbiReader(ev['data'] as String);
    return ((ev['topics'] as List)[2] as String, FusionOutcome.values[d.uint(2)], d.uint(3), tx);
  }

  /// Returns the old and new vigor (hp, atk, def, spd).
  Future<(List<int>, List<int>, TxRecord)> reroll(String kin) async {
    final (tx, logs) = await chain.sendTo(_lab, 'Re-rolled a Kin', Abi.call(_reroll, [Abi.bytes32(kin)]),
        value: prices!.reroll, marginPct: _margin);
    final ev = logs.firstWhere((l) => (l['topics'] as List).first == _topicRerolled);
    final d = AbiReader(ev['data'] as String);
    List<int> split(int v) => [for (var i = 0; i < 4; i++) (v >> (8 * i)) & 0xff];
    return (split(d.uint(0)), split(d.uint(1)), tx);
  }

  /// Orbs won, by tier (seed, bloom, aurora, crown).
  Future<(List<int>, TxRecord)> openPack() async {
    final (tx, logs) =
        await chain.sendTo(_lab, 'Opened an orb pack', _openPack, value: prices!.pack, marginPct: _margin);
    final ev = logs.firstWhere((l) => (l['topics'] as List).first == _topicPack);
    final d = AbiReader(ev['data'] as String);
    return ([for (var i = 0; i < 4; i++) d.uint(i)], tx);
  }

  Future<TxRecord> createDuel(List<String> squad, BigInt stake) async {
    final data = Abi.call(_createDuel, [null], [_bytes32Array(squad)]);
    final (tx, _) = await chain.sendTo(_lab, 'Opened a duel', data, value: stake);
    await refresh();
    return tx;
  }

  Future<TxRecord> cancelDuel(String id) async {
    final (tx, _) = await chain.sendTo(_lab, 'Cancelled a duel', Abi.call(_cancelDuel, [Abi.bytes32(id)]));
    await refresh();
    return tx;
  }

  /// Takes [duel] with [squad] ([mine] are its fighters, in order).
  Future<DuelResult> acceptDuel(OpenDuel duel, List<String> squad, List<Fighter> mine) async {
    final data = Abi.call(_acceptDuel, [Abi.bytes32(duel.id), null], [_bytes32Array(squad)]);
    final (tx, logs) =
        await chain.sendTo(_lab, 'Fought a duel', data, value: duel.stake, marginPct: _margin);
    final ev = logs.firstWhere((l) => (l['topics'] as List).first == _topicDuelSettled);
    final topics = (ev['topics'] as List).cast<String>();
    final d = AbiReader(ev['data'] as String);
    final won = '0x${topics[2].substring(26)}'.toLowerCase() == _me;
    final creatorAttacked = d.boolean(2);
    final theirs = [for (final x in duel.squad) x.fighter];
    final result = creatorAttacked
        ? simulateBattle(theirs, mine, d.big(1))
        : simulateBattle(mine, theirs, d.big(1));
    await refresh();
    return DuelResult(won, d.big(0), !creatorAttacked, result, tx.hash);
  }

  Future<TxRecord> withdrawWinnings() async {
    final (tx, _) = await chain.sendTo(_lab, 'Withdrew duel winnings', _withdrawWinnings);
    await refresh();
    return tx;
  }

  static String _bytes32Array(List<String> ids) => Abi.uint(ids.length) + ids.map(Abi.bytes32).join();
}
