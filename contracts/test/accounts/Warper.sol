// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { TestUtils } from "../../../modules/contract-test-utils/contracts/test.sol";
import { console }   from "../../../modules/contract-test-utils/contracts/log.sol";

import { IRevenueDistributionToken } from "../../interfaces/IRevenueDistributionToken.sol";

contract Warper is TestUtils {

    address internal _rdt;

    constructor(address rdt_) {
        _rdt = rdt_;
    }

    function warp(uint256 warpTime_) external {
        vm.warp(block.timestamp + constrictToRange(warpTime_, 1, 100 days));
        console.log("warp");
        // revert();
    }

    function warpAfterVesting(uint256 warpTime_) external {
        vm.warp(block.timestamp + IRevenueDistributionToken(_rdt).vestingPeriodFinish() + constrictToRange(warpTime_, 1, 100 days));
        console.log("warpAfterVesting");
        // revert();
    }

}
