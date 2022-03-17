// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;


import { TestUtils } from "../../modules/contract-test-utils/contracts/test.sol";
import { MockERC20 } from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { MockRDT } from "./mocks/MockRDT.sol";
import { Owner }   from "./accounts/Owner.sol";
import { Staker }  from "./accounts/Staker.sol";

import { RevenueDistributionToken as RDT } from "../RevenueDistributionToken.sol";

contract APRViewTests is TestUtils {

    uint256 constant START = 10_000_000;

    MockERC20 asset;
    Owner     owner;
    RDT       rdToken;
    Staker    staker;

    function setUp() public {
        asset   = new MockERC20("MockToken", "MT", 18);
        owner   = new Owner();
        rdToken = new RDT("Revenue Distribution Token", "RDT", address(owner), address(asset), 1e30);
        staker  = new Staker();
        vm.warp(START);
    }

    function test_APR(uint256 mintAmount_, uint256 vestingAmount_, uint256 vestingPeriod_) public {
        mintAmount_    = constrictToRange(mintAmount_,    0.0001e18, 1e29);
        vestingAmount_ = constrictToRange(mintAmount_,    0.0001e18, 1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 days,    10_000 days);

        asset.mint(address(staker), mintAmount_);

        staker.erc20_approve(address(asset), address(rdToken), mintAmount_);
        staker.rdToken_mint(address(rdToken), mintAmount_);

        asset.mint(address(owner), vestingAmount_);

        owner.erc20_transfer(address(asset), address(rdToken), vestingAmount_);
        owner.rdToken_updateVestingSchedule(address(rdToken), vestingPeriod_);

        uint256 apr = rdToken.APR();

        vm.warp(START + vestingPeriod_);

        staker.rdToken_redeem(address(rdToken), mintAmount_);  // Redeem entire balance

        uint256 aprProjectedEarnings = mintAmount_ * apr * vestingPeriod_ / 365 days / 1e6;

        assertWithinPrecision(asset.balanceOf(address(staker)), mintAmount_ + aprProjectedEarnings, 4);
    }

}

contract ConvertViewTests is TestUtils {

    MockERC20 asset;
    MockRDT   rdToken;
    Staker    staker;

    function setUp() public virtual {
        asset   = new MockERC20("MockToken", "MT", 18);
        rdToken = new MockRDT("Revenue Distribution Token", "RDT", address(this), address(asset), 1e30);
        staker  = new Staker();
        vm.warp(10_000_000);  // Warp to non-zero timestamp for __setTotalAssets
    }

    function test_convertToShares(uint256 totalAssets_, uint256 mintAmount_) public {
        totalAssets_ = constrictToRange(mintAmount_, 1, 1e29);
        mintAmount_  = constrictToRange(mintAmount_, 1, totalAssets_);  // So totalAssets > totalSupply

        asset.mint(address(staker), mintAmount_);

        staker.erc20_approve(address(asset), address(rdToken), mintAmount_);
        staker.rdToken_mint(address(rdToken), mintAmount_);

        rdToken.__setTotalAssets(totalAssets_);

        assertEq(rdToken.convertToShares(totalAssets_), mintAmount_);
    }

    function test_convertToAssets(uint256 totalAssets_, uint256 mintAmount_) public {
        totalAssets_ = constrictToRange(mintAmount_, 1, 1e29);
        mintAmount_  = constrictToRange(mintAmount_, 1, totalAssets_);  // So totalAssets > totalSupply

        asset.mint(address(staker), mintAmount_);

        staker.erc20_approve(address(asset), address(rdToken), mintAmount_);
        staker.rdToken_mint(address(rdToken), mintAmount_);

        rdToken.__setTotalAssets(totalAssets_);

        assertEq(rdToken.convertToAssets(mintAmount_), totalAssets_);
    }

}

contract MaxViewTests is TestUtils {

    MockERC20 asset;
    MockRDT   rdToken;
    Staker    staker;

    function setUp() public virtual {
        asset   = new MockERC20("MockToken", "MT", 18);
        rdToken = new MockRDT("Revenue Distribution Token", "RDT", address(this), address(asset), 1e30);
        staker  = new Staker();
        vm.warp(10_000_000);  // Warp to non-zero timestamp for __setTotalAssets
    }

    function test_maxDeposit(address receiver_) public {
        assertEq(rdToken.maxDeposit(receiver_), type(uint256).max);
    }

    function test_maxMint(address receiver_) public {
        assertEq(rdToken.maxMint(receiver_), type(uint256).max);
    }

    function test_maxRedeem(uint256 totalAssets_, uint256 mintAmount_) public {
        totalAssets_ = constrictToRange(mintAmount_, 1, 1e29);
        mintAmount_  = constrictToRange(mintAmount_, 1, totalAssets_);  // So totalAssets > totalSupply

        asset.mint(address(staker), mintAmount_);

        staker.erc20_approve(address(asset), address(rdToken), mintAmount_);
        staker.rdToken_mint(address(rdToken), mintAmount_);

        rdToken.__setTotalAssets(totalAssets_);

        assertEq(rdToken.maxRedeem(address(staker)), mintAmount_);
    }

    function test_maxWithdraw(uint256 totalAssets_, uint256 mintAmount_) public {
        totalAssets_ = constrictToRange(mintAmount_, 1, 1e29);
        mintAmount_  = constrictToRange(mintAmount_, 1, totalAssets_);  // So totalAssets > totalSupply

        asset.mint(address(staker), mintAmount_);

        staker.erc20_approve(address(asset), address(rdToken), mintAmount_);
        staker.rdToken_mint(address(rdToken), mintAmount_);

        rdToken.__setTotalAssets(totalAssets_);

        assertEq(rdToken.maxWithdraw(address(staker)), totalAssets_);
    }

}

contract PreviewViewTests is TestUtils {

    MockERC20 asset;
    MockRDT   rdToken;
    Staker    staker;

    function setUp() public virtual {
        asset   = new MockERC20("MockToken", "MT", 18);
        rdToken = new MockRDT("Revenue Distribution Token", "RDT", address(this), address(asset), 1e30);
        staker  = new Staker();
        vm.warp(10_000_000);  // Warp to non-zero timestamp for __setTotalAssets
    }

    function test_previewDeposit(uint256 totalAssets_, uint256 mintAmount_) public {
        totalAssets_ = constrictToRange(mintAmount_, 1, 1e29);
        mintAmount_  = constrictToRange(mintAmount_, 1, totalAssets_);  // So totalAssets > totalSupply

        asset.mint(address(staker), mintAmount_);

        staker.erc20_approve(address(asset), address(rdToken), mintAmount_);
        staker.rdToken_mint(address(rdToken), mintAmount_);

        rdToken.__setTotalAssets(totalAssets_);

        assertEq(rdToken.previewDeposit(totalAssets_), mintAmount_);
    }

    function test_previewMint(uint256 totalAssets_, uint256 mintAmount_) public {
        totalAssets_ = constrictToRange(mintAmount_, 1, 1e29);
        mintAmount_  = constrictToRange(mintAmount_, 1, totalAssets_);  // So totalAssets > totalSupply

        asset.mint(address(staker), mintAmount_);

        staker.erc20_approve(address(asset), address(rdToken), mintAmount_);
        staker.rdToken_mint(address(rdToken), mintAmount_);

        rdToken.__setTotalAssets(totalAssets_);

        assertEq(rdToken.previewMint(mintAmount_), totalAssets_);
    }

}

// TODO: test totalAssets
