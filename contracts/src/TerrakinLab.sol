// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {BattleLib} from "./BattleLib.sol";

/// What the Lab needs from the game contract (it is a registered module).
interface ITerrakinModules {
    function kinPacked(uint256[] calldata ids) external view returns (address[] memory owners, uint256[] memory packed);
    function moduleMint(address to, uint256 kinId, uint256 packed) external;
    function moduleBurn(uint256 kinId) external;
    function moduleSetKin(uint256 kinId, uint256 packed) external;
    function moduleGiveOrbs(address to, uint32[4] calldata qty) external;
}

/// @title Terrakin Lab
/// @notice The risky side of Terrakin, all settled on-chain with block
/// randomness:
/// - Fusion: burn two Kin, roll one. Usually the better parent's grade,
///   sometimes a grade up (jackpot), sometimes the worse one (dud).
/// - Re-roll: pay to re-roll a Kin's four hidden vigor stats, 0-15 each.
/// - Orb packs: a handful of random orbs, with a small chance of Crown Orbs.
/// - Duels: stake MON on a 1-3 Kin auto-battle against anyone, anywhere.
///   Winner takes the pot minus a house fee.
///
/// Fees and house cuts go to the game's reward pool. Randomness mixes the
/// block's prevrandao with a per-player nonce (no shared counter, so players'
/// transactions stay parallel on Monad).
contract TerrakinLab is Ownable {
    struct Prices {
        uint128 fuse;
        uint128 reroll;
        uint128 pack;
        uint128 minStake;
        uint16 duelFeeBps;
        uint8 jackpotPct; // fusion: chance of a grade up
        uint8 dudPct; // fusion: chance of the worse parent's grade
        uint8 packSize;
    }

    struct Duel {
        address creator;
        uint128 stake;
        uint40 created;
        uint256[] kin;
    }

    enum Fusion {
        Dud,
        Normal,
        Jackpot
    }

    ITerrakinModules public immutable game;
    Prices internal _prices;

    mapping(address => uint256) internal _nonce;
    mapping(uint256 => Duel) internal _duels;
    uint256[] internal _open;
    mapping(uint256 => uint256) internal _openIndex;
    mapping(address => uint256) public winnings; // payouts a push couldn't deliver
    mapping(address => uint32) public duelWins;
    mapping(address => uint32) public duelLosses;

    event Fused(address indexed player, uint256 a, uint256 b, uint256 indexed kinId, Fusion outcome, uint8 grade);
    event Rerolled(address indexed player, uint256 indexed kinId, uint32 oldVigor, uint32 newVigor);
    event PackOpened(address indexed player, uint32[4] orbs);
    event DuelCreated(uint256 indexed id, address indexed creator, uint256 stake, uint256[] kin);
    event DuelCancelled(uint256 indexed id);
    event DuelSettled(
        uint256 indexed id,
        address indexed winner,
        address indexed loser,
        uint256 payout,
        bytes32 seed,
        bool creatorAttacked,
        uint256[] creatorKin,
        uint256[] acceptorKin
    );

    error NotYours();
    error WrongPayment();
    error BadSquad();
    error NoDuel();
    error StaleDuel();
    error TransferFailed();

    constructor(ITerrakinModules game_, Prices memory prices_) Ownable(msg.sender) {
        game = game_;
        _prices = prices_;
    }

    // ----------------------------------------------------------------- fusion

    function fuse(uint256 a, uint256 b) external payable returns (uint256 kinId, Fusion outcome) {
        if (msg.value != _prices.fuse) revert WrongPayment();
        if (a == b) revert BadSquad();
        uint256[] memory ids = new uint256[](2);
        ids[0] = a;
        ids[1] = b;
        (address[] memory owners, uint256[] memory w) = game.kinPacked(ids);
        if (owners[0] != msg.sender || owners[1] != msg.sender) revert NotYours();

        uint256 r = _rand();
        uint256 ga = uint8(w[0] >> 8);
        uint256 gb = uint8(w[1] >> 8);
        uint256 hi = ga > gb ? ga : gb;
        uint256 roll = r % 100;
        uint256 grade;
        if (roll < _prices.jackpotPct) {
            outcome = Fusion.Jackpot;
            grade = hi < 4 ? hi + 1 : 4;
        } else if (roll >= 100 - _prices.dudPct) {
            outcome = Fusion.Dud;
            grade = ga < gb ? ga : gb;
        } else {
            outcome = Fusion.Normal;
            grade = hi;
        }

        // Species and trait from a random parent; each vigor stat lands
        // between the parents' with a -3..+3 mutation (+2 more on a jackpot);
        // trade multipliers average out.
        uint256 out = (r >> 8 & 1 == 0 ? w[0] : w[1]) & 0xff; // species
        out |= grade << 8;
        out |= (r >> 9 & 1 == 0 ? w[0] : w[1]) & (0xff << 16); // trait
        out |= block.timestamp << 48;
        out |= w[0] & (uint256(type(uint64).max) << 88); // origin lat, lng of parent a
        for (uint256 i; i < 4; ++i) {
            uint256 va = uint8(w[0] >> (152 + 8 * i));
            uint256 vb = uint8(w[1] >> (152 + 8 * i));
            (uint256 lo, uint256 top) = va < vb ? (va, vb) : (vb, va);
            uint256 bits = r >> (16 + 16 * i);
            int256 v = int256(lo + bits % (top - lo + 1)) + int256((bits >> 8) % 7) - 3;
            if (outcome == Fusion.Jackpot) v += 2;
            if (v < 0) v = 0;
            if (v > 15) v = 15;
            out |= uint256(v) << (152 + 8 * i);
            uint256 ma = uint16(w[0] >> (184 + 16 * i));
            uint256 mb = uint16(w[1] >> (184 + 16 * i));
            out |= ((ma + mb) / 2) << (184 + 16 * i);
        }

        game.moduleBurn(a);
        game.moduleBurn(b);
        kinId = uint256(keccak256(abi.encode(msg.sender, a, b, "fuse")));
        game.moduleMint(msg.sender, kinId, out);
        _toPool(msg.value);
        emit Fused(msg.sender, a, b, kinId, outcome, uint8(grade));
    }

    // ---------------------------------------------------------------- re-roll

    function reroll(uint256 kinId) external payable returns (uint32 newVigor) {
        if (msg.value != _prices.reroll) revert WrongPayment();
        uint256[] memory ids = new uint256[](1);
        ids[0] = kinId;
        (address[] memory owners, uint256[] memory w) = game.kinPacked(ids);
        if (owners[0] != msg.sender) revert NotYours();
        uint256 r = _rand();
        uint256 packed = w[0];
        uint32 oldVigor = uint32(packed >> 152);
        for (uint256 i; i < 4; ++i) {
            uint256 v = (r >> (8 * i)) % 16;
            packed = packed & ~(uint256(0xff) << (152 + 8 * i)) | v << (152 + 8 * i);
        }
        newVigor = uint32(packed >> 152);
        game.moduleSetKin(kinId, packed);
        _toPool(msg.value);
        emit Rerolled(msg.sender, kinId, oldVigor, newVigor);
    }

    // ------------------------------------------------------------------ packs

    /// Each orb: 2% Crown, 8% Aurora, 20% Bloom, 70% Seed.
    function openPack() external payable returns (uint32[4] memory orbs) {
        if (msg.value != _prices.pack) revert WrongPayment();
        uint256 r = _rand();
        for (uint256 i; i < _prices.packSize; ++i) {
            uint256 roll = (r >> (16 * i)) % 1000;
            orbs[roll < 20 ? 3 : roll < 100 ? 2 : roll < 300 ? 1 : 0]++;
        }
        game.moduleGiveOrbs(msg.sender, orbs);
        _toPool(msg.value);
        emit PackOpened(msg.sender, orbs);
    }

    // ------------------------------------------------------------------ duels

    /// Opens a challenge anyone can take by matching [msg.value].
    function createDuel(uint256[] calldata kin) external payable returns (uint256 id) {
        if (msg.value < _prices.minStake) revert WrongPayment();
        _checkSquad(kin, msg.sender);
        id = uint256(keccak256(abi.encode(msg.sender, _nonce[msg.sender]++, "duel")));
        Duel storage d = _duels[id];
        d.creator = msg.sender;
        d.stake = uint128(msg.value);
        d.created = uint40(block.timestamp);
        d.kin = kin;
        _openIndex[id] = _open.length;
        _open.push(id);
        emit DuelCreated(id, msg.sender, msg.value, kin);
    }

    function cancelDuel(uint256 id) external {
        Duel storage d = _duels[id];
        if (d.creator != msg.sender) revert NoDuel();
        uint256 stake = d.stake;
        _close(id);
        _send(msg.sender, stake);
        emit DuelCancelled(id);
    }

    /// Takes a challenge: both squads fight (who attacks is a coin flip),
    /// the winner gets both stakes minus the house fee.
    function acceptDuel(uint256 id, uint256[] calldata kin) external payable returns (bool acceptorWon) {
        Duel storage d = _duels[id];
        address creator = d.creator;
        if (creator == address(0)) revert NoDuel();
        if (creator == msg.sender) revert NotYours();
        if (msg.value != d.stake) revert WrongPayment();
        uint256[] memory theirs = d.kin;
        uint256 n = kin.length;
        if (n == 0 || n > 3) revert BadSquad();

        uint256[] memory all = new uint256[](n + theirs.length);
        for (uint256 i; i < n; ++i) all[i] = kin[i];
        for (uint256 i; i < theirs.length; ++i) all[n + i] = theirs[i];
        (address[] memory owners, uint256[] memory w) = game.kinPacked(all);
        BattleLib.Fighter[] memory mine = new BattleLib.Fighter[](n);
        BattleLib.Fighter[] memory other = new BattleLib.Fighter[](theirs.length);
        for (uint256 i; i < n; ++i) {
            if (owners[i] != msg.sender) revert NotYours();
            for (uint256 j; j < i; ++j) if (kin[j] == kin[i]) revert BadSquad();
            mine[i] = BattleLib.fighter(w[i], false);
        }
        for (uint256 i; i < theirs.length; ++i) {
            if (owners[n + i] != creator) revert StaleDuel(); // creator traded a Kin away; they can cancel
            other[i] = BattleLib.fighter(w[n + i], false);
        }

        bytes32 seed = bytes32(_rand());
        bool creatorAttacked = uint256(seed) >> 255 == 1;
        (bool attackerWon,,) =
            creatorAttacked ? BattleLib.simulate(other, mine, seed) : BattleLib.simulate(mine, other, seed);
        acceptorWon = creatorAttacked ? !attackerWon : attackerWon;

        uint256 pot = uint256(d.stake) * 2;
        uint256 fee = pot * _prices.duelFeeBps / 10000;
        address winner = acceptorWon ? msg.sender : creator;
        duelWins[winner]++;
        duelLosses[acceptorWon ? creator : msg.sender]++;
        _close(id);
        _toPool(fee);
        _send(winner, pot - fee);
        emit DuelSettled(id, winner, acceptorWon ? creator : msg.sender, pot - fee, seed, creatorAttacked, theirs, kin);
    }

    function withdrawWinnings() external {
        uint256 amount = winnings[msg.sender];
        winnings[msg.sender] = 0;
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    // ------------------------------------------------------------------ views

    function prices() external view returns (Prices memory) {
        return _prices;
    }

    /// Open challenges, newest last.
    function openDuels()
        external
        view
        returns (uint256[] memory ids, address[] memory creators, uint256[] memory stakes, uint256[] memory squadSizes)
    {
        uint256 n = _open.length;
        ids = new uint256[](n);
        creators = new address[](n);
        stakes = new uint256[](n);
        squadSizes = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            Duel storage d = _duels[_open[i]];
            ids[i] = _open[i];
            creators[i] = d.creator;
            stakes[i] = d.stake;
            squadSizes[i] = d.kin.length;
        }
    }

    function duelKin(uint256 id) external view returns (uint256[] memory) {
        return _duels[id].kin;
    }

    // ------------------------------------------------------------------ admin

    function setPrices(Prices calldata p) external onlyOwner {
        _prices = p;
    }

    // -------------------------------------------------------------- internals

    function _rand() internal returns (uint256) {
        return uint256(keccak256(abi.encode(block.prevrandao, blockhash(block.number - 1), msg.sender, _nonce[msg.sender]++)));
    }

    function _checkSquad(uint256[] calldata kin, address owner) internal view {
        if (kin.length == 0 || kin.length > 3) revert BadSquad();
        (address[] memory owners,) = game.kinPacked(kin);
        for (uint256 i; i < kin.length; ++i) {
            if (owners[i] != owner) revert NotYours();
            for (uint256 j; j < i; ++j) if (kin[j] == kin[i]) revert BadSquad();
        }
    }

    function _close(uint256 id) internal {
        uint256 idx = _openIndex[id];
        uint256 last = _open[_open.length - 1];
        _open[idx] = last;
        _openIndex[last] = idx;
        _open.pop();
        delete _openIndex[id];
        delete _duels[id];
    }

    function _send(address to, uint256 amount) internal {
        (bool ok,) = to.call{value: amount, gas: 30000}("");
        if (!ok) winnings[to] += amount;
    }

    function _toPool(uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = address(game).call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
