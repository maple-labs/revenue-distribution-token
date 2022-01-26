// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { ERC20User } from "../../../lib/erc20/src/test/accounts/ERC20User.sol";

import { IRevenueDistributionToken } from "../../interfaces/IRevenueDistributionToken.sol";

contract Staker is ERC20User {

    function rdToken_deposit(address pool, uint256 amount) external {
        IRevenueDistributionToken(pool).deposit(amount);
    }

    function rdToken_redeem(address pool, uint256 amount) external {
        IRevenueDistributionToken(pool).redeem(amount);
    }

    function rdToken_withdraw(address pool, uint256 amount) external {
        IRevenueDistributionToken(pool).withdraw(amount);
    }

}