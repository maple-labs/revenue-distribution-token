// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import { ERC20 }       from "../lib/erc20/src/ERC20.sol";
import { ERC20Helper } from "../lib/erc20-helper/src/ERC20Helper.sol";

import { IRevenueDistributionToken } from "./interfaces/IRevenueDistributionToken.sol";

contract RevenueDistributionToken is IRevenueDistributionToken, ERC20 {

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;

    address public immutable override underlying;

    uint256 public freeUnderlying;       // Amount of underlying unlocked regardless of time passed
    uint256 public issuanceRate;         // underlying/second rate dependent on aggregate vesting schedule (needs increased precision)
    uint256 public lastUpdated;          // Timestamp of when issuance equation was last updated
    uint256 public vestingPeriodFinish;  // Timestamp when current vesting schedule ends

    constructor(string memory name, string memory symbol, address earningsToken) ERC20(name, symbol, 18) {
        underlying = earningsToken;
    }

    /********************************/
    /*** Administrative Functions ***/
    /********************************/

    // TODO: Investigate implications of making this open vs permissioned.
    //       Currently a malicious user can deposit a small amount over a large vestingPeriod
    //       and essentially set the `issuanceRate` to zero.
    function depositVestingEarnings(uint256 vestingAmount_, uint256 vestingPeriod_) external {
        // Update "y-intercept" to reflect current available underlying
        uint256 _freeUnderlying = freeUnderlying = totalHoldings();

        uint256 _vestingPeriodFinish = vestingPeriodFinish;  // Cache to memory

        // Calculate y value at the end of the line
        uint256 vestingTimeRemaining       = block.timestamp > _vestingPeriodFinish ? 0 : _vestingPeriodFinish - block.timestamp;
        uint256 totalUnlockedAtEndOfPeriod = vestingAmount_ + unlockedBalance(vestingTimeRemaining, issuanceRate, _freeUnderlying);

        // Calculate x value of end of the line, else use existing `vestingPeriodFinish`
        if ((block.timestamp + vestingPeriod_) > _vestingPeriodFinish) {
            vestingPeriodFinish = block.timestamp + vestingPeriod_;  // TODO: Gas-optimize storage use of `vestingPeriodFinish`
        }

        // Calculate slope and update timestamp
        issuanceRate = (totalUnlockedAtEndOfPeriod - _freeUnderlying) * RAY / (vestingPeriodFinish - block.timestamp);
        lastUpdated  = block.timestamp;

        require(ERC20Helper.transferFrom(address(underlying), msg.sender, address(this), vestingAmount_), "RDT:DVE:TRANSFER_FROM");
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
