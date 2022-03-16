// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { TestUtils } from "../../modules/contract-test-utils/contracts/test.sol";
import { MockERC20 } from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { MockRevertingERC20 } from "./mocks/MockRevertingERC20.sol";

import { Owner }  from "./accounts/Owner.sol";
import { Staker } from "./accounts/Staker.sol";

import { RevenueDistributionToken as RDT } from "../RevenueDistributionToken.sol";

contract ConstructorTest is TestUtils {

    function test_constructor_ownerZeroAddress() external {
        MockERC20 asset = new MockERC20("MockToken", "MT", 18);

        vm.expectRevert("RDT:C:OWNER_ZERO_ADDRESS");
        RDT rdToken = new RDT("Revenue Distribution Token", "RDT", address(0), address(asset), 1e30);

        rdToken = new RDT("Revenue Distribution Token", "RDT", address(this), address(asset), 1e30);
    }

}

contract DepositAndMintWithPermitFailureModeTest is TestUtils {

    MockERC20 asset;
    RDT       rdToken;

    uint256 stakerPrivateKey    = 1;
    uint256 notStakerPrivateKey = 2;
    uint256 nonce               = 0;
    uint256 deadline            = 5_000_000_000;  // Timestamp far in the future

    uint256 constant sampleAssetsToConvert = 1e18;
    uint256 constant sampleSharesToConvert = 1e18;

    address staker;
    address notStaker;

    function setUp() public virtual {
        asset   = new MockERC20("MockToken", "MT", 18);
        rdToken = new RDT("Revenue Distribution Token", "RDT", address(this), address(asset), 1e30);

        staker    = vm.addr(stakerPrivateKey);
        notStaker = vm.addr(notStakerPrivateKey);

        vm.warp(10_000_000);  // Warp to non-zero timestamp
    }

    /**********************************************/
    /*** `depositWithPermit` Failure Mode Tests ***/
    /**********************************************/

    function test_depositWithPermit_zeroAddress() external {
        uint256 depositAmount = 1e18;
        asset.mint(address(staker), depositAmount);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(depositAmount, staker, address(rdToken), stakerPrivateKey, deadline);

        vm.startPrank(staker);

        vm.expectRevert(bytes("ERC20:P:MALLEABLE"));
        rdToken.depositWithPermit(depositAmount, staker, deadline, 17, r, s);

        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);
    }

    function test_depositWithPermit_notStakerSignature() external {
        uint256 depositAmount = 1e18;
        asset.mint(address(staker), depositAmount);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(depositAmount, notStaker, address(rdToken), notStakerPrivateKey, deadline);

        vm.startPrank(staker);

        vm.expectRevert(bytes("ERC20:P:INVALID_SIGNATURE"));
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

        vm.expectRevert(bytes("ERC20:P:EXPIRED"));
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

        vm.expectRevert(bytes("ERC20:P:INVALID_SIGNATURE"));
        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);
    }

    /*******************************************/
    /*** `mintWithPermit` Failure Mode Tests ***/
    /*******************************************/

    function test_mintWithPermit_zeroAddress() external {
        uint256 mintAmount = 1e18;
        uint256 maxAssets = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), maxAssets);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(maxAssets, staker, address(rdToken), stakerPrivateKey, deadline);

        vm.startPrank(staker);

        vm.expectRevert(bytes("ERC20:P:MALLEABLE"));
        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, 17, r, s);

        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);
    }

    function test_mintWithPermit_notStakerSignature() external {
        uint256 mintAmount = 1e18;
        uint256 maxAssets = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), maxAssets);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(maxAssets, notStaker, address(rdToken), notStakerPrivateKey, deadline);

        vm.startPrank(staker);

        vm.expectRevert(bytes("ERC20:P:INVALID_SIGNATURE"));
        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);

        ( v, r, s ) = _getValidPermitSignature(maxAssets, staker, address(rdToken), stakerPrivateKey, deadline);

        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);

    }

    function test_mintWithPermit_pastDeadline() external {
        uint256 mintAmount = 1e18;
        uint256 maxAssets = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), maxAssets);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(maxAssets, staker, address(rdToken), stakerPrivateKey, deadline);

        vm.startPrank(staker);

        vm.warp(deadline + 1);

        vm.expectRevert(bytes("ERC20:P:EXPIRED"));
        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);

        vm.warp(deadline);

        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);
    }

    function test_mintWithPermit_insufficientPermit() external {
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

    function test_mintWithPermit_replay() external {
        uint256 mintAmount = 1e18;
        uint256 maxAssets = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), maxAssets * 2);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(maxAssets, staker, address(rdToken), stakerPrivateKey, deadline);

        vm.startPrank(staker);

        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);

        vm.expectRevert(bytes("ERC20:P:INVALID_SIGNATURE"));
        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);
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

contract RDTTestBase is TestUtils {

    /***********************/
    /*** Setup Variables ***/
    /***********************/

    MockERC20 asset;
    RDT       rdToken;

    uint256 nonce    = 0;
    uint256 deadline = 5_000_000_000;  // Timestamp far in the future

    uint256 constant sampleAssetsToConvert = 1e18;
    uint256 constant sampleSharesToConvert = 1e18;

    bytes constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

    uint256 constant START = 10_000_000;

    function setUp() public virtual {
        asset   = new MockERC20("MockToken", "MT", 18);
        rdToken = new RDT("Revenue Distribution Token", "RDT", address(this), address(asset), 1e30);

        vm.warp(START);  // Warp to non-zero timestamp
    }

    // Deposit asset into RDT
    function _depositAsset(address asset_, address staker_, uint256 depositAmount_) internal {
        MockERC20(asset_).mint(staker_, depositAmount_);
        Staker(staker_).erc20_approve(asset_, address(rdToken), depositAmount_);
        Staker(staker_).rdToken_deposit(address(rdToken), depositAmount_);
    }

    // Transfer funds into RDT and update the vesting schedule
    function _transferAndUpdateVesting(address asset_, address rdToken_, uint256 vestingAmount_, uint256 vestingPeriod_) internal {
        MockERC20(asset_).mint(address(this), vestingAmount_);
        MockERC20(asset_).transfer(rdToken_, vestingAmount_);
        RDT(rdToken_).updateVestingSchedule(vestingPeriod_);
    }

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

contract RDTSuccessTestBase is RDTTestBase {

    /***************************/
    /*** Pre State Variables ***/
    /***************************/

    // NOTE: Pre state variables are kept in storage to avoid stack too deep
    int256 rdToken_balanceOf_staker;
    int256 rdToken_totalSupply;
    int256 rdToken_freeAssets;
    int256 rdToken_totalAssets;
    int256 rdToken_convertToAssets;
    int256 rdToken_convertToShares;
    int256 rdToken_issuanceRate;
    int256 rdToken_lastUpdated;
    int256 asset_balanceOf_staker;
    int256 asset_balanceOf_rdToken;
    int256 asset_nonces;
    int256 asset_allowance_staker_rdToken;

    /****************************************/
    /*** State Change Assertion Variables ***/
    /****************************************/

    // NOTE: State change assertion variables are kept in storage to avoid stack too deep
    int256 rdToken_balanceOf_staker_change;
    int256 rdToken_totalSupply_change;
    int256 rdToken_freeAssets_change;
    int256 rdToken_totalAssets_change;
    int256 rdToken_convertToAssets_change;
    int256 rdToken_convertToShares_change;
    int256 rdToken_issuanceRate_change;
    int256 rdToken_lastUpdated_change;
    int256 asset_balanceOf_staker_change;
    int256 asset_balanceOf_rdToken_change;
    int256 asset_nonces_change;
    int256 asset_allowance_staker_rdToken_change;

    function _assertDepositWithPermit(address staker_, uint256 stakerPrivateKey_, uint256 depositAmount_) internal {
        depositAmount_ = constrictToRange(depositAmount_, 1, 1e29);

        asset.mint(staker_, depositAmount_);

        rdToken_balanceOf_staker = _toInt256(rdToken.balanceOf(staker_));
        rdToken_totalSupply      = _toInt256(rdToken.totalSupply());
        rdToken_freeAssets       = _toInt256(rdToken.freeAssets());
        rdToken_totalAssets      = _toInt256(rdToken.totalAssets());
        rdToken_convertToAssets  = _toInt256(rdToken.convertToAssets(sampleSharesToConvert));
        rdToken_convertToShares  = _toInt256(rdToken.convertToShares(sampleAssetsToConvert));
        rdToken_issuanceRate     = _toInt256(rdToken.issuanceRate());
        rdToken_lastUpdated      = _toInt256(rdToken.lastUpdated());

        asset_balanceOf_staker         = _toInt256(asset.balanceOf(staker_));
        asset_balanceOf_rdToken        = _toInt256(asset.balanceOf(address(rdToken)));
        asset_nonces                   = _toInt256(asset.nonces(staker_));
        asset_allowance_staker_rdToken = _toInt256(asset.allowance(staker_, address(rdToken)));

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(depositAmount_, staker_, address(rdToken), stakerPrivateKey_, deadline);
        vm.prank(staker_);
        uint256 shares = rdToken.depositWithPermit(depositAmount_, staker_, deadline, v, r, s);

        assertEq(shares, rdToken.balanceOf(staker_));

        _assertWithinOne(rdToken.balanceOf(staker_),                     _toUint256(rdToken_balanceOf_staker + rdToken_balanceOf_staker_change));
        _assertWithinOne(rdToken.totalSupply(),                          _toUint256(rdToken_totalSupply      + rdToken_totalSupply_change));
        _assertWithinOne(rdToken.freeAssets(),                           _toUint256(rdToken_freeAssets       + rdToken_freeAssets_change));
        _assertWithinOne(rdToken.totalAssets(),                          _toUint256(rdToken_totalAssets      + rdToken_totalAssets_change));
        _assertWithinOne(rdToken.convertToAssets(sampleSharesToConvert), _toUint256(rdToken_convertToAssets  + rdToken_convertToAssets_change));
        _assertWithinOne(rdToken.convertToShares(sampleAssetsToConvert), _toUint256(rdToken_convertToShares  + rdToken_convertToShares_change));
        _assertWithinOne(rdToken.issuanceRate(),                         _toUint256(rdToken_issuanceRate     + rdToken_issuanceRate_change));

        assertEq(rdToken.lastUpdated(), _toUint256(rdToken_lastUpdated + rdToken_lastUpdated_change));

        _assertWithinOne(asset.balanceOf(staker_),          _toUint256(asset_balanceOf_staker  + asset_balanceOf_staker_change));
        _assertWithinOne(asset.balanceOf(address(rdToken)), _toUint256(asset_balanceOf_rdToken + asset_balanceOf_rdToken_change));

        assertEq(asset.allowance(staker_, address(rdToken)), _toUint256(asset_allowance_staker_rdToken + asset_allowance_staker_rdToken_change));
        assertEq(asset.nonces(staker_),                      _toUint256(asset_nonces                   + asset_nonces_change));
    }

    function _assertMintWithPermit(address staker_, uint256 stakerPrivateKey_, uint256 mintAmount_, uint256 maxAssets_) internal {
        mintAmount_ = constrictToRange(mintAmount_, 1, 1e29);

        asset.mint(staker_, mintAmount_);

        rdToken_balanceOf_staker = _toInt256(rdToken.balanceOf(staker_));
        rdToken_totalSupply      = _toInt256(rdToken.totalSupply());
        rdToken_freeAssets       = _toInt256(rdToken.freeAssets());
        rdToken_totalAssets      = _toInt256(rdToken.totalAssets());
        rdToken_convertToAssets  = _toInt256(rdToken.convertToAssets(sampleSharesToConvert));
        rdToken_convertToShares  = _toInt256(rdToken.convertToShares(sampleAssetsToConvert));
        rdToken_issuanceRate     = _toInt256(rdToken.issuanceRate());
        rdToken_lastUpdated      = _toInt256(rdToken.lastUpdated());

        asset_balanceOf_staker         = _toInt256(asset.balanceOf(staker_));
        asset_balanceOf_rdToken        = _toInt256(asset.balanceOf(address(rdToken)));
        asset_nonces                   = _toInt256(asset.nonces(staker_));
        asset_allowance_staker_rdToken = _toInt256(asset.allowance(staker_, address(rdToken)));

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(mintAmount_, staker_, address(rdToken), stakerPrivateKey_, deadline);
        vm.prank(staker_);
        uint256 shares = rdToken.mintWithPermit(mintAmount_, staker_, maxAssets_, deadline, v, r, s);

        assertEq(shares, rdToken.balanceOf(staker_));

        _assertWithinOne(rdToken.balanceOf(staker_),                     _toUint256(rdToken_balanceOf_staker + rdToken_balanceOf_staker_change));
        _assertWithinOne(rdToken.totalSupply(),                          _toUint256(rdToken_totalSupply      + rdToken_totalSupply_change));
        _assertWithinOne(rdToken.freeAssets(),                           _toUint256(rdToken_freeAssets       + rdToken_freeAssets_change));
        _assertWithinOne(rdToken.totalAssets(),                          _toUint256(rdToken_totalAssets      + rdToken_totalAssets_change));
        _assertWithinOne(rdToken.convertToAssets(sampleSharesToConvert), _toUint256(rdToken_convertToAssets  + rdToken_convertToAssets_change));
        _assertWithinOne(rdToken.convertToShares(sampleAssetsToConvert), _toUint256(rdToken_convertToShares  + rdToken_convertToShares_change));
        _assertWithinOne(rdToken.issuanceRate(),                         _toUint256(rdToken_issuanceRate     + rdToken_issuanceRate_change));

        assertEq(rdToken.lastUpdated(), _toUint256(rdToken_lastUpdated + rdToken_lastUpdated_change));

        _assertWithinOne(asset.balanceOf(staker_),          _toUint256(asset_balanceOf_staker  + asset_balanceOf_staker_change));
        _assertWithinOne(asset.balanceOf(address(rdToken)), _toUint256(asset_balanceOf_rdToken + asset_balanceOf_rdToken_change));

        assertEq(asset.allowance(staker_, address(rdToken)), _toUint256(asset_allowance_staker_rdToken + asset_allowance_staker_rdToken_change));
        assertEq(asset.nonces(staker_),                      _toUint256(asset_nonces                   + asset_nonces_change));
    }

        function _assertDeposit(address staker_, uint256 depositAmount_) internal {
        depositAmount_ = constrictToRange(depositAmount_, 1, 1e29);

        asset.mint(staker_, depositAmount_);

        Staker(staker_).erc20_approve(address(asset), address(rdToken), depositAmount_);

        rdToken_balanceOf_staker = _toInt256(rdToken.balanceOf(staker_));
        rdToken_totalSupply      = _toInt256(rdToken.totalSupply());
        rdToken_freeAssets       = _toInt256(rdToken.freeAssets());
        rdToken_totalAssets      = _toInt256(rdToken.totalAssets());
        rdToken_convertToAssets  = _toInt256(rdToken.convertToAssets(sampleSharesToConvert));
        rdToken_convertToShares  = _toInt256(rdToken.convertToShares(sampleAssetsToConvert));
        rdToken_issuanceRate     = _toInt256(rdToken.issuanceRate());
        rdToken_lastUpdated      = _toInt256(rdToken.lastUpdated());

        asset_balanceOf_staker         = _toInt256(asset.balanceOf(staker_));
        asset_balanceOf_rdToken        = _toInt256(asset.balanceOf(address(rdToken)));
        asset_allowance_staker_rdToken = _toInt256(asset.allowance(staker_, address(rdToken)));

        uint256 shares = Staker(staker_).rdToken_deposit(address(rdToken), depositAmount_);

        assertEq(shares, rdToken.balanceOf(staker_));

        _assertWithinOne(rdToken.balanceOf(staker_),                     _toUint256(rdToken_balanceOf_staker + rdToken_balanceOf_staker_change));
        _assertWithinOne(rdToken.totalSupply(),                          _toUint256(rdToken_totalSupply      + rdToken_totalSupply_change));
        _assertWithinOne(rdToken.freeAssets(),                           _toUint256(rdToken_freeAssets       + rdToken_freeAssets_change));
        _assertWithinOne(rdToken.totalAssets(),                          _toUint256(rdToken_totalAssets      + rdToken_totalAssets_change));
        _assertWithinOne(rdToken.convertToAssets(sampleSharesToConvert), _toUint256(rdToken_convertToAssets  + rdToken_convertToAssets_change));
        _assertWithinOne(rdToken.convertToShares(sampleAssetsToConvert), _toUint256(rdToken_convertToShares  + rdToken_convertToShares_change));
        _assertWithinOne(rdToken.issuanceRate(),                         _toUint256(rdToken_issuanceRate     + rdToken_issuanceRate_change));

        assertEq(rdToken.lastUpdated(), _toUint256(rdToken_lastUpdated + rdToken_lastUpdated_change));

        _assertWithinOne(asset.balanceOf(staker_),          _toUint256(asset_balanceOf_staker  + asset_balanceOf_staker_change));
        _assertWithinOne(asset.balanceOf(address(rdToken)), _toUint256(asset_balanceOf_rdToken + asset_balanceOf_rdToken_change));

        assertEq(asset.allowance(staker_, address(rdToken)), _toUint256(asset_allowance_staker_rdToken + asset_allowance_staker_rdToken_change));
    }

    function _assertMint(address staker_, uint256 mintAmount_) internal {
        mintAmount_ = constrictToRange(mintAmount_, 1, 1e29);

        asset.mint(staker_, mintAmount_);

        Staker(staker_).erc20_approve(address(asset), address(rdToken), mintAmount_);

        rdToken_balanceOf_staker = _toInt256(rdToken.balanceOf(staker_));
        rdToken_totalSupply      = _toInt256(rdToken.totalSupply());
        rdToken_freeAssets       = _toInt256(rdToken.freeAssets());
        rdToken_totalAssets      = _toInt256(rdToken.totalAssets());
        rdToken_convertToAssets  = _toInt256(rdToken.convertToAssets(sampleSharesToConvert));
        rdToken_convertToShares  = _toInt256(rdToken.convertToShares(sampleAssetsToConvert));
        rdToken_issuanceRate     = _toInt256(rdToken.issuanceRate());
        rdToken_lastUpdated      = _toInt256(rdToken.lastUpdated());

        asset_balanceOf_staker         = _toInt256(asset.balanceOf(staker_));
        asset_balanceOf_rdToken        = _toInt256(asset.balanceOf(address(rdToken)));
        asset_allowance_staker_rdToken = _toInt256(asset.allowance(staker_, address(rdToken)));

        uint256 shares = Staker(staker_).rdToken_mint(address(rdToken), mintAmount_);

        assertEq(shares, rdToken.balanceOf(staker_));

        _assertWithinOne(rdToken.balanceOf(staker_),                     _toUint256(rdToken_balanceOf_staker + rdToken_balanceOf_staker_change));
        _assertWithinOne(rdToken.totalSupply(),                          _toUint256(rdToken_totalSupply      + rdToken_totalSupply_change));
        _assertWithinOne(rdToken.freeAssets(),                           _toUint256(rdToken_freeAssets       + rdToken_freeAssets_change));
        _assertWithinOne(rdToken.totalAssets(),                          _toUint256(rdToken_totalAssets      + rdToken_totalAssets_change));
        _assertWithinOne(rdToken.convertToAssets(sampleSharesToConvert), _toUint256(rdToken_convertToAssets  + rdToken_convertToAssets_change));
        _assertWithinOne(rdToken.convertToShares(sampleAssetsToConvert), _toUint256(rdToken_convertToShares  + rdToken_convertToShares_change));
        _assertWithinOne(rdToken.issuanceRate(),                         _toUint256(rdToken_issuanceRate     + rdToken_issuanceRate_change));

        assertEq(rdToken.lastUpdated(), _toUint256(rdToken_lastUpdated + rdToken_lastUpdated_change));

        _assertWithinOne(asset.balanceOf(staker_),          _toUint256(asset_balanceOf_staker  + asset_balanceOf_staker_change));
        _assertWithinOne(asset.balanceOf(address(rdToken)), _toUint256(asset_balanceOf_rdToken + asset_balanceOf_rdToken_change));

        assertEq(asset.allowance(staker_, address(rdToken)), _toUint256(asset_allowance_staker_rdToken + asset_allowance_staker_rdToken_change));
    }

    function _assertWithdraw(address staker_, uint256 withdrawAmount_) internal {
        uint256 maxWithdrawAmount = rdToken.previewRedeem(rdToken.balanceOf(staker_));

        withdrawAmount_ = constrictToRange(withdrawAmount_, 1, maxWithdrawAmount);

        rdToken_balanceOf_staker = _toInt256(rdToken.balanceOf(staker_));
        rdToken_totalSupply      = _toInt256(rdToken.totalSupply());
        rdToken_freeAssets       = _toInt256(rdToken.freeAssets());
        rdToken_totalAssets      = _toInt256(rdToken.totalAssets());
        rdToken_convertToAssets  = _toInt256(rdToken.convertToAssets(sampleSharesToConvert));
        rdToken_convertToShares  = _toInt256(rdToken.convertToShares(sampleAssetsToConvert));
        rdToken_issuanceRate     = _toInt256(rdToken.issuanceRate());
        rdToken_lastUpdated      = _toInt256(rdToken.lastUpdated());

        asset_balanceOf_staker         = _toInt256(asset.balanceOf(staker_));
        asset_balanceOf_rdToken        = _toInt256(asset.balanceOf(address(rdToken)));
        asset_allowance_staker_rdToken = _toInt256(asset.allowance(staker_, address(rdToken)));

        uint256 shares = Staker(staker_).rdToken_withdraw(address(rdToken), withdrawAmount_);

        assertEq(shares, _toUint256(-rdToken_balanceOf_staker_change));  // Number of shares burned

        _assertWithinOne(rdToken.balanceOf(staker_),                     _toUint256(rdToken_balanceOf_staker + rdToken_balanceOf_staker_change));
        _assertWithinOne(rdToken.totalSupply(),                          _toUint256(rdToken_totalSupply      + rdToken_totalSupply_change));
        _assertWithinOne(rdToken.freeAssets(),                           _toUint256(rdToken_freeAssets       + rdToken_freeAssets_change));
        _assertWithinOne(rdToken.totalAssets(),                          _toUint256(rdToken_totalAssets      + rdToken_totalAssets_change));
        _assertWithinOne(rdToken.convertToAssets(sampleSharesToConvert), _toUint256(rdToken_convertToAssets  + rdToken_convertToAssets_change));
        _assertWithinOne(rdToken.convertToShares(sampleAssetsToConvert), _toUint256(rdToken_convertToShares  + rdToken_convertToShares_change));
        _assertWithinOne(rdToken.issuanceRate(),                         _toUint256(rdToken_issuanceRate     + rdToken_issuanceRate_change));

        assertEq(rdToken.lastUpdated(), _toUint256(rdToken_lastUpdated + rdToken_lastUpdated_change));

        _assertWithinOne(asset.balanceOf(staker_),          _toUint256(asset_balanceOf_staker  + asset_balanceOf_staker_change));
        _assertWithinOne(asset.balanceOf(address(rdToken)), _toUint256(asset_balanceOf_rdToken + asset_balanceOf_rdToken_change));

        assertEq(asset.allowance(staker_, address(rdToken)), _toUint256(asset_allowance_staker_rdToken + asset_allowance_staker_rdToken_change));
    }

    function _assertRedeem(address staker_, uint256 redeemAmount_) internal {
        uint256 maxWithdrawAmount = rdToken.previewRedeem(rdToken.balanceOf(staker_));

        redeemAmount_ = constrictToRange(redeemAmount_, 1, maxWithdrawAmount);

        rdToken_balanceOf_staker = _toInt256(rdToken.balanceOf(staker_));
        rdToken_totalSupply      = _toInt256(rdToken.totalSupply());
        rdToken_freeAssets       = _toInt256(rdToken.freeAssets());
        rdToken_totalAssets      = _toInt256(rdToken.totalAssets());
        rdToken_convertToAssets  = _toInt256(rdToken.convertToAssets(sampleSharesToConvert));
        rdToken_convertToShares  = _toInt256(rdToken.convertToShares(sampleAssetsToConvert));
        rdToken_issuanceRate     = _toInt256(rdToken.issuanceRate());
        rdToken_lastUpdated      = _toInt256(rdToken.lastUpdated());

        asset_balanceOf_staker         = _toInt256(asset.balanceOf(staker_));
        asset_balanceOf_rdToken        = _toInt256(asset.balanceOf(address(rdToken)));
        asset_allowance_staker_rdToken = _toInt256(asset.allowance(staker_, address(rdToken)));

        uint256 shares = Staker(staker_).rdToken_withdraw(address(rdToken), redeemAmount_);

        assertEq(shares, _toUint256(-rdToken_balanceOf_staker_change));  // Number of shares burned

        _assertWithinOne(rdToken.balanceOf(staker_),                     _toUint256(rdToken_balanceOf_staker + rdToken_balanceOf_staker_change));
        _assertWithinOne(rdToken.totalSupply(),                          _toUint256(rdToken_totalSupply      + rdToken_totalSupply_change));
        _assertWithinOne(rdToken.freeAssets(),                           _toUint256(rdToken_freeAssets       + rdToken_freeAssets_change));
        _assertWithinOne(rdToken.totalAssets(),                          _toUint256(rdToken_totalAssets      + rdToken_totalAssets_change));
        _assertWithinOne(rdToken.convertToAssets(sampleSharesToConvert), _toUint256(rdToken_convertToAssets  + rdToken_convertToAssets_change));
        _assertWithinOne(rdToken.convertToShares(sampleAssetsToConvert), _toUint256(rdToken_convertToShares  + rdToken_convertToShares_change));
        _assertWithinOne(rdToken.issuanceRate(),                         _toUint256(rdToken_issuanceRate     + rdToken_issuanceRate_change));

        assertEq(rdToken.lastUpdated(), _toUint256(rdToken_lastUpdated + rdToken_lastUpdated_change));

        _assertWithinOne(asset.balanceOf(staker_),          _toUint256(asset_balanceOf_staker  + asset_balanceOf_staker_change));
        _assertWithinOne(asset.balanceOf(address(rdToken)), _toUint256(asset_balanceOf_rdToken + asset_balanceOf_rdToken_change));

        assertEq(asset.allowance(staker_, address(rdToken)), _toUint256(asset_allowance_staker_rdToken + asset_allowance_staker_rdToken_change));
    }

    function _assertWithinOne(uint256 expected_, uint256 actual_) internal {
        assertWithinDiff(actual_, expected_, 1);
    }

    function _toInt256(uint256 unsigned_) internal pure returns (int256 signed_) {
        signed_ = int256(unsigned_);
        require(signed_ >= 0, "TO_INT256_OVERFLOW");
    }

    function _toUint256(int256 signed_) internal pure returns (uint256 _unsigned) {
        require(signed_ >= 0, "TO_UINT256_NEGATIVE");
        return uint256(signed_);
    }
}

contract DepositAndMintWithPermitTest is RDTSuccessTestBase {

    function test_depositWithPermit_singleUser_noVesting() external {
        rdToken_balanceOf_staker_change = 1000;
        rdToken_totalSupply_change      = 1000;
        rdToken_freeAssets_change       = 1000;
        rdToken_totalAssets_change      = 1000;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = 10_000_000;  // First deposit updates `lastUpdated`

        asset_balanceOf_staker_change         = -1000;
        asset_balanceOf_rdToken_change        = 1000;
        asset_nonces_change                   = 1;
        asset_allowance_staker_rdToken_change = 0;

        address staker = vm.addr(1);

        _assertDepositWithPermit(staker, 1, 1000);
    }

    function test_mintWithPermit_singleUser_noVesting() external {
        rdToken_balanceOf_staker_change = 1000;
        rdToken_totalSupply_change      = 1000;
        rdToken_freeAssets_change       = 1000;
        rdToken_totalAssets_change      = 1000;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = 10_000_000;  // First deposit updates `lastUpdated`

        asset_balanceOf_staker_change         = -1000;
        asset_balanceOf_rdToken_change        = 1000;
        asset_nonces_change                   = 1;
        asset_allowance_staker_rdToken_change = 0;

        address staker = vm.addr(1);

        _assertMintWithPermit(staker, 1, 1000, 1000);
    }

}

contract APRViewTest is RDTTestBase {

    Owner  owner;
    Staker staker;

    function setUp() public override {
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

        Staker staker = new Staker();
        asset.mint(address(staker), 1);
        staker.erc20_approve(address(asset), address(rdToken), 1);
        staker.rdToken_deposit(address(rdToken), 1);

        asset.mint(address(rdToken), 1000);

        vm.expectRevert("RDT:UVS:NOT_OWNER");
        notOwner.rdToken_updateVestingSchedule(address(rdToken), 100 seconds);

        assertEq(rdToken.freeAssets(),          1);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         10_000);
        assertEq(rdToken.vestingPeriodFinish(), 0);

        owner.rdToken_updateVestingSchedule(address(rdToken), 100 seconds);

        assertEq(rdToken.freeAssets(),          1);
        assertEq(rdToken.issuanceRate(),        10e30);
        assertEq(rdToken.lastUpdated(),         10_000);
        assertEq(rdToken.vestingPeriodFinish(), 10_100);
    }

}

contract DepositAndMintFailureModeTest is RDTTestBase {

    Staker staker;

    function setUp() public override {
        super.setUp();
        staker = new Staker();
    }

    /************************************/
    /*** `deposit` Failure Mode Tests ***/
    /************************************/

    function test_deposit_zeroAssets() external {

        asset.mint(address(staker), 1);
        staker.erc20_approve(address(asset), address(rdToken), 1);

        vm.expectRevert("RDT:M:ZERO_SHARES");
        staker.rdToken_deposit(address(rdToken), 0);

        staker.rdToken_deposit(address(rdToken), 1);
    }

    function test_deposit_badApprove(uint256 depositAmount) external {

        depositAmount = constrictToRange(depositAmount, 1, 1e29);

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount - 1);

        vm.expectRevert("RDT:M:TRANSFER_FROM");
        staker.rdToken_deposit(address(rdToken), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);
    }

    function test_deposit_insufficientBalance(uint256 depositAmount) external {

        depositAmount = constrictToRange(depositAmount, 1, 1e29);

        asset.mint(address(staker), depositAmount);
        staker.erc20_approve(address(asset), address(rdToken), depositAmount + 1);

        vm.expectRevert("RDT:M:TRANSFER_FROM");
        staker.rdToken_deposit(address(rdToken), depositAmount + 1);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);
    }

    function test_deposit_zeroShares() external {
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
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          block.timestamp);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount);
    }

    /*********************************/
    /*** `mint` Failure Mode Tests ***/
    /*********************************/

    function test_mint_zeroAmount() external {

        asset.mint(address(staker), 1);
        staker.erc20_approve(address(asset), address(rdToken), 1);

        vm.expectRevert("RDT:M:ZERO_SHARES");
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
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleAssetsToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          block.timestamp);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), assets);
    }

    function test_deposit_totalAssetsGtTotalSupply_explicitValues() external {
        /*************/
        /*** Setup ***/
        /*************/

        uint256 START = block.timestamp;

        // Do a deposit so that totalSupply is non-zero
        asset.mint(address(this), 20e18);
        asset.approve(address(rdToken), 20e18);
        rdToken.deposit(20e18, address(this));

        _transferAndUpdateVesting(5e18, 10 seconds);

        vm.warp(START + 11 seconds);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

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
        assertEq(rdToken.lastUpdated(),                          START);

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
        assertEq(rdToken.lastUpdated(),                          START + 11 seconds);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), 35e18);
    }

    function test_deposit_totalAssetsGtTotalSupply(uint256 initialAmount, uint256 depositAmount, uint256 vestingAmount) external {
        /*************/
        /*** Setup ***/
        /*************/

        initialAmount = constrictToRange(initialAmount, 1, 1e29);
        vestingAmount = constrictToRange(vestingAmount, 1, 1e29);

        // Since this is a test where totalAssets > totalSupply, need to ensure deposit amount is at least minimum to avoid 0 shares after conversion.
        uint256 minDeposit = (initialAmount + vestingAmount - 1) / initialAmount + 1;
        depositAmount      = constrictToRange(depositAmount, minDeposit, 1e29 + 1);  // + 1 since we round up in min deposit.

        // Do a deposit so that totalSupply is non-zero
        asset.mint(address(this), initialAmount);
        asset.approve(address(rdToken), initialAmount);
        uint256 initialShares = rdToken.deposit(initialAmount, address(this));

        uint256 START = block.timestamp;

        _transferAndUpdateVesting(vestingAmount, 10 seconds);

        vm.warp(START + 11 seconds);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting


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
        assertEq(rdToken.lastUpdated(),                          START);

        assertEq(asset.balanceOf(address(rdToken)), initialAmount + vestingAmount);

        /***************/
        /*** Deposit ***/
        /***************/

        asset.mint(address(staker), depositAmount);
        assertEq(asset.balanceOf(address(staker)),  depositAmount);

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
        assertEq(rdToken.lastUpdated(),                          START + 11 seconds);

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

contract DepositAndMintTest is RDTSuccessTestBase {

    function test_deposit_singleUser_noVesting() external {
        rdToken_balanceOf_staker_change = 1000;
        rdToken_totalSupply_change      = 1000;
        rdToken_freeAssets_change       = 1000;
        rdToken_totalAssets_change      = 1000;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = 10_000_000;  // First deposit updates `lastUpdated`

        asset_balanceOf_staker_change         = -1000;
        asset_balanceOf_rdToken_change        = 1000;
        asset_allowance_staker_rdToken_change = -1000;

        address staker = address(new Staker());

        _assertDeposit(staker, 1000);
    }

    function test_mint_singleUser_noVesting() external {
        rdToken_balanceOf_staker_change = 1000;
        rdToken_totalSupply_change      = 1000;
        rdToken_freeAssets_change       = 1000;
        rdToken_totalAssets_change      = 1000;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = 10_000_000;  // First deposit updates `lastUpdated`

        asset_balanceOf_staker_change         = -1000;
        asset_balanceOf_rdToken_change        = 1000;
        asset_allowance_staker_rdToken_change = -1000;

        address staker = address(new Staker());

        _assertMint(staker, 1000);
    }

}

contract RedeemAndWithdrawFailureModeTest is RDTTestBase {

    Staker staker;

    function setUp() public override {
        super.setUp();
        staker = new Staker();
    }

    /*************************************/
    /*** `withdraw` Failure Mode Tests ***/
    /*************************************/

    function test_withdraw_zeroAmount(uint256 depositAmount) external {
        _depositAsset(constrictToRange(depositAmount, 1, 1e29));

        vm.expectRevert("RDT:B:ZERO_SHARES");
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

    function test_withdraw_burnUnderflow_totalAssetsGtTotalSupply_explicitValues() external {
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

    /********************************/
    /*** `withdraw` Success Tests ***/
    /********************************/

    function test_withdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount  = constrictToRange(depositAmount,  1, 1e29);
        withdrawAmount = constrictToRange(withdrawAmount, 1, depositAmount);

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        uint256 START = block.timestamp;

        assertEq(rdToken.balanceOf(address(staker)),             depositAmount);
        assertEq(rdToken.totalSupply(),                          depositAmount);
        assertEq(rdToken.freeAssets(),                           depositAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          START);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount);

        vm.warp(START + 10 days);

        staker.rdToken_withdraw(address(rdToken), withdrawAmount);

        assertEq(rdToken.balanceOf(address(staker)),             depositAmount - withdrawAmount);
        assertEq(rdToken.totalSupply(),                          depositAmount - withdrawAmount);
        assertEq(rdToken.freeAssets(),                           depositAmount - withdrawAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount - withdrawAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          START + 10 days);

        assertEq(asset.balanceOf(address(staker)),  withdrawAmount);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount - withdrawAmount);
    }

    function test_withdraw_totalAssetsGtTotalSupply_explicitValues() public {
        uint256 depositAmount  = 100e18;
        uint256 withdrawAmount = 20e18;
        uint256 vestingAmount  = 10e18;
        uint256 vestingPeriod  = 200 seconds;
        uint256 warpTime       = 100 seconds;
        uint256 START          = block.timestamp;

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
        assertEq(rdToken.lastUpdated(),                          START);

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
        assertEq(rdToken.lastUpdated(),                          START + 100 seconds);

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

        depositAmount  = constrictToRange(depositAmount,  1, 1e29);
        withdrawAmount = constrictToRange(withdrawAmount, 1, depositAmount);
        vestingAmount  = constrictToRange(vestingAmount,  1, 1e29);
        vestingPeriod  = constrictToRange(vestingPeriod,  1, 100 days);
        warpTime       = constrictToRange(warpTime,       1, vestingPeriod);


        uint256 START = block.timestamp;


        _depositAsset(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        assertEq(rdToken.balanceOf(address(staker)), depositAmount);
        assertEq(rdToken.totalSupply(),              depositAmount);
        assertEq(rdToken.freeAssets(),               depositAmount);
        assertEq(rdToken.lastUpdated(),              START);

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
        assertEq(rdToken.lastUpdated(),              START + warpTime);

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

        uint256 START = block.timestamp;

        assertEq(rdToken.balanceOf(address(staker)),             depositAmount);
        assertEq(rdToken.totalSupply(),                          depositAmount);
        assertEq(rdToken.freeAssets(),                           depositAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          START);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount);

        vm.warp(START + 10 days);

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
        assertEq(rdToken.lastUpdated(),                          START + 10 days);

        assertEq(asset.balanceOf(address(staker)),        0);
        assertEq(asset.balanceOf(address(notShareOwner)), withdrawAmount);  // notShareOwner received the assets.
        assertEq(asset.balanceOf(address(rdToken)),       depositAmount - withdrawAmount);
    }

    function test_withdraw_callerNotOwner_totalAssetsGtTotalSupply_explicitValues() public {
        uint256 depositAmount  = 100e18;
        uint256 withdrawAmount = 20e18;
        uint256 vestingAmount  = 10e18;
        uint256 vestingPeriod  = 200 seconds;
        uint256 warpTime       = 100 seconds;
        uint256 START          = block.timestamp;

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
        assertEq(rdToken.lastUpdated(),                          START);

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
        assertEq(rdToken.lastUpdated(),                          START + 100 seconds);

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
        depositAmount  = constrictToRange(depositAmount,  1, 1e29);
        withdrawAmount = constrictToRange(withdrawAmount, 1, depositAmount);
        vestingAmount  = constrictToRange(vestingAmount,  1, 1e29);
        vestingPeriod  = constrictToRange(vestingPeriod,  1, 100 days);
        warpTime       = constrictToRange(warpTime,       1, vestingPeriod);

        uint256 START = block.timestamp;

        _depositAsset(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        assertEq(rdToken.balanceOf(address(staker)), depositAmount);
        assertEq(rdToken.totalSupply(),              depositAmount);
        assertEq(rdToken.freeAssets(),               depositAmount);
        assertEq(rdToken.lastUpdated(),              START);

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
        assertEq(rdToken.lastUpdated(),              START + warpTime);

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


    /***********************************/
    /*** `redeem` Failure Mode Tests ***/
    /***********************************/

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

    /********************************/
    /*** `redeem` Success Tests ***/
    /********************************/

    function test_redeem(uint256 depositAmount, uint256 redeemAmount) public {
        depositAmount = constrictToRange(depositAmount, 1, 1e29);
        redeemAmount  = constrictToRange(redeemAmount,  1, depositAmount);

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        uint256 START = block.timestamp;

        assertEq(rdToken.balanceOf(address(staker)),             depositAmount);
        assertEq(rdToken.totalSupply(),                          depositAmount);
        assertEq(rdToken.freeAssets(),                           depositAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          START);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount);

        vm.warp(START + 10 days);

        staker.rdToken_redeem(address(rdToken), redeemAmount);

        assertEq(rdToken.balanceOf(address(staker)),             depositAmount - redeemAmount);
        assertEq(rdToken.totalSupply(),                          depositAmount - redeemAmount);
        assertEq(rdToken.freeAssets(),                           depositAmount - redeemAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount - redeemAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          START + 10 days);

        assertEq(asset.balanceOf(address(staker)),  redeemAmount);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount - redeemAmount);
    }

    function test_redeem_totalAssetsGtTotalSupply_explicitValues() public {
        uint256 depositAmount = 100e18;
        uint256 redeemAmount  = 20e18;
        uint256 vestingAmount = 10e18;
        uint256 vestingPeriod = 200 seconds;
        uint256 warpTime      = 100 seconds;
        uint256 START         = block.timestamp;

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
        assertEq(rdToken.lastUpdated(),                          START);

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
        assertEq(rdToken.lastUpdated(),                          START + 100 seconds);

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

        uint256 START = block.timestamp;

        _depositAsset(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        assertEq(rdToken.balanceOf(address(staker)), depositAmount);
        assertEq(rdToken.totalSupply(),              depositAmount);
        assertEq(rdToken.freeAssets(),               depositAmount);
        assertEq(rdToken.lastUpdated(),              START);

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
        assertEq(rdToken.lastUpdated(),              START + warpTime);

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

        uint256 START = block.timestamp;

        assertEq(rdToken.balanceOf(address(staker)),             depositAmount);
        assertEq(rdToken.totalSupply(),                          depositAmount);
        assertEq(rdToken.freeAssets(),                           depositAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0);
        assertEq(rdToken.lastUpdated(),                          START);

        assertEq(asset.balanceOf(address(staker)),  0);
        assertEq(asset.balanceOf(address(rdToken)), depositAmount);

        vm.warp(START + 10 days);

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
        assertEq(rdToken.lastUpdated(),                          START + 10 days);

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
        uint256 START         = block.timestamp;

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
        assertEq(rdToken.lastUpdated(),                          START);

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
        assertEq(rdToken.lastUpdated(),                          START + 100 seconds);

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

        uint256 START = block.timestamp;

        _depositAsset(depositAmount);
        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        assertEq(rdToken.balanceOf(address(staker)), depositAmount);
        assertEq(rdToken.totalSupply(),              depositAmount);
        assertEq(rdToken.freeAssets(),               depositAmount);
        assertEq(rdToken.lastUpdated(),              START);

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
        assertEq(rdToken.lastUpdated(),              START + warpTime);

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

contract RedeemAndWithdrawTest is RDTSuccessTestBase {

    // TODO: Change names
    function test_withdraw_totalAssetsGtTotalSupply_explicitValues() external {
        address staker = address(new Staker());

        _depositAsset(address(asset), staker, 100e18);
        _transferAndUpdateVesting(address(asset), address(rdToken), 10e18, 200 seconds);

        vm.warp(block.timestamp + 100 seconds);  // Vest 5e18 tokens

        rdToken_balanceOf_staker_change = -19.047619047619047620e18;  // 20 / 1.05
        rdToken_totalSupply_change      = -19.047619047619047620e18;  // 20 / 1.05
        rdToken_freeAssets_change       = -15e18;  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw
        rdToken_totalAssets_change      = -20e18;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = 100 seconds;

        asset_balanceOf_staker_change         = 20e18;
        asset_balanceOf_rdToken_change        = -20e18;
        asset_allowance_staker_rdToken_change = 0;

        _assertWithdraw(staker, 20e18);
    }

    function test_withdraw_singleUser_noVesting() external {
        address staker = address(new Staker());

        _depositAsset(address(asset), staker, 1000);

        rdToken_balanceOf_staker_change = -1000;
        rdToken_totalSupply_change      = -1000;
        rdToken_freeAssets_change       = -1000;
        rdToken_totalAssets_change      = -1000;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = 0;

        asset_balanceOf_staker_change         = 1000;
        asset_balanceOf_rdToken_change        = -1000;
        asset_allowance_staker_rdToken_change = 0;

        _assertWithdraw(staker, 1000);
    }

    function test_redeem_singleUser_noVesting() external {
        address staker = address(new Staker());

        _depositAsset(address(asset), staker, 1000);

        rdToken_balanceOf_staker_change = -1000;
        rdToken_totalSupply_change      = -1000;
        rdToken_freeAssets_change       = -1000;
        rdToken_totalAssets_change      = -1000;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = 0;

        asset_balanceOf_staker_change         = 1000;
        asset_balanceOf_rdToken_change        = -1000;
        asset_allowance_staker_rdToken_change = 0;

        _assertRedeem(staker, 1000);
    }

}

contract RevenueStreamingTest is RDTTestBase {

    Staker firstStaker;

    uint256 startingAssets;

    function setUp() public override {
        super.setUp();
        firstStaker = new Staker();

        // Deposit the minimum amount of the asset to allow the vesting schedule updates to occur.
        startingAssets = 1;
        asset.mint(address(firstStaker), startingAssets);
        firstStaker.erc20_approve(address(asset), address(rdToken), startingAssets);
        firstStaker.rdToken_deposit(address(rdToken), startingAssets);
    }

    function test_updateVestingSchedule_zeroSupply() external {
        firstStaker.rdToken_withdraw(address(rdToken), 1);

        vm.expectRevert("RDT:UVS:ZERO_SUPPLY");
        rdToken.updateVestingSchedule(100 seconds);

        firstStaker.erc20_approve(address(asset), address(rdToken), 1);
        firstStaker.rdToken_deposit(address(rdToken), 1);

        rdToken.updateVestingSchedule(100 seconds);
    }

    /************************************/
    /*** Single updateVestingSchedule ***/
    /************************************/

    function test_updateVestingSchedule_single() external {
        assertEq(rdToken.freeAssets(),          startingAssets);
        assertEq(rdToken.totalAssets(),         startingAssets);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         START);
        assertEq(rdToken.vestingPeriodFinish(), 0);

        assertEq(asset.balanceOf(address(rdToken)), startingAssets);

        _transferAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        assertEq(asset.balanceOf(address(rdToken)), startingAssets + 1000);

        assertEq(rdToken.freeAssets(),                           startingAssets);
        assertEq(rdToken.totalAssets(),                          startingAssets);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         10e30);  // 10 tokens per second
        assertEq(rdToken.lastUpdated(),                          START);
        assertEq(rdToken.vestingPeriodFinish(),                  START + 100 seconds);

        vm.warp(rdToken.vestingPeriodFinish());

        assertEq(rdToken.totalAssets(), startingAssets + 1000);  // All tokens vested
    }

    function test_updateVestingSchedule_single_roundingDown() external {
        _transferAndUpdateVesting(1000, 30 seconds);  // 33.3333... tokens per second

        assertEq(rdToken.totalAssets(),  startingAssets);
        assertEq(rdToken.issuanceRate(), 33333333333333333333333333333333);  // 3.33e30

        // totalAssets should never be more than one full unit off
        vm.warp(START + 1 seconds);
        assertEq(rdToken.totalAssets(), startingAssets + 33);  // 33 < 33.33...

        vm.warp(START + 2 seconds);
        assertEq(rdToken.totalAssets(), startingAssets + 66);  // 66 < 66.66...

        vm.warp(START + 3 seconds);
        assertEq(rdToken.totalAssets(), startingAssets + 99);  // 99 < 99.99...

        vm.warp(START + 4 seconds);
        assertEq(rdToken.totalAssets(), startingAssets + 133);  // 133 < 133.33...

        vm.warp(rdToken.vestingPeriodFinish());
        assertEq(rdToken.totalAssets(), startingAssets + 999);  // 999 < 1000
    }

    /*************************************************/
    /*** Multiple updateVestingSchedule, same time ***/
    /*************************************************/

    function test_updateVestingSchedule_sameTime_shorterVesting() external {
        _transferAndUpdateVesting(1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), START + 100 seconds);  // Always updates to latest vesting schedule

        _transferAndUpdateVesting(1000, 20 seconds);
        assertEq(rdToken.issuanceRate(),        100e30);              // (1000 + 1000) / 20 seconds = 100 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), START + 20 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalAssets(), startingAssets);

        vm.warp(START + 20 seconds);

        assertEq(rdToken.totalAssets(), startingAssets + 2000);
    }

    function test_updateVestingSchedule_sameTime_longerVesting_higherRate() external {
        _transferAndUpdateVesting(1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), START + 100 seconds);  // Always updates to latest vesting schedule

        _transferAndUpdateVesting(3000, 200 seconds);
        assertEq(rdToken.issuanceRate(),        20e30);                // (3000 + 1000) / 200 seconds = 20 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), START + 200 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalAssets(), startingAssets);

        vm.warp(START + 200 seconds);

        assertEq(rdToken.totalAssets(), startingAssets + 4000);
    }

    function test_updateVestingSchedule_sameTime_longerVesting_lowerRate() external {
        _transferAndUpdateVesting(1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), START + 100 seconds);  // Always updates to latest vesting schedule

        _transferAndUpdateVesting(1000, 500 seconds);
        assertEq(rdToken.issuanceRate(),        4e30);                 // (1000 + 1000) / 500 seconds = 4 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), START + 500 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalAssets(), startingAssets);

        vm.warp(START + 5000 seconds);

        assertEq(rdToken.totalAssets(), startingAssets + 2000);
    }

    /*******************************************************/
    /*** Multiple updateVestingSchedule, different times ***/
    /*******************************************************/

    function test_updateVestingSchedule_diffTime_shorterVesting() external {
        _transferAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        vm.warp(START + 60 seconds);

        assertEq(rdToken.issuanceRate(),        10e30);
        assertEq(rdToken.totalAssets(),         startingAssets + 600);
        assertEq(rdToken.freeAssets(),          startingAssets);
        assertEq(rdToken.vestingPeriodFinish(), START + 100 seconds);

        _transferAndUpdateVesting(1000, 20 seconds);  // 50 tokens per second

        assertEq(rdToken.issuanceRate(),        70e30);  // (400 + 1000) / 20 seconds = 70 tokens per second
        assertEq(rdToken.totalAssets(),         startingAssets + 600);
        assertEq(rdToken.freeAssets(),          startingAssets + 600);
        assertEq(rdToken.vestingPeriodFinish(), START + 60 seconds + 20 seconds);

        vm.warp(START + 60 seconds + 20 seconds);

        assertEq(rdToken.issuanceRate(), 70e30);
        assertEq(rdToken.totalAssets(),  startingAssets + 2000);
        assertEq(rdToken.freeAssets(),   startingAssets + 600);
    }

    function test_updateVestingSchedule_diffTime_longerVesting_higherRate() external {
        _transferAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        vm.warp(START + 60 seconds);

        assertEq(rdToken.issuanceRate(),        10e30);
        assertEq(rdToken.totalAssets(),         startingAssets + 600);
        assertEq(rdToken.freeAssets(),          startingAssets);
        assertEq(rdToken.vestingPeriodFinish(), START + 100 seconds);

        _transferAndUpdateVesting(3000, 200 seconds);  // 15 tokens per second

        assertEq(rdToken.issuanceRate(), 17e30);  // (400 + 3000) / 200 seconds = 17 tokens per second
        assertEq(rdToken.totalAssets(),  startingAssets + 600);
        assertEq(rdToken.freeAssets(),   startingAssets + 600);

        vm.warp(START + 60 seconds + 200 seconds);

        assertEq(rdToken.issuanceRate(), 17e30);
        assertEq(rdToken.totalAssets(),  startingAssets + 4000);
        assertEq(rdToken.freeAssets(),   startingAssets + 600);
    }

    function test_updateVestingSchedule_diffTime_longerVesting_lowerRate() external {
        _transferAndUpdateVesting(1000, 100 seconds);  // 10 tokens per second

        vm.warp(START + 60 seconds);

        assertEq(rdToken.issuanceRate(), 10e30);
        assertEq(rdToken.totalAssets(),  startingAssets + 600);
        assertEq(rdToken.freeAssets(),   startingAssets);

        _transferAndUpdateVesting(1000, 200 seconds);  // 5 tokens per second

        assertEq(rdToken.issuanceRate(), 7e30);  // (400 + 1000) / 200 seconds = 7 tokens per second
        assertEq(rdToken.totalAssets(),  startingAssets + 600);
        assertEq(rdToken.freeAssets(),   startingAssets + 600);

        vm.warp(START + 60 seconds + 200 seconds);

        assertEq(rdToken.issuanceRate(), 7e30);
        assertEq(rdToken.totalAssets(),  startingAssets + 2000);
        assertEq(rdToken.freeAssets(),   startingAssets + 600);
    }

    function _transferAndUpdateVesting(uint256 vestingAmount_, uint256 vestingPeriod_) internal {
        asset.mint(address(this), vestingAmount_);
        asset.transfer(address(rdToken), vestingAmount_);
        rdToken.updateVestingSchedule(vestingPeriod_);
    }

}

contract EndToEndRevenueStreamingTest is RDTTestBase {

    /********************************/
    /*** End to end vesting tests ***/
    /********************************/

    function test_vesting_singleSchedule_explicitValues() public {
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
        assertEq(rdToken.lastUpdated(),                          START);
        assertEq(rdToken.vestingPeriodFinish(),                  0);

        vm.warp(START + 1 days);

        assertEq(rdToken.totalAssets(),  1_000_000e18);  // No change

        vm.warp(START);  // Warp back after demonstrating totalAssets is not time-dependent before vesting starts

        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        assertEq(rdToken.freeAssets(),                           1_000_000e18);
        assertEq(rdToken.totalAssets(),                          1_000_000e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         0.5e18 * 1e30);  // 0.5 tokens per second
        assertEq(rdToken.lastUpdated(),                          START);
        assertEq(rdToken.vestingPeriodFinish(),                  START + vestingPeriod);

        // Warp and assert vesting in 10% increments
        vm.warp(START + 20_000 seconds);  // 10% of vesting schedule

        assertEq(rdToken.balanceOfAssets(address(staker)),       1_010_000e18);
        assertEq(rdToken.totalAssets(),                          1_010_000e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.01e18);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 9.90099009900990099e17); // Shares go down, as they are worth more assets.

        vm.warp(START + 40_000 seconds);  // 20% of vesting schedule

        assertEq(rdToken.balanceOfAssets(address(staker)),       1_020_000e18);
        assertEq(rdToken.totalAssets(),                          1_020_000e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.02e18);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 9.80392156862745098e17);

        vm.warp(START + 60_000 seconds);  // 30% of vesting schedule

        assertEq(rdToken.balanceOfAssets(address(staker)),       1_030_000e18);
        assertEq(rdToken.totalAssets(),                          1_030_000e18);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.03e18);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 9.70873786407766990e17);

        vm.warp(START + 200_000 seconds);  // End of vesting schedule

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
        assertEq(rdToken.lastUpdated(),                          START + 200_000 seconds);  // This makes issuanceRate * time zero
        assertEq(rdToken.vestingPeriodFinish(),                  START + 200_000 seconds);

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
        assertEq(rdToken.lastUpdated(),                          START);
        assertEq(rdToken.vestingPeriodFinish(),                  0);

        vm.warp(START + 1 days);

        assertEq(rdToken.totalAssets(),  depositAmount);  // No change

        vm.warp(START);  // Warp back after demonstrating totalAssets is not time-dependent before vesting starts

        _transferAndUpdateVesting(vestingAmount, vestingPeriod);

        uint256 expectedRate = vestingAmount * 1e30 / vestingPeriod;

        assertEq(rdToken.freeAssets(),                           depositAmount);
        assertEq(rdToken.totalAssets(),                          depositAmount);
        assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert);
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert);
        assertEq(rdToken.issuanceRate(),                         expectedRate);
        assertEq(rdToken.lastUpdated(),                          START);
        assertEq(rdToken.vestingPeriodFinish(),                  START + vestingPeriod);

        // Warp and assert vesting in 10% increments
        for (uint256 i = 1; i < 10; ++i) {
            vm.warp(START + vestingPeriod * i / 10);  // 10% intervals of vesting schedule

            uint256 expectedTotalAssets = depositAmount + expectedRate * (block.timestamp - START) / 1e30;

            assertWithinDiff(rdToken.balanceOfAssets(address(staker)), expectedTotalAssets, 1);

            assertEq(rdToken.totalSupply(),                          depositAmount);
            assertEq(rdToken.totalAssets(),                          expectedTotalAssets);
            assertEq(rdToken.convertToAssets(sampleSharesToConvert), sampleSharesToConvert * expectedTotalAssets / depositAmount);
            assertEq(rdToken.convertToShares(sampleAssetsToConvert), sampleAssetsToConvert * depositAmount / expectedTotalAssets);
        }

        vm.warp(START + vestingPeriod);

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
        assertEq(rdToken.lastUpdated(),                          START + vestingPeriod);  // This makes issuanceRate * time zero
        assertEq(rdToken.vestingPeriodFinish(),                  START + vestingPeriod);

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

contract RedeemRevertOnTransfer is RDTTestBase {

    MockRevertingERC20 revertingAsset;
    Staker             staker;

    function setUp() public override {
        revertingAsset = new MockRevertingERC20("MockToken", "MT", 18);
        rdToken        = new RDT("Revenue Distribution Token", "RDT", address(this), address(revertingAsset), 1e30);
        staker         = new Staker();

        vm.warp(10_000_000);  // Warp to non-zero timestamp
    }

    function test_redeem_revertOnTransfer(uint256 depositAmount, uint256 redeemAmount) public {
        depositAmount = constrictToRange(depositAmount, 1, 1e29);
        redeemAmount  = constrictToRange(redeemAmount,  1, depositAmount);

        revertingAsset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(revertingAsset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        uint256 START = block.timestamp;

        vm.warp(START + 10 days);

        vm.expectRevert(bytes("RDT:B:TRANSFER"));
        staker.rdToken_redeem(address(rdToken), depositAmount, address(0), address(staker));

        staker.rdToken_redeem(address(rdToken), depositAmount, address(1), address(staker));
    }

    function test_withdraw_revertOnTransfer(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount  = constrictToRange(depositAmount,  1, 1e29);
        withdrawAmount = constrictToRange(withdrawAmount, 1, depositAmount);

        revertingAsset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(revertingAsset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);

        uint256 START = block.timestamp;

        vm.warp(START + 10 days);

        vm.expectRevert(bytes("RDT:B:TRANSFER"));
        staker.rdToken_withdraw(address(rdToken), withdrawAmount, address(0), address(staker));

        staker.rdToken_withdraw(address(rdToken), withdrawAmount, address(1), address(staker));
    }

    function _depositAsset(uint256 depositAmount) internal {
        asset.mint(address(staker), depositAmount);
        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_deposit(address(rdToken), depositAmount);
    }
}
