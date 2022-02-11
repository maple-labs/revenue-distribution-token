// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { TestUtils } from "../../lib/contract-test-utils/contracts/test.sol";
import { MockERC20 } from "../../lib/erc20/src/test/mocks/MockERC20.sol";

import { InvariantERC20User } from "./accounts/ERC20User.sol";
import { InvariantOwner }     from "./accounts/Owner.sol";
import { InvariantStaker }    from "./accounts/Staker.sol";
import { Warper }             from "./accounts/Warper.sol";

import { Vm } from "../interfaces/Interfaces.sol";

import { InvariantTest } from "./utils/InvariantTest.sol";
import { RDT_setOwner }  from "./utils/RDTSetOwner.sol";

// Invariant 1: totalHoldings <= underlying balance of contract (with rounding)
// Invariant 2: ∑balanceOfUnderlying == totalHoldings (with rounding)
// Invariant 3: totalSupply <= totalHoldings
// Invariant 4: totalSupply * exchangeRate == totalHoldings (with rounding)
// Invariant 5: exchangeRate >= 1e27
// Invariant 6: freeUnderlying <= totalHoldings
// Invariant 7: balanceOfUnderlying >= balanceOf

contract RDTInvariants is TestUtils, InvariantTest {

    InvariantERC20User erc20User;
    InvariantOwner     owner;
    InvariantStaker    staker1;
    InvariantStaker    staker2;
    InvariantStaker    staker3;
    MockERC20          underlying;
    RDT_setOwner       rdToken;
    Warper             warper;

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        underlying = new MockERC20("MockToken", "MT", 18);
        rdToken    = new RDT_setOwner("Revenue Distribution Token", "RDT", address(this), address(underlying), 1e30);
        erc20User  = new InvariantERC20User(address(rdToken), address(underlying));
        owner      = new InvariantOwner(address(rdToken), address(underlying));
        staker1    = new InvariantStaker(address(rdToken), address(underlying));
        staker2    = new InvariantStaker(address(rdToken), address(underlying));
        staker3    = new InvariantStaker(address(rdToken), address(underlying));
        warper     = new Warper();

        // Required to prevent `acceptOwner` from being a target function
        // TODO: Investigate hevm.store error: `hevm: internal error: unexpected failure code`
        rdToken.setOwner(address(owner));

        addTargetContract(address(erc20User));
        addTargetContract(address(owner));
        addTargetContract(address(staker1));
        addTargetContract(address(staker2));
        addTargetContract(address(staker3));
        addTargetContract(address(warper));
    }

    function invariant1_totalHoldings_lte_underlyingBal() public {
        assertTrue(rdToken.totalHoldings() <= underlying.balanceOf(address(rdToken)));
    }

    function invariant2_sumBalanceOfUnderlying_eq_totalHoldings() public {
        // Only relevant if deposits exist
        if(rdToken.totalSupply() > 0) {
            uint256 sumBalanceOfUnderlying =
                rdToken.balanceOfUnderlying(address(staker1)) +
                rdToken.balanceOfUnderlying(address(staker2)) +
                rdToken.balanceOfUnderlying(address(staker3));

            assertTrue(sumBalanceOfUnderlying <= rdToken.totalHoldings());
            assertWithinDiff(sumBalanceOfUnderlying, rdToken.totalHoldings(), 3);  // Three users, causing three rounding errors
        }
    }

    function invariant3_totalSupply_lte_totalHoldings() external {
        assertTrue(rdToken.totalSupply() <= rdToken.totalHoldings());
    }

    function invariant4_totalSupply_times_exchangeRate_eq_totalHoldings() external {
        assertWithinDiff(rdToken.totalSupply() * rdToken.exchangeRate() / rdToken.precision(), rdToken.totalHoldings(), 1);  // One division
    }

    function invariant5_exchangeRate_gte_precision() external {
        assertTrue(rdToken.exchangeRate() >= rdToken.precision());
    }

    function invariant6_freeUnderlying_lte_totalHoldings() external {
        assertTrue(rdToken.freeUnderlying() <= rdToken.totalHoldings());
    }

    function invariant7_balanceOfUnderlying_gte_balanceOf() public {
        assertTrue(rdToken.balanceOfUnderlying(address(staker1)) >= rdToken.balanceOf(address(staker1)));
        assertTrue(rdToken.balanceOfUnderlying(address(staker2)) >= rdToken.balanceOf(address(staker2)));
        assertTrue(rdToken.balanceOfUnderlying(address(staker3)) >= rdToken.balanceOf(address(staker3)));
    }

}
