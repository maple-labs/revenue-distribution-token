// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import { DSTest }    from "lib/ds-test/src/test.sol";
import { MockERC20 } from "lib/erc20/src/test/mocks/MockERC20.sol";

import { Staker } from "./accounts/Staker.sol";

import { RevenueDistributionToken } from "../RevenueDistributionToken.sol";

interface Vm {
    function expectRevert(bytes calldata error) external;
    function warp(uint256 timestamp) external;
}

contract EntryExitTest is DSTest {

    MockERC20 underlying;

    RevenueDistributionToken rdToken;

    bytes constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        underlying = new MockERC20("MockToken", "MT", 18);
        rdToken    = new RevenueDistributionToken("Revenue Distribution Token", "RDT", address(underlying));
    }

    function constrictToRange(uint256 input, uint256 min, uint256 max) internal pure returns (uint256 output) {
        return min == max ? max : input % (max - min) + min;
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
        assertEq(rdToken.exchangeRate(),                 1e18);

        vm.expectRevert("RDT:D:TRANSFER_FROM");
        staker.rdToken_deposit(address(rdToken), depositAmount);

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        assertEq(underlying.balanceOf(address(staker)),  0);
        assertEq(underlying.balanceOf(address(rdToken)), depositAmount);
        assertEq(rdToken.balanceOf(address(staker)),     depositAmount);
        assertEq(rdToken.totalHoldings(),                depositAmount);
        assertEq(rdToken.exchangeRate(),                 1e18);
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
        assertEq(rdToken.exchangeRate(),                 1e18);

        vm.expectRevert(ARITHMETIC_ERROR);  // Arithmetic error
        staker.rdToken_withdraw(address(rdToken), depositAmount + 1);
        staker.rdToken_withdraw(address(rdToken), depositAmount);

        assertEq(underlying.balanceOf(address(staker)),  depositAmount);
        assertEq(underlying.balanceOf(address(rdToken)), 0);
        assertEq(rdToken.balanceOf(address(staker)),     0);
        assertEq(rdToken.totalHoldings(),                0);
        assertEq(rdToken.exchangeRate(),                 1e18);
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
        assertEq(rdToken.exchangeRate(),                 1e18);

        staker.rdToken_redeem(address(rdToken), depositAmount);

        assertEq(underlying.balanceOf(address(staker)),  depositAmount);
        assertEq(underlying.balanceOf(address(rdToken)), 0);
        assertEq(rdToken.balanceOf(address(staker)),     0);
        assertEq(rdToken.totalHoldings(),                0);
        assertEq(rdToken.exchangeRate(),                 1e18);
    }
}

contract RevenueStreamingTest is DSTest {

    MockERC20 underlying;
    RevenueDistributionToken rdToken;

    bytes constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        underlying = new MockERC20("MockToken", "MT", 18);
        rdToken    = new RevenueDistributionToken("Revenue Distribution Token", "RDT", address(underlying));
    }

    function constrictToRange(uint256 input, uint256 min, uint256 max) internal pure returns (uint256 output) {
        return min == max ? max : input % (max - min) + min;
    }

    function test_vesting_singleSchedule(/*uint256 depositAmount, uint256 vestingAmount, uint256 vestingPeriod*/) public {
        uint256 depositAmount = 0;
        uint256 vestingAmount = 0;
        uint256 vestingPeriod = 1;
        depositAmount = constrictToRange(depositAmount, 10,         1e45);
        vestingAmount = constrictToRange(vestingAmount, 10,         1e45);
        vestingPeriod = constrictToRange(vestingPeriod, 10 seconds, 10_000_000 days);  // TODO: Add a zero case test

        emit log_named_uint("depositAmount", depositAmount);
        emit log_named_uint("vestingAmount", vestingAmount);
        emit log_named_uint("vestingPeriod", vestingPeriod);

        Staker staker = new Staker();

        underlying.mint(address(staker), depositAmount);

        staker.erc20_approve(address(underlying), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        uint256 start = block.timestamp;

        assertEq(rdToken.freeUnderlying(),      depositAmount);
        assertEq(rdToken.totalHoldings(),       depositAmount);
        assertEq(rdToken.exchangeRate(),        1 ether);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), 0);

        vm.warp(start + 1 days);

        assertEq(rdToken.totalHoldings(),  depositAmount);  // No change

        vm.warp(start);  // Warp back after demonstrating totalHoldings is not time-dependent before vesting starts

        underlying.mint(address(this), vestingAmount);
        underlying.approve(address(rdToken), vestingAmount);
        rdToken.depositVestingEarnings(vestingAmount, vestingPeriod);

        uint256 expectedRate = vestingAmount / vestingPeriod;

        assertEq(rdToken.freeUnderlying(),      depositAmount);
        assertEq(rdToken.totalHoldings(),       depositAmount);
        assertEq(rdToken.exchangeRate(),        1 ether);
        assertEq(rdToken.issuanceRate(),        expectedRate);
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), start + vestingPeriod);

        // Warp and assert vesting in 10% increments
        for (uint256 i = 1; i < 10; ++i) {
            emit log_named_uint("i", i);
            vm.warp(start + vestingPeriod * i / 10);  // 10% intervals of vesting schedule

            uint256 expectedTotalHoldings = expectedRate * (block.timestamp - start) + depositAmount;

            emit log_named_uint("vestingAmount", vestingAmount);
            emit log_named_uint("vestingPeriod", vestingPeriod);
            emit log_named_uint("expectedRate", expectedRate);
            emit log_named_uint("expectedTotalHoldings", expectedTotalHoldings);

            assertEq(rdToken.totalHoldings(), expectedTotalHoldings);
            assertEq(rdToken.exchangeRate(),  expectedTotalHoldings * 1e18 / depositAmount);
        }

        vm.warp(start + vestingPeriod);

        assertEq(rdToken.totalHoldings(), depositAmount + vestingAmount);
        assertEq(rdToken.exchangeRate(), (depositAmount + vestingAmount) * 1e18 / depositAmount);
    }
}
