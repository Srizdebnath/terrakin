import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:privy_flutter/privy_flutter.dart';

/// Passkey sign-in and the player's embedded wallet, via Privy.
///
/// Passkeys belong to [relyingParty]; the Android app is linked to it by
/// https://terrakin.vercel.app/.well-known/assetlinks.json. No seed phrase
/// exists: the key is held by Privy's wallet infrastructure and unlocked by
/// the passkey.
class AuthService extends ChangeNotifier {
  static const appId = 'cmvqz17pj00020iia8i4dectn';
  static const clientId = 'client-WY6etDEPUrW86E7cY9YUueM91yxH51Kcwq2m13Bm4VjSQ';
  static const relyingParty = 'https://terrakin.vercel.app';

  late final Privy _privy;
  bool ready = false;
  PrivyUser? user;
  EmbeddedEthereumWallet? wallet;

  bool get signedIn => user != null && wallet != null;
  String? get address => wallet?.address;

  Future<void> init() async {
    _privy = Privy.init(config: PrivyConfig(appId: appId, appClientId: clientId));
    var state = await _privy.getAuthState();
    if (state is AuthenticatedUnverified) {
      await _privy.onNetworkRestored();
      state = await _privy.getAuthState();
    }
    if (state is Authenticated) {
      user = state.user;
      await _ensureWallet();
    }
    ready = true;
    notifyListeners();
  }

  /// New player: creates a passkey on this phone and a wallet behind it.
  Future<void> signUp() => _finish(_privy.passkey.signup(relyingParty: relyingParty, displayName: 'Terrakin'));

  /// Returning player: picks an existing passkey.
  Future<void> logIn() => _finish(_privy.passkey.login(relyingParty: relyingParty));

  Future<void> _finish(Future<Result<PrivyUser>> attempt) async {
    final r = await attempt;
    switch (r) {
      case Success(:final value):
        user = value;
        await _ensureWallet();
        notifyListeners();
      case Failure(:final error):
        throw AuthException(error.message);
    }
  }

  Future<void> _ensureWallet() async {
    final u = user!;
    if (u.embeddedEthereumWallets.isNotEmpty) {
      wallet = u.embeddedEthereumWallets.first;
      return;
    }
    final r = await u.createEthereumWallet();
    switch (r) {
      case Success(:final value):
        wallet = value;
      case Failure(:final error):
        throw AuthException('Could not create your wallet: ${error.message}');
    }
  }

  Future<String> accessToken() async {
    final r = await user!.getAccessToken();
    return switch (r) {
      Success(:final value) => value,
      Failure(:final error) => throw AuthException(error.message),
    };
  }

  /// Signs (does not send) a transaction with the embedded wallet.
  Future<String> signTransaction(Map<String, Object> tx) async {
    final r = await wallet!.provider.request(EthereumRpcRequest.ethSignTransaction(jsonEncode(tx)));
    return switch (r) {
      Success(:final value) => value.data,
      Failure(:final error) => throw AuthException('Signing failed: ${error.message}'),
    };
  }

  Future<void> logOut() async {
    await _privy.logout();
    user = null;
    wallet = null;
    notifyListeners();
  }
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}
