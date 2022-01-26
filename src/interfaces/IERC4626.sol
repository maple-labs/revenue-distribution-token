// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

interface IERC4626 {
    function deposit(address to, uint256 value) external returns (uint256 shares);
    function mint(address to, uint256 shares) external returns (uint256 value);
    function withdraw(address from, address to, uint256 value) external returns (uint256 shares);
    function redeem(address from, address to, uint256 shares) external returns (uint256 value);
    function underlying() external view returns (address);
    function totalUnderlying() external view returns (uint256);
    function balanceOfUnderlying(address owner) external view returns (uint256);
    function exchangeRate() external view returns (uint256);
    function previewDeposit(uint256 underlyingAmount) external view returns (uint256 shareAmount);
    function previewMint(uint256 shareAmount) external view returns (uint256 underlyingAmount);
    function previewWithdraw(uint256 underlyingAmount) external view returns (uint256 shareAmount);
    function previewRedeem(uint256 shareAmount) external view returns (uint256 underlyingAmount);
}
