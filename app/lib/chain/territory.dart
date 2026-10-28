import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/battle.dart';
import '../core/hexgrid.dart';
import '../data/spawn_engine.dart';
import 'abi.dart';
import 'backend_api.dart';
import 'game_chain.dart';

class TerritoryPrices {
  TerritoryPrices(AbiReader r)
      : claim = r.big(0),
        attackFee = r.big(1),
        minBid = r.big(2),
        cutBps = r.uint(3),
        landmarkCutBps = r.uint(4),
        bidStepBps = r.uint(5),
        shield = Duration(seconds: r.uint(6));
  final BigInt claim, attackFee, minBid;
  final int cutBps, landmarkCutBps, bidStepBps;
  final Duration shield;
}

/// What the map needs to colour a hex.
class HexState {
  const HexState(this.owner, this.shieldUntil, this.defenders);
  final String? owner; // null when unclaimed
  final DateTime shieldUntil;
  final int defenders;
  bool get shielded => DateTime.now().isBefore(shieldUntil);
}

/// A stationed Kin as the contract will field it.
class Defender {
  const Defender(this.id, this.species, this.grade, this.fighter);
  final String id;
  final int species, grade;
  final Fighter fighter;
}

class HexDetail {
  const HexDetail(this.id, this.state, this.ownerName, this.since, this.defenders);
  final int id;
  final HexState state;
  final String ownerName;
  final DateTime? since;
  final List<Defender> defenders; // only those that would actually fight
}

class Auction {
  const Auction(this.zone, this.day, this.bidder, this.amount, this.bidderName);
  final int zone, day;
  final String? bidder;
  final BigInt amount;
  final String bidderName;
}

class BattleOutcome {
  const BattleOutcome(this.won, this.attackers, this.defenders, this.result, this.hash);
  final bool won;
  final List<Fighter> attackers;
  final List<Defender> defenders; // as the contract fielded them
  final BattleResult result; // replayed locally from the event's seed
  final String hash;
}

/// Territory on Monad: the hexes around the player, claiming, defending,
/// battles and the daily Landmark zone auctions (TerrakinTerritory.sol).
class TerritoryService extends ChangeNotifier {
  TerritoryService(this.chain);
  final GameChain chain;

  static const _claim = '0x0406b2e3';
  static const _station = '0x40bc2087';
  static const _attack = '0xf7554af1';
  static const _bid = '0x942c654d';
  static const _withdrawRefund = '0x110f8874';
  static const _refunds = '0xbc3da535';
  static const _bids = '0xf450b04c';
  static const _hexStates = '0xb88f3ffb';
  static const _hexesOf = '0x27581100';
  static const _defendersOf = '0x94fad6dd';
  static const _hexes = '0x559b9d95';
  static const _prices = '0xd3419bf3';
  static const _kinPacked = '0xbe25fad2';
  static const _stationedAt = '0x8e5d603c';
  static const _topicBattle = '0xd5d15a0971aeb4ca9c92cc3b8473f35fc3cad9c063c2ed627a8b64314dadfccd';
  static const _zero = '0x0000000000000000000000000000000000000000';

  /// How far around the player hexes are shown.
  static const viewMetres = 420.0;

  TerritoryPrices? prices;
  final states = <int, HexState>{};
  final _corners = <int, List<LatLng>>{};
  List<int> mine = [];
  BigInt refunds = BigInt.zero;
  int? here; // the hex the player stands in
  Timer? _poll;
  LatLng Function()? _where;
  bool _busy = false;

  bool get enabled => chain.configured && chain.territory.isNotEmpty;
  String get _land => chain.territory;
  String? get _me => chain.address?.toLowerCase();

  bool isMine(HexState s) => s.owner != null && s.owner == _me;

  List<LatLng> corners(int id) => _corners.putIfAbsent(id, () => HexGrid.corners(id));

  /// Keeps the hexes around [where] fresh while the map is open.
  void start(LatLng Function() where) {
    _where = where;
    _poll ??= Timer.periodic(const Duration(seconds: 20), (_) => refresh().catchError((Object _) {}));
    unawaited(refresh().catchError((Object _) {}));
  }

  /// Call on each GPS fix: refetches straight away when the player crosses
  /// into another hex.
  void moved(LatLng p) {
    final id = HexGrid.idAt(p);
    if (id == here) return;
    here = id;
    notifyListeners();
    unawaited(refresh().catchError((Object _) {}));
  }

  Future<void> refresh() async {
    final p = _where?.call();
    final me = chain.address;
    if (!enabled || p == null || me == null || _busy) return;
    _busy = true;
    try {
      here = HexGrid.idAt(p);
      final ids = HexGrid.around(p, viewMetres);
      final r = await Future.wait([
        chain.read(_land, Abi.call(_hexStates, [null], [_uint64Array(ids)])),
        chain.read(_land, '$_hexesOf${Abi.address(me)}'),
        chain.read(_land, '$_refunds${Abi.address(me)}'),
        if (prices == null) chain.read(_land, _prices),
      ]);
      final s = r[0];
      final o = s.arrayAt(0), sh = s.arrayAt(1), d = s.arrayAt(2);
      states.clear();
      for (var i = 0; i < s.uint(o); i++) {
        final owner = s.address(o + 1 + i);
        states[ids[i]] = HexState(
          owner == _zero ? null : owner.toLowerCase(),
          DateTime.fromMillisecondsSinceEpoch(s.uint(sh + 1 + i) * 1000),
          s.uint(d + 1 + i),
        );
      }
      final m = r[1], ma = m.arrayAt(0);
      mine = [for (var i = 0; i < m.uint(ma); i++) HexGrid.fromUint64(m.big(ma + 1 + i))];
      refunds = r[2].big(0);
      if (r.length > 3) prices = TerritoryPrices(r[3]);
      notifyListeners();
    } finally {
      _busy = false;
    }
  }

  /// Owner, shield and the defenders that would really fight for [id].
  Future<HexDetail> detail(int id) async {
    final hx = Abi.word(HexGrid.toUint64(id));
    final r = await Future.wait([
      chain.read(_land, '$_hexes$hx'),
      chain.read(_land, '$_defendersOf$hx'),
    ]);
    final owner = r[0].address(0).toLowerCase();
    final state = HexState(owner == _zero ? null : owner,
        DateTime.fromMillisecondsSinceEpoch(r[0].uint(2) * 1000), 0);
    final da = r[1].arrayAt(0);
    final ids = [for (var i = 0; i < r[1].uint(da); i++) r[1].bytes32(da + 1 + i)];
    final defenders = <Defender>[];
    if (ids.isNotEmpty && state.owner != null) {
      final packed = await kinPacked(ids);
      final at = await Future.wait([for (final k in ids) chain.read(_land, '$_stationedAt${Abi.bytes32(k)}')]);
      for (var i = 0; i < ids.length; i++) {
        final (who, w) = packed[i];
        if (who != state.owner || at[i].big(0) != HexGrid.toUint64(id)) continue;
        final (sp, gr, vig, mods) = unpackKin(w);
        defenders.add(Defender(ids[i], sp, gr, Fighter.of(sp, gr, vig, mods, home: true)));
      }
    }
    final name = state.owner == null ? '' : await chain.nameOf(state.owner!);
    final since = state.owner == null ? null : DateTime.fromMillisecondsSinceEpoch(r[0].uint(1) * 1000);
    return HexDetail(id, HexState(state.owner, state.shieldUntil, defenders.length), name, since, defenders);
  }

  /// Owner and packed record of each Kin, straight from Terrakin.kinPacked.
  Future<List<(String, BigInt)>> kinPacked(List<String> ids) async {
    final r = await chain.read(chain.game, Abi.call(_kinPacked, [null], [_bytes32Array(ids)]));
    final o = r.arrayAt(0), p = r.arrayAt(1);
    return [for (var i = 0; i < ids.length; i++) (r.address(o + 1 + i).toLowerCase(), r.big(p + 1 + i))];
  }

  /// Terrakin's packed Kin layout (see Terrakin._pack).
  static (int, int, List<int>, List<int>) unpackKin(BigInt w) {
    int bits(int shift, int width) => ((w >> shift) & ((BigInt.one << width) - BigInt.one)).toInt();
    return (
      bits(0, 8),
      bits(8, 8),
      [for (var i = 0; i < 4; i++) bits(152 + 8 * i, 8)],
      [for (var i = 0; i < 4; i++) bits(184 + 16 * i, 16)],
    );
  }

  // ---- Actions --------------------------------------------------------------

  Future<(String, String)> _presence(LatLng at, String token) async {
    final r = await BackendApi.presence(token, at.latitude, at.longitude);
    final p = r['presence'] as Map<String, dynamic>;
    final head = Abi.address(p['player']) +
        Abi.word(BigInt.parse(p['hexId'].toString())) +
        Abi.word(BigInt.parse(p['deadline'].toString()));
    return (head, r['signature'] as String);
  }

  /// Claims the hex the player stands in with [squad] (1-3 Kin ids).
  Future<TxRecord> claim(LatLng at, List<String> squad) async {
    final (p, sig) = await _presence(at, await chain.auth.accessToken());
    final data = Abi.call(_claim, [p, null, null], [Abi.hexBytes(sig), _bytes32Array(squad)]);
    final (tx, _) = await chain.sendTo(_land, 'Claimed a hex', data, value: prices!.claim);
    await refresh();
    return tx;
  }

  Future<TxRecord> station(int hexId, List<String> squad) async {
    final data = Abi.call(_station, [Abi.word(HexGrid.toUint64(hexId)), null], [_bytes32Array(squad)]);
    final (tx, _) = await chain.sendTo(_land, 'Changed hex defenders', data);
    await refresh();
    return tx;
  }

  /// Attacks the hex the player stands in. [mine] are the attacker's fighters
  /// in squad order and [theirs] the defenders as fetched by [detail]; the
  /// replay uses whichever of them the contract actually fielded.
  Future<BattleOutcome> attack(LatLng at, List<String> squad, List<Fighter> mine, List<Defender> theirs) async {
    final (p, sig) = await _presence(at, await chain.auth.accessToken());
    final data = Abi.call(_attack, [p, null, null], [Abi.hexBytes(sig), _bytes32Array(squad)]);
    // The battle's path depends on the block's randomness, so the estimate
    // can undershoot: give it a wide margin.
    final (tx, logs) = await chain.sendTo(_land, 'Attacked a hex', data, value: prices!.attackFee, marginPct: 30);
    final ev = logs.firstWhere((l) => (l['topics'] as List).first == _topicBattle);
    final d = AbiReader(ev['data'] as String);
    final won = d.boolean(0);
    final seed = d.big(1);
    final da = d.arrayAt(3);
    final fielded = [for (var i = 0; i < d.uint(da); i++) d.bytes32(da + 1 + i)];
    final defenders = [for (final id in fielded) theirs.firstWhere((x) => x.id == id)];
    final result = simulateBattle(mine, [for (final x in defenders) x.fighter], seed);
    unawaited(refresh().catchError((Object _) {}));
    return BattleOutcome(won, mine, defenders, result, tx.hash);
  }

  // ---- Landmark auctions ----------------------------------------------------

  static int utcDay(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  /// The Landmark zone around [p] and tomorrow's Landmark Kin there, which is
  /// what the auction is for.
  static (int, Spawn)? tomorrowsLandmark(LatLng p) {
    final tomorrow = DateTime.now().toUtc().add(const Duration(days: 1));
    final s = SpawnEngine.landmarks(p, now: tomorrow, ring: 0).firstOrNull;
    final zone = s == null ? null : HexGrid.zoneOfSpawn(s.id);
    return zone == null ? null : (zone, s!);
  }

  Future<Auction> auction(int zone, int day) async {
    final r = await chain.read(
        _land, Abi.call(_bids, [Abi.word(HexGrid.toUint64(zone)), Abi.uint(day)]));
    final who = r.address(0).toLowerCase();
    final bidder = who == _zero ? null : who;
    return Auction(zone, day, bidder, r.big(1), bidder == null ? '' : await chain.nameOf(bidder));
  }

  /// The smallest bid that would lead [a].
  BigInt minimumBid(Auction a) => a.bidder == null
      ? prices!.minBid
      : a.amount * BigInt.from(10000 + prices!.bidStepBps) ~/ BigInt.from(10000) + BigInt.one;

  Future<TxRecord> bid(int zone, int day, BigInt amount) async {
    final data = Abi.call(_bid, [Abi.word(HexGrid.toUint64(zone)), Abi.uint(day)]);
    final (tx, _) = await chain.sendTo(_land, 'Bid on a Landmark zone', data, value: amount);
    await refresh();
    return tx;
  }

  Future<TxRecord> withdrawRefund() async {
    final (tx, _) = await chain.sendTo(_land, 'Withdrew outbid MON', _withdrawRefund);
    await refresh();
    return tx;
  }

  static String _uint64Array(List<int> ids) =>
      Abi.uint(ids.length) + ids.map((id) => Abi.word(HexGrid.toUint64(id))).join();
  static String _bytes32Array(List<String> ids) => Abi.uint(ids.length) + ids.map(Abi.bytes32).join();

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
