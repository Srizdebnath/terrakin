// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Terrakin} from "../src/Terrakin.sol";
import {TerrakinCharacters} from "../src/TerrakinCharacters.sol";
import {TerrakinLab, ITerrakinModules} from "../src/TerrakinLab.sol";
import {TerrakinCrews} from "../src/TerrakinCrews.sol";
import {
    TerrakinSeason, ISeasonGame, ISeasonTerritory, ISeasonLab, ISeasonCrews
} from "../src/TerrakinSeason.sol";

contract SocialTest is Test {
    Terrakin game;
    TerrakinLab lab;
    TerrakinCrews crews;
    TerrakinSeason season;
    uint256 signerKey = 0xA11CE;
    address signer;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    function setUp() public {
        signer = vm.addr(signerKey);
        Terrakin.Prices memory p;
        p.firstCharacter = 0.02 ether;
        game = new Terrakin(signer, p);
        game.setCharacters(new TerrakinCharacters(address(game)));
        TerrakinLab.Prices memory l;
        l.minStake = 0.005 ether;
        lab = new TerrakinLab(ITerrakinModules(address(game)), l);
        crews = new TerrakinCrews(payable(address(game)), 0.02 ether);
        season = new TerrakinSeason(ISeasonGame(address(game)));
        season.setSources(ISeasonTerritory(address(0)), ISeasonLab(address(lab)), ISeasonCrews(address(crews)));
        season.startSeason(uint40(vm.getBlockTimestamp() + 30 days), 3);
        address[3] memory who = [alice, bob, carol];
        string[3] memory names = ["alice", "bobby", "carol"];
        for (uint256 i; i < 3; ++i) {
            vm.deal(who[i], 10 ether);
            vm.prank(who[i]);
            game.createProfile{value: 0.02 ether}(names[i], 0);
        }
    }

    // ---------------------------------------------------------------- seasons

    function test_MythicCapIsNumberedIdempotentAndSellsOut() public {
        vm.expectRevert(TerrakinSeason.NotSigner.selector);
        season.reserveMythic(alice, 3, "a");

        vm.startPrank(signer);
        assertEq(season.reserveMythic(alice, 3, "a"), 1);
        assertEq(season.reserveMythic(alice, 3, "a"), 1, "same spawn keeps its number");
        assertEq(season.reserveMythic(bob, 3, "a"), 2, "same spawn, other player");
        assertEq(season.reserveMythic(carol, 3, "c"), 3);
        vm.expectRevert(TerrakinSeason.SoldOut.selector);
        season.reserveMythic(carol, 3, "d");
        assertEq(season.reserveMythic(carol, 4, "d"), 1, "caps are per species");
        vm.stopPrank();

        (uint32 s, uint16[7] memory minted, uint16 cap,,) = season.mythicCounts();
        assertEq(s, 1);
        assertEq(minted[3], 3);
        assertEq(minted[4], 1);
        assertEq(cap, 3);
        assertEq(season.mythicsOf(1, carol), 2);

        // A new season resets the counts.
        season.startSeason(uint40(vm.getBlockTimestamp() + 30 days), 3);
        vm.prank(signer);
        assertEq(season.reserveMythic(carol, 3, "d"), 1);
    }

    function test_NoMythicsAfterSeasonEnds() public {
        vm.warp(vm.getBlockTimestamp() + 31 days);
        vm.prank(signer);
        vm.expectRevert(TerrakinSeason.SeasonOver.selector);
        season.reserveMythic(alice, 0, "x");
    }

    function test_LeaderboardAggregatesStats() public {
        season.enroll(); // a stranger can enrol themselves
        vm.prank(signer);
        season.enrollFor(alice);
        vm.prank(signer);
        season.enrollFor(alice); // twice is a no-op
        vm.prank(alice);
        season.enroll();
        vm.prank(signer);
        season.enrollFor(bob);
        assertEq(season.playerCount(), 3);

        vm.prank(signer);
        season.reserveMythic(bob, 1, "m");
        vm.prank(bob);
        uint256 crewId = crews.create{value: 0.02 ether}("Ranaghat Rangers", "rng");

        (address[] memory who, string[] memory names,, uint256[] memory kin, uint256[] memory mythics,, uint256[] memory crew)
        = season.leaderboard(1, 10);
        assertEq(who.length, 2);
        assertEq(who[0], alice);
        assertEq(names[0], "alice");
        assertEq(names[1], "bobby");
        assertEq(kin[0], 0);
        assertEq(mythics[1], 1);
        assertEq(crew[1], crewId);
        assertEq(crew[0], 0);

        (who,,,,,,) = season.leaderboard(5, 10);
        assertEq(who.length, 0);
    }

    // ------------------------------------------------------------------ crews

    function test_CrewLifecycle() public {
        vm.prank(alice);
        vm.expectRevert(TerrakinCrews.WrongPayment.selector);
        crews.create{value: 0.01 ether}("Kolkata Kings", "KOL");

        uint256 pool = address(game).balance;
        vm.prank(alice);
        uint256 id = crews.create{value: 0.02 ether}("Kolkata Kings", "kol");
        assertEq(address(game).balance - pool, 0.02 ether, "creation fee funds the pool");
        (TerrakinCrews.Crew memory c,) = crews.crew(id);
        assertEq(c.tag, "KOL");
        assertEq(c.captain, alice);

        vm.prank(bob);
        vm.expectRevert(TerrakinCrews.TagTaken.selector);
        crews.create{value: 0.02 ether}("Other", "KoL");
        vm.prank(bob);
        vm.expectRevert(TerrakinCrews.BadName.selector);
        crews.create{value: 0.02 ether}("Other", "K!");

        vm.prank(bob);
        crews.join(id);
        vm.prank(carol);
        crews.join(id);
        vm.prank(bob);
        vm.expectRevert(TerrakinCrews.InCrew.selector);
        crews.join(id);

        // Treasury: deposits, then the captain splits it.
        vm.prank(bob);
        crews.deposit{value: 0.3 ether}();
        vm.prank(bob);
        vm.expectRevert(TerrakinCrews.NotCaptain.selector);
        crews.payout();
        uint256 carolBefore = carol.balance;
        vm.prank(alice);
        crews.payout();
        assertEq(carol.balance - carolBefore, 0.1 ether);

        // Captain leaves: the longest-serving member takes over.
        vm.prank(alice);
        crews.leave();
        (c,) = crews.crew(id);
        assertEq(c.captain, bob);
        vm.prank(bob);
        crews.kick(carol);
        assertEq(crews.crewOf(carol), 0);

        // Last one out takes the treasury.
        vm.prank(bob);
        crews.deposit{value: 0.05 ether}();
        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        crews.leave();
        assertEq(bob.balance - bobBefore, 0.05 ether);

        uint256[] memory ids = crews.crewsOf(_three());
        assertEq(ids[0] + ids[1] + ids[2], 0);
        (string[] memory names, string[] memory tags,, uint256[] memory sizes) = crews.crews(0, 10);
        assertEq(names[0], "Kolkata Kings");
        assertEq(tags[0], "KOL");
        assertEq(sizes[0], 0);
    }

    function test_CrewIsCappedAtThirty() public {
        vm.prank(alice);
        uint256 id = crews.create{value: 0.02 ether}("Big Crew", "BIG");
        for (uint256 i; i < 29; ++i) {
            vm.prank(address(uint160(1000 + i)));
            crews.join(id);
        }
        vm.prank(bob);
        vm.expectRevert(TerrakinCrews.Full.selector);
        crews.join(id);
    }

    function _three() internal view returns (address[] memory l) {
        l = new address[](3);
        (l[0], l[1], l[2]) = (alice, bob, carol);
    }
}
