// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TerrakinStrides, IStridesGame} from "../src/TerrakinStrides.sol";

contract StubGame is IStridesGame {
    address public signer;

    constructor(address s) {
        signer = s;
    }
}

contract StridesTest is Test {
    TerrakinStrides strides;
    uint256 signerKey = 0xA11CE;
    address player = makeAddr("player");
    address other = makeAddr("other");

    function setUp() public {
        vm.warp(1_800_000_000);
        strides = new TerrakinStrides(
            IStridesGame(address(new StubGame(vm.addr(signerKey)))), TerrakinStrides.Rules(0.01 ether, 4)
        );
        vm.deal(address(strides), 1 ether);
    }

    function walk(address who, uint64 from, uint64 to, uint32 metres)
        internal
        view
        returns (TerrakinStrides.Walk memory w, bytes memory sig)
    {
        w = TerrakinStrides.Walk(who, from, to, metres, uint64(block.timestamp + 120));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, strides.walkDigest(w));
        sig = abi.encodePacked(r, s, v);
    }

    function claimAs(address who, uint64 from, uint64 to, uint32 metres) internal returns (uint256) {
        (TerrakinStrides.Walk memory w, bytes memory sig) = walk(who, from, to, metres);
        vm.prank(who);
        return strides.claim(w, sig);
    }

    function test_paysPerFullStep() public {
        assertEq(claimAs(player, 100, 800, 1040), 0.02 ether);
        assertEq(player.balance, 0.02 ether);
        assertEq(strides.walkedUntil(player), 800);
        assertEq(strides.stepsToday(player), 2);
    }

    function test_noStretchPaidTwice() public {
        claimAs(player, 100, 800, 500);
        (TerrakinStrides.Walk memory w, bytes memory sig) = walk(player, 700, 1200, 500);
        vm.prank(player);
        vm.expectRevert(TerrakinStrides.AlreadyPaid.selector);
        strides.claim(w, sig);
        assertEq(claimAs(player, 800, 1200, 500), 0.01 ether); // picks up where the last ended
    }

    function test_dailyCapThenNextDay() public {
        assertEq(claimAs(player, 100, 200, 3000), 0.04 ether); // 6 steps, cap 4
        (TerrakinStrides.Walk memory w, bytes memory sig) = walk(player, 300, 400, 500);
        vm.prank(player);
        vm.expectRevert(TerrakinStrides.DailyCap.selector);
        strides.claim(w, sig);
        vm.warp(block.timestamp + 1 days);
        assertEq(claimAs(player, 300, 400, 500), 0.01 ether);
    }

    function test_rejectsShortForeignForgedAndStale() public {
        (TerrakinStrides.Walk memory w, bytes memory sig) = walk(player, 100, 200, 499);
        vm.prank(player);
        vm.expectRevert(TerrakinStrides.TooShort.selector);
        strides.claim(w, sig);

        (w, sig) = walk(player, 100, 200, 500);
        vm.prank(other);
        vm.expectRevert(TerrakinStrides.NotYours.selector);
        strides.claim(w, sig);

        w.metres = 5000;
        vm.prank(player);
        vm.expectRevert(TerrakinStrides.BadSignature.selector);
        strides.claim(w, sig);

        (w, sig) = walk(player, 100, 200, 500);
        vm.warp(block.timestamp + 121);
        vm.prank(player);
        vm.expectRevert(TerrakinStrides.Expired.selector);
        strides.claim(w, sig);
    }

    function test_emptyPool() public {
        strides.withdraw(address(this), 1 ether);
        (TerrakinStrides.Walk memory w, bytes memory sig) = walk(player, 100, 200, 500);
        vm.prank(player);
        vm.expectRevert(TerrakinStrides.PoolEmpty.selector);
        strides.claim(w, sig);
    }

    receive() external payable {}
}
