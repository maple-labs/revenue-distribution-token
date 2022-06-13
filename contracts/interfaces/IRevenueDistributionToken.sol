// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import {IERC20} from "../../modules/erc20/contracts/interfaces/IERC20.sol";

import {IERC4626} from "./IERC4626.sol";

/// @title A token that represents ownership of future revenues distributed linearly over time.
interface IRevenueDistributionToken is IERC20, IERC4626 {
    /**************/
    /**
     ** Events **
     */
    /**************/

    /**
     *  @dev   Issuance parameters have been updated after a `_mint` or `_burn`.
     *  @param freeAssets_   Resulting `freeAssets` (y-intercept) value after accounting update.
     *  @param issuanceRate_ The new issuance rate of `asset` until `vestingPeriodFinish_`.
     */
    event IssuanceParamsUpdated(uint256 freeAssets_, uint256 issuanceRate_);

    /**
     *  @dev   `newOwner_` has accepted the transferral of RDT ownership from `previousOwner_`.
     *  @param previousOwner_ The previous RDT owner.
     *  @param newOwner_      The new RDT owner.
     */
    event OwnershipAccepted(
        address indexed previousOwner_,
        address indexed newOwner_
    );

    /**
     *  @dev   `owner_` has set the new pending owner of RDT to `pendingOwner_`.
     *  @param owner_        The current RDT owner.
     *  @param pendingOwner_ The new pending RDT owner.
     */
    event PendingOwnerSet(address indexed owner_, address indexed pendingOwner_);

    /**
     *  @dev   `owner_` has updated the RDT vesting schedule to end at `vestingPeriodFinish_`.
     *  @param owner_               The current RDT owner.
     *  @param vestingPeriodFinish_ When the unvested balance will finish vesting.
     */
    event VestingScheduleUpdated(
        address indexed owner_,
        uint256 vestingPeriodFinish_
    );

    /***********************/
    /**
     ** State Variables **
     */
    /***********************/

    /**
     *  @dev The total amount of the underlying asset that is currently unlocked and is not time-dependent.
     *       Analogous to the y-intercept in a linear function.
     */
    function freeAssets() external view returns (uint256 freeAssets_);

    /**
     *  @dev The rate of issuance of the vesting schedule that is currently active.
     *       Denominated as the amount of underlying assets vesting per second.
     */
    function issuanceRate() external view returns (uint256 issuanceRate_);

    /**
     *  @dev The timestamp of when the linear function was last recalculated.
     *       Analogous to t0 in a linear function.
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
    function vestingPeriodFinish()
        external
        view
        returns (uint256 vestingPeriodFinish_);

    /********************************/
    /**
     ** Administrative Functions **
     */
    /********************************/

    /**
     *  @dev Sets the pending owner as the new owner.
     *       Can be called only by the pending owner, and only after their nomination by the current owner.
     */
    function acceptOwnership() external;

    /**
     *  @dev   Sets a new address as the pending owner.
     *  @param pendingOwner_ The address of the next potential owner.
     */
    function setPendingOwner(address pendingOwner_) external;

    /**
     *  @dev    Updates the current vesting formula based on the amount of total unvested funds in the contract and the new `vestingPeriod_`.
     *  @param  vestingPeriod_ The amount of time over which all currently unaccounted underlying assets will be vested over.
     *  @return issuanceRate_  The new issuance rate.
     *  @return freeAssets_    The new amount of underlying assets that are unlocked.
     */
    function updateVestingSchedule(uint256 vestingPeriod_)
        external
        returns (uint256 issuanceRate_, uint256 freeAssets_);

    /************************/
    /**
     ** Staker Functions **
     */
    /************************/

    /**
     *  @dev    Does a ERC4626 `deposit` with a ERC-2612 `permit`.
     *  @param  assets_   The amount of `asset` to deposit.
     *  @param  receiver_ The receiver of the shares.
     *  @param  deadline_ The timestamp after which the `permit` signature is no longer valid.
     *  @param  v_        ECDSA signature v component.
     *  @param  r_        ECDSA signature r component.
     *  @param  s_        ECDSA signature s component.
     *  @return shares_   The amount of shares minted.
     */
    function depositWithPermit(
        uint256 assets_,
        address receiver_,
        uint256 deadline_,
        uint8 v_,
        bytes32 r_,
        bytes32 s_
    )
        external
        returns (uint256 shares_);

    /**
     *  @dev    Does a ERC4626 `mint` with a ERC-2612 `permit`.
     *  @param  shares_    The amount of `shares` to mint.
     *  @param  receiver_  The receiver of the shares.
     *  @param  maxAssets_ The maximum amount of assets that can be taken, as per the permit.
     *  @param  deadline_  The timestamp after which the `permit` signature is no longer valid.
     *  @param  v_         ECDSA signature v component.
     *  @param  r_         ECDSA signature r component.
     *  @param  s_         ECDSA signature s component.
     *  @return assets_    The amount of shares deposited.
     */
    function mintWithPermit(
        uint256 shares_,
        address receiver_,
        uint256 maxAssets_,
        uint256 deadline_,
        uint8 v_,
        bytes32 r_,
        bytes32 s_
    )
        external
        returns (uint256 assets_);

    /**********************/
    /**
     ** View Functions **
     */
    /**********************/

    /**
     *  @dev    Returns the amount of underlying assets owned by the specified account.
     *  @param  account_ Address of the account.
     *  @return assets_  Amount of assets owned.
     */
    function balanceOfAssets(address account_)
        external
        view
        returns (uint256 assets_);
}