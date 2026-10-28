// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title BattleLib
/// @notice Kin battle stats and the deterministic auto-battle, shared by hex
/// battles (TerrakinTerritory) and staked duels (TerrakinLab). The app mirrors
/// it in app/lib/core/battle.dart; test vectors pin the two together.
library BattleLib {
    struct Fighter {
        uint256 hp;
        uint256 atk;
        uint256 def;
        uint256 spd;
    }

    uint256 internal constant MAX_TURNS = 48;

    /// Species base stats, 8 bits each: species s, stat i at bit s*32 + i*8
    /// (hp, atk, def, spd). Mirrors app/lib/core/species.dart.
    uint256 internal constant BASES = uint256(72) | 44 << 8 | 56 << 16 | 40 << 24 // mossling
        | 62 << 32 | 50 << 40 | 46 << 48 | 56 << 56 // ripplet
        | 56 << 64 | 64 << 72 | 40 << 80 | 58 << 88 // emberpup
        | 76 << 96 | 48 << 104 | 66 << 112 | 30 << 120 // glyphlet
        | 50 << 128 | 60 << 136 | 46 << 144 | 62 << 152 // shardlet
        | 48 << 160 | 56 << 168 | 38 << 176 | 74 << 184 // sparkit
        | 86 << 192 | 42 << 200 | 74 << 208 | 26 << 216; // pebblet

    /// Battle stats of a packed Kin record (Terrakin's layout). Integer mirror
    /// of the app's stat formula without live weather/level modifiers;
    /// defenders get +10% HP for home turf.
    function fighter(uint256 w, bool home) internal pure returns (Fighter memory f) {
        uint256 species = uint8(w);
        uint256 grade = uint8(w >> 8);
        uint256 gm = grade == 0 ? 100 : grade == 1 ? 115 : grade == 2 ? 135 : grade == 3 ? 160 : 200;
        uint256[4] memory s;
        for (uint256 i; i < 4; ++i) {
            uint256 base = uint8(BASES >> (species * 32 + i * 8));
            uint256 vig = uint8(w >> (152 + 8 * i));
            uint256 mod = uint16(w >> (184 + 16 * i));
            s[i] = base * gm * (30 + vig) * mod / 30_000_000;
        }
        f = Fighter(s[0] * 2 * (home ? 11 : 10) / 10, s[1], s[2], s[3]);
    }

    /// Deterministic battle. Lineups fight in order; each turn the faster
    /// Kin (ties go to the defender) strikes first and the other strikes back
    /// if still standing. Damage = atk^2 / (atk + def) x 85-100%, at least 1.
    /// The defence wins ties and battles that hit MAX_TURNS. [hpLeft] is the
    /// winner's active Kin's remaining HP. The app replays
    /// it from the Battle event with the same integer math.
    function simulate(Fighter[] memory a, Fighter[] memory d, bytes32 seed)
        public
        pure
        returns (bool attackerWon, uint256 turns, uint256 hpLeft)
    {
        if (d.length == 0) return (true, 0, a[0].hp);
        uint64 x = uint64(uint256(seed));
        uint256 i;
        uint256 j;
        uint256 hpA = a[0].hp;
        uint256 hpD = d[0].hp;
        for (; turns < MAX_TURNS; ++turns) {
            bool aFirst = a[i].spd > d[j].spd;
            for (uint256 k; k < 2; ++k) {
                bool aStrikes = (k == 0) == aFirst;
                uint256 dmg;
                unchecked {
                    x = x * 6364136223846793005 + 1442695040888963407;
                }
                uint256 roll = 85 + (x >> 33) % 16;
                if (aStrikes) {
                    dmg = _damage(a[i].atk, d[j].def, roll);
                    if (dmg >= hpD) {
                        if (++j == d.length) return (true, turns + 1, hpA);
                        hpD = d[j].hp;
                        break;
                    }
                    hpD -= dmg;
                } else {
                    dmg = _damage(d[j].atk, a[i].def, roll);
                    if (dmg >= hpA) {
                        if (++i == a.length) return (false, turns + 1, hpD);
                        hpA = a[i].hp;
                        break;
                    }
                    hpA -= dmg;
                }
            }
        }
        return (false, turns, hpD);
    }

    function _damage(uint256 atk, uint256 def, uint256 roll) internal pure returns (uint256 dmg) {
        dmg = atk + def == 0 ? 0 : atk * atk / (atk + def) * roll / 100;
        if (dmg == 0) dmg = 1;
    }

}
