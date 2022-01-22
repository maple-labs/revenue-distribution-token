// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import { DSTest }    from "lib/ds-test/src/test.sol";
import { MockERC20 } from "lib/erc20/src/test/mocks/MockERC20.sol";

import { Staker } from "./accounts/Staker.sol";

import { RevenueDistributionToken } from "../RevenueDistributionToken.sol";

interface Vm {
    function expectRevert(bytes calldata) external;
    function warp(uint256 timestamp) external;
}

contract RevenueDistributionTokenTest is DSTest {

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
