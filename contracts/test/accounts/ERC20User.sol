// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { TestUtils } from "../../../modules/contract-test-utils/contracts/test.sol";

import { MockERC20 } from "../../../modules/erc20/contracts/test/mocks/MockERC20.sol";

contract InvariantERC20User is TestUtils {

    address   rdToken;
    MockERC20 underlying;

    uint256 public amountDeposited;

    constructor(address rdToken_, address underlying_) {
        rdToken    = rdToken_;
        underlying = MockERC20(underlying_);
    }

    function erc20_transfer(uint256 amount_) external {
        uint256 startingBalance = underlying.balanceOf(address(rdToken));

        amount_ = constrictToRange(amount_, 1, 1e29);  // 100 billion at WAD precision (1 less than 1e30 to avoid precision issues)

        underlying.mint(address(this), amount_);
        underlying.transfer(rdToken, amount_);

        assertEq(underlying.balanceOf(address(rdToken)), startingBalance + amount_);  // Ensure successful transfer
    }

}
