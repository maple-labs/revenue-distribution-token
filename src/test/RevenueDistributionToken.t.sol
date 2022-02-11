// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { TestUtils } from "../../lib/contract-test-utils/contracts/test.sol";
import { MockERC20 } from "../../lib/erc20/src/test/mocks/MockERC20.sol";

import { Owner }  from "./accounts/Owner.sol";
import { Staker } from "./accounts/Staker.sol";

import { Vm } from "../interfaces/Interfaces.sol";

import { RevenueDistributionToken } from "../RevenueDistributionToken.sol";

contract AuthTest is TestUtils {

    MockERC20                underlying;
    Owner                    notOwner;
    Owner                    owner;
    RevenueDistributionToken rdToken;

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        notOwner   = new Owner();
        owner      = new Owner();
        underlying = new MockERC20("MockToken", "MT", 18);
        rdToken    = new RevenueDistributionToken("Revenue Distribution Token", "RDT", address(owner), address(underlying), 1e30);
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

        assertEq(rdToken.freeUnderlying(),      0);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         0);
        assertEq(rdToken.vestingPeriodFinish(), 0);

        owner.rdToken_updateVestingSchedule(address(rdToken), 100 seconds);

        assertEq(rdToken.freeUnderlying(),      0);
        assertEq(rdToken.issuanceRate(),        10e30);
        assertEq(rdToken.lastUpdated(),         10_000);
        assertEq(rdToken.vestingPeriodFinish(), 10_100);
    }

}

contract EntryExitTest is TestUtils {

    MockERC20 underlying;

    RevenueDistributionToken rdToken;

    bytes constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        underlying = new MockERC20("MockToken", "MT", 18);
        rdToken    = new RevenueDistributionToken("Revenue Distribution Token", "RDT", address(this), address(underlying), 1e30);
    }

    // TODO: Add lastUpdated/issuanceRate assertions

    function test_deposit(uint256 depositAmount) public {
        Staker staker = new Staker();

        depositAmount = constrictToRange(depositAmount, 1, 1e45);

        underlying.mint(address(staker), depositAmount);

        assertEq(underlying.balanceOf(address(staker)),  depositAmount);
        assertEq(underlying.balanceOf(address(rdToken)), 0);
        assertEq(rdToken.balanceOf(address(staker)),     0);
        assertEq(rdToken.totalHoldings(),                0);
        assertEq(rdToken.exchangeRate(),                 1e30);

        vm.expectRevert("RDT:D:TRANSFER_FROM");
        staker.rdToken_deposit(address(rdToken), depositAmount);

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        assertEq(underlying.balanceOf(address(staker)),  0);
        assertEq(underlying.balanceOf(address(rdToken)), depositAmount);
        assertEq(rdToken.balanceOf(address(staker)),     depositAmount);
        assertEq(rdToken.totalHoldings(),                depositAmount);
        assertEq(rdToken.exchangeRate(),                 1e30);
    }

    function test_withdraw(uint256 depositAmount) public {
        Staker staker = new Staker();

        depositAmount = constrictToRange(depositAmount, 1, 1e45);

        underlying.mint(address(staker), depositAmount);

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        assertEq(underlying.balanceOf(address(staker)),  0);
        assertEq(underlying.balanceOf(address(rdToken)), depositAmount);
        assertEq(rdToken.balanceOf(address(staker)),     depositAmount);
        assertEq(rdToken.totalHoldings(),                depositAmount);
        assertEq(rdToken.exchangeRate(),                 1e30);

        vm.expectRevert(ARITHMETIC_ERROR);  // Arithmetic error
        staker.rdToken_withdraw(address(rdToken), depositAmount + 1);
        staker.rdToken_withdraw(address(rdToken), depositAmount);

        assertEq(underlying.balanceOf(address(staker)),  depositAmount);
        assertEq(underlying.balanceOf(address(rdToken)), 0);
        assertEq(rdToken.balanceOf(address(staker)),     0);
        assertEq(rdToken.totalHoldings(),                0);
        assertEq(rdToken.exchangeRate(),                 1e30);
    }

    function test_redeem(uint256 depositAmount) public {
        Staker staker = new Staker();

        depositAmount = constrictToRange(depositAmount, 1, 1e45);

        underlying.mint(address(staker), depositAmount);

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        assertEq(underlying.balanceOf(address(staker)),  0);
        assertEq(underlying.balanceOf(address(rdToken)), depositAmount);
        assertEq(rdToken.balanceOf(address(staker)),     depositAmount);
        assertEq(rdToken.totalHoldings(),                depositAmount);
        assertEq(rdToken.exchangeRate(),                 1e30);

        staker.rdToken_redeem(address(rdToken), depositAmount);

        assertEq(underlying.balanceOf(address(staker)),  depositAmount);
        assertEq(underlying.balanceOf(address(rdToken)), 0);
        assertEq(rdToken.balanceOf(address(staker)),     0);
        assertEq(rdToken.totalHoldings(),                0);
        assertEq(rdToken.exchangeRate(),                 1e30);
    }
}

contract RevenueStreamingTest is TestUtils {

    MockERC20 underlying;
    RevenueDistributionToken rdToken;

    bytes constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 start;

    function setUp() public {
        // Use non-zero timestamp
        start = 10_000;
        vm.warp(start);

        underlying = new MockERC20("MockToken", "MT", 18);
        rdToken    = new RevenueDistributionToken("Revenue Distribution Token", "RDT", address(this), address(underlying), 1e30);
    }

    /************************************/
    /*** Single updateVestingSchedule ***/
    /************************************/

    function test_updateVestingSchedule_single() external {
        assertEq(rdToken.freeUnderlying(),      0);
        assertEq(rdToken.totalHoldings(),       0);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         0);
        assertEq(rdToken.vestingPeriodFinish(), 0);

        assertEq(underlying.balanceOf(address(rdToken)), 0);

        _depositAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        assertEq(underlying.balanceOf(address(rdToken)), 1000);

        assertEq(rdToken.freeUnderlying(),      0);
        assertEq(rdToken.totalHoldings(),       0);
        assertEq(rdToken.exchangeRate(),        1e30);
        assertEq(rdToken.issuanceRate(),        10e30);  // 10 tokens per second
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);

        vm.warp(rdToken.vestingPeriodFinish());

        assertEq(rdToken.totalHoldings(), 1000);  // All tokens vested
    }

    function test_updateVestingSchedule_single_roundingDown() external {
        _depositAndUpdateVesting(1000, 30 seconds);  // 33.3333... tokens per second

        assertEq(rdToken.totalHoldings(), 0);
        assertEq(rdToken.issuanceRate(),  33333333333333333333333333333333);  // 3.33e30

        // totalHoldings should never be more than one full unit off
        vm.warp(start + 1 seconds);
        assertEq(rdToken.totalHoldings(), 33);  // 33 < 33.33...

        vm.warp(start + 2 seconds);
        assertEq(rdToken.totalHoldings(), 66);  // 66 < 66.66...

        vm.warp(start + 3 seconds);
        assertEq(rdToken.totalHoldings(), 99);  // 99 < 99.99...

        vm.warp(start + 4 seconds);
        assertEq(rdToken.totalHoldings(), 133);  // 133 < 133.33...

        vm.warp(rdToken.vestingPeriodFinish());
        assertEq(rdToken.totalHoldings(), 999);  // 999 < 1000
    }

    /*************************************************/
    /*** Multiple updateVestingSchedule, same time ***/
    /*************************************************/

    function test_updateVestingSchedule_sameTime_shorterVesting() external {
        _depositAndUpdateVesting(1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);  // Always updates to latest vesting schedule

        _depositAndUpdateVesting(1000, 20 seconds);
        assertEq(rdToken.issuanceRate(),        100e30);              // (1000 + 1000) / 20 seconds = 100 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 20 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalHoldings(), 0);

        vm.warp(start + 20 seconds);

        assertEq(rdToken.totalHoldings(), 2000);
    }

    function test_updateVestingSchedule_sameTime_longerVesting_higherRate() external {
        _depositAndUpdateVesting(1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);  // Always updates to latest vesting schedule

        _depositAndUpdateVesting(3000, 200 seconds);
        assertEq(rdToken.issuanceRate(),        20e30);                // (3000 + 1000) / 200 seconds = 20 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 200 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalHoldings(), 0);

        vm.warp(start + 200 seconds);

        assertEq(rdToken.totalHoldings(), 4000);
    }

    function test_updateVestingSchedule_sameTime_longerVesting_lowerRate() external {
        _depositAndUpdateVesting(1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);  // Always updates to latest vesting schedule

        _depositAndUpdateVesting(1000, 500 seconds);
        assertEq(rdToken.issuanceRate(),        4e30);                 // (1000 + 1000) / 500 seconds = 4 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 500 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalHoldings(), 0);

        vm.warp(start + 5000 seconds);

        assertEq(rdToken.totalHoldings(), 2000);
    }

    /*******************************************************/
    /*** Multiple updateVestingSchedule, different times ***/
    /*******************************************************/

    function test_updateVestingSchedule_diffTime_shorterVesting() external {
        _depositAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        vm.warp(start + 60 seconds);

        assertEq(rdToken.issuanceRate(),        10e30);
        assertEq(rdToken.totalHoldings(),       600);
        assertEq(rdToken.freeUnderlying(),      0);
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);

        _depositAndUpdateVesting(1000, 20 seconds);  // 50 tokens per second

        assertEq(rdToken.issuanceRate(),        70e30);  // (400 + 1000) / 20 seconds = 70 tokens per second
        assertEq(rdToken.totalHoldings(),       600);
        assertEq(rdToken.freeUnderlying(),      600);
        assertEq(rdToken.vestingPeriodFinish(), start + 60 seconds + 20 seconds);

        vm.warp(start + 60 seconds + 20 seconds);

        assertEq(rdToken.issuanceRate(),   70e30);
        assertEq(rdToken.totalHoldings(),  2000);
        assertEq(rdToken.freeUnderlying(), 600);
    }

    function test_updateVestingSchedule_diffTime_longerVesting_higherRate() external {
        _depositAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        vm.warp(start + 60 seconds);

        assertEq(rdToken.issuanceRate(),        10e30);
        assertEq(rdToken.totalHoldings(),       600);
        assertEq(rdToken.freeUnderlying(),      0);
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);

        _depositAndUpdateVesting(3000, 200 seconds);  // 15 tokens per second

        assertEq(rdToken.issuanceRate(),   17e30);  // (400 + 3000) / 200 seconds = 17 tokens per second
        assertEq(rdToken.totalHoldings(),  600);
        assertEq(rdToken.freeUnderlying(), 600);

        vm.warp(start + 60 seconds + 200 seconds);

        assertEq(rdToken.issuanceRate(),   17e30);
        assertEq(rdToken.totalHoldings(),  4000);
        assertEq(rdToken.freeUnderlying(), 600);
    }

    function test_updateVestingSchedule_diffTime_longerVesting_lowerRate() external {
        _depositAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        vm.warp(start + 60 seconds);

        assertEq(rdToken.issuanceRate(),   10e30);
        assertEq(rdToken.totalHoldings(),  600);
        assertEq(rdToken.freeUnderlying(), 0);

        _depositAndUpdateVesting(1000, 200 seconds);  // 5 tokens per second

        assertEq(rdToken.issuanceRate(),   7e30);  // (400 + 1000) / 200 seconds = 7 tokens per second
        assertEq(rdToken.totalHoldings(),  600);
        assertEq(rdToken.freeUnderlying(), 600);

        vm.warp(start + 60 seconds + 200 seconds);

        assertEq(rdToken.issuanceRate(),   7e30);
        assertEq(rdToken.totalHoldings(),  2000);
        assertEq(rdToken.freeUnderlying(), 600);
    }

    /********************************/
    /*** End to end vesting tests ***/
    /********************************/

    function test_vesting_singleSchedule_explicit_vals() public {
        uint256 depositAmount = 1_000_000 ether;
        uint256 vestingAmount = 100_000 ether;
        uint256 vestingPeriod = 200_000 seconds;

        Staker staker = new Staker();

        underlying.mint(address(staker), depositAmount);

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        assertEq(rdToken.freeUnderlying(),      1_000_000 ether);
        assertEq(rdToken.totalHoldings(),       1_000_000 ether);
        assertEq(rdToken.exchangeRate(),        1e30);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), 0);

        vm.warp(start + 1 days);

        assertEq(rdToken.totalHoldings(),  1_000_000 ether);  // No change

        vm.warp(start);  // Warp back after demonstrating totalHoldings is not time-dependent before vesting starts

        _depositAndUpdateVesting(vestingAmount, vestingPeriod);

        assertEq(rdToken.freeUnderlying(),      1_000_000 ether);
        assertEq(rdToken.totalHoldings(),       1_000_000 ether);
        assertEq(rdToken.exchangeRate(),        1e30);
        assertEq(rdToken.issuanceRate(),        0.5 ether * 1e30);  // 0.5 tokens per second
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), start + vestingPeriod);

        // Warp and assert vesting in 10% increments
        vm.warp(start + 20_000 seconds);  // 10% of vesting schedule

        assertEq(rdToken.balanceOfUnderlying(address(staker)), 1_010_000 ether);
        assertEq(rdToken.totalHoldings(),                      1_010_000 ether);
        assertEq(rdToken.exchangeRate(),                       1.01e30);

        vm.warp(start + 40_000 seconds);  // 20% of vesting schedule

        assertEq(rdToken.balanceOfUnderlying(address(staker)), 1_020_000 ether);
        assertEq(rdToken.totalHoldings(),                      1_020_000 ether);
        assertEq(rdToken.exchangeRate(),                       1.02e30);

        vm.warp(start + 60_000 seconds);  // 30% of vesting schedule

        assertEq(rdToken.balanceOfUnderlying(address(staker)), 1_030_000 ether);
        assertEq(rdToken.totalHoldings(),                      1_030_000 ether);
        assertEq(rdToken.exchangeRate(),                       1.03e30);

        vm.warp(start + 200_000 seconds);  // End of vesting schedule

        assertEq(rdToken.balanceOfUnderlying(address(staker)), 1_100_000 ether);
        assertEq(rdToken.totalHoldings(),                      1_100_000 ether);
        assertEq(rdToken.exchangeRate(),                       1.1e30);

        assertEq(underlying.balanceOf(address(rdToken)), 1_100_000 ether);
        assertEq(underlying.balanceOf(address(staker)),  0);
        assertEq(rdToken.balanceOf(address(staker)),     1_000_000 ether);

        staker.rdToken_redeem(address(rdToken), 1_000_000 ether);  // Use `redeem` so rdToken amount can be used to burn 100% of tokens

        assertEq(rdToken.freeUnderlying(),      0);
        assertEq(rdToken.totalHoldings(),       0);
        assertEq(rdToken.exchangeRate(),        1e30);                     // Exchange rate returns to 1 when empty
        assertEq(rdToken.issuanceRate(),        0.5 ether * 1e30);         // TODO: Investigate implications of non-zero issuanceRate here
        assertEq(rdToken.lastUpdated(),         start + 200_000 seconds);  // This makes issuanceRate * time zero
        assertEq(rdToken.vestingPeriodFinish(), start + 200_000 seconds);

        assertEq(underlying.balanceOf(address(rdToken)),       0);
        assertEq(rdToken.balanceOfUnderlying(address(staker)), 0);

        assertEq(underlying.balanceOf(address(staker)), 1_100_000 ether);
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

        assertEq(rdToken.freeUnderlying(),      depositAmount);
        assertEq(rdToken.totalHoldings(),       depositAmount);
        assertEq(rdToken.exchangeRate(),        1e30);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), 0);

        vm.warp(start + 1 days);

        assertEq(rdToken.totalHoldings(),  depositAmount);  // No change

        vm.warp(start);  // Warp back after demonstrating totalHoldings is not time-dependent before vesting starts

        _depositAndUpdateVesting(vestingAmount, vestingPeriod);

        uint256 expectedRate = vestingAmount * 1e30 / vestingPeriod;

        assertEq(rdToken.freeUnderlying(),      depositAmount);
        assertEq(rdToken.totalHoldings(),       depositAmount);
        assertEq(rdToken.exchangeRate(),        1e30);
        assertEq(rdToken.issuanceRate(),        expectedRate);
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), start + vestingPeriod);

        // Warp and assert vesting in 10% increments
        for (uint256 i = 1; i < 10; ++i) {
            vm.warp(start + vestingPeriod * i / 10);  // 10% intervals of vesting schedule

            uint256 expectedTotalHoldings = depositAmount + expectedRate * (block.timestamp - start) / 1e30;

            assertWithinDiff(rdToken.balanceOfUnderlying(address(staker)), expectedTotalHoldings, 1);

            assertEq(rdToken.totalHoldings(), expectedTotalHoldings);
            assertEq(rdToken.exchangeRate(),  expectedTotalHoldings * 1e30 / depositAmount);
        }

        vm.warp(start + vestingPeriod);

        uint256 expectedFinalTotal = depositAmount + vestingAmount;

        // TODO: Try assertEq
        assertWithinDiff(rdToken.balanceOfUnderlying(address(staker)), expectedFinalTotal, 2);

        assertWithinDiff(rdToken.totalHoldings(), expectedFinalTotal,                             1);
        assertWithinDiff(rdToken.exchangeRate(),  rdToken.totalHoldings() * 1e30 / depositAmount, 1);  // Using totalHoldings because of rounding

        assertEq(underlying.balanceOf(address(rdToken)), depositAmount + vestingAmount);

        assertEq(underlying.balanceOf(address(staker)), 0);
        assertEq(rdToken.balanceOf(address(staker)),    depositAmount);

        staker.rdToken_redeem(address(rdToken), depositAmount);  // Use `redeem` so rdToken amount can be used to burn 100% of tokens

        assertWithinDiff(rdToken.freeUnderlying(), 0, 1);
        assertWithinDiff(rdToken.totalHoldings(),  0, 1);

        assertEq(rdToken.exchangeRate(),        1e30);                   // Exchange rate returns to zero when empty
        assertEq(rdToken.issuanceRate(),        expectedRate);           // TODO: Investigate implications of non-zero issuanceRate here
        assertEq(rdToken.lastUpdated(),         start + vestingPeriod);  // This makes issuanceRate * time zero
        assertEq(rdToken.vestingPeriodFinish(), start + vestingPeriod);

        assertWithinDiff(underlying.balanceOf(address(rdToken)), 0, 2);

        assertEq(rdToken.balanceOfUnderlying(address(staker)), 0);

        assertWithinDiff(underlying.balanceOf(address(staker)), depositAmount + vestingAmount, 2);
        assertWithinDiff(rdToken.balanceOf(address(staker)),    0,                             1);
    }

    function _depositAndUpdateVesting(uint256 vestingAmount_, uint256 vestingPeriod_) internal {
        underlying.mint(address(this), vestingAmount_);
        underlying.transfer(address(rdToken), vestingAmount_);
        rdToken.updateVestingSchedule(vestingPeriod_);
    }
}
