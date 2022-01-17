// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import { ERC20 } from "lib/erc20/src/ERC20.sol";

contract xMPL is ERC20 {

    address constant public MPL = 0x33349B282065b0284d756F0577FB39c158F935e6;

    function depositMPL(uint256 amount) external {

    }

    // transfer
    // underlying
    // 4626 style

    // deposit
    // withdraw
    // redeem
    // balanceOfUnderlying
    // exchangeRate
    // totalHoldings

    function totalHoldings() external view returns (uint256 totalHoldings_) {
        return _freeBalance + rateOfIssuance * dTime;  // y = mx + b
    }
}
