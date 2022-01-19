// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import { ERC20 }       from "lib/erc20/src/ERC20.sol";
import { ERC20Helper } from "lib/erc20-helper/src/ERC20Helper.sol";

contract xMPL is ERC20 {

    address constant public MPL = 0x33349B282065b0284d756F0577FB39c158F935e6;

    uint256 constant WAD = 10 ** 18;

    uint256 public freeToken;            // Amount of MPL unlocked regardless of time passed
    uint256 public issuanceRate;         // MPL/second rate dependent on aggregate vesting schedule
    uint256 public lastUpdated;          // Timestamp of when issuance equation was last updated
    uint256 public vestingPeriodFinish;  // Timestamp when current vesting schedule ends

    constructor() ERC20("MPL Revenue Token", "xMPL", 18) {}

    function depositMPL(uint256 amount_, uint256 vestingPeriod_) external {
        // Update "y-intercept" to reflect all unlocked holdings based on current timestamp
        uint256 _freeToken = freeToken = totalHoldings();

        // Calculate point at the end of the line
        uint256 totalUnlockedAtEndOfPeriod = amount_ + getTotalUnlockedAtEndOfPeriod(block.timestamp, lastUpdated, vestingPeriod_, issuanceRate, _freeToken);

        // Calculate x value of end of the line
        if ((block.timestamp + vestingPeriod_) > vestingPeriodFinish) {
            vestingPeriodFinish = block.timestamp + vestingPeriod_;
        }

        // Calculate slope
        issuanceRate = (totalUnlockedAtEndOfPeriod - _freeToken) / (vestingPeriodFinish - block.timestamp);

        require(ERC20Helper.transferFrom(MPL, msg.sender, address(this), amount_), "xMPL:DM:TRANSFER_FROM");
    }

    function deposit(uint256 amount_) external {
        require(amount_ != 0, "xMPL:D:AMOUNT");
        _mint(msg.sender, amount_ * WAD / exchangeRate());
        require(ERC20Helper.transferFrom(MPL, msg.sender, address(this), amount_), "xMPL:D:TRANSFER_FROM");
    }

    function withdraw(uint256 mplAmount_) external {
        require(mplAmount_ != 0, "xMPL:W:AMOUNT");
        _burn(msg.sender, mplAmount_ * exchangeRate() / WAD);
        require(ERC20Helper.transfer(MPL, msg.sender, mplAmount_), "xMPL:D:TRANSFER");
    }

    function redeem(uint256 xMplAmount_) external {
        require(xMplAmount_ != 0, "xMPL:W:AMOUNT");
        _burn(msg.sender, xMplAmount_);
        require(ERC20Helper.transfer(MPL, msg.sender, xMplAmount_ * exchangeRate() / WAD), "xMPL:D:TRANSFER");
    }

    function balanceOfUnderlying(address account_) external view returns (uint256 balanceOfUnderlying_) {
        return balanceOf[account_] * exchangeRate() / WAD;
    }

    function exchangeRate() public view returns (uint256 exchangeRate_) {
        uint256 _totalSupply = totalSupply;
        if (_totalSupply == uint256(0)) return WAD;
        return totalHoldings() * WAD / _totalSupply;
    }

    function totalHoldings() public view returns (uint256 totalHoldings_) {
        return unlockedBalance(block.timestamp, lastUpdated, vestingPeriodFinish, issuanceRate, freeToken);
    }

    function unlockedBalance(
        uint256 currentTimestamp_,
        uint256 lastUpdated_,
        uint256 vestingPeriodFinish_,
        uint256 issuanceRate_,
        uint256 freeToken_
    )
        public pure returns (uint256 unlockedBalance_)
    {
        uint256 dTime = currentTimestamp_ > lastUpdated_ ? 0 : vestingPeriodFinish_ - lastUpdated_;
        return issuanceRate_ * dTime + freeToken_;
    }

    function getTotalUnlockedAtEndOfPeriod(
        uint256 currentTimestamp_,
        uint256 lastUpdated_,
        uint256 vestingPeriodFinish_,
        uint256 issuanceRate_,
        uint256 freeToken_
    )
        public pure returns (uint256 totalUnlocked_)
    {
        uint256 vestingTimeRemaining = currentTimestamp_ > vestingPeriodFinish_ ? 0 : vestingPeriodFinish_ - currentTimestamp_;
        return freeToken_ + vestingTimeRemaining * issuanceRate_;
    }
}
