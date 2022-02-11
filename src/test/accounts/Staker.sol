// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { TestUtils } from "../../../lib/contract-test-utils/contracts/test.sol";

import { ERC20User } from "../../../lib/erc20/src/test/accounts/ERC20User.sol";
import { MockERC20 } from "../../../lib/erc20/src/test/mocks/MockERC20.sol";

import { IRevenueDistributionToken as IRDT } from "../../interfaces/IRevenueDistributionToken.sol";

contract Staker is ERC20User {

    function rdToken_deposit(address token, uint256 amount) external {
        IRDT(token).deposit(amount);
    }

    function rdToken_redeem(address token, uint256 amount) external {
        IRDT(token).redeem(amount);
    }

    function rdToken_withdraw(address token, uint256 amount) external {
        IRDT(token).withdraw(amount);
    }

}

contract InvariantStaker is TestUtils {

    IRDT      rdToken;
    MockERC20 underlying;

    constructor(address rdToken_, address underlying_) {
        rdToken    = IRDT(rdToken_);
        underlying = MockERC20(underlying_);
    }

    function deposit(uint256 amount_) external {
        // NOTE: The precision of the exchangeRate is equal to the amount of funds that can be deposited before rounding errors start to arise
        amount_ = constrictToRange(amount_, 1, 1e29);  // 100 billion at WAD precision (1 less than 1e30 to avoid precision issues)

        uint256 beforeBal   = rdToken.balanceOf(address(this));
        uint256 shareAmount = rdToken.previewDeposit(amount_);

        underlying.mint(address(this),       amount_);
        underlying.approve(address(rdToken), amount_);
        rdToken.deposit(amount_);

        assertEq(rdToken.balanceOf(address(this)), beforeBal + shareAmount);  // Ensure successful deposit
    }

    function redeem(uint256 amount_) external {
        uint256 beforeBal    = rdToken.balanceOf(address(this));
        uint256 redeemAmount = amount_ % rdToken.balanceOf(address(this));

        emit log_named_uint("redeemAmount", redeemAmount);

        rdToken.redeem(redeemAmount);

        assertEq(rdToken.balanceOf(address(this)), beforeBal - redeemAmount);
    }

    function withdraw(uint256 amount_) external {
        uint256 beforeBal      = underlying.balanceOf(address(this));
        uint256 withdrawAmount = amount_ % rdToken.balanceOfUnderlying(address(this));

        rdToken.withdraw(withdrawAmount);

        assertEq(underlying.balanceOf(address(this)), beforeBal + withdrawAmount);  // Ensure successful withdraw
    }

}