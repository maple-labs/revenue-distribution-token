// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

interface Vm {
    function expectRevert(bytes calldata error_) external;
    function store(address contract_, bytes32 location_, bytes32 value_) external view;
    function warp(uint256 timestamp_) external;
}