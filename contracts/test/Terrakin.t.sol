// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Terrakin} from "../src/Terrakin.sol";
import {TerrakinCharacters} from "../src/TerrakinCharacters.sol";

contract TerrakinTest is Test {
    Terrakin game;
    uint256 signerKey = 0xA11CE;
    address signer;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        signer = vm.addr(signerKey);
        game = new Terrakin(signer, defaultPrices());
        game.setCharacters(new TerrakinCharacters(address(game)));
        vm.deal(address(game), 10 ether);
    }

    function defaultPrices() internal pure returns (Terrakin.Prices memory p) {
        p.grant = 0.1 ether;
        p.firstCharacter = 0.05 ether;
        p.nextCharacter = 0.08 ether;
        p.tradeReward = 0.001 ether;
        p.orb = [uint128(0.0005 ether), 0.0015 ether, 0.004 ether, 0.03 ether];
        p.catchReward = [uint128(0.0008 ether), 0.0015 ether, 0.0035 ether, 0.009 ether, 0.025 ether];
        p.starterOrbs = 10;
        p.rewardedTradesPerDay = 3;
    }

    function onboard(address who, string memory name) internal {
        vm.prank(signer);
        game.fund(who);
        vm.prank(who);
        game.createProfile{value: 0.05 ether}(name, 1);
    }

    function voucher(address player, bytes32 spawnId, uint8 grade, bool landmark)
        internal
        view
        returns (Terrakin.Bond memory v, bytes memory sig)
    {
        v = Terrakin.Bond({
            player: player,
            spawnId: spawnId,
            species: 3,
            grade: grade,
            vigor: 0x0F0A0503,
            trait: 2,
            landmark: landmark,
            lat: 23176000,
            lng: 88567000,
            hexId: 7,
            zone: landmark ? 9 : 0,
            deadline: uint64(block.timestamp + 300)
        });
        (uint8 r8, bytes32 r, bytes32 s) = vm.sign(signerKey, game.bondDigest(v));
        sig = abi.encodePacked(r, s, r8);
    }

    function bondOne(address who, bytes32 spawnId) internal returns (uint256 id) {
        (Terrakin.Bond memory v, bytes memory sig) = voucher(who, spawnId, 0, false);
        vm.prank(who);
        id = game.bond(v, sig, [uint32(1), 0, 0, 0]);
    }

    // ---------------------------------------------------------------- tests

    function test_FundOnceOnlyBySigner() public {
        vm.expectRevert(Terrakin.NotSigner.selector);
        game.fund(alice);
        vm.prank(signer);
        game.fund(alice);
        assertEq(alice.balance, 0.1 ether);
        assertEq(game.orbsOf(alice)[0], 10);
        vm.prank(signer);
        vm.expectRevert(Terrakin.AlreadyFunded.selector);
        game.fund(alice);
    }

    function test_NamesUniqueCaseInsensitiveAndValidated() public {
        onboard(alice, "Ansh_1");
        assertEq(game.nameOf(alice), "Ansh_1");
        assertFalse(game.isNameFree("ANSH_1"));
        vm.prank(signer);
        game.fund(bob);
        vm.startPrank(bob);
        vm.expectRevert(Terrakin.NameTaken.selector);
        game.createProfile{value: 0.05 ether}("ansh_1", 0);
        vm.expectRevert(Terrakin.BadName.selector);
        game.createProfile{value: 0.05 ether}("abc", 0);
        vm.expectRevert(Terrakin.BadName.selector);
        game.createProfile{value: 0.05 ether}("toolongname", 0);
        vm.expectRevert(Terrakin.BadName.selector);
        game.createProfile{value: 0.05 ether}("no space", 0);
        vm.expectRevert(Terrakin.WrongPayment.selector);
        game.createProfile{value: 0.01 ether}("bobby", 0);
        game.createProfile{value: 0.05 ether}("bobby", 4);
        vm.stopPrank();
        (uint256[] memory ids, uint8[] memory styles) = game.characters().charactersOf(bob);
        assertEq(ids.length, 1);
        assertEq(styles[0], 4);
    }

    function test_BuyOrbsExactPayment() public {
        onboard(alice, "alice");
        vm.startPrank(alice);
        game.buyOrbs{value: 0.015 ether}(1, 10);
        vm.expectRevert(Terrakin.WrongPayment.selector);
        game.buyOrbs{value: 0.01 ether}(1, 10);
        vm.expectRevert(Terrakin.BadOrb.selector);
        game.buyOrbs{value: 0}(4, 1);
        vm.stopPrank();
        assertEq(game.orbsOf(alice)[1], 10);
    }

    function test_BondNeedsValidVoucherAndOrbs() public {
        onboard(alice, "alice");
        uint256 before = alice.balance;
        (Terrakin.Bond memory v, bytes memory sig) = voucher(alice, keccak256("spawn-1"), 4, true);

        // Someone else can't use Alice's voucher.
        vm.prank(bob);
        vm.expectRevert(Terrakin.NotYours.selector);
        game.bond(v, sig, [uint32(1), 0, 0, 0]);

        // Orbs must be owned and at least one thrown.
        vm.startPrank(alice);
        vm.expectRevert(Terrakin.NoOrbs.selector);
        game.bond(v, sig, [uint32(0), 0, 0, 0]);
        vm.expectRevert(Terrakin.NoOrbs.selector);
        game.bond(v, sig, [uint32(0), 0, 0, 1]);

        uint256 id = game.bond(v, sig, [uint32(3), 0, 0, 0]);
        assertEq(game.ownerOf(id), alice);
        assertEq(game.orbsOf(alice)[0], 7);
        assertEq(alice.balance - before, 0.05 ether); // Mythic Landmark pays double
        Terrakin.Kin memory k = game.kin(id);
        assertEq(k.vigor[0], 3);
        assertEq(k.vigor[3], 15);
        assertEq(k.mods[2], 10000);
        assertEq(k.species, 3);
        assertEq(k.grade, 4);
        assertEq(k.trait, 2);
        assertTrue(k.landmark);
        assertEq(k.lat, 23176000);
        assertEq(k.lng, 88567000);
        assertEq(k.bondedAt, block.timestamp);

        vm.expectRevert(Terrakin.AlreadyBonded.selector);
        game.bond(v, sig, [uint32(1), 0, 0, 0]);
        vm.stopPrank();
    }

    function test_BondRejectsTamperedOrExpired() public {
        onboard(alice, "alice");
        (Terrakin.Bond memory v, bytes memory sig) = voucher(alice, keccak256("s"), 0, false);
        v.grade = 4; // try to upgrade a Common to Mythic
        vm.prank(alice);
        vm.expectRevert(Terrakin.BadSignature.selector);
        game.bond(v, sig, [uint32(1), 0, 0, 0]);

        (v, sig) = voucher(alice, keccak256("s"), 0, false);
        vm.warp(block.timestamp + 301);
        vm.prank(alice);
        vm.expectRevert(Terrakin.Expired.selector);
        game.bond(v, sig, [uint32(1), 0, 0, 0]);
    }

    function test_SameSpawnBondableByEveryone() public {
        onboard(alice, "alice");
        onboard(bob, "bobby");
        uint256 a = bondOne(alice, keccak256("shared"));
        uint256 b = bondOne(bob, keccak256("shared"));
        assertTrue(a != b);
    }

    function test_TradeSwapsShiftsAndCaps() public {
        onboard(alice, "alice");
        onboard(bob, "bobby");
        uint256 ka = bondOne(alice, keccak256("a"));
        uint256 kb = bondOne(bob, keccak256("b"));

        vm.prank(alice);
        bytes32 id = game.proposeTrade(ka, kb, bob);
        vm.prank(alice);
        vm.expectRevert(Terrakin.NoTrade.selector);
        game.acceptTrade(id);

        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        game.acceptTrade(id);
        assertEq(game.ownerOf(ka), bob);
        assertEq(game.ownerOf(kb), alice);
        assertEq(bob.balance - bobBefore, 0.001 ether);
        Terrakin.Kin memory k = game.kin(ka);
        assertEq(k.trades, 1);
        bool changed;
        for (uint256 i; i < 4; ++i) {
            assertGe(k.mods[i], 8500);
            assertLe(k.mods[i], 11500);
            if (k.mods[i] != 10000) changed = true;
        }
        assertTrue(changed);

        // Accepted trades can't be replayed.
        vm.prank(bob);
        vm.expectRevert(Terrakin.NoTrade.selector);
        game.acceptTrade(id);
    }

    function test_ManyTradesStayInBoundsAndRewardsCapDaily() public {
        onboard(alice, "alice");
        onboard(bob, "bobby");
        uint256 ka = bondOne(alice, keccak256("a"));
        uint256 kb = bondOne(bob, keccak256("b"));
        uint256 aliceStart = alice.balance;
        for (uint256 n; n < 40; ++n) {
            (address from, address to) = (game.ownerOf(ka), game.ownerOf(kb));
            (uint256 x, uint256 y) = (ka, kb);
            vm.roll(block.number + 1);
            vm.prevrandao(bytes32(n * 7919));
            vm.prank(from);
            bytes32 id = game.proposeTrade(x, y, to);
            vm.prank(to);
            game.acceptTrade(id);
        }
        Terrakin.Kin memory k = game.kin(ka);
        assertEq(k.trades, 40);
        for (uint256 i; i < 4; ++i) {
            assertGe(k.mods[i], 7000);
            assertLe(k.mods[i], 13000);
        }
        assertEq(alice.balance - aliceStart, 3 * 0.001 ether);
    }

    function test_ExpiredAndCancelledTrades() public {
        onboard(alice, "alice");
        onboard(bob, "bobby");
        uint256 ka = bondOne(alice, keccak256("a"));
        uint256 kb = bondOne(bob, keccak256("b"));
        vm.prank(alice);
        bytes32 id = game.proposeTrade(ka, kb, bob);
        vm.warp(block.timestamp + 11 minutes);
        vm.prank(bob);
        vm.expectRevert(Terrakin.Expired.selector);
        game.acceptTrade(id);

        vm.prank(alice);
        id = game.proposeTrade(ka, kb, bob);
        vm.prank(alice);
        game.cancelTrade(id);
        vm.prank(bob);
        vm.expectRevert(Terrakin.NoTrade.selector);
        game.acceptTrade(id);
    }

    function test_NegativeCoordinatesSurvivePacking() public {
        onboard(alice, "alice");
        Terrakin.Bond memory v = Terrakin.Bond({
            player: alice,
            spawnId: keccak256("south"),
            species: 6,
            grade: 2,
            vigor: 0x00FF0102,
            trait: 6,
            landmark: false,
            lat: -33868800,
            lng: -151209300,
            hexId: 8,
            zone: 0,
            deadline: uint64(block.timestamp + 300)
        });
        (uint8 r8, bytes32 r, bytes32 s) = vm.sign(signerKey, game.bondDigest(v));
        vm.prank(alice);
        uint256 id = game.bond(v, abi.encodePacked(r, s, r8), [uint32(1), 0, 0, 0]);
        (uint256[] memory ids, Terrakin.Kin[] memory data) = game.kinOf(alice);
        assertEq(ids[0], id);
        assertEq(data[0].lat, -33868800);
        assertEq(data[0].lng, -151209300);
        assertEq(data[0].vigor[2], 0xFF);
        assertFalse(data[0].landmark);
    }

    function test_CharactersLinkOnlyOnce() public {
        TerrakinCharacters other = new TerrakinCharacters(address(game));
        vm.expectRevert(Terrakin.NotYours.selector);
        game.setCharacters(other);
        vm.prank(alice);
        vm.expectRevert();
        game.setCharacters(other);
    }

    function test_PoolRunsDryWithoutBlockingPlay() public {
        vm.deal(address(game), 0);
        vm.prank(signer);
        game.fund(alice);
        assertEq(alice.balance, 0);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        game.createProfile{value: 0.05 ether}("alice", 0);
        bondOne(alice, keccak256("x"));
        assertEq(game.balanceOf(alice), 1);
    }
}
