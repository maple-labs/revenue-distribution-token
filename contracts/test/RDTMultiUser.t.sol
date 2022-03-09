// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

// This file duplicates the tests on RevenueDistributionToken.t.sol, but they're all executed in the context of an ongoing campaign, with already deposited users.

import { TestUtils }                  from "../../modules/contract-test-utils/contracts/test.sol";
import { MockERC20, MockERC20Permit } from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { MockRevertingERC20 } from "./mocks/MockRevertingERC20.sol";
import { MockRDT }            from "./mocks/MockRDT.sol";

import { Owner }  from "./accounts/Owner.sol";
import { Staker } from "./accounts/Staker.sol";

import { RevenueDistributionToken as RDT } from "../RevenueDistributionToken.sol";

contract DepositAndMintWithPermitTestWithMultipleUsers is TestUtils {

    MockERC20Permit asset;
    MockRDT         rdToken;

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
        rdToken = new MockRDT("Revenue Distribution Token", "MockRDT", address(this), address(asset), 1e30);

        staker    = vm.addr(stakerPrivateKey);
        notStaker = vm.addr(notStakerPrivateKey);

        vm.warp(10_000_000);  // Warp to non-zero timestamp
    }

    function test_multi_depositWithPermit_zeroAddress(uint256 entropy) external {
        _createOngoingCampaign(entropy);
        uint256 depositAmount = 1e18;
        asset.mint(address(staker), depositAmount);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(depositAmount, staker, address(rdToken), stakerPrivateKey, deadline);

        vm.startPrank(staker);

        vm.expectRevert(bytes("ERC20Permit:INVALID_SIGNATURE"));
        rdToken.depositWithPermit(depositAmount, staker, deadline, 17, r, s);

        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);
    }

    function test_multi_depositWithPermit_notStakerSignature(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        uint256 depositAmount = 1e18;
        asset.mint(address(staker), depositAmount);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(depositAmount, notStaker, address(rdToken), notStakerPrivateKey, deadline);

        vm.startPrank(staker);

        vm.expectRevert(bytes("ERC20Permit:INVALID_SIGNATURE"));
        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);

        ( v, r, s ) = _getValidPermitSignature(depositAmount, staker, address(rdToken), stakerPrivateKey, deadline);

        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);

    }

    function test_multi_depositWithPermit_pastDeadline(uint256 entropy) external {
        _createOngoingCampaign(entropy);

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

    function test_multi_depositWithPermit_replay(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        uint256 depositAmount = 1e18;
        asset.mint(address(staker), depositAmount * 2);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(depositAmount, staker, address(rdToken), stakerPrivateKey, deadline);

        vm.startPrank(staker);

        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);

        vm.expectRevert(bytes("ERC20Permit:INVALID_SIGNATURE"));
        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);
    }

    function test_multi_depositWithPermit_preVesting(uint256 depositAmount, uint256 entropy) external {
        _createOngoingCampaign(entropy);
        depositAmount = constrictToRange(depositAmount, 1e6, 1e29);

        uint256 initialSupply      = rdToken.totalSupply();
        uint256 initialTotalAssets = rdToken.totalAssets();
        uint256 initialFreeAssets  = rdToken.totalAssets();
        uint256 initialBalance     = asset.balanceOf(address(rdToken));
        uint256 start              = block.timestamp;

        asset.mint(address(staker), depositAmount);

        assertEq(rdToken.balanceOf(address(staker)), 0);
        assertEq(rdToken.totalSupply(),              initialSupply);
        assertEq(rdToken.freeAssets(),               initialFreeAssets);
        assertEq(rdToken.totalAssets(),              initialTotalAssets);
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              start);

        assertEq(asset.balanceOf(address(staker)),  depositAmount);
        assertEq(asset.balanceOf(address(rdToken)), initialBalance);

        assertEq(asset.nonces(staker),                      0);
        assertEq(asset.allowance(staker, address(rdToken)), 0);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(depositAmount, staker, address(rdToken), stakerPrivateKey, deadline);
        vm.prank(staker);
        uint256 shares = rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);

        assertEq(asset.allowance(staker, address(rdToken)), 0); // Should have used whole allowance
        assertEq(asset.nonces(staker),                      1);

        assertEq(shares, rdToken.balanceOf(staker));

        assertEq(rdToken.balanceOf(address(staker)), shares);
        assertEq(rdToken.totalSupply(),              initialSupply + shares);
        assertEq(rdToken.freeAssets(),               initialFreeAssets + depositAmount);
        assertEq(rdToken.totalAssets(),              initialTotalAssets + depositAmount);
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              block.timestamp);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), initialBalance + depositAmount);
    }

    function test_multi_mintWithPermit_zeroAddress(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        uint256 mintAmount = 1e18;
        uint256 maxAssets = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), maxAssets);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(maxAssets, staker, address(rdToken), stakerPrivateKey, deadline);

        vm.startPrank(staker);

        vm.expectRevert(bytes("ERC20Permit:INVALID_SIGNATURE"));
        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, 17, r, s);

        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);
    }

    function test_multi_mintWithPermit_notStakerSignature(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        uint256 mintAmount = 1e18;
        uint256 maxAssets = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), maxAssets);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(maxAssets, notStaker, address(rdToken), notStakerPrivateKey, deadline);

        vm.startPrank(staker);

        vm.expectRevert(bytes("ERC20Permit:INVALID_SIGNATURE"));
        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);

        ( v, r, s ) = _getValidPermitSignature(maxAssets, staker, address(rdToken), stakerPrivateKey, deadline);

        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);

    }

    function test_multi_mintWithPermit_pastDeadline(uint256 entropy) external {
         _createOngoingCampaign(entropy);

        uint256 mintAmount = 1e18;
        uint256 maxAssets = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), maxAssets);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(maxAssets, staker, address(rdToken), stakerPrivateKey, deadline);

        vm.startPrank(staker);

        vm.warp(deadline + 1);

        vm.expectRevert(bytes("ERC20Permit:EXPIRED"));
        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);

        vm.warp(deadline);

        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);
    }

    function test_multi_mintWithPermit_insufficientPermit(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        uint256 mintAmount = 1e18;
        uint256 maxAssets = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), maxAssets);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(maxAssets - 1, staker, address(rdToken), stakerPrivateKey, deadline);

        vm.startPrank(staker);

        vm.expectRevert(bytes("RDT:MWP:INSUFFICIENT_PERMIT"));
        rdToken.mintWithPermit(mintAmount, staker, maxAssets - 1, deadline, v, r, s);

        ( v, r, s ) = _getValidPermitSignature(maxAssets, staker, address(rdToken), stakerPrivateKey, deadline);

        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);
    }

    function test_multi_mintWithPermit_replay(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        uint256 mintAmount = 1e18;
        uint256 maxAssets = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), maxAssets);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(maxAssets, staker, address(rdToken), stakerPrivateKey, deadline);

        vm.startPrank(staker);

        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);

        maxAssets = rdToken.previewMint(mintAmount);
        asset.mint(address(staker), maxAssets);

        vm.expectRevert(bytes("ERC20Permit:INVALID_SIGNATURE"));
        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);
    }

    function test_multi_mintWithPermit_preVesting(uint256 mintAmount, uint256 entropy) external {
        _createOngoingCampaign(entropy);

        mintAmount = constrictToRange(mintAmount, 1, 1e29);
        uint256 maxAssets = rdToken.previewMint(mintAmount);

        uint256 initialSupply      = rdToken.totalSupply();
        uint256 initialTotalAssets = rdToken.totalAssets();
        uint256 initialFreeAssets  = rdToken.totalAssets();
        uint256 initialBalance     = asset.balanceOf(address(rdToken));
        uint256 start              = block.timestamp;

        asset.mint(address(staker), maxAssets);

        assertEq(rdToken.balanceOf(address(staker)), 0);
        assertEq(rdToken.totalSupply(),              initialSupply);
        assertEq(rdToken.freeAssets(),               initialFreeAssets);
        assertEq(rdToken.totalAssets(),              initialTotalAssets);
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              start);

        assertEq(asset.balanceOf(address(staker)),  maxAssets);
        assertEq(asset.balanceOf(address(rdToken)), initialBalance);

        assertEq(asset.nonces(staker),                      0);
        assertEq(asset.allowance(staker, address(rdToken)), 0);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(maxAssets, staker, address(rdToken), stakerPrivateKey, deadline);
        vm.prank(staker);
        uint256 assets = rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);

        assertEq(asset.allowance(staker, address(rdToken)), 0); // Should have used whole allowance
        assertEq(asset.nonces(staker),                      1);

        assertEq(mintAmount, rdToken.balanceOf(staker));
        assertEq(maxAssets,  assets);

        assertEq(rdToken.balanceOf(address(staker)), mintAmount);
        assertEq(rdToken.totalSupply(),              mintAmount + initialSupply);
        assertEq(rdToken.freeAssets(),               maxAssets + initialFreeAssets);
        assertEq(rdToken.totalAssets(),              maxAssets + initialTotalAssets);
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              block.timestamp);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), maxAssets + initialBalance);
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

    function _createOngoingCampaign(uint256 entropy) internal {
        // Put a initial supply of asset
        uint256 totalAssets = _getRangedValue(entropy, 0, 1e29, "total assets");
        asset.mint(address(rdToken), totalAssets);
        rdToken.__setTotalAssets(totalAssets);

        // Create and deposit with n amount of stakers
        uint256 count = _getRangedValue(entropy, 0, 25, "stakers");
        for (uint256 i = 0; i < count; i++) {
            uint256 amount = _getRangedValue(entropy / (i + 1), 0, 1e29, "deposit");

            if (rdToken.previewDeposit(amount) > 0) {
                Staker stk = new Staker();

                asset.mint(address(stk),amount);
                stk.erc20_approve(address(asset), address(rdToken), amount);
                stk.rdToken_deposit(address(rdToken), amount);
            }
        }

    }

    function _getRangedValue(uint256 entropy, uint256 lowerBound, uint256 upperBound, string memory salt) internal pure returns (uint256 val) {
        val = uint256(keccak256(abi.encode(entropy, salt))) % (upperBound - lowerBound) + lowerBound;
    }

}

contract DepositAndMintTestWithMultipleUsers is TestUtils {

    MockERC20 asset;
    MockRDT   rdToken;
    Staker    staker;

    uint256 constant sampleAssetsToConvert = 1e18;
    uint256 constant sampleSharesToConvert = 1e18;

    function setUp() public virtual {
        asset   = new MockERC20("MockToken", "MT", 18);
        rdToken = new MockRDT("Revenue Distribution Token", "MockRDT", address(this), address(asset), 1e30);
        staker  = new Staker();

        vm.warp(10_000_000);  // Warp to non-zero timestamp

    }

    function test_multi_deposit_zeroAssets(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        uint256 deposit = 1e6;

        asset.mint(address(staker), deposit);
        staker.erc20_approve(address(asset), address(rdToken), deposit);

        vm.expectRevert("RDT:M:ZERO_SHARES");
        staker.rdToken_deposit(address(rdToken), 0);

        staker.rdToken_deposit(address(rdToken), deposit);
    }

    function test_multi_deposit_badApprove(uint256 depositAmount, uint256 entropy) external {
        _createOngoingCampaign(entropy);

        depositAmount = constrictToRange(depositAmount, 1e6, 1e29);

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount - 1);

        vm.expectRevert("RDT:M:TRANSFER_FROM");
        staker.rdToken_deposit(address(rdToken), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);
    }

    function test_multi_deposit_insufficientBalance(uint256 depositAmount, uint256 entropy) external {
        _createOngoingCampaign(entropy);

        depositAmount = constrictToRange(depositAmount, 1e6, 1e29);

        asset.mint(address(staker), depositAmount);
        staker.erc20_approve(address(asset), address(rdToken), depositAmount + 1);

        vm.expectRevert("RDT:M:TRANSFER_FROM");
        staker.rdToken_deposit(address(rdToken), depositAmount + 1);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);
    }

    function test_multi_deposit_zeroShares(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        // Do a deposit so that totalSupply is non-zero
        asset.mint(address(this), 20e18);
        asset.approve(address(rdToken), 20e18);
        rdToken.deposit(20e18, address(this));

        _transferAndUpdateVesting(5e18, 10 seconds);

        vm.warp(block.timestamp + 2 seconds);

        uint256 minDeposit = (rdToken.totalAssets() - 1) / rdToken.totalSupply() + 1;

        asset.mint(address(staker), minDeposit);
        staker.erc20_approve(address(asset), address(rdToken), minDeposit);

        vm.expectRevert("RDT:M:ZERO_SHARES");
        staker.rdToken_deposit(address(rdToken), minDeposit - 1);

        staker.rdToken_deposit(address(rdToken), minDeposit);
    }

    function test_multi_deposit_preVesting(uint256 depositAmount, uint256 entropy) external {
        _createOngoingCampaign(entropy);

        depositAmount = constrictToRange(depositAmount, 1e6, 1e29);

        uint256 initialSupply      = rdToken.totalSupply();
        uint256 initialTotalAssets = rdToken.totalAssets();
        uint256 initialFreeAssets  = rdToken.totalAssets();
        uint256 initialBalance     = asset.balanceOf(address(rdToken));
        uint256 start              = block.timestamp;

        asset.mint(address(staker), depositAmount);

        assertEq(rdToken.balanceOf(address(staker)), 0);
        assertEq(rdToken.totalSupply(),              initialSupply);
        assertEq(rdToken.freeAssets(),               initialFreeAssets);
        assertEq(rdToken.totalAssets(),              initialTotalAssets);
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              start);

        assertEq(asset.balanceOf(address(staker)),  depositAmount);
        assertEq(asset.balanceOf(address(rdToken)), initialBalance);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);

        uint256 shares = staker.rdToken_deposit(address(rdToken), depositAmount);

        assertEq(rdToken.balanceOf(address(staker)),             shares);
        assertEq(rdToken.totalSupply(),                          initialSupply + shares);
        assertEq(rdToken.freeAssets(),                           initialFreeAssets + depositAmount);
        assertEq(rdToken.totalAssets(),                          initialTotalAssets + depositAmount);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          block.timestamp);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), initialBalance + depositAmount);
    }

    function test_multi_mint_zeroAmount(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        uint256 assetAmount = rdToken.previewMint(1);

        asset.mint(address(staker), assetAmount);
        staker.erc20_approve(address(asset), address(rdToken), assetAmount);

        vm.expectRevert("RDT:M:ZERO_SHARES");
        staker.rdToken_mint(address(rdToken), 0);

        staker.rdToken_mint(address(rdToken), 1);
    }

    function test_multi_mint_badApprove(uint256 mintAmount, uint256 entropy) external {
        _createOngoingCampaign(entropy);

        mintAmount = constrictToRange(mintAmount, 1, 1e29);

        uint256 depositAmount = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount - 1);

        vm.expectRevert("RDT:M:TRANSFER_FROM");
        staker.rdToken_mint(address(rdToken), mintAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_mint(address(rdToken), mintAmount);
    }

    function test_multi_mint_insufficientBalance(uint256 mintAmount, uint256 entropy) external {
        _createOngoingCampaign(entropy);

        mintAmount = constrictToRange(mintAmount, 1, 1e29);

        uint256 depositAmount = rdToken.previewMint(mintAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);

        vm.expectRevert("RDT:M:TRANSFER_FROM");
        staker.rdToken_mint(address(rdToken), mintAmount);

        asset.mint(address(staker), depositAmount);

        staker.rdToken_mint(address(rdToken), mintAmount);
    }

    function test_multi_mint_preVesting(uint256 mintAmount, uint256 entropy) external {
        _createOngoingCampaign(entropy);

        mintAmount = constrictToRange(mintAmount, 1, 1e29);

        uint256 depositAmount = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), depositAmount);

        uint256 initialSupply      = rdToken.totalSupply();
        uint256 initialTotalAssets = rdToken.totalAssets();
        uint256 initialFreeAssets  = rdToken.totalAssets();
        uint256 initialBalance     = asset.balanceOf(address(rdToken));
        uint256 start              = block.timestamp;

        assertEq(rdToken.balanceOf(address(staker)), 0);
        assertEq(rdToken.totalSupply(),              initialSupply);
        assertEq(rdToken.freeAssets(),               initialFreeAssets);
        assertEq(rdToken.totalAssets(),              initialTotalAssets);
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              start);

        assertEq(asset.balanceOf(address(staker)),  depositAmount);
        assertEq(asset.balanceOf(address(rdToken)), initialBalance);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);

        uint256 assets = staker.rdToken_mint(address(rdToken), mintAmount);

        assertEq(rdToken.balanceOf(address(staker)), mintAmount);
        assertEq(rdToken.totalSupply(),              initialSupply + mintAmount);
        assertEq(rdToken.freeAssets(),               initialTotalAssets + assets);
        assertEq(rdToken.totalAssets(),              initialFreeAssets + assets);
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              block.timestamp);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), initialBalance + assets);
    }

    function _transferAndUpdateVesting(uint256 vestingAmount_, uint256 vestingPeriod_) internal {
        asset.mint(address(this), vestingAmount_);
        asset.transfer(address(rdToken), vestingAmount_);
        rdToken.updateVestingSchedule(vestingPeriod_);
    }

    function _createOngoingCampaign(uint256 entropy) internal {
        // Put a initial supply of asset
        uint256 totalAssets = _getRangedValue(entropy, 0, 1e29, "total assets");
        asset.mint(address(rdToken), totalAssets);
        rdToken.__setTotalAssets(totalAssets);

        // Create and deposit with n amount of stakers
        uint256 count = _getRangedValue(entropy, 0, 25, "stakers");
        for (uint256 i = 0; i < count; i++) {
            uint256 amount = _getRangedValue(entropy / (i + 1), 0, 1e29, "deposit");

            if (rdToken.previewDeposit(amount) > 0) {
                Staker stk = new Staker();

                asset.mint(address(stk),amount);
                stk.erc20_approve(address(asset), address(rdToken), amount);
                stk.rdToken_deposit(address(rdToken), amount);
            }
        }

    }

    function _getRangedValue(uint256 entropy, uint256 lowerBound, uint256 upperBound, string memory salt) internal pure returns (uint256 val) {
        val = uint256(keccak256(abi.encode(entropy, salt))) % (upperBound - lowerBound) + lowerBound;
    }

}

contract ExitTestWithMultipleUsers is TestUtils {
    MockERC20 asset;
    MockRDT   rdToken;
    Staker    staker;

    uint256 constant sampleAssetsToConvert = 1e18;
    uint256 constant sampleSharesToConvert = 1e18;
    uint256 constant minAmount             = 1e6; // Minimum amount is require so that the conversion from asset to shared does not yield zero. 

    bytes constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

    function setUp() public virtual {
        asset   = new MockERC20("MockToken", "MT", 18);
        rdToken = new MockRDT("Revenue Distribution Token", "MockRDT", address(this), address(asset), 1e30);
        staker  = new Staker();

        vm.warp(10_000_000);  // Warp to non-zero timestamp
    }

    /************************/
    /*** `withdraw` tests ***/
    /************************/

    function test_multi_withdraw_zeroAmount(uint256 depositAmount, uint256 entropy) external {
        _createOngoingCampaign(entropy);
        _depositAsset(constrictToRange(depositAmount, minAmount, 1e29));

        vm.expectRevert("RDT:B:ZERO_SHARES");
        staker.rdToken_withdraw(address(rdToken), 0);

        staker.rdToken_withdraw(address(rdToken), 1);
    }

    function test_multi_withdraw_burnUnderflow(uint256 depositAmount, uint256 entropy) external {
        _createOngoingCampaign(entropy);

        depositAmount = constrictToRange(depositAmount, minAmount, 1e29);
        _depositAsset(depositAmount);

        // Due to rounding up, sometimes a staker can't withdraw the same amount he deposited. Bug?
        uint256 maxWithdraw = rdToken.maxWithdraw(address(staker));

        vm.expectRevert(ARITHMETIC_ERROR);
        staker.rdToken_withdraw(address(rdToken), maxWithdraw + 1);

        staker.rdToken_withdraw(address(rdToken), maxWithdraw);
    }

    function test_multi_withdraw(uint256 depositAmount, uint256 withdrawAmount, uint256 entropy) public {
        _createOngoingCampaign(entropy);

        depositAmount  = constrictToRange(depositAmount,  minAmount, 1e29);
        withdrawAmount = constrictToRange(withdrawAmount, minAmount, depositAmount);

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);

        uint256 initialSupply      = rdToken.totalSupply();
        uint256 initialTotalAssets = rdToken.totalAssets();
        uint256 initialFreeAssets  = rdToken.totalAssets();
        uint256 initialBalance     = asset.balanceOf(address(rdToken));
        uint256 start              = block.timestamp;

        uint256 mintedShares = staker.rdToken_deposit(address(rdToken), depositAmount);

        assertEq(rdToken.balanceOf(address(staker)), mintedShares);
        assertEq(rdToken.totalSupply(),              initialSupply + mintedShares);
        assertEq(rdToken.freeAssets(),               initialFreeAssets + depositAmount);
        assertEq(rdToken.totalAssets(),              initialTotalAssets + depositAmount);
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              start);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount + initialBalance);

        vm.warp(start + 10 days);

        uint256 withdrawnShares = staker.rdToken_withdraw(address(rdToken), withdrawAmount);

        assertEq(rdToken.totalSupply(),                          initialSupply + mintedShares - withdrawnShares);
        assertEq(rdToken.balanceOf(address(staker)),             mintedShares - withdrawnShares);
        assertEq(rdToken.freeAssets(),                           initialFreeAssets + depositAmount - withdrawAmount);
        assertEq(rdToken.totalAssets(),                          initialTotalAssets + depositAmount - withdrawAmount);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          start + 10 days);

        assertEq(asset.balanceOf(address(staker)),  withdrawAmount);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount + initialBalance - withdrawAmount);
    }

    function test_multi_withdraw_totalAssetsGtTotalSupply(
        uint256 depositAmount,
        uint256 withdrawAmount,
        uint256 vestingAmount,
        uint256 vestingPeriod,
        uint256 warpTime,
        uint256 entropy
    ) public {
        //todo getting stack too deep
        _createOngoingCampaign(entropy);

        depositAmount  = constrictToRange(depositAmount,  minAmount, 1e29);
        withdrawAmount = constrictToRange(withdrawAmount, minAmount, depositAmount);
        vestingAmount  = constrictToRange(vestingAmount,  1,         1e29);
        vestingPeriod  = constrictToRange(vestingPeriod,  1,         100 days);
        warpTime       = constrictToRange(warpTime,       1,         vestingPeriod);

        uint256 initialSupply      = rdToken.totalSupply();
        uint256 initialTotalAssets = rdToken.totalAssets();
        uint256 initialFreeAssets  = rdToken.totalAssets();
        uint256 initialBalance     = asset.balanceOf(address(rdToken));
        uint256 start              = block.timestamp;

        uint256 mintedShares = _depositAsset(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        {
            assertEq(rdToken.balanceOf(address(staker)), mintedShares);
            assertEq(rdToken.totalSupply(),              initialSupply + mintedShares);
            assertEq(rdToken.freeAssets(),               initialFreeAssets + depositAmount);
            assertEq(rdToken.lastUpdated(),              start);
        }

        uint256 totalAssets = initialTotalAssets + depositAmount + vestingAmount * warpTime / vestingPeriod;

        assertWithinDiff(rdToken.totalAssets(),  totalAssets,                          1);
        assertWithinDiff(rdToken.issuanceRate(), vestingAmount * 1e30 / vestingPeriod, 1);

        // assertEq(asset.balanceOf(address(staker)),  0);
        // assertEq(asset.balanceOf(address(rdToken)), depositAmount + vestingAmount + initialBalance);

        // uint256 expectedSharesBurned = rdToken.previewWithdraw(withdrawAmount);
        // uint256 sharesBurned         = staker.rdToken_withdraw(address(rdToken), withdrawAmount);

        // totalAssets -= withdrawAmount;

        // assertEq(sharesBurned,                       expectedSharesBurned);
        // assertEq(rdToken.balanceOf(address(staker)), depositAmount - sharesBurned);
        // assertEq(rdToken.totalSupply(),              depositAmount - sharesBurned);
        // assertEq(rdToken.lastUpdated(),              start + warpTime);

        // // // if (rdToken.totalSupply() > 0) assertWithinPrecision(rdToken.exchangeRate(), exchangeRate1, 8);  // TODO: Add specialized testing for this

        // assertWithinDiff(rdToken.issuanceRate(), vestingAmount * 1e30 / vestingPeriod, 1);
        // assertWithinDiff(rdToken.freeAssets(),   totalAssets,                          1);
        // assertWithinDiff(rdToken.totalAssets(),  totalAssets,                          1);

        // assertEq(asset.balanceOf(address(staker)),  withdrawAmount);
        // assertEq(asset.balanceOf(address(rdToken)), depositAmount + vestingAmount - withdrawAmount);

    }

    function test_multi_withdraw_callerNotOwner_badApproval(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        Staker shareOwner    = new Staker();
        Staker notShareOwner = new Staker();

        uint256 depositAmount = 1e29;
        asset.mint(address(shareOwner), depositAmount);

        shareOwner.erc20_approve(address(asset), address(rdToken), depositAmount);
        shareOwner.rdToken_deposit(address(rdToken), depositAmount);

        uint256 maxWithdraw = rdToken.maxWithdraw(address(shareOwner));
        uint256 shares      = rdToken.previewWithdraw(maxWithdraw);

        shareOwner.erc20_approve(address(rdToken), address(notShareOwner), shares - 1);
        vm.expectRevert("RDT:CALLER_ALLOWANCE");
        notShareOwner.rdToken_withdraw(address(rdToken), maxWithdraw, address(shareOwner), address(shareOwner));

        // This is a weird test, because we're approving shares, even though withdraw take assets as inputs.
        shareOwner.erc20_approve(address(rdToken), address(notShareOwner), shares);

        assertEq(rdToken.allowance(address(shareOwner), address(notShareOwner)), shares);

        notShareOwner.rdToken_withdraw(address(rdToken), maxWithdraw, address(notShareOwner), address(shareOwner));

        assertEq(rdToken.allowance(address(shareOwner), address(notShareOwner)), 0);
    }

    function test_multi_withdraw_callerNotOwner_infiniteApprovalForCaller(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        Staker shareOwner    = new Staker();
        Staker notShareOwner = new Staker();

        uint256 depositAmount = 1e29;
        asset.mint(address(shareOwner), depositAmount);

        shareOwner.erc20_approve(address(asset), address(rdToken), depositAmount);
        uint256 shares = shareOwner.rdToken_deposit(address(rdToken), depositAmount);

        shareOwner.erc20_approve(address(rdToken), address(notShareOwner), type(uint256).max);

        assertEq(rdToken.allowance(address(shareOwner), address(notShareOwner)), type(uint256).max);

        notShareOwner.rdToken_withdraw(address(rdToken), shares, address(notShareOwner), address(shareOwner));

        // Infinite approval stays infinite.
        assertEq(rdToken.allowance(address(shareOwner), address(notShareOwner)), type(uint256).max);
    }

    function test_multi_withdraw_callerNotOwner(uint256 depositAmount, uint256 withdrawAmount, uint256 callerAllowance, uint256 entropy) public {
         _createOngoingCampaign(entropy);

        depositAmount  = constrictToRange(depositAmount,  minAmount, 1e29);
        withdrawAmount = constrictToRange(withdrawAmount, minAmount, depositAmount);

        asset.mint(address(staker), depositAmount);

        uint256 initialSupply      = rdToken.totalSupply();
        uint256 initialTotalAssets = rdToken.totalAssets();
        uint256 initialFreeAssets  = rdToken.totalAssets();
        uint256 initialBalance     = asset.balanceOf(address(rdToken));
        uint256 start              = block.timestamp;

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        uint256 shares = staker.rdToken_deposit(address(rdToken), depositAmount);

        assertEq(rdToken.balanceOf(address(staker)), shares);
        assertEq(rdToken.totalSupply(),              initialSupply + shares);
        assertEq(rdToken.freeAssets(),               initialFreeAssets + depositAmount);
        assertEq(rdToken.totalAssets(),              initialTotalAssets + depositAmount);
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              start);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), initialBalance + depositAmount);

        vm.warp(start + 10 days);

        Staker notShareOwner = new Staker();



        uint256 expectedSharesBurned = rdToken.maxWithdraw(address(staker));
        callerAllowance              = constrictToRange(callerAllowance, expectedSharesBurned, type(uint256).max - 1);  // Allowance reduction doesn't happen with infinite approval.
        staker.erc20_approve(address(rdToken), address(notShareOwner), callerAllowance);

        assertEq(rdToken.allowance(address(staker), address(notShareOwner)), callerAllowance);

        emit log_named_uint("expectedSharesBurned", expectedSharesBurned);
        emit log_named_uint("allsssssssssssowance", rdToken.allowance(address(staker), address(notShareOwner)));

        // Withdraw assets to notShareOwner
        uint256 sharesBurned = notShareOwner.rdToken_withdraw(address(rdToken), withdrawAmount, address(notShareOwner), address(staker));

        assertEq(rdToken.allowance(address(staker), address(notShareOwner)), callerAllowance - sharesBurned);

        assertEq(rdToken.balanceOf(address(staker)), shares - sharesBurned);
        assertEq(rdToken.totalSupply(),              initialSupply + shares - sharesBurned);
        assertEq(rdToken.freeAssets(),               initialFreeAssets + depositAmount - withdrawAmount);
        assertEq(rdToken.totalAssets(),              initialTotalAssets + depositAmount - withdrawAmount);
        assertEq(rdToken.issuanceRate(),             0);
        assertEq(rdToken.lastUpdated(),              start + 10 days);

        assertEq(asset.balanceOf(address(staker)),        0);
        assertEq(asset.balanceOf(address(notShareOwner)), withdrawAmount);  // notShareOwner received the assets.
        assertEq(asset.balanceOf(address(rdToken)),       initialBalance + depositAmount - withdrawAmount);
    }

    function test_withdraw_callerNotOwner_totalAssetsGtTotalSupply(
        uint256 depositAmount,
        uint256 withdrawAmount,
        uint256 vestingAmount,
        uint256 vestingPeriod,
        uint256 warpTime,
        uint256 callerAllowance
    ) public {
        depositAmount  = constrictToRange(depositAmount,  1, 1e29);
        withdrawAmount = constrictToRange(withdrawAmount, 1, depositAmount);
        vestingAmount  = constrictToRange(vestingAmount,  1, 1e29);
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

    function test_redeem_zeroShares(uint256 depositAmount) external {
        _depositAsset(constrictToRange(depositAmount, 1, 1e29));

        vm.expectRevert("RDT:B:ZERO_SHARES");
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

    function test_redeem_burnUnderflow_totalAssetsGtTotalSupply_explicitValues() external {
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

    function test_redeem_totalAssetsGtTotalSupply_explicitValues() public {
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

    function test_redeem_callerNotOwner_totalAssetsGtTotalSupply_explicitValues() external {
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

    function _depositAsset(uint256 depositAmount) internal returns (uint256 shares){
        asset.mint(address(staker), depositAmount);
        staker.erc20_approve(address(asset), address(rdToken), depositAmount);

        shares = staker.rdToken_deposit(address(rdToken), depositAmount);
    }

    function _transferAndUpdateVesting(uint256 vestingAmount_, uint256 vestingPeriod_) internal {
        asset.mint(address(this), vestingAmount_);
        asset.transfer(address(rdToken), vestingAmount_);
        rdToken.updateVestingSchedule(vestingPeriod_);
    }

    function _createOngoingCampaign(uint256 entropy) internal {
        // Put a initial supply of asset
        uint256 totalAssets = _getRangedValue(entropy, 0, 1e29, "total assets");
        asset.mint(address(rdToken), totalAssets);
        rdToken.__setTotalAssets(totalAssets);

        // Create and deposit with n amount of stakers
        uint256 count = _getRangedValue(entropy, 0, 25, "stakers");
        for (uint256 i = 0; i < count; i++) {
            uint256 amount = _getRangedValue(entropy / (i + 1), 0, 1e29, "deposit");

            if (rdToken.previewDeposit(amount) > 0) {
                Staker stk = new Staker();

                asset.mint(address(stk),amount);
                stk.erc20_approve(address(asset), address(rdToken), amount);
                stk.rdToken_deposit(address(rdToken), amount);
            }
        }

    }

    function _getRangedValue(uint256 entropy, uint256 lowerBound, uint256 upperBound, string memory salt) internal pure returns (uint256 val) {
        val = uint256(keccak256(abi.encode(entropy, salt))) % (upperBound - lowerBound) + lowerBound;
    }

}

contract RevenueStreamingTestWithMultipleUsers is TestUtils {

    MockERC20 asset;
    MockRDT   rdToken;

    uint256 constant sampleAssetsToConvert = 1e18;
    uint256 constant sampleSharesToConvert = 1e18;

    bytes constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

    uint256 start;

    function setUp() public virtual {
        // Use non-zero timestamp
        start = 10_000;
        vm.warp(start);

        asset   = new MockERC20("MockToken", "MT", 18);
        rdToken = new MockRDT("Revenue Distribution Token", "MockRDT", address(this), address(asset), 1e30);
    }

    /************************************/
    /*** Single updateVestingSchedule ***/
    /************************************/

    function test_multi_updateVestingSchedule_single(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        uint256 initialSupply      = rdToken.totalSupply();
        uint256 initialTotalAssets = rdToken.totalAssets();
        uint256 initialFreeAssets  = rdToken.totalAssets();
        uint256 initialBalance     = asset.balanceOf(address(rdToken));
        uint256 start              = block.timestamp;

        emit log_named_uint("start", start);

        assertEq(rdToken.freeAssets(),          initialFreeAssets);
        assertEq(rdToken.totalAssets(),         initialTotalAssets);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), start - 1);

        assertEq(asset.balanceOf(address(rdToken)), initialBalance);

        _transferAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        assertEq(asset.balanceOf(address(rdToken)), initialBalance + 1000);

        assertEq(rdToken.freeAssets(),                           initialFreeAssets);
        assertEq(rdToken.totalAssets(),                          initialTotalAssets);
        assertEq(rdToken.issuanceRate(),                         10e30);  // 10 tokens per second
        assertEq(rdToken.lastUpdated(),                          start);
        assertEq(rdToken.vestingPeriodFinish(),                  start + 100 seconds);

        vm.warp(rdToken.vestingPeriodFinish());

        assertEq(rdToken.totalAssets(), initialTotalAssets + 1000);  // All tokens vested
    }

    function test_multi_updateVestingSchedule_single_roundingDown(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        uint256 initialTotalAssets = rdToken.totalAssets();

        _transferAndUpdateVesting(1000, 30 seconds);  // 33.3333... tokens per second

        assertEq(rdToken.totalAssets(),  initialTotalAssets);
        assertEq(rdToken.issuanceRate(), 33333333333333333333333333333333);  // 3.33e30

        // totalAssets should never be more than one full unit off
        vm.warp(start + 1 seconds);
        assertEq(rdToken.totalAssets(), initialTotalAssets + 33);  // 33 < 33.33...

        vm.warp(start + 2 seconds);
        assertEq(rdToken.totalAssets(), initialTotalAssets + 66);  // 66 < 66.66...

        vm.warp(start + 3 seconds);
        assertEq(rdToken.totalAssets(), initialTotalAssets + 99);  // 99 < 99.99...

        vm.warp(start + 4 seconds);
        assertEq(rdToken.totalAssets(), initialTotalAssets + 133);  // 133 < 133.33...

        vm.warp(rdToken.vestingPeriodFinish());
        assertEq(rdToken.totalAssets(), initialTotalAssets + 999);  // 999 < 1000
    }

    /*************************************************/
    /*** Multiple updateVestingSchedule, same time ***/
    /*************************************************/

    function test_multi_updateVestingSchedule_sameTime_shorterVesting(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        uint256 initialTotalAssets = rdToken.totalAssets();

        _transferAndUpdateVesting(1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);  // Always updates to latest vesting schedule

        _transferAndUpdateVesting(1000, 20 seconds);
        assertEq(rdToken.issuanceRate(),        100e30);              // (1000 + 1000) / 20 seconds = 100 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 20 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalAssets(), initialTotalAssets);

        vm.warp(start + 20 seconds);

        assertEq(rdToken.totalAssets(), initialTotalAssets + 2000);
    }

    function test_multi_updateVestingSchedule_sameTime_longerVesting_higherRate(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        uint256 initialTotalAssets = rdToken.totalAssets();

        _transferAndUpdateVesting(1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);  // Always updates to latest vesting schedule

        _transferAndUpdateVesting(3000, 200 seconds);
        assertEq(rdToken.issuanceRate(),        20e30);                // (3000 + 1000) / 200 seconds = 20 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 200 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalAssets(), initialTotalAssets);

        vm.warp(start + 200 seconds);

        assertEq(rdToken.totalAssets(), initialTotalAssets + 4000);
    }

    function test_multi_updateVestingSchedule_sameTime_longerVesting_lowerRate(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        uint256 initialTotalAssets = rdToken.totalAssets();

        _transferAndUpdateVesting(1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);  // Always updates to latest vesting schedule

        _transferAndUpdateVesting(1000, 500 seconds);
        assertEq(rdToken.issuanceRate(),        4e30);                 // (1000 + 1000) / 500 seconds = 4 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), start + 500 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalAssets(), initialTotalAssets);

        vm.warp(start + 5000 seconds);

        assertEq(rdToken.totalAssets(), initialTotalAssets + 2000);
    }

    /*******************************************************/
    /*** Multiple updateVestingSchedule, different times ***/
    /*******************************************************/

    function test_multi_updateVestingSchedule_diffTime_shorterVesting(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        uint256 initialTotalAssets = rdToken.totalAssets();
        uint256 initialFreeAssets  = rdToken.totalAssets();

        _transferAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        vm.warp(start + 60 seconds);

        assertEq(rdToken.issuanceRate(),        10e30);
        assertEq(rdToken.totalAssets(),         initialTotalAssets + 600);
        assertEq(rdToken.freeAssets(),          initialFreeAssets);
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);

        _transferAndUpdateVesting(1000, 20 seconds);  // 50 tokens per second

        assertEq(rdToken.issuanceRate(),        70e30);  // (400 + 1000) / 20 seconds = 70 tokens per second
        assertEq(rdToken.totalAssets(),         initialTotalAssets + 600);
        assertEq(rdToken.freeAssets(),          initialFreeAssets + 600);
        assertEq(rdToken.vestingPeriodFinish(), start + 60 seconds + 20 seconds);

        vm.warp(start + 60 seconds + 20 seconds);

        assertEq(rdToken.issuanceRate(), 70e30);
        assertEq(rdToken.totalAssets(),  initialTotalAssets + 2000);
        assertEq(rdToken.freeAssets(),   initialFreeAssets + 600);
    }

    function test_multi_updateVestingSchedule_diffTime_longerVesting_higherRate(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        uint256 initialTotalAssets = rdToken.totalAssets();
        uint256 initialFreeAssets  = rdToken.totalAssets();

        _transferAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        vm.warp(start + 60 seconds);

        assertEq(rdToken.issuanceRate(),        10e30);
        assertEq(rdToken.totalAssets(),         initialTotalAssets + 600);
        assertEq(rdToken.freeAssets(),          initialFreeAssets);
        assertEq(rdToken.vestingPeriodFinish(), start + 100 seconds);

        _transferAndUpdateVesting(3000, 200 seconds);  // 15 tokens per second

        assertEq(rdToken.issuanceRate(), 17e30);  // (400 + 3000) / 200 seconds = 17 tokens per second
        assertEq(rdToken.totalAssets(),  initialTotalAssets + 600);
        assertEq(rdToken.freeAssets(),   initialFreeAssets + 600);

        vm.warp(start + 60 seconds + 200 seconds);

        assertEq(rdToken.issuanceRate(), 17e30);
        assertEq(rdToken.totalAssets(),  initialTotalAssets + 4000);
        assertEq(rdToken.freeAssets(),   initialFreeAssets + 600);
    }

    function test_multi_updateVestingSchedule_diffTime_longerVesting_lowerRate(uint256 entropy) external {
        _createOngoingCampaign(entropy);

        uint256 initialTotalAssets = rdToken.totalAssets();
        uint256 initialFreeAssets  = rdToken.totalAssets();

        _transferAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        vm.warp(start + 60 seconds);

        assertEq(rdToken.issuanceRate(), 10e30);
        assertEq(rdToken.totalAssets(),  initialTotalAssets + 600);
        assertEq(rdToken.freeAssets(),   initialFreeAssets);

        _transferAndUpdateVesting(1000, 200 seconds);  // 5 tokens per second

        assertEq(rdToken.issuanceRate(), 7e30);  // (400 + 1000) / 200 seconds = 7 tokens per second
        assertEq(rdToken.totalAssets(),  initialTotalAssets + 600);
        assertEq(rdToken.freeAssets(),   initialFreeAssets + 600);

        vm.warp(start + 60 seconds + 200 seconds);

        assertEq(rdToken.issuanceRate(), 7e30);
        assertEq(rdToken.totalAssets(),  initialTotalAssets + 2000);
        assertEq(rdToken.freeAssets(),   initialFreeAssets + 600);
    }

    /********************************/
    /*** End to end vesting tests ***/
    /********************************/

    function test_multi_vesting_singleSchedule_fuzz(uint256 depositAmount, uint256 vestingAmount, uint256 vestingPeriod, uint256 entropy) public {
        _createOngoingCampaign(entropy);

        depositAmount = constrictToRange(depositAmount, 1e6,        1e30);                    // 1 billion at WAD precision
        vestingAmount = constrictToRange(vestingAmount, 1e6,        1e30);                    // 1 billion at WAD precision
        vestingPeriod = constrictToRange(vestingPeriod, 10 seconds, 100_000 days) / 10 * 10;  // Must be divisible by 10 for for loop 10% increment calculations // TODO: Add a zero case test

        uint256 initialSupply      = rdToken.totalSupply();
        uint256 initialTotalAssets = rdToken.totalAssets();
        uint256 initialFreeAssets  = rdToken.totalAssets();
        uint256 initialBalance     = asset.balanceOf(address(rdToken));
        uint256 start              = block.timestamp;

        Staker staker = new Staker();

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        uint256 shares = staker.rdToken_deposit(address(rdToken), depositAmount);

        assertEq(rdToken.freeAssets(),          initialFreeAssets + depositAmount);
        assertEq(rdToken.totalAssets(),         initialTotalAssets + depositAmount);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), start - 1); //todo i don't really know why this happens

        vm.warp(start + 1 days);

        assertEq(rdToken.totalAssets(),  initialTotalAssets + depositAmount);  // No change

        vm.warp(start);  // Warp back after demonstrating totalAssets is not time-dependent before vesting starts

        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        uint256 expectedRate = vestingAmount * 1e30 / vestingPeriod;

        assertEq(rdToken.freeAssets(),          initialFreeAssets + depositAmount);
        assertEq(rdToken.totalAssets(),         initialTotalAssets + depositAmount);
        assertEq(rdToken.issuanceRate(),        expectedRate);
        assertEq(rdToken.lastUpdated(),         start);
        assertEq(rdToken.vestingPeriodFinish(), start + vestingPeriod);

        //todo stack too deep

        //Warp and assert vesting in 10% increments
        for (uint256 i = 1; i < 10; ++i) {
            vm.warp(start + vestingPeriod * i / 10);  // 10% intervals of vesting schedule

            uint256 expectedTotalAssets  = initialTotalAssets + depositAmount + expectedRate * (block.timestamp - start) / 1e30;
            uint256 expectedStakerAssets = depositAmount + expectedRate * (block.timestamp - start) / 1e30;

            // assertWithinDiff(rdToken.balanceOfAssets(address(staker)), expectedStakerAssets, 1);

            assertEq(rdToken.totalSupply(),                          initialSupply + shares);
            assertEq(rdToken.totalAssets(),                          expectedTotalAssets);
            // assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert * expectedTotalAssets / depositAmount);
            // assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert * depositAmount / expectedTotalAssets);
        }

        // vm.warp(start + vestingPeriod);

        // uint256 expectedFinalTotal = depositAmount + vestingAmount;

        // // TODO: Try assertEq
        // assertWithinDiff(rdToken.balanceOfAssets(address(staker)), expectedFinalTotal, 2);

        // assertWithinDiff(rdToken.totalAssets(), expectedFinalTotal, 1);
        // assertEq(rdToken.convertToAssets(sampleSharesToConvert),    sampleSharesToConvert * rdToken.totalAssets() / depositAmount); // Using totalAssets because of rounding
        // assertEq(rdToken.convertToShares(sampleAssetsToConvert),    sampleAssetsToConvert * depositAmount / rdToken.totalAssets());

        // assertEq(asset.balanceOf(address(rdToken)), depositAmount + vestingAmount);

        // assertEq(asset.balanceOf(address(staker)), 0);
        // assertEq(rdToken.balanceOf(address(staker)),    depositAmount);

        // staker.rdToken_redeem(address(rdToken), depositAmount);  // Use `redeem` so rdToken amount can be used to burn 100% of tokens

        // assertWithinDiff(rdToken.freeAssets(),  0, 1);
        // assertWithinDiff(rdToken.totalAssets(), 0, 1);

        // assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);  // Returns to sampleSharesToConvert zero when empty.
        // assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);  // Returns to sampleAssetsToConvert zero when empty.
        // assertEq(rdToken.issuanceRate(),                         expectedRate);           // TODO: Investigate implications of non-zero issuanceRate here
        // assertEq(rdToken.lastUpdated(),                          start + vestingPeriod);  // This makes issuanceRate * time zero
        // assertEq(rdToken.vestingPeriodFinish(),                  start + vestingPeriod);

        // assertWithinDiff(asset.balanceOf(address(rdToken)), 0, 2);

        // assertEq(rdToken.balanceOfAssets(address(staker)), 0);

        // assertWithinDiff(asset.balanceOf(address(staker)),   depositAmount + vestingAmount, 2);
        // assertWithinDiff(rdToken.balanceOf(address(staker)), 0,                             1);
    }

    function _transferAndUpdateVesting(uint256 vestingAmount_, uint256 vestingPeriod_) internal {
        asset.mint(address(this), vestingAmount_);
        asset.transfer(address(rdToken), vestingAmount_);
        rdToken.updateVestingSchedule(vestingPeriod_);
    }

    function _createOngoingCampaign(uint256 entropy) internal {
        // Put a initial supply of asset
        uint256 totalAssets = _getRangedValue(entropy, 0, 1e29, "total assets");
        asset.mint(address(rdToken), totalAssets);
        rdToken.__setTotalAssets(totalAssets);

        // Create and deposit with n amount of stakers
        uint256 count = _getRangedValue(entropy, 0, 25, "stakers");
        for (uint256 i = 0; i < count; i++) {
            uint256 amount = _getRangedValue(entropy / (i + 1), 0, 1e29, "deposit");

            if (rdToken.previewDeposit(amount) > 0) {
                Staker stk = new Staker();

                asset.mint(address(stk),amount);
                stk.erc20_approve(address(asset), address(rdToken), amount);
                stk.rdToken_deposit(address(rdToken), amount);
            }
        }

    }

    function _getRangedValue(uint256 entropy, uint256 lowerBound, uint256 upperBound, string memory salt) internal pure returns (uint256 val) {
        val = uint256(keccak256(abi.encode(entropy, salt))) % (upperBound - lowerBound) + lowerBound;
    }

}

contract RedeemRevertOnTransferWithMultipleUsers is TestUtils {

    MockRevertingERC20 asset;
    MockRDT            rdToken;
    Staker             staker;

    uint256 constant sampleAssetsToConvert = 1e18;
    uint256 constant sampleSharesToConvert = 1e18;

    bytes constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

    function setUp() public virtual {
        asset   = new MockRevertingERC20("MockToken", "MT", 18);
        rdToken = new MockRDT("Revenue Distribution Token", "MockRDT", address(this), address(asset), 1e30);
        staker  = new Staker();

        vm.warp(10_000_000);  // Warp to non-zero timestamp
    }

    function test_multi_redeem_revertOnTransfer(uint256 depositAmount, uint256 redeemAmount, uint256 entropy) public {
        _createOngoingCampaign(entropy);

        depositAmount = constrictToRange(depositAmount, 1e6, 1e29);
        redeemAmount  = constrictToRange(redeemAmount,  1e6, depositAmount);

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        uint256 shares = staker.rdToken_deposit(address(rdToken), depositAmount);

        uint256 start = block.timestamp;

        vm.warp(start + 10 days);

        vm.expectRevert(bytes("RDT:B:TRANSFER"));
        staker.rdToken_redeem(address(rdToken), shares, address(0), address(staker));

        staker.rdToken_redeem(address(rdToken), shares, address(1), address(staker));
    }

    function test_multi_withdraw_revertOnTransfer(uint256 depositAmount, uint256 withdrawAmount, uint256 entropy) public {
        _createOngoingCampaign(entropy);

        depositAmount  = constrictToRange(depositAmount,  1e6, 1e29);
        withdrawAmount = constrictToRange(withdrawAmount, 1e6, depositAmount);

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        uint256 start = block.timestamp;

        vm.warp(start + 10 days);

        vm.expectRevert(bytes("RDT:B:TRANSFER"));
        staker.rdToken_withdraw(address(rdToken), withdrawAmount, address(0), address(staker));

        staker.rdToken_withdraw(address(rdToken), withdrawAmount, address(1), address(staker));
    }

    function _depositAsset(uint256 depositAmount) internal {
        asset.mint(address(staker), depositAmount);
        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);
    }

    function _createOngoingCampaign(uint256 entropy) internal {
        // Put a initial supply of asset
        uint256 totalAssets = _getRangedValue(entropy, 0, 1e29, "total assets");
        asset.mint(address(rdToken), totalAssets);
        rdToken.__setTotalAssets(totalAssets);

        // Create and deposit with n amount of stakers
        uint256 count = _getRangedValue(entropy, 0, 25, "stakers");
        for (uint256 i = 0; i < count; i++) {
            uint256 amount = _getRangedValue(entropy / (i + 1), 0, 1e29, "deposit");

            if (rdToken.previewDeposit(amount) > 0) {
                Staker stk = new Staker();

                asset.mint(address(stk),amount);
                stk.erc20_approve(address(asset), address(rdToken), amount);
                stk.rdToken_deposit(address(rdToken), amount);
            }
        }

    }

    function _getRangedValue(uint256 entropy, uint256 lowerBound, uint256 upperBound, string memory salt) internal pure returns (uint256 val) {
        val = uint256(keccak256(abi.encode(entropy, salt))) % (upperBound - lowerBound) + lowerBound;
    }
}
