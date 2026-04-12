// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { DIEMPool } from "../src/DIEMPool.sol";

contract DeployScript is Script {
    // DIEM token on Base mainnet
    address constant DIEM_BASE = 0xF4d97F2da56e8c3098f3a8D538DB630A2606a024;

    // USDC on Base mainnet
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function run() public {
        // Read config from environment
        address diem = vm.envOr("DIEM_TOKEN", DIEM_BASE);
        address yieldToken = vm.envOr("YIELD_TOKEN", USDC_BASE);
        address owner = vm.envAddress("OWNER");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console2.log("Deploying DIEMPool...");
        console2.log("  DIEM Token:", diem);
        console2.log("  Yield Token:", yieldToken);
        console2.log("  Owner:", owner);

        vm.startBroadcast(deployerPrivateKey);

        DIEMPool pool = new DIEMPool(diem, yieldToken, owner);

        vm.stopBroadcast();

        console2.log("DIEMPool deployed at:", address(pool));
    }
}

contract DeployTestnet is Script {
    // For Base Sepolia testnet - these would need to be deployed or mocked
    function run() public {
        address diem = vm.envAddress("DIEM_TOKEN");
        address yieldToken = vm.envAddress("YIELD_TOKEN");
        address owner = vm.envAddress("OWNER");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console2.log("Deploying DIEMPool to testnet...");
        console2.log("  DIEM Token:", diem);
        console2.log("  Yield Token:", yieldToken);
        console2.log("  Owner:", owner);

        vm.startBroadcast(deployerPrivateKey);

        DIEMPool pool = new DIEMPool(diem, yieldToken, owner);

        vm.stopBroadcast();

        console2.log("DIEMPool deployed at:", address(pool));
    }
}
