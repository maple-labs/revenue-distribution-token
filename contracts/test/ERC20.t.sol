// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { ERC20 }           from "../../modules/erc20/contracts/ERC20.sol";
import { ERC20User }       from "../../modules/erc20/contracts/test/accounts/ERC20User.sol";
import { ERC20BaseTest }   from "../../modules/erc20/contracts/test/ERC20.t.sol";
import { ERC20PermitTest } from "../../modules/erc20/contracts/test/ERC20.t.sol";
import { MockERC20 }       from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { RevenueDistributionToken as RDT } from "../RevenueDistributionToken.sol";

import { MockERC20_RDT } from "./mocks/MockERC20.RDT.sol";  // Required for mint/burn tests

contract RDT_ERC20Test is ERC20BaseTest {

    function setUp() override public {
        address asset = address(new MockERC20("MockToken", "MT", 18));

        _token = MockERC20(address(new MockERC20_RDT("Token", "TKN", address(this), asset, 1e30)));
    }

}

contract RDT_ERC20PermitTest is ERC20PermitTest {

    function setUp() override public {
        super.setUp();

        address asset = address(new MockERC20("MockToken", "MT", 18));

        _token = ERC20(address(new RDT("Token", "TKN", address(this), asset, 1e30)));
    }

    function test_domainSeparator() public override {
        assertEq(_token.DOMAIN_SEPARATOR(), 0xa0948b5dcf9f99364e925fbc7ed09b4fa9c2ca703920db5c3c2453442cc5dd0d);
    }

}
