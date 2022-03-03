// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { IERC4626 } from "./IERC4626.sol";
import { IERC20Permit } from "../../modules/erc20/contracts/interfaces/IERC20Permit.sol";

/// @title A token that represents ownership of future revenues distributed linearly over time.
interface IRevenueDistributionToken is IERC4626, IERC20Permit {

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     *  @dev The total amount of the underlying asset that is currently unlocked.
     */
    function freeAssets() external view returns (uint256 freeAssets_);

    /**
     *  @dev The estimated rate of the vesting schedule that is currently active.
     *       Denominated as the amount of underlying assets vesting per second.
     */
    function issuanceRate() external view returns (uint256 issuanceRate_);

    /**
     *  @dev The last time the vesting schedule has been updated.
     */
    function lastUpdated() external view returns (uint256 lastUpdated_);

    /**
     *  @dev The address of the account that is allowed to update the vesting schedule.
     */
    function owner() external view returns (address owner_);

    /**
     *  @dev The next owner, nominated by the current owner.
     */
    function pendingOwner() external view returns (address pendingOwner_);

    /**
     *  @dev The precision at which the issuance rate is measured.
     */
    function precision() external view returns (uint256 precision_);

    /**
     *  @dev The end of the current vesting schedule.
     */
    function vestingPeriodFinish() external view returns (uint256 vestingPeriodFinish_);

    /********************************/
    /*** Administrative Functions ***/
    /********************************/

    /**
     *  @dev Sets the pending owner as the new owner.
     *       Can be called only by the pending owner, and only after his nomination by the current owner.
     */
    function acceptOwnership() external;

    /**
     *  @dev   Sets a new address as the pending owner.
     *  @param pendingOwner_ The next potential owner.
     */
    function setPendingOwner(address pendingOwner_) external;

    /**
     *  @dev    Updates the current vesting schedule based on how much time has elapsed since the last update.
     *  @param  vestingPeriod_ The amount of time over which all so far unaccounted underlying assets will be vested over.
     *  @return issuanceRate_  The new issuance rate.
     *  @return freeAssets_    The new amount of underlying assets that are unlocked.
     */
    function updateVestingSchedule(uint256 vestingPeriod_) external returns (uint256 issuanceRate_, uint256 freeAssets_);

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @dev Returns the annualized yearly return of the current vesting schedule.
     */
    function APR() external view returns (uint256 APR_);

    /**
     *  @dev    Returns the amount of underlying assets owned by the specified account.
     *  @param  account_ Address of the account.
     *  @return assets_  Amount of assets owned.
     */
    function balanceOfAssets(address account_) external view returns (uint256 assets_);

}
