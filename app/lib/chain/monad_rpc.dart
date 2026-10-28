import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'abi.dart';

class RpcException implements Exception {
  RpcException(this.message, [this.data]);
  final String message;

  /// Revert data (selector + args) when a call or gas estimate reverted.
  final String? data;

  @override
  String toString() => message;
}

/// A sent transaction and how long Monad took to confirm it.
class TxResult {
  const TxResult(this.hash, this.logs, this.confirmIn, this.gasUsed, this.feeWei);
  final String hash;
  final List<Map<String, dynamic>> logs;
  final Duration confirmIn;
  final int gasUsed;
  final BigInt feeWei;
}

/// Signs a transaction JSON (Privy `eth_signTransaction`) and returns raw hex.
typedef TxSigner = Future<String> Function(Map<String, Object> tx);

/// JSON-RPC client for Monad testnet. Transactions are signed by the player's
/// embedded wallet and broadcast here, so the app controls nonce, gas and the
/// fast-confirmation loop.
class MonadRpc {
  MonadRpc(this.url, {this.chainId = 10143});
  final String url;
  final int chainId;
  var _id = 0;

  Future<dynamic> call(String method, List<Object?> params) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(Uri.parse(url));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'jsonrpc': '2.0', 'id': ++_id, 'method': method, 'params': params}));
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final err = body['error'];
      if (err is Map) {
        final data = err['data'];
        throw RpcException(err['message']?.toString() ?? 'RPC error', data is String ? data : null);
      }
      return body['result'];
    } finally {
      client.close();
    }
  }

  static BigInt _big(Object? hex) => BigInt.parse(Abi.strip(hex as String), radix: 16);
  static String hex(BigInt v) => '0x${v.toRadixString(16)}';

  Future<BigInt> balance(String address) async => _big(await call('eth_getBalance', [address, 'latest']));

  Future<String> ethCall(String to, String data) async =>
      await call('eth_call', [
        {'to': to, 'data': data},
        'latest',
      ]) as String;

  /// Builds, signs and sends a transaction, then waits for its receipt.
  ///
  /// Monad bills the whole gas *limit*, so the limit is the estimate plus a
  /// thin [marginPct] (default 2%) + 2,000 gas margin (state rarely shifts
  /// between estimate and inclusion for our calls; battles, whose path
  /// depends on the block's randomness, pass more); the estimate also
  /// surfaces reverts before anything is signed or paid for.
  Future<TxResult> send({
    required String from,
    required String to,
    required String data,
    BigInt? value,
    required TxSigner sign,
    int marginPct = 2,
  }) async {
    final v = value ?? BigInt.zero;
    final txCall = {'from': from, 'to': to, 'data': data, 'value': hex(v)};
    final results = await Future.wait([
      call('eth_estimateGas', [txCall]),
      call('eth_getTransactionCount', [from, 'pending']),
      call('eth_getBlockByNumber', ['latest', false]),
      call('eth_maxPriorityFeePerGas', []),
    ]);
    final estimate = _big(results[0]);
    final gas = estimate + estimate * BigInt.from(marginPct) ~/ BigInt.from(100) + BigInt.from(2000);
    final nonce = _big(results[1]);
    final base = _big((results[2] as Map)['baseFeePerGas']);
    final tip = _big(results[3]);
    // Keep the max fee close to what is charged: the wallet must hold
    // limit x maxFee up front, and starter wallets are small.
    final maxFee = base * BigInt.from(5) ~/ BigInt.from(4) + tip;

    final raw = await sign({
      'from': from,
      'to': to,
      'data': data,
      'value': hex(v),
      'chainId': hex(BigInt.from(chainId)),
      'nonce': hex(nonce),
      'gasLimit': hex(gas),
      'maxFeePerGas': hex(maxFee),
      'maxPriorityFeePerGas': hex(tip),
      'type': 2, // Privy's Android parser wants a number here, unlike the hex fields
    });

    final started = DateTime.now();
    final hash = await call('eth_sendRawTransaction', [raw]) as String;
    for (var i = 0; i < 150; i++) {
      final r = await call('eth_getTransactionReceipt', [hash]);
      if (r is Map<String, dynamic>) {
        final took = DateTime.now().difference(started);
        if (r['status'] != '0x1') throw RpcException('Transaction reverted');
        final used = _big(r['gasUsed']).toInt();
        final price = _big(r['effectiveGasPrice'] ?? hex(base + tip));
        return TxResult(hash, (r['logs'] as List).cast<Map<String, dynamic>>(), took, used, gas * price);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw RpcException('Timed out waiting for confirmation ($hash)');
  }
}
