// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { TestUtils }                  from "../../modules/contract-test-utils/contracts/test.sol";
import { MockERC20, MockERC20Permit } from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { MockRevertingERC20 } from "./mocks/MockRevertingERC20.sol";

import { Owner }  from "./accounts/Owner.sol";
import { Staker } from "./accounts/Staker.sol";

import { RevenueDistributionToken as RDT } from "../RevenueDistributionToken.sol";

contract ConstructorTest is TestUtils {

    function test_constructor_ownerZeroAddress() external {
        MockERC20Permit asset   = new MockERC20Permit("MockToken", "MT", 18);

        vm.expectRevert("RDT:C:OWNER_ZERO_ADDRESS");
        RDT rdToken = new RDT("Revenue Distribution Token", "RDT", address(0), address(asset), 1e30);

        rdToken = new RDT("Revenue Distribution Token", "RDT", address(this), address(asset), 1e30);
    }
    
}

contract DepositAndMintWithPermitTest is TestUtils {

    MockERC20Permit asset;
    RDT             rdToken;

    uint256 stakerPrivateKey    = 1;
    uint256 notStakerPrivateKey = 2;
    uint256 nonce               = 0;
    uint256 deadline            = 5_000_000_000;  // Timestamp far in the future

    uint256 constant sampleAssetsToConvert = 1e18;
    uint256 constant sampleSharesToConvert = 1e18;

    address staker;
    address notStaker;

    function setUp() public virtual {
        asset   = new MockERC20Permit("MockToken", "MT", 18);
        rdToken = new RDT("Revenue Distribution Token", "RDT", address(this), address(asset), 1e30);

        staker    = vm.addr(stakerPrivateKey);
        notStaker = vm.addr(notStakerPrivateKey);

        vm.warp(10_000_000);  // Warp to non-zero timestamp
    }

    function test_depositWithPermit_zeroAddress() external {
        uint256 depositAmount = 1e18;
        asset.mint(address(staker), depositAmount);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(depositAmount, staker, address(rdToken), stakerPrivateKey, deadline);

        vm.startPrank(staker);

        vm.expectRevert(bytes("ERC20Permit:INVALID_SIGNATURE"));
        rdToken.depositWithPermit(depositAmount, staker, deadline, 17, r, s);

        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);
    }

    function test_depositWithPermit_notStakerSignature() external {
        uint256 depositAmount = 1e18;
        asset.mint(address(staker), depositAmount);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(depositAmount, notStaker, address(rdToken), notStakerPrivateKey, deadline);

        vm.startPrank(staker);

        vm.expectRevert(bytes("ERC20Permit:INVALID_SIGNATURE"));
        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);

        ( v, r, s ) = _getValidPermitSignature(depositAmount, staker, address(rdToken), stakerPrivateKey, deadline);

        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);

    }

    function test_depositWithPermit_pastDeadline() external {
        uint256 depositAmount = 1e18;
        asset.mint(address(staker), depositAmount);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(depositAmount, staker, address(rdToken), stakerPrivateKey, deadline);

        vm.startPrank(staker);

        vm.warp(deadline + 1);

        vm.expectRevert(bytes("ERC20Permit:EXPIRED"));
        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);

        vm.warp(deadline);

        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);
    }

    function test_depositWithPermit_replay() external {
        uint256 depositAmount = 1e18;
        asset.mint(address(staker), depositAmount * 2);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(depositAmount, staker, address(rdToken), stakerPrivateKey, deadline);

        vm.startPrank(staker);

        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);

        vm.expectRevert(bytes("ERC20Permit:INVALID_SIGNATURE"));
        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);
    }

    function test_depositWithPermit_preVesting(uint256 depositAmount) external {
        depositAmount = constrictToRange(depositAmount, 1, 1e29);

        asset.mint(address(staker), depositAmount);

        assertEq(rdToken.balanceOf(address(staker)),             0);
        assertEq(rdToken.totalSupply(),                          0);
        assertEq(rdToken.freeAssets(),                           0);
        assertEq(rdToken.totalAssets(),                          0);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          0);

        assertEq(asset.balanceOf(address(staker)),  depositAmount);
        assertEq(asset.balanceOf(address(rdToken)), 0);

        assertEq(asset.nonces(staker),                      0);
        assertEq(asset.allowance(staker, address(rdToken)), 0);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(depositAmount, staker, address(rdToken), stakerPrivateKey, deadline);
        vm.prank(staker);
        uint256 shares = rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);

        assertEq(asset.allowance(staker, address(rdToken)), 0); // Should have used whole allowance
        assertEq(asset.nonces(staker),                      1);

        assertEq(shares, rdToken.balanceOf(staker));

        assertEq(rdToken.balanceOf(address(staker)),             depositAmount);
        assertEq(rdToken.totalSupply(),                          depositAmount);
        assertEq(rdToken.freeAssets(),                           depositAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert); // No revenue, conversion should be the same.
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          block.timestamp);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount);
    }

    function test_mintWithPermit_zeroAddress() external {
        uint256 depositAmount = 1e18;
        asset.mint(address(staker), depositAmount);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(depositAmount, staker, address(rdToken), stakerPrivateKey, deadline);

        uint mintAmount = depositAmount;

        vm.startPrank(staker);

        vm.expectRevert(bytes("ERC20Permit:INVALID_SIGNATURE"));
        rdToken.mintWithPermit(mintAmount, staker, deadline, 17, r, s);

        rdToken.mintWithPermit(mintAmount, staker, deadline, v, r, s);
    }

    function test_mintWithPermit_notStakerSignature() external {
        uint256 depositAmount = 1e18;
        asset.mint(address(staker), depositAmount);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(depositAmount, notStaker, address(rdToken), notStakerPrivateKey, deadline);

        uint mintAmount = depositAmount;

        vm.startPrank(staker);

        vm.expectRevert(bytes("ERC20Permit:INVALID_SIGNATURE"));
        rdToken.depositWithPermit(mintAmount, staker, deadline, v, r, s);

        ( v, r, s ) = _getValidPermitSignature(depositAmount, staker, address(rdToken), stakerPrivateKey, deadline);

        rdToken.depositWithPermit(mintAmount, staker, deadline, v, r, s);

    }

    function test_mintWithPermit_pastDeadline() external {
        uint256 depositAmount = 1e18;
        asset.mint(address(staker), depositAmount);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(depositAmount, staker, address(rdToken), stakerPrivateKey, deadline);

        uint mintAmount = depositAmount;

        vm.startPrank(staker);

        vm.warp(deadline + 1);

        vm.expectRevert(bytes("ERC20Permit:EXPIRED"));
        rdToken.mintWithPermit(mintAmount, staker, deadline, v, r, s);

        vm.warp(deadline);

        rdToken.mintWithPermit(mintAmount, staker, deadline, v, r, s);
    }

    function test_mintWithPermit_replay() external {
        uint256 depositAmount = 1e18;
        asset.mint(address(staker), depositAmount * 2);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(depositAmount, staker, address(rdToken), stakerPrivateKey, deadline);

        uint256 mintAmount = depositAmount;

        vm.startPrank(staker);

        rdToken.depositWithPermit(mintAmount, staker, deadline, v, r, s);

        vm.expectRevert(bytes("ERC20Permit:INVALID_SIGNATURE"));
        rdToken.depositWithPermit(mintAmount, staker, deadline, v, r, s);
    }

    function test_mintWithPermit_preVesting(uint256 mintAmount) external {
        mintAmount = constrictToRange(mintAmount, 1, 1e29);

        uint256 depositAmount = mintAmount; // totalSupply = totalAssets, so they will be equal.
        asset.mint(address(staker), depositAmount);

        assertEq(rdToken.balanceOf(address(staker)),             0);
        assertEq(rdToken.totalSupply(),                          0);
        assertEq(rdToken.freeAssets(),                           0);
        assertEq(rdToken.totalAssets(),                          0);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          0);

        assertEq(asset.balanceOf(address(staker)),  depositAmount);
        assertEq(asset.balanceOf(address(rdToken)), 0);

        assertEq(asset.nonces(staker),                      0);
        assertEq(asset.allowance(staker, address(rdToken)), 0);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(mintAmount, staker, address(rdToken), stakerPrivateKey, deadline);
        vm.prank(staker);
        uint256 assets = rdToken.mintWithPermit(mintAmount, staker, deadline, v, r, s);

        assertEq(asset.allowance(staker, address(rdToken)), 0); // Should have used whole allowance
        assertEq(asset.nonces(staker),                      1);

        assertEq(mintAmount,    rdToken.balanceOf(staker));
        assertEq(depositAmount, assets);

        assertEq(rdToken.balanceOf(address(staker)),             mintAmount);
        assertEq(rdToken.totalSupply(),                          mintAmount);
        assertEq(rdToken.freeAssets(),                           depositAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert); // No revenue, conversion should be the same.
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          block.timestamp);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), mintAmount);
    }

    // No need to further test *withPermit functionality, as in-depth deposit and mint testing will be done with the deposit() and mint() functions.

    // Returns an ERC-2612 `permit` digest for the `owner` to sign
    function _getDigest(address owner_, address spender_, uint256 value_, uint256 nonce_, uint256 deadline_) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                '\x19\x01',
                asset.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(asset.PERMIT_TYPEHASH(), owner_, spender_, value_, nonce_, deadline_))
            )
        );
    }

    // Returns a valid `permit` signature signed by this contract's `owner` address
    function _getValidPermitSignature(uint256 value_, address owner_, address spender_, uint256 ownerSk_, uint256 deadline_) internal returns (uint8 v_, bytes32 r_, bytes32 s_) {
        bytes32 digest = _getDigest(owner_, spender_, value_, nonce, deadline_);
        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(ownerSk_, digest);
        return (v, r, s);
    }

}

contract APRViewTest is TestUtils {

    MockERC20 asset;
    Owner     owner;
    RDT       rdToken;
    Staker    staker;

    uint256 START = 10_000_000;

    function setUp() public virtual {
        asset   = new MockERC20("MockToken", "MT", 18);
        owner   = new Owner();
        rdToken = new RDT("Revenue Distribution Token", "RDT", address(owner), address(asset), 1e30);
        staker  = new Staker();
        vm.warp(START);
    }

    function test_APR(uint256 mintAmount_, uint256 vestingAmount_, uint256 vestingPeriod_) external {
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

contract AuthTest is TestUtils {

    MockERC20 asset;
    Owner     notOwner;
    Owner     owner;
    RDT       rdToken;

    function setUp() public virtual {
        notOwner = new Owner();
        owner    = new Owner();
        asset    = new MockERC20("MockToken", "MT", 18);
        rdToken  = new RDT("Revenue Distribution Token", "RDT", address(owner), address(asset), 1e30);
    }

    function test_setPendingOwner_acl() external {
        vm.expectRevert("RDT:SPO:NOT_OWNER");
        notOwner.rdToken_setPendingOwner(address(rdToken), address(1));

        assertEq(rdToken.pendingOwner(), address(0));
        owner.rdToken_setPendingOwner(address(rdToken), address(1));
        assertEq(rdToken.pendingOwner(), address(1));
    }

    function test_acceptOwnership_acl() external {
        owner.rdToken_setPendingOwner(address(rdToken), address(notOwner));

        vm.expectRevert("RDT:AO:NOT_PO");
        owner.rdToken_acceptOwnership(address(rdToken));

        assertEq(rdToken.pendingOwner(), address(notOwner));
        assertEq(rdToken.owner(),        address(owner));

        notOwner.rdToken_acceptOwnership(address(rdToken));

        assertEq(rdToken.pendingOwner(), address(0));
        assertEq(rdToken.owner(),        address(notOwner));
    }

    function test_updateVestingSchedule_acl() external {
        // Use non-zero timestamp
        vm.warp(10_000);

        asset.mint(address(rdToken), 1000);

        vm.expectRevert("RDT:UVS:NOT_OWNER");
        notOwner.rdToken_updateVestingSchedule(address(rdToken), 100 seconds);

        assertEq(rdToken.freeAssets(),          0);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         0);
        assertEq(rdToken.vestingPeriodFinish(), 0);

        owner.rdToken_updateVestingSchedule(address(rdToken), 100 seconds);

        assertEq(rdToken.freeAssets(),          0);
        assertEq(rdToken.issuanceRate(),        10e30);
        assertEq(rdToken.lastUpdated(),         10_000);
        assertEq(rdToken.vestingPeriodFinish(), 10_100);
    }

}

contract DepositAndMintTest is TestUtils {

    MockERC20 asset;
    RDT       rdToken;
    Staker    staker;

    uint256 constant sampleAssetsToConvert = 1e18;
    uint256 constant sampleSharesToConvert = 1e18;

    function setUp() public virtual {
        asset   = new MockERC20("MockToken", "MT", 18);
        rdToken = new RDT("Revenue Distribution Token", "RDT", address(this), address(asset), 1e30);
        staker  = new Staker();

        vm.warp(10_000_000);  // Warp to non-zero timestamp

    }

    function test_deposit_zeroAmount() external {

        asset.mint(address(staker), 1);
        staker.erc20_approve(address(asset), address(rdToken), 1);

        vm.expectRevert("RDT:D:ZERO_ASSETS");
        staker.rdToken_deposit(address(rdToken), 0);

        staker.rdToken_deposit(address(rdToken), 1);
    }

    function test_deposit_badApprove(uint256 depositAmount) external {

        depositAmount = constrictToRange(depositAmount, 1, 1e29);

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount - 1);

        vm.expectRevert("RDT:D:TRANSFER_FROM");
        staker.rdToken_deposit(address(rdToken), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);
    }

    function test_deposit_insufficientBalance(uint256 depositAmount) external {

        depositAmount = constrictToRange(depositAmount, 1, 1e29);

        asset.mint(address(staker), depositAmount);
        staker.erc20_approve(address(asset), address(rdToken), depositAmount + 1);

        vm.expectRevert("RDT:D:TRANSFER_FROM");
        staker.rdToken_deposit(address(rdToken), depositAmount + 1);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);
    }

    function test_deposit_zeroShares() external {
        uint256 depositAmount = 1;

        // Do a deposit so that totalSupply is non-zero
        asset.mint(address(this), 20e18);
        asset.approve(address(rdToken), 20e18);
        rdToken.deposit(20e18, address(this));

        _transferAndUpdateVesting(5e18, 10 seconds);

        vm.warp(block.timestamp + 2 seconds);

        asset.mint(address(staker), depositAmount);
        staker.erc20_approve(address(asset), address(rdToken), depositAmount);

        vm.expectRevert("RDT:D:ZERO_SHARES");
        staker.rdToken_deposit(address(rdToken), depositAmount);

        // Deposit larger amount
        depositAmount = 1e5;

        asset.mint(address(staker), depositAmount);
        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);
    }

    function test_deposit_preVesting(uint256 depositAmount) external {

        depositAmount = constrictToRange(depositAmount, 1, 1e29);

        asset.mint(address(staker), depositAmount);

        assertEq(rdToken.balanceOf(address(staker)),             0);
        assertEq(rdToken.totalSupply(),                          0);
        assertEq(rdToken.freeAssets(),                           0);
        assertEq(rdToken.totalAssets(),                          0);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          0);

        assertEq(asset.balanceOf(address(staker)),  depositAmount);
        assertEq(asset.balanceOf(address(rdToken)), 0);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);

        uint256 shares = staker.rdToken_deposit(address(rdToken), depositAmount);

        assertEq(shares, rdToken.balanceOf(address(staker)));

        assertEq(rdToken.balanceOf(address(staker)),             depositAmount);
        assertEq(rdToken.totalSupply(),                          depositAmount);
        assertEq(rdToken.freeAssets(),                           depositAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert); // No revenue, conversion should be the same.
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          block.timestamp);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount);
    }

    function test_mint_zeroAmount() external {

        asset.mint(address(staker), 1);
        staker.erc20_approve(address(asset), address(rdToken), 1);

        vm.expectRevert("RDT:M:AMOUNT");
        staker.rdToken_mint(address(rdToken), 0);

        staker.rdToken_mint(address(rdToken), 1);
    }

    function test_mint_badApprove(uint256 mintAmount) external {

        mintAmount = constrictToRange(mintAmount, 1, 1e29);

        uint256 depositAmount = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount - 1);

        vm.expectRevert("RDT:M:TRANSFER_FROM");
        staker.rdToken_mint(address(rdToken), mintAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_mint(address(rdToken), mintAmount);
    }

    function test_mint_insufficientBalance(uint256 mintAmount) external {

        mintAmount = constrictToRange(mintAmount, 1, 1e29);

        uint256 depositAmount = rdToken.previewMint(mintAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);

        vm.expectRevert("RDT:M:TRANSFER_FROM");
        staker.rdToken_mint(address(rdToken), mintAmount);

        asset.mint(address(staker), depositAmount);

        staker.rdToken_mint(address(rdToken), mintAmount);
    }

    function test_mint_preVesting(uint256 mintAmount) external {

        mintAmount = constrictToRange(mintAmount, 1, 1e29);

        uint256 depositAmount = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), depositAmount);

        assertEq(rdToken.balanceOf(address(staker)),             0);
        assertEq(rdToken.totalSupply(),                          0);
        assertEq(rdToken.freeAssets(),                           0);
        assertEq(rdToken.totalAssets(),                          0);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          0);

        assertEq(asset.balanceOf(address(staker)),  depositAmount);
        assertEq(asset.balanceOf(address(rdToken)), 0);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);

        uint256 assets = staker.rdToken_mint(address(rdToken), mintAmount);
        assertEq(assets, depositAmount);

        assertEq(rdToken.balanceOf(address(staker)),             mintAmount);
        assertEq(rdToken.totalSupply(),                          mintAmount);
        assertEq(rdToken.freeAssets(),                           assets);
        assertEq(rdToken.totalAssets(),                          assets);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleAssetsToConvert); // No revenue, conversion should be the same.
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          block.timestamp);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), assets);
    }

    function test_deposit_totalAssetsGtTotalSupply_explicitVals() external {
        /*************/
        /*** Setup ***/
        /*************/

        uint256 start = block.timestamp;

        // Do a deposit so that totalSupply is non-zero
        asset.mint(address(this), 20e18);
        asset.approve(address(rdToken), 20e18);
        rdToken.deposit(20e18, address(this));

        _transferAndUpdateVesting(5e18, 10 seconds);

        vm.warp(start + 11 seconds);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        asset.mint(address(staker), 10e18);

        /********************/
        /*** Before state ***/
        /********************/

        assertEq(rdToken.balanceOf(address(staker)),             0);
        assertEq(rdToken.totalSupply(),                          20e18);
        assertEq(rdToken.freeAssets(),                           20e18);
        assertEq(rdToken.totalAssets(),                          25e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.25e18); // 1 * (20 + 5) / 20
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 0.8e18);  // 1 * 20 / (20 + 5)
        assertEq(rdToken.issuanceRate(),                         0.5e48);  // 5e18 * 1e30 / 10s
        assertEq(rdToken.lastUpdated(),                          start);

        assertEq(asset.balanceOf(address(staker)),  10e18);
        assertEq(asset.balanceOf(address(rdToken)), 25e18);

        /***************/
        /*** Deposit ***/
        /***************/

        staker.erc20_approve(address(asset), address(rdToken), 10e18);
        uint256 stakerShares = staker.rdToken_deposit(address(rdToken), 10e18);

        /*******************/
        /*** After state ***/
        /*******************/

        assertEq(stakerShares, 8e18);  // 10 / 1.25 exchangeRate

        assertEq(rdToken.balanceOf(address(staker)),             8e18);
        assertEq(rdToken.totalSupply(),                          28e18);  // 8 + original 10
        assertEq(rdToken.freeAssets(),                           35e18);
        assertEq(rdToken.totalAssets(),                          35e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.25e18); // totalAssets gets updated but share conversion stays constant
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 0.8e18);  // totalAssets gets updated but asset conversion stays constant
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          start + 11 seconds);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), 35e18);
    }

    function test_deposit_totalAssetsGtTotalSupply(uint256 initialAmount, uint256 depositAmount, uint256 vestingAmount) external {
        /*************/
        /*** Setup ***/
        /*************/

        uint256 minAmount = 1e2;

        initialAmount = constrictToRange(initialAmount, minAmount, 1e29);
        depositAmount = constrictToRange(depositAmount, minAmount, 1e29);
        vestingAmount = constrictToRange(vestingAmount, minAmount, initialAmount);

        // Do a deposit so that totalSupply is non-zero
        asset.mint(address(this), initialAmount);
        asset.approve(address(rdToken), initialAmount);
        uint256 initialShares = rdToken.deposit(initialAmount, address(this));

        uint256 start = block.timestamp;

        _transferAndUpdateVesting(vestingAmount, 10 seconds);

        vm.warp(start + 11 seconds);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        asset.mint(address(staker), depositAmount);

        /********************/
        /*** Before state ***/
        /********************/

        assertEq(rdToken.balanceOf(address(staker)),             0);
        assertEq(rdToken.totalSupply(),                          initialAmount);
        assertEq(rdToken.freeAssets(),                           initialAmount);
        assertEq(rdToken.totalAssets(),                          initialAmount + vestingAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert * (initialAmount + vestingAmount) / initialShares);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert * initialShares / (initialAmount + vestingAmount));
        assertEq(rdToken.issuanceRate(),                         vestingAmount * 1e30 / 10 seconds);
        assertEq(rdToken.lastUpdated(),                          start);

        assertEq(asset.balanceOf(address(staker)),  depositAmount);
        assertEq(asset.balanceOf(address(rdToken)), initialAmount + vestingAmount);

        /***************/
        /*** Deposit ***/
        /***************/

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        uint256 stakerShares = staker.rdToken_deposit(address(rdToken), depositAmount);

        /*******************/
        /*** After state ***/
        /*******************/

        assertEq(stakerShares, rdToken.balanceOf(address(staker)));

        assertEq(rdToken.balanceOf(address(staker)),             depositAmount * (initialShares + stakerShares) / (initialAmount + vestingAmount + depositAmount));
        assertEq(rdToken.totalSupply(),                          initialShares + stakerShares);
        assertEq(rdToken.freeAssets(),                           initialAmount + vestingAmount + depositAmount);
        assertEq(rdToken.totalAssets(),                          initialAmount + vestingAmount + depositAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert * (initialAmount + vestingAmount + depositAmount) / (initialShares + stakerShares));
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert * (initialShares + stakerShares) / (initialAmount + vestingAmount + depositAmount));
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          start + 11 seconds);

        // assertWithinDiff(rdToken.exchangeRate(), previousExchangeRate, 10000);  // Assert that exchangeRate doesn't change on new deposits TODO: Figure out why this is large

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), initialAmount + vestingAmount + depositAmount);
    }

    function _transferAndUpdateVesting(uint256 vestingAmount_, uint256 vestingPeriod_) internal {
        asset.mint(address(this), vestingAmount_);
        asset.transfer(address(rdToken), vestingAmount_);
        rdToken.updateVestingSchedule(vestingPeriod_);
    }

}

contract ExitTest is TestUtils {
    MockERC20 asset;
    RDT       rdToken;
    Staker    staker;

    uint256 constant sampleAssetsToConvert = 1e18;
    uint256 constant sampleSharesToConvert = 1e18;

    bytes constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

    function setUp() public virtual {
        asset   = new MockERC20("MockToken", "MT", 18);
        rdToken = new RDT("Revenue Distribution Token", "RDT", address(this), address(asset), 1e30);
        staker  = new Staker();

        vm.warp(10_000_000);  // Warp to non-zero timestamp
    }

    /************************/
    /*** `withdraw` tests ***/
    /************************/

    function test_withdraw_zeroAmount(uint256 depositAmount) external {
        _depositAsset(constrictToRange(depositAmount, 1, 1e29));

        vm.expectRevert("RDT:W:ZERO_ASSETS");
        staker.rdToken_withdraw(address(rdToken), 0);

        staker.rdToken_withdraw(address(rdToken), 1);
    }

    function test_withdraw_burnUnderflow(uint256 depositAmount) external {
        depositAmount = constrictToRange(depositAmount, 1, 1e29);
        _depositAsset(depositAmount);

        vm.expectRevert(ARITHMETIC_ERROR);
        staker.rdToken_withdraw(address(rdToken), depositAmount + 1);

        staker.rdToken_withdraw(address(rdToken), depositAmount);
    }

    function test_withdraw_burnUnderflow_totalAssetsGtTotalSupply_explicitVals() external {
        uint256 depositAmount = 100e18;
        uint256 vestingAmount = 10e18;
        uint256 vestingPeriod = 10 days;
        uint256 warpTime      = 5 days;

        _depositAsset(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        uint256 maxWithdrawAmount = rdToken.previewRedeem(rdToken.balanceOf(address(staker)));  // TODO

        vm.expectRevert(ARITHMETIC_ERROR);
        staker.rdToken_withdraw(address(rdToken), maxWithdrawAmount + 1);

        staker.rdToken_withdraw(address(rdToken), maxWithdrawAmount);
    }

    function test_withdraw_zeroShares() external {
        uint256 depositAmount = 1;

        // Do a deposit so that totalSupply is non-zero
        asset.mint(address(this), 20e18);
        asset.approve(address(rdToken), 20e18);
        rdToken.deposit(20e18, address(this));

        _transferAndUpdateVesting(5e18, 10 seconds);

        vm.warp(block.timestamp + 2 seconds);

        asset.mint(address(staker), depositAmount);
        staker.erc20_approve(address(asset), address(rdToken), depositAmount);

        depositAmount = 1e5;

        asset.mint(address(staker), depositAmount);
        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        // Withdraw small amount
        uint256 withdrawAmount = 1;

        vm.expectRevert("RDT:W:ZERO_SHARES");
        staker.rdToken_withdraw(address(rdToken), withdrawAmount);

        staker.rdToken_withdraw(address(rdToken), depositAmount);
    }

    function test_withdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount  = constrictToRange(depositAmount,  1, 1e29);
        withdrawAmount = constrictToRange(withdrawAmount, 1, depositAmount);

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        uint256 start = block.timestamp;

        assertEq(rdToken.balanceOf(address(staker)),             depositAmount);
        assertEq(rdToken.totalSupply(),                          depositAmount);
        assertEq(rdToken.freeAssets(),                           depositAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          start);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount);

        vm.warp(start + 10 days);

        staker.rdToken_withdraw(address(rdToken), withdrawAmount);

        assertEq(rdToken.balanceOf(address(staker)),             depositAmount - withdrawAmount);
        assertEq(rdToken.totalSupply(),                          depositAmount - withdrawAmount);
        assertEq(rdToken.freeAssets(),                           depositAmount - withdrawAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount - withdrawAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          start + 10 days);

        assertEq(asset.balanceOf(address(staker)),  withdrawAmount);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount - withdrawAmount);
    }

    function test_withdraw_totalAssetsGtTotalSupply_explicitVals() public {
        uint256 depositAmount  = 100e18;
        uint256 withdrawAmount = 20e18;
        uint256 vestingAmount  = 10e18;
        uint256 vestingPeriod  = 200 seconds;
        uint256 warpTime       = 100 seconds;
        uint256 start          = block.timestamp;

        _depositAsset(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        assertEq(rdToken.balanceOf(address(staker)),             100e18);
        assertEq(rdToken.totalSupply(),                          100e18);
        assertEq(rdToken.freeAssets(),                           100e18);
        assertEq(rdToken.totalAssets(),                          105e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.05e18);               // sampleSharesToConvert * 105e18 / 100e18
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 9.5238095238095238e17); // sampleAssetsToConvert * 100e18 / 105e18
        assertEq(rdToken.issuanceRate(),                         0.05e18 * 1e30);
        assertEq(rdToken.lastUpdated(),                          start);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), 110e18);

        staker.rdToken_withdraw(address(rdToken), withdrawAmount);

        assertEq(rdToken.balanceOf(address(staker)),             80.952380952380952380e18);
        assertEq(rdToken.totalSupply(),                          80.952380952380952380e18);
        assertEq(rdToken.freeAssets(),                           85e18);                     // totalAssets - 20 withdrawn
        assertEq(rdToken.totalAssets(),                          85e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.05e18);                   // sampleSharesToConvert * 85e18 / 80.952380952380952381e18
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 9.5238095238095238e17);     // sampleAssetsToConvert * 80.952380952380952381e18 / 85e18
        assertEq(rdToken.issuanceRate(),                         0.05e18 * 1e30);
        assertEq(rdToken.lastUpdated(),                          start + 100 seconds);

        assertEq(asset.balanceOf(address(staker)),  20e18);
        assertEq(asset.balanceOf(address(rdToken)), 90e18);
    }

    function test_withdraw_totalAssetsGtTotalSupply(
        uint256 depositAmount,
        uint256 withdrawAmount,
        uint256 vestingAmount,
        uint256 vestingPeriod,
        uint256 warpTime
    ) public {

        uint256 minAmount = 1e2;

        depositAmount  = constrictToRange(depositAmount,  minAmount, 1e29);
        withdrawAmount = constrictToRange(withdrawAmount, minAmount, depositAmount);
        vestingAmount  = constrictToRange(vestingAmount,  minAmount, depositAmount);
        vestingPeriod  = constrictToRange(vestingPeriod,  1, 100 days);
        warpTime       = constrictToRange(warpTime,       1, vestingPeriod);

        uint256 start = block.timestamp;

        _depositAsset(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        assertEq(rdToken.balanceOf(address(staker)), depositAmount);
        assertEq(rdToken.totalSupply(),              depositAmount);
        assertEq(rdToken.freeAssets(),               depositAmount);
        assertEq(rdToken.lastUpdated(),              start);

        uint256 totalAssets = depositAmount + vestingAmount * warpTime / vestingPeriod;

        assertWithinDiff(rdToken.totalAssets(),  totalAssets,                          1);
        assertWithinDiff(rdToken.issuanceRate(), vestingAmount * 1e30 / vestingPeriod, 1);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount + vestingAmount);  // Balance is higher than totalAssets

        uint256 expectedSharesBurned = rdToken.previewWithdraw(withdrawAmount);
        uint256 sharesBurned         = staker.rdToken_withdraw(address(rdToken), withdrawAmount);

        totalAssets -= withdrawAmount;

        assertEq(sharesBurned,                       expectedSharesBurned);
        assertEq(rdToken.balanceOf(address(staker)), depositAmount - sharesBurned);
        assertEq(rdToken.totalSupply(),              depositAmount - sharesBurned);
        assertEq(rdToken.lastUpdated(),              start + warpTime);

        // // if (rdToken.totalSupply() > 0) assertWithinPrecision(rdToken.exchangeRate(), exchangeRate1, 8);  // TODO: Add specialized testing for this

        assertWithinDiff(rdToken.issuanceRate(), vestingAmount * 1e30 / vestingPeriod, 1);
        assertWithinDiff(rdToken.freeAssets(),   totalAssets,                          1);
        assertWithinDiff(rdToken.totalAssets(),  totalAssets,                          1);

        assertEq(asset.balanceOf(address(staker)),  withdrawAmount);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount + vestingAmount - withdrawAmount);

    }

    function test_withdraw_callerNotOwner_badApproval() external {
        Staker shareOwner    = new Staker();
        Staker notShareOwner = new Staker();

        uint256 depositAmount = 1e18;
        asset.mint(address(shareOwner), depositAmount);

        shareOwner.erc20_approve(address(asset), address(rdToken), depositAmount);
        shareOwner.rdToken_deposit(address(rdToken), depositAmount);

        shareOwner.erc20_approve(address(rdToken), address(notShareOwner), depositAmount - 1);
        vm.expectRevert("RDT:CALLER_ALLOWANCE");
        notShareOwner.rdToken_withdraw(address(rdToken), depositAmount, address(shareOwner), address(shareOwner));

        shareOwner.erc20_approve(address(rdToken), address(notShareOwner), depositAmount);

        assertEq(rdToken.allowance(address(shareOwner), address(notShareOwner)), depositAmount);

        notShareOwner.rdToken_withdraw(address(rdToken), depositAmount, address(notShareOwner), address(shareOwner));

        assertEq(rdToken.allowance(address(shareOwner), address(notShareOwner)), 0);
    }

    function test_withdraw_callerNotOwner_infiniteApprovalForCaller() external {
        Staker shareOwner    = new Staker();
        Staker notShareOwner = new Staker();

        uint256 depositAmount = 1e18;
        asset.mint(address(shareOwner), depositAmount);

        shareOwner.erc20_approve(address(asset), address(rdToken), depositAmount);
        shareOwner.rdToken_deposit(address(rdToken), depositAmount);

        shareOwner.erc20_approve(address(rdToken), address(notShareOwner), type(uint256).max);

        assertEq(rdToken.allowance(address(shareOwner), address(notShareOwner)), type(uint256).max);

        notShareOwner.rdToken_withdraw(address(rdToken), depositAmount, address(notShareOwner), address(shareOwner));

        // Infinite approval stays infinite.
        assertEq(rdToken.allowance(address(shareOwner), address(notShareOwner)), type(uint256).max);
    }

    function test_withdraw_callerNotOwner(uint256 depositAmount, uint256 withdrawAmount, uint256 callerAllowance) public {
        depositAmount  = constrictToRange(depositAmount,  1, 1e29);
        withdrawAmount = constrictToRange(withdrawAmount, 1, depositAmount);

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        uint256 start = block.timestamp;

        assertEq(rdToken.balanceOf(address(staker)),             depositAmount);
        assertEq(rdToken.totalSupply(),                          depositAmount);
        assertEq(rdToken.freeAssets(),                           depositAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          start);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount);

        vm.warp(start + 10 days);

        Staker notShareOwner = new Staker();

        uint256 expectedSharesBurned = rdToken.convertToShares(withdrawAmount);
        callerAllowance              = constrictToRange(callerAllowance, expectedSharesBurned, type(uint256).max - 1);  // Allowance reduction doesn't happen with infinite approval.
        staker.erc20_approve(address(rdToken), address(notShareOwner), callerAllowance);

        assertEq(rdToken.allowance(address(staker), address(notShareOwner)), callerAllowance);

        // Withdraw assets to notShareOwner
        uint256 sharesBurned = notShareOwner.rdToken_withdraw(address(rdToken), withdrawAmount, address(notShareOwner), address(staker));

        assertEq(rdToken.allowance(address(staker), address(notShareOwner)), callerAllowance - sharesBurned);

        assertEq(rdToken.balanceOf(address(staker)),             depositAmount - withdrawAmount);
        assertEq(rdToken.totalSupply(),                          depositAmount - withdrawAmount);
        assertEq(rdToken.freeAssets(),                           depositAmount - withdrawAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount - withdrawAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          start + 10 days);

        assertEq(asset.balanceOf(address(staker)),        0);
        assertEq(asset.balanceOf(address(notShareOwner)), withdrawAmount);  // notShareOwner received the assets.
        assertEq(asset.balanceOf(address(rdToken)),       depositAmount - withdrawAmount);
    }

    function test_withdraw_callerNotOwner_totalAssetsGtTotalSupply_explicitVals() public {
        uint256 depositAmount  = 100e18;
        uint256 withdrawAmount = 20e18;
        uint256 vestingAmount  = 10e18;
        uint256 vestingPeriod  = 200 seconds;
        uint256 warpTime       = 100 seconds;
        uint256 start          = block.timestamp;

        _depositAsset(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        assertEq(rdToken.balanceOf(address(staker)),             100e18);
        assertEq(rdToken.totalSupply(),                          100e18);
        assertEq(rdToken.freeAssets(),                           100e18);
        assertEq(rdToken.totalAssets(),                          105e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.05e18);                // sampleSharesToConvert * 105e18 / 100e18
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 9.5238095238095238e17);  // sampleAssetsToConvert * 100e18 / 105e18
        assertEq(rdToken.issuanceRate(),                         0.05e18 * 1e30);
        assertEq(rdToken.lastUpdated(),                          start);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), 110e18);

        Staker notShareOwner = new Staker();

        uint256 expectedSharesBurned = rdToken.previewWithdraw(withdrawAmount);

        assertEq(expectedSharesBurned, 19.047619047619047620e18);

        staker.erc20_approve(address(rdToken), address(notShareOwner), expectedSharesBurned);

        assertEq(rdToken.allowance(address(staker), address(notShareOwner)), expectedSharesBurned);

        uint256 sharesBurned = notShareOwner.rdToken_withdraw(address(rdToken), withdrawAmount, address(notShareOwner), address(staker));

        assertEq(rdToken.allowance(address(staker), address(notShareOwner)), 0);

        assertEq(sharesBurned,                                   19.047619047619047620e18);
        assertEq(rdToken.balanceOf(address(staker)),             80.952380952380952380e18);
        assertEq(rdToken.totalSupply(),                          80.952380952380952380e18);
        assertEq(rdToken.freeAssets(),                           85e18);                     // totalAssets - 20 withdrawn
        assertEq(rdToken.totalAssets(),                          85e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.05e18);                   // sampleSharesToConvert * 85e18 / 80.952380952380952381e18
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 9.5238095238095238e17);     // sampleAssetsToConvert * 80.952380952380952381e18 / 85e18
        assertEq(rdToken.issuanceRate(),                         0.05e18 * 1e30);
        assertEq(rdToken.lastUpdated(),                          start + 100 seconds);

        assertEq(asset.balanceOf(address(staker)),        0);
        assertEq(asset.balanceOf(address(notShareOwner)), 20e18);  // notShareOwner received the assets.
        assertEq(asset.balanceOf(address(rdToken)),       90e18);
    }

    function test_withdraw_callerNotOwner_totalAssetsGtTotalSupply(
        uint256 depositAmount,
        uint256 withdrawAmount,
        uint256 vestingAmount,
        uint256 vestingPeriod,
        uint256 warpTime,
        uint256 callerAllowance
    ) public {
        uint256 minAmount = 1e2;

        depositAmount  = constrictToRange(depositAmount,  minAmount, 1e29);
        withdrawAmount = constrictToRange(withdrawAmount, minAmount, depositAmount);
        vestingAmount  = constrictToRange(vestingAmount,  minAmount, depositAmount);
        vestingPeriod  = constrictToRange(vestingPeriod,  1, 100 days);
        warpTime       = constrictToRange(warpTime,       1, vestingPeriod);

        uint256 start = block.timestamp;

        _depositAsset(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        assertEq(rdToken.balanceOf(address(staker)), depositAmount);
        assertEq(rdToken.totalSupply(),              depositAmount);
        assertEq(rdToken.freeAssets(),               depositAmount);
        assertEq(rdToken.lastUpdated(),              start);

        uint256 totalAssets = depositAmount + vestingAmount * warpTime / vestingPeriod;

        assertWithinDiff(rdToken.totalAssets(),  totalAssets,                          1);
        assertWithinDiff(rdToken.issuanceRate(), vestingAmount * 1e30 / vestingPeriod, 1);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount + vestingAmount);  // Balance is higher than totalAssets

        Staker notShareOwner = new Staker();

        uint256 expectedSharesBurned = rdToken.previewWithdraw(withdrawAmount);
        callerAllowance              = constrictToRange(callerAllowance, expectedSharesBurned, type(uint256).max - 1); // Allowance reduction doesn't happen with infinite approval.
        staker.erc20_approve(address(rdToken), address(notShareOwner), callerAllowance);

        assertEq(rdToken.allowance(address(staker), address(notShareOwner)), callerAllowance);

        uint256 sharesBurned = notShareOwner.rdToken_withdraw(address(rdToken), withdrawAmount, address(notShareOwner), address(staker));

        assertEq(rdToken.allowance(address(staker), address(notShareOwner)), callerAllowance - sharesBurned);

        totalAssets -= withdrawAmount;

        assertEq(sharesBurned,                       expectedSharesBurned);
        assertEq(rdToken.balanceOf(address(staker)), depositAmount - sharesBurned);
        assertEq(rdToken.totalSupply(),              depositAmount - sharesBurned);
        assertEq(rdToken.lastUpdated(),              start + warpTime);

        // // if (rdToken.totalSupply() > 0) assertWithinPrecision(rdToken.exchangeRate(), exchangeRate1, 8);  // TODO: Add specialized testing for this

        assertWithinDiff(rdToken.issuanceRate(), vestingAmount * 1e30 / vestingPeriod, 1);
        assertWithinDiff(rdToken.freeAssets(),   totalAssets,                          1);
        assertWithinDiff(rdToken.totalAssets(),  totalAssets,                          1);

        assertEq(asset.balanceOf(address(staker)),        0);
        assertEq(asset.balanceOf(address(notShareOwner)), withdrawAmount);  // notShareOwner received the assets.
        assertEq(asset.balanceOf(address(rdToken)),       depositAmount + vestingAmount - withdrawAmount);

    }

    // TODO: Implement once max* functions are added as per 4626 standard
    // function test_withdraw_burnUnderflow_totalAssetsGtTotalSupply(uint256 depositAmount, uint256 vestingAmount, uint256 vestingPeriod, uint256 warpTime) external {
    //     depositAmount = constrictToRange(depositAmount, 1, 1e29);
    //     vestingAmount = constrictToRange(vestingAmount, 1, 1e29);
    //     vestingPeriod = constrictToRange(vestingPeriod, 1, 100 days);
    //     warpTime      = constrictToRange(vestingAmount, 1, vestingPeriod);

    //     _depositAsset(depositAmount);
    //     _transferAndUpdateVesting(vestingAmount, vestingPeriod);

    //     vm.warp(block.timestamp + warpTime);

    //     uint256 underflowWithdrawAmount = rdToken.previewRedeem(rdToken.balanceOf(address(staker)) + 1);  // TODO
    //     uint256 maxWithdrawAmount       = rdToken.previewRedeem(rdToken.balanceOf(address(staker)));  // TODO

    //     vm.expectRevert(ARITHMETIC_ERROR);
    //     staker.rdToken_withdraw(address(rdToken), underflowWithdrawAmount);

    //     staker.rdToken_withdraw(address(rdToken), maxWithdrawAmount);
    // }


    /************************/
    /*** `redeem` tests ***/
    /************************/

    function test_redeem_zeroAmount(uint256 depositAmount) external {
        _depositAsset(constrictToRange(depositAmount, 1, 1e29));

        vm.expectRevert("RDT:R:ZERO_SHARES");
        staker.rdToken_redeem(address(rdToken), 0);

        staker.rdToken_redeem(address(rdToken), 1);
    }

    function test_redeem_burnUnderflow(uint256 depositAmount) external {
        depositAmount = constrictToRange(depositAmount, 1, 1e29);
        _depositAsset(depositAmount);

        vm.expectRevert(ARITHMETIC_ERROR);
        staker.rdToken_redeem(address(rdToken), depositAmount + 1);

        staker.rdToken_redeem(address(rdToken), depositAmount);
    }

    function test_redeem_burnUnderflow_totalAssetsGtTotalSupply_explicitVals() external {
        uint256 depositAmount = 100e18;
        uint256 vestingAmount = 10e18;
        uint256 vestingPeriod = 10 days;
        uint256 warpTime      = 5 days;

        _depositAsset(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        vm.expectRevert(ARITHMETIC_ERROR);
        staker.rdToken_redeem(address(rdToken), 100e18 + 1);

        staker.rdToken_redeem(address(rdToken), 100e18);
    }

    function test_redeem(uint256 depositAmount, uint256 redeemAmount) public {
        depositAmount = constrictToRange(depositAmount, 1, 1e29);
        redeemAmount  = constrictToRange(redeemAmount,  1, depositAmount);

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        uint256 start = block.timestamp;

        assertEq(rdToken.balanceOf(address(staker)),             depositAmount);
        assertEq(rdToken.totalSupply(),                          depositAmount);
        assertEq(rdToken.freeAssets(),                           depositAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          start);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount);

        vm.warp(start + 10 days);

        staker.rdToken_redeem(address(rdToken), redeemAmount);

        assertEq(rdToken.balanceOf(address(staker)),             depositAmount - redeemAmount);
        assertEq(rdToken.totalSupply(),                          depositAmount - redeemAmount);
        assertEq(rdToken.freeAssets(),                           depositAmount - redeemAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount - redeemAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          start + 10 days);

        assertEq(asset.balanceOf(address(staker)),  redeemAmount);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount - redeemAmount);
    }

    function test_redeem_totalAssetsGtTotalSupply_explicitVals() public {
        uint256 depositAmount = 100e18;
        uint256 redeemAmount  = 20e18;
        uint256 vestingAmount = 10e18;
        uint256 vestingPeriod = 200 seconds;
        uint256 warpTime      = 100 seconds;
        uint256 start         = block.timestamp;

        _depositAsset(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        assertEq(rdToken.balanceOf(address(staker)),             100e18);
        assertEq(rdToken.totalSupply(),                          100e18);
        assertEq(rdToken.freeAssets(),                           100e18);
        assertEq(rdToken.totalAssets(),                          105e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.05e18);               // sampleSharesToConvert * 105e18 / 100e18
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 9.5238095238095238e17); // sampleAssetsToConvert * 100e18 / 105e18
        assertEq(rdToken.issuanceRate(),                         0.05e18 * 1e30);
        assertEq(rdToken.lastUpdated(),                          start);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), 110e18);

        staker.rdToken_redeem(address(rdToken), redeemAmount);

        assertEq(rdToken.balanceOf(address(staker)),             80e18);
        assertEq(rdToken.totalSupply(),                          80e18);
        assertEq(rdToken.freeAssets(),                           84e18);                 // 105 * 0.8
        assertEq(rdToken.totalAssets(),                          84e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.05e18);               // sampleSharesToConvert * 84e18 / 80e18
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 9.5238095238095238e17); // sampleAssetsToConvert * 80e18 / 84e18
        assertEq(rdToken.issuanceRate(),                         0.05e18 * 1e30);
        assertEq(rdToken.lastUpdated(),                          start + 100 seconds);

        assertEq(asset.balanceOf(address(staker)),  21e18);
        assertEq(asset.balanceOf(address(rdToken)), 89e18);
    }

    function test_redeem_totalAssetsGtTotalSupply(
        uint256 depositAmount,
        uint256 redeemAmount,
        uint256 vestingAmount,
        uint256 vestingPeriod,
        uint256 warpTime
    ) public {
        depositAmount = constrictToRange(depositAmount, 1, 1e29);
        redeemAmount  = constrictToRange(redeemAmount,  1, depositAmount);
        vestingAmount = constrictToRange(vestingAmount, 1, 1e29);
        vestingPeriod = constrictToRange(vestingPeriod, 1, 100 days);
        warpTime      = constrictToRange(warpTime,      1, vestingPeriod);

        uint256 start = block.timestamp;

        _depositAsset(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        assertEq(rdToken.balanceOf(address(staker)), depositAmount);
        assertEq(rdToken.totalSupply(),              depositAmount);
        assertEq(rdToken.freeAssets(),               depositAmount);
        assertEq(rdToken.lastUpdated(),              start);

        uint256 totalAssets  = depositAmount + vestingAmount * warpTime / vestingPeriod;
        uint256 amountVested = vestingAmount * 1e30 * warpTime / vestingPeriod / 1e30;

        assertWithinDiff(rdToken.totalAssets(),  totalAssets,                          1);
        assertWithinDiff(rdToken.issuanceRate(), vestingAmount * 1e30 / vestingPeriod, 1);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount + vestingAmount);  // Balance is higher than totalAssets

        uint256 expectedAssetsFromRedeem = rdToken.convertToAssets(redeemAmount);
        uint256 assetsFromRedeem         = staker.rdToken_redeem(address(rdToken), redeemAmount);

        assertEq(assetsFromRedeem,                   expectedAssetsFromRedeem);
        assertEq(rdToken.balanceOf(address(staker)), depositAmount - redeemAmount);
        assertEq(rdToken.totalSupply(),              depositAmount - redeemAmount);
        assertEq(rdToken.lastUpdated(),              start + warpTime);

        // if (rdToken.totalSupply() > 0) assertWithinPrecision(rdToken.exchangeRate(), exchangeRate1, 8);  // TODO: Add specialized testing for this

        assertWithinDiff(rdToken.issuanceRate(), vestingAmount * 1e30 / vestingPeriod, 1);
        assertWithinDiff(rdToken.freeAssets(),           depositAmount + amountVested - expectedAssetsFromRedeem, 1);
        assertWithinDiff(rdToken.totalAssets(),          depositAmount + amountVested - expectedAssetsFromRedeem, 1);

        assertEq(asset.balanceOf(address(staker)),  expectedAssetsFromRedeem);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount + vestingAmount - expectedAssetsFromRedeem);  // Note that vestingAmount is used
    }

    function test_redeem_callerNotOwner_badApproval() external {
        Staker shareOwner    = new Staker();
        Staker notShareOwner = new Staker();

        uint256 depositAmount = 1e18;
        asset.mint(address(shareOwner), depositAmount);

        shareOwner.erc20_approve(address(asset), address(rdToken), depositAmount);
        shareOwner.rdToken_deposit(address(rdToken), depositAmount);

        shareOwner.erc20_approve(address(rdToken), address(notShareOwner), depositAmount - 1);
        vm.expectRevert("RDT:CALLER_ALLOWANCE");
        notShareOwner.rdToken_redeem(address(rdToken), depositAmount, address(shareOwner), address(shareOwner));

        shareOwner.erc20_approve(address(rdToken), address(notShareOwner), depositAmount);

        assertEq(rdToken.allowance(address(shareOwner), address(notShareOwner)), depositAmount);

        notShareOwner.rdToken_redeem(address(rdToken), depositAmount, address(notShareOwner), address(shareOwner));

        assertEq(rdToken.allowance(address(shareOwner), address(notShareOwner)), 0);
    }

    function test_redeem_callerNotOwner_infiniteApprovalForCaller() external {
        Staker shareOwner    = new Staker();
        Staker notShareOwner = new Staker();

        uint256 depositAmount = 1e18;
        asset.mint(address(shareOwner), depositAmount);

        shareOwner.erc20_approve(address(asset), address(rdToken), depositAmount);
        shareOwner.rdToken_deposit(address(rdToken), depositAmount);

        shareOwner.erc20_approve(address(rdToken), address(notShareOwner), type(uint256).max);

        assertEq(rdToken.allowance(address(shareOwner), address(notShareOwner)), type(uint256).max);

        notShareOwner.rdToken_redeem(address(rdToken), depositAmount, address(notShareOwner), address(shareOwner));

        // Infinite approval stays infinite.
        assertEq(rdToken.allowance(address(shareOwner), address(notShareOwner)), type(uint256).max);
    }

    function test_redeem_callerNotOwner(uint256 depositAmount, uint256 redeemAmount, uint256 callerAllowance) external {
        depositAmount   = constrictToRange(depositAmount, 1, 1e29);
        redeemAmount    = constrictToRange(redeemAmount,  1, depositAmount);
        callerAllowance = constrictToRange(callerAllowance,  redeemAmount, type(uint256).max - 1); // Allowance reduction doesn't happen with infinite approval.

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        uint256 start = block.timestamp;

        assertEq(rdToken.balanceOf(address(staker)),             depositAmount);
        assertEq(rdToken.totalSupply(),                          depositAmount);
        assertEq(rdToken.freeAssets(),                           depositAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          start);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount);

        vm.warp(start + 10 days);

        uint256 expectedAssetsFromRedeem = rdToken.convertToAssets(redeemAmount);

        Staker notShareOwner = new Staker();
        staker.erc20_approve(address(rdToken), address(notShareOwner), callerAllowance);

        assertEq(rdToken.allowance(address(staker), address(notShareOwner)), callerAllowance);

        uint256 assetsFromRedeem = notShareOwner.rdToken_redeem(address(rdToken), redeemAmount, address(notShareOwner), address(staker));

        assertEq(rdToken.allowance(address(staker), address(notShareOwner)), callerAllowance - redeemAmount);

        assertEq(assetsFromRedeem,                               expectedAssetsFromRedeem);
        assertEq(rdToken.balanceOf(address(staker)),             depositAmount - redeemAmount);
        assertEq(rdToken.totalSupply(),                          depositAmount - redeemAmount);
        assertEq(rdToken.freeAssets(),                           depositAmount - redeemAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount - redeemAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          start + 10 days);

        assertEq(asset.balanceOf(address(staker)),        0);
        assertEq(asset.balanceOf(address(notShareOwner)), redeemAmount);  // notShareOwner received the assets.
        assertEq(asset.balanceOf(address(rdToken)),       depositAmount - redeemAmount);
    }

    function test_redeem_callerNotOwner_totalAssetsGtTotalSupply_explicitVals() external {
        uint256 depositAmount = 100e18;
        uint256 redeemAmount  = 20e18;
        uint256 vestingAmount = 10e18;
        uint256 vestingPeriod = 200 seconds;
        uint256 warpTime      = 100 seconds;
        uint256 start         = block.timestamp;

        _depositAsset(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        assertEq(rdToken.balanceOf(address(staker)),             100e18);
        assertEq(rdToken.totalSupply(),                          100e18);
        assertEq(rdToken.freeAssets(),                           100e18);
        assertEq(rdToken.totalAssets(),                          105e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.05e18);               // sampleSharesToConvert * 105e18 / 100e18
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 9.5238095238095238e17); // sampleAssetsToConvert * 100e18 / 105e18
        assertEq(rdToken.issuanceRate(),                         0.05e18 * 1e30);
        assertEq(rdToken.lastUpdated(),                          start);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), 110e18);

        Staker notShareOwner = new Staker();
        staker.erc20_approve(address(rdToken), address(notShareOwner), redeemAmount);

        assertEq(rdToken.allowance(address(staker), address(notShareOwner)), 20e18);

        uint256 assetsFromRedeem = notShareOwner.rdToken_redeem(address(rdToken), redeemAmount, address(notShareOwner), address(staker));

        assertEq(rdToken.allowance(address(staker), address(notShareOwner)), 0);

        assertEq(assetsFromRedeem,                               21e18);
        assertEq(rdToken.balanceOf(address(staker)),             80e18);
        assertEq(rdToken.totalSupply(),                          80e18);
        assertEq(rdToken.freeAssets(),                           84e18);                 // 105 * 0.8
        assertEq(rdToken.totalAssets(),                          84e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.05e18);               // sampleSharesToConvert * 84e18 / 80e18
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 9.5238095238095238e17); // sampleAssetsToConvert * 80e18 / 84e18
        assertEq(rdToken.issuanceRate(),                         0.05e18 * 1e30);
        assertEq(rdToken.lastUpdated(),                          start + 100 seconds);

        assertEq(asset.balanceOf(address(staker)),        0);
        assertEq(asset.balanceOf(address(notShareOwner)), 21e18);  // notShareOwner received the assets.
        assertEq(asset.balanceOf(address(rdToken)),       89e18);
    }

    function test_redeem_callerNotOwner_totalAssetsGtTotalSupply(
        uint256 depositAmount,
        uint256 redeemAmount,
        uint256 vestingAmount,
        uint256 vestingPeriod,
        uint256 warpTime,
        uint256 callerAllowance
    ) external {
        depositAmount   = constrictToRange(depositAmount, 1, 1e29);
        redeemAmount    = constrictToRange(redeemAmount,  1, depositAmount);
        vestingAmount   = constrictToRange(vestingAmount, 1, 1e29);
        vestingPeriod   = constrictToRange(vestingPeriod, 1, 100 days);
        warpTime        = constrictToRange(warpTime,      1, vestingPeriod);
        callerAllowance = constrictToRange(callerAllowance, redeemAmount, type(uint256).max - 1); // Allowance reduction doesn't happen with infinite approval.

        uint256 start = block.timestamp;

        _depositAsset(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        assertEq(rdToken.balanceOf(address(staker)), depositAmount);
        assertEq(rdToken.totalSupply(),              depositAmount);
        assertEq(rdToken.freeAssets(),               depositAmount);
        assertEq(rdToken.lastUpdated(),              start);

        uint256 totalAssets  = depositAmount + vestingAmount * warpTime / vestingPeriod;
        uint256 amountVested = vestingAmount * 1e30 * warpTime / vestingPeriod / 1e30;

        assertWithinDiff(rdToken.totalAssets(),  totalAssets,                          1);
        assertWithinDiff(rdToken.issuanceRate(), vestingAmount * 1e30 / vestingPeriod, 1);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount + vestingAmount);  // Balance is higher than totalAssets

        uint256 expectedAssetsFromRedeem = rdToken.convertToAssets(redeemAmount);

        Staker notShareOwner = new Staker();
        staker.erc20_approve(address(rdToken), address(notShareOwner), callerAllowance);

        assertEq(rdToken.allowance(address(staker), address(notShareOwner)), callerAllowance);

        uint256 assetsFromRedeem = notShareOwner.rdToken_redeem(address(rdToken), redeemAmount, address(notShareOwner), address(staker));

        assertEq(rdToken.allowance(address(staker), address(notShareOwner)), callerAllowance - redeemAmount);

        assertEq(assetsFromRedeem,                   expectedAssetsFromRedeem);
        assertEq(rdToken.balanceOf(address(staker)), depositAmount - redeemAmount);
        assertEq(rdToken.totalSupply(),              depositAmount - redeemAmount);
        assertEq(rdToken.lastUpdated(),              start + warpTime);

        // if (rdToken.totalSupply() > 0) assertWithinPrecision(rdToken.exchangeRate(), exchangeRate1, 8);  // TODO: Add specialized testing for this

        assertWithinDiff(rdToken.issuanceRate(), vestingAmount * 1e30 / vestingPeriod, 1);
        assertWithinDiff(rdToken.freeAssets(),           depositAmount + amountVested - expectedAssetsFromRedeem, 1);
        assertWithinDiff(rdToken.totalAssets(),          depositAmount + amountVested - expectedAssetsFromRedeem, 1);

        assertEq(asset.balanceOf(address(staker)),        0);
        assertEq(asset.balanceOf(address(notShareOwner)), expectedAssetsFromRedeem);  // notShareOwner received the assets.
        assertEq(asset.balanceOf(address(rdToken)),       depositAmount + vestingAmount - expectedAssetsFromRedeem);  // Note that vestingAmount is used
    }

    function _depositAsset(uint256 depositAmount) internal {
        asset.mint(address(staker), depositAmount);
        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);
    }

    function _transferAndUpdateVesting(uint256 vestingAmount_, uint256 vestingPeriod_) internal {
        asset.mint(address(this), vestingAmount_);
        asset.transfer(address(rdToken), vestingAmount_);
        rdToken.updateVestingSchedule(vestingPeriod_);
    }

}

contract RevenueStreamingTest is TestUtils {

    MockERC20 asset;
    RDT       rdToken;

    uint256 constant sampleAssetsToConvert = 1e18;
    uint256 constant sampleSharesToConvert = 1e18;

    bytes constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

    uint256 start;

    function setUp() public virtual {
        // Use non-zero timestamp
        start = 10_000;
        vm.warp(start);

        asset   = new MockERC20("MockToken", "MT", 18);
        rdToken = new RDT("Revenue Distribution Token", "RDT", address(this), address(asset), 1e30);
    }

    /************************************/
    /*** Single updateVestingSchedule ***/
    /************************************/

    function test_updateVestingSchedule_single() external {
        assertEq(rdToken.freeAssets(),          0);
        assertEq(rdToken.totalAssets(),         0);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         0);
        assertEq(rdToken.vestingPeriodFinish(), 0);

        assertEq(asset.balanceOf(address(rdToken)), 0);

        _transferAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        assertEq(asset.balanceOf(address(rdToken)), 1000);

        assertEq(rdToken.freeAssets(),                           0);
        assertEq(rdToken.totalAssets(),                          0);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         10e30);  // 10 tokens per second
        assertEq(rdToken.lastUpdated(),                          start);
        assertEq(rdToken.vestingPeriodFinish(),                  start + 100 seconds);

        vm.warp(rdToken.vestingPeriodFinish());

        assertEq(rdToken.totalAssets(), 1000);  // All tokens vested
    }

    function test_updateVestingSchedule_single_roundingDown() external {
        _transferAndUpdateVesting(1000, 30 seconds);  // 33.3333... tokens per second

        assertEq(rdToken.totalAssets(),  0);
        assertEq(rdToken.issuanceRate(), 33333333333333333333333333333333);  // 3.33e30

        // totalAssets should never be more than one full unit off
        vm.warp(start + 1 seconds);
        assertEq(rdToken.totalAssets(), 33);  // 33 < 33.33...

        vm.warp(start + 2 seconds);
        assertEq(rdToken.totalAssets(), 66);  // 66 < 66.66...

        vm.warp(start + 3 seconds);
        assertEq(rdToken.totalAssets(), 99);  // 99 < 99.99...

        vm.warp(start + 4 seconds);
        assertEq(rdToken.totalAssets(), 133);  // 133 < 133.33...

        vm.warp(rdToken.vestingPeriodFinish());
        assertEq(rdToken.totalAssets(), 999);  // 999 < 1000
    }

    /*************************************************/
    /*** Multiple updateVestingSchedule, same time ***/
    /*************************************************/

    function test_updateVestingSchedule_sameTime_shorterVesting() external {
        _transferAndUpdateVesting(1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);  // Always updates to latest vesting schedule

        _transferAndUpdateVesting(1000, 20 seconds);
        assertEq(rdToken.issuanceRate(),        100e30);              // (1000 + 1000) / 20 seconds = 100 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 20 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalAssets(), 0);

        vm.warp(start + 20 seconds);

        assertEq(rdToken.totalAssets(), 2000);
    }

    function test_updateVestingSchedule_sameTime_longerVesting_higherRate() external {
        _transferAndUpdateVesting(1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);  // Always updates to latest vesting schedule

        _transferAndUpdateVesting(3000, 200 seconds);
        assertEq(rdToken.issuanceRate(),        20e30);                // (3000 + 1000) / 200 seconds = 20 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 200 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalAssets(), 0);

        vm.warp(start + 200 seconds);

        assertEq(rdToken.totalAssets(), 4000);
    }

    function test_updateVestingSchedule_sameTime_longerVesting_lowerRate() external {
        _transferAndUpdateVesting(1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);  // Always updates to latest vesting schedule

        _transferAndUpdateVesting(1000, 500 seconds);
        assertEq(rdToken.issuanceRate(),        4e30);                 // (1000 + 1000) / 500 seconds = 4 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 500 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalAssets(), 0);

        vm.warp(start + 5000 seconds);

        assertEq(rdToken.totalAssets(), 2000);
    }

    /*******************************************************/
    /*** Multiple updateVestingSchedule, different times ***/
    /*******************************************************/

    function test_updateVestingSchedule_diffTime_shorterVesting() external {
        _transferAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        vm.warp(start + 60 seconds);

        assertEq(rdToken.issuanceRate(),        10e30);
        assertEq(rdToken.totalAssets(),         600);
        assertEq(rdToken.freeAssets(),          0);
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);

        _transferAndUpdateVesting(1000, 20 seconds);  // 50 tokens per second

        assertEq(rdToken.issuanceRate(),        70e30);  // (400 + 1000) / 20 seconds = 70 tokens per second
        assertEq(rdToken.totalAssets(),         600);
        assertEq(rdToken.freeAssets(),          600);
        assertEq(rdToken.vestingPeriodFinish(), start + 60 seconds + 20 seconds);

        vm.warp(start + 60 seconds + 20 seconds);

        assertEq(rdToken.issuanceRate(), 70e30);
        assertEq(rdToken.totalAssets(),  2000);
        assertEq(rdToken.freeAssets(),   600);
    }

    function test_updateVestingSchedule_diffTime_longerVesting_higherRate() external {
        _transferAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        vm.warp(start + 60 seconds);

        assertEq(rdToken.issuanceRate(),        10e30);
        assertEq(rdToken.totalAssets(),         600);
        assertEq(rdToken.freeAssets(),          0);
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);

        _transferAndUpdateVesting(3000, 200 seconds);  // 15 tokens per second

        assertEq(rdToken.issuanceRate(), 17e30);  // (400 + 3000) / 200 seconds = 17 tokens per second
        assertEq(rdToken.totalAssets(),  600);
        assertEq(rdToken.freeAssets(),   600);

        vm.warp(start + 60 seconds + 200 seconds);

        assertEq(rdToken.issuanceRate(), 17e30);
        assertEq(rdToken.totalAssets(),  4000);
        assertEq(rdToken.freeAssets(),   600);
    }

    function test_updateVestingSchedule_diffTime_longerVesting_lowerRate() external {
        _transferAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        vm.warp(start + 60 seconds);

        assertEq(rdToken.issuanceRate(), 10e30);
        assertEq(rdToken.totalAssets(),  600);
        assertEq(rdToken.freeAssets(),   0);

        _transferAndUpdateVesting(1000, 200 seconds);  // 5 tokens per second

        assertEq(rdToken.issuanceRate(), 7e30);  // (400 + 1000) / 200 seconds = 7 tokens per second
        assertEq(rdToken.totalAssets(),  600);
        assertEq(rdToken.freeAssets(),   600);

        vm.warp(start + 60 seconds + 200 seconds);

        assertEq(rdToken.issuanceRate(), 7e30);
        assertEq(rdToken.totalAssets(),  2000);
        assertEq(rdToken.freeAssets(),   600);
    }

    /********************************/
    /*** End to end vesting tests ***/
    /********************************/

    function test_vesting_singleSchedule_explicit_vals() public {
        uint256 depositAmount = 1_000_000e18;
        uint256 vestingAmount = 100_000e18;
        uint256 vestingPeriod = 200_000 seconds;

        Staker staker = new Staker();

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        assertEq(rdToken.freeAssets(),                           1_000_000e18);
        assertEq(rdToken.totalAssets(),                          1_000_000e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          start);
        assertEq(rdToken.vestingPeriodFinish(),                  0);

        vm.warp(start + 1 days);

        assertEq(rdToken.totalAssets(),  1_000_000e18);  // No change

        vm.warp(start);  // Warp back after demonstrating totalAssets is not time-dependent before vesting starts

        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        assertEq(rdToken.freeAssets(),                           1_000_000e18);
        assertEq(rdToken.totalAssets(),                          1_000_000e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0.5e18 * 1e30);  // 0.5 tokens per second
        assertEq(rdToken.lastUpdated(),                          start);
        assertEq(rdToken.vestingPeriodFinish(),                  start + vestingPeriod);

        // Warp and assert vesting in 10% increments
        vm.warp(start + 20_000 seconds);  // 10% of vesting schedule

        assertEq(rdToken.balanceOfAssets(address(staker)),       1_010_000e18);
        assertEq(rdToken.totalAssets(),                          1_010_000e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.01e18);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 9.90099009900990099e17); // Shares go down, as they are worth more assets.

        vm.warp(start + 40_000 seconds);  // 20% of vesting schedule

        assertEq(rdToken.balanceOfAssets(address(staker)),       1_020_000e18);
        assertEq(rdToken.totalAssets(),                          1_020_000e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.02e18);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 9.80392156862745098e17);

        vm.warp(start + 60_000 seconds);  // 30% of vesting schedule

        assertEq(rdToken.balanceOfAssets(address(staker)),       1_030_000e18);
        assertEq(rdToken.totalAssets(),                          1_030_000e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.03e18);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 9.70873786407766990e17);

        vm.warp(start + 200_000 seconds);  // End of vesting schedule

        assertEq(rdToken.balanceOfAssets(address(staker)),       1_100_000e18);
        assertEq(rdToken.totalAssets(),                          1_100_000e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.1e18);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 9.09090909090909090e17);

        assertEq(asset.balanceOf(address(rdToken)), 1_100_000e18);
        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(rdToken.balanceOf(address(staker)),     1_000_000e18);

        staker.rdToken_redeem(address(rdToken), 1_000_000e18);  // Use `redeem` so rdToken amount can be used to burn 100% of tokens

        assertEq(rdToken.freeAssets(),                           0);
        assertEq(rdToken.totalAssets(),                          0);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);    // returns to sampleAssetsToConvert when empty
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);    // returns to sampleAssetsToConvert when empty
        assertEq(rdToken.issuanceRate(),                         0.5e18 * 1e30);            // TODO: Investigate implications of non-zero issuanceRate here
        assertEq(rdToken.lastUpdated(),                          start + 200_000 seconds);  // This makes issuanceRate * time zero
        assertEq(rdToken.vestingPeriodFinish(),                  start + 200_000 seconds);

        assertEq(asset.balanceOf(address(rdToken)),   0);
        assertEq(rdToken.balanceOfAssets(address(staker)), 0);

        assertEq(asset.balanceOf(address(staker)), 1_100_000e18);
        assertEq(rdToken.balanceOf(address(staker)),    0);
    }

    function test_vesting_singleSchedule_fuzz(uint256 depositAmount, uint256 vestingAmount, uint256 vestingPeriod) public {
        depositAmount = constrictToRange(depositAmount, 1e6,        1e30);                    // 1 billion at WAD precision
        vestingAmount = constrictToRange(vestingAmount, 1e6,        1e30);                    // 1 billion at WAD precision
        vestingPeriod = constrictToRange(vestingPeriod, 10 seconds, 100_000 days) / 10 * 10;  // Must be divisible by 10 for for loop 10% increment calculations // TODO: Add a zero case test

        Staker staker = new Staker();

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        assertEq(rdToken.freeAssets(),                           depositAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          start);
        assertEq(rdToken.vestingPeriodFinish(),                  0);

        vm.warp(start + 1 days);

        assertEq(rdToken.totalAssets(),  depositAmount);  // No change

        vm.warp(start);  // Warp back after demonstrating totalAssets is not time-dependent before vesting starts

        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        uint256 expectedRate = vestingAmount * 1e30 / vestingPeriod;

        assertEq(rdToken.freeAssets(),                           depositAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         expectedRate);
        assertEq(rdToken.lastUpdated(),                          start);
        assertEq(rdToken.vestingPeriodFinish(),                  start + vestingPeriod);

        // Warp and assert vesting in 10% increments
        for (uint256 i = 1; i < 10; ++i) {
            vm.warp(start + vestingPeriod * i / 10);  // 10% intervals of vesting schedule

            uint256 expectedtotalAssets = depositAmount + expectedRate * (block.timestamp - start) / 1e30;

            assertWithinDiff(rdToken.balanceOfAssets(address(staker)), expectedtotalAssets, 1);

            assertEq(rdToken.totalSupply(),                          depositAmount);
            assertEq(rdToken.totalAssets(),                          expectedtotalAssets);
            assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert * expectedtotalAssets / depositAmount);
            assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert * depositAmount / expectedtotalAssets);
        }

        vm.warp(start + vestingPeriod);

        uint256 expectedFinalTotal = depositAmount + vestingAmount;

        // TODO: Try assertEq
        assertWithinDiff(rdToken.balanceOfAssets(address(staker)), expectedFinalTotal, 2);

        assertWithinDiff(rdToken.totalAssets(), expectedFinalTotal, 1);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert),    sampleSharesToConvert * rdToken.totalAssets() / depositAmount); // Using totalAssets because of rounding
        assertEq(rdToken.convertToShares(sampleAssetsToConvert),    sampleAssetsToConvert * depositAmount / rdToken.totalAssets());

        assertEq(asset.balanceOf(address(rdToken)), depositAmount + vestingAmount);

        assertEq(asset.balanceOf(address(staker)), 0);
        assertEq(rdToken.balanceOf(address(staker)),    depositAmount);

        staker.rdToken_redeem(address(rdToken), depositAmount);  // Use `redeem` so rdToken amount can be used to burn 100% of tokens

        assertWithinDiff(rdToken.freeAssets(),  0, 1);
        assertWithinDiff(rdToken.totalAssets(), 0, 1);

        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);  // Returns to sampleSharesToConvert zero when empty.
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);  // Returns to sampleAssetsToConvert zero when empty.
        assertEq(rdToken.issuanceRate(),                         expectedRate);           // TODO: Investigate implications of non-zero issuanceRate here
        assertEq(rdToken.lastUpdated(),                          start + vestingPeriod);  // This makes issuanceRate * time zero
        assertEq(rdToken.vestingPeriodFinish(),                  start + vestingPeriod);

        assertWithinDiff(asset.balanceOf(address(rdToken)), 0, 2);

        assertEq(rdToken.balanceOfAssets(address(staker)), 0);

        assertWithinDiff(asset.balanceOf(address(staker)),   depositAmount + vestingAmount, 2);
        assertWithinDiff(rdToken.balanceOf(address(staker)), 0,                             1);
    }

    function _transferAndUpdateVesting(uint256 vestingAmount_, uint256 vestingPeriod_) internal {
        asset.mint(address(this), vestingAmount_);
        asset.transfer(address(rdToken), vestingAmount_);
        rdToken.updateVestingSchedule(vestingPeriod_);
    }

}

contract RedeemRevertOnTransfer is TestUtils {

    MockRevertingERC20 asset;
    RDT                rdToken;
    Staker             staker;

    uint256 constant sampleAssetsToConvert = 1e18;
    uint256 constant sampleSharesToConvert = 1e18;

    bytes constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

    function setUp() public virtual {
        asset   = new MockRevertingERC20("MockToken", "MT", 18);
        rdToken = new RDT("Revenue Distribution Token", "RDT", address(this), address(asset), 1e30);
        staker  = new Staker();

        vm.warp(10_000_000);  // Warp to non-zero timestamp
    }

    function test_redeem_revertOnTransfer(uint256 depositAmount, uint256 redeemAmount) public {
        depositAmount = constrictToRange(depositAmount, 1, 1e29);
        redeemAmount  = constrictToRange(redeemAmount,  1, depositAmount);

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        uint256 start = block.timestamp;

        vm.warp(start + 10 days);

        vm.expectRevert(bytes("RDT:R:TRANSFER"));
        staker.rdToken_redeem(address(rdToken), depositAmount, address(0), address(staker));

        staker.rdToken_redeem(address(rdToken), depositAmount, address(1), address(staker));
    }

    function test_withdraw_revertOnTransfer(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount  = constrictToRange(depositAmount,  1, 1e29);
        withdrawAmount = constrictToRange(withdrawAmount, 1, depositAmount);

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        uint256 start = block.timestamp;

        vm.warp(start + 10 days);

        vm.expectRevert(bytes("RDT:W:TRANSFER"));
        staker.rdToken_withdraw(address(rdToken), withdrawAmount, address(0), address(staker));

        staker.rdToken_withdraw(address(rdToken), withdrawAmount, address(1), address(staker));
    }

    function _depositAsset(uint256 depositAmount) internal {
        asset.mint(address(staker), depositAmount);
        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);
    }
}
