// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import {RevenueDistributionToken as RDT} from
    "../../RevenueDistributionToken.sol";

contract MockERC20_RDT is RDT {
    constructor(
        string memory name_,
        string memory symbol_,
        address owner_,
        address asset_,
        uint256 precision_
    )
        RDT(name_, symbol_, owner_, asset_, precision_)
    {}

    function mint(address recipient_, uint256 amount_) external {
        _mint(recipient_, amount_);
    }

    function burn(address owner_, uint256 amount_) external {
        _burn(owner_, amount_);
    }
}