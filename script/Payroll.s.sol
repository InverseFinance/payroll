// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Payroll} from "../src/Payroll.sol";

contract CounterScript is Script {
    Payroll public payroll;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        //payroll = new Payroll();

        vm.stopBroadcast();
    }
}
