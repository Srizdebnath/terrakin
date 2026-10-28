import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../app_state.dart';
import '../core/avatars.dart';
import '../core/trade_rules.dart';
import '../data/collection.dart';

/// A connected trading partner over Nearby Connections.
abstract class TradePeer {
  Stream<Map<String, dynamic>> get messages;
  void send(Map<String, dynamic> message);
  Future<void> close();
}

class TradeResult {
  const TradeResult(this.gaveBefore, this.gaveAfter, this.gotBefore, this.gotAfter, this.txHash);
  final Kin gaveBefore, gotBefore;

  /// After-trade state; [gaveAfter] arrives from the partner and may be null.
  final Kin? gaveAfter, gotAfter;
  final String txHash;
}

/// One trade between two players standing together.
///
/// The phones agree over Bluetooth/Wi-Fi (`hello` with name, wallet and live
/// GPS every 2 s; `offer`; `lock`/`unlock`), then settle on Monad: the player
/// with the lower wallet address sends `proposeTrade`, the other `acceptTrade`.
/// The contract swaps both Kin atomically and rolls the stat shifts, so both
/// phones read the same result from the chain.
class TradeSession extends ChangeNotifier {
  TradeSession(this.peer) {
    _sub = peer.messages.listen(_on, onDone: () => _end('Your trading partner left.'));
    _hello = Timer.periodic(const Duration(seconds: 2), (_) => _sendHello());
    _sendHello();
  }

  final TradePeer peer;
  late final StreamSubscription<Map<String, dynamic>> _sub;
  late final Timer _hello;

  String? partnerName;
  String? partnerWallet;
  AvatarStyle partnerStyle = avatarStyles.first;
  LatLng? partnerAt;
  double partnerAccuracy = 99;

  Kin? myOffer;
  Kin? theirOffer;
  bool myLock = false;
  bool theirLock = false;

  /// Set while the on-chain swap is in flight.
  String? settling;
  TradeResult? result;
  String? endedReason;
  String? notice;
  Kin? _gaveAfter;

  static String get myName => chain.name.isEmpty ? 'Wayfinder' : chain.name;

  double? get distance {
    final p = partnerAt;
    return p == null ? null : location.distanceTo(p);
  }

  bool get inRange {
    final d = distance;
    return d != null && location.live && withinTradeRange(d, location.accuracy, partnerAccuracy);
  }

  bool get busy => result != null || endedReason != null || settling != null;
  bool get canLock => myOffer != null && theirOffer != null && partnerWallet != null && inRange && !myLock && !busy;

  /// The lower wallet address proposes, the other accepts.
  bool get _iPropose => (chain.address ?? '').toLowerCase().compareTo(partnerWallet!.toLowerCase()) < 0;

  // ---- Actions --------------------------------------------------------------

  void offer(Kin k) {
    if (myLock || busy) return;
    myOffer = k;
    myLock = false;
    theirLock = false;
    peer.send({'t': 'offer', 'kin': _wire(k)});
    notifyListeners();
  }

  void lock() {
    if (!canLock) return;
    myLock = true;
    peer.send({'t': 'lock', 'mine': myOffer!.uid, 'theirs': theirOffer!.uid});
    _maybeSettle();
    notifyListeners();
  }

  void unlock() {
    if (busy) return;
    myLock = false;
    peer.send({'t': 'unlock'});
    notifyListeners();
  }

  Future<void> leave() async {
    peer.send({'t': 'bye'});
    _end('You left the trade.');
    await peer.close();
  }

  // ---- Protocol -------------------------------------------------------------

  void _sendHello() {
    final p = location.position;
    peer.send({
      't': 'hello',
      'name': myName,
      'wallet': chain.address,
      'style': profile.style.id,
      'lat': p.latitude,
      'lng': p.longitude,
      'acc': location.live ? location.accuracy : 999,
    });
    if (myLock && !inRange && settling == null) {
      myLock = false;
      notice = 'Moved out of range, so your lock was released.';
      peer.send({'t': 'unlock'});
    }
    notifyListeners();
  }

  void _on(Map<String, dynamic> m) {
    if (result != null || endedReason != null) {
      if (m['t'] == 'done') _gotDone(m);
      return;
    }
    switch (m['t']) {
      case 'hello':
        partnerName = m['name'] as String?;
        partnerWallet = m['wallet'] as String?;
        partnerStyle = avatarById(m['style'] as String? ?? 'rio');
        partnerAt = LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
        partnerAccuracy = (m['acc'] as num).toDouble();
      case 'offer':
        if (settling != null) return;
        final k = _parse(m['kin']);
        if (k == null) return;
        theirOffer = k;
        myLock = false;
        theirLock = false;
        notice = '${partnerName ?? 'Your partner'} put up ${k.species.name}.';
      case 'lock':
        theirLock = m['mine'] == theirOffer?.uid && m['theirs'] == myOffer?.uid;
        _maybeSettle();
      case 'unlock':
        if (settling == null) theirLock = false;
      case 'proposed':
        _accept(m['id'] as String);
      case 'accepted':
        _finish(m['tx'] as String, theirAfter: _parse(m['kin']));
      case 'done':
        _gotDone(m);
      case 'abort':
        settling = null;
        myLock = false;
        theirLock = false;
        notice = 'Trade cancelled: ${m['reason']}';
      case 'bye':
        _end('${partnerName ?? 'Your partner'} left the trade.');
    }
    notifyListeners();
  }

  void _gotDone(Map<String, dynamic> m) {
    _gaveAfter = _parse(m['kin']) ?? _gaveAfter;
    final r = result;
    if (r != null) result = TradeResult(r.gaveBefore, _gaveAfter, r.gotBefore, r.gotAfter, r.txHash);
    notifyListeners();
  }

  /// Both locked and in range: the proposer goes on chain first.
  Future<void> _maybeSettle() async {
    if (!myLock || !theirLock || settling != null || partnerWallet == null || !_iPropose) return;
    if (!inRange) {
      myLock = false;
      notice = 'Step closer: you need to be within ${tradeRangeMetres.round()} m.';
      peer.send({'t': 'unlock'});
      return;
    }
    settling = 'Offering on Monad…';
    notifyListeners();
    try {
      final (id, _) = await chain.proposeTrade(myOffer!.uid, theirOffer!.uid, partnerWallet!);
      settling = 'Waiting for ${partnerName ?? 'your partner'} to accept…';
      peer.send({'t': 'proposed', 'id': id});
    } catch (e) {
      _abort('$e');
    }
    notifyListeners();
  }

  Future<void> _accept(String tradeId) async {
    if (!myLock || !theirLock || !inRange) {
      _abort('not both locked within range');
      return;
    }
    settling = 'Accepting on Monad…';
    notifyListeners();
    try {
      final tx = await chain.acceptTrade(tradeId);
      await chain.sync();
      final got = collection.byUid(theirOffer!.uid);
      peer.send({'t': 'accepted', 'tx': tx.hash, if (got != null) 'kin': _wire(got)});
      await _finish(tx.hash);
    } catch (e) {
      _abort('$e');
    }
  }

  Future<void> _finish(String tx, {Kin? theirAfter}) async {
    final mine = myOffer, theirs = theirOffer;
    if (mine == null || theirs == null) return;
    await chain.sync();
    final got = collection.byUid(theirs.uid);
    _gaveAfter ??= theirAfter;
    if (profile.buddyUid == mine.uid) await profile.setBuddy(null);
    if (got != null) peer.send({'t': 'done', 'kin': _wire(got)});
    settling = null;
    result = TradeResult(mine, _gaveAfter, theirs, got, tx);
    notifyListeners();
  }

  void _abort(String reason) {
    settling = null;
    myLock = false;
    theirLock = false;
    notice = 'Trade didn\'t go through: $reason';
    peer.send({'t': 'abort', 'reason': reason});
    notifyListeners();
  }

  void _end(String reason) {
    if (result != null || endedReason != null) return;
    endedReason = reason;
    notifyListeners();
  }

  /// What goes over the air: everything except the local photo path.
  static Map<String, dynamic> _wire(Kin k) => k.toJson()..remove('imprintPath');

  static Kin? _parse(Object? raw) {
    if (raw == null) return null;
    try {
      final k = Kin.fromJson(Map<String, dynamic>.from(raw as Map));
      if (k.genes.vigor.toList().any((x) => x < 0 || x > 15)) return null;
      if (k.tradeMods.length != 4 || k.tradeMods.any((m) => m < modFloor - 1e-6 || m > modCeil + 1e-6)) return null;
      return k;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _hello.cancel();
    _sub.cancel();
    super.dispose();
  }
}
