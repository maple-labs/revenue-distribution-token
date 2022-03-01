// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { InvariantTest, TestUtils } from "../../modules/contract-test-utils/contracts/test.sol";
import { MockERC20 }                from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { InvariantERC20User }     from "./accounts/ERC20User.sol";
import { InvariantOwner }         from "./accounts/Owner.sol";
import { InvariantStakerManager } from "./accounts/Staker.sol";
import { Warper }                 from "./accounts/Warper.sol";

import { MutableRDT } from "./utils/MutableRDT.sol";

// Invariant 1: totalAssets <= underlying balance of contract (with rounding)
// Invariant 2: ∑balanceOfUnderlying == totalAssets (with rounding)
// Invariant 3: totalSupply <= totalAssets
// Invariant 4: totalSupply * exchangeRate == totalAssets (with rounding)
// Invariant 5: exchangeRate >= `precision`
// Invariant 6: freeUnderlying <= totalAssets
// Invariant 7: balanceOfUnderlying >= balanceOf

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

    function invariant1_totalAssets_lte_underlyingBal() public {
        assertTrue(rdToken.totalAssets() <= underlying.balanceOf(address(rdToken)));
    }

    function invariant2_sumBalanceOfUnderlying_eq_totalAssets() public {
        // Only relevant if deposits exist
        if(rdToken.totalSupply() > 0) {
            uint256 sumBalanceOfUnderlying;
            uint256 stakerCount = stakerManager.getStakerCount();

            for(uint256 i; i < stakerCount; ++i) {
                sumBalanceOfUnderlying += rdToken.balanceOfUnderlying(address(stakerManager.stakers(i)));
            }

            assertTrue(sumBalanceOfUnderlying <= rdToken.totalAssets());
            assertWithinDiff(sumBalanceOfUnderlying, rdToken.totalAssets(), stakerCount);  // Rounding error of one per user
        }
    }

    function invariant3_totalSupply_lte_totalAssets() external {
        assertTrue(rdToken.totalSupply() <= rdToken.totalAssets());
    }

    function invariant4_totalSupply_times_exchangeRate_eq_totalAssets() external {
        if(rdToken.totalSupply() > 0) {
            assertWithinDiff(rdToken.totalSupply() * rdToken.exchangeRate() / rdToken.precision(), rdToken.totalAssets(), 1);  // One division
        }
    }

    function invariant5_exchangeRate_gte_precision() external {
        assertTrue(rdToken.exchangeRate() >= rdToken.precision());
    }

    function invariant6_freeUnderlying_lte_totalAssets() external {
        assertTrue(rdToken.freeUnderlying() <= rdToken.totalAssets());
    }

    function invariant7_balanceOfUnderlying_gte_balanceOf() public {
        for(uint256 i; i < stakerManager.getStakerCount(); ++i) {
            address staker = address(stakerManager.stakers(i));
            assertTrue(rdToken.balanceOfUnderlying(staker) >= rdToken.balanceOf(staker));
        }
    }

}
