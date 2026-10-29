// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IStridesGame {
    function signer() external view returns (address);
}

/// @title Terrakin Strides
/// @notice MON for walking: every 500 m walked pays a small reward, up to a
/// daily cap.
///
/// While the app is open the backend stamps the player's position every
/// ~100 m (HMAC over wallet, spot and time). Claiming sends the stamps back;
/// the backend checks the walk was continuous and humanly paced, and signs
/// the time span it covers and the metres walked. Each walk must start at or
/// after the end of the last one paid, so no stretch is paid twice. The pool
/// is topped up by sending MON to this contract.
contract TerrakinStrides is EIP712, Ownable {
    struct Walk {
        address player;
        uint64 from; // first stamp, unix seconds
        uint64 to; // last stamp counted
        uint32 metres;
        uint64 deadline;
    }

    struct Rules {
        uint128 perStep; // MON per STEP metres
        uint32 stepsPerDay;
    }

    bytes32 private constant WALK_TYPEHASH =
        keccak256("Walk(address player,uint64 from,uint64 to,uint32 metres,uint64 deadline)");
    uint32 public constant STEP = 500;

    IStridesGame public immutable game;
    Rules public rules;

    mapping(address => uint64) public walkedUntil;
    mapping(address => uint256) public metresPaid;
    /// Steps paid today, packed as day << 32 | steps (one slot per player).
    mapping(address => uint256) internal _today;

    event Strode(address indexed player, uint32 metres, uint32 steps, uint256 mon);
    event RulesSet(uint128 perStep, uint32 stepsPerDay);

    error BadSignature();
    error Expired();
    error NotYours();
    error AlreadyPaid();
    error TooShort();
    error DailyCap();
    error PoolEmpty();
    error TransferFailed();

    constructor(IStridesGame game_, Rules memory rules_) EIP712("Terrakin Strides", "1") Ownable(msg.sender) {
        game = game_;
        rules = rules_;
        emit RulesSet(rules_.perStep, rules_.stepsPerDay);
    }

    receive() external payable {}

    /// @notice Pays a signed walk: one reward per full 500 m, within today's cap.
    function claim(Walk calldata w, bytes calldata sig) external returns (uint256 mon) {
        if (w.player != msg.sender) revert NotYours();
        if (block.timestamp > w.deadline) revert Expired();
        if (ECDSA.recover(walkDigest(w), sig) != game.signer()) revert BadSignature();
        if (w.from < walkedUntil[msg.sender] || w.to <= w.from) revert AlreadyPaid();
        uint32 steps = w.metres / STEP;
        if (steps == 0) revert TooShort();

        uint256 day = block.timestamp / 1 days;
        uint256 t = _today[msg.sender];
        uint32 done = t >> 32 == day ? uint32(t) : 0;
        Rules memory r = rules;
        if (done >= r.stepsPerDay) revert DailyCap();
        if (steps > r.stepsPerDay - done) steps = r.stepsPerDay - done;

        mon = uint256(steps) * r.perStep;
        if (address(this).balance < mon) revert PoolEmpty();
        walkedUntil[msg.sender] = w.to;
        metresPaid[msg.sender] += w.metres;
        _today[msg.sender] = day << 32 | (done + steps);
        (bool ok,) = msg.sender.call{value: mon}("");
        if (!ok) revert TransferFailed();
        emit Strode(msg.sender, w.metres, steps, mon);
    }

    /// Steps already paid to [player] today (UTC).
    function stepsToday(address player) external view returns (uint32) {
        uint256 t = _today[player];
        return t >> 32 == block.timestamp / 1 days ? uint32(t) : 0;
    }

    function walkDigest(Walk calldata w) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(WALK_TYPEHASH, w.player, w.from, w.to, w.metres, w.deadline)));
    }

    // ----------------------------------------------------------------- owner

    function setRules(Rules calldata r) external onlyOwner {
        rules = r;
        emit RulesSet(r.perStep, r.stepsPerDay);
    }

    function withdraw(address to, uint256 amount) external onlyOwner {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
