// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IDropsGame {
    function signer() external view returns (address);
}

/// @title Terrakin Dead Drops
/// @notice Lock MON and/or a Kin at the exact spot you stand, with a riddle.
/// Only someone who physically stands there can take it.
///
/// The spot never appears on-chain in the clear: the backend seals it
/// (AES-GCM under a server key) and signs the sealed blob along with the hex
/// it lies in. The hex (~150 m) and the riddle are public; the backend
/// unseals the spot to check a claimer's GPS fix (within 25 m) before
/// signing their claim. A drop can be addressed to one player, and the
/// dropper can take it back once it expires.
contract TerrakinDrops is EIP712 {
    struct Spot {
        address player;
        uint64 hexId;
        bytes32 sealedHash;
        uint64 deadline;
    }

    struct Claim {
        address player;
        uint256 dropId;
        uint64 deadline;
    }

    struct Drop {
        address dropper;
        address forWho; // zero: anyone
        uint64 hexId;
        uint64 expiresAt;
        bool done;
        uint256 kinId; // zero: no Kin
        uint256 mon;
        bytes sealedSpot;
        string riddle;
    }

    bytes32 private constant SPOT_TYPEHASH =
        keccak256("Spot(address player,uint64 hexId,bytes32 sealedHash,uint64 deadline)");
    bytes32 private constant CLAIM_TYPEHASH = keccak256("Claim(address player,uint256 dropId,uint64 deadline)");
    uint256 public constant MAX_RIDDLE = 140;
    uint256 public constant MIN_LIFE = 1 hours;
    uint256 public constant MAX_LIFE = 30 days;

    IDropsGame public immutable game;
    IERC721 public immutable kin;
    uint256 public immutable minMon; // a drop holds at least this much MON, or a Kin

    // No global counter: ids hash (dropper, their drop count), so drops by
    // different players touch disjoint storage and run in parallel on Monad.
    mapping(uint256 => Drop) internal _drops;
    mapping(uint64 => uint256[]) internal _byHex;
    mapping(address => uint256[]) internal _byDropper;

    event Dropped(uint256 indexed id, address indexed dropper, uint64 indexed hexId, address forWho, uint256 kinId, uint256 mon);
    event Found(uint256 indexed id, address indexed finder);
    event Reclaimed(uint256 indexed id);

    error BadSignature();
    error Expired();
    error NotYours();
    error BadDrop();
    error Gone();
    error TransferFailed();

    constructor(IDropsGame game_, IERC721 kin_, uint256 minMon_) EIP712("Terrakin Drops", "1") {
        game = game_;
        kin = kin_;
        minMon = minMon_;
    }

    /// @notice Leaves a drop at the spot sealed in [sealedSpot]. Send the MON
    /// reward as value; to include a Kin, approve this contract first.
    function drop(
        Spot calldata s,
        bytes calldata spotSig,
        bytes calldata sealedSpot,
        string calldata riddle,
        uint256 kinId,
        address forWho,
        uint64 expiresAt
    ) external payable returns (uint256 id) {
        if (s.player != msg.sender) revert NotYours();
        if (block.timestamp > s.deadline) revert Expired();
        if (keccak256(sealedSpot) != s.sealedHash) revert BadDrop();
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(SPOT_TYPEHASH, s.player, s.hexId, s.sealedHash, s.deadline)));
        if (ECDSA.recover(digest, spotSig) != game.signer()) revert BadSignature();
        if (expiresAt < block.timestamp + MIN_LIFE || expiresAt > block.timestamp + MAX_LIFE) revert BadDrop();
        if (bytes(riddle).length > MAX_RIDDLE || forWho == msg.sender) revert BadDrop();
        if (kinId == 0 && msg.value < minMon) revert BadDrop();

        id = uint256(keccak256(abi.encode(msg.sender, _byDropper[msg.sender].length)));
        _drops[id] = Drop(msg.sender, forWho, s.hexId, expiresAt, false, kinId, msg.value, sealedSpot, riddle);
        _byHex[s.hexId].push(id);
        _byDropper[msg.sender].push(id);
        if (kinId != 0) kin.transferFrom(msg.sender, address(this), kinId);
        emit Dropped(id, msg.sender, s.hexId, forWho, kinId, msg.value);
    }

    /// @notice Takes a drop the player is standing at.
    function claim(Claim calldata c, bytes calldata sig) external {
        if (c.player != msg.sender) revert NotYours();
        if (block.timestamp > c.deadline) revert Expired();
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(CLAIM_TYPEHASH, c.player, c.dropId, c.deadline)));
        if (ECDSA.recover(digest, sig) != game.signer()) revert BadSignature();
        Drop storage d = _drops[c.dropId];
        if (d.dropper == address(0) || d.done || block.timestamp > d.expiresAt) revert Gone();
        if (d.dropper == msg.sender || (d.forWho != address(0) && d.forWho != msg.sender)) revert NotYours();
        d.done = true;
        _payOut(d, msg.sender);
        emit Found(c.dropId, msg.sender);
    }

    /// @notice The dropper takes back a drop nobody found in time.
    function reclaim(uint256 id) external {
        Drop storage d = _drops[id];
        if (d.dropper != msg.sender) revert NotYours();
        if (d.done) revert Gone();
        if (block.timestamp <= d.expiresAt) revert BadDrop();
        d.done = true;
        _payOut(d, msg.sender);
        emit Reclaimed(id);
    }

    function _payOut(Drop storage d, address to) internal {
        if (d.kinId != 0) kin.transferFrom(address(this), to, d.kinId);
        if (d.mon != 0) {
            (bool ok,) = to.call{value: d.mon}("");
            if (!ok) revert TransferFailed();
        }
    }

    // ----------------------------------------------------------------- views

    /// Open drops in the given hexes (for the map).
    function openIn(uint64[] calldata hexIds) external view returns (uint256[] memory ids) {
        uint256 n;
        for (uint256 i; i < hexIds.length; ++i) n += _byHex[hexIds[i]].length;
        ids = new uint256[](n);
        n = 0;
        for (uint256 i; i < hexIds.length; ++i) {
            uint256[] storage l = _byHex[hexIds[i]];
            for (uint256 k; k < l.length; ++k) {
                Drop storage d = _drops[l[k]];
                if (!d.done && block.timestamp <= d.expiresAt) ids[n++] = l[k];
            }
        }
        assembly ("memory-safe") {
            mstore(ids, n)
        }
    }

    function dropsBy(address dropper) external view returns (uint256[] memory) {
        return _byDropper[dropper];
    }

    /// Everything about a drop except its sealed spot.
    function info(uint256 id)
        external
        view
        returns (
            address dropper,
            address forWho,
            uint64 hexId,
            uint64 expiresAt,
            bool done,
            uint256 kinId,
            uint256 mon,
            string memory riddle
        )
    {
        Drop storage d = _drops[id];
        return (d.dropper, d.forWho, d.hexId, d.expiresAt, d.done, d.kinId, d.mon, d.riddle);
    }

    function sealedSpotOf(uint256 id) external view returns (bytes memory) {
        return _drops[id].sealedSpot;
    }

    function spotDigest(Spot calldata s) external view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(SPOT_TYPEHASH, s.player, s.hexId, s.sealedHash, s.deadline)));
    }

    function claimDigest(Claim calldata c) external view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(CLAIM_TYPEHASH, c.player, c.dropId, c.deadline)));
    }
}
