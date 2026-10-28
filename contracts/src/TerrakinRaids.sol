// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {BattleLib} from "./BattleLib.sol";

interface IRaidGame {
    function signer() external view returns (address);
    function kinPacked(uint256[] calldata ids) external view returns (address[] memory owners, uint256[] memory packed);
    function moduleGiveOrbs(address to, uint32[4] calldata qty) external;
}

/// @title Terrakin Raids
/// @notice Every Landmark zone has a raid boss each UTC day with one shared
/// HP bar. Players standing at the Landmark (a signed raid pass) pay an entry
/// fee and send up to three Kin at it; each attack is a BattleLib fight
/// against the boss at its current HP, so everyone chips away at the same
/// bar, in parallel. The pot (entry fees minus a house cut) is split by
/// damage dealt. Felling the boss earns the finisher a Crown Orb and everyone
/// who hit it an Aurora Orb.
contract TerrakinRaids is EIP712 {
    struct Pass {
        address player;
        uint64 zone;
        uint32 day;
        uint64 deadline;
    }

    struct Raid {
        uint32 hpLeft; // 0 until the first attack (then counts down)
        bool cleared;
        address finisher;
        uint128 pot;
        uint64 totalDamage;
    }

    bytes32 private constant PASS_TYPEHASH = keccak256("Pass(address player,uint64 zone,uint32 day,uint64 deadline)");
    uint32 public constant BOSS_HP = 8000;
    uint256 public constant BOSS_ATK = 140;
    uint256 public constant BOSS_DEF = 100;
    uint256 public constant BOSS_SPD = 60;

    IRaidGame public immutable game;
    uint128 public immutable entryFee;
    uint16 public immutable houseBps;

    mapping(bytes32 => Raid) public raids;
    mapping(bytes32 => mapping(address => uint64)) public damageOf;
    mapping(bytes32 => mapping(address => bool)) public claimed;
    mapping(address => uint256) internal _nonce;

    event RaidAttack(
        uint64 indexed zone, uint32 indexed day, address indexed player, uint256 damage, bool felled, bytes32 seed, uint256 bossHpBefore
    );
    event RaidClaimed(uint64 indexed zone, uint32 indexed day, address indexed player, uint256 share);

    error BadPass();
    error Expired();
    error Cleared();
    error WrongPayment();
    error BadSquad();
    error NotYours();
    error StillOpen();
    error Nothing();
    error TransferFailed();

    constructor(IRaidGame game_, uint128 entryFee_, uint16 houseBps_) EIP712("Terrakin Raids", "1") {
        game = game_;
        entryFee = entryFee_;
        houseBps = houseBps_;
    }

    function raidId(uint64 zone, uint32 day) public pure returns (bytes32) {
        return keccak256(abi.encode(zone, day));
    }

    /// The boss's species (for art) is fixed per zone and day.
    function bossSpecies(uint64 zone, uint32 day) public pure returns (uint8) {
        return uint8(uint256(raidId(zone, day)) % 7);
    }

    function today() public view returns (uint32) {
        return uint32(block.timestamp / 1 days);
    }

    function attack(Pass calldata p, bytes calldata sig, uint256[] calldata kin)
        external
        payable
        returns (uint256 damage, bool felled)
    {
        if (p.player != msg.sender || p.day != today()) revert BadPass();
        if (block.timestamp > p.deadline) revert Expired();
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(PASS_TYPEHASH, p.player, p.zone, p.day, p.deadline)));
        if (ECDSA.recover(digest, sig) != game.signer()) revert BadPass();
        if (msg.value != entryFee) revert WrongPayment();
        if (kin.length == 0 || kin.length > 3) revert BadSquad();

        bytes32 id = raidId(p.zone, p.day);
        Raid storage r = raids[id];
        if (r.cleared) revert Cleared();
        uint32 hpBefore = r.hpLeft == 0 ? BOSS_HP : r.hpLeft;

        (address[] memory owners, uint256[] memory w) = game.kinPacked(kin);
        BattleLib.Fighter[] memory squad = new BattleLib.Fighter[](kin.length);
        for (uint256 i; i < kin.length; ++i) {
            if (owners[i] != msg.sender) revert NotYours();
            for (uint256 j; j < i; ++j) if (kin[j] == kin[i]) revert BadSquad();
            squad[i] = BattleLib.fighter(w[i], false);
        }
        BattleLib.Fighter[] memory boss = new BattleLib.Fighter[](1);
        boss[0] = BattleLib.Fighter(hpBefore, BOSS_ATK, BOSS_DEF, BOSS_SPD);

        bytes32 seed = keccak256(abi.encode(block.prevrandao, blockhash(block.number - 1), msg.sender, _nonce[msg.sender]++));
        (bool won,, uint256 hpLeft) = BattleLib.simulate(squad, boss, seed);
        felled = won;
        damage = won ? hpBefore : hpBefore - hpLeft;

        r.hpLeft = won ? 0 : uint32(hpLeft);
        r.totalDamage += uint64(damage);
        damageOf[id][msg.sender] += uint64(damage);
        uint256 house = msg.value * houseBps / 10000;
        r.pot += uint128(msg.value - house);
        if (won) {
            r.cleared = true;
            r.finisher = msg.sender;
            game.moduleGiveOrbs(msg.sender, [uint32(0), 0, 0, 1]); // Crown Orb
        } else if (r.hpLeft == 0) {
            r.hpLeft = 1; // never reads as "untouched"
        }
        _send(address(game), house);
        emit RaidAttack(p.zone, p.day, msg.sender, damage, won, seed, hpBefore);
    }

    /// Your share of the pot, by damage, once the boss falls or the day ends.
    /// Felled raids also give everyone who hit it an Aurora Orb.
    function claim(uint64 zone, uint32 day) external returns (uint256 share) {
        bytes32 id = raidId(zone, day);
        Raid storage r = raids[id];
        if (!r.cleared && day >= today()) revert StillOpen();
        uint64 mine = damageOf[id][msg.sender];
        if (mine == 0 || claimed[id][msg.sender]) revert Nothing();
        claimed[id][msg.sender] = true;
        share = uint256(r.pot) * mine / r.totalDamage;
        if (r.cleared) game.moduleGiveOrbs(msg.sender, [uint32(0), 0, 1, 0]);
        _send(msg.sender, share);
        emit RaidClaimed(zone, day, msg.sender, share);
    }

    function raidInfo(uint64 zone, uint32 day, address player)
        external
        view
        returns (uint8 species, uint32 hpLeft, uint32 hpMax, uint128 pot, uint64 totalDamage, bool cleared, address finisher, uint64 mine, bool hasClaimed)
    {
        bytes32 id = raidId(zone, day);
        Raid memory r = raids[id];
        return (
            bossSpecies(zone, day),
            r.cleared ? 0 : (r.hpLeft == 0 ? BOSS_HP : r.hpLeft),
            BOSS_HP,
            r.pot,
            r.totalDamage,
            r.cleared,
            r.finisher,
            damageOf[id][player],
            claimed[id][player]
        );
    }

    function passDigest(Pass calldata p) external view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(PASS_TYPEHASH, p.player, p.zone, p.day, p.deadline)));
    }

    function _send(address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
