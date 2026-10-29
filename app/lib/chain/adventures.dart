import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/hexgrid.dart';
import 'abi.dart';
import 'backend_api.dart';
import 'game_chain.dart';
import 'territory.dart';

/// A Convergence: a Mythic at a real public place for 20 minutes, bonded
/// only by a circle of 3+ players standing there together.
class Convergence {
  Convergence(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        at = LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
        species = j['species'] as int,
        opensAt = DateTime.fromMillisecondsSinceEpoch(j['opensAt'] as int);
  final String id, name;
  final LatLng at;
  final int species;
  final DateTime opensAt;

  static const window = Duration(minutes: 20);
  static const announce = Duration(hours: 1);
  static const reachM = 40.0;
  static const together = Duration(minutes: 5);
  static const circle = 3;

  DateTime get closesAt => opensAt.add(window);
  bool get open {
    final now = DateTime.now();
    return !now.isBefore(opensAt) && now.isBefore(closesAt);
  }

  bool get announced => DateTime.now().isAfter(opensAt.subtract(announce)) && DateTime.now().isBefore(closesAt);
}

/// Who is in a Convergence circle right now.
class Circle {
  const Circle(this.joined, this.recent, this.iBonded, this.iJoined);
  final int joined; // ever
  final int recent; // within the last 5 minutes
  final bool iBonded, iJoined;
}

class DeadDrop {
  const DeadDrop(this.id, this.dropper, this.forWho, this.hexId, this.expiresAt, this.done, this.kinId, this.mon,
      this.riddle, this.dropperName);
  final BigInt id; // keccak(dropper, n): no global counter
  final int hexId;
  final String dropper, dropperName;
  final String? forWho; // null: anyone
  final DateTime expiresAt;
  final bool done;
  final String? kinId;
  final BigInt mon;
  final String riddle;

  bool get expired => DateTime.now().isAfter(expiresAt);
  LatLng get area => HexGrid.center(hexId);
}

/// What came of a claim attempt at a drop.
enum DropSearch { cold, warm, found }

/// Loop Capture, Convergence and Dead Drops: the three things that need the
/// player's body somewhere real, proven by the backend and settled on Monad.
class AdventureService extends ChangeNotifier {
  AdventureService(this.chain, this.territory);
  final GameChain chain;
  final TerritoryService territory;

  static const _claimLoop = '0xaf4299f2';
  static const _join = '0x7794202d';
  static const _attendees = '0xf56fbf1f';
  static const _bonded = '0x9180ba7b';
  static const _drop = '0x2a155d45';
  static const _claimDrop = '0xd7f48057';
  static const _reclaim = '0x2dabbeed';
  static const _openIn = '0xcba9fa38';
  static const _dropsBy = '0x8c6a2128';
  static const _info = '0x2e340599';
  static const _setApprovalForAll = '0xa22cb465';
  static const _isApprovedForAll = '0xe985e9c5';
  static const _topicLoopClosed = '0xca5fe32feb9ed252cb3856f35f7dac32374508c9d55bc3382e7945209483a521';
  static const _topicCircleBonded = '0x11eed6167c2dbe5723c79d3331f04d90bfcdf18ab2f8404ce1008c89834e3757';
  static const _nameKey = '0xeb506f9e';
  static const _nameOwner = '0x1493ecae';
  static const _zero = '0x0000000000000000000000000000000000000000';

  String get _me => chain.address!.toLowerCase();
  Future<String> _token() => chain.auth.accessToken();

  // ------------------------------------------------------------ loop capture

  bool looping = false;
  final stamps = <Map<String, dynamic>>[];
  final trail = <int>[]; // hexes walked, in order (for the map)
  bool _stamping = false;
  String? loopError;

  int? get startHex => trail.isEmpty ? null : trail.first;
  int get distinctHexes => trail.toSet().length;

  /// Back in the starting hex after at least 6 different hexes.
  bool get canClose => looping && trail.length > 1 && distinctHexes >= 6 && trail.last == trail.first;

  Future<void> startLoop(LatLng at) async {
    looping = true;
    stamps.clear();
    trail.clear();
    loopError = null;
    notifyListeners();
    await _stamp(at);
  }

  void cancelLoop() {
    looping = false;
    stamps.clear();
    trail.clear();
    loopError = null;
    unawaited(_saveLoop());
    notifyListeners();
  }

  /// Call on each GPS fix while looping: stamps every new hex entered.
  void walked(LatLng p) {
    if (!looping || _stamping) return;
    if (trail.isNotEmpty && HexGrid.idAt(p) == trail.last) return;
    unawaited(_stamp(p));
  }

  Future<void> _stamp(LatLng p) async {
    _stamping = true;
    try {
      final s = await BackendApi.loopStamp(await _token(), p.latitude, p.longitude);
      final hex = HexGrid.fromUint64(BigInt.parse(s['hexId'] as String));
      if (trail.isNotEmpty && hex == trail.last) return;
      stamps.add(s);
      trail.add(hex);
      loopError = null;
      await _saveLoop();
      notifyListeners();
    } catch (e) {
      loopError = e.toString();
      notifyListeners();
    } finally {
      _stamping = false;
    }
  }

  /// Sends the walk to the backend, then claims what it encloses. Returns the
  /// hexes actually taken.
  Future<(int, String)> closeLoop() async {
    final r = await BackendApi.closeLoop(await _token(), stamps);
    final tr = [for (final h in r['trail'] as List) BigInt.parse(h as String)];
    final ins = [for (final h in r['inside'] as List) BigInt.parse(h as String)];
    final per = territory.prices?.loopPerHex ?? BigInt.from(2) * BigInt.from(10).pow(15);
    String arr(List<BigInt> l) => Abi.uint(l.length) + l.map(Abi.word).join();
    final data = Abi.call(
      _claimLoop,
      [Abi.uint(r['startedAt'] as int), Abi.word(BigInt.parse(r['deadline'] as String)), null, null, null],
      [arr(tr), arr(ins), Abi.hexBytes(r['signature'] as String)],
    );
    final (tx, logs) = await chain.sendTo(chain.territory, 'Closed a loop', data,
        value: per * BigInt.from(tr.length + ins.length), marginPct: 30);
    final ev = logs.firstWhere((l) => (l['topics'] as List).first == _topicLoopClosed);
    final d = AbiReader(ev['data'] as String);
    final taken = d.uint(d.arrayAt(2));
    cancelLoop();
    unawaited(territory.refresh());
    return (taken, tx.hash);
  }

  Future<void> _saveLoop() async {
    final prefs = await SharedPreferences.getInstance();
    if (!looping) {
      await prefs.remove('loop.v1');
      return;
    }
    await prefs.setString('loop.v1', jsonEncode({'stamps': stamps, 'trail': trail}));
  }

  /// Resumes a walk the app was closed in the middle of (stamps last 2 h).
  Future<void> restoreLoop() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('loop.v1');
    if (raw == null || looping) return;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final s = (j['stamps'] as List).cast<Map<String, dynamic>>();
    if (s.isEmpty || DateTime.now().millisecondsSinceEpoch ~/ 1000 - (s.first['t'] as int) > 2 * 3600) {
      await prefs.remove('loop.v1');
      return;
    }
    looping = true;
    stamps.addAll(s);
    trail.addAll((j['trail'] as List).cast<int>());
    notifyListeners();
  }

  // ------------------------------------------------------------- convergence

  List<Convergence> convergences = [];
  final circles = <String, Circle>{};
  DateTime? _convAt;
  LatLng? _convWhere;

  /// The next one worth showing: open now, or announced, or later today.
  Convergence? get nextConvergence {
    final now = DateTime.now();
    final live = convergences.where((c) => now.isBefore(c.closesAt)).toList()
      ..sort((a, b) => a.opensAt.compareTo(b.opensAt));
    return live.isEmpty ? null : live.first;
  }

  /// Refetches the zone's schedule at most every 10 minutes or 2 km.
  Future<void> refreshConvergences(LatLng p, {bool force = false}) async {
    if (chain.convergence.isEmpty) return;
    final fresh = _convAt != null && DateTime.now().difference(_convAt!) < const Duration(minutes: 10);
    final near = _convWhere != null && const Distance().as(LengthUnit.Meter, _convWhere!, p) < 2000;
    if (!force && fresh && near) return;
    _convAt = DateTime.now();
    _convWhere = p;
    final r = await BackendApi.convergences(p.latitude, p.longitude);
    convergences = [for (final e in r['events'] as List) Convergence(e as Map<String, dynamic>)];
    notifyListeners();
  }

  Future<Circle> circle(Convergence c) async {
    final r = await Future.wait([
      chain.read(chain.convergence, Abi.call(_attendees, [Abi.bytes32(c.id)])),
      chain.read(chain.convergence, Abi.call(_bonded, [Abi.bytes32(c.id), Abi.address(_me)])),
    ]);
    final a = r[0];
    final who = a.arrayAt(0), at = a.arrayAt(1);
    final n = a.uint(who);
    final since = DateTime.now().subtract(Convergence.together).millisecondsSinceEpoch ~/ 1000;
    var recent = 0;
    var mine = false;
    for (var i = 0; i < n; i++) {
      if (a.uint(at + 1 + i) >= since) recent++;
      if (a.address(who + 1 + i).toLowerCase() == _me) mine = true;
    }
    final out = Circle(n, recent, r[1].boolean(0), mine);
    circles[c.id] = out;
    notifyListeners();
    return out;
  }

  /// Steps into the circle. Returns how many stand together now and whether
  /// that bonded the Mythic for us.
  Future<(int, bool, String)> join(Convergence c, LatLng at) async {
    final r = await BackendApi.convergencePass(await _token(), at.latitude, at.longitude, c.id);
    final p = r['pass'] as Map<String, dynamic>;
    final head = Abi.address(p['player'] as String) +
        Abi.bytes32(p['eventId'] as String) +
        Abi.uint(p['species'] as int) +
        Abi.word(BigInt.from(p['lat'] as int)) +
        Abi.word(BigInt.from(p['lng'] as int)) +
        Abi.word(BigInt.parse(p['opensAt'] as String)) +
        Abi.word(BigInt.parse(p['deadline'] as String));
    final data = Abi.call(_join, [head, null], [Abi.hexBytes(r['signature'] as String)]);
    final (tx, logs) = await chain.sendTo(chain.convergence, 'Joined a Convergence', data, marginPct: 40);
    final bonded = logs.any((l) {
      final t = l['topics'] as List;
      return t.first == _topicCircleBonded && (t[2] as String).toLowerCase().endsWith(_me.substring(2));
    });
    final now = await circle(c);
    return (now.recent, bonded, tx.hash);
  }

  // -------------------------------------------------------------- dead drops

  List<DeadDrop> nearbyDrops = [];
  List<DeadDrop> myDrops = [];

  bool get dropsEnabled => chain.drops.isNotEmpty;

  Future<DeadDrop> _load(BigInt id) async {
    final r = await chain.read(chain.drops, Abi.call(_info, [Abi.word(id)]));
    final dropper = r.address(0);
    final forWho = r.address(1);
    final kin = r.big(5);
    return DeadDrop(
      id,
      dropper,
      forWho == _zero ? null : forWho,
      HexGrid.fromUint64(r.big(2)),
      DateTime.fromMillisecondsSinceEpoch(r.uint(3) * 1000),
      r.boolean(4),
      kin == BigInt.zero ? null : '0x${kin.toRadixString(16).padLeft(64, '0')}',
      r.big(6),
      r.string(7),
      await chain.nameOf(dropper),
    );
  }

  /// Open drops in the hexes around [p] (the same area territory shows).
  Future<void> refreshDrops(LatLng p) async {
    if (!dropsEnabled || chain.address == null) return;
    final ids = HexGrid.around(p, TerritoryService.viewMetres);
    final arr = Abi.uint(ids.length) + ids.map((i) => Abi.word(HexGrid.toUint64(i))).join();
    final r = await chain.read(chain.drops, Abi.call(_openIn, [null], [arr]));
    final at = r.arrayAt(0);
    final found = [for (var i = 0; i < r.uint(at); i++) r.big(at + 1 + i)];
    nearbyDrops = await Future.wait(found.map(_load));
    notifyListeners();
  }

  Future<void> refreshMyDrops() async {
    if (!dropsEnabled || chain.address == null) return;
    final r = await chain.read(chain.drops, Abi.call(_dropsBy, [Abi.address(_me)]));
    final at = r.arrayAt(0);
    final ids = [for (var i = 0; i < r.uint(at); i++) r.big(at + 1 + i)];
    myDrops = (await Future.wait(ids.map(_load))).reversed.toList();
    notifyListeners();
  }

  /// The wallet behind an IGN, or null when nobody has it.
  Future<String?> addressOfName(String name) async {
    try {
      final key = await chain.read(chain.game, Abi.call(_nameKey, [null], [Abi.string(name.trim())]));
      final who = await chain.read(chain.game, Abi.call(_nameOwner, [Abi.bytes32(key.bytes32(0))]));
      final a = who.address(0);
      return a == _zero ? null : a;
    } catch (_) {
      return null; // not a valid name
    }
  }

  /// Leaves a drop where the player stands.
  Future<String> leaveDrop({
    required LatLng at,
    required BigInt mon,
    String? kinId,
    required String riddle,
    String? forWho,
    required Duration life,
  }) async {
    if (kinId != null) {
      final ok = await chain.read(chain.game, Abi.call(_isApprovedForAll, [Abi.address(_me), Abi.address(chain.drops)]));
      if (!ok.boolean(0)) {
        await chain.sendTo(chain.game, 'Let dead drops hold a Kin',
            Abi.call(_setApprovalForAll, [Abi.address(chain.drops), Abi.boolean(true)]));
      }
    }
    final r = await BackendApi.dropSpot(await _token(), at.latitude, at.longitude);
    final s = r['spot'] as Map<String, dynamic>;
    final spot = Abi.address(s['player'] as String) +
        Abi.word(BigInt.parse(s['hexId'] as String)) +
        Abi.bytes32(s['sealedHash'] as String) +
        Abi.word(BigInt.parse(s['deadline'] as String));
    final expires = DateTime.now().add(life).millisecondsSinceEpoch ~/ 1000;
    final data = Abi.call(
      _drop,
      [spot, null, null, null, kinId == null ? Abi.uint(0) : Abi.bytes32(kinId), Abi.address(forWho ?? _zero), Abi.uint(expires)],
      [Abi.hexBytes(r['signature'] as String), Abi.hexBytes(r['sealedSpot'] as String), Abi.string(riddle)],
    );
    final (tx, _) = await chain.sendTo(chain.drops, 'Left a dead drop', data, value: mon, marginPct: 30);
    unawaited(refreshMyDrops());
    unawaited(refreshDrops(at));
    return tx.hash;
  }

  /// Searches for [d] at [at]: cold, warm (within ~60 m) or found and taken.
  Future<(DropSearch, String?)> search(DeadDrop d, LatLng at) async {
    final r = await BackendApi.dropClaim(await _token(), at.latitude, at.longitude, d.id);
    if (r['found'] != true) return (r['warm'] == true ? DropSearch.warm : DropSearch.cold, null);
    final c = r['claim'] as Map<String, dynamic>;
    final head = Abi.address(c['player'] as String) +
        Abi.word(BigInt.parse(c['dropId'] as String)) +
        Abi.word(BigInt.parse(c['deadline'] as String));
    final data = Abi.call(_claimDrop, [head, null], [Abi.hexBytes(r['signature'] as String)]);
    final (tx, _) = await chain.sendTo(chain.drops, 'Found a dead drop', data, marginPct: 30);
    nearbyDrops.removeWhere((x) => x.id == d.id);
    notifyListeners();
    return (DropSearch.found, tx.hash);
  }

  Future<void> reclaim(DeadDrop d) async {
    await chain.sendTo(chain.drops, 'Took back a dead drop', Abi.call(_reclaim, [Abi.word(d.id)]));
    await refreshMyDrops();
  }

  void forget() {
    cancelLoop();
    convergences = [];
    circles.clear();
    nearbyDrops = [];
    myDrops = [];
    _convAt = null;
  }
}
