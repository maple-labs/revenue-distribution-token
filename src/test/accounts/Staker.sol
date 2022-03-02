// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { TestUtils } from "../../../lib/contract-test-utils/contracts/test.sol";

import { ERC20User } from "../../../lib/erc20/src/test/accounts/ERC20User.sol";
import { MockERC20 } from "../../../lib/erc20/src/test/mocks/MockERC20.sol";

import { IRevenueDistributionToken as IRDT } from "../../interfaces/IRevenueDistributionToken.sol";

contract Staker is ERC20User {

    function rdToken_deposit(address token_, uint256 amount_) external {
        IRDT(token_).deposit(amount_);
    }

    function rdToken_redeem(address token_, uint256 amount_) external {
        IRDT(token_).redeem(amount_);
    }

    function rdToken_withdraw(address token_, uint256 amount_) external {
        IRDT(token_).withdraw(amount_);
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
        uint256 beforeBal = rdToken.balanceOf(address(this));

        if (beforeBal > 0) {
            uint256 redeemAmount = constrictToRange(amount_, 1, rdToken.balanceOf(address(this)));

            rdToken.redeem(redeemAmount);

            assertEq(rdToken.balanceOf(address(this)), beforeBal - redeemAmount);
        }
    }

    function withdraw(uint256 amount_) external {
        uint256 beforeBal = underlying.balanceOf(address(this));

        if (beforeBal > 0) {
            uint256 withdrawAmount = constrictToRange(amount_, 1, rdToken.balanceOfUnderlying(address(this)));

            rdToken.withdraw(withdrawAmount);

            assertEq(underlying.balanceOf(address(this)), beforeBal + withdrawAmount);  // Ensure successful withdraw
        }
    }

}

contract InvariantStakerManager is TestUtils {

    address rdToken;
    address underlying;
    address manager;

    uint256 startTime;

    bool allowWarp;
    bool allowDeposit  = true;
    bool allowRedeem   = true;
    bool allowWithdraw = true;


    InvariantStaker[] public stakers;

    constructor(address rdToken_, address underlying_, uint256 startTime_, bool allowWarp_) {
        manager    = msg.sender;
        rdToken    = rdToken_;
        underlying = underlying_;
        startTime  = startTime_;
        allowWarp  = allowWarp_; 
    }

    modifier warper() {
        if (!allowWarp) vm.warp(startTime);
        _;
    }

    modifier onlyManager() {
        require(msg.sender == manager);
        _;
    }

    function setAllowDeposit(bool deposit_) external onlyManager {
        allowDeposit = deposit_;
    }

    function setAllowRedeem(bool redeem_) external onlyManager {
        allowRedeem = redeem_;
    }

    function setAllowWithdrawal(bool withdrawal) external onlyManager {
        allowWithdraw = withdrawal;
    }

    function createStaker() external {
        InvariantStaker staker = new InvariantStaker(rdToken, underlying);
        stakers.push(staker);
    }

    function deposit(uint256 amount_, uint256 index_) external warper {
        stakers[constrictToRange(index_, 0, stakers.length - 1)].deposit(amount_);
    }

    function redeem(uint256 amount_, uint256 index_) external warper {
        stakers[constrictToRange(index_, 0, stakers.length - 1)].redeem(amount_);
    }

    function withdraw(uint256 amount_, uint256 index_) external warper {
        stakers[constrictToRange(index_, 0, stakers.length - 1)].withdraw(amount_);
    }

    function getStakerCount() external view returns (uint256 stakerCount_) {
        return stakers.length;
    }

}
