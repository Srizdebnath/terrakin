// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Terrakin, ITerritory} from "../src/Terrakin.sol";
import {TerrakinCharacters} from "../src/TerrakinCharacters.sol";
import {TerrakinTerritory, ITerrakin} from "../src/TerrakinTerritory.sol";
import {BattleLib} from "../src/BattleLib.sol";

contract TerritoryTest is Test {
    Terrakin game;
    TerrakinTerritory land;
    uint256 signerKey = 0xA11CE;
    address signer;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    uint64 constant HEX = 0x8000_0010_7fff_ff00;
    uint64 constant ZONE = 0x8000_0002_8000_0007;
    uint256 nonce;

    function setUp() public {
        vm.warp(1_800_000_000);
        signer = vm.addr(signerKey);
        Terrakin.Prices memory p;
        p.grant = 0.1 ether;
        p.firstCharacter = 0.05 ether;
        p.nextCharacter = 0.08 ether;
        p.tradeReward = 0.001 ether;
        p.orb = [uint128(0.0005 ether), 0.0015 ether, 0.004 ether, 0.03 ether];
        p.catchReward = [uint128(0.001 ether), 0.002 ether, 0.004 ether, 0.01 ether, 0.025 ether];
        p.starterOrbs = 50;
        p.rewardedTradesPerDay = 3;
        game = new Terrakin(signer, p);
        game.setCharacters(new TerrakinCharacters(address(game)));
        land = new TerrakinTerritory(ITerrakin(address(game)), landPrices());
        game.setTerritory(ITerritory(address(land)));
        vm.deal(address(game), 10 ether);
        for (uint256 i; i < 3; ++i) {
            address who = [alice, bob, carol][i];
            vm.prank(signer);
            game.fund(who);
            vm.deal(who, 1 ether);
        }
    }

    function landPrices() internal pure returns (TerrakinTerritory.Prices memory t) {
        t.claim = 0.01 ether;
        t.attackFee = 0.004 ether;
        t.minBid = 0.005 ether;
        t.cutBps = 1000;
        t.landmarkCutBps = 2500;
        t.bidStepBps = 500;
        t.shield = 30 minutes;
        t.loopPerHex = 0.002 ether;
    }

    // ------------------------------------------------------------- helpers

    function kin(address who, uint8 species, uint8 grade, uint32 vigor, uint64 hexId, uint64 zone)
        internal
        returns (uint256 id)
    {
        Terrakin.Bond memory v = Terrakin.Bond({
            player: who,
            spawnId: keccak256(abi.encode(nonce++)),
            species: species,
            grade: grade,
            vigor: vigor,
            trait: 0,
            landmark: zone != 0,
            lat: 23176000,
            lng: 88567000,
            hexId: hexId,
            zone: zone,
            deadline: uint64(vm.getBlockTimestamp() + 300)
        });
        (uint8 r8, bytes32 r, bytes32 s) = vm.sign(signerKey, game.bondDigest(v));
        vm.prank(who);
        id = game.bond(v, abi.encodePacked(r, s, r8), [uint32(1), 0, 0, 0]);
    }

    function strong(address who) internal returns (uint256) {
        return kin(who, 6, 4, 0x0F0F0F0F, 1, 0); // Mythic Pebblet, perfect vigor
    }

    function weak(address who) internal returns (uint256) {
        return kin(who, 5, 0, 0, 1, 0); // Common Sparkit, zero vigor
    }

    function presence(address who, uint64 hexId) internal view returns (TerrakinTerritory.Presence memory p, bytes memory sig) {
        p = TerrakinTerritory.Presence(who, hexId, uint64(vm.getBlockTimestamp() + 300));
        (uint8 r8, bytes32 r, bytes32 s) = vm.sign(signerKey, land.presenceDigest(p));
        sig = abi.encodePacked(r, s, r8);
    }

    function one(uint256 a) internal pure returns (uint256[] memory l) {
        l = new uint256[](1);
        l[0] = a;
    }

    function claimAs(address who, uint64 hexId, uint256[] memory squad) internal {
        (TerrakinTerritory.Presence memory p, bytes memory sig) = presence(who, hexId);
        vm.prank(who);
        land.claim{value: 0.01 ether}(p, sig, squad);
    }

    function attackAs(address who, uint64 hexId, uint256[] memory squad) internal returns (bool) {
        (TerrakinTerritory.Presence memory p, bytes memory sig) = presence(who, hexId);
        vm.prank(who);
        return land.attack{value: 0.004 ether}(p, sig, squad);
    }

    /// Signs first, so vm.expectRevert applies to the attack itself.
    function attackReverts(address who, uint64 hexId, uint256[] memory squad, bytes4 err) internal {
        (TerrakinTerritory.Presence memory p, bytes memory sig) = presence(who, hexId);
        vm.prank(who);
        vm.expectRevert(err);
        land.attack{value: 0.004 ether}(p, sig, squad);
    }

    // ---------------------------------------------------------------- tests

    function test_ClaimNeedsPresencePaymentAndOwnKin() public {
        uint256 a = weak(alice);
        uint256 b = weak(bob);
        (TerrakinTerritory.Presence memory p, bytes memory sig) = presence(alice, HEX);

        vm.prank(bob); // someone else's presence voucher
        vm.expectRevert(TerrakinTerritory.NotYours.selector);
        land.claim{value: 0.01 ether}(p, sig, one(b));

        vm.prank(alice);
        vm.expectRevert(TerrakinTerritory.WrongPayment.selector);
        land.claim{value: 0.001 ether}(p, sig, one(a));

        vm.prank(alice);
        vm.expectRevert(TerrakinTerritory.NotYours.selector);
        land.claim{value: 0.01 ether}(p, sig, one(b));

        p.hexId = HEX + 1; // tampered
        vm.prank(alice);
        vm.expectRevert(TerrakinTerritory.BadSignature.selector);
        land.claim{value: 0.01 ether}(p, sig, one(a));

        uint256 pool = address(game).balance;
        claimAs(alice, HEX, one(a));
        (address owner,, uint40 shield) = land.hexes(HEX);
        assertEq(owner, alice);
        assertEq(shield, vm.getBlockTimestamp() + 30 minutes);
        assertEq(address(game).balance, pool + 0.01 ether, "claim fee funds the pool");
        assertEq(land.hexesOf(alice).length, 1);
        assertEq(land.stationedAt(a), HEX);

        (p, sig) = presence(bob, HEX);
        vm.prank(bob);
        vm.expectRevert(TerrakinTerritory.Owned.selector);
        land.claim{value: 0.01 ether}(p, sig, one(b));
    }

    function test_OwnerTakesCutOfCatchesInHex() public {
        claimAs(alice, HEX, one(weak(alice)));
        uint256 before = alice.balance;
        uint256 bobBefore = bob.balance;
        kin(bob, 0, 2, 0, HEX, 0); // Rare in Alice's hex: 0.004 reward
        assertEq(alice.balance - before, 0.0004 ether, "10% to the owner");
        assertEq(bob.balance - bobBefore, 0.0036 ether, "catcher keeps 90%");

        before = alice.balance;
        kin(alice, 0, 2, 0, HEX, 0); // owner catching at home pays no cut to themselves
        assertEq(alice.balance - before, 0.004 ether);
    }

    function test_ShieldThenStrongAttackerCaptures() public {
        uint256 d = weak(alice);
        claimAs(alice, HEX, one(d));
        uint256 s = strong(bob);

        attackReverts(bob, HEX, one(s), TerrakinTerritory.Shielded.selector);

        vm.warp(vm.getBlockTimestamp() + 31 minutes);
        uint256 pool = address(game).balance;
        assertTrue(attackAs(bob, HEX, one(s)));
        (address owner,,) = land.hexes(HEX);
        assertEq(owner, bob);
        assertEq(land.stationedAt(s), HEX);
        assertEq(land.stationedAt(d), 0, "old defenders are released");
        assertEq(land.hexesOf(alice).length, 0);
        assertEq(land.hexesOf(bob)[0], HEX);
        assertEq(address(game).balance, pool + 0.004 ether, "winner's fee funds the pool");

        attackReverts(alice, HEX, one(weak(alice)), TerrakinTerritory.Shielded.selector);
    }

    function test_FailedAttackPaysDefender() public {
        claimAs(alice, HEX, one(strong(alice)));
        vm.warp(vm.getBlockTimestamp() + 31 minutes);
        uint256 before = alice.balance;
        assertFalse(attackAs(bob, HEX, one(weak(bob))));
        (address owner,,) = land.hexes(HEX);
        assertEq(owner, alice);
        assertEq(alice.balance - before, 0.004 ether);
    }

    function test_TradedAwayDefendersDontFight() public {
        uint256 d = strong(alice);
        claimAs(alice, HEX, one(d));
        // Alice stations her only defender elsewhere: HEX is left undefended.
        claimAs(alice, HEX + 1, one(d));
        (,, uint8[] memory counts) = land.hexStates(_ids(HEX, HEX + 1));
        assertEq(counts[0], 0);
        assertEq(counts[1], 1);
        vm.warp(vm.getBlockTimestamp() + 31 minutes);
        assertTrue(attackAs(bob, HEX, one(weak(bob))), "an empty hex falls to any Kin");
    }

    function test_SquadRules() public {
        claimAs(alice, HEX, one(weak(alice)));
        vm.warp(vm.getBlockTimestamp() + 31 minutes);
        uint256 b = weak(bob);
        uint256[] memory dup = new uint256[](2);
        dup[0] = b;
        dup[1] = b;
        attackReverts(bob, HEX, dup, TerrakinTerritory.BadSquad.selector);
        attackReverts(alice, HEX, one(b), TerrakinTerritory.NotYours.selector); // owner can't attack own hex
        attackReverts(bob, HEX, new uint256[](0), TerrakinTerritory.BadSquad.selector);
        attackReverts(bob, HEX, one(weak(carol)), TerrakinTerritory.NotYours.selector);
    }

    function test_LandmarkAuctionOutbidRefundAndCut() public {
        uint32 tomorrow = land.today() + 1;
        vm.expectRevert(TerrakinTerritory.BadAuction.selector);
        vm.prank(alice);
        land.bid{value: 0.005 ether}(ZONE, tomorrow - 1);

        vm.prank(alice);
        vm.expectRevert(TerrakinTerritory.BidTooLow.selector);
        land.bid{value: 0.004 ether}(ZONE, tomorrow);

        vm.prank(alice);
        land.bid{value: 0.01 ether}(ZONE, tomorrow);
        vm.prank(bob);
        vm.expectRevert(TerrakinTerritory.BidTooLow.selector);
        land.bid{value: 0.0104 ether}(ZONE, tomorrow); // needs +5%
        vm.prank(bob);
        land.bid{value: 0.0105 ether}(ZONE, tomorrow);
        assertEq(land.refunds(alice), 0.01 ether);

        uint256 before = alice.balance;
        vm.prank(alice);
        land.withdrawRefund();
        assertEq(alice.balance - before, 0.01 ether);

        vm.expectRevert(TerrakinTerritory.BadAuction.selector);
        land.settle(ZONE, tomorrow); // not started yet

        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 pool = address(game).balance;
        land.settle(ZONE, tomorrow);
        assertEq(address(game).balance, pool + 0.0105 ether);
        vm.expectRevert(TerrakinTerritory.BadAuction.selector);
        land.settle(ZONE, tomorrow);

        // Bob now takes 25% of Landmark catches in the zone today, even over
        // the hex owner.
        claimAs(alice, HEX, one(weak(alice)));
        before = bob.balance;
        uint256 carolBefore = carol.balance;
        kin(carol, 3, 4, 0, HEX, ZONE); // Mythic Landmark: 0.025 x2 = 0.05
        assertEq(bob.balance - before, 0.0125 ether);
        assertEq(carol.balance - carolBefore, 0.0375 ether);
    }

    function test_OwnerIndexSurvivesTrades() public {
        uint256 a1 = weak(alice);
        uint256 a2 = weak(alice);
        uint256 b1 = weak(bob);
        vm.prank(alice);
        bytes32 t = game.proposeTrade(a1, b1, bob);
        vm.prank(bob);
        game.acceptTrade(t);
        (uint256[] memory ids,) = game.kinOf(alice);
        assertEq(ids.length, 2);
        assertTrue((ids[0] == a2 && ids[1] == b1) || (ids[0] == b1 && ids[1] == a2));
        (ids,) = game.kinOf(bob);
        assertEq(ids.length, 1);
        assertEq(ids[0], a1);
    }

    /// Fixed battles whose outcomes the Dart mirror (app/test/battle_test.dart)
    /// must reproduce exactly.
    function test_BattleVectors() public view {
        BattleLib.Fighter[] memory a = new BattleLib.Fighter[](2);
        BattleLib.Fighter[] memory d = new BattleLib.Fighter[](2);
        a[0] = land.fighter(_packed(6, 4, 0x0F0F0F0F), false);
        a[1] = land.fighter(_packed(2, 1, 0x05060708), false);
        d[0] = land.fighter(_packed(0, 2, 0x0A0A0A0A), true);
        d[1] = land.fighter(_packed(5, 3, 0x01020304), true);
        assertEq(a[0].hp, 516); // 86 x 2.0 x (30+15)/30 = 258, doubled
        assertEq(a[0].atk, 126);
        (bool won, uint256 turns, uint256 hp) = land.simulate(a, d, keccak256("terrakin"));
        console.log("vector1", won, turns, hp);
        (won, turns, hp) = land.simulate(a, d, keccak256("monad"));
        console.log("vector2", won, turns, hp);

        // Evenly matched, so the seed decides: these catch any drift in the
        // RNG or damage maths between Solidity and Dart.
        a[0] = land.fighter(_packed(1, 1, 0x0B0A0908), false);
        a[1] = land.fighter(_packed(4, 1, 0x0C0B0A09), false);
        d[0] = land.fighter(_packed(5, 1, 0x05060708), true);
        d[1] = land.fighter(_packed(0, 0, 0x090A0B0C), true);
        for (uint256 k; k < 8; ++k) {
            (won, turns, hp) = land.simulate(a, d, keccak256(abi.encode(k)));
            console.log("even", k, turns, hp);
            console.log(won);
        }
    }

    function _packed(uint256 species, uint256 grade, uint32 vigor) internal pure returns (uint256 w) {
        w = species | grade << 8;
        for (uint256 i; i < 4; ++i) {
            w |= uint256(uint8(vigor >> (8 * i))) << (152 + 8 * i);
            w |= uint256(10000) << (184 + 16 * i);
        }
    }

    function _ids(uint64 x, uint64 y) internal pure returns (uint64[] memory l) {
        l = new uint64[](2);
        l[0] = x;
        l[1] = y;
    }

    // --------------------------------------------------------- loop capture

    function ids(uint64 first, uint256 n) internal pure returns (uint64[] memory l) {
        l = new uint64[](n);
        for (uint256 i; i < n; ++i) l[i] = first + uint64(i);
    }

    function loopSig(address who, uint64 startedAt, uint64[] memory trail, uint64[] memory inside)
        internal
        view
        returns (uint64 deadline, bytes memory sig)
    {
        deadline = uint64(vm.getBlockTimestamp() + 300);
        (uint8 r8, bytes32 r, bytes32 s) = vm.sign(signerKey, land.loopDigest(who, startedAt, trail, inside, deadline));
        sig = abi.encodePacked(r, s, r8);
    }

    function test_loopTakesFreeHexesAndRefunds() public {
        uint64[] memory trail = ids(HEX + 100, 7);
        uint64[] memory inside = ids(HEX + 200, 3);
        uint64 start = uint64(block.timestamp - 600);
        (uint64 dl, bytes memory sig) = loopSig(alice, start, trail, inside);
        uint256 before = alice.balance;
        vm.prank(alice);
        uint64[] memory taken = land.claimLoop{value: 0.1 ether}(start, dl, trail, inside, sig);
        assertEq(taken.length, 10);
        assertEq(before - alice.balance, 10 * 0.002 ether);
        assertEq(land.hexesOf(alice).length, 10);
    }

    function test_loopSurroundsUndefendedButNotDefended() public {
        uint256 b1 = strong(bob);
        claimAs(bob, HEX + 200, one(b1)); // defended
        uint256 b2 = weak(bob);
        claimAs(bob, HEX + 201, one(b2));
        vm.prank(bob);
        game.transferFrom(bob, carol, b2); // HEX+201 is now undefended
        vm.warp(block.timestamp + 31 minutes); // past the shield

        uint64[] memory trail = ids(HEX + 100, 6);
        uint64[] memory inside = ids(HEX + 200, 2);
        uint64 start = uint64(block.timestamp - 60);
        (uint64 dl, bytes memory sig) = loopSig(alice, start, trail, inside);
        vm.prank(alice);
        uint64[] memory taken = land.claimLoop{value: 1 ether}(start, dl, trail, inside, sig);
        assertEq(taken.length, 7);
        (address o200,,) = land.hexes(HEX + 200);
        (address o201,,) = land.hexes(HEX + 201);
        assertEq(o200, bob);
        assertEq(o201, alice);
    }

    function test_loopIsCutWhenRivalTakesTrailHexMidWalk() public {
        uint64[] memory trail = ids(HEX + 100, 6);
        uint64[] memory inside = ids(HEX + 200, 1);
        uint64 start = uint64(block.timestamp);
        vm.warp(block.timestamp + 120);
        claimAs(bob, HEX + 103, one(strong(bob)));
        (uint64 dl, bytes memory sig) = loopSig(alice, start, trail, inside);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TerrakinTerritory.Cut.selector, HEX + 103));
        land.claimLoop{value: 1 ether}(start, dl, trail, inside, sig);
    }

    function test_loopRejectsForgedOrReplayedSignature() public {
        uint64[] memory trail = ids(HEX + 100, 6);
        uint64[] memory inside = ids(HEX + 200, 1);
        uint64 start = uint64(block.timestamp);
        (uint64 dl, bytes memory sig) = loopSig(alice, start, trail, inside);
        vm.prank(bob); // signed for alice
        vm.expectRevert(TerrakinTerritory.BadSignature.selector);
        land.claimLoop{value: 1 ether}(start, dl, trail, inside, sig);
        inside[0] = HEX + 999; // tampered list
        vm.prank(alice);
        vm.expectRevert(TerrakinTerritory.BadSignature.selector);
        land.claimLoop{value: 1 ether}(start, dl, trail, inside, sig);
    }

    function test_migrateCopiesOwnersOnceThenLocks() public {
        uint256 a = strong(alice);
        uint64[] memory hs = new uint64[](1);
        hs[0] = HEX;
        address[] memory os = new address[](1);
        os[0] = alice;
        uint256[][] memory ds = new uint256[][](1);
        ds[0] = one(a);
        land.migrate(hs, os, ds);
        (address o,,) = land.hexes(HEX);
        assertEq(o, alice);
        assertEq(land.defendersOf(HEX).length, 1);
        land.closeMigration();
        vm.expectRevert(TerrakinTerritory.BadAuction.selector);
        land.migrate(hs, os, ds);
        vm.prank(bob);
        vm.expectRevert();
        land.closeMigration();
    }
}
