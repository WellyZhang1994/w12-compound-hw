// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "forge-std/script.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyScript is Script {
    function run() external {
        vm.startBroadcast();
        ERC20 simpleToken = new ERC20("WELLYGO","WEG");
        vm.stopBroadcast();
    }
}