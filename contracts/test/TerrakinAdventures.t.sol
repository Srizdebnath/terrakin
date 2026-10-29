// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Terrakin} from "../src/Terrakin.sol";
import {TerrakinCharacters} from "../src/TerrakinCharacters.sol";
import {TerrakinConvergence, IConvergenceGame} from "../src/TerrakinConvergence.sol";
import {TerrakinDrops, IDropsGame} from "../src/TerrakinDrops.sol";

contract AdventuresTest is Test {
    Terrakin game;
    TerrakinConvergence conv;
    TerrakinDrops drops;
    uint256 signerKey = 0xA11CE;
    address signer;
    address[5] p;
    uint256 nonce;
    bytes32 constant EVENT = keccak256("C1:2:20000");
    uint64 opensAt;

    function setUp() public {
        vm.warp(1_800_000_000);
        signer = vm.addr(signerKey);
        Terrakin.Prices memory pr;
        pr.grant = 0.1 ether;
        pr.firstCharacter = 0.05 ether;
        pr.nextCharacter = 0.08 ether;
        pr.orb = [uint128(0.0005 ether), 0.0015 ether, 0.004 ether, 0.03 ether];
        pr.catchReward = [uint128(0.001 ether), 0.002 ether, 0.004 ether, 0.01 ether, 0.025 ether];
        pr.starterOrbs = 50;
        game = new Terrakin(signer, pr);
        game.setCharacters(new TerrakinCharacters(address(game)));
        conv = new TerrakinConvergence(IConvergenceGame(address(game)));
        game.setModule(address(conv), true);
        drops = new TerrakinDrops(IDropsGame(address(game)), IERC721(address(game)), 0.001 ether);
        vm.deal(address(game), 10 ether);
        for (uint256 i; i < 5; ++i) {
            p[i] = makeAddr(string(abi.encode(i)));
            vm.prank(signer);
            game.fund(p[i]);
            vm.deal(p[i], 1 ether);
        }
        opensAt = uint64(block.timestamp);
    }

    // ----------------------------------------------------------- convergence

    function pass(address who) internal view returns (TerrakinConvergence.Pass memory c, bytes memory sig) {
        c = TerrakinConvergence.Pass(who, EVENT, 3, 22544800, 88342600, opensAt, uint64(vm.getBlockTimestamp() + 120));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, conv.passDigest(c));
        sig = abi.encodePacked(r, s, v);
    }

    function joinAs(address who) internal returns (uint256) {
        (TerrakinConvergence.Pass memory c, bytes memory sig) = pass(who);
        vm.prank(who);
        return conv.join(c, sig);
    }

    function test_circleOfThreeEachGetAMythic() public {
        assertEq(joinAs(p[0]), 1);
        vm.warp(block.timestamp + 60);
        assertEq(joinAs(p[1]), 2);
        assertEq(game.balanceOf(p[0]), 0);
        vm.warp(block.timestamp + 60);
        assertEq(joinAs(p[2]), 3);
        for (uint256 i; i < 3; ++i) {
            assertEq(game.balanceOf(p[i]), 1);
            assertTrue(conv.bonded(EVENT, p[i]));
        }
        uint256 id = uint256(keccak256(abi.encode(EVENT, p[0], "converge")));
        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        (, uint256[] memory packed) = game.kinPacked(ids);
        assertEq(uint8(packed[0]), 3); // species
        assertEq(uint8(packed[0] >> 8), 4); // Mythic
        for (uint256 i; i < 4; ++i) assertGe(uint8(packed[0] >> (152 + 8 * i)), 10);

        // A latecomer while the circle still stands bonds straight away.
        vm.warp(block.timestamp + 60);
        assertEq(joinAs(p[3]), 4);
        assertEq(game.balanceOf(p[3]), 1);
    }

    function test_stragglersOutsideFiveMinutesDontCount() public {
        joinAs(p[0]);
        vm.warp(block.timestamp + 6 minutes);
        joinAs(p[1]);
        vm.warp(block.timestamp + 1 minutes);
        assertEq(joinAs(p[2]), 2); // p[0] fell out of the circle
        assertEq(game.balanceOf(p[2]), 0);
        vm.warp(block.timestamp + 1 minutes);
        assertEq(joinAs(p[3]), 3);
        assertEq(game.balanceOf(p[0]), 0); // never in a full circle
        assertEq(game.balanceOf(p[1]), 1);
        assertEq(game.balanceOf(p[2]), 1);
        assertEq(game.balanceOf(p[3]), 1);
    }

    function test_convergenceRules() public {
        joinAs(p[0]);
        (TerrakinConvergence.Pass memory c, bytes memory sig) = pass(p[0]);
        vm.prank(p[0]);
        vm.expectRevert(TerrakinConvergence.AlreadyJoined.selector);
        conv.join(c, sig);

        (c, sig) = pass(p[1]);
        vm.prank(p[2]); // someone else's pass
        vm.expectRevert(TerrakinConvergence.NotYours.selector);
        conv.join(c, sig);

        c.species = 6; // tampered
        vm.prank(p[1]);
        vm.expectRevert(TerrakinConvergence.BadSignature.selector);
        conv.join(c, sig);

        vm.warp(opensAt + 20 minutes);
        (c, sig) = pass(p[1]);
        vm.prank(p[1]);
        vm.expectRevert(TerrakinConvergence.Closed.selector);
        conv.join(c, sig);
    }

    // ---------------------------------------------------------------- drops

    function kin(address who) internal returns (uint256) {
        Terrakin.Bond memory v = Terrakin.Bond({
            player: who,
            spawnId: keccak256(abi.encode(nonce++)),
            species: 1,
            grade: 2,
            vigor: 0x05050505,
            trait: 0,
            landmark: false,
            lat: 22544800,
            lng: 88342600,
            hexId: 7,
            zone: 0,
            deadline: uint64(vm.getBlockTimestamp() + 300)
        });
        (uint8 r8, bytes32 r, bytes32 s) = vm.sign(signerKey, game.bondDigest(v));
        vm.prank(who);
        return game.bond(v, abi.encodePacked(r, s, r8), [uint32(1), 0, 0, 0]);
    }

    function spot(address who, bytes memory sealedSpot)
        internal
        view
        returns (TerrakinDrops.Spot memory s, bytes memory sig)
    {
        s = TerrakinDrops.Spot(who, 77, keccak256(sealedSpot), uint64(vm.getBlockTimestamp() + 120));
        (uint8 v, bytes32 r, bytes32 ss) = vm.sign(signerKey, drops.spotDigest(s));
        sig = abi.encodePacked(r, ss, v);
    }

    function claimSig(address who, uint256 id) internal view returns (TerrakinDrops.Claim memory c, bytes memory sig) {
        c = TerrakinDrops.Claim(who, id, uint64(vm.getBlockTimestamp() + 120));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, drops.claimDigest(c));
        sig = abi.encodePacked(r, s, v);
    }

    function dropAs(address who, uint256 kinId, uint256 mon, address forWho) internal returns (uint256) {
        bytes memory sealedSpot = hex"0102030405";
        (TerrakinDrops.Spot memory s, bytes memory sig) = spot(who, sealedSpot);
        vm.prank(who);
        return drops.drop{value: mon}(s, sig, sealedSpot, "Under the oldest tree", kinId, forWho, uint64(block.timestamp + 1 days));
    }

    function test_dropWithKinAndMonIsFound() public {
        uint256 k = kin(p[0]);
        vm.prank(p[0]);
        game.setApprovalForAll(address(drops), true);
        uint256 id = dropAs(p[0], k, 0.05 ether, address(0));
        assertEq(game.ownerOf(k), address(drops));
        uint64[] memory hs = new uint64[](1);
        hs[0] = 77;
        assertEq(drops.openIn(hs).length, 1);

        (TerrakinDrops.Claim memory c, bytes memory sig) = claimSig(p[1], id);
        uint256 before = p[1].balance;
        vm.prank(p[1]);
        drops.claim(c, sig);
        assertEq(game.ownerOf(k), p[1]);
        assertEq(p[1].balance - before, 0.05 ether);
        assertEq(drops.openIn(hs).length, 0);

        (c, sig) = claimSig(p[2], id);
        vm.prank(p[2]);
        vm.expectRevert(TerrakinDrops.Gone.selector);
        drops.claim(c, sig);
    }

    function test_addressedDropAndOwnDropRules() public {
        uint256 id = dropAs(p[0], 0, 0.01 ether, p[3]);
        (TerrakinDrops.Claim memory c, bytes memory sig) = claimSig(p[1], id);
        vm.prank(p[1]);
        vm.expectRevert(TerrakinDrops.NotYours.selector);
        drops.claim(c, sig);
        (c, sig) = claimSig(p[0], id);
        vm.prank(p[0]);
        vm.expectRevert(TerrakinDrops.NotYours.selector);
        drops.claim(c, sig);
        (c, sig) = claimSig(p[3], id);
        vm.prank(p[3]);
        drops.claim(c, sig);
    }

    function test_dropExpiresAndIsReclaimed() public {
        uint256 id = dropAs(p[0], 0, 0.01 ether, address(0));
        vm.prank(p[0]);
        vm.expectRevert(TerrakinDrops.BadDrop.selector);
        drops.reclaim(id);
        vm.warp(block.timestamp + 1 days + 1);
        (TerrakinDrops.Claim memory c, bytes memory sig) = claimSig(p[1], id);
        vm.prank(p[1]);
        vm.expectRevert(TerrakinDrops.Gone.selector);
        drops.claim(c, sig);
        uint256 before = p[0].balance;
        vm.prank(p[0]);
        drops.reclaim(id);
        assertEq(p[0].balance - before, 0.01 ether);
    }

    function test_dropRejectsTamperedSpotAndEmptyDrops() public {
        (TerrakinDrops.Spot memory s, bytes memory sig) = spot(p[0], hex"0102030405");
        vm.prank(p[0]);
        vm.expectRevert(TerrakinDrops.BadDrop.selector);
        drops.drop{value: 0.01 ether}(s, sig, hex"0102030406", "x", 0, address(0), uint64(block.timestamp + 1 days));
        vm.prank(p[0]);
        vm.expectRevert(TerrakinDrops.BadDrop.selector);
        drops.drop{value: 0}(s, sig, hex"0102030405", "x", 0, address(0), uint64(block.timestamp + 1 days));
        s.hexId = 78;
        vm.prank(p[0]);
        vm.expectRevert(TerrakinDrops.BadSignature.selector);
        drops.drop{value: 0.01 ether}(s, sig, hex"0102030405", "x", 0, address(0), uint64(block.timestamp + 1 days));
    }
}
