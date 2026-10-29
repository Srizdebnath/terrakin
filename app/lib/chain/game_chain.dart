import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'abi.dart';
import 'auth.dart';
import 'backend_api.dart';
import 'monad_rpc.dart';

/// A Kin as stored on chain (Terrakin.Kin).
class ChainKin {
  ChainKin(this.id, this.species, this.grade, this.trait, this.landmark, this.trades, this.bondedAt, this.lat,
      this.lng, this.vigor, this.mods);
  final String id;
  final int species, grade, trait, trades, bondedAt;
  final bool landmark;

  /// Micro-degrees.
  final int lat, lng;
  final List<int> vigor;

  /// Basis points, 10000 = x1.
  final List<int> mods;
}

class ChainPrices {
  ChainPrices(AbiReader r)
      : grant = r.big(0),
        firstCharacter = r.big(1),
        nextCharacter = r.big(2),
        tradeReward = r.big(3),
        orb = [for (var i = 0; i < 4; i++) r.big(4 + i)],
        catchReward = [for (var i = 0; i < 5; i++) r.big(8 + i)],
        starterOrbs = r.uint(13),
        tradesPerDay = r.uint(14);
  final BigInt grant, firstCharacter, nextCharacter, tradeReward;
  final List<BigInt> orb, catchReward;
  final int starterOrbs, tradesPerDay;
}

/// One transaction the player sent, for the activity list.
class TxRecord {
  TxRecord(this.memo, this.hash, this.confirmMs, this.feeWei, this.at);
  final String memo, hash;
  final int confirmMs;
  final BigInt feeWei;
  final DateTime at;

  Map<String, dynamic> toJson() =>
      {'memo': memo, 'hash': hash, 'ms': confirmMs, 'fee': feeWei.toString(), 'at': at.toIso8601String()};
  factory TxRecord.fromJson(Map<String, dynamic> j) =>
      TxRecord(j['memo'], j['hash'], j['ms'], BigInt.parse(j['fee']), DateTime.parse(j['at']));
}

/// The player's on-chain state on Monad testnet and every game transaction.
///
/// Reads are single `eth_call`s to view functions (playerOf, kinOf,
/// charactersOf) so a full refresh is a handful of parallel requests.
class GameChain extends ChangeNotifier {
  GameChain(this.auth);
  final AuthService auth;

  // Selectors from `cast sig`.
  static const _createProfile = '0xbd3eaa6f';
  static const _mintCharacter = '0x2d93ee49';
  static const _buyOrbs = '0x8d4b5a4a';
  static const _bond = '0x3f473e50';
  static const _proposeTrade = '0xa839c09a';
  static const _acceptTrade = '0x564fdb0e';
  static const _isNameFree = '0x08a1cd05';
  static const _playerOf = '0xef75e3d1';
  static const _kinOf = '0xfe30146a';
  static const _prices = '0xd3419bf3';
  static const _charactersOf = '0xa0a76eb0';
  static const _topicBonded = '0x9411ba08801ee20e2aad82aa80e857a29b87da52fc2ed589a6d5c305c7256c42';
  static const _topicTradeProposed = '0x29604f1b615c6a6d88167a5ccd3c6539311d31f7cbdc559834ee14730f4cbf79';

  static const _errors = {
    '0xacf04168': 'You already bonded this Kin.',
    '0x5adf6387': 'This wallet was already funded.',
    '0x153736cd': 'Names are 4-8 letters, numbers or _.',
    '0x13c59d67': 'Unknown orb.',
    '0x5cd5d233': 'The bond voucher was rejected.',
    '0x9e4b2685': 'That name is taken.',
    '0xf60dfbf4': 'You already have a profile.',
    '0x6f860927': 'Create your profile first.',
    '0x788a686f': 'Wrong payment amount.',
    '0xad939594': 'Not enough orbs.',
    '0x203d82d8': 'This expired. Try again.',
    '0x4a636d30': 'That Kin isn\'t yours to trade.',
    '0xa3b36525': 'No such trade.',
    '0xb303dcbd': 'Someone already owns this hex.',
    '0x0ca0e4ce': 'Nobody owns this hex yet. Claim it instead.',
    '0x562a6b64': 'This hex is shielded right now.',
    '0x29e2a762': 'Pick 1 to 3 different Kin.',
    '0x81ef8c64': 'That auction isn\'t open.',
    '0xa0d26eb6': 'Your bid is too low.',
    '0x90b8ec18': 'A transfer failed.',
    '0x21c6aca1': 'That duel is gone.',
    '0x681fcdf7': 'Their squad changed. They need to cancel and re-open.',
    '0xd71aef93': 'You\'re already in a crew.',
    '0xa25c970a': 'No such crew.',
    '0xf36efb6f': 'That crew is full (30 max).',
    '0x988f5333': 'That tag is taken.',
    '0x1c491e38': 'Only the captain can do that.',
    '0xc19f17a9': 'Approve the market first.',
    '0x32166ff8': 'That listing is gone.',
    '0xd7815800': 'The seller no longer has that Kin.',
    '0x07a3057c': 'Check the bounty: reward, radius (100 m-50 km) and deadline (1 h-30 days).',
    '0xde151d99': 'That bounty is gone.',
    '0x2d011ca7': 'That Kin doesn\'t match the bounty.',
    '0x085de625': 'You can cancel after the deadline.',
    '0x95fe3ea5': 'Raid pass rejected. Stand at the Landmark and retry.',
    '0x84c77753': 'The boss already fell today.',
    '0xa0fa2997': 'Loot unlocks when the boss falls or the day ends.',
    '0xf9820cc1': 'Nothing to claim.',
    '0x1c2506c8': 'Your loop was cut: a rival took a hex on your trail while you walked.',
    '0x6954f21c': 'That loop doesn\'t work. Walk at least 6 hexes around something.',
    '0xd70a0e30': 'That stretch of walking was already paid.',
    '0x82e65044': 'Walk 500 m to earn MON.',
    '0xbbcba066': 'You\'ve earned today\'s walking MON. More tomorrow.',
    '0xb9c049a0': 'The walking reward pool is empty right now.',
    '0x1cdde67b': 'This Convergence isn\'t open right now.',
    '0x003b2682': 'You\'re already in this circle.',
    '0x9445b059': 'Check the drop: a riddle up to 140 characters, 1 h-30 days, and MON or a Kin inside.',
    '0x72ec8f1a': 'That drop is gone.',
  };

  late MonadRpc rpc;
  String game = '', characters = '', territory = '', lab = '', crews = '', season = '', market = '', bounties = '', raids = '', convergence = '', drops = '', strides = '', explorer = 'https://testnet.monadexplorer.com';
  bool configured = false;

  BigInt balance = BigInt.zero;
  String name = '';
  bool funded = false;
  List<int> orbs = [0, 0, 0, 0];
  List<(String, int)> characterTokens = [];
  List<ChainKin> kin = [];
  ChainPrices? prices;
  final txs = <TxRecord>[];
  DateTime? syncedAt;
  Timer? _poll;

  String? get address => auth.address;
  bool get hasProfile => name.isNotEmpty;

  Future<void> configure() async {
    final c = await BackendApi.config();
    rpc = MonadRpc(c['rpc'] as String, chainId: (c['chainId'] as num).toInt());
    game = c['game'] as String? ?? '';
    characters = c['characters'] as String? ?? '';
    territory = c['territory'] as String? ?? '';
    lab = c['lab'] as String? ?? '';
    crews = c['crews'] as String? ?? '';
    season = c['season'] as String? ?? '';
    market = c['market'] as String? ?? '';
    bounties = c['bounties'] as String? ?? '';
    raids = c['raids'] as String? ?? '';
    convergence = c['convergence'] as String? ?? '';
    drops = c['drops'] as String? ?? '';
    strides = c['strides'] as String? ?? '';
    explorer = c['explorer'] as String? ?? explorer;
    configured = game.isNotEmpty;
    final prefs = await SharedPreferences.getInstance();
    txs
      ..clear()
      ..addAll([for (final s in prefs.getStringList('txlog.v1') ?? const <String>[]) TxRecord.fromJson(jsonDecode(s))]);
  }

  /// Drops the signed-out player's state so the next account starts clean.
  void forget() {
    _poll?.cancel();
    _poll = null;
    balance = BigInt.zero;
    name = '';
    funded = false;
    orbs = [0, 0, 0, 0];
    characterTokens = [];
    kin = [];
    syncedAt = null;
    notifyListeners();
  }

  /// Keeps balance and inventory fresh while the app is open.
  void startPolling() {
    _poll ??= Timer.periodic(const Duration(seconds: 15), (_) => sync().catchError((Object _) {}));
  }

  Future<void> sync() async {
    final a = address;
    if (!configured || a == null) return;
    final addr = Abi.address(a);
    final r = await Future.wait([
      rpc.balance(a),
      rpc.ethCall(game, '$_playerOf$addr'),
      rpc.ethCall(game, '$_kinOf$addr'),
      rpc.ethCall(characters, '$_charactersOf$addr'),
      if (prices == null) rpc.ethCall(game, _prices),
    ]);
    balance = r[0] as BigInt;
    final p = AbiReader(r[1] as String);
    name = p.string(0);
    funded = p.boolean(1);
    orbs = [for (var i = 0; i < 4; i++) p.uint(2 + i)];

    final k = AbiReader(r[2] as String);
    final ids = k.arrayAt(0), data = k.arrayAt(1);
    kin = [
      for (var i = 0; i < k.uint(ids); i++)
        () {
          final b = data + 1 + i * 16;
          return ChainKin(
            k.bytes32(ids + 1 + i),
            k.uint(b),
            k.uint(b + 1),
            k.uint(b + 2),
            k.boolean(b + 3),
            k.uint(b + 4),
            k.uint(b + 5),
            k.signed(b + 6, 32),
            k.signed(b + 7, 32),
            [for (var j = 0; j < 4; j++) k.uint(b + 8 + j)],
            [for (var j = 0; j < 4; j++) k.uint(b + 12 + j)],
          );
        }(),
    ];

    final c = AbiReader(r[3] as String);
    final cIds = c.arrayAt(0), cStyles = c.arrayAt(1);
    characterTokens = [for (var i = 0; i < c.uint(cIds); i++) (c.bytes32(cIds + 1 + i), c.uint(cStyles + 1 + i))];
    if (r.length > 4) prices = ChainPrices(AbiReader(r[4] as String));
    syncedAt = DateTime.now();
    notifyListeners();
  }

  // ---- Actions --------------------------------------------------------------

  /// Asks the backend for the starter grant (once per wallet).
  Future<void> fundIfNeeded() async {
    if (funded) return;
    await BackendApi.fund(await auth.accessToken());
    await sync();
  }

  Future<bool> isNameFree(String n) async {
    final out = await rpc.ethCall(game, Abi.call(_isNameFree, [null], [Abi.string(n)]));
    return AbiReader(out).boolean(0);
  }

  Future<TxRecord> createProfile(String n, int style) =>
      _send('Created $n · first character', Abi.call(_createProfile, [null, Abi.uint(style)], [Abi.string(n)]),
          value: prices!.firstCharacter);

  Future<TxRecord> mintCharacter(int style) =>
      _send('Minted a character', Abi.call(_mintCharacter, [Abi.uint(style)]), value: prices!.nextCharacter);

  Future<TxRecord> buyOrbs(int orb, int qty, String label) =>
      _send('Bought $qty× $label', Abi.call(_buyOrbs, [Abi.uint(orb), Abi.uint(qty)]),
          value: prices!.orb[orb] * BigInt.from(qty));

  /// Mints the Kin with a backend voucher, burning the orbs thrown. Returns the
  /// Kin id and the MON reward paid.
  Future<(String, BigInt, TxRecord)> bond(Map<String, dynamic> v, String signature, List<int> orbsUsed, String memo) async {
    final tuple = [
      Abi.address(v['player']),
      Abi.bytes32(v['spawnId']),
      Abi.uint(v['species']),
      Abi.uint(v['grade']),
      Abi.uint(v['vigor']),
      Abi.uint(v['trait']),
      Abi.boolean(v['landmark']),
      Abi.word(BigInt.from(v['lat'] as int)),
      Abi.word(BigInt.from(v['lng'] as int)),
      Abi.word(BigInt.parse(v['hexId'].toString())),
      Abi.word(BigInt.parse(v['zone'].toString())),
      Abi.word(BigInt.parse(v['deadline'].toString())),
    ];
    final data = Abi.call(_bond, [...tuple, null, ...orbsUsed.map(Abi.uint)], [Abi.hexBytes(signature)]);
    final (tx, logs) = await _sendWithLogs(memo, data);
    final ev = logs.firstWhere((l) => (l['topics'] as List).first == _topicBonded);
    final reward = AbiReader(ev['data'] as String).big(3);
    return ((ev['topics'] as List)[2] as String, reward, tx);
  }

  Future<(String, TxRecord)> proposeTrade(String myKin, String theirKin, String partner) async {
    final data = Abi.call(_proposeTrade, [Abi.bytes32(myKin), Abi.bytes32(theirKin), Abi.address(partner)]);
    final (tx, logs) = await _sendWithLogs('Offered a trade', data);
    final ev = logs.firstWhere((l) => (l['topics'] as List).first == _topicTradeProposed);
    return ((ev['topics'] as List)[1] as String, tx);
  }

  Future<TxRecord> acceptTrade(String tradeId) =>
      _send('Completed a trade', Abi.call(_acceptTrade, [Abi.bytes32(tradeId)]));

  Future<TxRecord> _send(String memo, String data, {BigInt? value}) async =>
      (await _sendWithLogs(memo, data, value: value)).$1;

  Future<(TxRecord, List<Map<String, dynamic>>)> _sendWithLogs(String memo, String data, {BigInt? value}) =>
      sendTo(game, memo, data, value: value);

  /// Sends a game transaction to [to] (the game or territory contract),
  /// records it in the activity list, and returns its receipt logs.
  Future<(TxRecord, List<Map<String, dynamic>>)> sendTo(String to, String memo, String data,
      {BigInt? value, int marginPct = 2}) async {
    try {
      final r = await rpc.send(
          from: address!, to: to, data: data, value: value, sign: auth.signTransaction, marginPct: marginPct);
      final rec = TxRecord(memo, r.hash, r.confirmIn.inMilliseconds, r.feeWei, DateTime.now());
      txs.insert(0, rec);
      if (txs.length > 40) txs.removeLast();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('txlog.v1', [for (final t in txs) jsonEncode(t.toJson())]);
      unawaited(sync());
      return (rec, r.logs);
    } on RpcException catch (e) {
      throw ChainException(_explain(e));
    }
  }

  String _explain(RpcException e) {
    final d = e.data;
    if (d != null && d.length >= 10) {
      final known = _errors[d.substring(0, 10)];
      if (known != null) return known;
    }
    final m = e.message.toLowerCase();
    if (m.contains('insufficient') || m.contains('balance')) return 'Not enough MON for this and its gas.';
    return e.message;
  }

  String txUrl(String hash) => '$explorer/tx/$hash';

  /// Read-only call to [to], for other chain services.
  Future<AbiReader> read(String to, String data) async => AbiReader(await rpc.ethCall(to, data));

  static const _nameOf = '0xf5c57382';
  final _names = <String, String>{};

  /// A player's IGN, cached.
  Future<String> nameOf(String addr) async {
    final key = addr.toLowerCase();
    final hit = _names[key];
    if (hit != null) return hit;
    final n = (await read(game, '$_nameOf${Abi.address(addr)}')).string(0);
    return _names[key] = n;
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}

class ChainException implements Exception {
  ChainException(this.message);
  final String message;
  @override
  String toString() => message;
}
