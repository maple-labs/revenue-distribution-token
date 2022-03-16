// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

contract MockRevertingERC20 {

    uint8 public immutable decimals;

    string public name;
    string public symbol;

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;

    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name     = name_;
        symbol   = symbol_;
        decimals = decimals_;
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    function mint(address recipient_, uint256 amount_) external {
        _mint(recipient_, amount_);
    }

    function burn(address from_, uint256 amount_) external {
        _burn(from_, amount_);
    }

    function approve(address spender_, uint256 amount_) external returns (bool success_) {
        _approve(msg.sender, spender_, amount_);
        return true;
    }

    function transfer(address recipient_, uint256 amount_) external returns (bool success_) {
        require(recipient_ != address(0), "INVALID");
        _transfer(msg.sender, recipient_, amount_);
        return true;
    }

    function transferFrom(address owner_, address recipient_, uint256 amount_) external returns (bool success_) {
        _approve(owner_, msg.sender, allowance[owner_][msg.sender] - amount_);
        _transfer(owner_, recipient_, amount_);
        return true;
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _approve(address owner_, address spender_, uint256 amount_) internal {
        allowance[owner_][spender_] = amount_;
    }

    function _transfer(address owner_, address recipient_, uint256 amount_) internal {
        balanceOf[owner_]     -= amount_;
        balanceOf[recipient_] += amount_;
    }

    function _mint(address recipient_, uint256 amount_) internal {
        totalSupply           += amount_;
        balanceOf[recipient_] += amount_;
    }

    function _burn(address owner_, uint256 amount_) internal {
        balanceOf[owner_] -= amount_;
        totalSupply       -= amount_;
    }

}
