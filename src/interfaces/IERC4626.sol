// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { IERC20 } from "../../lib/erc20/src/interfaces/IERC20.sol";

interface IERC4626 is IERC20 {

    /**************/
    /*** Events ***/
    /**************/

    /**
      @notice `caller_` has exchanged `assets_ for `shares_`, and transferred those `shares_` to `owner_`.
              MUST be emitted when tokens are deposited into the Vault via the `mint` and `deposit` methods.
      @param  caller_   The caller of the function that emitted the `Deposit` event`
      @param  owner_    The owner of the shares minted.
      @param  assets_   The amount of assets deposited.
      @param  shares_   The amount of shares minted.
    */
    event Deposit(address indexed caller_, address indexed owner_, uint256 assets_, uint256 shares_);

    /**
      @notice `caller_` has exchanged `shares_`, owned by `owner_`, for `assets_`, and transferred those `assets_` to `receiver_`.
              MUST be emitted when shares are withdrawn from the Vault in `ERC4626.redeem` or `ERC4626.withdraw` methods.
      @param  caller_   The caller of the function that emitted the `Withdraw` event`
      @param  receiver_ The receiver of the `assets_`.
      @param  owner_    The owner of the shares.
      @param  assets_   The amount of assets withdrawn.
      @param  shares_   The amount of shares burned.
    */
    event Withdraw(address indexed caller_, address indexed receiver_, address indexed owner_, uint256 assets_, uint256 shares_);

    /*************************/
    /*** Mutable Functions ***/
    /*************************/

    /**
      @notice Mints `shares_` Vault shares to `receiver_` by depositing exactly `assets_` of underlying tokens.
              MUST emit the `Deposit` event.
              MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the `deposit` execution, and are accounted for during `deposit`.
              MUST revert if all of `assets_` cannot be deposited (due to deposit limit being reached, slippage, the user not approving enough underlying tokens to the Vault contract, etc).
              Note that most implementations will require pre-approval of the Vault with the Vault’s underlying `asset` token.
      @param  assets_   The amount of assets to deposit.
      @param  receiver_ The address to receive shares corresponding to the deposit.
      @return shares_   The shares in the vault credited to `receiver_`.
    */
    function deposit(uint256 assets_, address receiver_) external returns (uint256 shares_);

    /**
      @notice Mints exactly `shares_` Vault shares to `receiver_` by depositing `assets_` of underlying tokens.
              MUST emit the `Deposit` event.
              MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the `mint` execution, and are accounted for during `mint`.
              MUST revert if all of `shares_` cannot be minted (due to deposit limit being reached, slippage, the user not approving enough underlying tokens to the Vault contract, etc).
              Note that most implementations will require pre-approval of the Vault with the Vault’s underlying `asset` token.
      @param  shares_   The amount of vault shares to mint.
      @param  receiver_ The address to receive shares corresponding to the mint.
      @return assets_   The amount of the assets deposited from the mint call.
    */
    function mint(uint256 shares_, address receiver_) external returns (uint256 assets_);

    /**
      @notice Burns exactly `shares_` from `owner_` and sends `assets_` of underlying tokens to `receiver_`.
              MUST emit the Withdraw event.
              MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the `redeem` execution, and are accounted for during `redeem`.
              MUST revert if all of `shares_` cannot be redeemed (due to withdrawal limit being reached, slippage, the owner not having enough shares, etc).
              Note that some implementations will require pre-requesting to the Vault before a withdrawal may be performed. Those methods should be performed separately.
      @param  shares_   The amount of shares to redeem.
      @param  receiver_ The address to receive the amount of assets corresponding to the redemption.
      @param  owner_    The address to burn shares from corresponding to the redemption.
      @return assets_   The asset amount transferred to `receiver_`.
    */
    function redeem(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_);

    /**
      @notice Burns `shares_` from `owner_` and sends exactly `assets_` of underlying tokens to `receiver_`.
              MUST emit the `Withdraw` event.
              MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the `withdraw` execution, and are accounted for during `withdraw`.
              MUST revert if all of `assets_` cannot be withdrawn (due to withdrawal limit being reached, slippage, the owner not having enough shares, etc).
              Note that some implementations will require pre-requesting to the Vault before a withdrawal may be performed. 
              Those methods should be performed separately.
      @param  assets_   The amount of assets to withdraw.
      @param  receiver_ The address to receive the amount of assets corresponding to the withdrawal.
      @param  owner_    The address to burn shares from corresponding to the withdrawal.
      @return shares_   The amount of shares burned from `owner_`.
    */
    function withdraw(uint256 assets_, address receiver_, address owner_) external returns (uint256 shares_);

    /**********************/
    /*** View Functions ***/
    /**********************/

    /** 
      @notice The address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
              MUST be an ERC-20 token contract.
              MUST NOT revert.
      @return assetTokenAddress_ The asset address.
    */
    function asset() external view returns (address assetTokenAddress_);

    /** 
      @notice The amount of assets that the Vault would exchange for the amount of shares provided, in an ideal scenario where all the conditions are met.
              MUST NOT be inclusive of any fees that are charged against assets in the Vault.
              MUST NOT show any variations depending on the caller.
              MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
              MUST NOT revert.
              This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the “average-user’s” price-per-share,
              meaning what the average user should expect to see when exchanging to and from.
      @param  shares_ The amount of shares looking to convert.
      @return assets_ The amount of assets that the Vault would exchange for the amount of shares provided.
    */
    function convertToAssets(uint256 shares_) external view returns (uint256 assets_);

    /** 
      @notice The amount of shares that the Vault would exchange for the amount of assets provided, in an ideal scenario where all the conditions are met.
              MUST NOT be inclusive of any fees that are charged against assets in the Vault.
              MUST NOT show any variations depending on the caller.
              MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
              MUST NOT revert.
              This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the “average-user’s” price-per-share,
              meaning what the average user should expect to see when exchanging to and from.
      @param  assets_ The amount of assets looking to convert.
      @return shares_ The amount of shares that the Vault would exchange for the amount of assets provided.
    */
    function convertToShares(uint256 assets_) external view returns (uint256 shares_);

    /**
      @notice Maximum amount of the underlying asset that can be deposited into the Vault for the `receiver_`, through a `deposit` call.
              MUST return a limited value if `receiver_` is subject to some deposit limit.
              MUST return `2 ** 256 - 1` if there is no limit on the maximum amount of assets that may be deposited.
              MUST NOT revert.
      @param  receiver_  The deposit recipient.
      @return maxAssets_ The max input amount of assets for deposit for a user.
    */
    function maxDeposit(address receiver_) external view returns (uint256 maxAssets_);

    /**
      @notice Maximum amount of the Vault shares that can be minted for the `receiver_`, through a `mint` call.
              MUST return a limited value if `receiver` is subject to some mint limit.
              MUST return `2 ** 256 - 1` if there is no limit on the maximum amount of shares that may be minted.
              MUST NOT revert.
      @param  receiver_  The mint recipient.
      @return maxShares_ The max shares that can be minted for the `receiver_`.
    */
    function maxMint(address receiver_) external view returns (uint256 maxShares_);

    /**
      @notice Maximum amount of Vault shares that can be redeemed from the `owner_` balance in the Vault, through a `redeem` call.
              MUST return a limited value if `owner_` is subject to some withdrawal limit or timelock.
              MUST return `balanceOf(owner_)` if `owner_` is not subject to any withdrawal limit or timelock.
              MUST NOT revert.
      @param  owner_     The owner of the vault shares.
      @return maxShares_ The max shares out in a redeem for a user
    */
    function maxRedeem(address owner_) external view returns (uint256 maxShares_);

    /**
      @notice Maximum amount of the underlying asset that can be withdrawn from the `owner` balance in the Vault, through a `withdraw` call.
              MUST return a limited value if `owner` is subject to some withdrawal limit or timelock.
              MUST NOT revert.
      @param  owner_     The owner of assets to withdraw.
      @return maxAssets_ The max amount of assets `owner_` can withdraw.
    */
    function maxWithdraw(address owner_) external view returns (uint256 maxAssets_);

    /**
      @notice Allows an on-chain or off-chain user to simulate the effects of their deposit at the current block, given current on-chain conditions.
              MUST return as close to and no more than the exact amount of Vault shares that would be minted in a `deposit` call in the same transaction.
              I.e. `deposit` should return the same or more `shares_` as `previewDeposit` if called in the same transaction.
              MUST NOT account for deposit limits like those returned from maxDeposit and should always act as
              though the deposit would be accepted, regardless if the user has enough tokens approved, etc.
              MUST be inclusive of deposit fees. Integrators should be aware of the existence of deposit fees.
              MUST NOT revert.
              Note that any unfavorable discrepancy between `convertToShares` and `previewDeposit` SHOULD be considered
              slippage in share price or some other type of condition,meaning the depositor will lose assets by depositing.
      @param  assets_ The input amount of assets.
      @return shares_ the corresponding amount of shares out from a deposit call with `assets_` in
    */
    function previewDeposit(uint256 assets_) external view returns (uint256 shares_);

    /**
      @notice Allows an on-chain or off-chain user to simulate the effects of their mint at the current block, given current on-chain conditions.
              MUST return as close to and no fewer than the exact amount of assets that would be deposited in a `mint` call in the same transaction.
              I.e. `mint` should return the same or fewer `assets_` as `previewMint` if called in the same transaction.
              MUST NOT account for mint limits like those returned from maxMint and should always act as though the mint would be accepted,
              regardless if the user has enough tokens approved, etc.
              MUST be inclusive of deposit fees. Integrators should be aware of the existence of deposit fees.
              MUST NOT revert.
              Note that any unfavorable discrepancy between `convertToAssets` and `previewMint` SHOULD be considered slippage
              in share price or some other type of condition, meaning the depositor will lose assets by minting.
      @param  shares_ The amount of shares to be minted.
      @return assets_ The amount of assets corresponding to the mint call.
    */
    function previewMint(uint256 shares_) external view returns (uint256 assets_);

    /**
      @notice Allows an on-chain or off-chain user to simulate the effects of their redeemption at the current block, given current on-chain conditions.
              MUST return as close to and no more than the exact amount of assets that would be withdrawn in a `redeem` call in the same transaction.
              I.e. `redeem` should return the same or more `assets_` as `previewRedeem` if called in the same transaction.
              MUST NOT account for redemption limits like those returned from maxRedeem and should always act as though the redemption would be accepted,
              regardless if the user has enough shares, etc.
              MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.
              MUST NOT revert.
              Note that any unfavorable discrepancy between `convertToAssets` and `previewRedeem` SHOULD be considered slippage
              in share price or some other type of condition, meaning the depositor will lose assets by redeeming.
      @param  shares_ The amount of shares to redeem.
      @return assets_ The amount of assets corresponding to the redeem call
     */
    function previewRedeem(uint256 shares_) external view returns (uint256 assets_);

    /**
      @notice Allows an on-chain or off-chain user to simulate the effects of their withdrawal at the current block, given current on-chain conditions.
              MUST return as close to and no fewer than the exact amount of Vault shares that would be burned in a `withdraw` call in the same transaction.
              I.e. `withdraw` should return the same or fewer `shares_` as `previewWithdraw` if called in the same transaction.
              MUST NOT account for withdrawal limits like those returned from maxWithdraw and should always act as though the withdrawal would be accepted,
              regardless if the user has enough shares, etc.
              MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.
              MUST NOT revert.
              Note that any unfavorable discrepancy between `convertToShares` and `previewWithdraw` SHOULD be considered slippage 
              in share price or some other type of condition, meaning the depositor will lose assets by depositing.
      @param  assets_ The input amount of `asset` to withdraw.
      @return shares_ The corresponding amount of shares out from a withdraw call with `assets_` in.
    */
    function previewWithdraw(uint256 assets_) external view returns (uint256 shares_);

    /** 
      @notice Total amount of the underlying asset that is “managed” by Vault.
              SHOULD include any compounding that occurs from yield.
              MUST be inclusive of any fees that are charged against assets in the Vault.
              MUST NOT revert.
      @return totalManagedAssets_ The total amount of assets the Vault manages.
    */
    function totalAssets() external view returns (uint256 totalManagedAssets_);

}
