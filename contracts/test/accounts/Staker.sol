// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { TestUtils } from "../../../modules/contract-test-utils/contracts/test.sol";
import { console }   from "../../../modules/contract-test-utils/contracts/log.sol";

import { ERC20User } from "../../../modules/erc20/contracts/test/accounts/ERC20User.sol";
import { MockERC20 } from "../../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { IRevenueDistributionToken as IRDT } from "../../interfaces/IRevenueDistributionToken.sol";

contract Staker is ERC20User {

    function rdToken_deposit(address token_, uint256 assets_) external returns (uint256 shares_) {
        shares_ = IRDT(token_).deposit(assets_, address(this));
    }

    function rdToken_deposit(address token_, uint256 assets_, address receiver_) external returns (uint256 shares_) {
        shares_ = IRDT(token_).deposit(assets_, receiver_);
    }

    function rdToken_mint(address token_, uint256 shares_) external returns (uint256 assets_) {
        assets_ = IRDT(token_).mint(shares_, address(this));
    }

    function rdToken_mint(address token_, uint256 shares_, address receiver_) external returns (uint256 assets_) {
        assets_ = IRDT(token_).mint(shares_, receiver_);
    }

    function rdToken_redeem(address token_, uint256 shares_) external returns (uint256 assets_) {
        assets_ = IRDT(token_).redeem(shares_, address(this), address(this));
    }

    function rdToken_redeem(address token_, uint256 shares_, address recipient_, address owner_) external returns (uint256 assets_) {
        assets_ = IRDT(token_).redeem(shares_, recipient_, owner_);
    }

    function rdToken_withdraw(address token_, uint256 assets_) external returns (uint256 shares_) {
        shares_ = IRDT(token_).withdraw(assets_, address(this), address(this));
    }

    function rdToken_withdraw(address token_, uint256 assets_, address recipient_, address owner_) external returns (uint256 shares_) {
        shares_ = IRDT(token_).withdraw(assets_, recipient_, owner_);
    }

}

contract InvariantStaker is TestUtils {

    IRDT      internal _rdToken;
    MockERC20 internal _underlying;

    constructor(address rdToken_, address underlying_) {
        _rdToken    = IRDT(rdToken_);
        _underlying = MockERC20(underlying_);
    }

    // function deposit(uint256 assets_) external {
    //     // NOTE: The precision of the exchangeRate is equal to the amount of funds that can be deposited before rounding errors start to arise
    //     assets_ = constrictToRange(assets_, 1, 1e29);  // 100 billion at WAD precision (1 less than 1e30 to avoid precision issues)

    //     uint256 startingBalance = _rdToken.balanceOf(address(this));
    //     uint256 shareAmount     = _rdToken.previewDeposit(assets_);

    //     _underlying.mint(address(this),        assets_);
    //     _underlying.approve(address(_rdToken), assets_);

    //     _rdToken.deposit(assets_, address(this));

    //     assertEq(_rdToken.balanceOf(address(this)), startingBalance + shareAmount);  // Ensure successful deposit

    //     console.log("TEST");
    // }

    // function redeem(uint256 shares_) external {
    //     uint256 startingBalance = _rdToken.balanceOf(address(this));

    //     if (startingBalance > 0) {
    //         uint256 redeemAmount = constrictToRange(shares_, 1, _rdToken.balanceOf(address(this)));

    //         _rdToken.redeem(redeemAmount, address(this), address(this));

    //         assertEq(_rdToken.balanceOf(address(this)), startingBalance - redeemAmount);
    //     }
    //     console.log("TEST");
    // }


    // function withdraw(uint256 assets_) external {
    //     uint256 startingBalance = _underlying.balanceOf(address(this));

    //     if (startingBalance > 0) {
    //         uint256 withdrawAmount = constrictToRange(assets_, 1, _rdToken.balanceOfAssets(address(this)));

    //         _rdToken.withdraw(withdrawAmount, address(this), address(this));

    //         assertEq(_underlying.balanceOf(address(this)), startingBalance + withdrawAmount);  // Ensure successful withdraw
    //     }
    //     console.log("TEST");
    // }

    function deposit(uint256 assets_) external {
        // NOTE: The precision of the exchangeRate is equal to the amount of funds that can be deposited before rounding errors start to arise
        assets_ = constrictToRange(assets_, 1, 1e29);  // 100 billion at WAD precision (1 less than 1e30 to avoid precision issues)

        uint256 startingBalance = _rdToken.balanceOf(address(this));
        uint256 shareAmount     = _rdToken.previewDeposit(assets_);

        bool ok;

        ( ok, ) = address(_underlying).call(abi.encodeWithSignature("mint(address,uint256)", address(this), assets_));

        if (!ok) {
            console.log("deposit REVERT");
        } else {
            console.log("deposit SUCCESS");
        }
        console.log("mint(address,uint256)", address(this), assets_);

        ( ok, ) = address(_underlying).call(abi.encodeWithSignature("approve(address,uint256)", address(_rdToken), assets_));

        if (!ok) {
            console.log("deposit REVERT");
        } else {
            console.log("deposit SUCCESS");
        }
        console.log("approve(address,uint256)", address(_rdToken), assets_);

        ( ok, ) = address(_rdToken).call(abi.encodeWithSignature("deposit(uint256,address)", assets_, address(this)));

        if (!ok) {
            console.log("deposit REVERT");
        } else {
            console.log("deposit SUCCESS");
        }
        console.log("deposit(uint256,address)", assets_, address(this));

        assertEq(_rdToken.balanceOf(address(this)), startingBalance + shareAmount);  // Ensure successful deposit
    }

    function redeem(uint256 shares_) external {
        uint256 startingBalance = _rdToken.balanceOf(address(this));

        if (startingBalance > 0) {
            uint256 redeemAmount = constrictToRange(shares_, 1, _rdToken.balanceOf(address(this)));

            ( bool ok, ) = address(_rdToken).call(abi.encodeWithSignature("redeem(uint256,address,address)", shares_, address(this), address(this)));

            if (!ok) {
                console.log("redeem REVERT");
            } else {
                console.log("redeem SUCCESS");
            }
            console.log("redeem(uint256,address,address)", shares_, address(this));

            assertEq(_rdToken.balanceOf(address(this)), startingBalance - redeemAmount);
        }
    }

    function withdraw(uint256 assets_) external {
        uint256 startingBalance = _underlying.balanceOf(address(this));

        if (startingBalance > 0) {
            uint256 withdrawAmount = constrictToRange(assets_, 1, _rdToken.balanceOfAssets(address(this)));

            ( bool ok, ) = address(_rdToken).call(abi.encodeWithSignature("withdraw(uint256,address,address)", assets_, address(this), address(this)));

            if (!ok) {
                console.log("withdraw REVERT");
            } else {
                console.log("withdraw SUCVESS");
            }
            console.log("withdraw(uint256,address,address)", assets_, address(this));

            assertEq(_underlying.balanceOf(address(this)), startingBalance + withdrawAmount);  // Ensure successful withdraw
        }
    }

}

contract InvariantStakerManager is TestUtils {

    address internal _rdToken;
    address internal _underlying;

    InvariantStaker[] public stakers;

    constructor(address rdToken_, address underlying_) {
        _rdToken    = rdToken_;
        _underlying = underlying_;
    }

    function createStaker() external {
        InvariantStaker staker = new InvariantStaker(_rdToken, _underlying);
        stakers.push(staker);
        console.log("createStaker");
    }

    function deposit(uint256 amount_, uint256 index_) external {
        stakers[constrictToRange(index_, 0, stakers.length - 1)].deposit(amount_);
        console.log("deposit");
        // revert();
    }

    function redeem(uint256 amount_, uint256 index_) external {
        stakers[constrictToRange(index_, 0, stakers.length - 1)].redeem(amount_);
        console.log("redeem");
        // revert();
    }

    function withdraw(uint256 amount_, uint256 index_) external {
        stakers[constrictToRange(index_, 0, stakers.length - 1)].withdraw(amount_);
        console.log("withdraw");
        // revert();
    }

    function getStakerCount() external view returns (uint256 stakerCount_) {
        return stakers.length;
    }

    // function deposit(uint256 amount_, uint256 index_) external {
    //     ( bool ok, ) = address(stakers[constrictToRange(index_, 0, stakers.length - 1)]).call(abi.encodeWithSignature("deposit(uint256)", amount_));
    //     if (!ok) {
    //         console.log("deposit STAKER REVERT");
    //         console.log("deposit(uint256)", amount_);
    //         fail();
    //     }
    // }

    // function redeem(uint256 amount_, uint256 index_) external {
    //     ( bool ok, ) = address(stakers[constrictToRange(index_, 0, stakers.length - 1)]).call(abi.encodeWithSignature("redeem(uint256)", amount_));
    //     if (!ok) {
    //         console.log("redeem STAKER REVERT");
    //         console.log("redeem(uint256)", amount_);
    //         fail();
    //     }
    // }

    // function withdraw(uint256 amount_, uint256 index_) external {
    //     ( bool ok, ) = address(stakers[constrictToRange(index_, 0, stakers.length - 1)]).call(abi.encodeWithSignature("withdraw(uint256)", amount_));
    //     if (!ok) {
    //         console.log("withdraw STAKER REVERT");
    //         console.log("withdraw(uint256)", amount_);
    //         fail();
    //     }
    // }

}
