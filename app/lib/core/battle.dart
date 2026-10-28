/// Integer mirror of TerrakinTerritory.fighter / simulate. The contract
/// decides every hex battle; the app re-runs it from the Battle event's seed
/// to animate the replay. test/battle_test.dart pins it to the Solidity
/// vectors in contracts/test/TerrakinTerritory.t.sol.
class Fighter {
  const Fighter(this.hp, this.atk, this.def, this.spd);
  final int hp, atk, def, spd;

  /// Species base stats in hp, atk, def, spd order (species.dart, by index).
  static const _bases = [
    [72, 44, 56, 40],
    [62, 50, 46, 56],
    [56, 64, 40, 58],
    [76, 48, 66, 30],
    [50, 60, 46, 62],
    [48, 56, 38, 74],
    [86, 42, 74, 26],
  ];
  static const _gradeMul = [100, 115, 135, 160, 200];

  /// Battle stats from on-chain genes: [vigor] 0..15 and [mods] in basis
  /// points. Defenders ([home]) get +10% HP.
  factory Fighter.of(int species, int grade, List<int> vigor, List<int> mods, {required bool home}) {
    final s = [
      for (var i = 0; i < 4; i++) _bases[species][i] * _gradeMul[grade] * (30 + vigor[i]) * mods[i] ~/ 30000000,
    ];
    return Fighter(s[0] * 2 * (home ? 11 : 10) ~/ 10, s[1], s[2], s[3]);
  }
}

/// One blow, for the replay.
class Strike {
  const Strike(this.byAttacker, this.attackerIndex, this.defenderIndex, this.damage, this.hpAfter, this.fainted);
  final bool byAttacker;
  final int attackerIndex, defenderIndex, damage, hpAfter;
  final bool fainted;
}

class BattleResult {
  const BattleResult(this.attackerWon, this.turns, this.hpLeft, this.strikes);
  final bool attackerWon;
  final int turns, hpLeft;
  final List<Strike> strikes;
}

const maxBattleTurns = 48;

/// [seed] is the Battle event's bytes32; only its low 64 bits drive the dice.
BattleResult simulateBattle(List<Fighter> a, List<Fighter> d, BigInt seed) {
  final strikes = <Strike>[];
  if (d.isEmpty) return BattleResult(true, 0, a[0].hp, strikes);
  // Dart ints wrap at 64 bits like Solidity's unchecked uint64; >>> keeps the
  // shift unsigned.
  var x = seed.toUnsigned(64).toSigned(64).toInt();
  var i = 0, j = 0, hpA = a[0].hp, hpD = d[0].hp;
  for (var turn = 0; turn < maxBattleTurns; turn++) {
    final aFirst = a[i].spd > d[j].spd;
    for (var k = 0; k < 2; k++) {
      final aStrikes = (k == 0) == aFirst;
      x = x * 6364136223846793005 + 1442695040888963407;
      final roll = 85 + (x >>> 33) % 16;
      if (aStrikes) {
        final dmg = _damage(a[i].atk, d[j].def, roll);
        if (dmg >= hpD) {
          strikes.add(Strike(true, i, j, dmg, 0, true));
          if (++j == d.length) return BattleResult(true, turn + 1, hpA, strikes);
          hpD = d[j].hp;
          break;
        }
        hpD -= dmg;
        strikes.add(Strike(true, i, j, dmg, hpD, false));
      } else {
        final dmg = _damage(d[j].atk, a[i].def, roll);
        if (dmg >= hpA) {
          strikes.add(Strike(false, i, j, dmg, 0, true));
          if (++i == a.length) return BattleResult(false, turn + 1, hpD, strikes);
          hpA = a[i].hp;
          break;
        }
        hpA -= dmg;
        strikes.add(Strike(false, i, j, dmg, hpA, false));
      }
    }
  }
  return BattleResult(false, maxBattleTurns, hpD, strikes);
}

int _damage(int atk, int def, int roll) {
  final dmg = atk + def == 0 ? 0 : atk * atk ~/ (atk + def) * roll ~/ 100;
  return dmg == 0 ? 1 : dmg;
}
