// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Terrakin} from "../src/Terrakin.sol";
import {TerrakinCharacters} from "../src/TerrakinCharacters.sol";
import {TerrakinMarket} from "../src/TerrakinMarket.sol";
import {TerrakinBounties} from "../src/TerrakinBounties.sol";
import {TerrakinRaids, IRaidGame} from "../src/TerrakinRaids.sol";

contract CommerceTest is Test {
    Terrakin game;
    TerrakinMarket market;
    TerrakinBounties bounties;
    TerrakinRaids raids;
    uint256 signerKey = 0xA11CE;
    address signer;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    uint256 nonce;
    uint64 constant ZONE = 0x8000_0233_8000_0899;

    function setUp() public {
        vm.warp(1_800_000_000);
        signer = vm.addr(signerKey);
        Terrakin.Prices memory p;
        p.firstCharacter = 0.02 ether;
        p.starterOrbs = 100;
        game = new Terrakin(signer, p);
        game.setCharacters(new TerrakinCharacters(address(game)));
        market = new TerrakinMarket(IERC721(address(game)), 300);
        bounties = new TerrakinBounties(IERC721(address(game)), 300, 0.01 ether);
        raids = new TerrakinRaids(IRaidGame(address(game)), 0.01 ether, 500);
        game.setModule(address(raids), true);
        vm.deal(address(game), 10 ether);
        address[3] memory who = [alice, bob, carol];
        for (uint256 i; i < 3; ++i) {
            vm.prank(signer);
            game.fund(who[i]);
            vm.deal(who[i], 10 ether);
        }
    }

    function kin(address who, uint8 species, uint8 grade, uint32 vigor, int32 lat, int32 lng) internal returns (uint256 id) {
        Terrakin.Bond memory v = Terrakin.Bond({
            player: who,
            spawnId: keccak256(abi.encode(nonce++)),
            species: species,
            grade: grade,
            vigor: vigor,
            trait: 0,
            landmark: false,
            lat: lat,
            lng: lng,
            hexId: 1,
            zone: 0,
            deadline: uint64(vm.getBlockTimestamp() + 300)
        });
        (uint8 r8, bytes32 r, bytes32 s) = vm.sign(signerKey, game.bondDigest(v));
        vm.prank(who);
        id = game.bond(v, abi.encodePacked(r, s, r8), [uint32(1), 0, 0, 0]);
    }

    function list(uint256 a) internal pure returns (uint256[] memory l) {
        l = new uint256[](1);
        l[0] = a;
    }

    // ----------------------------------------------------------------- market

    function test_MarketListBuyAndFees() public {
        uint256 k = kin(alice, 2, 3, 0, 0, 0);
        vm.prank(alice);
        vm.expectRevert(TerrakinMarket.NotApproved.selector);
        market.list(k, 0.5 ether);
        vm.prank(alice);
        game.setApprovalForAll(address(market), true);
        vm.prank(bob);
        vm.expectRevert(TerrakinMarket.NotYours.selector);
        market.list(k, 0.5 ether);
        vm.prank(alice);
        market.list(k, 0.5 ether);

        vm.prank(bob);
        vm.expectRevert(TerrakinMarket.WrongPayment.selector);
        market.buy{value: 0.4 ether}(k);

        uint256 aliceBefore = alice.balance;
        uint256 pool = address(game).balance;
        vm.prank(bob);
        market.buy{value: 0.5 ether}(k);
        assertEq(game.ownerOf(k), bob);
        assertEq(alice.balance - aliceBefore, 0.485 ether);
        assertEq(address(game).balance - pool, 0.015 ether);
        (uint256[] memory ids,,,) = market.all();
        assertEq(ids.length, 0);
    }

    function test_MarketStaleListing() public {
        uint256 k = kin(alice, 2, 3, 0, 0, 0);
        uint256 b = kin(bob, 1, 1, 0, 0, 0);
        vm.startPrank(alice);
        game.setApprovalForAll(address(market), true);
        market.list(k, 0.5 ether);
        bytes32 t = game.proposeTrade(k, b, bob);
        vm.stopPrank();
        vm.prank(bob);
        game.acceptTrade(t);
        (,,, bool[] memory live) = market.all();
        assertFalse(live[0]);
        vm.prank(carol);
        vm.expectRevert(TerrakinMarket.Stale.selector);
        market.buy{value: 0.5 ether}(k);
        vm.prank(carol);
        market.delist(k); // anyone can clear a stale listing
        (uint256[] memory ids,,,) = market.all();
        assertEq(ids.length, 0);
    }

    // --------------------------------------------------------------- bounties

    function test_BountyMatchesAndPays() public {
        // Sealdah-ish, 2 km radius, Shardlet (4), Rare or better.
        int32 lat = 22567900;
        int32 lng = 88370200;
        uint32 cosE6 = 923400;
        vm.prank(alice);
        uint256 id = bounties.post{value: 1 ether}(4, 2, lat, lng, 2000, cosE6, uint40(vm.getBlockTimestamp() + 2 days));

        uint256 tooFar = kin(bob, 4, 3, 0, lat + 30000, lng); // ~3.3 km north
        uint256 wrongSpecies = kin(bob, 3, 3, 0, lat, lng);
        uint256 tooWeak = kin(bob, 4, 1, 0, lat, lng);
        uint256 good = kin(bob, 4, 2, 0, lat + 10000, lng + 10000); // ~1.5 km NE
        assertFalse(bounties.matches(id, tooFar, bob));
        assertFalse(bounties.matches(id, wrongSpecies, bob));
        assertFalse(bounties.matches(id, tooWeak, bob));
        assertTrue(bounties.matches(id, good, bob));
        assertFalse(bounties.matches(id, good, carol), "must be the hunter's");

        vm.prank(bob);
        vm.expectRevert();
        bounties.claim(id, good); // not approved yet
        vm.prank(bob);
        game.setApprovalForAll(address(bounties), true);
        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        bounties.claim(id, good);
        assertEq(game.ownerOf(good), alice, "Kin delivered to the poster");
        assertEq(bob.balance - bobBefore, 0.97 ether);
    }

    function test_BountyOldKinDontCountAndRefund() public {
        uint256 old = kin(bob, 0, 4, 0, 0, 0);
        vm.warp(vm.getBlockTimestamp() + 10);
        vm.prank(alice);
        uint256 id = bounties.post{value: 0.1 ether}(255, 0, 0, 0, 1000, 1_000_000, uint40(vm.getBlockTimestamp() + 2 hours));
        assertFalse(bounties.matches(id, old, bob), "bonded before the bounty");
        vm.prank(alice);
        vm.expectRevert(TerrakinBounties.TooEarly.selector);
        bounties.cancel(id);
        vm.warp(vm.getBlockTimestamp() + 3 hours);
        uint256 before = alice.balance;
        vm.prank(alice);
        bounties.cancel(id);
        assertEq(alice.balance - before, 0.1 ether);
    }

    // ------------------------------------------------------------------ raids

    function pass(address who) internal view returns (TerrakinRaids.Pass memory p, bytes memory sig) {
        p = TerrakinRaids.Pass(who, ZONE, raids.today(), uint64(vm.getBlockTimestamp() + 300));
        (uint8 r8, bytes32 r, bytes32 s) = vm.sign(signerKey, raids.passDigest(p));
        sig = abi.encodePacked(r, s, r8);
    }

    function test_RaidSharedHpPotAndOrbs() public {
        (TerrakinRaids.Pass memory p, bytes memory sig) = pass(alice);
        uint256 a = kin(alice, 6, 4, 0x0F0F0F0F, 0, 0);
        uint256 junk = kin(bob, 0, 0, 0, 0, 0);
        vm.prank(bob);
        vm.expectRevert(TerrakinRaids.BadPass.selector);
        raids.attack{value: 0.01 ether}(p, sig, list(junk));

        uint256 totalA;
        uint256 totalB;
        bool felled;
        uint256 b = kin(bob, 2, 3, 0x0A0A0A0A, 0, 0);
        for (uint256 i; i < 40 && !felled; ++i) {
            vm.prevrandao(bytes32(i));
            address who = i % 2 == 0 ? alice : bob;
            (p, sig) = pass(who);
            vm.prank(who);
            (uint256 dmg, bool f) = raids.attack{value: 0.01 ether}(p, sig, list(who == alice ? a : b));
            assertGt(dmg, 0);
            if (who == alice) totalA += dmg;
            else totalB += dmg;
            felled = f;
        }
        assertTrue(felled, "the boss falls eventually");
        assertEq(totalA + totalB, 8000);
        uint32 day = raids.today();
        (,,, uint128 pot,, bool cleared, address finisher,,) = raids.raidInfo(ZONE, day, alice);
        assertTrue(cleared);
        assertEq(game.orbsOf(finisher)[3], 1, "finisher's Crown Orb");

        uint256 c = kin(carol, 0, 0, 0, 0, 0);
        (p, sig) = pass(carol);
        vm.prank(carol);
        vm.expectRevert(TerrakinRaids.Cleared.selector);
        raids.attack{value: 0.01 ether}(p, sig, list(c));

        uint256 before = alice.balance;
        vm.prank(alice);
        uint256 share = raids.claim(ZONE, day);
        assertEq(alice.balance - before, share);
        assertEq(share, uint256(pot) * totalA / 8000);
        assertEq(game.orbsOf(alice)[2], 1, "everyone's Aurora Orb");
        vm.prank(alice);
        vm.expectRevert(TerrakinRaids.Nothing.selector);
        raids.claim(ZONE, day);
        vm.prank(carol);
        vm.expectRevert(TerrakinRaids.Nothing.selector);
        raids.claim(ZONE, day);
    }

    function test_UnfinishedRaidPaysOutNextDay() public {
        (TerrakinRaids.Pass memory p, bytes memory sig) = pass(alice);
        uint32 day = raids.today();
        uint256 k = kin(alice, 5, 0, 0, 0, 0);
        vm.prank(alice);
        raids.attack{value: 0.01 ether}(p, sig, list(k));
        vm.prank(alice);
        vm.expectRevert(TerrakinRaids.StillOpen.selector);
        raids.claim(ZONE, day);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 before = alice.balance;
        vm.prank(alice);
        raids.claim(ZONE, day);
        assertEq(alice.balance - before, 0.0095 ether, "the whole pot: only attacker");
        assertEq(game.orbsOf(alice)[2], 0, "no orbs if the boss survived");
    }
}
