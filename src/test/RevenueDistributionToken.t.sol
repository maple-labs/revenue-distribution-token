// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import { TestUtils } from "lib/contract-test-utils/contracts/test.sol";
import { MockERC20 } from "lib/erc20/src/test/mocks/MockERC20.sol";

import { Staker } from "./accounts/Staker.sol";

import { RevenueDistributionToken } from "../RevenueDistributionToken.sol";

interface Vm {
    function expectRevert(bytes calldata error) external;
    function warp(uint256 timestamp) external;
}

contract EntryExitTest is TestUtils {

    MockERC20 underlying;

    RevenueDistributionToken rdToken;

    bytes constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        underlying = new MockERC20("MockToken", "MT", 18);
        rdToken    = new RevenueDistributionToken("Revenue Distribution Token", "RDT", address(underlying));
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
        assertEq(rdToken.exchangeRate(),                 1e27);

        vm.expectRevert("RDT:D:TRANSFER_FROM");
        staker.rdToken_deposit(address(rdToken), depositAmount);

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        assertEq(underlying.balanceOf(address(staker)),  0);
        assertEq(underlying.balanceOf(address(rdToken)), depositAmount);
        assertEq(rdToken.balanceOf(address(staker)),     depositAmount);
        assertEq(rdToken.totalHoldings(),                depositAmount);
        assertEq(rdToken.exchangeRate(),                 1e27);
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
        assertEq(rdToken.exchangeRate(),                 1e27);

        vm.expectRevert(ARITHMETIC_ERROR);  // Arithmetic error
        staker.rdToken_withdraw(address(rdToken), depositAmount + 1);
        staker.rdToken_withdraw(address(rdToken), depositAmount);

        assertEq(underlying.balanceOf(address(staker)),  depositAmount);
        assertEq(underlying.balanceOf(address(rdToken)), 0);
        assertEq(rdToken.balanceOf(address(staker)),     0);
        assertEq(rdToken.totalHoldings(),                0);
        assertEq(rdToken.exchangeRate(),                 1e27);
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
        assertEq(rdToken.exchangeRate(),                 1e27);

        staker.rdToken_redeem(address(rdToken), depositAmount);

        assertEq(underlying.balanceOf(address(staker)),  depositAmount);
        assertEq(underlying.balanceOf(address(rdToken)), 0);
        assertEq(rdToken.balanceOf(address(staker)),     0);
        assertEq(rdToken.totalHoldings(),                0);
        assertEq(rdToken.exchangeRate(),                 1e27);
    }
}

contract RevenueStreamingTest is TestUtils {

    MockERC20 underlying;
    RevenueDistributionToken rdToken;

    bytes constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        underlying = new MockERC20("MockToken", "MT", 18);
        rdToken    = new RevenueDistributionToken("Revenue Distribution Token", "RDT", address(underlying));
    }

    function test_vesting_singleSchedule_explicit_vals() public {
        uint256 depositAmount = 1_000_000 ether;
        uint256 vestingAmount = 100_000 ether;
        uint256 vestingPeriod = 200_000 seconds;

        Staker staker = new Staker();

        underlying.mint(address(staker), depositAmount);

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        uint256 start = block.timestamp;

        assertEq(rdToken.freeUnderlying(),      1_000_000 ether);
        assertEq(rdToken.totalHoldings(),       1_000_000 ether);
        assertEq(rdToken.exchangeRate(),        1e27);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), 0);

        vm.warp(start + 1 days);

        assertEq(rdToken.totalHoldings(),  1_000_000 ether);  // No change

        vm.warp(start);  // Warp back after demonstrating totalHoldings is not time-dependent before vesting starts

        underlying.mint(address(this), vestingAmount);
        underlying.approve(address(rdToken), vestingAmount);
        rdToken.depositVestingEarnings(vestingAmount, vestingPeriod);

        assertEq(rdToken.freeUnderlying(),      1_000_000 ether);
        assertEq(rdToken.totalHoldings(),       1_000_000 ether);
        assertEq(rdToken.exchangeRate(),        1e27);
        assertEq(rdToken.issuanceRate(),        0.5 ether * 1e27);  // 0.5 tokens per second
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), start + vestingPeriod);

        // Warp and assert vesting in 10% increments
        vm.warp(start + 20_000 seconds);  // 10% of vesting schedule

        assertEq(rdToken.balanceOfUnderlying(address(staker)), 1_010_000 ether);
        assertEq(rdToken.totalHoldings(),                      1_010_000 ether);
        assertEq(rdToken.exchangeRate(),                       1.01e27);

        vm.warp(start + 40_000 seconds);  // 20% of vesting schedule

        assertEq(rdToken.balanceOfUnderlying(address(staker)), 1_020_000 ether);
        assertEq(rdToken.totalHoldings(),                      1_020_000 ether);
        assertEq(rdToken.exchangeRate(),                       1.02e27);

        vm.warp(start + 60_000 seconds);  // 30% of vesting schedule

        assertEq(rdToken.balanceOfUnderlying(address(staker)), 1_030_000 ether);
        assertEq(rdToken.totalHoldings(),                      1_030_000 ether);
        assertEq(rdToken.exchangeRate(),                       1.03e27);

        vm.warp(start + 200_000 seconds);  // End of vesting schedule

        assertEq(rdToken.balanceOfUnderlying(address(staker)), 1_100_000 ether);
        assertEq(rdToken.totalHoldings(),                      1_100_000 ether);
        assertEq(rdToken.exchangeRate(),                       1.1e27);

        assertEq(underlying.balanceOf(address(rdToken)), 1_100_000 ether);
        assertEq(underlying.balanceOf(address(staker)),  0);
        assertEq(rdToken.balanceOf(address(staker)),     1_000_000 ether);

        staker.rdToken_redeem(address(rdToken), 1_000_000 ether);  // Use `redeem` so rdToken amount can be used to burn 100% of tokens

        assertEq(rdToken.freeUnderlying(),      0);
        assertEq(rdToken.totalHoldings(),       0);
        assertEq(rdToken.exchangeRate(),        1e27);                     // Exchange rate returns to 1 when empty
        assertEq(rdToken.issuanceRate(),        0.5 ether * 1e27);         // TODO: Investigate implications of non-zero issuanceRate here
        assertEq(rdToken.lastUpdated(),         start + 200_000 seconds);  // This makes issuanceRate * time zero
        assertEq(rdToken.vestingPeriodFinish(), start + 200_000 seconds);

        assertEq(underlying.balanceOf(address(rdToken)),       0);
        assertEq(rdToken.balanceOfUnderlying(address(staker)), 0);

        assertEq(underlying.balanceOf(address(staker)), 1_100_000 ether);
        assertEq(rdToken.balanceOf(address(staker)),    0);
    }

    function test_vesting_singleSchedule_fuzz(uint256 depositAmount, uint256 vestingAmount, uint256 vestingPeriod) public {
        depositAmount = constrictToRange(depositAmount, 1e6,        1e27);                    // 1 billion at WAD precision
        vestingAmount = constrictToRange(vestingAmount, 1e6,        1e27);                    // 1 billion at WAD precision
        vestingPeriod = constrictToRange(vestingPeriod, 10 seconds, 100_000 days) / 10 * 10;  // Must be divisible by 10 for for loop 10% increment calculations // TODO: Add a zero case test

        Staker staker = new Staker();

        underlying.mint(address(staker), depositAmount);

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        uint256 start = block.timestamp;

        assertEq(rdToken.freeUnderlying(),      depositAmount);
        assertEq(rdToken.totalHoldings(),       depositAmount);
        assertEq(rdToken.exchangeRate(),        1e27);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), 0);

        vm.warp(start + 1 days);

        assertEq(rdToken.totalHoldings(),  depositAmount);  // No change

        vm.warp(start);  // Warp back after demonstrating totalHoldings is not time-dependent before vesting starts

        underlying.mint(address(this), vestingAmount);
        underlying.approve(address(rdToken), vestingAmount);
        rdToken.depositVestingEarnings(vestingAmount, vestingPeriod);

        uint256 expectedRate = vestingAmount * 1e27 / vestingPeriod;

        assertEq(rdToken.freeUnderlying(),      depositAmount);
        assertEq(rdToken.totalHoldings(),       depositAmount);
        assertEq(rdToken.exchangeRate(),        1e27);
        assertEq(rdToken.issuanceRate(),        expectedRate);
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), start + vestingPeriod);

        // Warp and assert vesting in 10% increments
        for (uint256 i = 1; i < 2; ++i) {
            vm.warp(start + vestingPeriod * i / 10);  // 10% intervals of vesting schedule

            uint256 expectedTotalHoldings = depositAmount + expectedRate * (block.timestamp - start) / 1e27;

            assertWithinDiff(rdToken.balanceOfUnderlying(address(staker)), expectedTotalHoldings, 1);

            assertEq(rdToken.totalHoldings(), expectedTotalHoldings);
            assertEq(rdToken.exchangeRate(),  expectedTotalHoldings * 1e27 / depositAmount);
        }

        vm.warp(start + vestingPeriod);

        uint256 expectedFinalTotal = depositAmount + vestingAmount;

        assertWithinDiff(rdToken.balanceOfUnderlying(address(staker)), expectedFinalTotal, 2);

        assertWithinDiff(rdToken.totalHoldings(), expectedFinalTotal,                             1);
        assertWithinDiff(rdToken.exchangeRate(),  rdToken.totalHoldings() * 1e27 / depositAmount, 1);  // Using totalHoldings because of rounding

        assertEq(underlying.balanceOf(address(rdToken)), depositAmount + vestingAmount);

        assertEq(underlying.balanceOf(address(staker)), 0);
        assertEq(rdToken.balanceOf(address(staker)),    depositAmount);

        staker.rdToken_redeem(address(rdToken), depositAmount);  // Use `redeem` so rdToken amount can be used to burn 100% of tokens

        assertWithinDiff(rdToken.freeUnderlying(), 0, 1);
        assertWithinDiff(rdToken.totalHoldings(),  0, 1);
        assertEq(rdToken.exchangeRate(),        1e27);                   // Exchange rate returns to zero when empty
        assertEq(rdToken.issuanceRate(),        expectedRate);           // TODO: Investigate implications of non-zero issuanceRate here
        assertEq(rdToken.lastUpdated(),         start + vestingPeriod);  // This makes issuanceRate * time zero
        assertEq(rdToken.vestingPeriodFinish(), start + vestingPeriod);

        assertWithinDiff(underlying.balanceOf(address(rdToken)), 0, 2);

        assertEq(rdToken.balanceOfUnderlying(address(staker)), 0);

        assertWithinDiff(underlying.balanceOf(address(staker)), depositAmount + vestingAmount, 2);
        assertWithinDiff(rdToken.balanceOf(address(staker)),    0,                             1);
    }
}
