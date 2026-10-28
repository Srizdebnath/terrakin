import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../app_state.dart';
import '../chain/backend_api.dart';
import '../chain/game_chain.dart';
import '../core/copy.dart';
import '../core/sound.dart';
import '../widgets/meme_card.dart';
import '../core/economy.dart';
import '../core/species.dart';
import '../core/theme.dart';
import '../data/collection.dart';
import '../data/spawn_engine.dart';
import '../game/tether_game.dart';
import '../widgets/kin_widgets.dart';
import '../widgets/orb_painter.dart';
import 'market_screen.dart';

enum _Stage { camera, tether, sealing, bonded, fled }

/// Bonding flow (SRS 3.3): photograph the place, play the Tether, see the card.
class BondScreen extends StatefulWidget {
  const BondScreen({super.key, required this.spawn});
  final Spawn spawn;

  @override
  State<BondScreen> createState() => _BondScreenState();
}

class _BondScreenState extends State<BondScreen> {
  _Stage stage = _Stage.camera;
  CameraController? _camera;
  String? _cameraError;
  String? _photoPath;
  Kin? _kin;
  TetherGame? _game;
  Orb _orb = Orb.seed;
  int _throws = 0;
  BigInt _reward = BigInt.zero;
  TxRecord? _tx;
  String? _sealError;
  String? _hint;
  String? _mythicNote; // "Mythic #3/100" or sold-out notice
  late final String _caughtLine = copy.caught(widget.spawn.grade),
      _fledLine = copy.fled(widget.spawn.species.name),
      _fledHint = copy.fledHint();

  @override
  void initState() {
    super.initState();
    _openCamera();
  }

  Future<void> _openCamera() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() => _camera = ctrl);
    } catch (e) {
      setState(() => _cameraError = 'Camera unavailable');
    }
  }

  Future<void> _capture() async {
    final cam = _camera;
    if (cam == null || cam.value.isTakingPicture) return;
    final shot = await cam.takePicture();
    final dir = await getApplicationDocumentsDirectory();
    final path =
        '${dir.path}/imprint_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(shot.path).copy(path);
    _startTether(path);
  }

  void _startTether(String? photo) {
    _camera?.dispose();
    _camera = null;
    setState(() {
      _photoPath = photo;
      stage = _Stage.tether;
      _game = _newGame();
    });
  }

  TetherGame _newGame() {
    final ability = buddy?.species.ability;
    _pickDefaultOrb();
    return TetherGame(
      species: widget.spawn.species,
      grade: widget.spawn.grade,
      takeOrb: () => profile.useOrb(_orb) ? _orb : null,
      resolveThrow: _resolveThrow,
      onSettled: _settled,
      bandScale: ability == Ability.refract ? 1.35 : 1,
      slowScale: ability == Ability.overclock ? 1.25 : 1,
    );
  }

  /// Keeps the selected orb if any are left, else the cheapest one in the bag.
  void _pickDefaultOrb() {
    if (profile.orbsLeft(_orb) > 0) return;
    _orb = Orb.values.firstWhere(
      (o) => profile.orbsLeft(o) > 0 && o != Orb.crown,
      orElse: () => profile.orbsLeft(Orb.crown) > 0 ? Orb.crown : Orb.seed,
    );
  }

  ThrowOutcome _resolveThrow(double accuracy, Orb orb) {
    final s = widget.spawn;
    _throws++;
    final rng = Random();
    final caught = rng.nextDouble() < catchChance(s, accuracy, orb);
    final fled = !caught && rng.nextDouble() < fleeChance(s);
    _lastAccuracy = accuracy;
    return ThrowOutcome(caught: caught, fled: fled);
  }

  double _lastAccuracy = 0.5;

  Future<void> _settled(ThrowOutcome o) async {
    final s = widget.spawn;
    if (o.fled) {
      sound.play(Sfx.fled);
      fledSpawns.add(s.id);
      setState(() => stage = _Stage.fled);
      return;
    }
    if (!o.caught) {
      sound.play(Sfx.breakFree);
      setState(() {
        _pickDefaultOrb();
        _hint = profile.totalOrbs == 0 ? copy.outOfOrbs() : copy.brokeFree();
      });
      return;
    }
    await _seal();
  }

  /// Seals the bond on Monad: backend voucher, then the player's own
  /// transaction mints the Kin, burns every orb thrown and pays the reward.
  Future<void> _seal() async {
    final s = widget.spawn;
    setState(() {
      stage = _Stage.sealing;
      _sealError = null;
    });
    try {
      final p = location.position;
      final v = await BackendApi.voucher(await auth.accessToken(), {
        'spawnId': s.id,
        'species': species.indexOf(s.species),
        'lat': p.latitude,
        'lng': p.longitude,
        if (s.kind == SpawnKind.weather)
          'boosted': [for (final a in conditions.boosted) a.index],
      });
      final m = v['mythic'] as Map<String, dynamic>?;
      _mythicNote = m == null
          ? null
          : m['soldOut'] == true
          ? '${s.species.name} Mythics are sold out this season, so it bonded as Epic.'
          : (m['serial'] as int? ?? 0) > 0
          ? 'Mythic ${s.species.name} #${m['serial']}/${m['cap']} this season'
          : null;
      final burn = profile.throwsToBurn;
      final (kinId, reward, tx) = await chain.bond(
        (v['voucher'] as Map).cast<String, dynamic>(),
        v['signature'] as String,
        burn,
        'Bonded ${s.grade.label} ${s.species.name}',
      );
      profile.clearThrows(burn);
      await collection.remember(
        kinId,
        KinMeta(
          imprintPath: _photoPath,
          spawnId: s.id,
          resonance: (40 + 60 * _lastAccuracy).round().clamp(0, 100),
        ),
      );
      await chain.sync();
      // First Kin becomes the buddy automatically.
      if (buddy == null) await profile.setBuddy(kinId);
      if (!mounted) return;
      sound.play(s.grade == Grade.mythic ? Sfx.crown : Sfx.catchKin);
      Future.delayed(
        const Duration(milliseconds: 900),
        () => sound.play(Sfx.coin),
      );
      setState(() {
        _reward = reward;
        _tx = tx;
        _kin = collection.byUid(kinId);
        stage = _Stage.bonded;
      });
    } catch (e) {
      if (mounted) setState(() => _sealError = e.toString());
    }
  }

  Widget _sealingView() => SafeArea(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Bobbing(child: KinSprite(widget.spawn.species, size: 140)),
            const SizedBox(height: 20),
            if (_sealError == null) ...[
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: TK.signal,
                ),
              ),
              const SizedBox(height: 14),
              Text('Sealing the bond on Monad…', style: TK.display(20)),
              const SizedBox(height: 6),
              Text(
                'Your wallet signs one transaction. It confirms in about a second.',
                textAlign: TextAlign.center,
                style: TK.body(13, color: TK.mist),
              ),
            ] else ...[
              Text(
                'The bond didn\'t go through',
                style: TK.display(20, color: TK.danger),
              ),
              const SizedBox(height: 8),
              Text(
                _sealError!,
                textAlign: TextAlign.center,
                style: TK.body(14, color: TK.mist),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _seal, child: const Text('Try again')),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Leave it'),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SceneMusic(
      Scene.encounter,
      child: Scaffold(
        backgroundColor: TK.night,
        body: switch (stage) {
          _Stage.camera => _cameraView(),
          _Stage.tether => _tetherView(),
          _Stage.sealing => _sealingView(),
          _Stage.bonded => _resultView(),
          _Stage.fled => _fledView(),
        },
      ),
    );
  }

  Widget _header() {
    final s = widget.spawn;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: TK.paper),
            ),
            Image.asset(s.species.affinity.emblem, width: 28),
            const SizedBox(width: 8),
            Text(s.species.name, style: TK.display(22)),
            const Spacer(),
            GradeGems(s.grade),
          ],
        ),
      ),
    );
  }

  Widget _cameraView() {
    final cam = _camera;
    final s = widget.spawn;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (cam != null)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: cam.value.previewSize?.height ?? 1080,
              height: cam.value.previewSize?.width ?? 1920,
              child: CameraPreview(cam),
            ),
          )
        else
          Center(
            child: Text(
              _cameraError ?? 'Opening camera…',
              style: TK.body(15, color: TK.mist),
            ),
          ),
        Align(alignment: Alignment.topCenter, child: _header()),
        Align(
          alignment: const Alignment(0, 0.15),
          child: Bobbing(child: KinSprite(s.species, size: 150)),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: TK.dusk.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Photograph the place to make your Imprint',
                      style: TK.body(13, color: TK.paper),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (cam != null)
                    GestureDetector(
                      onTap: _capture,
                      child: Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: TK.paper,
                          border: Border.all(color: TK.signal, width: 6),
                        ),
                      ),
                    )
                  else
                    FilledButton(
                      onPressed: () => _startTether(null),
                      child: const Text('Bond without photo'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tetherView() {
    final photo = _photoPath;
    final chance = (catchChance(widget.spawn, 0.8, _orb) * 100).round();
    return Stack(
      fit: StackFit.expand,
      children: [
        if (photo != null) Image.file(File(photo), fit: BoxFit.cover),
        Container(color: TK.night.withValues(alpha: photo != null ? 0.55 : 1)),
        GameWidget(key: ObjectKey(_game), game: _game!),
        Align(alignment: Alignment.topCenter, child: _header()),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: ListenableBuilder(
                listenable: profile,
                builder: (_, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _hint ?? 'Tap when the ring crosses the glow to throw',
                      textAlign: TextAlign.center,
                      style: TK.body(
                        15,
                        color: _hint != null ? TK.signal : TK.paper,
                        bold: true,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _orb.guaranteed
                          ? '${_orb.label}: always bonds'
                          : '${_orb.label}: about $chance% on a Great throw · throws: $_throws',
                      style: TK.body(12, color: TK.mist),
                    ),
                    const SizedBox(height: 10),
                    _orbTray(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _orbTray() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    decoration: BoxDecoration(
      color: TK.dusk.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: TK.slate),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final o in Orb.values)
          GestureDetector(
            onTap: profile.orbsLeft(o) > 0
                ? () => setState(() => _orb = o)
                : null,
            child: Opacity(
              opacity: profile.orbsLeft(o) > 0 ? 1 : 0.35,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: o == _orb ? TK.signal : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: OrbIcon(o, size: 44),
                  ),
                  Text(
                    '×${profile.orbsLeft(o)}',
                    style: TK.body(12, bold: true),
                  ),
                ],
              ),
            ),
          ),
        GestureDetector(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MarketScreen()),
            );
            if (mounted) setState(_pickDefaultOrb);
          },
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.storefront_rounded,
                  color: TK.signal,
                  size: 38,
                ),
              ),
              Text('Buy', style: TK.body(12, bold: true)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _resultView() {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                _caughtLine,
                textAlign: TextAlign.center,
                style: TK.display(34, color: TK.signal),
              ),
              const SizedBox(height: 4),
              Text(
                '+${fmtMon(_reward)} · ${_throws == 1 ? 'first throw' : '$_throws throws'}',
                style: TK.body(15, color: TK.paper, bold: true),
              ),
              if (_mythicNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _mythicNote!,
                    textAlign: TextAlign.center,
                    style: TK.body(13, color: Grade.mythic.color, bold: true),
                  ),
                ),
              if (_tx != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Sealed on Monad in ${(_tx!.confirmMs / 1000).toStringAsFixed(1)} s · gas ${fmtMon(_tx!.feeWei)}',
                  style: TK.body(12, color: TK.mist),
                ),
              ],
              const SizedBox(height: 16),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutBack,
                builder: (_, v, child) => Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY((1 - v) * pi / 2),
                  child: child,
                ),
                child: KinCard(
                  _kin!,
                  conditions: conditions,
                  player: location.position,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => showMemeCard(
                        context,
                        MemeCardData(
                          headline: _caughtLine,
                          subtitle:
                              '${widget.spawn.grade.label} ${widget.spawn.species.name}'
                              '${widget.spawn.landmark ? ' · Landmark' : ''}',
                          art: widget.spawn.species.sprite,
                          accent: widget.spawn.grade.color,
                          chips: [
                            if (_mythicNote != null &&
                                _mythicNote!.startsWith('Mythic'))
                              _mythicNote!.split(' ').sublist(2, 3).join(),
                            '+${fmtMon(_reward)}',
                            _throws == 1 ? 'first throw' : '$_throws throws',
                            if (weather.place != null) weather.place!,
                          ],
                          footer: '@${chain.name}',
                          shareText:
                              'Just bonded a ${widget.spawn.grade.label} ${widget.spawn.species.name} on Terrakin 🌱 #Terrakin #Monad',
                        ),
                      ),
                      icon: const Icon(Icons.ios_share_rounded),
                      label: const Text('Share'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to the map'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fledView() {
    final s = widget.spawn;
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.6,
              child: KinSprite(s.species, size: 140, glow: false),
            ),
            const SizedBox(height: 16),
            Text(_fledLine, textAlign: TextAlign.center, style: TK.display(26)),
            const SizedBox(height: 8),
            Text(
              _fledHint,
              textAlign: TextAlign.center,
              style: TK.body(14, color: TK.mist),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to the map'),
            ),
          ],
        ),
      ),
    );
  }
}
