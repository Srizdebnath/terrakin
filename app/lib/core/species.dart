import 'package:flutter/painting.dart';

enum Affinity {
  grove('Grove', Color(0xFF5FBF6A), Color(0xFF3E9150)),
  tide('Tide', Color(0xFF4CB3E6), Color(0xFF2E85B8)),
  forge('Forge', Color(0xFFFF8A3D), Color(0xFFD9612A)),
  rune('Rune', Color(0xFFC9A26B), Color(0xFF9C7A4A)),
  prism('Prism', Color(0xFFC77DFF), Color(0xFF9A52D6)),
  volt('Volt', Color(0xFFFFD93D), Color(0xFFE0B020)),
  stone('Stone', Color(0xFF8E9AAF), Color(0xFF68748A));

  const Affinity(this.label, this.color, this.shade);
  final String label;
  final Color color;
  final Color shade;

  String get emblem => 'assets/images/emblems/$name.png';
}

/// Grade table from SRS section 3.2. `weight` is the base wild spawn share in percent.
enum Grade {
  common('Common', 1, 62, 1.0, Color(0xFF9AA0B5)),
  uncommon('Uncommon', 2, 26, 1.15, Color(0xFF5FBF6A)),
  rare('Rare', 3, 9.5, 1.35, Color(0xFF4CB3E6)),
  epic('Epic', 4, 2.3, 1.6, Color(0xFFC77DFF)),
  mythic('Mythic', 5, 0.2, 2.0, Color(0xFFFFB547));

  const Grade(this.label, this.gems, this.weight, this.statMultiplier, this.color);
  final String label;
  final int gems;
  final double weight;
  final double statMultiplier;
  final Color color;

  String get gem => 'assets/images/grades/$name.png';

  /// Chance a perfect Tether bonds this grade; scaled by accuracy at runtime.
  double get bondChance => switch (this) {
        Grade.common => 0.95,
        Grade.uncommon => 0.85,
        Grade.rare => 0.7,
        Grade.epic => 0.5,
        Grade.mythic => 0.3,
      };
}

/// Field abilities: they work while the Kin walks with you as your buddy.
enum Ability {
  photosynth('Photosynth', 'Walking in daylight under clear or light-cloud skies earns 50% more Stride.'),
  rainsense('Rainsense', 'In drizzle, rain or storms your bond reach grows by 20 m.'),
  emberNose('Ember Nose', 'Rare, Epic and Mythic Kin show up from twice as far away.'),
  oldMemory('Old Memory', 'Landmark Kin show on your radar from much farther away.'),
  refract('Refract', 'The Tether glow band is 35% wider.'),
  overclock('Overclock', 'The Tether ring shrinks 20% slower.'),
  steadfast('Steadfast', 'Kin that break free from an orb are half as likely to flee.');

  const Ability(this.label, this.description);
  final String label;
  final String description;
}

class BaseStats {
  const BaseStats(this.hp, this.atk, this.def, this.spd);
  final int hp, atk, def, spd;
}

class Species {
  const Species(this.id, this.name, this.affinity, this.blurb, this.base, this.ability);
  final String id;
  final String name;
  final Affinity affinity;
  final String blurb;
  final BaseStats base;
  final Ability ability;

  String get sprite => 'assets/images/kin/$id.png';
}

const species = <Species>[
  Species('mossling', 'Mossling', Affinity.grove,
      'Sprouts a new leaf every time it naps in the sun.', BaseStats(72, 44, 56, 40), Ability.photosynth),
  Species('ripplet', 'Ripplet', Affinity.tide,
      'Hums softly near fountains; its bubbles smell of rain.', BaseStats(62, 50, 46, 56), Ability.rainsense),
  Species('emberpup', 'Emberpup', Affinity.forge,
      'Follows the smell of fresh bread from three streets away.', BaseStats(56, 64, 40, 58), Ability.emberNose),
  Species('glyphlet', 'Glyphlet', Affinity.rune,
      'Carved itself from an old step; the glyph glows when it remembers.', BaseStats(76, 48, 66, 30),
      Ability.oldMemory),
  Species('shardlet', 'Shardlet', Affinity.prism,
      'Catches stray light from murals and keeps it in its crest.', BaseStats(50, 60, 46, 62), Ability.refract),
  Species('sparkit', 'Sparkit', Affinity.volt,
      'Naps on ticket gates and wakes up when a train arrives.', BaseStats(48, 56, 38, 74), Ability.overclock),
  Species('pebblet', 'Pebblet', Affinity.stone,
      'Sleepy and stubborn; has never once been moved by a broom.', BaseStats(86, 42, 74, 26), Ability.steadfast),
];

Species speciesById(String id) => species.firstWhere((s) => s.id == id);

Species speciesOf(Affinity a) => species.firstWhere((s) => s.affinity == a);
