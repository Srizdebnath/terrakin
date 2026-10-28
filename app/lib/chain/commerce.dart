import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/battle.dart';
import '../core/hexgrid.dart';
import 'abi.dart';
import 'backend_api.dart';
import 'game_chain.dart';
import 'territory.dart';

class Listing {
  const Listing(this.kinId, this.seller, this.sellerName, this.price, this.species, this.grade, this.fighter);
  final String kinId, seller, sellerName;
  final BigInt price;
  final int species, grade;
  final Fighter fighter;
}

class Bounty {
  const Bounty(this.id, this.poster, this.posterName, this.species, this.minGrade, this.center, this.radiusM,
      this.deadline, this.reward);
  final String id, poster, posterName;
  final int species; // 255 = any
  final int minGrade, radiusM;
  final LatLng center;
  final DateTime deadline;
  final BigInt reward;
}

class RaidState {
  const RaidState(this.zone, this.day, this.species, this.hpLeft, this.hpMax, this.pot, this.totalDamage, this.cleared,
      this.finisher, this.myDamage, this.claimed);
  final int zone, day, species, hpLeft, hpMax, totalDamage, myDamage;
  final BigInt pot;
  final bool cleared, claimed;
  final String finisher;
}

class RaidHit {
  const RaidHit(this.damage, this.felled, this.hpBefore, this.result, this.boss, this.hash);
  final int damage, hpBefore;
  final bool felled;
  final BattleResult result;
  final Fighter boss;
  final String hash;
}

/// The Kin market, bounties and Landmark raids (TerrakinMarket/Bounties/Raids).
class CommerceService extends ChangeNotifier {
  CommerceService(this.chain, this.territory);
  final GameChain chain;
  final TerritoryService territory;

  static const _list = '0x08567145';
  static const _delist = '0x964bc33f';
  static const _buy = '0xd96a094a';
  static const _all = '0x10c4e8b0';
  static const _withdrawProceeds = '0x9038e693';
  static const _proceeds = '0x35adde54';
  static const _post = '0x2a69b973';
  static const _claimBounty = '0xc3490263';
  static const _cancel = '0x40e58ee5';
  static const _open = '0xfcfff16f';
  static const _matches = '0x89ed3ecb';
  static const _raidAttack = '0x9c4f49dc';
  static const _raidClaim = '0x66b5075d';
  static const _raidInfo = '0x52d88318';
  static const _setApprovalForAll = '0xa22cb465';
  static const _isApprovedForAll = '0xe985e9c5';
  static const _topicRaidAttack = '0xbe08ca91d3c7bef603277c9b71c2ec08216ab299f760427462fb8ccd11da2ada';

  /// Mirrors TerrakinRaids' boss stats.
  static const bossAtk = 140, bossDef = 100, bossSpd = 60;

  List<Listing> listings = [];
  List<Bounty> bounties = [];
  BigInt proceeds = BigInt.zero;

  String get _me => chain.address!;

  // ---- Market ---------------------------------------------------------------

  Future<void> refreshMarket() async {
    if (chain.market.isEmpty) return;
    final r = await chain.read(chain.market, _all);
    final ids = r.arrayAt(0), sellers = r.arrayAt(1), prices = r.arrayAt(2), live = r.arrayAt(3);
    final n = r.uint(ids);
    final kinIds = <String>[];
    final rows = <(String, String, BigInt)>[];
    for (var i = 0; i < n; i++) {
      if (!r.boolean(live + 1 + i)) continue;
      final id = r.bytes32(ids + 1 + i);
      kinIds.add(id);
      rows.add((id, r.address(sellers + 1 + i).toLowerCase(), r.big(prices + 1 + i)));
    }
    final packed = kinIds.isEmpty ? <(String, BigInt)>[] : await territory.kinPacked(kinIds);
    listings = [
      for (var i = 0; i < rows.length; i++)
        await () async {
          final (sp, gr, vig, mods) = TerritoryService.unpackKin(packed[i].$2);
          return Listing(rows[i].$1, rows[i].$2, await chain.nameOf(rows[i].$2), rows[i].$3, sp, gr,
              Fighter.of(sp, gr, vig, mods, home: false));
        }(),
    ];
    proceeds = (await chain.read(chain.market, '$_proceeds${Abi.address(_me)}')).big(0);
    notifyListeners();
  }

  /// One-time `setApprovalForAll` so [operator] can move Kin on the player's
  /// behalf (the market for sales, bounties for deliveries).
  Future<void> _approve(String operator) async {
    final r = await chain.read(chain.game, Abi.call(_isApprovedForAll, [Abi.address(_me), Abi.address(operator)]));
    if (r.boolean(0)) return;
    await chain.sendTo(chain.game, 'Approved Kin transfers',
        Abi.call(_setApprovalForAll, [Abi.address(operator), Abi.boolean(true)]));
  }

  Future<void> list(String kinId, BigInt price) async {
    await _approve(chain.market);
    await chain.sendTo(chain.market, 'Listed a Kin', Abi.call(_list, [Abi.bytes32(kinId), Abi.word(price)]));
    await refreshMarket();
  }

  Future<void> delist(String kinId) async {
    await chain.sendTo(chain.market, 'Delisted a Kin', Abi.call(_delist, [Abi.bytes32(kinId)]));
    await refreshMarket();
  }

  Future<TxRecord> buy(Listing l) async {
    final (tx, _) =
        await chain.sendTo(chain.market, 'Bought a Kin', Abi.call(_buy, [Abi.bytes32(l.kinId)]), value: l.price);
    await refreshMarket();
    return tx;
  }

  Future<void> withdrawProceeds() async {
    await chain.sendTo(chain.market, 'Withdrew sale proceeds', _withdrawProceeds);
    await refreshMarket();
  }

  // ---- Bounties -------------------------------------------------------------

  Future<void> refreshBounties() async {
    if (chain.bounties.isEmpty) return;
    final r = await chain.read(chain.bounties, _open);
    final ids = r.arrayAt(0), list = r.arrayAt(1);
    final n = r.uint(ids);
    final out = <Bounty>[];
    for (var i = 0; i < n; i++) {
      final b = list + 1 + i * 10;
      final poster = r.address(b).toLowerCase();
      out.add(Bounty(
        r.bytes32(ids + 1 + i),
        poster,
        await chain.nameOf(poster),
        r.uint(b + 1),
        r.uint(b + 2),
        LatLng(r.signed(b + 3, 32) / 1e6, r.signed(b + 4, 32) / 1e6),
        r.uint(b + 5),
        DateTime.fromMillisecondsSinceEpoch(r.uint(b + 8) * 1000),
        r.big(b + 9),
      ));
    }
    bounties = out..sort((a, b) => b.reward.compareTo(a.reward));
    notifyListeners();
  }

  Future<void> postBounty({
    required int species,
    required int minGrade,
    required LatLng center,
    required int radiusM,
    required Duration within,
    required BigInt reward,
  }) async {
    final lat = (center.latitude * 1e6).round(), lng = (center.longitude * 1e6).round();
    final deadline = DateTime.now().add(within).millisecondsSinceEpoch ~/ 1000;
    final data = Abi.call(_post, [
      Abi.uint(species),
      Abi.uint(minGrade),
      Abi.word(BigInt.from(lat)),
      Abi.word(BigInt.from(lng)),
      Abi.uint(radiusM),
      Abi.uint(HexGrid.cosE6(lat)),
      Abi.uint(deadline),
    ]);
    await chain.sendTo(chain.bounties, 'Posted a bounty', data, value: reward);
    await refreshBounties();
  }

  Future<bool> matches(Bounty b, String kinId) async => (await chain.read(
          chain.bounties, Abi.call(_matches, [Abi.bytes32(b.id), Abi.bytes32(kinId), Abi.address(_me)])))
      .boolean(0);

  Future<void> claimBounty(Bounty b, String kinId) async {
    await _approve(chain.bounties);
    await chain.sendTo(chain.bounties, 'Claimed a bounty', Abi.call(_claimBounty, [Abi.bytes32(b.id), Abi.bytes32(kinId)]));
    await refreshBounties();
  }

  Future<void> cancelBounty(Bounty b) async {
    await chain.sendTo(chain.bounties, 'Cancelled a bounty', Abi.call(_cancel, [Abi.bytes32(b.id)]));
    await refreshBounties();
  }

  // ---- Raids ----------------------------------------------------------------

  Future<RaidState> raid(int zone, int day) async {
    final r = await chain.read(
        chain.raids, Abi.call(_raidInfo, [Abi.word(HexGrid.toUint64(zone)), Abi.uint(day), Abi.address(_me)]));
    return RaidState(zone, day, r.uint(0), r.uint(1), r.uint(2), r.big(3), r.uint(4), r.boolean(5),
        r.address(6).toLowerCase(), r.uint(7), r.boolean(8));
  }

  /// Attacks today's boss at the Landmark the player stands at. [mine] are
  /// the squad's fighters in order, for the replay.
  Future<RaidHit> attackRaid(LatLng at, List<String> squad, List<Fighter> mine) async {
    final pass = await BackendApi.raidPass(await chain.auth.accessToken(), at.latitude, at.longitude);
    final p = pass['pass'] as Map<String, dynamic>;
    final head = Abi.address(p['player']) +
        Abi.word(BigInt.parse(p['zone'].toString())) +
        Abi.uint(p['day'] as int) +
        Abi.word(BigInt.parse(p['deadline'].toString()));
    final data = Abi.call(_raidAttack, [head, null, null],
        [Abi.hexBytes(pass['signature'] as String), Abi.uint(squad.length) + squad.map(Abi.bytes32).join()]);
    final (tx, logs) = await chain.sendTo(chain.raids, 'Hit a raid boss', data,
        value: BigInt.from(10).pow(16), marginPct: 30); // 0.01 MON entry
    final ev = logs.firstWhere((l) => (l['topics'] as List).first == _topicRaidAttack);
    final d = AbiReader(ev['data'] as String);
    final hpBefore = d.uint(3);
    final boss = Fighter(hpBefore, bossAtk, bossDef, bossSpd);
    return RaidHit(d.uint(0), d.boolean(1), hpBefore, simulateBattle(mine, [boss], d.big(2)), boss, tx.hash);
  }

  Future<void> claimRaid(int zone, int day) =>
      chain.sendTo(chain.raids, 'Claimed raid loot', Abi.call(_raidClaim, [Abi.word(HexGrid.toUint64(zone)), Abi.uint(day)]));
}
