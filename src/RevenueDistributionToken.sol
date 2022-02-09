// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { ERC20 }       from "../lib/erc20/src/ERC20.sol";
import { ERC20Helper } from "../lib/erc20-helper/src/ERC20Helper.sol";

import { IRevenueDistributionToken } from "./interfaces/IRevenueDistributionToken.sol";

contract RevenueDistributionToken is IRevenueDistributionToken, ERC20 {

    uint256 internal constant RAY = 1e27;

    address public immutable override underlying;

    address public override owner;
    address public override pendingOwner;

    uint256 public override freeUnderlying;       // Amount of underlying unlocked regardless of time passed
    uint256 public override issuanceRate;         // underlying/second rate dependent on aggregate vesting schedule (needs increased precision)
    uint256 public override lastUpdated;          // Timestamp of when issuance equation was last updated
    uint256 public override vestingPeriodFinish;  // Timestamp when current vesting schedule ends

    constructor(string memory name_, string memory symbol_, address owner_, address underlying_)
        ERC20(name_, symbol_, ERC20(underlying_).decimals())
    {
        owner      = owner_;
        underlying = underlying_;
    }

    /********************************/
    /*** Administrative Functions ***/
    /********************************/

    function acceptOwner() external override {
        require(msg.sender == pendingOwner, "RDT:AO:NOT_PO");
        owner        = msg.sender;
        pendingOwner = address(0);
    }

    function setPendingOwner(address pendingOwner_) external override {
        require(msg.sender == owner, "RDT:SPO:NOT_OWNER");
        pendingOwner = pendingOwner_;
    }

    function updateVestingSchedule(uint256 vestingPeriod_) external override {
        require(msg.sender == owner, "RDT:UVS:NOT_OWNER");

        // Update "y-intercept" to reflect current available underlying
        uint256 _freeUnderlying = freeUnderlying = totalHoldings();

        // Calculate slope, update timestamp and period finish
        issuanceRate        = (ERC20(underlying).balanceOf(address(this)) - _freeUnderlying) * RAY / vestingPeriod_;
        lastUpdated         = block.timestamp;
        vestingPeriodFinish = block.timestamp + vestingPeriod_;
    }

    /************************/
    /*** Staker Functions ***/
    /************************/

    function deposit(uint256 amount_) public virtual override returns (uint256 shares_) {
        require(amount_ != 0, "RDT:D:AMOUNT");
        _mint(msg.sender, shares_ = previewDeposit(amount_));
        freeUnderlying = totalHoldings() + amount_;
        _updateIssuanceParams();
        require(ERC20Helper.transferFrom(address(underlying), msg.sender, address(this), amount_), "RDT:D:TRANSFER_FROM");
        emit Deposit(msg.sender, amount_);
    }

    function redeem(uint256 rdTokenAmount_) public virtual override returns (uint256 underlyingAmount_) {
        require(rdTokenAmount_ != 0, "RDT:W:AMOUNT");
        underlyingAmount_ = previewRedeem(rdTokenAmount_);
        _burn(msg.sender, rdTokenAmount_);
        freeUnderlying = totalHoldings() - underlyingAmount_;
        _updateIssuanceParams();
        require(ERC20Helper.transfer(address(underlying), msg.sender, underlyingAmount_), "RDT:D:TRANSFER");
        emit Withdraw(msg.sender, underlyingAmount_);
    }

    function withdraw(uint256 underlyingAmount_) public virtual override returns (uint256 shares_) {
        require(underlyingAmount_ != 0, "RDT:W:AMOUNT");
        _burn(msg.sender, shares_ = previewWithdraw(underlyingAmount_));
        freeUnderlying = totalHoldings() - underlyingAmount_;
        _updateIssuanceParams();
        require(ERC20Helper.transfer(address(underlying), msg.sender, underlyingAmount_), "RDT:D:TRANSFER");
        emit Withdraw(msg.sender, underlyingAmount_);
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function APR() external view override returns (uint256 apr_) {
        return issuanceRate * 365 days * ERC20(underlying).decimals() / totalSupply / RAY;
    }

    function balanceOfUnderlying(address account_) external view override returns (uint256 balanceOfUnderlying_) {
        return balanceOf[account_] * exchangeRate() / RAY;
    }

    function exchangeRate() public view override returns (uint256 exchangeRate_) {
        uint256 _totalSupply = totalSupply;
        if (_totalSupply == uint256(0)) return RAY;
        return totalHoldings() * RAY / _totalSupply;
    }

    function previewDeposit(uint256 underlyingAmount_) public view override returns (uint256 shareAmount_) {
        shareAmount_ = underlyingAmount_ * RAY / exchangeRate();
    }

    function previewWithdraw(uint256 underlyingAmount_) public view override returns (uint256 shareAmount_) {
        shareAmount_ = underlyingAmount_ * exchangeRate() / RAY;
    }

    function previewRedeem(uint256 shareAmount_) public view override returns (uint256 underlyingAmount_) {
        underlyingAmount_ = shareAmount_ * exchangeRate() / RAY;
    }

    function totalHoldings() public view override returns (uint256 totalHoldings_) {
        if (issuanceRate == 0) return freeUnderlying;

        uint256 vestingTimePassed =
            block.timestamp > vestingPeriodFinish ?
                vestingPeriodFinish - lastUpdated :
                block.timestamp - lastUpdated;
        return unlockedBalance(issuanceRate, vestingTimePassed, freeUnderlying);
    }

    /**********************/
    /*** Pure Functions ***/
    /**********************/

    function unlockedBalance(uint256 vestingTime, uint256 issuanceRate_, uint256 freeUnderlying_)
        public pure returns (uint256 unlockedBalance_)
    {
        return issuanceRate_ * vestingTime / RAY + freeUnderlying_;
    }

    /*********************************/
    /*** Internal Helper Functions ***/
    /*********************************/

    function _updateIssuanceParams() internal {
        issuanceRate = block.timestamp > vestingPeriodFinish ? 0 : issuanceRate;
        lastUpdated  = block.timestamp;
    }
}
