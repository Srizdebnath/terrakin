import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import 'trade_session.dart';

/// Finds other Terrakin players close by over Bluetooth / Wi-Fi (Google Nearby
/// Connections) and opens a one-to-one link. No server or internet involved;
/// the 8 m rule is enforced on top with GPS in [TradeSession].
class NearbyLink extends ChangeNotifier {
  static const _service = 'xyz.terrakin.trade';
  static const _strategy = Strategy.P2P_POINT_TO_POINT;

  final _nearby = Nearby();
  final found = <String, String>{}; // endpointId -> player name
  final _requested = <String>{};
  final _names = <String, String>{};

  bool running = false;
  String? error;
  bool permanentlyDenied = false;

  /// Someone asked to trade with us: (endpointId, name).
  (String, String)? incoming;
  NearbyPeer? peer;
  String _me = '';

  Future<void> start(String myName) async {
    _me = myName;
    error = null;
    final ok = await _permissions();
    if (!ok) {
      notifyListeners();
      return;
    }
    try {
      await _nearby.startAdvertising(
        _me,
        _strategy,
        serviceId: _service,
        onConnectionInitiated: _initiated,
        onConnectionResult: _result,
        onDisconnected: _disconnected,
      );
      await _nearby.startDiscovery(
        _me,
        _strategy,
        serviceId: _service,
        onEndpointFound: (id, name, _) {
          found[id] = name;
          notifyListeners();
        },
        onEndpointLost: (id) {
          found.remove(id);
          notifyListeners();
        },
      );
      running = true;
    } catch (e) {
      error = 'Could not start searching: $e';
    }
    notifyListeners();
  }

  Future<bool> _permissions() async {
    final statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();
    final denied = statuses.entries.where((e) => !e.value.isGranted && !e.value.isLimited).toList();
    if (denied.isEmpty) {
      if (!await Permission.location.serviceStatus.isEnabled) {
        error = 'Turn on location to find nearby players.';
        return false;
      }
      return true;
    }
    permanentlyDenied = denied.any((e) => e.value.isPermanentlyDenied);
    error = 'Trading needs Nearby devices and Location permission.';
    return false;
  }

  Future<void> connect(String endpointId) async {
    _requested.add(endpointId);
    _names[endpointId] = found[endpointId] ?? 'Player';
    try {
      await _nearby.requestConnection(
        _me,
        endpointId,
        onConnectionInitiated: _initiated,
        onConnectionResult: _result,
        onDisconnected: _disconnected,
      );
    } catch (e) {
      _requested.remove(endpointId);
      error = 'Could not reach ${found[endpointId]}.';
      notifyListeners();
    }
  }

  void _initiated(String id, ConnectionInfo info) {
    _names[id] = info.endpointName;
    if (_requested.contains(id)) {
      _accept(id);
    } else {
      incoming = (id, info.endpointName);
      notifyListeners();
    }
  }

  void acceptIncoming() {
    final i = incoming;
    if (i == null) return;
    incoming = null;
    _accept(i.$1);
    notifyListeners();
  }

  Future<void> declineIncoming() async {
    final i = incoming;
    incoming = null;
    notifyListeners();
    if (i != null) await _nearby.rejectConnection(i.$1);
  }

  void _accept(String id) {
    _nearby.acceptConnection(
      id,
      onPayLoadRecieved: (endpointId, payload) {
        final bytes = payload.bytes;
        if (payload.type == PayloadType.BYTES && bytes != null && endpointId == peer?.endpointId) {
          peer!._deliver(bytes);
        }
      },
    );
  }

  void _result(String id, Status status) {
    _requested.remove(id);
    if (status == Status.CONNECTED) {
      peer = NearbyPeer(this, id, _names[id] ?? 'Player');
      _nearby.stopDiscovery();
      _nearby.stopAdvertising();
    } else {
      error = status == Status.REJECTED ? '${_names[id] ?? 'They'} declined.' : 'Connection failed. Try again.';
    }
    notifyListeners();
  }

  void _disconnected(String id) {
    if (peer?.endpointId == id) {
      peer!._closed();
      peer = null;
    }
    notifyListeners();
  }

  Future<void> stop() async {
    running = false;
    await _nearby.stopAdvertising();
    await _nearby.stopDiscovery();
    await _nearby.stopAllEndpoints();
    found.clear();
    peer = null;
  }

  Future<void> _send(String id, Map<String, dynamic> m) =>
      _nearby.sendBytesPayload(id, Uint8List.fromList(utf8.encode(jsonEncode(m))));
}

class NearbyPeer implements TradePeer {
  NearbyPeer(this._link, this.endpointId, this.name);
  final NearbyLink _link;
  final String endpointId;
  final String name;
  // Single-subscription so messages that arrive before the session listens are buffered.
  final _ctrl = StreamController<Map<String, dynamic>>();

  @override
  Stream<Map<String, dynamic>> get messages => _ctrl.stream;

  @override
  void send(Map<String, dynamic> message) {
    _link._send(endpointId, message).catchError((Object e) => debugPrint('trade send failed: $e'));
  }

  void _deliver(Uint8List bytes) {
    try {
      final m = jsonDecode(utf8.decode(bytes));
      if (m is Map<String, dynamic> && !_ctrl.isClosed) _ctrl.add(m);
    } catch (e) {
      debugPrint('bad trade message: $e');
    }
  }

  void _closed() {
    if (!_ctrl.isClosed) _ctrl.close();
  }

  @override
  Future<void> close() async {
    await _link._nearby.disconnectFromEndpoint(endpointId);
    _closed();
  }
}
