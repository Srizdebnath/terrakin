import 'package:flutter/painting.dart';

import 'species.dart';

/// Game rules that stay on the device. Prices and rewards live on chain
/// (Terrakin.prices()) so they can be tuned without an app update.
class Economy {
  /// Chance a Kin runs off after breaking free, by Grade.
  static double fleeChance(Grade g) => switch (g) {
        Grade.common => 0.08,
        Grade.uncommon => 0.12,
        Grade.rare => 0.18,
        Grade.epic => 0.25,
        Grade.mythic => 0.3,
      };
}

/// Throwable catch orbs, sold in the Market.
enum Orb {
  seed('Seed Orb', 'Everyday orb woven from field grass.', 1.0, Color(0xFF5FBF6A), Color(0xFFA8E39B)),
  bloom('Bloom Orb', 'Petal-bound; Kin settle in it more easily.', 1.6, Color(0xFF4CB3E6), Color(0xFFFFD93D)),
  aurora('Aurora Orb', 'Holds a sliver of sky light. Strong pull.', 2.3, Color(0xFFC77DFF), Color(0xFF4CB3E6)),
  crown('Crown Orb', 'Never misses. Save it for a Mythic.', 0, Color(0xFFFFB547), Color(0xFFFFF0A0));

  const Orb(this.label, this.blurb, this.catchMultiplier, this.top, this.band);
  final String label;
  final String blurb;
  final double catchMultiplier;
  final Color top;
  final Color band;

  bool get guaranteed => this == crown;
}

/// Formats a wei amount as MON with up to 4 decimals, e.g. "0.0005 MON".
String fmtMon(BigInt wei) {
  final micro = (wei ~/ BigInt.from(100000000000000)).toInt(); // 1e-4 MON units
  final whole = micro ~/ 10000;
  final frac = (micro % 10000).toString().padLeft(4, '0').replaceFirst(RegExp(r'0+$'), '');
  return frac.isEmpty ? '$whole MON' : '$whole.$frac MON';
}
