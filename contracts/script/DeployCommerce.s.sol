// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Terrakin} from "../src/Terrakin.sol";
import {TerrakinMarket} from "../src/TerrakinMarket.sol";
import {TerrakinBounties} from "../src/TerrakinBounties.sol";
import {TerrakinRaids, IRaidGame} from "../src/TerrakinRaids.sol";

/// Adds the Kin market, bounties and Landmark raids to a live deployment.
/// Env: OPERATOR_KEY, GAME.
contract DeployCommerce is Script {
    function run() external {
        uint256 key = vm.envUint("OPERATOR_KEY");
        Terrakin game = Terrakin(payable(vm.envAddress("GAME")));
        vm.startBroadcast(key);
        TerrakinMarket market = new TerrakinMarket(IERC721(address(game)), 300); // 3% to the pool
        TerrakinBounties bounties = new TerrakinBounties(IERC721(address(game)), 300, 0.01 ether);
        TerrakinRaids raids = new TerrakinRaids(IRaidGame(address(game)), 0.01 ether, 500); // 5% house
        game.setModule(address(raids), true); // raids award orbs
        vm.stopBroadcast();
        console.log("MARKET", address(market));
        console.log("BOUNTIES", address(bounties));
        console.log("RAIDS", address(raids));
    }
}
