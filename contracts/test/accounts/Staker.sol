// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { TestUtils } from "../../../modules/contract-test-utils/contracts/test.sol";

import { ERC20User } from "../../../modules/erc20/contracts/test/accounts/ERC20User.sol";
import { MockERC20 } from "../../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { IRevenueDistributionToken as IRDT } from "../../interfaces/IRevenueDistributionToken.sol";

contract Staker is ERC20User {

    function rdToken_deposit(address token_, uint256 assets_) external returns (uint256 shares_) {
        return IRDT(token_).deposit(assets_, address(this));
    }

    function rdToken_redeem(address token_, uint256 shares_) external returns (uint256 assets_) {
        return IRDT(token_).redeem(shares_, address(this), address(this));
    }

    function rdToken_redeem(address token_, uint256 shares_, address recipient_, address owner_) external returns (uint256 assets_) {
        return IRDT(token_).redeem(shares_, recipient_, owner_);
    }

    function rdToken_withdraw(address token_, uint256 assets_) external returns (uint256 shares_) {
        return IRDT(token_).withdraw(assets_, address(this), address(this));
    }

    function rdToken_withdraw(address token_, uint256 assets_, address recipient_, address owner_) external returns (uint256 shares_) {
        return IRDT(token_).withdraw(assets_, recipient_, owner_);
    }

}

contract InvariantStaker is TestUtils {

    IRDT      rdToken;
    MockERC20 underlying;

    constructor(address rdToken_, address underlying_) {
        rdToken    = IRDT(rdToken_);
        underlying = MockERC20(underlying_);
    }

    function deposit(uint256 assets_) external {
        // NOTE: The precision of the exchangeRate is equal to the amount of funds that can be deposited before rounding errors start to arise
        assets_ = constrictToRange(assets_, 1, 1e29);  // 100 billion at WAD precision (1 less than 1e30 to avoid precision issues)

        uint256 beforeBal   = rdToken.balanceOf(address(this));
        uint256 shareAmount = rdToken.previewDeposit(assets_);

        underlying.mint(address(this),       assets_);
        underlying.approve(address(rdToken), assets_);
        rdToken.deposit(assets_, address(this));

        assertEq(rdToken.balanceOf(address(this)), beforeBal + shareAmount);  // Ensure successful deposit
    }

    function redeem(uint256 shares_) external {
        uint256 beforeBal = rdToken.balanceOf(address(this));

        if (beforeBal > 0) {
            uint256 redeemAmount = constrictToRange(shares_, 1, rdToken.balanceOf(address(this)));

            rdToken.redeem(redeemAmount, address(this), address(this));

            assertEq(rdToken.balanceOf(address(this)), beforeBal - redeemAmount);
        }
    }

    function withdraw(uint256 assets_) external {
        uint256 beforeBal = underlying.balanceOf(address(this));

        if (beforeBal > 0) {
            uint256 withdrawAmount = constrictToRange(assets_, 1, rdToken.balanceOfAssets(address(this)));

            rdToken.withdraw(withdrawAmount, address(this), address(this));

            assertEq(underlying.balanceOf(address(this)), beforeBal + withdrawAmount);  // Ensure successful withdraw
        }
    }

}

contract InvariantStakerManager is TestUtils {

    address rdToken;
    address underlying;

    InvariantStaker[] public stakers;

    constructor(address rdToken_, address underlying_) {
        rdToken      = rdToken_;
        underlying   = underlying_;
    }

    function createStaker() external {
        InvariantStaker staker = new InvariantStaker(rdToken, underlying);
        stakers.push(staker);
    }

    function deposit(uint256 amount_, uint256 index_) external {
        stakers[constrictToRange(index_, 0, stakers.length - 1)].deposit(amount_);
    }

    function redeem(uint256 amount_, uint256 index_) external {
        stakers[constrictToRange(index_, 0, stakers.length - 1)].redeem(amount_);
    }

    function withdraw(uint256 amount_, uint256 index_) external {
        stakers[constrictToRange(index_, 0, stakers.length - 1)].withdraw(amount_);
    }

    function getStakerCount() external view returns (uint256 stakerCount_) {
        return stakers.length;
    }

}
