import 'package:flutter/material.dart';

import 'abi.dart';
import 'backend_api.dart';
import 'game_chain.dart';

class SeasonInfo {
  const SeasonInfo(this.season, this.minted, this.cap, this.startedAt, this.endsAt);
  final int season, cap;
  final List<int> minted; // Mythics bonded this season, by species index
  final DateTime startedAt, endsAt;
  Duration get left => endsAt.difference(DateTime.now());
}

class PlayerRow {
  const PlayerRow(this.address, this.name, this.hexes, this.kin, this.mythics, this.wins, this.crew);
  final String address, name;
  final int hexes, kin, mythics, wins, crew;
}

class CrewRow {
  const CrewRow(this.id, this.name, this.tag, this.treasury, this.size);
  final int id, size;
  final String name, tag;
  final BigInt treasury;
}

class CrewDetail {
  const CrewDetail(this.id, this.name, this.tag, this.captain, this.treasury, this.members);
  final int id;
  final String name, tag, captain;
  final BigInt treasury;
  final List<String> members;
}

/// Seasons, leaderboards and crews (TerrakinSeason.sol, TerrakinCrews.sol).
class SocialService extends ChangeNotifier {
  SocialService(this.chain);
  final GameChain chain;

  static const _mythicCounts = '0x78917ea6';
  static const _leaderboard = '0xaee6c69c';
  static const _crewOf = '0x6b770833';
  static const _crew = '0x4e22423d';
  static const _crewsOf = '0x88e3ca86';
  static const _crews = '0x5b0c71b4';
  static const _crewCount = '0x7628eaa4';
  static const _createFee = '0xb2db919b';
  static const _create = '0x198e2b8a';
  static const _join = '0x049878f3';
  static const _leave = '0xd66d9e19';
  static const _kick = '0x96c55175';
  static const _deposit = '0xd0e30db0';
  static const _payout = '0x63bd1d4a';

  SeasonInfo? season;
  List<PlayerRow> players = [];
  List<CrewRow> crews = [];
  CrewDetail? myCrew;
  BigInt? createFee;
  bool _enrolled = false;

  /// Crew id by lower-case address, for colouring the map.
  final crewOfOwner = <String, int>{};
  final _crewTags = <int, String>{};

  bool get enabled => chain.season.isNotEmpty && chain.crews.isNotEmpty;
  String? get _me => chain.address?.toLowerCase();

  String? tagOf(int crewId) => _crewTags[crewId];

  /// Stable colour per crew, so a crew's turf reads as one block on the map.
  static Color crewColour(int id) =>
      HSLColor.fromAHSL(1, (id * 137.508) % 360, 0.75, 0.6).toColor(); // golden-angle hues

  /// Joins the season leaderboards once per install (the backend pays).
  Future<void> enrollOnce() async {
    if (_enrolled || !enabled) return;
    await BackendApi.enroll(await chain.auth.accessToken());
    _enrolled = true;
    await refreshLeaderboard();
  }

  Future<void> refreshSeason() async {
    if (!enabled) return;
    final r = await chain.read(chain.season, _mythicCounts);
    season = SeasonInfo(
      r.uint(0),
      [for (var i = 0; i < 7; i++) r.uint(1 + i)],
      r.uint(8),
      DateTime.fromMillisecondsSinceEpoch(r.uint(9) * 1000),
      DateTime.fromMillisecondsSinceEpoch(r.uint(10) * 1000),
    );
    notifyListeners();
  }

  /// Every enrolled player's stats, 100 per call.
  Future<void> refreshLeaderboard() async {
    if (!enabled) return;
    final out = <PlayerRow>[];
    for (var offset = 0;; offset += 100) {
      final r = await chain.read(chain.season, Abi.call(_leaderboard, [Abi.uint(offset), Abi.uint(100)]));
      final who = r.arrayAt(0), names = r.arrayAt(1), hexes = r.arrayAt(2), kin = r.arrayAt(3);
      final mythics = r.arrayAt(4), wins = r.arrayAt(5), crew = r.arrayAt(6);
      final n = r.uint(who);
      for (var i = 0; i < n; i++) {
        out.add(PlayerRow(
          r.address(who + 1 + i).toLowerCase(),
          r.string(names + 1 + i, base: names + 1),
          r.uint(hexes + 1 + i),
          r.uint(kin + 1 + i),
          r.uint(mythics + 1 + i),
          r.uint(wins + 1 + i),
          r.uint(crew + 1 + i),
        ));
      }
      if (n < 100) break;
    }
    players = out;
    for (final p in out) {
      crewOfOwner[p.address] = p.crew;
    }
    notifyListeners();
  }

  Future<void> refreshCrews() async {
    if (!enabled) return;
    final count = (await chain.read(chain.crews, _crewCount)).uint(0);
    final out = <CrewRow>[];
    for (var offset = 0; offset < count; offset += 100) {
      final r = await chain.read(chain.crews, Abi.call(_crews, [Abi.uint(offset), Abi.uint(100)]));
      final names = r.arrayAt(0), tags = r.arrayAt(1), tr = r.arrayAt(2), sizes = r.arrayAt(3);
      for (var i = 0; i < r.uint(names); i++) {
        final id = offset + i + 1;
        final tag = r.string(tags + 1 + i, base: tags + 1);
        _crewTags[id] = tag;
        out.add(CrewRow(id, r.string(names + 1 + i, base: names + 1), tag, r.big(tr + 1 + i), r.uint(sizes + 1 + i)));
      }
    }
    crews = out;
    createFee ??= (await chain.read(chain.crews, _createFee)).big(0);
    await refreshMyCrew();
  }

  Future<void> refreshMyCrew() async {
    final me = chain.address;
    if (!enabled || me == null) return;
    final id = (await chain.read(chain.crews, '$_crewOf${Abi.address(me)}')).uint(0);
    myCrew = id == 0 ? null : await crewDetail(id);
    if (id != 0) crewOfOwner[me.toLowerCase()] = id;
    notifyListeners();
  }

  Future<CrewDetail> crewDetail(int id) async {
    final r = await chain.read(chain.crews, Abi.call(_crew, [Abi.uint(id)]));
    final t = r.uint(0) ~/ 32; // tuple start
    final m = r.arrayAt(1);
    return CrewDetail(
      id,
      r.string(t, base: t),
      r.string(t + 1, base: t),
      r.address(t + 2).toLowerCase(),
      r.big(t + 3),
      [for (var i = 0; i < r.uint(m); i++) r.address(m + 1 + i).toLowerCase()],
    );
  }

  /// Looks up the crews of hex owners on the map.
  Future<void> lookupCrews(Iterable<String> owners) async {
    final todo = owners.where((o) => !crewOfOwner.containsKey(o)).toSet().toList();
    if (!enabled || todo.isEmpty) return;
    final r = await chain.read(
        chain.crews, Abi.call(_crewsOf, [null], [Abi.uint(todo.length) + todo.map(Abi.address).join()]));
    final a = r.arrayAt(0);
    for (var i = 0; i < todo.length; i++) {
      crewOfOwner[todo[i]] = r.uint(a + 1 + i);
    }
    if (crews.isEmpty && crewOfOwner.values.any((c) => c != 0)) await refreshCrews();
    notifyListeners();
  }

  bool isAlly(String owner) {
    final mine = myCrew?.id;
    return mine != null && crewOfOwner[owner] == mine;
  }

  // ---- Actions --------------------------------------------------------------

  Future<void> _then(Future<Object?> tx) async {
    await tx;
    await refreshCrews();
  }

  Future<void> create(String name, String tag) => _then(chain.sendTo(chain.crews, 'Founded crew [$tag]',
      Abi.call(_create, [null, null], [Abi.string(name), Abi.string(tag)]),
      value: createFee));

  Future<void> join(int id) => _then(chain.sendTo(chain.crews, 'Joined a crew', Abi.call(_join, [Abi.uint(id)])));

  Future<void> leave() {
    crewOfOwner.remove(_me);
    return _then(chain.sendTo(chain.crews, 'Left the crew', _leave));
  }

  Future<void> kick(String member) {
    crewOfOwner.remove(member);
    return _then(chain.sendTo(chain.crews, 'Removed a crew member', Abi.call(_kick, [Abi.address(member)])));
  }

  Future<void> deposit(BigInt amount) =>
      _then(chain.sendTo(chain.crews, 'Paid into the crew treasury', _deposit, value: amount));

  Future<void> payout() => _then(chain.sendTo(chain.crews, 'Split the crew treasury', _payout, marginPct: 20));
}
