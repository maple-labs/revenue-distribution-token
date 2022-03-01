// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { IERC4626 } from "./IERC4626.sol";

// TODO: Add natspec + inherit from IERC4626 once spec is well defined.
interface IRevenueDistributionToken is IERC4626 {

    /***********************/
    /*** State Variables ***/
    /***********************/

    function freeAssets() external view returns (uint256 freeAssets_);
    function issuanceRate() external view returns (uint256 issuanceRate_);
    function lastUpdated() external view returns (uint256 lastUpdated_);
    function owner() external view returns (address owner_);
    function pendingOwner() external view returns (address pendingOwner_);
    function precision() external view returns (uint256 precision_);
    function vestingPeriodFinish() external view returns (uint256 vestingPeriodFinish_);

    /********************************/
    /*** Administrative Functions ***/
    /********************************/

    function acceptOwnership() external;
    function setPendingOwner(address pendingOwner_) external;
    function updateVestingSchedule(uint256 vestingPeriod_) external returns (uint256 issuanceRate_, uint256 freeAssets_);

    /**********************/
    /*** View Functions ***/
    /**********************/

    function APR() external view returns (uint256 APR_);
    function balanceOfAssets(address account) external view returns (uint256 balanceOfAssets_);

}
