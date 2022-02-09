// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { IRevenueDistributionToken } from "../../interfaces/IRevenueDistributionToken.sol";

contract Owner {

    function rdToken_acceptOwner(address rdt_) external {
        IRevenueDistributionToken(rdt_).acceptOwner();
    }

    function rdToken_setPendingOwner(address rdt_, address pendingOwner_) external {
        IRevenueDistributionToken(rdt_).setPendingOwner(pendingOwner_);
    }

    function rdToken_updateVestingSchedule(address rdt_, uint256 vestingPeriod_) external {
        IRevenueDistributionToken(rdt_).updateVestingSchedule(vestingPeriod_);
    }

}