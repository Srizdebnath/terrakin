// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {BattleLib} from "./BattleLib.sol";

/// What territory needs from the game contract.
interface ITerrakin {
    function signer() external view returns (address);
    function kinPacked(uint256[] calldata ids) external view returns (address[] memory owners, uint256[] memory packed);
}

/// @title Terrakin Territory
/// @notice The real map as land. Hexes (~150 m across) are claimed by standing
/// in them, defended by up to three stationed Kin, and captured by beating
/// those Kin in an on-chain auto-battle. Owners take a cut of every catch
/// reward in their hex. Landmark zones go to a daily auction instead: the
/// winner takes a bigger cut of that day's Landmark catches.
///
/// Hex and zone ids are computed off-chain (identical integer math in the app
/// and the backend) and arrive signed by the game's voucher signer, so the
/// contract never does trigonometry.
///
/// Every MON paid here (claims, lost attack fees, winning bids) goes to the
/// game's reward pool.
contract TerrakinTerritory is EIP712, Ownable {
    // ------------------------------------------------------------------ types

    /// Server-signed proof that [player] stood inside [hexId].
    struct Presence {
        address player;
        uint64 hexId;
        uint64 deadline;
    }

    struct Prices {
        uint128 claim; // claiming an unowned hex
        uint128 attackFee; // paid to the defender if the defence holds
        uint128 minBid; // opening bid for a Landmark zone-day
        uint16 cutBps; // hex owner's share of catch rewards in the hex
        uint16 landmarkCutBps; // auction winner's share of Landmark catches
        uint16 bidStepBps; // each bid beats the last by at least this much
        uint32 shield; // seconds a hex is safe after it changes hands
        uint128 loopPerHex; // Loop Capture, per hex actually taken
    }

    struct Hex {
        address owner;
        uint40 since;
        uint40 shieldUntil;
    }

    struct Bid {
        address bidder;
        uint128 amount;
        bool settled;
    }

    bytes32 private constant PRESENCE_TYPEHASH = keccak256("Presence(address player,uint64 hexId,uint64 deadline)");
    bytes32 private constant LOOP_TYPEHASH = keccak256(
        "Loop(address player,uint64 startedAt,bytes32 trail,bytes32 inside,uint64 deadline)"
    );
    uint256 public constant MAX_SQUAD = 3;
    uint256 public constant MAX_LOOP = 160; // trail + inside hexes per loop

    // ------------------------------------------------------------------ state

    ITerrakin public immutable game;
    Prices internal _prices;

    mapping(uint64 => Hex) public hexes;
    mapping(uint64 => uint256[]) internal _defenders;
    mapping(uint256 => uint64) public stationedAt; // a Kin defends one hex at a time
    mapping(address => uint64[]) internal _owned;
    mapping(uint64 => uint256) internal _ownedIndex;
    mapping(uint64 => mapping(uint32 => Bid)) public bids; // zone => UTC day => top bid
    mapping(address => uint256) public refunds; // outbid MON, withdrawn by its owner
    bool public migrationClosed;

    // ----------------------------------------------------------------- events

    event HexClaimed(uint64 indexed hexId, address indexed owner);
    event DefendersSet(uint64 indexed hexId, uint256[] kin);
    event Battle(
        uint64 indexed hexId,
        address indexed attacker,
        address indexed defender,
        bool attackerWon,
        bytes32 seed,
        uint256[] attackers,
        uint256[] defenders
    );
    event BidPlaced(uint64 indexed zone, uint32 indexed day, address indexed bidder, uint256 amount);
    event AuctionSettled(uint64 indexed zone, uint32 indexed day, address winner, uint256 amount);
    event LoopClosed(address indexed player, uint256 trail, uint256 inside, uint64[] taken);

    // ----------------------------------------------------------------- errors

    error BadSignature();
    error Expired();
    error NotYours();
    error Owned();
    error Unowned();
    error Shielded();
    error WrongPayment();
    error BadSquad();
    error BadAuction();
    error BidTooLow();
    error TransferFailed();
    error Cut(uint64 hexId);
    error BadLoop();

    constructor(ITerrakin game_, Prices memory prices_) EIP712("Terrakin Territory", "2") Ownable(msg.sender) {
        game = game_;
        _prices = prices_;
    }

    // ---------------------------------------------------------------- hexes

    /// @notice Claims an unowned hex the player is standing in, stationing 1-3
    /// of their Kin as its defenders.
    function claim(Presence calldata p, bytes calldata sig, uint256[] calldata kin) external payable {
        _checkPresence(p, sig);
        Hex storage h = hexes[p.hexId];
        if (h.owner != address(0)) revert Owned();
        if (msg.value != _prices.claim) revert WrongPayment();
        _setOwner(p.hexId, h, msg.sender);
        _station(p.hexId, kin);
        _toPool(msg.value);
        emit HexClaimed(p.hexId, msg.sender);
    }

    /// @notice The owner swaps the hex's defenders (no need to be there).
    function station(uint64 hexId, uint256[] calldata kin) external {
        if (hexes[hexId].owner != msg.sender) revert NotYours();
        _station(hexId, kin);
    }

    /// @notice Challenges a hex the player is standing in. 1-3 of their Kin
    /// fight its defenders in a deterministic auto-battle seeded by the block.
    /// Win: the hex and the stationing pass to the attacker. Lose: the fee
    /// goes to the defender.
    function attack(Presence calldata p, bytes calldata sig, uint256[] calldata kin)
        external
        payable
        returns (bool won)
    {
        _checkPresence(p, sig);
        Hex storage h = hexes[p.hexId];
        address defender = h.owner;
        if (defender == address(0)) revert Unowned();
        if (defender == msg.sender) revert NotYours();
        if (block.timestamp < h.shieldUntil) revert Shielded();
        if (msg.value != _prices.attackFee) revert WrongPayment();
        if (kin.length == 0 || kin.length > MAX_SQUAD) revert BadSquad();

        uint256[] memory defIds = _defenders[p.hexId];
        uint256 n = kin.length;
        uint256[] memory all = new uint256[](n + defIds.length);
        for (uint256 i; i < n; ++i) all[i] = kin[i];
        for (uint256 i; i < defIds.length; ++i) all[n + i] = defIds[i];
        (address[] memory owners, uint256[] memory packed) = game.kinPacked(all);

        BattleLib.Fighter[] memory att = new BattleLib.Fighter[](n);
        for (uint256 i; i < n; ++i) {
            if (owners[i] != msg.sender) revert NotYours();
            for (uint256 j; j < i; ++j) if (kin[j] == kin[i]) revert BadSquad();
            att[i] = fighter(packed[i], false);
        }
        // Defenders traded away or moved since stationing don't fight.
        uint256 live;
        BattleLib.Fighter[] memory def = new BattleLib.Fighter[](defIds.length);
        uint256[] memory liveIds = new uint256[](defIds.length);
        for (uint256 i; i < defIds.length; ++i) {
            if (owners[n + i] == defender && stationedAt[defIds[i]] == p.hexId) {
                def[live] = fighter(packed[n + i], true);
                liveIds[live++] = defIds[i];
            }
        }
        assembly ("memory-safe") {
            mstore(def, live)
            mstore(liveIds, live)
        }

        bytes32 seed = keccak256(abi.encode(block.prevrandao, blockhash(block.number - 1), msg.sender, p.hexId));
        (won,,) = simulate(att, def, seed);

        if (won) {
            _setOwner(p.hexId, h, msg.sender);
            _station(p.hexId, kin);
            _toPool(msg.value);
        } else {
            (bool ok,) = defender.call{value: msg.value, gas: 10000}("");
            if (!ok) _toPool(msg.value);
        }
        emit Battle(p.hexId, msg.sender, defender, won, seed, kin, liveIds);
    }

    // ----------------------------------------------------------- loop capture

    /// @notice Loop Capture. The player walked a closed loop of adjacent hexes
    /// ([trail], first == last) starting at [startedAt]; the backend checked
    /// the walk and computed the hexes it encloses ([inside]). Free trail and
    /// inside hexes become the player's, and so do rivals' inside hexes that
    /// are neither shielded nor defended: they're surrounded. Defended hexes
    /// stay put. If a rival took any trail hex after the walk began, the loop
    /// was cut and nothing happens. Pays [Prices.loopPerHex] per hex taken;
    /// send enough for every listed hex and the rest is refunded.
    function claimLoop(
        uint64 startedAt,
        uint64 deadline,
        uint64[] calldata trail,
        uint64[] calldata inside,
        bytes calldata sig
    ) external payable returns (uint64[] memory taken) {
        if (block.timestamp > deadline) revert Expired();
        if (trail.length < 6 || inside.length == 0 || trail.length + inside.length > MAX_LOOP) revert BadLoop();
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    LOOP_TYPEHASH,
                    msg.sender,
                    startedAt,
                    keccak256(abi.encodePacked(trail)),
                    keccak256(abi.encodePacked(inside)),
                    deadline
                )
            )
        );
        if (ECDSA.recover(digest, sig) != game.signer()) revert BadSignature();

        for (uint256 i; i < trail.length; ++i) {
            Hex storage h = hexes[trail[i]];
            if (h.owner != address(0) && h.owner != msg.sender && h.since > startedAt) revert Cut(trail[i]);
        }

        taken = new uint64[](trail.length + inside.length);
        uint256 n;
        for (uint256 i; i < trail.length; ++i) {
            Hex storage h = hexes[trail[i]];
            if (h.owner == address(0)) {
                _setOwner(trail[i], h, msg.sender);
                taken[n++] = trail[i];
            }
        }
        for (uint256 i; i < inside.length; ++i) {
            uint64 id = inside[i];
            Hex storage h = hexes[id];
            address o = h.owner;
            if (o == msg.sender) continue;
            if (o != address(0) && (block.timestamp < h.shieldUntil || _liveDefenders(id, o) > 0)) continue;
            if (o != address(0)) _unstation(id);
            _setOwner(id, h, msg.sender);
            taken[n++] = id;
        }
        assembly ("memory-safe") {
            mstore(taken, n)
        }

        uint256 cost = n * _prices.loopPerHex;
        if (msg.value < cost) revert WrongPayment();
        _toPool(cost);
        if (msg.value > cost) {
            (bool ok,) = msg.sender.call{value: msg.value - cost}("");
            if (!ok) revert TransferFailed();
        }
        emit LoopClosed(msg.sender, trail.length, inside.length, taken);
    }

    function _liveDefenders(uint64 hexId, address owner) internal view returns (uint256 live) {
        uint256[] storage ds = _defenders[hexId];
        if (ds.length == 0) return 0;
        (address[] memory owners,) = game.kinPacked(ds);
        for (uint256 i; i < ds.length; ++i) {
            if (owners[i] == owner && stationedAt[ds[i]] == hexId) ++live;
        }
    }

    function _unstation(uint64 hexId) internal {
        uint256[] storage cur = _defenders[hexId];
        for (uint256 i; i < cur.length; ++i) {
            if (stationedAt[cur[i]] == hexId) delete stationedAt[cur[i]];
        }
        delete _defenders[hexId];
    }

    /// Battle stats of a packed Kin record; see BattleLib.fighter.
    function fighter(uint256 w, bool home) public pure returns (BattleLib.Fighter memory) {
        return BattleLib.fighter(w, home);
    }

    /// See BattleLib.simulate.
    function simulate(BattleLib.Fighter[] memory a, BattleLib.Fighter[] memory d, bytes32 seed)
        public
        pure
        returns (bool attackerWon, uint256 turns, uint256 hpLeft)
    {
        return BattleLib.simulate(a, d, seed);
    }

    function _station(uint64 hexId, uint256[] calldata kin) internal {
        if (kin.length == 0 || kin.length > MAX_SQUAD) revert BadSquad();
        (address[] memory owners,) = game.kinPacked(kin);
        uint256[] storage cur = _defenders[hexId];
        for (uint256 i; i < cur.length; ++i) {
            if (stationedAt[cur[i]] == hexId) delete stationedAt[cur[i]];
        }
        delete _defenders[hexId];
        for (uint256 i; i < kin.length; ++i) {
            if (owners[i] != msg.sender) revert NotYours();
            if (stationedAt[kin[i]] == hexId) revert BadSquad(); // duplicate
            stationedAt[kin[i]] = hexId;
            cur.push(kin[i]);
        }
        emit DefendersSet(hexId, kin);
    }

    function _setOwner(uint64 hexId, Hex storage h, address to) internal {
        address from = h.owner;
        if (from != address(0)) {
            uint64[] storage list = _owned[from];
            uint256 idx = _ownedIndex[hexId];
            uint64 last = list[list.length - 1];
            list[idx] = last;
            _ownedIndex[last] = idx;
            list.pop();
        }
        _ownedIndex[hexId] = _owned[to].length;
        _owned[to].push(hexId);
        h.owner = to;
        h.since = uint40(block.timestamp);
        h.shieldUntil = uint40(block.timestamp + _prices.shield);
    }

    function _checkPresence(Presence calldata p, bytes calldata sig) internal view {
        if (p.player != msg.sender) revert NotYours();
        if (block.timestamp > p.deadline) revert Expired();
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(PRESENCE_TYPEHASH, p.player, p.hexId, p.deadline)));
        if (ECDSA.recover(digest, sig) != game.signer()) revert BadSignature();
    }

    // -------------------------------------------------------------- auctions

    /// @notice Bids for a Landmark zone on tomorrow's UTC day. The previous top
    /// bidder's MON becomes withdrawable from [refunds].
    function bid(uint64 zone, uint32 day) external payable {
        if (zone == 0 || day != today() + 1) revert BadAuction();
        Bid storage b = bids[zone][day];
        uint256 floor = b.bidder == address(0)
            ? _prices.minBid
            : uint256(b.amount) * (10000 + _prices.bidStepBps) / 10000;
        if (msg.value < floor) revert BidTooLow();
        if (b.bidder != address(0)) refunds[b.bidder] += b.amount;
        b.bidder = msg.sender;
        b.amount = uint128(msg.value);
        emit BidPlaced(zone, day, msg.sender, msg.value);
    }

    /// @notice Sends a finished auction's winning bid to the reward pool.
    /// Anyone may call it once the day it was for has begun.
    function settle(uint64 zone, uint32 day) external {
        Bid storage b = bids[zone][day];
        if (day > today() || b.bidder == address(0) || b.settled) revert BadAuction();
        b.settled = true;
        _toPool(b.amount);
        emit AuctionSettled(zone, day, b.bidder, b.amount);
    }

    function withdrawRefund() external {
        uint256 amount = refunds[msg.sender];
        refunds[msg.sender] = 0;
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    function today() public view returns (uint32) {
        return uint32(block.timestamp / 1 days);
    }

    // ----------------------------------------------------------------- views

    /// Who takes the cut of a catch, and how much (Terrakin calls this).
    function landlord(uint64 hexId, uint64 zone, bool landmark) external view returns (address to, uint16 bps) {
        if (landmark && zone != 0) {
            Bid storage b = bids[zone][today()];
            if (b.bidder != address(0)) return (b.bidder, _prices.landmarkCutBps);
        }
        return (hexes[hexId].owner, _prices.cutBps);
    }

    function prices() external view returns (Prices memory) {
        return _prices;
    }

    function presenceDigest(Presence calldata p) external view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(PRESENCE_TYPEHASH, p.player, p.hexId, p.deadline)));
    }

    function defendersOf(uint64 hexId) external view returns (uint256[] memory) {
        return _defenders[hexId];
    }

    function hexesOf(address owner) external view returns (uint64[] memory) {
        return _owned[owner];
    }

    /// One call for the map: owner and shield of each hex in view.
    function hexStates(uint64[] calldata ids)
        external
        view
        returns (address[] memory owners, uint40[] memory shieldUntil, uint8[] memory defenders)
    {
        owners = new address[](ids.length);
        shieldUntil = new uint40[](ids.length);
        defenders = new uint8[](ids.length);
        for (uint256 i; i < ids.length; ++i) {
            Hex storage h = hexes[ids[i]];
            owners[i] = h.owner;
            shieldUntil[i] = h.shieldUntil;
            uint256[] storage ds = _defenders[ids[i]];
            for (uint256 k; k < ds.length; ++k) {
                if (stationedAt[ds[k]] == ids[i]) defenders[i]++;
            }
        }
    }

    // ----------------------------------------------------------------- admin

    /// @notice One-off copy of hex ownership and defenders from the previous
    /// territory contract. Locked for good by [closeMigration].
    function migrate(uint64[] calldata ids, address[] calldata owners, uint256[][] calldata defenders)
        external
        onlyOwner
    {
        if (migrationClosed) revert BadAuction();
        for (uint256 i; i < ids.length; ++i) {
            Hex storage h = hexes[ids[i]];
            if (h.owner != address(0)) continue;
            _setOwner(ids[i], h, owners[i]);
            h.shieldUntil = 0;
            uint256[] storage cur = _defenders[ids[i]];
            for (uint256 k; k < defenders[i].length; ++k) {
                if (stationedAt[defenders[i][k]] != 0) continue;
                stationedAt[defenders[i][k]] = ids[i];
                cur.push(defenders[i][k]);
            }
            emit HexClaimed(ids[i], owners[i]);
        }
    }

    function closeMigration() external onlyOwner {
        migrationClosed = true;
    }

    function loopDigest(address player, uint64 startedAt, uint64[] calldata trail, uint64[] calldata inside, uint64 deadline)
        external
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    LOOP_TYPEHASH,
                    player,
                    startedAt,
                    keccak256(abi.encodePacked(trail)),
                    keccak256(abi.encodePacked(inside)),
                    deadline
                )
            )
        );
    }

    function setPrices(Prices calldata p) external onlyOwner {
        _prices = p;
    }

    function _toPool(uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = address(game).call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
