// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { TestUtils } from "../../../lib/contract-test-utils/contracts/test.sol";

contract Warper is TestUtils {

    function warp(uint256 warpTime_) external {
        vm.warp(block.timestamp + constrictToRange(warpTime_, 1, 100 days));
    }

}
