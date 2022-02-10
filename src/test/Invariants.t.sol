// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

contract InvariantTest {

    address[] private _targetContracts;

    function targetContracts() public view returns (address[] memory targetContracts_) {
        require(_targetContracts.length != uint256(0), "NO_TARGET_CONTRACTS");
        return _targetContracts;
    }

    function addTargetContract(address newTargetContract_) internal {
        _targetContracts.push(newTargetContract_);
    }

}

interface Hevm {
    function expectRevert(bytes calldata error_) external;
    function store(address contract_, bytes32 location_, bytes32 value_) external view;
    function warp(uint256 timestamp_) external;
}

// Invariant 1: totalHoldings <= underlying balance of contract (with rounding)
// Invariant 2: ∑balanceOfUnderlying == totalHoldings (with rounding)
// Invariant 3: totalSupply <= totalHoldings
// Invariant 4: totalSupply * exchangeRate == totalHoldings (with rounding)
// Invariant 5: exchangeRate >= 1e27
// Invariant 6: freeUnderlying <= totalHoldings

import { TestUtils } from "lib/contract-test-utils/contracts/test.sol";
import { MockERC20 } from "lib/erc20/src/test/mocks/MockERC20.sol";

import { InvariantERC20User }  from "./accounts/ERC20User.sol";
import { InvariantOwner }      from "./accounts/Owner.sol";
import { InvariantStaker }     from "./accounts/Staker.sol";

import { RevenueDistributionToken } from "../RevenueDistributionToken.sol";

contract RDT_setOwner is RevenueDistributionToken {

    constructor(string memory name_, string memory symbol_, address owner_, address underlying_)
        RevenueDistributionToken(name_, symbol_, owner_, underlying_)
    { }

    function setOwner(address owner_) external {
        owner = owner_;
    }

}

contract RDTInvariants is TestUtils, InvariantTest {

    InvariantERC20User erc20User;
    InvariantOwner     owner;
    InvariantStaker    staker1;
    InvariantStaker    staker2;
    InvariantStaker    staker3;
    MockERC20          underlying;
    RDT_setOwner       rdToken;

    Hevm hevm = Hevm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    function setUp() public {
        underlying = new MockERC20("MockToken", "MT", 18);
        rdToken    = new RDT_setOwner("Revenue Distribution Token", "RDT", address(this), address(underlying));
        erc20User  = new InvariantERC20User(address(rdToken), address(underlying));
        owner      = new InvariantOwner(address(rdToken));
        staker1    = new InvariantStaker(address(rdToken), address(underlying));
        staker2    = new InvariantStaker(address(rdToken), address(underlying));
        staker3    = new InvariantStaker(address(rdToken), address(underlying));

        // Required to prevent `acceptOwner` from being a target function
        // TODO: Investigate hevm.store error: `hevm: internal error: unexpected failure code`
        rdToken.setOwner(address(owner));

        // addTargetContract(address(erc20User));
        // addTargetContract(address(owner));
        addTargetContract(address(staker1));
        // addTargetContract(address(staker2));
        // addTargetContract(address(staker3));
    }

    function invariant_balanceSum() public {
        assertEq(rdToken.balanceOf(address(staker1)), staker1.amountDeposited());
    }
}
