// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IBountyGame {
    function kinPacked(uint256[] calldata ids) external view returns (address[] memory owners, uint256[] memory packed);
}

/// @title Terrakin Bounties
/// @notice "Catch me a Mythic Shardlet within 2 km of Sealdah by Friday": a
/// poster locks MON; the first hunter to deliver a Kin that matches (species,
/// minimum grade, bonded after the bounty went up, spawned inside the circle)
/// gets the reward and the poster gets the Kin. Everything is checked against
/// the Kin's on-chain record. Unclaimed bounties refund after the deadline.
contract TerrakinBounties {
    struct Bounty {
        address poster;
        uint8 species; // 255 = any
        uint8 minGrade;
        int32 lat; // micro-degrees
        int32 lng;
        uint32 radiusM;
        uint32 cosE6; // cos(lat) x 1e6, for east-west distance (HexGrid.cosE6)
        uint40 created;
        uint40 deadline;
        uint128 reward;
    }

    IERC721 public immutable kin;
    uint16 public immutable feeBps;
    uint128 public immutable minReward;

    mapping(uint256 => Bounty) public bounties;
    uint256[] internal _open;
    mapping(uint256 => uint256) internal _index;
    mapping(address => uint256) internal _nonce;

    event Posted(uint256 indexed id, address indexed poster, uint8 species, uint8 minGrade, uint256 reward, uint40 deadline);
    event Claimed(uint256 indexed id, address indexed hunter, uint256 indexed kinId, uint256 reward);
    event Cancelled(uint256 indexed id);

    error BadBounty();
    error NoBounty();
    error NotYours();
    error NoMatch();
    error Expired();
    error TooEarly();
    error TransferFailed();

    constructor(IERC721 kin_, uint16 feeBps_, uint128 minReward_) {
        kin = kin_;
        feeBps = feeBps_;
        minReward = minReward_;
    }

    function post(uint8 species, uint8 minGrade, int32 lat, int32 lng, uint32 radiusM, uint32 cosE6, uint40 deadline)
        external
        payable
        returns (uint256 id)
    {
        if (msg.value < minReward || (species >= 7 && species != 255) || minGrade > 4) revert BadBounty();
        if (radiusM < 100 || radiusM > 50_000 || cosE6 == 0 || cosE6 > 1_000_000) revert BadBounty();
        if (deadline <= block.timestamp + 1 hours || deadline > block.timestamp + 30 days) revert BadBounty();
        id = uint256(keccak256(abi.encode(msg.sender, _nonce[msg.sender]++, "bounty")));
        bounties[id] = Bounty(
            msg.sender, species, minGrade, lat, lng, radiusM, cosE6, uint40(block.timestamp), deadline, uint128(msg.value)
        );
        _index[id] = _open.length;
        _open.push(id);
        emit Posted(id, msg.sender, species, minGrade, msg.value, deadline);
    }

    /// Delivers [kinId] to the poster (approve this contract first).
    function claim(uint256 id, uint256 kinId) external {
        Bounty memory b = bounties[id];
        if (b.poster == address(0)) revert NoBounty();
        if (block.timestamp > b.deadline) revert Expired();
        if (b.poster == msg.sender) revert NotYours();
        if (!matches(id, kinId, msg.sender)) revert NoMatch();
        _remove(id);
        kin.transferFrom(msg.sender, b.poster, kinId);
        uint256 fee = uint256(b.reward) * feeBps / 10000;
        _send(address(kin), fee);
        _send(msg.sender, b.reward - fee);
        emit Claimed(id, msg.sender, kinId, b.reward - fee);
    }

    /// Whether [kinId], owned by [hunter], satisfies bounty [id].
    function matches(uint256 id, uint256 kinId, address hunter) public view returns (bool) {
        Bounty memory b = bounties[id];
        uint256[] memory ids = new uint256[](1);
        ids[0] = kinId;
        (address[] memory owners, uint256[] memory p) = IBountyGame(address(kin)).kinPacked(ids);
        if (owners[0] != hunter || hunter == address(0)) return false;
        uint256 w = p[0];
        if (b.species != 255 && uint8(w) != b.species) return false;
        if (uint8(w >> 8) < b.minGrade) return false;
        uint256 bondedAt = uint40(w >> 48);
        if (bondedAt < b.created || bondedAt > b.deadline) return false;
        // Equirectangular distance in micro-degrees of latitude; 1 m ~ 8.983.
        int256 dLat = int256(int32(uint32(w >> 88))) - b.lat;
        int256 dLng = (int256(int32(uint32(w >> 120))) - b.lng) * int256(uint256(b.cosE6)) / 1e6;
        int256 r = int256(uint256(b.radiusM)) * 8983 / 1000;
        return dLat * dLat + dLng * dLng <= r * r;
    }

    function cancel(uint256 id) external {
        Bounty memory b = bounties[id];
        if (b.poster != msg.sender) revert NotYours();
        if (block.timestamp <= b.deadline) revert TooEarly();
        _remove(id);
        _send(msg.sender, b.reward);
        emit Cancelled(id);
    }

    function open() external view returns (uint256[] memory ids, Bounty[] memory list) {
        ids = _open;
        list = new Bounty[](ids.length);
        for (uint256 i; i < ids.length; ++i) list[i] = bounties[ids[i]];
    }

    function _remove(uint256 id) internal {
        uint256 idx = _index[id];
        uint256 last = _open[_open.length - 1];
        _open[idx] = last;
        _index[last] = idx;
        _open.pop();
        delete _index[id];
        delete bounties[id];
    }

    function _send(address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
