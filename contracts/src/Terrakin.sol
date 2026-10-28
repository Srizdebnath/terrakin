// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {OwnerIndexed} from "./OwnerIndexed.sol";
import {TerrakinCharacters} from "./TerrakinCharacters.sol";

/// What Terrakin needs from the territory contract when paying a catch.
interface ITerritory {
    function landlord(uint64 hexId, uint64 zone, bool landmark) external view returns (address to, uint16 bps);
}

/// @title Terrakin
/// @notice Game core on Monad: player names (IGN), the starter grant, orbs,
/// Kin (this contract is the Kin NFT collection), bonding and trading.
/// Territory (hexes, battles, Landmark auctions) lives in TerrakinTerritory.
///
/// Monad notes:
/// - Every player's state lives in slots keyed by their address and Kin ids
///   are hashes, not a shared counter, so different players' transactions
///   don't conflict and run in parallel.
/// - Fast finality lets the app treat a receipt (~1 s) as final.
contract Terrakin is OwnerIndexed, EIP712, Ownable {
    // ------------------------------------------------------------------ types

    struct Kin {
        uint8 species; // index into the app's species table
        uint8 grade; // 0 Common .. 4 Mythic
        uint8 trait;
        bool landmark;
        uint16 trades;
        uint40 bondedAt;
        int32 lat; // origin, micro-degrees
        int32 lng;
        uint8[4] vigor; // hp, atk, def, spd, each 0..15
        uint16[4] mods; // trade multipliers in basis points, 7000..13000
    }

    /// Server-signed proof that a spawn exists where and when the player bonded it.
    struct Bond {
        address player;
        bytes32 spawnId;
        uint8 species;
        uint8 grade;
        uint32 vigor; // 4 x 8 bits: hp | atk << 8 | def << 16 | spd << 24
        uint8 trait;
        bool landmark;
        int32 lat;
        int32 lng;
        uint64 hexId; // territory hex of the spawn (see hexgrid in the app/backend)
        uint64 zone; // Landmark zone, 0 for other Kin
        uint64 deadline;
    }

    struct Trade {
        address a;
        address b;
        uint256 kinA;
        uint256 kinB;
        uint64 expires;
    }

    struct Prices {
        uint128 grant; // MON sent to each new player
        uint128 firstCharacter;
        uint128 nextCharacter;
        uint128 tradeReward;
        uint128[4] orb; // seed, bloom, aurora, crown
        uint128[5] catchReward; // by grade; Landmarks pay double
        uint32 starterOrbs; // Seed Orbs in the welcome pack
        uint32 rewardedTradesPerDay;
    }

    bytes32 private constant BOND_TYPEHASH = keccak256(
        "Bond(address player,bytes32 spawnId,uint8 species,uint8 grade,uint32 vigor,uint8 trait,bool landmark,int32 lat,int32 lng,uint64 hexId,uint64 zone,uint64 deadline)"
    );
    uint16 private constant MOD_ONE = 10000;
    uint16 private constant MOD_FLOOR = 7000;
    uint16 private constant MOD_CEIL = 13000;
    uint16 private constant TRADE_SWING = 1500; // +-15%
    uint64 private constant TRADE_TTL = 10 minutes;

    // ------------------------------------------------------------------ state

    TerrakinCharacters public characters;
    ITerritory public territory;
    /// Side contracts (the Lab, and later the market, raids...) allowed to
    /// mint, burn and edit Kin and grant orbs, so new features ship without
    /// redeploying this contract.
    mapping(address => bool) public modules;
    address public signer;
    Prices internal _prices;

    mapping(bytes32 => address) public nameOwner; // lower-cased name hash
    mapping(address => string) public nameOf;
    mapping(address => bool) public funded;
    mapping(address => uint256) public charactersMinted;
    mapping(address => uint32[4]) internal _orbs;
    /// Each Kin packed into one slot (one SSTORE per bond, which matters when
    /// players pay gas): species 8 | grade 8 | trait 8 | landmark 8 | trades 16 |
    /// bondedAt 40 | lat 32 | lng 32 | vigor 4x8 | mods 4x16.
    mapping(uint256 => uint256) internal _kin;
    mapping(bytes32 => Trade) public trades;
    mapping(address => uint256) internal _tradeDay; // day << 8 | rewarded count

    // ----------------------------------------------------------------- events

    event Funded(address indexed player, uint256 amount, uint32 orbs);
    event ProfileCreated(address indexed player, string name, uint256 characterId, uint8 style);
    event CharacterMinted(address indexed player, uint256 characterId, uint8 style);
    event OrbsBought(address indexed player, uint8 orb, uint32 qty);
    event Bonded(address indexed player, uint256 indexed kinId, bytes32 spawnId, uint8 species, uint8 grade, uint256 reward);
    event TradeProposed(bytes32 indexed id, address indexed a, address indexed b, uint256 kinA, uint256 kinB);
    event Traded(bytes32 indexed id, address indexed a, address indexed b, uint256 kinA, uint256 kinB);
    event TradeCancelled(bytes32 indexed id);
    event ModuleSet(address indexed module, bool enabled);
    event HexCut(uint64 indexed hexId, address indexed to, uint256 amount);

    // ----------------------------------------------------------------- errors

    error NotSigner();
    error AlreadyFunded();
    error BadName();
    error NameTaken();
    error HasProfile();
    error NoProfile();
    error WrongPayment();
    error BadOrb();
    error NoOrbs();
    error Expired();
    error BadSignature();
    error AlreadyBonded();
    error NotYours();
    error NoTrade();
    error TransferFailed();

    constructor(address signer_, Prices memory prices_)
        ERC721("Terrakin Kin", "KIN")
        EIP712("Terrakin", "1")
        Ownable(msg.sender)
    {
        signer = signer_;
        _prices = prices_;
    }

    /// One-time link to the character collection (deployed separately so this
    /// contract stays under the 24 KB size limit).
    function setCharacters(TerrakinCharacters c) external onlyOwner {
        if (address(characters) != address(0) || c.game() != address(this)) revert NotYours();
        characters = c;
    }

    /// Link to the territory contract (separate for the same reason);
    /// replaceable so territory rules can be upgraded.
    function setTerritory(ITerritory t) external onlyOwner {
        territory = t;
    }

    function setModule(address m, bool enabled) external onlyOwner {
        modules[m] = enabled;
        emit ModuleSet(m, enabled);
    }

    // ---------------------------------------------------------------- modules

    modifier onlyModule() {
        if (!modules[msg.sender]) revert NotYours();
        _;
    }

    /// Mints a Kin with a given packed record (see _pack).
    function moduleMint(address to, uint256 kinId, uint256 packed) external onlyModule {
        if (_ownerOf(kinId) != address(0)) revert AlreadyBonded();
        _kin[kinId] = packed;
        _mint(to, kinId);
    }

    function moduleBurn(uint256 kinId) external onlyModule {
        delete _kin[kinId];
        _burn(kinId);
    }

    function moduleSetKin(uint256 kinId, uint256 packed) external onlyModule {
        if (_ownerOf(kinId) == address(0)) revert NotYours();
        _kin[kinId] = packed;
    }

    function moduleGiveOrbs(address to, uint32[4] calldata qty) external onlyModule {
        uint32[4] storage bag = _orbs[to];
        for (uint256 i; i < 4; ++i) bag[i] += qty[i];
    }

    receive() external payable {}

    // ------------------------------------------------------------- onboarding

    /// @notice Sends the starter grant and welcome orbs to a new player. Called
    /// by the backend after it has verified the player's Privy login.
    function fund(address player) external {
        if (msg.sender != signer) revert NotSigner();
        if (funded[player]) revert AlreadyFunded();
        funded[player] = true;
        _orbs[player][0] += _prices.starterOrbs;
        _pay(player, _prices.grant);
        emit Funded(player, _prices.grant, _prices.starterOrbs);
    }

    /// @notice Claims a unique in-game name (4-8 of a-z, 0-9, _; case-insensitive)
    /// and mints the first character, in one transaction.
    function createProfile(string calldata name, uint8 style) external payable returns (uint256 characterId) {
        if (bytes(nameOf[msg.sender]).length != 0) revert HasProfile();
        if (msg.value != _prices.firstCharacter) revert WrongPayment();
        bytes32 key = nameKey(name);
        if (nameOwner[key] != address(0)) revert NameTaken();
        nameOwner[key] = msg.sender;
        nameOf[msg.sender] = name;
        characterId = characters.mint(msg.sender, style, charactersMinted[msg.sender]++);
        emit ProfileCreated(msg.sender, name, characterId, style);
    }

    function mintCharacter(uint8 style) external payable returns (uint256 characterId) {
        if (bytes(nameOf[msg.sender]).length == 0) revert NoProfile();
        if (msg.value != _prices.nextCharacter) revert WrongPayment();
        characterId = characters.mint(msg.sender, style, charactersMinted[msg.sender]++);
        emit CharacterMinted(msg.sender, characterId, style);
    }

    /// Lower-cased hash of a valid name; reverts on invalid names.
    function nameKey(string calldata name) public pure returns (bytes32) {
        bytes memory b = bytes(name);
        if (b.length < 4 || b.length > 8) revert BadName();
        for (uint256 i; i < b.length; ++i) {
            bytes1 c = b[i];
            if (c >= "A" && c <= "Z") {
                b[i] = bytes1(uint8(c) + 32);
            } else if (!((c >= "a" && c <= "z") || (c >= "0" && c <= "9") || c == "_")) {
                revert BadName();
            }
        }
        return keccak256(b);
    }

    function isNameFree(string calldata name) external view returns (bool) {
        return nameOwner[nameKey(name)] == address(0);
    }

    // ------------------------------------------------------------------ orbs

    function buyOrbs(uint8 orb, uint32 qty) external payable {
        if (orb > 3 || qty == 0) revert BadOrb();
        if (msg.value != uint256(_prices.orb[orb]) * qty) revert WrongPayment();
        _orbs[msg.sender][orb] += qty;
        emit OrbsBought(msg.sender, orb, qty);
    }

    // --------------------------------------------------------------- bonding

    /// @notice Bonds a Kin. [orbsUsed] are the orbs thrown during the encounter
    /// (at least one); they are burned. Pays the catch reward from the pool.
    function bond(Bond calldata v, bytes calldata sig, uint32[4] calldata orbsUsed) external returns (uint256 kinId) {
        if (v.player != msg.sender) revert NotYours();
        if (block.timestamp > v.deadline) revert Expired();
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    BOND_TYPEHASH, v.player, v.spawnId, v.species, v.grade, v.vigor, v.trait, v.landmark, v.lat, v.lng, v.hexId, v.zone, v.deadline
                )
            )
        );
        if (ECDSA.recover(digest, sig) != signer) revert BadSignature();

        uint32 thrown;
        uint32[4] storage bag = _orbs[msg.sender];
        for (uint256 i; i < 4; ++i) {
            if (bag[i] < orbsUsed[i]) revert NoOrbs();
            bag[i] -= orbsUsed[i];
            thrown += orbsUsed[i];
        }
        if (thrown == 0) revert NoOrbs();

        kinId = uint256(keccak256(abi.encode(msg.sender, v.spawnId)));
        if (_ownerOf(kinId) != address(0)) revert AlreadyBonded();
        _kin[kinId] = _pack(
            Kin({
                species: v.species,
                grade: v.grade,
                trait: v.trait,
                landmark: v.landmark,
                trades: 0,
                bondedAt: uint40(block.timestamp),
                lat: v.lat,
                lng: v.lng,
                vigor: [uint8(v.vigor), uint8(v.vigor >> 8), uint8(v.vigor >> 16), uint8(v.vigor >> 24)],
                mods: [MOD_ONE, MOD_ONE, MOD_ONE, MOD_ONE]
            })
        );
        _mint(msg.sender, kinId);

        uint256 reward = uint256(_prices.catchReward[v.grade]) * (v.landmark ? 2 : 1);
        reward = _payCut(v, reward);
        reward = _pay(msg.sender, reward);
        emit Bonded(msg.sender, kinId, v.spawnId, v.species, v.grade, reward);
    }

    /// The hex owner (or the Landmark zone's auction winner for today) takes
    /// a cut of the catch reward. Pushed with a gas cap and skipped if it
    /// fails, so a hostile owner can never block catches.
    function _payCut(Bond calldata v, uint256 reward) internal returns (uint256) {
        if (address(territory) == address(0) || reward == 0 || reward > address(this).balance) return reward;
        (address to, uint16 bps) = territory.landlord(v.hexId, v.zone, v.landmark);
        if (to == address(0) || to == msg.sender) return reward;
        uint256 cut = reward * bps / 10000;
        if (cut == 0) return reward;
        (bool ok,) = to.call{value: cut, gas: 10000}("");
        if (!ok) return reward;
        emit HexCut(v.hexId, to, cut);
        return reward - cut;
    }

    // --------------------------------------------------------------- trading

    /// @notice Step 1: offer [myKin] for [theirKin] owned by [partner]. Nothing
    /// moves until the partner accepts within 10 minutes.
    function proposeTrade(uint256 myKin, uint256 theirKin, address partner) external returns (bytes32 id) {
        if (ownerOf(myKin) != msg.sender || ownerOf(theirKin) != partner || partner == msg.sender) revert NotYours();
        id = keccak256(abi.encode(msg.sender, partner, myKin, theirKin, block.number));
        trades[id] = Trade(msg.sender, partner, myKin, theirKin, uint64(block.timestamp) + TRADE_TTL);
        emit TradeProposed(id, msg.sender, partner, myKin, theirKin);
    }

    /// @notice Step 2: the partner accepts. Both Kin swap atomically and each
    /// one's HP/ATK/DEF/SPD shifts by up to +-15% (kept within -30%..+30%).
    function acceptTrade(bytes32 id) external {
        Trade memory t = trades[id];
        if (t.b != msg.sender) revert NoTrade();
        if (block.timestamp > t.expires) revert Expired();
        if (ownerOf(t.kinA) != t.a || ownerOf(t.kinB) != t.b) revert NotYours();
        delete trades[id];

        bytes32 seed = keccak256(abi.encode(id, block.prevrandao, blockhash(block.number - 1)));
        _shift(t.kinA, seed);
        _shift(t.kinB, seed);
        _transfer(t.a, t.b, t.kinA);
        _transfer(t.b, t.a, t.kinB);
        _rewardTrade(t.a);
        _rewardTrade(t.b);
        emit Traded(id, t.a, t.b, t.kinA, t.kinB);
    }

    function cancelTrade(bytes32 id) external {
        if (trades[id].a != msg.sender) revert NoTrade();
        delete trades[id];
        emit TradeCancelled(id);
    }

    function _shift(uint256 kinId, bytes32 seed) internal {
        Kin memory k = _unpack(_kin[kinId]);
        k.trades += 1;
        for (uint256 i; i < 4; ++i) {
            int256 r = int256(uint256(keccak256(abi.encode(seed, kinId, i))) % (2 * TRADE_SWING + 1)) - int256(uint256(TRADE_SWING));
            int256 m = int256(uint256(k.mods[i])) * (int256(uint256(MOD_ONE)) + r) / int256(uint256(MOD_ONE));
            if (m < int256(uint256(MOD_FLOOR))) m = int256(uint256(MOD_FLOOR));
            if (m > int256(uint256(MOD_CEIL))) m = int256(uint256(MOD_CEIL));
            k.mods[i] = uint16(uint256(m));
        }
        _kin[kinId] = _pack(k);
    }

    function _pack(Kin memory k) internal pure returns (uint256 w) {
        w = uint256(k.species) | uint256(k.grade) << 8 | uint256(k.trait) << 16 | uint256(k.landmark ? 1 : 0) << 24
            | uint256(k.trades) << 32 | uint256(k.bondedAt) << 48 | uint256(uint32(k.lat)) << 88
            | uint256(uint32(k.lng)) << 120;
        for (uint256 i; i < 4; ++i) {
            w |= uint256(k.vigor[i]) << (152 + 8 * i);
            w |= uint256(k.mods[i]) << (184 + 16 * i);
        }
    }

    function _unpack(uint256 w) internal pure returns (Kin memory k) {
        k.species = uint8(w);
        k.grade = uint8(w >> 8);
        k.trait = uint8(w >> 16);
        k.landmark = uint8(w >> 24) != 0;
        k.trades = uint16(w >> 32);
        k.bondedAt = uint40(w >> 48);
        k.lat = int32(uint32(w >> 88));
        k.lng = int32(uint32(w >> 120));
        for (uint256 i; i < 4; ++i) {
            k.vigor[i] = uint8(w >> (152 + 8 * i));
            k.mods[i] = uint16(w >> (184 + 16 * i));
        }
    }

    function _rewardTrade(address p) internal {
        uint256 day = block.timestamp / 1 days;
        uint256 packed = _tradeDay[p];
        uint256 count = packed >> 8 == day ? packed & 0xff : 0;
        if (count >= _prices.rewardedTradesPerDay) return;
        _tradeDay[p] = (day << 8) | (count + 1);
        _pay(p, _prices.tradeReward);
    }

    // ----------------------------------------------------------------- views

    function prices() external view returns (Prices memory) {
        return _prices;
    }

    function orbsOf(address p) external view returns (uint32[4] memory) {
        return _orbs[p];
    }

    function kin(uint256 id) external view returns (Kin memory) {
        return _unpack(_kin[id]);
    }

    /// One call for the app: every Kin a wallet holds.
    function kinOf(address owner) external view returns (uint256[] memory ids, Kin[] memory data) {
        uint256 n = balanceOf(owner);
        ids = new uint256[](n);
        data = new Kin[](n);
        for (uint256 i; i < n; ++i) {
            ids[i] = tokenOfOwnerByIndex(owner, i);
            data[i] = _unpack(_kin[ids[i]]);
        }
    }

    /// One call for the app: the whole player record.
    function playerOf(address p)
        external
        view
        returns (string memory name, bool isFunded, uint32[4] memory orbs, uint256 kinCount, uint256 characterCount)
    {
        return (nameOf[p], funded[p], _orbs[p], balanceOf(p), characters.balanceOf(p));
    }

    /// For battles: owner and packed record of each Kin (zero owner if none).
    function kinPacked(uint256[] calldata ids) external view returns (address[] memory owners, uint256[] memory packed) {
        owners = new address[](ids.length);
        packed = new uint256[](ids.length);
        for (uint256 i; i < ids.length; ++i) {
            owners[i] = _ownerOf(ids[i]);
            packed[i] = _kin[ids[i]];
        }
    }

    function bondDigest(Bond calldata v) external view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    BOND_TYPEHASH, v.player, v.spawnId, v.species, v.grade, v.vigor, v.trait, v.landmark, v.lat, v.lng, v.hexId, v.zone, v.deadline
                )
            )
        );
    }

    // ----------------------------------------------------------------- admin

    function setSigner(address s) external onlyOwner {
        signer = s;
    }

    function setPrices(Prices calldata p) external onlyOwner {
        _prices = p;
    }

    function withdraw(address to, uint256 amount) external onlyOwner {
        _pay(to, amount);
    }

    /// Pays out from the pool; pays what it can rather than blocking gameplay.
    function _pay(address to, uint256 amount) internal returns (uint256 paid) {
        paid = amount > address(this).balance ? address(this).balance : amount;
        if (paid == 0) return 0;
        (bool ok,) = to.call{value: paid}("");
        if (!ok) revert TransferFailed();
    }
}
