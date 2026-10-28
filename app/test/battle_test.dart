import 'package:flutter_test/flutter_test.dart';
import 'package:terrakin/core/battle.dart';

/// Expected values come from `forge test --match-test test_BattleVectors -vv`
/// in contracts/; the Solidity contract is the source of truth.
void main() {
  Fighter f(int species, int grade, int vigor, {required bool home}) => Fighter.of(
        species,
        grade,
        [for (var i = 0; i < 4; i++) (vigor >> (8 * i)) & 0xff],
        const [10000, 10000, 10000, 10000],
        home: home,
      );

  test('stats match TerrakinTerritory.fighter', () {
    final mythic = f(6, 4, 0x0F0F0F0F, home: false);
    expect(mythic.hp, 516);
    expect(mythic.atk, 126);
  });

  test('battles match the Solidity vectors', () {
    final a = [f(6, 4, 0x0F0F0F0F, home: false), f(2, 1, 0x05060708, home: false)];
    final d = [f(0, 2, 0x0A0A0A0A, home: true), f(5, 3, 0x01020304, home: true)];
    void check(String seed, bool won, int turns, int hp) {
      final r = simulateBattle(a, d, BigInt.parse(seed.substring(2), radix: 16));
      expect((r.attackerWon, r.turns, r.hpLeft), (won, turns, hp), reason: seed);
    }

    check('0x1612d0957b3a732d8f3c7a4b18a5258fa186411eb6ca4a8658db1fd40efc1996', true, 8, 360);
    check('0xf1de9861b08b21d92b3e3f00dc7e5f604b1aeb5224a75b1f59db814c3dec599c', true, 8, 359);

    a
      ..[0] = f(1, 1, 0x0B0A0908, home: false)
      ..[1] = f(4, 1, 0x0C0B0A09, home: false);
    d
      ..[0] = f(5, 1, 0x05060708, home: true)
      ..[1] = f(0, 0, 0x090A0B0C, home: true);
    const even = [
      ('0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563', 10, 80),
      ('0xb10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6', 10, 73),
      ('0x405787fa12a823e0f2b7631cc41b3ba8828b3321ca811111fa75cd3aa3bb5ace', 10, 50),
      ('0xc2575a0e9e593c00f959f8c92f12db2869c3395a3b0502d05e2516446f71f85b', 11, 16),
      ('0x8a35acfbc15ff81a39ae7d344fd709f28e8600b4aa8c65c6b64bfe7fe36bd19b', 10, 79),
      ('0x036b6384b5eca791c62761152d0c79bb0604c104a5fb6f4eb0703f3154bb3db0', 10, 74),
      ('0xf652222313e28459528d920b65115c16c04f3efc82aaedc97be59f3f377c0d3f', 10, 79),
      ('0xa66cc928b5edb82af9bd49922954155ab7b0942694bea4ce44661d9a8736c688', 10, 72),
    ];
    for (final (seed, turns, hp) in even) {
      check(seed, true, turns, hp);
    }
  });

  test('an undefended hex falls without a fight', () {
    final r = simulateBattle([f(0, 0, 0, home: false)], const [], BigInt.one);
    expect(r.attackerWon, isTrue);
    expect(r.strikes, isEmpty);
  });
}
