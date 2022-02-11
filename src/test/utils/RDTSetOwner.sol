// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { RevenueDistributionToken } from "../../RevenueDistributionToken.sol";

contract RDT_setOwner is RevenueDistributionToken {

    constructor(string memory name_, string memory symbol_, address owner_, address underlying_, uint256 precision_)
        RevenueDistributionToken(name_, symbol_, owner_, underlying_, precision_)
    { }

    function setOwner(address owner_) external {
        owner = owner_;
    }

}