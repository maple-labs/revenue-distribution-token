// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { ERC20 }       from "../lib/erc20/src/ERC20.sol";
import { ERC20Helper } from "../lib/erc20-helper/src/ERC20Helper.sol";

import { IRevenueDistributionToken } from "./interfaces/IRevenueDistributionToken.sol";

contract RevenueDistributionToken is IRevenueDistributionToken, ERC20 {

    uint256 public immutable override precision;  // Precision of rates, equals max deposit amounts before rounding errors occur

    address public override owner;
    address public override pendingOwner;
    address public override underlying;

    uint256 public override freeUnderlying;       // Amount of underlying unlocked regardless of time passed
    uint256 public override issuanceRate;         // underlying/second rate dependent on aggregate vesting schedule (needs increased precision)
    uint256 public override lastUpdated;          // Timestamp of when issuance equation was last updated
    uint256 public override vestingPeriodFinish;  // Timestamp when current vesting schedule ends

    constructor(string memory name_, string memory symbol_, address owner_, address underlying_, uint256 precision_)
        ERC20(name_, symbol_, ERC20(underlying_).decimals())
    {
        owner      = owner_;
        precision  = precision_;
        underlying = underlying_;
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
    function updateVestingSchedule(uint256 vestingPeriod_) external override returns (uint256 issuanceRate_, uint256 freeUnderlying_) {
        require(msg.sender == owner, "RDT:UVS:NOT_OWNER");

        // Update "y-intercept" to reflect current available underlying
        freeUnderlying = freeUnderlying_ = totalHoldings();

        // Calculate slope, update timestamp and period finish
        issuanceRate        = issuanceRate_ = (ERC20(underlying).balanceOf(address(this)) - freeUnderlying_) * precision / vestingPeriod_;
        lastUpdated         = block.timestamp;
        vestingPeriodFinish = block.timestamp + vestingPeriod_;
    }

    /************************/
    /*** Staker Functions ***/
    /************************/

    function deposit(uint256 amount_) external virtual override returns (uint256 shares_) {
        return _deposit(msg.sender, amount_);
    }

    function redeem(uint256 rdTokenAmount_) external virtual override returns (uint256 underlyingAmount_) {
        return _redeem(msg.sender, rdTokenAmount_);
    }

    function withdraw(uint256 underlyingAmount_) external virtual override returns (uint256 shares_) {
        return _withdraw(msg.sender, underlyingAmount_);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _deposit(address account_, uint256 amount_) internal returns (uint256 shares_) {
        require(amount_ != 0, "RDT:D:AMOUNT");
        _mint(account_, shares_ = previewDeposit(amount_));
        freeUnderlying = totalHoldings() + amount_;
        _updateIssuanceParams();
        require(ERC20Helper.transferFrom(address(underlying), account_, address(this), amount_), "RDT:D:TRANSFER_FROM");
        emit Deposit(account_, amount_);
    }

    function _redeem(address account_, uint256 rdTokenAmount_) internal returns (uint256 underlyingAmount_) {
        require(rdTokenAmount_ != 0, "RDT:W:AMOUNT");
        underlyingAmount_ = previewRedeem(rdTokenAmount_);
        _burn(account_, rdTokenAmount_);
        freeUnderlying = totalHoldings() - underlyingAmount_;
        _updateIssuanceParams();
        require(ERC20Helper.transfer(address(underlying), account_, underlyingAmount_), "RDT:D:TRANSFER");
        emit Withdraw(account_, underlyingAmount_);
    }

    function _withdraw(address account_, uint256 underlyingAmount_) internal returns (uint256 shares_) {
        require(underlyingAmount_ != 0, "RDT:W:AMOUNT");
        _burn(account_, shares_ = previewWithdraw(underlyingAmount_));
        freeUnderlying = totalHoldings() - underlyingAmount_;
        _updateIssuanceParams();
        require(ERC20Helper.transfer(address(underlying), account_, underlyingAmount_), "RDT:D:TRANSFER");
        emit Withdraw(account_, underlyingAmount_);
    }

    function _updateIssuanceParams() internal {
        issuanceRate = block.timestamp > vestingPeriodFinish ? 0 : issuanceRate;
        lastUpdated  = block.timestamp;
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function APR() external view override returns (uint256 apr_) {
        return issuanceRate * 365 days * ERC20(underlying).decimals() / totalSupply / precision;
    }

    function balanceOfUnderlying(address account_) external view override returns (uint256 balanceOfUnderlying_) {
        return balanceOf[account_] * exchangeRate() / precision;
    }

    function exchangeRate() public view override returns (uint256 exchangeRate_) {
        uint256 _totalSupply = totalSupply;
        if (_totalSupply == uint256(0)) return precision;
        return totalHoldings() * precision / _totalSupply;
    }

    function previewDeposit(uint256 underlyingAmount_) public view override returns (uint256 shareAmount_) {
        shareAmount_ = underlyingAmount_ * precision / exchangeRate();
    }

    // TODO: Update this function and corresponding test to divide by exchange rate
    function previewWithdraw(uint256 underlyingAmount_) public view override returns (uint256 shareAmount_) {
        shareAmount_ = underlyingAmount_ * precision / exchangeRate();
    }

    function previewRedeem(uint256 shareAmount_) public view override returns (uint256 underlyingAmount_) {
        underlyingAmount_ = shareAmount_ * exchangeRate() / precision;
    }

    function totalHoldings() public view override returns (uint256 totalHoldings_) {
        if (issuanceRate == 0) return freeUnderlying;

        uint256 vestingTimePassed =
            block.timestamp > vestingPeriodFinish ?
                vestingPeriodFinish - lastUpdated :
                block.timestamp - lastUpdated;

        return issuanceRate * vestingTimePassed / precision + freeUnderlying;
    }

}
