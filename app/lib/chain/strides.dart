import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'abi.dart';
import 'backend_api.dart';
import 'game_chain.dart';

/// Walk rewards (TerrakinStrides): MON for every 500 m walked with the app
/// open. The backend stamps the player's spot every ~100 m; once the stamps
/// add up to 500 m the walk is claimed on chain. Mirrors backend/lib/walk.ts
/// so the progress shown matches what the backend will count.
class StrideRewards extends ChangeNotifier {
  StrideRewards(this.chain);
  final GameChain chain;

  static const stepM = 500.0; // TerrakinStrides.STEP
  static const _stampEveryM = 100.0;
  static const _maxMps = 4.5; // backend: faster stretches don't count
  static const _maxGapM = 400.0;
  static const _keep = Duration(hours: 2, minutes: 45); // backend allows 3 h per claim

  static const _claim = '0xc968dd02';
  static const _rules = '0x52f6747a';
  static const _stepsToday = '0x5d40edaf';
  static const _topicStrode = '0xb319284951491dec3ecee9b177d1c5961793b8a2ecdd6c173b6def5e37cf7ba6';

  final _stamps = <Map<String, dynamic>>[];
  bool _busy = false;
  bool _restored = false;
  BigInt perStep = BigInt.zero;
  int stepsPerDay = 0, stepsToday = 0;
  String? error;

  /// Last reward paid, for the world screen to celebrate once.
  (BigInt, int)? lastReward;

  bool get enabled => chain.configured && chain.strides.isNotEmpty && chain.address != null;
  bool get cappedToday => stepsPerDay > 0 && stepsToday >= stepsPerDay;

  /// Metres the backend will count from the stamps held so far.
  double get stampedMetres {
    var total = 0.0;
    for (var i = 1; i < _stamps.length; i++) {
      final a = _stamps[i - 1], b = _stamps[i];
      final d = _metres(a, b);
      final dt = (b['t'] as int) - (a['t'] as int);
      if (dt > 0 && d <= _maxGapM && d / dt <= _maxMps) total += d;
    }
    return total;
  }

  /// Progress towards the next reward, 0..500.
  double get progressM => stampedMetres % stepM;

  /// Call on each trusted GPS fix while walking (not driving).
  void walked(LatLng p) {
    if (!enabled || _busy || cappedToday) return;
    if (!_restored) {
      unawaited(_restore());
      return;
    }
    final last = _stamps.isEmpty ? null : _stamps.last;
    if (last != null && const Distance().as(LengthUnit.Meter, _at(last), p) < _stampEveryM) return;
    unawaited(_stamp(p));
  }

  Future<void> _stamp(LatLng p) async {
    _busy = true;
    try {
      final s = await BackendApi.walkStamp(await chain.auth.accessToken(), p.latitude, p.longitude);
      _stamps.add(s);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      _stamps.removeWhere((x) => now - (x['t'] as int) > _keep.inSeconds && x != _stamps.last);
      error = null;
      await _save();
      notifyListeners();
      if (stampedMetres >= stepM) await _claimNow();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    } finally {
      _busy = false;
    }
  }

  Future<void> _claimNow() async {
    final Map<String, dynamic> r;
    try {
      r = await BackendApi.claimWalk(await chain.auth.accessToken(), _stamps);
    } on BackendException catch (e) {
      // The backend won't take these stamps (stale, forged by a key change…).
      if (e.status == 422) _stamps.removeRange(0, _stamps.length - 1);
      await _save();
      rethrow;
    }
    final w = r['walk'] as Map<String, dynamic>;
    final data = Abi.call(
      _claim,
      [
        Abi.address(w['player'] as String),
        Abi.uint(w['from'] as int),
        Abi.uint(w['to'] as int),
        Abi.uint(w['metres'] as int),
        Abi.word(BigInt.parse(w['deadline'] as String)),
        null,
      ],
      [Abi.hexBytes(r['signature'] as String)],
    );
    try {
      final (_, logs) = await chain.sendTo(chain.strides, 'Walked ${w['metres']} m', data, marginPct: 30);
      final ev = logs.firstWhere((l) => (l['topics'] as List).first == _topicStrode);
      final d = AbiReader(ev['data'] as String);
      lastReward = (d.big(2), d.uint(0));
      stepsToday += d.uint(1);
      _stamps.removeRange(0, r['keepFrom'] as int);
    } on ChainException catch (e) {
      // Already paid or capped: these stamps will never pay, start afresh.
      if (e.message.contains('already paid') || e.message.contains('today')) {
        _stamps.removeRange(0, _stamps.length - 1);
        if (e.message.contains('today')) stepsToday = stepsPerDay;
      }
      rethrow;
    } finally {
      await _save();
      notifyListeners();
    }
  }

  /// Reward rules and today's count, from the contract.
  Future<void> refresh() async {
    if (!enabled) return;
    final rules = AbiReader(await chain.rpc.ethCall(chain.strides, _rules));
    perStep = rules.big(0);
    stepsPerDay = rules.uint(1);
    final today = AbiReader(await chain.rpc.ethCall(chain.strides, '$_stepsToday${Abi.address(chain.address!)}'));
    stepsToday = today.uint(0);
    notifyListeners();
  }

  Future<void> _restore() async {
    _restored = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) _stamps.addAll((jsonDecode(raw) as List).cast<Map<String, dynamic>>());
    unawaited(refresh().catchError((Object _) {}));
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_stamps));
  }

  String get _key => 'walk.v1.${chain.address?.toLowerCase()}';

  void forget() {
    _stamps.clear();
    _restored = false;
    stepsToday = stepsPerDay = 0;
    perStep = BigInt.zero;
    lastReward = null;
    error = null;
  }

  static LatLng _at(Map<String, dynamic> s) => LatLng((s['lat'] as int) / 1e5, (s['lng'] as int) / 1e5);
  static double _metres(Map<String, dynamic> a, Map<String, dynamic> b) =>
      const Distance().as(LengthUnit.Meter, _at(a), _at(b));
}
