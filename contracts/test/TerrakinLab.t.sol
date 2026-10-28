// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Terrakin} from "../src/Terrakin.sol";
import {TerrakinCharacters} from "../src/TerrakinCharacters.sol";
import {TerrakinLab, ITerrakinModules} from "../src/TerrakinLab.sol";

contract LabTest is Test {
    Terrakin game;
    TerrakinLab lab;
    uint256 signerKey = 0xA11CE;
    address signer;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    uint256 nonce;

    function setUp() public {
        signer = vm.addr(signerKey);
        Terrakin.Prices memory p;
        p.grant = 0.2 ether;
        p.firstCharacter = 0.02 ether;
        p.nextCharacter = 0.08 ether;
        p.catchReward = [uint128(0.03 ether), 0.05 ether, 0.1 ether, 0.25 ether, 0.8 ether];
        p.orb = [uint128(0.0005 ether), 0.0015 ether, 0.004 ether, 0.03 ether];
        p.starterOrbs = 1000;
        game = new Terrakin(signer, p);
        game.setCharacters(new TerrakinCharacters(address(game)));
        lab = new TerrakinLab(ITerrakinModules(address(game)), labPrices());
        game.setModule(address(lab), true);
        vm.deal(address(game), 100 ether);
        for (uint256 i; i < 2; ++i) {
            address who = [alice, bob][i];
            vm.prank(signer);
            game.fund(who);
            vm.deal(who, 10 ether);
        }
    }

    function labPrices() internal pure returns (TerrakinLab.Prices memory t) {
        t.fuse = 0.01 ether;
        t.reroll = 0.005 ether;
        t.pack = 0.01 ether;
        t.minStake = 0.005 ether;
        t.duelFeeBps = 500;
        t.jackpotPct = 8;
        t.dudPct = 22;
        t.packSize = 5;
    }

    function kin(address who, uint8 grade, uint32 vigor) internal returns (uint256 id) {
        Terrakin.Bond memory v = Terrakin.Bond({
            player: who,
            spawnId: keccak256(abi.encode(nonce++)),
            species: uint8(nonce % 7),
            grade: grade,
            vigor: vigor,
            trait: 1,
            landmark: false,
            lat: -33868800,
            lng: 151209300,
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

    function test_ModulesOnlyOwnerSet() public {
        vm.prank(alice);
        vm.expectRevert();
        game.setModule(alice, true);
        vm.prank(alice);
        vm.expectRevert(Terrakin.NotYours.selector);
        game.moduleBurn(1);
    }

    function test_FusionBurnsParentsAndRollsGrades() public {
        uint256 jackpots;
        uint256 duds;
        for (uint256 i; i < 60; ++i) {
            vm.prevrandao(bytes32(i * 7919));
            uint256 a = kin(alice, 1, 0x0A0A0A0A);
            uint256 b = kin(alice, 2, 0x02030405);
            uint256 pool = address(game).balance;
            vm.prank(alice);
            (uint256 id, TerrakinLab.Fusion o) = lab.fuse{value: 0.01 ether}(a, b);
            assertEq(address(game).balance, pool + 0.01 ether);
            vm.expectRevert();
            game.ownerOf(a);
            assertEq(game.ownerOf(id), alice);
            Terrakin.Kin memory k = game.kin(id);
            if (o == TerrakinLab.Fusion.Jackpot) {
                assertEq(k.grade, 3);
                jackpots++;
            } else if (o == TerrakinLab.Fusion.Dud) {
                assertEq(k.grade, 1);
                duds++;
            } else {
                assertEq(k.grade, 2);
            }
            assertEq(k.lat, -33868800, "origin kept");
            for (uint256 s; s < 4; ++s) {
                assertLe(k.vigor[s], 15);
                assertEq(k.mods[s], 10000);
            }
        }
        assertGt(jackpots, 0, "some jackpots");
        assertGt(duds, 0, "some duds");
        assertLt(jackpots, duds, "jackpots rarer than duds");
    }

    function test_FusionNeedsOwnTwoAndFee() public {
        uint256 a = kin(alice, 0, 0);
        uint256 b = kin(bob, 0, 0);
        vm.prank(alice);
        vm.expectRevert(TerrakinLab.NotYours.selector);
        lab.fuse{value: 0.01 ether}(a, b);
        vm.prank(alice);
        vm.expectRevert(TerrakinLab.BadSquad.selector);
        lab.fuse{value: 0.01 ether}(a, a);
        uint256 c = kin(alice, 0, 0);
        vm.prank(alice);
        vm.expectRevert(TerrakinLab.WrongPayment.selector);
        lab.fuse{value: 0.001 ether}(a, c);
    }

    function test_RerollChangesOnlyVigor() public {
        uint256 a = kin(alice, 3, 0x01010101);
        Terrakin.Kin memory before = game.kin(a);
        vm.prevrandao(bytes32(uint256(42)));
        vm.prank(alice);
        uint32 v = lab.reroll{value: 0.005 ether}(a);
        Terrakin.Kin memory k = game.kin(a);
        assertEq(k.grade, before.grade);
        assertEq(k.species, before.species);
        assertEq(k.bondedAt, before.bondedAt);
        for (uint256 s; s < 4; ++s) {
            assertLe(k.vigor[s], 15);
            assertEq(k.vigor[s], uint8(v >> (8 * s)));
        }
        vm.prank(bob);
        vm.expectRevert(TerrakinLab.NotYours.selector);
        lab.reroll{value: 0.005 ether}(a);
    }

    function test_PackGivesFiveOrbsWithRareCrowns() public {
        uint256 crowns;
        uint256 seeds;
        for (uint256 i; i < 100; ++i) {
            vm.prevrandao(bytes32(i));
            vm.prank(alice);
            uint32[4] memory o = lab.openPack{value: 0.01 ether}();
            assertEq(o[0] + o[1] + o[2] + o[3], 5);
            crowns += o[3];
            seeds += o[0];
        }
        uint32[4] memory bag = game.orbsOf(alice);
        assertEq(bag[0] + bag[1] + bag[2] + bag[3], 1000 + 500); // starter + packs
        assertGt(seeds, 250, "~70% seeds");
        assertLt(crowns, 40, "~2% crowns");
    }

    function test_DuelPaysWinnerAndRefundsOnCancel() public {
        uint256 a = kin(alice, 4, 0x0F0F0F0F); // Mythic, perfect vigor
        uint256 b = kin(bob, 0, 0); // Common, zero vigor
        vm.prank(alice);
        uint256 id = lab.createDuel{value: 0.1 ether}(list(a));
        (uint256[] memory ids,, uint256[] memory stakes,) = lab.openDuels();
        assertEq(ids.length, 1);
        assertEq(stakes[0], 0.1 ether);

        vm.prank(alice);
        vm.expectRevert(TerrakinLab.NotYours.selector);
        lab.acceptDuel{value: 0.1 ether}(id, list(a));
        vm.prank(bob);
        vm.expectRevert(TerrakinLab.WrongPayment.selector);
        lab.acceptDuel{value: 0.05 ether}(id, list(b));

        uint256 aliceBefore = alice.balance;
        uint256 pool = address(game).balance;
        vm.prank(bob);
        bool bobWon = lab.acceptDuel{value: 0.1 ether}(id, list(b));
        assertFalse(bobWon, "a Mythic beats a zero-vigor Common");
        assertEq(lab.duelWins(alice), 1);
        assertEq(lab.duelLosses(bob), 1);
        assertEq(alice.balance - aliceBefore, 0.19 ether, "pot minus 5%");
        assertEq(address(game).balance - pool, 0.01 ether, "house fee to pool");
        (ids,,,) = lab.openDuels();
        assertEq(ids.length, 0);

        vm.prank(bob);
        uint256 id2 = lab.createDuel{value: 0.02 ether}(list(b));
        uint256 bobBefore = bob.balance;
        vm.prank(alice);
        vm.expectRevert(TerrakinLab.NoDuel.selector);
        lab.cancelDuel(id2);
        vm.prank(bob);
        lab.cancelDuel(id2);
        assertEq(bob.balance - bobBefore, 0.02 ether);
    }

    function test_StaleDuelAfterFusion() public {
        uint256 a = kin(alice, 0, 0);
        uint256 a2 = kin(alice, 0, 0);
        vm.prank(alice);
        uint256 id = lab.createDuel{value: 0.01 ether}(list(a));
        vm.prank(alice);
        lab.fuse{value: 0.01 ether}(a, a2);
        uint256 b = kin(bob, 0, 0);
        vm.prank(bob);
        vm.expectRevert(TerrakinLab.StaleDuel.selector);
        lab.acceptDuel{value: 0.01 ether}(id, list(b));
    }
}
