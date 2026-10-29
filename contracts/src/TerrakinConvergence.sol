// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// What Convergence needs from the game contract.
interface IConvergenceGame {
    function signer() external view returns (address);
    function moduleMint(address to, uint256 kinId, uint256 packed) external;
}

/// @title Terrakin Convergence
/// @notice A Mythic Kin appears at a real public place for twenty minutes.
/// Nobody can bond it alone: it answers only when a circle of at least
/// [CIRCLE] players stands there within [TOGETHER] of each other. Each
/// player's phone proves it is within reach with a pass signed by the game
/// signer (the backend checks the GPS fix against the spot). Everyone in the
/// circle gets their own copy, minted the moment the circle completes; anyone
/// who joins while the circle still stands gets one too.
contract TerrakinConvergence is EIP712 {
    struct Pass {
        address player;
        bytes32 eventId;
        uint8 species;
        int32 lat; // spot, micro-degrees
        int32 lng;
        uint64 opensAt;
        uint64 deadline;
    }

    struct Event {
        uint8 species;
        int32 lat;
        int32 lng;
        uint64 opensAt;
        uint16 joined;
        uint16 bonded;
    }

    bytes32 private constant PASS_TYPEHASH = keccak256(
        "Pass(address player,bytes32 eventId,uint8 species,int32 lat,int32 lng,uint64 opensAt,uint64 deadline)"
    );
    uint256 public constant CIRCLE = 3;
    uint256 public constant TOGETHER = 5 minutes;
    uint256 public constant WINDOW = 20 minutes;
    uint256 public constant MAX_ATTENDEES = 64;
    uint256 private constant MYTHIC = 4;
    uint256 private constant TRAITS = 7; // backend/lib/spawn.ts

    IConvergenceGame public immutable game;

    mapping(bytes32 => Event) public events;
    mapping(bytes32 => address[]) internal _attendees;
    mapping(bytes32 => mapping(address => uint64)) public joinedAt;
    mapping(bytes32 => mapping(address => bool)) public bonded;

    event Joined(bytes32 indexed eventId, address indexed player, uint256 together);
    event CircleBonded(bytes32 indexed eventId, address indexed player, uint256 kinId);

    error BadSignature();
    error Expired();
    error NotYours();
    error Closed();
    error AlreadyJoined();
    error Full();

    constructor(IConvergenceGame game_) EIP712("Terrakin Convergence", "1") {
        game = game_;
    }

    /// @notice Steps into the circle. Returns how many players are within
    /// [TOGETHER] of now, including the caller; at [CIRCLE] or more, every
    /// one of them who hasn't bonded yet gets the Mythic.
    function join(Pass calldata p, bytes calldata sig) external returns (uint256 together) {
        if (p.player != msg.sender) revert NotYours();
        if (block.timestamp > p.deadline) revert Expired();
        if (block.timestamp < p.opensAt || block.timestamp >= p.opensAt + WINDOW) revert Closed();
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(PASS_TYPEHASH, p.player, p.eventId, p.species, p.lat, p.lng, p.opensAt, p.deadline))
        );
        if (ECDSA.recover(digest, sig) != game.signer()) revert BadSignature();

        Event storage e = events[p.eventId];
        if (e.opensAt == 0) {
            e.species = p.species;
            e.lat = p.lat;
            e.lng = p.lng;
            e.opensAt = p.opensAt;
        }
        if (joinedAt[p.eventId][msg.sender] != 0) revert AlreadyJoined();
        address[] storage list = _attendees[p.eventId];
        if (list.length >= MAX_ATTENDEES) revert Full();
        list.push(msg.sender);
        joinedAt[p.eventId][msg.sender] = uint64(block.timestamp);
        e.joined++;

        uint256 since = block.timestamp > TOGETHER ? block.timestamp - TOGETHER : 0;
        for (uint256 i; i < list.length; ++i) {
            if (joinedAt[p.eventId][list[i]] >= since) ++together;
        }
        emit Joined(p.eventId, msg.sender, together);
        if (together < CIRCLE) return together;

        for (uint256 i; i < list.length; ++i) {
            address who = list[i];
            if (joinedAt[p.eventId][who] < since || bonded[p.eventId][who]) continue;
            bonded[p.eventId][who] = true;
            e.bonded++;
            uint256 kinId = uint256(keccak256(abi.encode(p.eventId, who, "converge")));
            game.moduleMint(who, kinId, _mythic(e, who));
            emit CircleBonded(p.eventId, who, kinId);
        }
    }

    /// Each copy gets its own vigor (10-15 per stat) and trait; species and
    /// origin are the event's.
    function _mythic(Event storage e, address who) internal view returns (uint256 w) {
        uint256 r = uint256(keccak256(abi.encode(block.prevrandao, who, e.opensAt)));
        w = uint256(e.species) | MYTHIC << 8 | (r % TRAITS) << 16 | uint256(1) << 24;
        w |= block.timestamp << 48 | uint256(uint32(e.lat)) << 88 | uint256(uint32(e.lng)) << 120;
        for (uint256 i; i < 4; ++i) {
            w |= (10 + (r >> (8 + 8 * i)) % 6) << (152 + 8 * i);
            w |= uint256(10000) << (184 + 16 * i);
        }
    }

    function attendees(bytes32 eventId) external view returns (address[] memory list, uint64[] memory at) {
        list = _attendees[eventId];
        at = new uint64[](list.length);
        for (uint256 i; i < list.length; ++i) at[i] = joinedAt[eventId][list[i]];
    }

    function passDigest(Pass calldata p) external view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(abi.encode(PASS_TYPEHASH, p.player, p.eventId, p.species, p.lat, p.lng, p.opensAt, p.deadline))
        );
    }
}
