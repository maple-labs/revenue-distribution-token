// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { ERC20Permit } from "../modules/erc20/contracts/ERC20Permit.sol";
import { ERC20Helper } from "../modules/erc20-helper/src/ERC20Helper.sol";

import { IRevenueDistributionToken } from "./interfaces/IRevenueDistributionToken.sol";

contract RevenueDistributionToken is IRevenueDistributionToken, ERC20Permit {

    uint256 public immutable override precision;  // Precision of rates, equals max deposit amounts before rounding errors occur

    address public override asset;

    address public override owner;
    address public override pendingOwner;

    uint256 public override freeAssets;           // Amount of assets unlocked regardless of time passed.
    uint256 public override issuanceRate;         // asset/second rate dependent on aggregate vesting schedule (needs increased precision).
    uint256 public override lastUpdated;          // Timestamp of when issuance equation was last updated.
    uint256 public override vestingPeriodFinish;  // Timestamp when current vesting schedule ends.

    uint256 private locked = 1;                   // Used in reentrancy check.

    /*****************/
    /*** Modifiers ***/
    /*****************/

    modifier nonReentrant() {
        require(locked == 1, "RDT:LOCKED");

        locked = 2;

        _;

        locked = 1;
    }

    constructor(string memory name_, string memory symbol_, address owner_, address asset_, uint256 precision_)
        ERC20Permit(name_, symbol_, ERC20Permit(asset_).decimals())
    {
        require((owner = owner_) != address(0), "RDT:C:OWNER_ZERO_ADDRESS");
        asset = asset_;  // Don't need to check zero address as ERC20Permit(asset_).decimals() will fail in ERC20Permit constructor.

        precision = precision_;
    }

    /********************************/
    /*** Administrative Functions ***/
    /********************************/

    function acceptOwnership() external override {
        require(msg.sender == pendingOwner, "RDT:AO:NOT_PO");
        emit OwnershipAccepted(owner, msg.sender);
        owner        = msg.sender;
        pendingOwner = address(0);
    }

    function setPendingOwner(address pendingOwner_) external override {
        require(msg.sender == owner, "RDT:SPO:NOT_OWNER");
        pendingOwner = pendingOwner_;
        emit PendingOwnerSet(msg.sender, pendingOwner_);
    }

    // TODO: Revisit returns
    function updateVestingSchedule(uint256 vestingPeriod_) external override returns (uint256 issuanceRate_, uint256 freeAssets_) {
        require(msg.sender == owner, "RDT:UVS:NOT_OWNER");

        // Update "y-intercept" to reflect current available asset.
        freeAssets = freeAssets_ = totalAssets();

        // Calculate slope, update timestamp and period finish.
        issuanceRate        = issuanceRate_ = (ERC20Permit(asset).balanceOf(address(this)) - freeAssets_) * precision / vestingPeriod_;
        lastUpdated         = block.timestamp;
        vestingPeriodFinish = block.timestamp + vestingPeriod_;

        emit VestingScheduleUpdated(msg.sender, vestingPeriodFinish, issuanceRate);
    }

    /************************/
    /*** Staker Functions ***/
    /************************/

    function deposit(uint256 assets_, address receiver_) external virtual override nonReentrant returns (uint256 shares_) {
        shares_ = _deposit(assets_, receiver_, msg.sender);
    }

    function depositWithPermit(
        uint256 assets_,
        address receiver_,
        uint256 deadline_,
        uint8   v_,
        bytes32 r_,
        bytes32 s_
    )
        external virtual override nonReentrant returns (uint256 shares_)
    {
        ERC20Permit(asset).permit(msg.sender, address(this), assets_, deadline_, v_, r_, s_);
        shares_ = _deposit(assets_, receiver_, msg.sender);
    }

    function mint(uint256 shares_, address receiver_) external virtual override nonReentrant returns (uint256 assets_) {
        assets_ = _mint(shares_, receiver_, msg.sender);
    }

    function mintWithPermit(
        uint256 shares_,
        address receiver_,
        uint256 deadline_,
        uint8   v_,
        bytes32 r_,
        bytes32 s_
    )
        external virtual override nonReentrant returns (uint256 assets_)
    {
        ERC20Permit(asset).permit(msg.sender, address(this), convertToAssets(shares_), deadline_, v_, r_, s_);
        assets_ = _mint(shares_, receiver_, msg.sender);
    }

    function redeem(uint256 shares_, address receiver_, address owner_) external virtual override nonReentrant returns (uint256 assets_) {
        assets_ = _redeem(shares_, receiver_, owner_, msg.sender);
    }

    function withdraw(uint256 assets_, address receiver_, address owner_) external virtual override nonReentrant returns (uint256 shares_) {
        shares_ = _withdraw(assets_, receiver_, owner_, msg.sender);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _deposit(uint256 assets_, address receiver_, address caller_) internal returns (uint256 shares_) {
        require(assets_ != 0,                              "RDT:D:ZERO_ASSETS");
        require((shares_ = convertToShares(assets_)) != 0, "RDT:D:ZERO_SHARES");
        _mint(receiver_, shares_);
        freeAssets = totalAssets() + assets_;
        _updateIssuanceParams();
        require(ERC20Helper.transferFrom(address(asset), caller_, address(this), assets_), "RDT:D:TRANSFER_FROM");
        emit Deposit(caller_, receiver_, assets_, shares_);
    }

    function _mint(uint256 shares_, address receiver_, address caller_) internal returns (uint256 assets_) {
        require(shares_ != 0, "RDT:M:ZERO_SHARES");
        assets_ = previewMint(shares_);
        _mint(receiver_, shares_);
        freeAssets = totalAssets() + assets_;
        _updateIssuanceParams();
        require(ERC20Helper.transferFrom(address(asset), caller_, address(this), assets_), "RDT:M:TRANSFER_FROM");
        emit Deposit(caller_, receiver_, assets_, shares_);
    }

    function _redeem(uint256 shares_, address receiver_, address owner_, address caller_) internal returns (uint256 assets_) {
        require(shares_ != 0, "RDT:R:ZERO_SHARES");
        if (caller_ != owner_) {
            _reduceCallerAllowance(caller_, owner_, shares_);
        }
        assets_ = convertToAssets(shares_);
        _burn(owner_, shares_);
        freeAssets = totalAssets() - assets_;
        _updateIssuanceParams();
        require(ERC20Helper.transfer(address(asset), receiver_, assets_), "RDT:R:TRANSFER");
        emit Withdraw(caller_, receiver_, owner_, assets_, shares_);
    }

    function _withdraw(uint256 assets_, address receiver_, address owner_, address caller_) internal returns (uint256 shares_) {
        require(assets_ != 0,                              "RDT:W:ZERO_ASSETS");
        require((shares_ = previewWithdraw(assets_)) != 0, "RDT:W:ZERO_SHARES");
        if (caller_ != owner_) {
            _reduceCallerAllowance(caller_, owner_, shares_);
        }
        _burn(owner_, shares_);
        freeAssets = totalAssets() - assets_;
        _updateIssuanceParams();
        require(ERC20Helper.transfer(address(asset), receiver_, assets_), "RDT:W:TRANSFER");
        emit Withdraw(caller_, receiver_, owner_, assets_, shares_);
    }

    function _updateIssuanceParams() internal {
        issuanceRate = block.timestamp > vestingPeriodFinish ? 0 : issuanceRate;  // TODO: >=?
        lastUpdated  = block.timestamp;
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function APR() external view override returns (uint256 apr_) {
        return issuanceRate * 365 days * 1e6 / totalSupply / precision;
    }

    function balanceOfAssets(address account_) public view override returns (uint256 balanceOfAssets_) {
        return convertToAssets(balanceOf[account_]);
    }

    function convertToAssets(uint256 shares_) public view override returns (uint256 assets_) {
        uint256 supply = totalSupply;  // Cache to memory.

        assets_ = supply == 0 ? shares_ : shares_ * totalAssets() / supply;
    }

    function convertToShares(uint256 assets_) public view override returns (uint256 shares_) {
        uint256 supply = totalSupply;  // Cache to memory.

        shares_ = supply == 0 ? assets_ : assets_ * supply / totalAssets();
    }

    function maxDeposit(address receiver_) external pure virtual override returns (uint256 maxAssets_) {
        receiver_;  // Silence warning
        maxAssets_ = type(uint256).max;
    }

    function maxMint(address receiver_) external pure virtual override returns (uint256 maxShares_) {
        receiver_;  // Silence warning
        maxShares_ = type(uint256).max;
    }

    function maxRedeem(address owner_) external view virtual override returns (uint256 maxShares_) {
        maxShares_ = balanceOf[owner_];
    }

    function maxWithdraw(address owner_) external view virtual override returns (uint256 maxAssets_) {
        maxAssets_ = balanceOfAssets(owner_);
    }

    function previewDeposit(uint256 assets_) external view virtual override returns (uint256 shares_) {
        shares_ = convertToShares(assets_);
    }

    function previewMint(uint256 shares_) public view virtual override returns (uint256 assets_) {
        uint256 supply = totalSupply;  // Cache to memory.

        // Round up to favor the vault as recommended in EIP-4626: https://eips.ethereum.org/EIPS/eip-4626#security-considerations
        assets_ = supply == 0 ? shares_ : _mulDivRoundUp(shares_, totalAssets(), supply);
    }

    function previewRedeem(uint256 shares_) external view virtual override returns (uint256 assets_) {
        assets_ = convertToAssets(shares_);
    }

    function previewWithdraw(uint256 assets_) public view virtual override returns (uint256 shares_) {
        uint256 supply = totalSupply;  // Cache to memory.

        // Round up to favor the vault as recommended in EIP-4626: https://eips.ethereum.org/EIPS/eip-4626#security-considerations
        shares_ = supply == 0 ? assets_ : _mulDivRoundUp(assets_, supply, totalAssets());
    }

    function totalAssets() public view override returns (uint256 totalManagedAssets_) {
        if (issuanceRate == 0) return freeAssets;

        uint256 vestingTimePassed =
            block.timestamp > vestingPeriodFinish ?
                vestingPeriodFinish - lastUpdated :
                block.timestamp - lastUpdated;

        return issuanceRate * vestingTimePassed / precision + freeAssets;
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _reduceCallerAllowance(address caller_, address owner_, uint256 shares_) internal {
        uint256 callerAllowance = allowance[owner_][caller_];  // Cache to memory.

        // TODO: investigate whether leave this `require()` in for clarity from error message, or let the safe math check in `callerAllowance - shares_` handle the underflow.
        require(callerAllowance >= shares_, "RDT:CALLER_ALLOWANCE");

        if (callerAllowance != type(uint256).max) {
            allowance[owner_][caller_] = callerAllowance - shares_;
        }
    }

    function _mulDivRoundUp(uint256 multiplicand_, uint256 multiplier_, uint256 divisor_) internal pure returns (uint256 result_) {
        result_ = (((multiplicand_ * multiplier_) - 1) / divisor_) + 1;
    }

}
