// // Invariant 1: totalHoldings <= underlying balance of contract (with rounding)
// // Invariant 2: ∑balanceOfUnderlying == totalHoldings (with rounding)
// // Invariant 3: totalSupply <= totalHoldings
// // Invariant 4: totalSupply * exchangeRate == totalHoldings (with rounding)
// // Invariant 5: exchangeRate >= 1e27
// // Invariant 6: freeUnderlying <= totalHoldings

// // SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity ^0.8.7;

// import { TestUtils } from "lib/contract-test-utils/contracts/test.sol";
// import { MockERC20 } from "lib/erc20/src/test/mocks/MockERC20.sol";

// import { Staker } from "./accounts/Staker.sol";

// import { RevenueDistributionToken } from "../RevenueDistributionToken.sol";

// contract RDTInvariants is TestUtils, InvariantTest {

//     MockERC20                underlying;
//     RevenueDistributionToken rdToken;
//     Staker                   staker;

//     Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

//     function setUp() public {
//         underlying = new MockERC20("MockToken", "MT", 18);
//         rdToken    = new RevenueDistributionToken("Revenue Distribution Token", "RDT", address(underlying));
//         staker     = new Staker();
//         addTargetContract(address(staker));
//     }
// }

// contract InvariantStaker is Staker {

//     uint256 public sum;

//     function mint(address account, uint256 amount) external {
//         token.mint(account, amount);
//         sum += amount;
//     }

//     function burn(address account, uint256 amount) external {
//         token.burn(account, amount);
//         sum -= amount;
//     }

//     function approve(address dst, uint256 amount) external {
//         token.approve(dst, amount);
//     }

//     function transferFrom(address src, address dst, uint256 amount) external {
//         token.transferFrom(src, dst, amount);
//     }

//     function transfer(address dst, uint256 amount) external {
//         token.transfer(dst, amount);
//     }

// }


// pragma solidity ^0.8.7;

// contract InvariantTest {

//     address[] private _targetContracts;

//     function targetContracts() public view returns (address[] memory targetContracts_) {
//         require(_targetContracts.length != uint256(0), "NO_TARGET_CONTRACTS");
//         return _targetContracts;
//     }

//     function addTargetContract(address newTargetContract_) internal {
//         _targetContracts.push(newTargetContract_);
//     }

// }