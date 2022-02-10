// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { ERC20User } from "lib/erc20/src/test/accounts/ERC20User.sol";
import { MockERC20 } from "lib/erc20/src/test/mocks/MockERC20.sol";

import { TestUtils } from "lib/contract-test-utils/contracts/test.sol";

import { IRevenueDistributionToken } from "../../interfaces/IRevenueDistributionToken.sol";

contract Staker is ERC20User {

    function rdToken_deposit(address token, uint256 amount) external {
        IRevenueDistributionToken(token).deposit(amount);
    }

    function rdToken_redeem(address token, uint256 amount) external {
        IRevenueDistributionToken(token).redeem(amount);
    }

    function rdToken_withdraw(address token, uint256 amount) external {
        IRevenueDistributionToken(token).withdraw(amount);
    }

}

contract InvariantStaker is TestUtils {

    IRevenueDistributionToken rdToken;
    MockERC20                 underlying;

    uint256 public amountDeposited;

    constructor(address rdToken_, address underlying_) {
        rdToken    = IRevenueDistributionToken(rdToken_);
        underlying = MockERC20(underlying_);
    }

    function deposit(uint256 amount_) external {
        amount_ = constrictToRange(amount_, 1, 1e45);

        underlying.mint(address(this),       amount_);
        underlying.approve(address(rdToken), amount_);
        rdToken.deposit(amount_);

        amountDeposited += amount_;
    }

    // function redeem(uint256 amount_) external {
    //     rdToken_redeem(rdToken, amount_);
    //     amountDeposited += amount_;
    // }

    // function withdraw(uint256 amount_) external {
    //     rdToken_withdraw(rdToken, amount_);
    //     amountDeposited -= amount_;
    // }

}