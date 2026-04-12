// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { DIEMPool } from "../src/DIEMPool.sol";

contract DeployScript is Script {
    function run() public {
        // Read config from environment
        address diemToken = vm.envAddress("DIEM_TOKEN");
        address yieldToken = vm.envAddress("YIELD_TOKEN");
        address owner = vm.envAddress("OWNER");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console2.log("Deploying DIEMPool...");
        console2.log("  DIEM Token:", diemToken);
        console2.log("  Yield Token:", yieldToken);
        console2.log("  Owner:", owner);

        vm.startBroadcast(deployerPrivateKey);

        DIEMPool pool = new DIEMPool(diemToken, yieldToken, owner);

        vm.stopBroadcast();

        console2.log("DIEMPool deployed at:", address(pool));
    }
}
