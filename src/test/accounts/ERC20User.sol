// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { IERC20 } from "lib/erc20/src/interfaces/IERC20.sol";

contract InvariantERC20User {

    address rdToken;
    address token;

    constructor(address rdToken_, address token_) {
        rdToken = rdToken_;
        token   = token_;
    }

    function transfer(uint256 amount_) external {
        IERC20(token).transfer(rdToken, amount_);
    }

}