// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { IRevenueDistributionToken } from "../../interfaces/IRevenueDistributionToken.sol";

contract Owner {

    function rdToken_acceptOwnership(address rdt_) external {
        IRevenueDistributionToken(rdt_).acceptOwnership();
    }

    function rdToken_setPendingOwner(address rdt_, address pendingOwner_) external {
        IRevenueDistributionToken(rdt_).setPendingOwner(pendingOwner_);
    }

    function rdToken_updateVestingSchedule(address rdt_, uint256 vestingPeriod_) external {
        IRevenueDistributionToken(rdt_).updateVestingSchedule(vestingPeriod_);
    }

}

contract InvariantOwner {

    address rdToken;

    constructor(address rdToken_) {
        rdToken = rdToken_;
    }

    function rdToken_updateVestingSchedule(uint256 vestingPeriod_) external {
        IRevenueDistributionToken(rdToken).updateVestingSchedule(vestingPeriod_);
    }

}