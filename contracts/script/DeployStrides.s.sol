// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {TerrakinStrides, IStridesGame} from "../src/TerrakinStrides.sol";

/// Walk rewards: 0.01 MON per 500 m, up to 10 km a day, with a starting pool.
/// Env: OPERATOR_KEY, GAME, POOL (wei to seed the pool with).
contract DeployStrides is Script {
    function run() external {
        uint256 key = vm.envUint("OPERATOR_KEY");
        vm.startBroadcast(key);
        TerrakinStrides strides =
            new TerrakinStrides(IStridesGame(vm.envAddress("GAME")), TerrakinStrides.Rules(0.01 ether, 20));
        (bool ok,) = address(strides).call{value: vm.envUint("POOL")}("");
        require(ok, "seed pool");
        vm.stopBroadcast();
        console.log("STRIDES", address(strides));
    }
}
