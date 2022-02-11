// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { TestUtils } from "../../../lib/contract-test-utils/contracts/test.sol";

import { Vm } from "../../interfaces/Interfaces.sol";

contract Warper is TestUtils {

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function warp(uint256 warpTime_) external {
        vm.warp(block.timestamp + constrictToRange(warpTime_, 1, 100 days));
    }

}