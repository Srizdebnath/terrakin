import 'dart:math';

import 'conditions.dart';
import 'species.dart';

/// Per-individual quirk, rolled with the spawn so every player who reaches the
/// same coordinate meets the same Kin.
enum Trait {
  stormborn('Stormborn', '+25% in rain and storms'),
  sunkissed('Sunkissed', '+20% under clear daytime skies'),
  nightborn('Nightborn', '+20% at night'),
  mistwalker('Mistwalker', '+20% in fog and overcast'),
  homebody('Homebody', 'Homeground bonus doubled'),
  wanderer('Wanderer', 'Earns 50% more Stride'),
  steady('Steady', '+8% always');

  const Trait(this.label, this.description);
  final String label;
  final String description;
}

/// Hidden per-stat roll, 0..15 each (like a fingerprint of this individual).
class Vigor {
  const Vigor(this.hp, this.atk, this.def, this.spd);
  final int hp, atk, def, spd;

  int get total => hp + atk + def + spd;
  List<int> toList() => [hp, atk, def, spd];
  factory Vigor.fromList(List l) => Vigor(l[0], l[1], l[2], l[3]);
}

/// What a Kin *is*: fixed when it spawns, identical for every player.
class Genes {
  const Genes(this.species, this.grade, this.vigor, this.trait);
  final Species species;
  final Grade grade;
  final Vigor vigor;
  final Trait trait;

  static Genes roll(Random rng, Species sp, Grade grade, {int minVigor = 0}) {
    int v() => minVigor + rng.nextInt(16 - minVigor);
    return Genes(sp, grade, Vigor(v(), v(), v(), v()), Trait.values[rng.nextInt(Trait.values.length)]);
  }

  StatBlock stats({int level = 1}) {
    final g = grade.statMultiplier * (1 + 0.04 * (level - 1));
    final b = species.base;
    int s(int base, int vig) => (base * g * (1 + vig / 30)).round();
    return StatBlock(
      s(b.hp, vigor.hp) * 2,
      s(b.atk, vigor.atk),
      s(b.def, vigor.def),
      s(b.spd, vigor.spd),
    );
  }
}

class StatBlock {
  const StatBlock(this.hp, this.atk, this.def, this.spd);
  final int hp, atk, def, spd;

  /// One number to compare Kin by.
  int get power => (atk * 1.0 + def * 0.7 + hp * 0.2 + spd * 0.5).round();

  StatBlock scaled(double m) =>
      StatBlock((hp * m).round(), (atk * m).round(), (def * m).round(), (spd * m).round());

  /// Per-stat multipliers in hp, atk, def, spd order (trade shifts).
  StatBlock withMods(List<double> m) =>
      StatBlock((hp * m[0]).round(), (atk * m[1]).round(), (def * m[2]).round(), (spd * m[3]).round());
}

/// A labelled live multiplier, for showing *why* a Kin is stronger right now.
class Modifier {
  const Modifier(this.label, this.factor);
  final String label;
  final double factor;
}

/// Live modifiers from the real world: weather, time of day, and distance from
/// the Kin's origin coordinate.
List<Modifier> liveModifiers(Genes g, Conditions c, {double? metresFromOrigin}) {
  final out = <Modifier>[];
  final a = g.species.affinity;
  if (c.boosted.contains(a)) {
    out.add(Modifier('Attuned · ${c.sky.label}', a == Affinity.volt && c.sky == Sky.storm ? 1.25 : 1.2));
  } else if (c.dampened.contains(a)) {
    out.add(Modifier('Sulking · ${c.sky.label}', 0.9));
  }
  final t = switch (g.trait) {
    Trait.stormborn when c.sky.wet => 1.25,
    Trait.sunkissed when c.sky == Sky.clear && c.isDay => 1.2,
    Trait.nightborn when c.isNight => 1.2,
    Trait.mistwalker when c.sky == Sky.fog || c.sky == Sky.cloudy => 1.2,
    Trait.steady => 1.08,
    _ => 1.0,
  };
  if (t != 1.0) out.add(Modifier(g.trait.label, t));
  if (metresFromOrigin != null && metresFromOrigin <= homegroundMetres) {
    out.add(Modifier('Homeground', g.trait == Trait.homebody ? 1.3 : 1.15));
  }
  return out;
}

const homegroundMetres = 1000.0;

double combined(List<Modifier> mods) => mods.fold(1.0, (a, m) => a * m.factor);

/// Stride level from metres walked as buddy: 250 m → 2, 1 km → 3, 2.25 km → 4…
int strideLevel(double metres) => min(30, 1 + sqrt(metres / 250).floor());

double strideForLevel(int level) => pow(level - 1, 2) * 250.0;
