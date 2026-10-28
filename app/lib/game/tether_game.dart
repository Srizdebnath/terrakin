import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/animation.dart' show Cubic, Curves;
import 'package:flutter/painting.dart' show TextStyle, FontVariation;
import 'package:flutter/services.dart' show HapticFeedback;
import '../core/sound.dart';

import '../core/economy.dart';
import '../core/species.dart';
import '../widgets/orb_painter.dart';

class ThrowOutcome {
  const ThrowOutcome({required this.caught, required this.fled});
  final bool caught;
  final bool fled;
}

/// The Tether (SRS FR-BND-04), now with orbs: a ring pulses around the Kin and
/// the player taps as it crosses the glow to throw the selected orb. Timing
/// sets accuracy; the orb's pull and the Kin's Grade decide whether it holds.
class TetherGame extends FlameGame with TapCallbacks {
  TetherGame({
    required this.species,
    required this.grade,
    required this.takeOrb,
    required this.resolveThrow,
    required this.onSettled,
    this.bandScale = 1,
    this.slowScale = 1,
  });

  final Species species;
  final Grade grade;

  /// Removes the selected orb from the bag; null when none are left.
  final Orb? Function() takeOrb;

  /// Decides the throw's result (the animation then reveals it).
  final ThrowOutcome Function(double accuracy, Orb orb) resolveThrow;
  final void Function(ThrowOutcome outcome) onSettled;

  /// Buddy abilities: Refract widens the glow band, Overclock slows the ring.
  final double bandScale;
  final double slowScale;

  late final SpriteComponent kin;
  late final TetherRing ring;
  bool aiming = true;
  bool finished = false;

  Vector2 get focus => Vector2(size.x / 2, size.y * 0.4);

  /// Higher grades pulse faster: Common 1.7 s down to Mythic 0.9 s.
  double get pulseSeconds => (1.7 - (grade.index * 0.2)) * slowScale;

  double get band => TetherRing.band * bandScale;

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    kin = SpriteComponent(
      sprite: await loadSprite('kin/${species.id}.png'),
      size: Vector2.all(150),
      anchor: Anchor.center,
      position: focus,
    );
    kin.add(MoveEffect.by(
      Vector2(0, -8),
      EffectController(duration: 0.8, alternate: true, infinite: true, curve: _easeInOut),
    ));
    ring = TetherRing();
    addAll([ring, kin]);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) kin.position = focus;
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (!aiming || finished) return;
    final orb = takeOrb();
    if (orb == null) {
      flash('No orb', bad: true);
      return;
    }
    final err = (ring.radius - TetherRing.target).abs();
    final acc = (1 - err / (70 * bandScale)).clamp(0.0, 1.0);
    aiming = false;
    HapticFeedback.lightImpact();
    sound.play(Sfx.throwOrb);
    flash(switch (acc) {
      > 0.9 => 'Perfect',
      > 0.7 => 'Great',
      > 0.4 => 'Good',
      _ => 'Wide',
    }, bad: acc <= 0.4);
    final outcome = resolveThrow(acc, orb);
    add(OrbThrow(
      orb: orb,
      from: Vector2(size.x / 2, size.y - 60),
      to: focus.clone(),
      outcome: outcome,
    ));
  }

  /// Called by [OrbThrow] when its animation has played out.
  void settle(ThrowOutcome o) {
    if (o.caught) {
      finished = true;
      flash('Bonded!');
      add(TimerComponent(period: 0.9, removeOnFinish: true, onTick: () => onSettled(o)));
      return;
    }
    if (o.fled) {
      finished = true;
      kin
        ..scale = Vector2.all(1)
        ..add(OpacityEffect.to(0, EffectController(duration: 0.6)));
      flash('It fled…', bad: true);
      add(TimerComponent(period: 0.9, removeOnFinish: true, onTick: () => onSettled(o)));
      return;
    }
    kin.add(ScaleEffect.to(Vector2.all(1), EffectController(duration: 0.25, curve: Curves.easeOutBack)));
    flash('Broke free!', bad: true);
    add(TimerComponent(
      period: 0.6,
      removeOnFinish: true,
      onTick: () {
        aiming = true;
        ring.restart(delay: 0.2);
        onSettled(o);
      },
    ));
  }

  void flash(String word, {bool bad = false}) {
    final text = TextComponent(
      text: word,
      anchor: Anchor.center,
      position: focus + Vector2(0, -130),
      textRenderer: TextPaint(
        style: TextStyle(
          fontFamily: 'Fredoka',
          fontSize: 34,
          color: bad ? const Color(0xFFFF5D6C) : const Color(0xFFFFB547),
          fontVariations: const [FontVariation('wght', 600)],
          shadows: const [Shadow(color: Color(0xFF231A2E), offset: Offset(0, 3))],
        ),
      ),
    );
    text.addAll([
      MoveEffect.by(Vector2(0, -30), EffectController(duration: 0.7)),
      RemoveEffect(delay: 0.7),
    ]);
    add(text);
  }
}

const _easeInOut = Cubic(0.42, 0, 0.58, 1);

/// The orb's flight: arc in, swallow the Kin, drop, wobble, then reveal.
class OrbThrow extends PositionComponent with HasGameReference<TetherGame> {
  OrbThrow({required this.orb, required this.from, required this.to, required this.outcome})
      : super(anchor: Anchor.center, size: Vector2.all(56), position: from.clone(), priority: 10);

  final Orb orb;
  final Vector2 from, to;
  final ThrowOutcome outcome;

  static const _fly = 0.55, _drop = 0.3, _wobble = 0.55, _gap = 0.25;
  double _t = 0;
  late final int _wobbles = outcome.caught ? 3 : 1 + Random().nextInt(2);
  bool _swallowed = false, _done = false;
  double _glow = 0;

  Vector2 get _rest => to + Vector2(0, 70);

  @override
  void update(double dt) {
    _t += dt;
    if (_t < _fly) {
      final k = _t / _fly;
      position = from + (to - from) * k + Vector2(0, -220 * 4 * k * (1 - k));
      angle += dt * 14;
      scale = Vector2.all(1.1 - 0.35 * k);
      return;
    }
    if (!_swallowed) {
      _swallowed = true;
      angle = 0;
      _glow = 1;
      game.kin.add(ScaleEffect.to(Vector2.zero(), EffectController(duration: 0.18)));
      HapticFeedback.mediumImpact();
      sound.play(Sfx.reveal);
    }
    _glow = max(0, _glow - dt * 3);
    final t2 = _t - _fly;
    if (t2 < _drop) {
      position = to + (_rest - to) * Curves.bounceOut.transform(t2 / _drop);
      return;
    }
    final t3 = t2 - _drop;
    final cycle = _wobble + _gap;
    final i = (t3 / cycle).floor();
    if (i < _wobbles) {
      final w = t3 - i * cycle;
      angle = w < _wobble ? sin(w / _wobble * 2 * pi) * 0.45 : 0;
      if (w < dt) {
        HapticFeedback.selectionClick();
        sound.play(Sfx.wobble);
      }
      return;
    }
    if (_done) return;
    _done = true;
    angle = 0;
    if (outcome.caught) {
      _glow = 1;
      _burst();
    } else {
      removeFromParent();
    }
    game.settle(outcome);
  }

  void _burst() {
    for (var i = 0; i < 10; i++) {
      final a = i / 10 * 2 * pi;
      final star = CircleComponent(
        radius: 5,
        anchor: Anchor.center,
        position: position.clone(),
        paint: Paint()..color = orb.top,
      );
      star.addAll([
        MoveEffect.by(Vector2(cos(a), sin(a)) * 90, EffectController(duration: 0.6, curve: Curves.easeOut)),
        RemoveEffect(delay: 0.6),
      ]);
      game.add(star);
    }
  }

  @override
  void render(Canvas canvas) {
    paintOrb(canvas, (size / 2).toOffset(), size.x / 2, orb, glow: _glow);
  }
}

class TetherRing extends Component with HasGameReference<TetherGame> {
  static const start = 230.0;
  static const end = 40.0;
  static const target = 100.0;
  static const band = 18.0;

  double _t = 0;
  double _delay = 0.5;

  double get radius => start + (end - start) * (_t / game.pulseSeconds);

  void restart({double delay = 0}) {
    _t = 0;
    _delay = delay;
  }

  @override
  void update(double dt) {
    if (!game.aiming) return;
    if (_delay > 0) {
      _delay -= dt;
      return;
    }
    _t += dt;
    if (_t >= game.pulseSeconds) _t = 0; // keeps pulsing until you throw
  }

  @override
  void render(Canvas canvas) {
    if (game.finished) return;
    final c = game.focus.toOffset();
    final color = game.species.affinity.color;
    final active = game.aiming && _delay <= 0;
    final near = active && (radius - target).abs() < game.band;

    canvas.drawCircle(
      c,
      target,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = game.band * 2
        ..color = color.withValues(alpha: near ? 0.55 : 0.28),
    );
    canvas.drawCircle(
      c,
      target,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFF6EFE2).withValues(alpha: 0.5),
    );
    if (!active) return;
    canvas.drawCircle(
      c,
      max(radius, 0),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = near ? const Color(0xFFFFB547) : const Color(0xFFF6EFE2),
    );
  }
}
