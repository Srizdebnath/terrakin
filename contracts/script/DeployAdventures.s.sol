// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Terrakin, ITerritory} from "../src/Terrakin.sol";
import {TerrakinTerritory, ITerrakin} from "../src/TerrakinTerritory.sol";
import {TerrakinConvergence, IConvergenceGame} from "../src/TerrakinConvergence.sol";
import {TerrakinDrops, IDropsGame} from "../src/TerrakinDrops.sol";
import {TerrakinSeason, ISeasonTerritory, ISeasonLab, ISeasonCrews} from "../src/TerrakinSeason.sol";

/// Loop Capture (territory v2, same prices plus loopPerHex), Convergence and
/// Dead Drops. Hex ownership is copied from v1 afterwards with migrate().
/// Env: OPERATOR_KEY, GAME, TERRITORY (v1), SEASON, LAB, CREWS.
contract DeployAdventures is Script {
    function run() external {
        uint256 key = vm.envUint("OPERATOR_KEY");
        Terrakin game = Terrakin(payable(vm.envAddress("GAME")));
        TerrakinTerritory v1 = TerrakinTerritory(vm.envAddress("TERRITORY"));
        TerrakinSeason season = TerrakinSeason(vm.envAddress("SEASON"));

        (bool ok, bytes memory raw) = address(v1).staticcall(abi.encodeWithSignature("prices()"));
        require(ok, "v1 prices");
        (uint128 claim, uint128 attackFee, uint128 minBid, uint16 cutBps, uint16 landmarkCutBps, uint16 bidStepBps, uint32 shield) =
            abi.decode(raw, (uint128, uint128, uint128, uint16, uint16, uint16, uint32));
        TerrakinTerritory.Prices memory p = TerrakinTerritory.Prices(
            claim, attackFee, minBid, cutBps, landmarkCutBps, bidStepBps, shield, 0.002 ether
        );

        vm.startBroadcast(key);
        TerrakinTerritory land = new TerrakinTerritory(ITerrakin(address(game)), p);
        game.setTerritory(ITerritory(address(land)));
        season.setSources(
            ISeasonTerritory(address(land)), ISeasonLab(vm.envAddress("LAB")), ISeasonCrews(vm.envAddress("CREWS"))
        );
        TerrakinConvergence conv = new TerrakinConvergence(IConvergenceGame(address(game)));
        game.setModule(address(conv), true); // mints the Mythics
        TerrakinDrops drops = new TerrakinDrops(IDropsGame(address(game)), IERC721(address(game)), 0.001 ether);
        vm.stopBroadcast();
        console.log("TERRITORY", address(land));
        console.log("CONVERGENCE", address(conv));
        console.log("DROPS", address(drops));
    }
}
