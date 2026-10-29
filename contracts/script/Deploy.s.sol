// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Terrakin} from "../src/Terrakin.sol";
import {TerrakinCharacters} from "../src/TerrakinCharacters.sol";
import {TerrakinTerritory, ITerrakin} from "../src/TerrakinTerritory.sol";
import {ITerritory} from "../src/Terrakin.sol";
import {TerrakinLab, ITerrakinModules} from "../src/TerrakinLab.sol";

/// forge script script/Deploy.s.sol --rpc-url monad_testnet --broadcast
/// Env: OPERATOR_KEY (deployer, owner and voucher signer), POOL (wei to seed the reward pool).
contract Deploy is Script {
    function run() external {
        uint256 key = vm.envUint("OPERATOR_KEY");
        address operator = vm.addr(key);

        // A 0.2 MON grant covers a profile, a few catches and a hex claim at
        // Monad testnet gas (~0.02 MON per catch). Adjustable with setPrices().
        Terrakin.Prices memory p;
        p.grant = 0.2 ether;
        p.firstCharacter = 0.02 ether;
        p.nextCharacter = 0.08 ether;
        p.tradeReward = 0.01 ether;
        p.orb = [uint128(0.0005 ether), 0.0015 ether, 0.004 ether, 0.03 ether];
        p.catchReward = [uint128(0.03 ether), 0.05 ether, 0.1 ether, 0.25 ether, 0.8 ether]; // above gas, so catching pays
        p.starterOrbs = 10;
        p.rewardedTradesPerDay = 3;

        TerrakinTerritory.Prices memory t;
        t.claim = 0.01 ether;
        t.attackFee = 0.004 ether;
        t.minBid = 0.005 ether;
        t.cutBps = 1000; // 10% of catch rewards in an owned hex
        t.landmarkCutBps = 2500; // 25% of Landmark catches to the zone's auction winner
        t.bidStepBps = 500;
        t.shield = 30 minutes;
        t.loopPerHex = 0.002 ether;

        TerrakinLab.Prices memory l;
        l.fuse = 0.01 ether;
        l.reroll = 0.005 ether;
        l.pack = 0.01 ether;
        l.minStake = 0.005 ether;
        l.duelFeeBps = 500; // 5% of each duel pot to the reward pool
        l.jackpotPct = 8;
        l.dudPct = 22;
        l.packSize = 5;

        vm.startBroadcast(key);
        Terrakin game = new Terrakin(operator, p);
        TerrakinCharacters chars = new TerrakinCharacters(address(game));
        game.setCharacters(chars);
        TerrakinTerritory land = new TerrakinTerritory(ITerrakin(address(game)), t);
        game.setTerritory(ITerritory(address(land)));
        TerrakinLab lab = new TerrakinLab(ITerrakinModules(address(game)), l);
        game.setModule(address(lab), true);
        uint256 pool = vm.envOr("POOL", uint256(0));
        if (pool > 0) {
            (bool ok,) = address(game).call{value: pool}("");
            require(ok, "pool");
        }
        vm.stopBroadcast();

        console.log("GAME", address(game));
        console.log("CHARACTERS", address(chars));
        console.log("TERRITORY", address(land));
        console.log("LAB", address(lab));
    }
}
