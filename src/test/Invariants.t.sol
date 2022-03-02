// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { InvariantTest, TestUtils } from "../../lib/contract-test-utils/contracts/test.sol";
import { MockERC20 }                from "../../lib/erc20/src/test/mocks/MockERC20.sol";

import { InvariantERC20User }     from "./accounts/ERC20User.sol";
import { InvariantOwner }         from "./accounts/Owner.sol";
import { InvariantStakerManager } from "./accounts/Staker.sol";
import { Warper }                 from "./accounts/Warper.sol";

import { MutableRDT } from "./utils/MutableRDT.sol";

// Invariant 1: totalHoldings <= underlying balance of contract (with rounding)
// Invariant 2: ∑balanceOfUnderlying == totalHoldings (with rounding)
// Invariant 3: totalSupply <= totalHoldings
// Invariant 4: totalSupply * exchangeRate == totalHoldings (with rounding)
// Invariant 5: exchangeRate >= `precision`
// Invariant 6: freeUnderlying <= totalHoldings
// Invariant 7: balanceOfUnderlying >= balanceOf

contract RDTInvariantsBase is TestUtils, InvariantTest {

    // Performs random transfers of underlying into contract
    InvariantERC20User     erc20User;

    // Performs random transfers of underlying into contract
    // Performs random updateVestingSchedule calls
    InvariantOwner         owner;

    // Performs random instantiations of new staker users
    // Performs random deposit calls from a random instantiated staker
    // Performs random withdraw calls from a random instantiated staker
    // Performs random redeem calls from a random instantiated staker
    InvariantStakerManager stakerManager;

    MockERC20              underlying;
    MutableRDT             rdToken;

    // Peforms random warps forward in time
    Warper                 warper;

    function setUp() public virtual {
        underlying    = new MockERC20("MockToken", "MT", 18);
        rdToken       = new MutableRDT("Revenue Distribution Token", "RDT", address(this), address(underlying), 1e30);
        erc20User     = new InvariantERC20User(address(rdToken), address(underlying));
        stakerManager = new InvariantStakerManager(address(rdToken), address(underlying), 0, true);
        owner         = new InvariantOwner(address(rdToken), address(underlying));
        warper        = new Warper();

        // Required to prevent `acceptOwner` from being a target function
        // TODO: Investigate hevm.store error: `hevm: internal error: unexpected failure code`
        rdToken.setOwner(address(owner));
        
        addTargetContract(address(erc20User));
        addTargetContract(address(owner));
        addTargetContract(address(stakerManager));

        addTargetContract(address(warper));

        // Create one staker to prevent underflows on index calculations
        stakerManager.createStaker();
    }

    function invariant1_totalHoldings_lte_underlyingBal() public {
        assertTrue(rdToken.totalHoldings() <= underlying.balanceOf(address(rdToken)));
    }

    function invariant2_sumBalanceOfUnderlying_eq_totalHoldings() public {
        // Only relevant if deposits exist
        if(rdToken.totalSupply() > 0) {
            uint256 sumBalanceOfUnderlying;
            uint256 stakerCount = stakerManager.getStakerCount();

            for(uint256 i; i < stakerCount; ++i) {
                sumBalanceOfUnderlying += rdToken.balanceOfUnderlying(address(stakerManager.stakers(i)));
            }

            assertTrue(sumBalanceOfUnderlying <= rdToken.totalHoldings());
            assertWithinDiff(sumBalanceOfUnderlying, rdToken.totalHoldings(), stakerCount);  // Rounding error of one per user
        }
    }

    function invariant3_totalSupply_lte_totalHoldings() external {
        assertTrue(rdToken.totalSupply() <= rdToken.totalHoldings());
    }

    function invariant4_totalSupply_times_exchangeRate_eq_totalHoldings() external {
        if(rdToken.totalSupply() > 0) {
            assertWithinDiff(rdToken.totalSupply() * rdToken.exchangeRate() / rdToken.precision(), rdToken.totalHoldings(), 1);  // One division
        }
    }

    function invariant5_exchangeRate_gte_precision() external {
        assertTrue(rdToken.exchangeRate() >= rdToken.precision());
    }

    function invariant6_freeUnderlying_lte_totalHoldings() external {
        assertTrue(rdToken.freeUnderlying() <= rdToken.totalHoldings());
    }

    function invariant7_balanceOfUnderlying_gte_balanceOf() public {
        for(uint256 i; i < stakerManager.getStakerCount(); ++i) {
            address staker = address(stakerManager.stakers(i));
            assertTrue(rdToken.balanceOfUnderlying(staker) >= rdToken.balanceOf(staker));
        }
    }

}


contract RDTInvariantsConstantExchangeRate is RDTInvariantsBase { 

    uint256 initialExchangeRate;
    uint256 startTime;

    // No warping and no updates to the vesting schedule
    function setUp() public override { 
        // Non zero start time
        vm.warp(10_000);

        underlying    = new MockERC20("MockToken", "MT", 18);
        rdToken       = new MutableRDT("Revenue Distribution Token", "RDT", address(this), address(underlying), 1e30);
        erc20User     = new InvariantERC20User(address(rdToken), address(underlying));
        stakerManager = new InvariantStakerManager(address(rdToken), address(underlying), block.timestamp, false);
        owner         = new InvariantOwner(address(rdToken), address(underlying));
        warper        = new Warper();

        // Required to prevent `acceptOwner` from being a target function
        // TODO: Investigate hevm.store error: `hevm: internal error: unexpected failure code`
        rdToken.setOwner(address(owner));

        addTargetContract(address(erc20User));
        addTargetContract(address(stakerManager));

        // Create one staker to prevent underflows on index calculations
        stakerManager.createStaker();
        stakerManager.deposit(1e30, 0);

        // Do one deposit and update rate
        owner.erc20_transfer(1e45);
        owner.rdToken_updateVestingSchedule(300 days);

        initialExchangeRate = rdToken.exchangeRate();
        startTime           = block.timestamp;
    }

    function invariant8_constantExchangeRate() public {
        vm.warp(startTime);
        assertEq(rdToken.exchangeRate(), initialExchangeRate);
    }

}

contract RDTInvariantsMultipleDeposits is RDTInvariantsBase {

    function setUp() public override {
        super.setUp();

        // Add 50 depositors
        for (uint i = 0; i <= 50; i++) {
            stakerManager.createStaker();

            // Get a more or less random amount between 1 and 1_000_000 ether
            uint256 amt = uint256(keccak256(abi.encode(i, "SALT"))) % 1_000_000 ether + 1;

            stakerManager.deposit(amt, i);
        }

    }

}

contract RDTInvariantsWithdraws is RDTInvariantsBase {

    uint256 initialSupply;

    function setUp() public override {
        super.setUp();

        // Add 50 depositors
        for (uint i = 0; i <= 50; i++) {
            stakerManager.createStaker();

            // Get a more or less random amount between 1 and 1_000_000 ether
            uint256 amt = uint256(keccak256(abi.encode(i, "SALT"))) % 1_000_000 ether + 1;

            stakerManager.deposit(amt, i);
        }

        // Fuzzer can't deposit
        stakerManager.setAllowDeposit(false);

        initialSupply = MockERC20(address(rdToken)).totalSupply();
    }

    function invariant8_supplyDoesNotIncrease() public {
        assertTrue(MockERC20(address(rdToken)).totalSupply() > initialSupply);
    }

}