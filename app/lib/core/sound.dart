import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'conditions.dart';

/// Where the player is, which picks the music.
enum Scene { world, encounter, battle, lab }

enum Sfx {
  tap,
  throwOrb,
  wobble,
  catchKin,
  breakFree,
  fled,
  hit,
  ko,
  coin,
  reveal,
  crown,
  jackpot,
  dud,
  claim,
  win,
  lose;

  String get file => 'audio/sfx_${switch (this) {
        Sfx.throwOrb => 'throw',
        Sfx.catchKin => 'catch',
        Sfx.breakFree => 'break_free',
        _ => name,
      }}.ogg';
}

/// Music and sound effects. All audio is synthesised by art/tools/audio.py.
///
/// Screens push their [Scene] when shown and pop it when closed; the world
/// track follows the real weather and time of day. Plays alongside other
/// apps' audio (music, podcasts, navigation) instead of stopping it, since
/// people play this outdoors.
class Sound extends ChangeNotifier with WidgetsBindingObserver {
  Sound._();
  static final instance = Sound._();

  double music = 0.6, sfx = 0.9;

  final _scenes = <Scene>[Scene.world];
  final _pools = <Sfx, AudioPool>{};
  final _a = AudioPlayer(), _b = AudioPlayer();
  late AudioPlayer _live = _a;
  String? _track;
  Conditions? _conditions;
  Timer? _fade;
  bool _paused = false, _ready = false;

  static final _ctx = AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build();

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    music = p.getDouble('vol.music') ?? music;
    sfx = p.getDouble('vol.sfx') ?? sfx;
    for (final pl in [_a, _b]) {
      await pl.setAudioContext(_ctx);
      await pl.setReleaseMode(ReleaseMode.loop);
    }
    WidgetsBinding.instance.addObserver(this);
    _ready = true;
    _apply();
  }

  Future<void> setVolumes({double? music, double? sfx}) async {
    if (music != null) this.music = music;
    if (sfx != null) this.sfx = sfx;
    notifyListeners();
    await _live.setVolume(this.music);
    if (this.music == 0) await _live.pause();
    if (this.music > 0 && _track != null && _live.state != PlayerState.playing && !_paused) await _live.resume();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('vol.music', this.music);
    await p.setDouble('vol.sfx', this.sfx);
  }

  void push(Scene s) {
    _scenes.add(s);
    _apply();
  }

  void pop(Scene s) {
    final i = _scenes.lastIndexOf(s);
    if (i > 0) _scenes.removeAt(i);
    _apply();
  }

  /// Weather and time of day pick the world track.
  void setConditions(Conditions c) {
    _conditions = c;
    _apply();
  }

  void play(Sfx s) {
    if (sfx == 0) return;
    unawaited(() async {
      try {
        final pool = _pools[s] ??= await AudioPool.create(
          source: AssetSource(s.file),
          maxPlayers: 3,
          audioContext: _ctx,
        );
        await pool.start(volume: sfx);
      } catch (_) {
        // A missed sound effect never matters more than the game.
      }
    }());
  }

  String _trackFor(Scene s) => switch (s) {
        Scene.world => switch (_conditions) {
            final c? when c.isNight => 'audio/music_night.ogg',
            final c? when c.sky.wet => 'audio/music_rain.ogg',
            _ => 'audio/music_day.ogg',
          },
        Scene.encounter || Scene.lab => 'audio/music_encounter.ogg',
        Scene.battle => 'audio/music_battle.ogg',
      };

  void _apply() {
    if (!_ready) return;
    final track = _trackFor(_scenes.last);
    if (track == _track) return;
    _track = track;
    unawaited(_crossfade(track));
  }

  /// Fades the live track out and the next one in over ~1 s.
  Future<void> _crossfade(String track) async {
    final out = _live, next = identical(_live, _a) ? _b : _a;
    _live = next;
    _fade?.cancel();
    if (music == 0 || _paused) {
      await out.stop();
      await next.setSource(AssetSource(track));
      return;
    }
    await next.setVolume(0);
    await next.play(AssetSource(track));
    var step = 0;
    const steps = 12;
    _fade = Timer.periodic(const Duration(milliseconds: 80), (t) {
      step++;
      final v = step / steps;
      unawaited(next.setVolume(music * v));
      unawaited(out.setVolume(music * (1 - v)));
      if (step >= steps) {
        t.cancel();
        unawaited(out.stop());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = state != AppLifecycleState.resumed;
    if (away == _paused) return;
    _paused = away;
    if (away) {
      unawaited(_live.pause());
    } else if (music > 0 && _track != null) {
      unawaited(_live.setVolume(music));
      unawaited(_live.resume());
    }
  }
}

final sound = Sound.instance;

/// Pushes a music [Scene] for as long as this widget is on screen.
class SceneMusic extends StatefulWidget {
  const SceneMusic(this.scene, {super.key, required this.child});
  final Scene scene;
  final Widget child;

  @override
  State<SceneMusic> createState() => _SceneMusicState();
}

class _SceneMusicState extends State<SceneMusic> {
  @override
  void initState() {
    super.initState();
    sound.push(widget.scene);
  }

  @override
  void dispose() {
    sound.pop(widget.scene);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
