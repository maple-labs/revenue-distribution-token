// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { IERC4626 } from "./IERC4626.sol";
import { IERC20Permit } from "../../modules/erc20/contracts/interfaces/IERC20Permit.sol";

/// @title ...
interface IRevenueDistributionToken is IERC4626, IERC20Permit {

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     *  @dev ...
     */
    function freeAssets() external view returns (uint256 freeAssets_);

    /**
     *  @dev ...
     */
    function issuanceRate() external view returns (uint256 issuanceRate_);

    /**
     *  @dev ...
     */
    function lastUpdated() external view returns (uint256 lastUpdated_);

    /**
     *  @dev ...
     */
    function owner() external view returns (address owner_);

    /**
     *  @dev ...
     */
    function pendingOwner() external view returns (address pendingOwner_);

    /**
     *  @dev ...
     */
    function precision() external view returns (uint256 precision_);

    /**
     *  @dev ...
     */
    function vestingPeriodFinish() external view returns (uint256 vestingPeriodFinish_);

    /********************************/
    /*** Administrative Functions ***/
    /********************************/

    /**
     *  @dev ...
     */
    function acceptOwnership() external;

    /**
     *  @dev   ...
     *  @param account_ ...
     */
    function setPendingOwner(address account_) external;

    /**
     *  @dev    ...
     *  @param  vestingPeriod_ ...
     *  @return issuanceRate_  ...
     *  @return freeAssets_    ...
     */
    function updateVestingSchedule(uint256 vestingPeriod_) external returns (uint256 issuanceRate_, uint256 freeAssets_);

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @dev    ...
     *  @return APR_ ...
     */
    function APR() external view returns (uint256 APR_);

    /**
     *  @dev    ...
     *  @param  account_ ...
     *  @return assets_  ...
     */
    function balanceOfAssets(address account_) external view returns (uint256 assets_);

}
