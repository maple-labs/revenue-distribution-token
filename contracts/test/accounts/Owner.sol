// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { TestUtils } from "../../../modules/contract-test-utils/contracts/test.sol";

import { IERC20 }    from "../../../modules/erc20/contracts/interfaces/IERC20.sol";
import { MockERC20 } from "../../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { IRevenueDistributionToken as IRDT } from "../../interfaces/IRevenueDistributionToken.sol";

contract Owner {

    function rdToken_acceptOwnership(address rdt_) external {
        IRDT(rdt_).acceptOwnership();
    }

    function rdToken_setPendingOwner(address rdt_, address pendingOwner_) external {
        IRDT(rdt_).setPendingOwner(pendingOwner_);
    }

    function rdToken_updateVestingSchedule(address rdt_, uint256 vestingPeriod_) external {
        IRDT(rdt_).updateVestingSchedule(vestingPeriod_);
    }

    function erc20_transfer(address token_, address receiver_, uint256 amount_) external {
        IERC20(token_).transfer(receiver_, amount_);
    }

}

contract InvariantOwner is TestUtils {

    IRDT      rdToken;
    MockERC20 underlying;

    uint256 numberOfCalls;

    uint256 public amountDeposited;

    constructor(address rdToken_, address underlying_) {
        rdToken    = IRDT(rdToken_);
        underlying = MockERC20(underlying_);
    }

    function rdToken_updateVestingSchedule(uint256 vestingPeriod_) external {
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1, 10_000 days);

        rdToken.updateVestingSchedule(vestingPeriod_);

        assertEq(rdToken.vestingPeriodFinish(), block.timestamp + vestingPeriod_);
    }

    function erc20_transfer(uint256 amount_) external {
        uint256 beforeBal = underlying.balanceOf(address(rdToken));

        amount_ = constrictToRange(amount_, 1, 1e29);  // 100 billion at WAD precision (1 less than 1e30 to avoid precision issues)
        underlying.mint(address(this), amount_);
        underlying.transfer(address(rdToken), amount_);

        assertEq(underlying.balanceOf(address(rdToken)), beforeBal + amount_);  // Ensure successful transfer
    }

}
