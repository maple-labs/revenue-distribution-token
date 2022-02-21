// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { IERC20 } from "../../lib/erc20/src/interfaces/IERC20.sol";

// TODO: Add natspec + inherit from IERC4626 once spec is well defined.
interface IRevenueDistributionToken is IERC20 {

    /**************/
    /*** Events ***/
    /**************/

    event Deposit(address indexed from, uint256 value);
    event Withdraw(address indexed to, uint256 value);

    /***********************/
    /*** State Variables ***/
    /***********************/

    function freeUnderlying() external view returns (uint256 freeUnderlying_);
    function issuanceRate() external view returns (uint256 issuanceRate_);
    function lastUpdated() external view returns (uint256 lastUpdated_);
    function owner() external view returns (address owner_);
    function pendingOwner() external view returns (address pendingOwner_);
    function precision() external view returns (uint256 precision_);
    function underlying() external view returns (address underlying_);
    function vestingPeriodFinish() external view returns (uint256 vestingPeriodFinish_);

    /********************************/
    /*** Administrative Functions ***/
    /********************************/

    function acceptOwnership() external;
    function setPendingOwner(address pendingOwner_) external;
    function updateVestingSchedule(uint256 vestingPeriod_) external returns (uint256 issuanceRate_, uint256 freeUnderlying_);

    /************************/
    /*** Staker Functions ***/
    /************************/

    function deposit(uint256 amount_) external returns (uint256 shares_);
    function redeem(uint256 rdTokenAmount_) external returns (uint256 underlyingAmount_);
    function withdraw(uint256 underlyingAmount_) external returns (uint256 shares_);

    /**********************/
    /*** View Functions ***/
    /**********************/

    function APR() external view returns (uint256 APR_);
    function balanceOfUnderlying(address account) external view returns (uint256 balanceOfUnderlying_);
    function exchangeRate() external view returns (uint256 exchangeRate_);
    function previewDeposit(uint256 underlyingAmount) external view returns (uint256 shareAmount);
    function previewWithdraw(uint256 underlyingAmount) external view returns (uint256 shareAmount);
    function previewRedeem(uint256 shareAmount) external view returns (uint256 underlyingAmount);
    function totalHoldings() external view returns (uint256 totalHoldings_);

}
