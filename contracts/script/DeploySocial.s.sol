// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Terrakin} from "../src/Terrakin.sol";
import {TerrakinLab, ITerrakinModules} from "../src/TerrakinLab.sol";
import {TerrakinCrews} from "../src/TerrakinCrews.sol";
import {
    TerrakinSeason, ISeasonGame, ISeasonTerritory, ISeasonLab, ISeasonCrews
} from "../src/TerrakinSeason.sol";

/// Adds Lab v2 (duel stats), Crews and Seasons to a live deployment without
/// touching player state.
/// Env: OPERATOR_KEY, GAME, TERRITORY, OLD_LAB (0 if none).
contract DeploySocial is Script {
    function run() external {
        uint256 key = vm.envUint("OPERATOR_KEY");
        Terrakin game = Terrakin(payable(vm.envAddress("GAME")));
        address territory = vm.envAddress("TERRITORY");
        address oldLab = vm.envOr("OLD_LAB", address(0));

        TerrakinLab.Prices memory l;
        l.fuse = 0.01 ether;
        l.reroll = 0.005 ether;
        l.pack = 0.01 ether;
        l.minStake = 0.005 ether;
        l.duelFeeBps = 500;
        l.jackpotPct = 8;
        l.dudPct = 22;
        l.packSize = 5;

        vm.startBroadcast(key);
        TerrakinLab lab = new TerrakinLab(ITerrakinModules(address(game)), l);
        game.setModule(address(lab), true);
        if (oldLab != address(0)) game.setModule(oldLab, false);
        TerrakinCrews crews = new TerrakinCrews(payable(address(game)), 0.02 ether);
        TerrakinSeason season = new TerrakinSeason(ISeasonGame(address(game)));
        season.setSources(ISeasonTerritory(territory), ISeasonLab(address(lab)), ISeasonCrews(address(crews)));
        season.startSeason(uint40(block.timestamp + 30 days), 100); // 100 Mythics per species
        vm.stopBroadcast();

        console.log("LAB", address(lab));
        console.log("CREWS", address(crews));
        console.log("SEASON", address(season));
    }
}
