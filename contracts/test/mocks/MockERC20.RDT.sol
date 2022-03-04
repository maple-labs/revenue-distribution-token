// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { RevenueDistributionToken as RDT } from "../../RevenueDistributionToken.sol";

contract MockERC20_RDT is RDT {

    constructor(string memory name_, string memory symbol_, address owner_, address asset_, uint256 precision_)
        RDT(name_, symbol_, owner_, asset_, precision_) { }

    function mint(address to_, uint256 value_) external {
        _mint(to_, value_);
    }

    function burn(address from_, uint256 value_) external {
        _burn(from_, value_);
    }

}