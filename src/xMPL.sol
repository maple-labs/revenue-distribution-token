// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import { ERC20 }       from "lib/erc20/src/ERC20.sol";
import { ERC20Helper } from "lib/erc20-helper/src/ERC20Helper.sol";

contract xMPL is ERC20 {

    address constant public MPL = 0x33349B282065b0284d756F0577FB39c158F935e6;

    uint256 constant WAD = 10 ** 18;

    function depositMPL(uint256 amount_) external {
        uint256 _freeToken     = freeToken = unlockedBalance();
        uint256 _vestingPeriod = vestingPeriod;

        uint256 totalUnlockedAtEndOfPeriod = amount + getTotalUnlockedAtEndOfPeriod(lastUpdated, _vestingPeriod, issuanceRate, _freeToken);

        issuanceRate = (totalUnlockedAtEndOfPeriod - _freeToken) / _vestingPeriod;

        lastUpdated = block.timestamp;

        require(ERC20Helper.transferFrom(MPL, msg.sender, address(this), amount_), "xMPL:DM:TRANSFER_FROM");
    }

    function deposit(uint256 amount_) external {
        require(amount_ != 0, "xMPL:D:AMOUNT");
        _mint(msg.sender, amount_ * WAD / exchangeRate());
        require(ERC20Helper.transferFrom(msg.sender, address(this), amount_), "xMPL:D:TRANSFER_FROM");
    }

    function withdraw(uint256 mplAmount_) external {
        require(mplAmount_ != 0, "xMPL:W:AMOUNT");
        _burn(msg.sender, mplAmount_ * exchangeRate() / WAD);
        require(ERC20Helper.transfer(msg.sender, mplAmount_), "xMPL:D:TRANSFER");
    }

    function redeem(uint256 xMplAmount_) external {
        require(xMplAmount_ != 0, "xMPL:W:AMOUNT");
        _burn(msg.sender, xMplAmount_);
        require(ERC20Helper.transfer(msg.sender, xMplAmount_ * exchangeRate() / WAD), "xMPL:D:TRANSFER");
    }

    function balanceOfUnderlying(address account_) external view returns (uint256 balanceOfUnderlying_) {
        return balanceOf[account_] * exchangeRate() / WAD;
    }

    function exchangeRate() public view returns (uint256 exchangeRate_) {
        uint256 _totalSupply = totalSupply;
        if (_totalSupply == uint256(0)) return WAD;
        return totalHolding() * WAD / _totalSupply;
    }

    function totalHoldings() public view returns (uint256 totalHoldings_) {
        return unlockedBalance(lastUpdated, vestingPeriod, issuanceRate, freeToken);
    }

    function unlockedBalance(uint256 lastUpdated_, uint256 vestingPeriod_, uint256 issuanceRate_, uint256 freeToken_) public pure returns (uint256 unlockedBalance_) {
        uint256 timeSinceLastUpdate = block.timestamp - lastUpdated_;
        uint256 dTime = timeSinceLastUpdate > vestingPeriod_ ? vestingPeriod_ : timeSinceLastUpdate;
        return issuanceRate_ * dTime + freeToken_;
    }

    function getTotalUnlockedAtEndOfPeriod(
        uint256 lastUpdated_,
        uint256 vestingPeriod_,
        uint256 issuanceRate_,
        uint256 freeToken_
    )
        public pure returns (uint256 totalUnlocked_)
    {
        uint256 timeSinceUpdate = block.timestamp - lastUpdated;
        uint256 dTime = timeSinceUpdate > vestingPeriod ? 0 : vestingPeriod_ - timeSinceUpdate;
        return freeToken + dTime * issuanceRate;
    }
}
