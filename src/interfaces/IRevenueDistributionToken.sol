// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

// TODO: add natspec + inherit from IERC4626 once spec is well defined.
interface IRevenueDistributionToken {
    event Deposit(address indexed from, uint256 value);
    event Withdraw(address indexed to, uint256 value);

    function balanceOfUnderlying(address account) external view returns (uint256);
    function deposit(uint256 amount) external returns (uint256 shares);
    function exchangeRate() external view returns (uint256);
    function previewDeposit(uint256 underlyingAmount) external view returns (uint256 shareAmount);
    function previewWithdraw(uint256 underlyingAmount) external view returns (uint256 shareAmount);
    function previewRedeem(uint256 shareAmount) external view returns (uint256 underlyingAmount);
    function redeem(uint256 poolTokenAmount) external returns (uint256 value);
    function totalHoldings() external view returns (uint256);
    function underlying() external view returns (address);
    function withdraw(uint256 fundsAssetAmount) external returns (uint256 shares);
}
