// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { RevenueDistributionToken as RDT } from "../../RevenueDistributionToken.sol";

contract MockRDT is RDT {

    constructor(string memory name_, string memory symbol_, address owner_, address asset_, uint256 precision_)
        RDT(name_, symbol_, owner_, asset_, precision_) { }

    function __setTotalAssets(uint256 amount_) external {
        freeAssets          = amount_;
        vestingPeriodFinish = block.timestamp - 1;
        _updateIssuanceParams();
    }

}