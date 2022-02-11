// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

<<<<<<< HEAD
import { InvariantTest, TestUtils } from "../../lib/contract-test-utils/contracts/test.sol";
import { MockERC20 }                from "../../lib/erc20/src/test/mocks/MockERC20.sol";

import { InvariantERC20User }     from "./accounts/ERC20User.sol";
import { InvariantOwner }         from "./accounts/Owner.sol";
import { InvariantStakerManager } from "./accounts/Staker.sol";
import { Warper }                 from "./accounts/Warper.sol";

import { MutableRDT } from "./utils/MutableRDT.sol";
=======
import { TestUtils } from "../../lib/contract-test-utils/contracts/test.sol";
import { MockERC20 } from "../../lib/erc20/src/test/mocks/MockERC20.sol";

import { InvariantERC20User } from "./accounts/ERC20User.sol";
import { InvariantOwner }     from "./accounts/Owner.sol";
import { InvariantStaker }    from "./accounts/Staker.sol";
import { Warper }             from "./accounts/Warper.sol";

import { Vm } from "../interfaces/Interfaces.sol";

import { InvariantTest } from "./utils/InvariantTest.sol";
import { RDT_setOwner }  from "./utils/RDTSetOwner.sol";
>>>>>>> 0451150 (feat: all invariant testing passing, added precision variable)

// Invariant 1: totalHoldings <= underlying balance of contract (with rounding)
// Invariant 2: ∑balanceOfUnderlying == totalHoldings (with rounding)
// Invariant 3: totalSupply <= totalHoldings
// Invariant 4: totalSupply * exchangeRate == totalHoldings (with rounding)
// Invariant 5: exchangeRate >= `precision`
// Invariant 6: freeUnderlying <= totalHoldings
// Invariant 7: balanceOfUnderlying >= balanceOf
<<<<<<< HEAD

contract RDTInvariants is TestUtils, InvariantTest {

    InvariantERC20User     erc20User;
    InvariantOwner         owner;
    InvariantStakerManager stakerManager;
    MockERC20              underlying;
    MutableRDT             rdToken;
    Warper                 warper;

    function setUp() public virtual {
        underlying    = new MockERC20("MockToken", "MT", 18);
        rdToken       = new MutableRDT("Revenue Distribution Token", "RDT", address(this), address(underlying), 1e30);
        erc20User     = new InvariantERC20User(address(rdToken), address(underlying));
        stakerManager = new InvariantStakerManager(address(rdToken), address(underlying));
        owner         = new InvariantOwner(address(rdToken), address(underlying));
        warper        = new Warper();

        // Required to prevent `acceptOwner` from being a target function
        // TODO: Investigate hevm.store error: `hevm: internal error: unexpected failure code`
        rdToken.setOwner(address(owner));

        // Performs random transfers of underlying into contract
        addTargetContract(address(erc20User));

        // Performs random transfers of underlying into contract
        // Performs random updateVestingSchedule calls
        addTargetContract(address(owner));

        // Performs random instantiations of new staker users
        // Performs random deposit calls from a random instantiated staker
        // Performs random withdraw calls from a random instantiated staker
        // Performs random redeem calls from a random instantiated staker
        addTargetContract(address(stakerManager));

        // Peforms random warps forward in time
        addTargetContract(address(warper));

        // Create one staker to prevent underflows on index calculations
        stakerManager.createStaker();
    }

    function invariant1_totalHoldings_lte_underlyingBal() public {
        assertTrue(rdToken.totalHoldings() <= underlying.balanceOf(address(rdToken)));
    }
=======
>>>>>>> 0451150 (feat: all invariant testing passing, added precision variable)

    function invariant2_sumBalanceOfUnderlying_eq_totalHoldings() public {
        // Only relevant if deposits exist
        if(rdToken.totalSupply() > 0) {
            uint256 sumBalanceOfUnderlying;
            uint256 stakerCount = stakerManager.getStakerCount();

<<<<<<< HEAD
            for(uint256 i; i < stakerCount; ++i) {
                sumBalanceOfUnderlying += rdToken.balanceOfUnderlying(address(stakerManager.stakers(i)));
            }
=======
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
>>>>>>> 0451150 (feat: all invariant testing passing, added precision variable)

            assertTrue(sumBalanceOfUnderlying <= rdToken.totalHoldings());
            assertWithinDiff(sumBalanceOfUnderlying, rdToken.totalHoldings(), stakerCount);  // Rounding error of one per user
        }
    }

<<<<<<< HEAD
=======
        addTargetContract(address(erc20User));
        addTargetContract(address(owner));
        addTargetContract(address(staker1));
        addTargetContract(address(staker2));
        addTargetContract(address(staker3));
        addTargetContract(address(warper));
    }

    function invariant1_totalHoldings_gte_underlyingBal() public {
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

>>>>>>> 0451150 (feat: all invariant testing passing, added precision variable)
    function invariant3_totalSupply_lte_totalHoldings() external {
        assertTrue(rdToken.totalSupply() <= rdToken.totalHoldings());
    }

    function invariant4_totalSupply_times_exchangeRate_eq_totalHoldings() external {
<<<<<<< HEAD
        if(rdToken.totalSupply() > 0) {
            assertWithinDiff(rdToken.totalSupply() * rdToken.exchangeRate() / rdToken.precision(), rdToken.totalHoldings(), 1);  // One division
        }
=======
        assertWithinDiff(rdToken.totalSupply() * rdToken.exchangeRate() / rdToken.precision(), rdToken.totalHoldings(), 1);  // One division
>>>>>>> 0451150 (feat: all invariant testing passing, added precision variable)
    }

    function invariant5_exchangeRate_gte_precision() external {
        assertTrue(rdToken.exchangeRate() >= rdToken.precision());
    }

    function invariant6_freeUnderlying_lte_totalHoldings() external {
        assertTrue(rdToken.freeUnderlying() <= rdToken.totalHoldings());
    }

    function invariant7_balanceOfUnderlying_gte_balanceOf() public {
<<<<<<< HEAD
        for(uint256 i; i < stakerManager.getStakerCount(); ++i) {
            address staker = address(stakerManager.stakers(i));
            assertTrue(rdToken.balanceOfUnderlying(staker) >= rdToken.balanceOf(staker));
        }
=======
        assertTrue(rdToken.balanceOfUnderlying(address(staker1)) >= rdToken.balanceOf(address(staker1)));
        assertTrue(rdToken.balanceOfUnderlying(address(staker2)) >= rdToken.balanceOf(address(staker2)));
        assertTrue(rdToken.balanceOfUnderlying(address(staker3)) >= rdToken.balanceOf(address(staker3)));
>>>>>>> 0451150 (feat: all invariant testing passing, added precision variable)
    }

}
