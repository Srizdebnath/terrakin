import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app_state.dart';
import '../core/avatars.dart';
import '../core/economy.dart';
import '../core/theme.dart';
import '../data/location.dart';
import 'mint_screen.dart';
import 'world_screen.dart';

/// Decides what the player sees: sign in → starter grant → name + first
/// character → GPS on → the world.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

enum _Step { booting, signIn, funding, setup, gps, play, error }

class _RootGateState extends State<RootGate> {
  _Step _step = _Step.booting;
  String? _error;

  @override
  void initState() {
    super.initState();
    location.addListener(_onLocation);
    _boot();
  }

  @override
  void dispose() {
    location.removeListener(_onLocation);
    super.dispose();
  }

  void _onLocation() {
    if (_step == _Step.gps && location.live) setState(() => _step = _Step.play);
  }

  Future<void> _boot() async {
    setState(() {
      _step = _Step.booting;
      _error = null;
    });
    try {
      await Future.wait([auth.init(), chain.configure()]);
      await _advance();
    } catch (e) {
      setState(() {
        _error = 'Could not reach Terrakin: $e';
        _step = _Step.error;
      });
    }
  }

  /// Moves to the next unmet requirement.
  Future<void> _advance() async {
    if (!auth.signedIn) return setState(() => _step = _Step.signIn);
    await chain.sync();
    if (!chain.funded) {
      setState(() => _step = _Step.funding);
      await chain.fundIfNeeded();
    }
    if (!chain.hasProfile) return setState(() => _step = _Step.setup);
    chain.startPolling();
    location.start();
    setState(() => _step = location.live ? _Step.play : _Step.gps);
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _error = null);
    try {
      await f();
      await _advance();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => switch (_step) {
        _Step.booting => const _Splash('Waking up the world…'),
        _Step.funding => const _Splash('Funding your wallet with testnet MON and Seed Orbs…'),
        _Step.signIn => _SignIn(
            error: _error,
            onSignUp: () => _run(auth.signUp),
            onLogIn: () => _run(auth.logIn),
          ),
        _Step.setup => _Setup(onDone: () => _run(() async {})),
        _Step.gps => _GpsGate(onRetry: () => location.start()),
        _Step.play => const WorldScreen(),
        _Step.error => _Splash(_error ?? 'Something went wrong', retry: _boot),
      };
}

class _Splash extends StatelessWidget {
  const _Splash(this.text, {this.retry});
  final String text;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('assets/images/brand/logo-mark.png', width: 110),
              const SizedBox(height: 16),
              if (retry == null) const CircularProgressIndicator(color: TK.signal),
              const SizedBox(height: 16),
              Text(text, textAlign: TextAlign.center, style: TK.body(15, color: TK.mist)),
              if (retry != null) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: retry, child: const Text('Try again')),
              ],
            ]),
          ),
        ),
      );
}

class _SignIn extends StatefulWidget {
  const _SignIn({required this.onSignUp, required this.onLogIn, this.error});
  final Future<void> Function() onSignUp, onLogIn;
  final String? error;

  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  bool _busy = false;

  Future<void> _go(Future<void> Function() f) async {
    setState(() => _busy = true);
    await f();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Spacer(),
              Image.asset('assets/images/brand/logo-mark.png', width: 180),
              const SizedBox(height: 8),
              Text('TERRAKIN', style: TK.display(44, color: TK.signal)),
              Text('own the map', style: TK.display(18, color: TK.paper.withValues(alpha: 0.85))),
              const SizedBox(height: 10),
              Text('Bond with Kin at real places. Own the land they live on, on Monad.',
                  textAlign: TextAlign.center, style: TK.body(15, color: TK.mist)),
              const Spacer(),
              if (widget.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(widget.error!, textAlign: TextAlign.center, style: TK.body(13, color: TK.danger)),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _go(widget.onSignUp),
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('Create account with a passkey'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
                  onPressed: _busy ? null : () => _go(widget.onLogIn),
                  child: Text('I already have a passkey', style: TK.display(16)),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Your passkey (fingerprint or screen lock) unlocks a wallet made for you. '
                'No passwords, no seed phrase to lose.',
                textAlign: TextAlign.center,
                style: TK.body(12, color: TK.mist),
              ),
            ]),
          ),
        ),
      );
}

/// Pick a unique in-game name and the first character, minted together in one
/// transaction.
class _Setup extends StatefulWidget {
  const _Setup({required this.onDone});
  final Future<void> Function() onDone;

  @override
  State<_Setup> createState() => _SetupState();
}

class _SetupState extends State<_Setup> {
  static final _valid = RegExp(r'^[A-Za-z0-9_]{4,8}$');
  final _name = TextEditingController();
  int _style = 0;
  bool? _free;
  bool _checking = false, _minting = false;
  String? _error;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    super.dispose();
  }

  void _onName(String v) {
    _debounce?.cancel();
    setState(() {
      _free = null;
      _error = null;
    });
    if (!_valid.hasMatch(v)) return;
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _checking = true);
      try {
        final free = await chain.isNameFree(v);
        if (mounted && _name.text == v) setState(() => _free = free);
      } catch (_) {
      } finally {
        if (mounted) setState(() => _checking = false);
      }
    });
  }

  Future<void> _create() async {
    setState(() {
      _minting = true;
      _error = null;
    });
    try {
      await chain.createProfile(_name.text, _style);
      await chain.sync();
      await widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _minting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = chain.prices?.firstCharacter;
    final name = _name.text;
    final hint = name.isEmpty
        ? '4–8 letters, numbers or _'
        : !_valid.hasMatch(name)
            ? '4–8 letters, numbers or _ only'
            : _checking || _free == null
                ? 'Checking…'
                : _free!
                    ? 'Available'
                    : 'Taken. Try another.';
    final ok = _valid.hasMatch(name) && _free == true;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Choose your Wayfinder', style: TK.display(26)),
              const SizedBox(height: 4),
              Text('Wallet funded: ${fmtMon(chain.balance)} and ${chain.orbs[0]} Seed Orbs.',
                  style: TK.body(13, color: TK.mist)),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                onChanged: _onName,
                maxLength: 8,
                style: TK.display(20),
                decoration: InputDecoration(
                  labelText: 'In-game name',
                  helperText: hint,
                  helperStyle: TK.body(12, color: ok ? const Color(0xFF5FBF6A) : TK.mist),
                  border: const OutlineInputBorder(),
                ),
              ),
            ]),
          ),
          Expanded(child: CharacterCarousel(onChanged: (i) => setState(() => _style = i))),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_error!, textAlign: TextAlign.center, style: TK.body(13, color: TK.danger)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: ok && !_minting && price != null ? _create : null,
                child: _minting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: TK.ink))
                    : Text(price == null
                        ? 'Loading…'
                        : 'Mint ${avatarStyles[_style].name} as ${name.isEmpty ? '…' : name} · ${fmtMon(price)}'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Terrakin is played on foot: no GPS, no game.
class _GpsGate extends StatelessWidget {
  const _GpsGate({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ListenableBuilder(
              listenable: location,
              builder: (context, _) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.location_searching_rounded, size: 72, color: TK.signal),
                const SizedBox(height: 16),
                Text(location.state == LocationState.starting ? 'Finding you…' : 'Turn on GPS to play',
                    style: TK.display(26)),
                const SizedBox(height: 8),
                Text(
                  'Kin live at real coordinates. Terrakin needs precise location while you play.',
                  textAlign: TextAlign.center,
                  style: TK.body(14, color: TK.mist),
                ),
                const SizedBox(height: 20),
                if (location.state == LocationState.off)
                  FilledButton(onPressed: Geolocator.openLocationSettings, child: const Text('Open location settings'))
                else if (location.state == LocationState.denied)
                  FilledButton(onPressed: Geolocator.openAppSettings, child: const Text('Allow location for Terrakin'))
                else
                  const CircularProgressIndicator(color: TK.signal),
                const SizedBox(height: 10),
                TextButton(onPressed: onRetry, child: const Text('Check again')),
              ]),
            ),
          ),
        ),
      );
}
