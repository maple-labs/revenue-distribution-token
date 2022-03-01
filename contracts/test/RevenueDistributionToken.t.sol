// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { TestUtils } from "../../modules/contract-test-utils/contracts/test.sol";
import { MockERC20 } from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { Owner }  from "./accounts/Owner.sol";
import { Staker } from "./accounts/Staker.sol";

import { RevenueDistributionToken as RDT } from "../RevenueDistributionToken.sol";

contract AuthTest is TestUtils {

    MockERC20 underlying;
    Owner     notOwner;
    Owner     owner;
    RDT       rdToken;

    function setUp() public virtual {
        notOwner   = new Owner();
        owner      = new Owner();
        underlying = new MockERC20("MockToken", "MT", 18);
        rdToken    = new RDT("Revenue Distribution Token", "RDT", address(owner), address(underlying), 1e30);
    }

    function test_setPendingOwner_acl() external {
        vm.expectRevert("RDT:SPO:NOT_OWNER");
        notOwner.rdToken_setPendingOwner(address(rdToken), address(1));

        assertEq(rdToken.pendingOwner(), address(0));
        owner.rdToken_setPendingOwner(address(rdToken), address(1));
        assertEq(rdToken.pendingOwner(), address(1));
    }

    function test_acceptOwnership_acl() external {
        owner.rdToken_setPendingOwner(address(rdToken), address(notOwner));

        vm.expectRevert("RDT:AO:NOT_PO");
        owner.rdToken_acceptOwnership(address(rdToken));

        assertEq(rdToken.pendingOwner(), address(notOwner));
        assertEq(rdToken.owner(),        address(owner));

        notOwner.rdToken_acceptOwnership(address(rdToken));

        assertEq(rdToken.pendingOwner(), address(0));
        assertEq(rdToken.owner(),        address(notOwner));
    }

    function test_updateVestingSchedule_acl() external {
        // Use non-zero timestamp
        vm.warp(10_000);

        underlying.mint(address(rdToken), 1000);

        vm.expectRevert("RDT:UVS:NOT_OWNER");
        notOwner.rdToken_updateVestingSchedule(address(rdToken), 100 seconds);

        assertEq(rdToken.freeAssets(),      0);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         0);
        assertEq(rdToken.vestingPeriodFinish(), 0);

        owner.rdToken_updateVestingSchedule(address(rdToken), 100 seconds);

        assertEq(rdToken.freeAssets(),      0);
        assertEq(rdToken.issuanceRate(),        10e30);
        assertEq(rdToken.lastUpdated(),         10_000);
        assertEq(rdToken.vestingPeriodFinish(), 10_100);
    }

}

contract DepositTest is TestUtils {

    MockERC20 underlying;
    RDT       rdToken;
    Staker    staker;

    function setUp() public virtual {
        underlying = new MockERC20("MockToken", "MT", 18);
        rdToken    = new RDT("Revenue Distribution Token", "RDT", address(this), address(underlying), 1e30);
        staker     = new Staker();

        vm.warp(10_000_000);  // Warp to non-zero timestamp
    }

    function test_deposit_zeroAmount() external {

        underlying.mint(address(staker), 1);
        staker.erc20_approve(address(underlying), address(rdToken), 1);

        vm.expectRevert("RDT:D:AMOUNT");
        staker.rdToken_deposit(address(rdToken), 0);

        staker.rdToken_deposit(address(rdToken), 1);
    }

    function test_deposit_badApprove(uint256 depositAmount) external {

        depositAmount = constrictToRange(depositAmount, 1, 1e29);

        underlying.mint(address(staker), depositAmount);

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount - 1);

        vm.expectRevert("RDT:D:TRANSFER_FROM");
        staker.rdToken_deposit(address(rdToken), depositAmount);

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);
    }

    function test_deposit_insufficientBalance(uint256 depositAmount) external {

        depositAmount = constrictToRange(depositAmount, 1, 1e29);

        underlying.mint(address(staker), depositAmount);
        staker.erc20_approve(address(underlying), address(rdToken), depositAmount + 1);

        vm.expectRevert("RDT:D:TRANSFER_FROM");
        staker.rdToken_deposit(address(rdToken), depositAmount + 1);

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);
    }

    function test_deposit_preVesting(uint256 depositAmount) external {

        depositAmount = constrictToRange(depositAmount, 1, 1e29);

        underlying.mint(address(staker), depositAmount);

        assertEq(rdToken.balanceOf(address(staker)), 0);
        assertEq(rdToken.totalSupply(),              0);
        assertEq(rdToken.freeAssets(),           0);
        assertEq(rdToken.totalAssets(),            0);
        // assertEq(rdToken.exchangeRate(),             1e30);
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              0);

        assertEq(underlying.balanceOf(address(staker)),  depositAmount);
        assertEq(underlying.balanceOf(address(rdToken)), 0);

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);

        uint256 shares = staker.rdToken_deposit(address(rdToken), depositAmount);

        assertEq(shares, rdToken.balanceOf(address(staker)));

        assertEq(rdToken.balanceOf(address(staker)), depositAmount);
        assertEq(rdToken.totalSupply(),              depositAmount);
        assertEq(rdToken.freeAssets(),           depositAmount);
        assertEq(rdToken.totalAssets(),            depositAmount);
        // assertEq(rdToken.exchangeRate(),             1e30);
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              block.timestamp);

        assertEq(underlying.balanceOf(address(staker)),  0);
        assertEq(underlying.balanceOf(address(rdToken)), depositAmount);
    }

    function test_deposit_exchangeRateGtOne_explicitVals() external {
        /*************/
        /*** Setup ***/
        /*************/

        uint256 start = block.timestamp;

        // Do a deposit so that totalSupply is non-zero
        underlying.mint(address(this), 20e18);
        underlying.approve(address(rdToken), 20e18);
        rdToken.deposit(20e18, address(this));

        _transferAndUpdateVesting(5e18, 10 seconds);

        vm.warp(start + 11 seconds);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        underlying.mint(address(staker), 10e18);

        /********************/
        /*** Before state ***/
        /********************/

        assertEq(rdToken.balanceOf(address(staker)), 0);
        assertEq(rdToken.totalSupply(),              20e18);
        assertEq(rdToken.freeAssets(),           20e18);
        assertEq(rdToken.totalAssets(),            25e18);
        // assertEq(rdToken.exchangeRate(),             1.25e30);  // (20 + 5) * 1e30 / 20
        assertEq(rdToken.issuanceRate(),             0.5e48);   // 5e18 * 1e30 / 10s
        assertEq(rdToken.lastUpdated(),              start);

        assertEq(underlying.balanceOf(address(staker)),  10e18);
        assertEq(underlying.balanceOf(address(rdToken)), 25e18);

        /***************/
        /*** Deposit ***/
        /***************/

        staker.erc20_approve(address(underlying), address(rdToken), 10e18);
        uint256 stakerShares = staker.rdToken_deposit(address(rdToken), 10e18);

        /*******************/
        /*** After state ***/
        /*******************/

        assertEq(stakerShares, 8e18);  // 10 / 1.25 exchangeRate

        assertEq(rdToken.balanceOf(address(staker)), 8e18);
        assertEq(rdToken.totalSupply(),              28e18);  // 8 + original 10
        assertEq(rdToken.freeAssets(),           35e18);
        assertEq(rdToken.totalAssets(),            35e18);
        // assertEq(rdToken.exchangeRate(),             1.25e30);  // totalAssets gets updated but exchangeRate stays constant
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              start + 11 seconds);

        assertEq(underlying.balanceOf(address(staker)),  0);
        assertEq(underlying.balanceOf(address(rdToken)), 35e18);
    }

    function test_deposit_exchangeRateGtOne(uint256 initialAmount, uint256 depositAmount, uint256 vestingAmount) external {
        /*************/
        /*** Setup ***/
        /*************/

        initialAmount = constrictToRange(initialAmount, 1, 1e29);
        depositAmount = constrictToRange(depositAmount, 1, 1e29);
        vestingAmount = constrictToRange(vestingAmount, 1, 1e29);

        // Do a deposit so that totalSupply is non-zero
        underlying.mint(address(this), initialAmount);
        underlying.approve(address(rdToken), initialAmount);
        uint256 initialShares = rdToken.deposit(initialAmount, address(this));

        uint256 start = block.timestamp;

        _transferAndUpdateVesting(vestingAmount, 10 seconds);

        vm.warp(start + 11 seconds);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        underlying.mint(address(staker), depositAmount);

        /********************/
        /*** Before state ***/
        /********************/

        assertEq(rdToken.balanceOf(address(staker)), 0);
        assertEq(rdToken.totalSupply(),              initialAmount);
        assertEq(rdToken.freeAssets(),           initialAmount);
        assertEq(rdToken.totalAssets(),            initialAmount + vestingAmount);
        // assertEq(rdToken.exchangeRate(),             (initialAmount + vestingAmount) * 1e30 / initialShares);
        assertEq(rdToken.issuanceRate(),             vestingAmount * 1e30 / 10 seconds);
        assertEq(rdToken.lastUpdated(),              start);

        assertEq(underlying.balanceOf(address(staker)),  depositAmount);
        assertEq(underlying.balanceOf(address(rdToken)), initialAmount + vestingAmount);

        // uint256 previousExchangeRate = rdToken.exchangeRate();

        /***************/
        /*** Deposit ***/
        /***************/

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);
        uint256 stakerShares = staker.rdToken_deposit(address(rdToken), depositAmount);

        /*******************/
        /*** After state ***/
        /*******************/

        assertEq(stakerShares, rdToken.balanceOf(address(staker)));

        uint256 exchangeRate = (initialAmount + vestingAmount + depositAmount) * 1e30 / (initialShares + stakerShares);

        assertEq(rdToken.balanceOf(address(staker)), depositAmount * 1e30 / exchangeRate);
        assertEq(rdToken.totalSupply(),              initialShares + stakerShares);
        assertEq(rdToken.freeAssets(),           initialAmount + vestingAmount + depositAmount);
        assertEq(rdToken.totalAssets(),            initialAmount + vestingAmount + depositAmount);
        // assertEq(rdToken.exchangeRate(),             exchangeRate);
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              start + 11 seconds);

        // assertWithinDiff(rdToken.exchangeRate(), previousExchangeRate, 10000);  // Assert that exchangeRate doesn't change on new deposits TODO: Figure out why this is large

        assertEq(underlying.balanceOf(address(staker)),  0);
        assertEq(underlying.balanceOf(address(rdToken)), initialAmount + vestingAmount + depositAmount);
    }

    function _transferAndUpdateVesting(uint256 vestingAmount_, uint256 vestingPeriod_) internal {
        underlying.mint(address(this), vestingAmount_);
        underlying.transfer(address(rdToken), vestingAmount_);
        rdToken.updateVestingSchedule(vestingPeriod_);
    }

}

contract ExitTest is TestUtils {
    MockERC20 underlying;
    RDT       rdToken;
    Staker    staker;

    bytes constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

    function setUp() public virtual {
        underlying = new MockERC20("MockToken", "MT", 18);
        rdToken    = new RDT("Revenue Distribution Token", "RDT", address(this), address(underlying), 1e30);
        staker     = new Staker();

        vm.warp(10_000_000);  // Warp to non-zero timestamp
    }

    /************************/
    /*** `withdraw` tests ***/
    /************************/

    function test_withdraw_zeroAmount(uint256 depositAmount) external {
        _depositUnderlying(constrictToRange(depositAmount, 1, 1e29));

        vm.expectRevert("RDT:W:AMOUNT");
        staker.rdToken_withdraw(address(rdToken), 0);

        staker.rdToken_withdraw(address(rdToken), 1);
    }

    function test_withdraw_burnUnderflow(uint256 depositAmount) external {
        depositAmount = constrictToRange(depositAmount, 1, 1e29);
        _depositUnderlying(depositAmount);

        vm.expectRevert(ARITHMETIC_ERROR);
        staker.rdToken_withdraw(address(rdToken), depositAmount + 1);

        staker.rdToken_withdraw(address(rdToken), depositAmount);
    }

    function test_withdraw_burnUnderflow_exchangeRateGtOne_explicitVals() external {
        uint256 depositAmount = 100e18;
        uint256 vestingAmount = 10e18;
        uint256 vestingPeriod = 10 days;
        uint256 warpTime      = 5 days;

        _depositUnderlying(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        uint256 maxWithdrawAmount = rdToken.previewRedeem(rdToken.balanceOf(address(staker)));  // TODO

        vm.expectRevert(ARITHMETIC_ERROR);
        staker.rdToken_withdraw(address(rdToken), maxWithdrawAmount + 1);

        staker.rdToken_withdraw(address(rdToken), maxWithdrawAmount);
    }

    function test_withdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount  = constrictToRange(depositAmount,  1, 1e29);
        withdrawAmount = constrictToRange(withdrawAmount, 1, depositAmount);

        underlying.mint(address(staker), depositAmount);

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        uint256 start = block.timestamp;

        assertEq(rdToken.balanceOf(address(staker)), depositAmount);
        assertEq(rdToken.totalSupply(),              depositAmount);
        assertEq(rdToken.freeAssets(),           depositAmount);
        assertEq(rdToken.totalAssets(),            depositAmount);
        // assertEq(rdToken.exchangeRate(),             1e30);
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              start);

        assertEq(underlying.balanceOf(address(staker)),  0);
        assertEq(underlying.balanceOf(address(rdToken)), depositAmount);

        vm.warp(start + 10 days);

        staker.rdToken_withdraw(address(rdToken), withdrawAmount);

        assertEq(rdToken.balanceOf(address(staker)), depositAmount - withdrawAmount);
        assertEq(rdToken.totalSupply(),              depositAmount - withdrawAmount);
        assertEq(rdToken.freeAssets(),           depositAmount - withdrawAmount);
        assertEq(rdToken.totalAssets(),            depositAmount - withdrawAmount);
        // assertEq(rdToken.exchangeRate(),             1e30);
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              start + 10 days);

        assertEq(underlying.balanceOf(address(staker)),  withdrawAmount);
        assertEq(underlying.balanceOf(address(rdToken)), depositAmount - withdrawAmount);
    }

    function test_withdraw_exchangeRateGtOne_explicitVals() public {
        uint256 depositAmount  = 100e18;
        uint256 withdrawAmount = 20e18;
        uint256 vestingAmount  = 10e18;
        uint256 vestingPeriod  = 200 seconds;
        uint256 warpTime       = 100 seconds;
        uint256 start          = block.timestamp;

        _depositUnderlying(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        assertEq(rdToken.balanceOf(address(staker)), 100e18);
        assertEq(rdToken.totalSupply(),              100e18);
        assertEq(rdToken.freeAssets(),           100e18);
        assertEq(rdToken.totalAssets(),            105e18);
        // assertEq(rdToken.exchangeRate(),             1.05e30);
        assertEq(rdToken.issuanceRate(),             0.05e18 * 1e30);
        assertEq(rdToken.lastUpdated(),              start);

        assertEq(underlying.balanceOf(address(staker)),  0);
        assertEq(underlying.balanceOf(address(rdToken)), 110e18);

        staker.rdToken_withdraw(address(rdToken), withdrawAmount);

        assertEq(rdToken.balanceOf(address(staker)), 80.952380952380952381e18);  // 100 - 80 / 1.05
        assertEq(rdToken.totalSupply(),              80.952380952380952381e18);
        assertEq(rdToken.freeAssets(),           85e18);  // totalAssets - 20 withdrawn
        assertEq(rdToken.totalAssets(),            85e18);
        // assertEq(rdToken.exchangeRate(),             1.049999999999999999999382352941e30);
        assertEq(rdToken.issuanceRate(),             0.05e18 * 1e30);
        assertEq(rdToken.lastUpdated(),              start + 100 seconds);

        assertEq(underlying.balanceOf(address(staker)),  20e18);
        assertEq(underlying.balanceOf(address(rdToken)), 90e18);
    }

    function test_withdraw_exchangeRateGtOne(
        uint256 depositAmount,
        uint256 withdrawAmount,
        uint256 vestingAmount,
        uint256 vestingPeriod,
        uint256 warpTime
    ) public {

        depositAmount  = constrictToRange(depositAmount,  1, 1e29);
        withdrawAmount = constrictToRange(withdrawAmount, 1, depositAmount);
        vestingAmount  = constrictToRange(vestingAmount,  1, 1e29);
        vestingPeriod  = constrictToRange(vestingPeriod,  1, 100 days);
        warpTime       = constrictToRange(warpTime,       1, vestingPeriod);

        uint256 start = block.timestamp;

        _depositUnderlying(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        assertEq(rdToken.balanceOf(address(staker)), depositAmount);
        assertEq(rdToken.totalSupply(),              depositAmount);
        assertEq(rdToken.freeAssets(),           depositAmount);
        assertEq(rdToken.lastUpdated(),              start);

        uint256 totalAssets = depositAmount + vestingAmount * warpTime / vestingPeriod;
        uint256 exchangeRate1 = rdToken.totalAssets() * 1e30 / depositAmount;  // Use actual `totalAssets` to not propogate errors

        assertWithinDiff(rdToken.totalAssets(), totalAssets,                         1);
        // assertWithinDiff(rdToken.exchangeRate(),  exchangeRate1,                         1);
        assertWithinDiff(rdToken.issuanceRate(),  vestingAmount * 1e30 / vestingPeriod,  1);

        assertEq(underlying.balanceOf(address(staker)),  0);
        assertEq(underlying.balanceOf(address(rdToken)), depositAmount + vestingAmount);  // Balance is higher than totalAssets

        staker.rdToken_withdraw(address(rdToken), withdrawAmount);

        totalAssets -= withdrawAmount;
        uint256 stakerBalance = depositAmount - withdrawAmount * 1e30 / exchangeRate1;

        assertEq(rdToken.balanceOf(address(staker)), stakerBalance);
        assertEq(rdToken.totalSupply(),              stakerBalance);
        assertEq(rdToken.lastUpdated(),              start + warpTime);

        uint256 exchangeRate2 = stakerBalance == 0 ? 1e30 : rdToken.totalAssets() * 1e30 / stakerBalance;  // Use actual `totalAssets` to avoid propogating errors

        // if (rdToken.totalSupply() > 0) assertWithinPrecision(rdToken.exchangeRate(), exchangeRate1, 8);  // TODO: Add specialized testing for this

        // assertWithinDiff(rdToken.exchangeRate(),   exchangeRate2,                        10);
        assertWithinDiff(rdToken.issuanceRate(),   vestingAmount * 1e30 / vestingPeriod, 1);
        assertWithinDiff(rdToken.freeAssets(), totalAssets,                        1);
        assertWithinDiff(rdToken.totalAssets(),  totalAssets,                        1);

        assertEq(underlying.balanceOf(address(staker)),  withdrawAmount);
        assertEq(underlying.balanceOf(address(rdToken)), depositAmount + vestingAmount - withdrawAmount);

    }

    // TODO: Implement once max* functions are added as per 4626 standard
    // function test_withdraw_burnUnderflow_exchangeRateGtOne(uint256 depositAmount, uint256 vestingAmount, uint256 vestingPeriod, uint256 warpTime) external {
    //     depositAmount = constrictToRange(depositAmount, 1, 1e29);
    //     vestingAmount = constrictToRange(vestingAmount, 1, 1e29);
    //     vestingPeriod = constrictToRange(vestingPeriod, 1, 100 days);
    //     warpTime      = constrictToRange(vestingAmount, 1, vestingPeriod);

    //     _depositUnderlying(depositAmount);
    //     _transferAndUpdateVesting(vestingAmount, vestingPeriod);

    //     vm.warp(block.timestamp + warpTime);

    //     uint256 underflowWithdrawAmount = rdToken.previewRedeem(rdToken.balanceOf(address(staker)) + 1);  // TODO
    //     uint256 maxWithdrawAmount       = rdToken.previewRedeem(rdToken.balanceOf(address(staker)));  // TODO

    //     vm.expectRevert(ARITHMETIC_ERROR);
    //     staker.rdToken_withdraw(address(rdToken), underflowWithdrawAmount);

    //     staker.rdToken_withdraw(address(rdToken), maxWithdrawAmount);
    // }


    /************************/
    /*** `redeem` tests ***/
    /************************/

    function test_redeem_zeroAmount(uint256 depositAmount) external {
        _depositUnderlying(constrictToRange(depositAmount, 1, 1e29));

        vm.expectRevert("RDT:W:AMOUNT");
        staker.rdToken_redeem(address(rdToken), 0);

        staker.rdToken_redeem(address(rdToken), 1);
    }

    function test_redeem_burnUnderflow(uint256 depositAmount) external {
        depositAmount = constrictToRange(depositAmount, 1, 1e29);
        _depositUnderlying(depositAmount);

        vm.expectRevert(ARITHMETIC_ERROR);
        staker.rdToken_redeem(address(rdToken), depositAmount + 1);

        staker.rdToken_redeem(address(rdToken), depositAmount);
    }

    function test_redeem_burnUnderflow_exchangeRateGtOne_explicitVals() external {
        uint256 depositAmount = 100e18;
        uint256 vestingAmount = 10e18;
        uint256 vestingPeriod = 10 days;
        uint256 warpTime      = 5 days;

        _depositUnderlying(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        vm.expectRevert(ARITHMETIC_ERROR);
        staker.rdToken_redeem(address(rdToken), 100e18 + 1);

        staker.rdToken_redeem(address(rdToken), 100e18);
    }

    function test_redeem(uint256 depositAmount, uint256 redeemAmount) public {
        depositAmount  = constrictToRange(depositAmount,  1, 1e29);
        redeemAmount = constrictToRange(redeemAmount, 1, depositAmount);

        underlying.mint(address(staker), depositAmount);

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        uint256 start = block.timestamp;

        assertEq(rdToken.balanceOf(address(staker)), depositAmount);
        assertEq(rdToken.totalSupply(),              depositAmount);
        assertEq(rdToken.freeAssets(),           depositAmount);
        assertEq(rdToken.totalAssets(),            depositAmount);
        // assertEq(rdToken.exchangeRate(),             1e30);
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              start);

        assertEq(underlying.balanceOf(address(staker)),  0);
        assertEq(underlying.balanceOf(address(rdToken)), depositAmount);

        vm.warp(start + 10 days);

        staker.rdToken_redeem(address(rdToken), redeemAmount);

        assertEq(rdToken.balanceOf(address(staker)), depositAmount - redeemAmount);
        assertEq(rdToken.totalSupply(),              depositAmount - redeemAmount);
        assertEq(rdToken.freeAssets(),           depositAmount - redeemAmount);
        assertEq(rdToken.totalAssets(),            depositAmount - redeemAmount);
        // assertEq(rdToken.exchangeRate(),             1e30);
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              start + 10 days);

        assertEq(underlying.balanceOf(address(staker)),  redeemAmount);
        assertEq(underlying.balanceOf(address(rdToken)), depositAmount - redeemAmount);
    }

    function test_redeem_exchangeRateGtOne_explicitVals() public {
        uint256 depositAmount  = 100e18;
        uint256 redeemAmount   = 20e18;
        uint256 vestingAmount  = 10e18;
        uint256 vestingPeriod  = 200 seconds;
        uint256 warpTime       = 100 seconds;
        uint256 start          = block.timestamp;

        _depositUnderlying(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        assertEq(rdToken.balanceOf(address(staker)), 100e18);
        assertEq(rdToken.totalSupply(),              100e18);
        assertEq(rdToken.freeAssets(),           100e18);
        assertEq(rdToken.totalAssets(),            105e18);
        // assertEq(rdToken.exchangeRate(),             1.05e30);
        assertEq(rdToken.issuanceRate(),             0.05e18 * 1e30);
        assertEq(rdToken.lastUpdated(),              start);

        assertEq(underlying.balanceOf(address(staker)),  0);
        assertEq(underlying.balanceOf(address(rdToken)), 110e18);

        staker.rdToken_redeem(address(rdToken), redeemAmount);

        assertEq(rdToken.balanceOf(address(staker)), 80e18);
        assertEq(rdToken.totalSupply(),              80e18);
        assertEq(rdToken.freeAssets(),           84e18);  // 105 * 0.8
        assertEq(rdToken.totalAssets(),            84e18);
        // assertEq(rdToken.exchangeRate(),             1.05e30);
        assertEq(rdToken.issuanceRate(),             0.05e18 * 1e30);
        assertEq(rdToken.lastUpdated(),              start + 100 seconds);

        assertEq(underlying.balanceOf(address(staker)),  21e18);
        assertEq(underlying.balanceOf(address(rdToken)), 89e18);
    }

    function test_redeem_exchangeRateGtOne(
        uint256 depositAmount,
        uint256 redeemAmount,
        uint256 vestingAmount,
        uint256 vestingPeriod,
        uint256 warpTime
    ) public {
        depositAmount = constrictToRange(depositAmount, 1, 1e29);
        redeemAmount  = constrictToRange(redeemAmount,  1, depositAmount);
        vestingAmount = constrictToRange(vestingAmount, 1, 1e29);
        vestingPeriod = constrictToRange(vestingPeriod, 1, 100 days);
        warpTime      = constrictToRange(warpTime,      1, vestingPeriod);

        uint256 start = block.timestamp;

        _depositUnderlying(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        assertEq(rdToken.balanceOf(address(staker)), depositAmount);
        assertEq(rdToken.totalSupply(),              depositAmount);
        assertEq(rdToken.freeAssets(),           depositAmount);
        assertEq(rdToken.lastUpdated(),              start);

        uint256 totalAssets = depositAmount + vestingAmount * warpTime / vestingPeriod;
        uint256 amountVested  = vestingAmount * 1e30 * warpTime / vestingPeriod / 1e30;

        assertWithinDiff(rdToken.totalAssets(), totalAssets,                        1);
        // assertWithinDiff(rdToken.exchangeRate(),  exchangeRate1,                        1);
        assertWithinDiff(rdToken.issuanceRate(),  vestingAmount * 1e30 / vestingPeriod, 1);

        assertEq(underlying.balanceOf(address(staker)),  0);
        assertEq(underlying.balanceOf(address(rdToken)), depositAmount + vestingAmount);  // Balance is higher than totalAssets

        uint256 expectedAssetsFromRedeem = rdToken.convertToAssets(redeemAmount);
        uint256 assetsFromRedeem = staker.rdToken_redeem(address(rdToken), redeemAmount);

        assertEq(assetsFromRedeem,                   expectedAssetsFromRedeem);
        assertEq(rdToken.balanceOf(address(staker)), depositAmount - redeemAmount);
        assertEq(rdToken.totalSupply(),              depositAmount - redeemAmount);
        assertEq(rdToken.lastUpdated(),              start + warpTime);

        // if (rdToken.totalSupply() > 0) assertWithinPrecision(rdToken.exchangeRate(), exchangeRate1, 8);  // TODO: Add specialized testing for this

        assertWithinDiff(rdToken.issuanceRate(), vestingAmount * 1e30 / vestingPeriod, 1);
        assertEq(rdToken.freeAssets(),           depositAmount + amountVested - expectedAssetsFromRedeem);
        assertEq(rdToken.totalAssets(),          depositAmount + amountVested - expectedAssetsFromRedeem);

        assertEq(underlying.balanceOf(address(staker)),  expectedAssetsFromRedeem);
        assertEq(underlying.balanceOf(address(rdToken)), depositAmount + vestingAmount - expectedAssetsFromRedeem);  // Note that vestingAmount is used
    }

    function _depositUnderlying(uint256 depositAmount) internal {
        underlying.mint(address(staker), depositAmount);
        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);
    }

    function _transferAndUpdateVesting(uint256 vestingAmount_, uint256 vestingPeriod_) internal {
        underlying.mint(address(this), vestingAmount_);
        underlying.transfer(address(rdToken), vestingAmount_);
        rdToken.updateVestingSchedule(vestingPeriod_);
    }
}

contract RevenueStreamingTest is TestUtils {

    MockERC20 underlying;
    RDT       rdToken;

    bytes constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

    uint256 start;

    function setUp() public virtual {
        // Use non-zero timestamp
        start = 10_000;
        vm.warp(start);

        underlying = new MockERC20("MockToken", "MT", 18);
        rdToken    = new RDT("Revenue Distribution Token", "RDT", address(this), address(underlying), 1e30);
    }

    /************************************/
    /*** Single updateVestingSchedule ***/
    /************************************/

    function test_updateVestingSchedule_single() external {
        assertEq(rdToken.freeAssets(),      0);
        assertEq(rdToken.totalAssets(),       0);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         0);
        assertEq(rdToken.vestingPeriodFinish(), 0);

        assertEq(underlying.balanceOf(address(rdToken)), 0);

        _transferAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        assertEq(underlying.balanceOf(address(rdToken)), 1000);

        assertEq(rdToken.freeAssets(),      0);
        assertEq(rdToken.totalAssets(),       0);
        // assertEq(rdToken.exchangeRate(),        1e30);
        assertEq(rdToken.issuanceRate(),        10e30);  // 10 tokens per second
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);

        vm.warp(rdToken.vestingPeriodFinish());

        assertEq(rdToken.totalAssets(), 1000);  // All tokens vested
    }

    function test_updateVestingSchedule_single_roundingDown() external {
        _transferAndUpdateVesting(1000, 30 seconds);  // 33.3333... tokens per second

        assertEq(rdToken.totalAssets(), 0);
        assertEq(rdToken.issuanceRate(),  33333333333333333333333333333333);  // 3.33e30

        // totalAssets should never be more than one full unit off
        vm.warp(start + 1 seconds);
        assertEq(rdToken.totalAssets(), 33);  // 33 < 33.33...

        vm.warp(start + 2 seconds);
        assertEq(rdToken.totalAssets(), 66);  // 66 < 66.66...

        vm.warp(start + 3 seconds);
        assertEq(rdToken.totalAssets(), 99);  // 99 < 99.99...

        vm.warp(start + 4 seconds);
        assertEq(rdToken.totalAssets(), 133);  // 133 < 133.33...

        vm.warp(rdToken.vestingPeriodFinish());
        assertEq(rdToken.totalAssets(), 999);  // 999 < 1000
    }

    /*************************************************/
    /*** Multiple updateVestingSchedule, same time ***/
    /*************************************************/

    function test_updateVestingSchedule_sameTime_shorterVesting() external {
        _transferAndUpdateVesting(1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);  // Always updates to latest vesting schedule

        _transferAndUpdateVesting(1000, 20 seconds);
        assertEq(rdToken.issuanceRate(),        100e30);              // (1000 + 1000) / 20 seconds = 100 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 20 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalAssets(), 0);

        vm.warp(start + 20 seconds);

        assertEq(rdToken.totalAssets(), 2000);
    }

    function test_updateVestingSchedule_sameTime_longerVesting_higherRate() external {
        _transferAndUpdateVesting(1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);  // Always updates to latest vesting schedule

        _transferAndUpdateVesting(3000, 200 seconds);
        assertEq(rdToken.issuanceRate(),        20e30);                // (3000 + 1000) / 200 seconds = 20 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 200 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalAssets(), 0);

        vm.warp(start + 200 seconds);

        assertEq(rdToken.totalAssets(), 4000);
    }

    function test_updateVestingSchedule_sameTime_longerVesting_lowerRate() external {
        _transferAndUpdateVesting(1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);  // Always updates to latest vesting schedule

        _transferAndUpdateVesting(1000, 500 seconds);
        assertEq(rdToken.issuanceRate(),        4e30);                 // (1000 + 1000) / 500 seconds = 4 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 500 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalAssets(), 0);

        vm.warp(start + 5000 seconds);

        assertEq(rdToken.totalAssets(), 2000);
    }

    /*******************************************************/
    /*** Multiple updateVestingSchedule, different times ***/
    /*******************************************************/

    function test_updateVestingSchedule_diffTime_shorterVesting() external {
        _transferAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        vm.warp(start + 60 seconds);

        assertEq(rdToken.issuanceRate(),        10e30);
        assertEq(rdToken.totalAssets(),       600);
        assertEq(rdToken.freeAssets(),      0);
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);

        _transferAndUpdateVesting(1000, 20 seconds);  // 50 tokens per second

        assertEq(rdToken.issuanceRate(),        70e30);  // (400 + 1000) / 20 seconds = 70 tokens per second
        assertEq(rdToken.totalAssets(),       600);
        assertEq(rdToken.freeAssets(),      600);
        assertEq(rdToken.vestingPeriodFinish(), start + 60 seconds + 20 seconds);

        vm.warp(start + 60 seconds + 20 seconds);

        assertEq(rdToken.issuanceRate(),   70e30);
        assertEq(rdToken.totalAssets(),  2000);
        assertEq(rdToken.freeAssets(), 600);
    }

    function test_updateVestingSchedule_diffTime_longerVesting_higherRate() external {
        _transferAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        vm.warp(start + 60 seconds);

        assertEq(rdToken.issuanceRate(),        10e30);
        assertEq(rdToken.totalAssets(),       600);
        assertEq(rdToken.freeAssets(),      0);
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);

        _transferAndUpdateVesting(3000, 200 seconds);  // 15 tokens per second

        assertEq(rdToken.issuanceRate(),   17e30);  // (400 + 3000) / 200 seconds = 17 tokens per second
        assertEq(rdToken.totalAssets(),  600);
        assertEq(rdToken.freeAssets(), 600);

        vm.warp(start + 60 seconds + 200 seconds);

        assertEq(rdToken.issuanceRate(),   17e30);
        assertEq(rdToken.totalAssets(),  4000);
        assertEq(rdToken.freeAssets(), 600);
    }

    function test_updateVestingSchedule_diffTime_longerVesting_lowerRate() external {
        _transferAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        vm.warp(start + 60 seconds);

        assertEq(rdToken.issuanceRate(),   10e30);
        assertEq(rdToken.totalAssets(),  600);
        assertEq(rdToken.freeAssets(), 0);

        _transferAndUpdateVesting(1000, 200 seconds);  // 5 tokens per second

        assertEq(rdToken.issuanceRate(),   7e30);  // (400 + 1000) / 200 seconds = 7 tokens per second
        assertEq(rdToken.totalAssets(),  600);
        assertEq(rdToken.freeAssets(), 600);

        vm.warp(start + 60 seconds + 200 seconds);

        assertEq(rdToken.issuanceRate(),   7e30);
        assertEq(rdToken.totalAssets(),  2000);
        assertEq(rdToken.freeAssets(), 600);
    }

    /********************************/
    /*** End to end vesting tests ***/
    /********************************/

    function test_vesting_singleSchedule_explicit_vals() public {
        uint256 depositAmount = 1_000_000e18;
        uint256 vestingAmount = 100_000e18;
        uint256 vestingPeriod = 200_000 seconds;

        Staker staker = new Staker();

        underlying.mint(address(staker), depositAmount);

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        assertEq(rdToken.freeAssets(),      1_000_000e18);
        assertEq(rdToken.totalAssets(),       1_000_000e18);
        // assertEq(rdToken.exchangeRate(),        1e30);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), 0);

        vm.warp(start + 1 days);

        assertEq(rdToken.totalAssets(),  1_000_000e18);  // No change

        vm.warp(start);  // Warp back after demonstrating totalAssets is not time-dependent before vesting starts

        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        assertEq(rdToken.freeAssets(),      1_000_000e18);
        assertEq(rdToken.totalAssets(),       1_000_000e18);
        // assertEq(rdToken.exchangeRate(),        1e30);
        assertEq(rdToken.issuanceRate(),        0.5e18 * 1e30);  // 0.5 tokens per second
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), start + vestingPeriod);

        // Warp and assert vesting in 10% increments
        vm.warp(start + 20_000 seconds);  // 10% of vesting schedule

        assertEq(rdToken.balanceOfAssets(address(staker)), 1_010_000e18);
        assertEq(rdToken.totalAssets(),                      1_010_000e18);
        // assertEq(rdToken.exchangeRate(),                       1.01e30);

        vm.warp(start + 40_000 seconds);  // 20% of vesting schedule

        assertEq(rdToken.balanceOfAssets(address(staker)), 1_020_000e18);
        assertEq(rdToken.totalAssets(),                      1_020_000e18);
        // assertEq(rdToken.exchangeRate(),                       1.02e30);

        vm.warp(start + 60_000 seconds);  // 30% of vesting schedule

        assertEq(rdToken.balanceOfAssets(address(staker)), 1_030_000e18);
        assertEq(rdToken.totalAssets(),                      1_030_000e18);
        // assertEq(rdToken.exchangeRate(),                       1.03e30);

        vm.warp(start + 200_000 seconds);  // End of vesting schedule

        assertEq(rdToken.balanceOfAssets(address(staker)), 1_100_000e18);
        assertEq(rdToken.totalAssets(),                      1_100_000e18);
        // assertEq(rdToken.exchangeRate(),                       1.1e30);

        assertEq(underlying.balanceOf(address(rdToken)), 1_100_000e18);
        assertEq(underlying.balanceOf(address(staker)),  0);
        assertEq(rdToken.balanceOf(address(staker)),     1_000_000e18);

        staker.rdToken_redeem(address(rdToken), 1_000_000e18);  // Use `redeem` so rdToken amount can be used to burn 100% of tokens

        assertEq(rdToken.freeAssets(),      0);
        assertEq(rdToken.totalAssets(),       0);
        // assertEq(rdToken.exchangeRate(),        1e30);                     // Exchange rate returns to 1 when empty
        assertEq(rdToken.issuanceRate(),        0.5e18 * 1e30);         // TODO: Investigate implications of non-zero issuanceRate here
        assertEq(rdToken.lastUpdated(),         start + 200_000 seconds);  // This makes issuanceRate * time zero
        assertEq(rdToken.vestingPeriodFinish(), start + 200_000 seconds);

        assertEq(underlying.balanceOf(address(rdToken)),       0);
        assertEq(rdToken.balanceOfAssets(address(staker)), 0);

        assertEq(underlying.balanceOf(address(staker)), 1_100_000e18);
        assertEq(rdToken.balanceOf(address(staker)),    0);
    }

    function test_vesting_singleSchedule_fuzz(uint256 depositAmount, uint256 vestingAmount, uint256 vestingPeriod) public {
        depositAmount = constrictToRange(depositAmount, 1e6,        1e30);                    // 1 billion at WAD precision
        vestingAmount = constrictToRange(vestingAmount, 1e6,        1e30);                    // 1 billion at WAD precision
        vestingPeriod = constrictToRange(vestingPeriod, 10 seconds, 100_000 days) / 10 * 10;  // Must be divisible by 10 for for loop 10% increment calculations // TODO: Add a zero case test

        Staker staker = new Staker();

        underlying.mint(address(staker), depositAmount);

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        assertEq(rdToken.freeAssets(),      depositAmount);
        assertEq(rdToken.totalAssets(),       depositAmount);
        // assertEq(rdToken.exchangeRate(),        1e30);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), 0);

        vm.warp(start + 1 days);

        assertEq(rdToken.totalAssets(),  depositAmount);  // No change

        vm.warp(start);  // Warp back after demonstrating totalAssets is not time-dependent before vesting starts

        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        uint256 expectedRate = vestingAmount * 1e30 / vestingPeriod;

        assertEq(rdToken.freeAssets(),      depositAmount);
        assertEq(rdToken.totalAssets(),       depositAmount);
        // assertEq(rdToken.exchangeRate(),        1e30);
        assertEq(rdToken.issuanceRate(),        expectedRate);
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), start + vestingPeriod);

        // Warp and assert vesting in 10% increments
        for (uint256 i = 1; i < 10; ++i) {
            vm.warp(start + vestingPeriod * i / 10);  // 10% intervals of vesting schedule

            uint256 expectedtotalAssets = depositAmount + expectedRate * (block.timestamp - start) / 1e30;

            assertWithinDiff(rdToken.balanceOfAssets(address(staker)), expectedtotalAssets, 1);

            assertEq(rdToken.totalAssets(), expectedtotalAssets);
            // assertEq(rdToken.exchangeRate(),  expectedtotalAssets * 1e30 / depositAmount);
        }

        vm.warp(start + vestingPeriod);

        uint256 expectedFinalTotal = depositAmount + vestingAmount;

        // TODO: Try assertEq
        assertWithinDiff(rdToken.balanceOfAssets(address(staker)), expectedFinalTotal, 2);

        assertWithinDiff(rdToken.totalAssets(), expectedFinalTotal,                             1);
        // assertWithinDiff(rdToken.exchangeRate(),  rdToken.totalAssets() * 1e30 / depositAmount, 1);  // Using totalAssets because of rounding

        assertEq(underlying.balanceOf(address(rdToken)), depositAmount + vestingAmount);

        assertEq(underlying.balanceOf(address(staker)), 0);
        assertEq(rdToken.balanceOf(address(staker)),    depositAmount);

        staker.rdToken_redeem(address(rdToken), depositAmount);  // Use `redeem` so rdToken amount can be used to burn 100% of tokens

        assertWithinDiff(rdToken.freeAssets(), 0, 1);
        assertWithinDiff(rdToken.totalAssets(),  0, 1);

        // assertEq(rdToken.exchangeRate(),        1e30);                   // Exchange rate returns to zero when empty
        assertEq(rdToken.issuanceRate(),        expectedRate);           // TODO: Investigate implications of non-zero issuanceRate here
        assertEq(rdToken.lastUpdated(),         start + vestingPeriod);  // This makes issuanceRate * time zero
        assertEq(rdToken.vestingPeriodFinish(), start + vestingPeriod);

        assertWithinDiff(underlying.balanceOf(address(rdToken)), 0, 2);

        assertEq(rdToken.balanceOfAssets(address(staker)), 0);

        assertWithinDiff(underlying.balanceOf(address(staker)), depositAmount + vestingAmount, 2);
        assertWithinDiff(rdToken.balanceOf(address(staker)),    0,                             1);
    }

    function _transferAndUpdateVesting(uint256 vestingAmount_, uint256 vestingPeriod_) internal {
        underlying.mint(address(this), vestingAmount_);
        underlying.transfer(address(rdToken), vestingAmount_);
        rdToken.updateVestingSchedule(vestingPeriod_);
    }
}
