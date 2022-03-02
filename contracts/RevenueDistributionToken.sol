// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { ERC20Permit }       from "../modules/erc20/contracts/ERC20Permit.sol";
import { ERC20Helper } from "../modules/erc20-helper/src/ERC20Helper.sol";

import { IRevenueDistributionToken } from "./interfaces/IRevenueDistributionToken.sol";

contract RevenueDistributionToken is IRevenueDistributionToken, ERC20Permit {

    uint256 public immutable override precision;  // Precision of rates, equals max deposit amounts before rounding errors occur

    address public override owner;
    address public override pendingOwner;
    address public override asset;

    uint256 public override freeAssets;           // Amount of assets unlocked regardless of time passed.
    uint256 public override issuanceRate;         // asset/second rate dependent on aggregate vesting schedule (needs increased precision).
    uint256 public override lastUpdated;          // Timestamp of when issuance equation was last updated.
    uint256 public override vestingPeriodFinish;  // Timestamp when current vesting schedule ends.

    constructor(string memory name_, string memory symbol_, address owner_, address asset_, uint256 precision_)
        ERC20Permit(name_, symbol_, ERC20Permit(asset_).decimals())
    {
        owner     = owner_;
        precision = precision_;
        asset     = asset_;
    }

    /********************************/
    /*** Administrative Functions ***/
    /********************************/

    function acceptOwnership() external override {
        require(msg.sender == pendingOwner, "RDT:AO:NOT_PO");
        owner        = msg.sender;
        pendingOwner = address(0);
    }

    function setPendingOwner(address pendingOwner_) external override {
        require(msg.sender == owner, "RDT:SPO:NOT_OWNER");
        pendingOwner = pendingOwner_;
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
    }

    /************************/
    /*** Staker Functions ***/
    /************************/

    function depositWithPermit(uint256 assets_, address receiver_, uint256 deadline_, uint8 v_, bytes32 r_, bytes32 s_) external virtual returns (uint256 shares_) {
        ERC20Permit(asset).permit(msg.sender, address(this), assets_, deadline_, v_, r_, s_);
        shares_ = _deposit(assets_, receiver_, msg.sender);
    }

    function mintWithPermit(uint256 shares_, address receiver_, uint256 deadline_, uint8 v_, bytes32 r_, bytes32 s_) external virtual returns (uint256 assets_) {
        ERC20Permit(asset).permit(msg.sender, address(this), convertToAssets(shares_), deadline_, v_, r_, s_);
        assets_ = _mint(shares_, receiver_, msg.sender);
    }

    function deposit(uint256 assets_, address receiver_) external virtual override returns (uint256 shares_) {
        shares_ = _deposit(assets_, receiver_, msg.sender);
    }

    function mint(uint256 shares_, address receiver_) external virtual override returns (uint256 assets_) {
        assets_ = _mint(shares_, receiver_, msg.sender);
    }

    function redeem(uint256 shares_, address receiver_, address owner_) external virtual override returns (uint256 assets_) {
        assets_ = _redeem(shares_, receiver_, owner_, msg.sender);
    }

    function withdraw(uint256 assets_, address receiver_, address owner_) external virtual override returns (uint256 shares_) {
        shares_ = _withdraw(assets_, receiver_, owner_, msg.sender);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _deposit(uint256 assets_, address receiver_, address caller_) internal returns (uint256 shares_) {
        require(assets_ != 0, "RDT:D:AMOUNT");
        _mint(receiver_, shares_ = previewDeposit(assets_));
        freeAssets = totalAssets() + assets_;
        _updateIssuanceParams();
        require(ERC20Helper.transferFrom(address(asset), caller_, address(this), assets_), "RDT:D:TRANSFER_FROM");
        emit Deposit(caller_, receiver_, assets_, shares_);
    }

    function _mint(uint256 shares_, address receiver_, address caller_) internal returns (uint256 assets_) {
        require(shares_ != 0, "RDT:M:AMOUNT");
        _mint(receiver_, assets_ = previewMint(shares_));
        freeAssets = totalAssets() + assets_;
        _updateIssuanceParams();
        require(ERC20Helper.transferFrom(address(asset), caller_, address(this), assets_), "RDT:M:TRANSFER_FROM");
        emit Deposit(caller_, receiver_, assets_, shares_);
    }

    function _redeem(uint256 shares_, address receiver_, address owner_, address caller_) internal returns (uint256 assets_) {
        require(owner_ == msg.sender, "RDT:R:NOT_OWNER");
        require(shares_ != 0, "RDT:R:AMOUNT");
        assets_ = previewRedeem(shares_);
        _burn(owner_, shares_);
        freeAssets = totalAssets() - assets_;
        _updateIssuanceParams();
        require(ERC20Helper.transfer(address(asset), receiver_, assets_), "RDT:R:TRANSFER");
        emit Withdraw(caller_, receiver_, owner_, assets_, shares_);
    }

    function _withdraw(uint256 assets_, address receiver_, address owner_, address caller_) internal returns (uint256 shares_) {
        require(owner_ == msg.sender, "RDT:W:NOT_OWNER");
        require(assets_ != 0, "RDT:W:AMOUNT");
        _burn(owner_, shares_ = previewWithdraw(assets_));
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
        return issuanceRate * 365 days * ERC20Permit(asset).decimals() / totalSupply / precision;
    }

    function balanceOfAssets(address account_) public view override returns (uint256 balanceOfAssets_) {
        return convertToAssets(balanceOf[account_]);
    }

    function convertToAssets(uint256 shares_) public view override returns (uint256 assets_) {
        assets_ = totalSupply != uint256(0) ? shares_ * totalAssets() / totalSupply : shares_;
    }

    function convertToShares(uint256 assets_) public view override returns (uint256 shares_) {
        shares_ = totalSupply != uint256(0) ? assets_ * totalSupply / totalAssets() : assets_;
    }

    function maxDeposit(address receiver_) external pure virtual override returns (uint256 maxAssets_) {
        maxAssets_ = type(uint256).max;
    }

    function maxMint(address receiver_) external pure virtual override returns (uint256 maxShares_) {
        maxShares_ = type(uint256).max;
    }

    function maxRedeem(address owner_) external view virtual override returns (uint256 maxShares_) {
        maxShares_ = balanceOf[owner_]; 
    }

    function maxWithdraw(address owner_) external view virtual override returns (uint256 maxAssets_) {
        maxAssets_ = balanceOfAssets(owner_);
    }

    function previewDeposit(uint256 assets_) public view virtual override returns (uint256 shares_) {
        shares_ = convertToShares(assets_);
    }

    function previewMint(uint256 shares_) public view virtual override returns (uint256 assets_) {
        assets_ = convertToAssets(shares_);
    }

    function previewRedeem(uint256 shares_) public view virtual override returns (uint256 assets_) {
        assets_ = convertToAssets(shares_);
    }

    function previewWithdraw(uint256 assets_) public view virtual override returns (uint256 shares_) {
        shares_ = convertToShares(assets_);
    }

    function totalAssets() public view override returns (uint256 totalManagedAssets_) {
        if (issuanceRate == 0) return freeAssets;

        uint256 vestingTimePassed =
            block.timestamp > vestingPeriodFinish ?
                vestingPeriodFinish - lastUpdated :
                block.timestamp - lastUpdated;

        return issuanceRate * vestingTimePassed / precision + freeAssets;
    }

}
