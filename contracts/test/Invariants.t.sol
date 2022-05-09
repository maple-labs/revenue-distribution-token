// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { InvariantTest, TestUtils } from "../../modules/contract-test-utils/contracts/test.sol";
import { MockERC20 }                from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { InvariantERC20User }     from "./accounts/ERC20User.sol";
import { InvariantOwner }         from "./accounts/Owner.sol";
import { InvariantStakerManager } from "./accounts/Staker.sol";
import { Warper }                 from "./accounts/Warper.sol";

import { MutableRDT } from "./utils/MutableRDT.sol";

// Invariant 1:  totalAssets <= underlying balance of contract (with rounding)
// Invariant 2:  ∑ balanceOfAssets == totalAssets (with rounding)
// Invariant 3:  totalSupply <= totalAssets
// Invariant 4:  convertToAssets(totalSupply) == totalAssets (with rounding)
// Invariant 5:  exchangeRate >= `precision`
// Invariant 6:  freeAssets <= totalAssets
// Invariant 7:  balanceOfAssets >= balanceOf
// Invariant 8:  freeAssets <= underlying balance
// Invariant 9:  issuanceRate == 0 (if post vesting)
// Invariant 10: issuanceRate > 0 (if mid vesting)

contract RDTInvariants is TestUtils, InvariantTest {

    InvariantERC20User     internal _erc20User;
    InvariantOwner         internal _owner;
    InvariantStakerManager internal _stakerManager;
    MockERC20              internal _underlying;
    MutableRDT             internal _rdToken;
    Warper                 internal _warper;

    function setUp() public virtual {
        _underlying    = new MockERC20("MockToken", "MT", 18);
        _rdToken       = new MutableRDT("Revenue Distribution Token", "RDT", address(this), address(_underlying), 1e30);
        _erc20User     = new InvariantERC20User(address(_rdToken), address(_underlying));
        _stakerManager = new InvariantStakerManager(address(_rdToken), address(_underlying));
        _owner         = new InvariantOwner(address(_rdToken), address(_underlying));
        _warper        = new Warper(address(_rdToken));

        // Required to prevent `acceptOwner` from being a target function
        // TODO: Investigate hevm.store error: `hevm: internal error: unexpected failure code`
        _rdToken.setOwner(address(_owner));

        // Performs random transfers of underlying into contract
        addTargetContract(address(_erc20User));

        // Performs random transfers of underlying into contract
        // Performs random updateVestingSchedule calls
        addTargetContract(address(_owner));

        // Performs random instantiations of new staker users
        // Performs random deposit calls from a random instantiated staker
        // Performs random withdraw calls from a random instantiated staker
        // Performs random redeem calls from a random instantiated staker
        addTargetContract(address(_stakerManager));

        // Performs random warps forward in time
        addTargetContract(address(_warper));

        // Create one staker to prevent underflow on index calculations
        _stakerManager.createStaker();
    }

    function invariant_totalAssets_lte_underlyingBalance() public {
        assertTrue(_rdToken.totalAssets() <= _underlying.balanceOf(address(_rdToken)));
    }

    function invariant_sumBalanceOfAssets_eq_totalAssets() public {
        // Only relevant if deposits exist
        if (_rdToken.totalSupply() > 0) {
            uint256 sumBalanceOfAssets;
            uint256 stakerCount = _stakerManager.getStakerCount();

            for (uint256 i; i < stakerCount; ++i) {
                sumBalanceOfAssets += _rdToken.balanceOfAssets(address(_stakerManager.stakers(i)));
            }

            assertTrue(sumBalanceOfAssets <= _rdToken.totalAssets());
            assertWithinDiff(sumBalanceOfAssets, _rdToken.totalAssets(), stakerCount);  // Rounding error of one per user
        }
    }

    function invariant_totalSupply_lte_totalAssets() public {
        assertTrue(_rdToken.totalSupply() <= _rdToken.totalAssets());
    }

    function invariant_totalSupply_times_exchangeRate_eq_totalAssets() public {
        if (_rdToken.totalSupply() > 0) {
            assertWithinDiff(_rdToken.convertToAssets(_rdToken.totalSupply()), _rdToken.totalAssets(), 1);  // One division
        }
    }

    // TODO: figure out if there's a replacement for this one involving convertTo* functions. I think Invariant 3: totalSupply <= totalAssets covers this.
    // function invariant_exchangeRate_gte_precision() public {
    //     assertTrue(_rdToken.exchangeRate() >= _rdToken.precision());
    // }

    function invariant_freeAssets_lte_totalAssets() public {
        assertTrue(_rdToken.freeAssets() <= _rdToken.totalAssets());
    }

    function invariant_balanceOfAssets_gte_balanceOf() public {
        for (uint256 i; i < _stakerManager.getStakerCount(); ++i) {
            address staker = address(_stakerManager.stakers(i));
            assertTrue(_rdToken.balanceOfAssets(staker) >= _rdToken.balanceOf(staker));
        }
    }

    function invariant_freeAssets_lte_underlyingBalance() public {
        assertTrue(_rdToken.freeAssets() <= _underlying.balanceOf(address(_rdToken)));
    }

    function invariant_issuanceRate_eq_zero_ifPostVesting() public {
        if (block.timestamp >= _rdToken.vestingPeriodFinish() && _rdToken.lastUpdated() >= _rdToken.vestingPeriodFinish()) {
            assertTrue(_rdToken.issuanceRate() == 0);
        }
    }

    function invariant_issuanceRate_gt_zero_ifMidVesting() public {
        if (block.timestamp < _rdToken.vestingPeriodFinish()) {
            assertTrue(_rdToken.issuanceRate() > 0);
        }
    }

}
