// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface ISeasonGame {
    function signer() external view returns (address);
    function nameOf(address) external view returns (string memory);
    function balanceOf(address) external view returns (uint256);
}

interface ISeasonTerritory {
    function hexesOf(address) external view returns (uint64[] memory);
}

interface ISeasonLab {
    function duelWins(address) external view returns (uint32);
}

interface ISeasonCrews {
    function crewOf(address) external view returns (uint256);
}

/// @title Terrakin Seasons
/// @notice Seasons with a capped, numbered supply of Mythics per species, and
/// the player registry the leaderboards read.
///
/// Every bond needs a voucher from the game's signer. Before signing a Mythic
/// voucher the signer reserves a numbered slot here ("Mythic Glyphlet
/// #3/100"); once a species sells out for the season, the backend signs that
/// Kin as Epic instead. The counts are public, so anyone can check the cap.
contract TerrakinSeason is Ownable {
    ISeasonGame public immutable game;
    ISeasonTerritory public territory;
    ISeasonLab public lab;
    ISeasonCrews public crews;

    uint32 public season;
    uint40 public startedAt;
    uint40 public endsAt;
    uint16 public mythicCap; // per species per season

    mapping(uint32 => uint16[7]) internal _minted; // season => count by species
    mapping(uint32 => mapping(address => uint16)) public mythicsOf;
    mapping(bytes32 => uint16) public serialOf; // keccak(season, player, spawnId) => serial, 0 = none

    address[] internal _players;
    mapping(address => bool) public enrolled;

    event SeasonStarted(uint32 indexed season, uint40 endsAt, uint16 mythicCap);
    event MythicReserved(uint32 indexed season, uint8 indexed species, address indexed player, uint16 serial);
    event Enrolled(address indexed player);

    error NotSigner();
    error SoldOut();
    error SeasonOver();
    error BadSpecies();

    constructor(ISeasonGame game_) Ownable(msg.sender) {
        game = game_;
    }

    modifier onlySigner() {
        if (msg.sender != game.signer()) revert NotSigner();
        _;
    }

    // ---------------------------------------------------------------- seasons

    function startSeason(uint40 endsAt_, uint16 cap) external onlyOwner {
        season++;
        startedAt = uint40(block.timestamp);
        endsAt = endsAt_;
        mythicCap = cap;
        emit SeasonStarted(season, endsAt_, cap);
    }

    /// Reserves the next numbered Mythic of [species] for [player]'s spawn.
    /// Idempotent per spawn, so a retried voucher keeps its number.
    function reserveMythic(address player, uint8 species, bytes32 spawnId) external onlySigner returns (uint16 serial) {
        if (species >= 7) revert BadSpecies();
        if (block.timestamp > endsAt) revert SeasonOver();
        bytes32 key = keccak256(abi.encode(season, player, spawnId));
        serial = serialOf[key];
        if (serial != 0) return serial;
        uint16[7] storage minted = _minted[season];
        if (minted[species] >= mythicCap) revert SoldOut();
        serial = ++minted[species];
        serialOf[key] = serial;
        mythicsOf[season][player]++;
        emit MythicReserved(season, species, player, serial);
    }

    /// The app's season banner: count by species, cap and dates.
    function mythicCounts()
        external
        view
        returns (uint32 s, uint16[7] memory minted, uint16 cap, uint40 started, uint40 ends)
    {
        return (season, _minted[season], mythicCap, startedAt, endsAt);
    }

    // ------------------------------------------------------------- registry

    function enroll() external {
        _enroll(msg.sender);
    }

    /// The backend enrols players at signup, so joining costs them nothing.
    function enrollFor(address player) external onlySigner {
        _enroll(player);
    }

    function _enroll(address p) internal {
        if (enrolled[p]) return;
        enrolled[p] = true;
        _players.push(p);
        emit Enrolled(p);
    }

    function playerCount() external view returns (uint256) {
        return _players.length;
    }

    /// One call for the leaderboards: every stat that ranks players, for
    /// players [offset, offset + limit). The app sorts.
    function leaderboard(uint256 offset, uint256 limit)
        external
        view
        returns (
            address[] memory who,
            string[] memory names,
            uint256[] memory hexes,
            uint256[] memory kin,
            uint256[] memory mythics,
            uint256[] memory wins,
            uint256[] memory crew
        )
    {
        uint256 end = offset + limit > _players.length ? _players.length : offset + limit;
        uint256 n = end > offset ? end - offset : 0;
        who = new address[](n);
        names = new string[](n);
        hexes = new uint256[](n);
        kin = new uint256[](n);
        mythics = new uint256[](n);
        wins = new uint256[](n);
        crew = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            address p = _players[offset + i];
            who[i] = p;
            names[i] = game.nameOf(p);
            kin[i] = game.balanceOf(p);
            mythics[i] = mythicsOf[season][p];
            if (address(territory) != address(0)) hexes[i] = territory.hexesOf(p).length;
            if (address(lab) != address(0)) wins[i] = lab.duelWins(p);
            if (address(crews) != address(0)) crew[i] = crews.crewOf(p);
        }
    }

    // ------------------------------------------------------------------ admin

    function setSources(ISeasonTerritory t, ISeasonLab l, ISeasonCrews c) external onlyOwner {
        territory = t;
        lab = l;
        crews = c;
    }
}
