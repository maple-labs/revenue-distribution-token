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

    function rdToken_updateVestingSchedule(address rdt_, uint256 vestingPeriod_) external returns (uint256 issuanceRate_, uint256 freeAssets_) {
        return IRDT(rdt_).updateVestingSchedule(vestingPeriod_);
    }

    function erc20_transfer(address token_, address receiver_, uint256 amount_) external returns (bool success_) {
        return IERC20(token_).transfer(receiver_, amount_);
    }

}

contract InvariantOwner is TestUtils {

    IRDT      internal _rdToken;
    MockERC20 internal _underlying;

    uint256 numberOfCalls;

    uint256 public amountDeposited;

    constructor(address rdToken_, address underlying_) {
        _rdToken    = IRDT(rdToken_);
        _underlying = MockERC20(underlying_);
    }

    function rdToken_updateVestingSchedule(uint256 vestingPeriod_) external {
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1, 10_000 days);

        _rdToken.updateVestingSchedule(vestingPeriod_);

        assertEq(_rdToken.vestingPeriodFinish(), block.timestamp + vestingPeriod_);
    }

    function erc20_transfer(uint256 amount_) external {
        uint256 startingBalance = _underlying.balanceOf(address(_rdToken));

        amount_ = constrictToRange(amount_, 1, 1e29);  // 100 billion at WAD precision (1 less than 1e30 to avoid precision issues)

        _underlying.mint(address(this), amount_);
        _underlying.transfer(address(_rdToken), amount_);

        assertEq(_underlying.balanceOf(address(_rdToken)), startingBalance + amount_);  // Ensure successful transfer
    }

}
