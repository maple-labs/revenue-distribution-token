// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { TestUtils } from "../../../modules/contract-test-utils/contracts/test.sol";

import { MockERC20 } from "../../../modules/erc20/contracts/test/mocks/MockERC20.sol";

contract InvariantERC20TransferUser is TestUtils {

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

contract InvariantERC20User is TestUtils {

    MockERC20 asset;

    uint256 public amountDeposited;

    constructor(address asset_) {
        asset = MockERC20(asset_);
    }

    function erc20_transfer(address account_, uint256 amount_) external {
        uint256 startingBalance = asset.balanceOf(account_);

        amount_ = constrictToRange(amount_, 1, 1e29);  // 100 billion at WAD precision (1 less than 1e30 to avoid precision issues)

        asset.mint(address(this), amount_);
        asset.transfer(account_, amount_);

        assertEq(asset.balanceOf(account_), startingBalance + amount_);  // Ensure successful transfer
    }

    function erc20_approve(address account_, uint256 amount_) external {
        uint256 startingAllowance = asset.allowance(address(this), account_);

        amount_ = constrictToRange(amount_, 1, 1e29);  // 100 billion at WAD precision (1 less than 1e30 to avoid precision issues)

        asset.mint(address(this), amount_);
        asset.approve(account_, amount_);

        assertEq(asset.allowance(address(this), account_), startingAllowance + amount_);  // Ensure successful transfer
    }

}
