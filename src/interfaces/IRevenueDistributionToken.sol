// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

interface IRevenueDistributionToken {
    function deposit(uint256 amount) external;
    function withdraw(uint256 fundsAssetAmount) external;
    function redeem(uint256 poolTokenAmount) external;
    function exchangeRate() external view returns (uint256);
    function totalHoldings() external view returns (uint256);
    function balanceOfUnderlying(address account) external view returns (uint256);
}
