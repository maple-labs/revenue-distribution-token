// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { TestUtils } from "../../modules/contract-test-utils/contracts/test.sol";
import { MockERC20 } from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { MockRevertingERC20 } from "./mocks/MockRevertingERC20.sol";

import { Owner }  from "./accounts/Owner.sol";
import { Staker } from "./accounts/Staker.sol";

import { RevenueDistributionToken as RDT } from "../RevenueDistributionToken.sol";

/*************************/
/*** Base Test Classes ***/
/*************************/

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
    function _getDigest(address owner_, address spender_, uint256 value_, uint256 nonce_, uint256 deadline_) internal view returns (bytes32 digest_) {
        return keccak256(
            abi.encodePacked(
                '\x19\x01',
                asset.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(asset.PERMIT_TYPEHASH(), owner_, spender_, value_, nonce_, deadline_))
            )
        );
    }

    function _getMinDeposit(address rdToken_) internal view returns (uint256 minDeposit_) {
        minDeposit_ = (RDT(rdToken_).totalAssets() - 1) / RDT(rdToken_).totalSupply() + 1;
    }

    // Returns a valid `permit` signature signed by this contract's `owner` address
    function _getValidPermitSignature(address owner_, address spender_, uint256 value_, uint256 deadline_, uint256 ownerSk_) internal returns (uint8 v_, bytes32 r_, bytes32 s_) {
        return vm.sign(ownerSk_, _getDigest(owner_, spender_, value_, nonce, deadline_));
    }

}

contract RDTSuccessTestBase is RDTTestBase {

    /***************************/
    /*** Pre State Variables ***/
    /***************************/

    // NOTE: Pre state variables are kept in storage to avoid stack too deep
    int256 rdToken_allowance_staker_caller;
    int256 rdToken_balanceOf_staker;
    int256 rdToken_totalSupply;
    int256 rdToken_freeAssets;
    int256 rdToken_totalAssets;
    int256 rdToken_convertToAssets;
    int256 rdToken_convertToShares;
    int256 rdToken_issuanceRate;
    int256 rdToken_lastUpdated;
    int256 asset_balanceOf_caller;
    int256 asset_balanceOf_staker;
    int256 asset_balanceOf_rdToken;
    int256 asset_nonces;
    int256 asset_allowance_staker_rdToken;

    /****************************************/
    /*** State Change Assertion Variables ***/
    /****************************************/

    // NOTE: State change assertion variables are kept in storage to avoid stack too deep
    int256 rdToken_allowance_staker_caller_change;
    int256 rdToken_balanceOf_caller_change;
    int256 rdToken_balanceOf_staker_change;
    int256 rdToken_totalSupply_change;
    int256 rdToken_freeAssets_change;
    int256 rdToken_totalAssets_change;
    int256 rdToken_convertToAssets_change;
    int256 rdToken_convertToShares_change;
    int256 rdToken_issuanceRate_change;
    int256 rdToken_lastUpdated_change;
    int256 asset_balanceOf_caller_change;
    int256 asset_balanceOf_staker_change;
    int256 asset_balanceOf_rdToken_change;
    int256 asset_nonces_change;
    int256 asset_allowance_staker_rdToken_change;

    /***********************************/
    /*** Assertion Utility Functions ***/
    /***********************************/

    function _assertDeposit(address staker_, uint256 depositAmount_, bool fuzzed_) internal {
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

        assertEq(shares, rdToken.balanceOf(staker_) - _toUint256(rdToken_balanceOf_staker));

        _assertWithinOne(rdToken.balanceOf(staker_),  _toUint256(rdToken_balanceOf_staker + rdToken_balanceOf_staker_change));
        _assertWithinOne(rdToken.totalSupply(),       _toUint256(rdToken_totalSupply      + rdToken_totalSupply_change));
        _assertWithinOne(rdToken.freeAssets(),        _toUint256(rdToken_freeAssets       + rdToken_freeAssets_change));
        _assertWithinOne(rdToken.totalAssets(),       _toUint256(rdToken_totalAssets      + rdToken_totalAssets_change));
        _assertWithinOne(rdToken.issuanceRate(),      _toUint256(rdToken_issuanceRate     + rdToken_issuanceRate_change));

        if (!fuzzed_) {
            // TODO: Determine a way to mathematically determine inaccuracy based on inputs, so can be used in fuzz tests
            _assertWithinOne(rdToken.convertToAssets(sampleSharesToConvert), _toUint256(rdToken_convertToAssets + rdToken_convertToAssets_change));
            _assertWithinOne(rdToken.convertToShares(sampleAssetsToConvert), _toUint256(rdToken_convertToShares + rdToken_convertToShares_change));
        }

        assertEq(rdToken.lastUpdated(), _toUint256(rdToken_lastUpdated + rdToken_lastUpdated_change));

        _assertWithinOne(asset.balanceOf(staker_),                   _toUint256(asset_balanceOf_staker         + asset_balanceOf_staker_change));
        _assertWithinOne(asset.balanceOf(address(rdToken)),          _toUint256(asset_balanceOf_rdToken        + asset_balanceOf_rdToken_change));
        _assertWithinOne(asset.allowance(staker_, address(rdToken)), _toUint256(asset_allowance_staker_rdToken + asset_allowance_staker_rdToken_change));
    }

    function _assertMint(address staker_, uint256 mintAmount_, bool fuzzed_) internal {
        uint256 assetAmount = rdToken.previewMint(mintAmount_);

        asset.mint(staker_, assetAmount);

        Staker(staker_).erc20_approve(address(asset), address(rdToken), assetAmount);

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

        uint256 depositedAmount = Staker(staker_).rdToken_mint(address(rdToken), mintAmount_);

        assertEq(depositedAmount, _toUint256(asset_balanceOf_staker) - asset.balanceOf(staker_));

        _assertWithinOne(rdToken.balanceOf(staker_),  _toUint256(rdToken_balanceOf_staker + rdToken_balanceOf_staker_change));
        _assertWithinOne(rdToken.totalSupply(),       _toUint256(rdToken_totalSupply      + rdToken_totalSupply_change));
        _assertWithinOne(rdToken.freeAssets(),        _toUint256(rdToken_freeAssets       + rdToken_freeAssets_change));
        _assertWithinOne(rdToken.totalAssets(),       _toUint256(rdToken_totalAssets      + rdToken_totalAssets_change));
        _assertWithinOne(rdToken.issuanceRate(),      _toUint256(rdToken_issuanceRate     + rdToken_issuanceRate_change));

        if (!fuzzed_) {
            _assertWithinOne(rdToken.convertToAssets(sampleSharesToConvert), _toUint256(rdToken_convertToAssets + rdToken_convertToAssets_change));
            _assertWithinOne(rdToken.convertToShares(sampleAssetsToConvert), _toUint256(rdToken_convertToShares + rdToken_convertToShares_change));
        }

        assertEq(rdToken.lastUpdated(), _toUint256(rdToken_lastUpdated + rdToken_lastUpdated_change));

        _assertWithinOne(asset.balanceOf(staker_),                   _toUint256(asset_balanceOf_staker         + asset_balanceOf_staker_change));
        _assertWithinOne(asset.balanceOf(address(rdToken)),           _toUint256(asset_balanceOf_rdToken       + asset_balanceOf_rdToken_change));
        _assertWithinOne(asset.allowance(staker_, address(rdToken)), _toUint256(asset_allowance_staker_rdToken + asset_allowance_staker_rdToken_change));
    }

    function _assertDepositWithPermit(address staker_, uint256 stakerPrivateKey_, uint256 depositAmount_, bool fuzzed_) internal {
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

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(staker_, address(rdToken), depositAmount_,  block.timestamp, stakerPrivateKey_);
        vm.prank(staker_);
        uint256 shares = rdToken.depositWithPermit(depositAmount_, staker_, block.timestamp, v, r, s);

        assertEq(shares, rdToken.balanceOf(staker_) - _toUint256(rdToken_balanceOf_staker));

        _assertWithinOne(rdToken.balanceOf(staker_), _toUint256(rdToken_balanceOf_staker + rdToken_balanceOf_staker_change));
        _assertWithinOne(rdToken.totalSupply(),      _toUint256(rdToken_totalSupply      + rdToken_totalSupply_change));
        _assertWithinOne(rdToken.freeAssets(),       _toUint256(rdToken_freeAssets       + rdToken_freeAssets_change));
        _assertWithinOne(rdToken.totalAssets(),      _toUint256(rdToken_totalAssets      + rdToken_totalAssets_change));
        _assertWithinOne(rdToken.issuanceRate(),     _toUint256(rdToken_issuanceRate     + rdToken_issuanceRate_change));

        if (!fuzzed_) {
            // TODO: Determine a way to mathematically determine inaccuracy based on inputs, so can be used in fuzz tests
            _assertWithinOne(rdToken.convertToAssets(sampleSharesToConvert), _toUint256(rdToken_convertToAssets + rdToken_convertToAssets_change));
            _assertWithinOne(rdToken.convertToShares(sampleAssetsToConvert), _toUint256(rdToken_convertToShares + rdToken_convertToShares_change));
        }

        assertEq(rdToken.lastUpdated(), _toUint256(rdToken_lastUpdated + rdToken_lastUpdated_change));

        _assertWithinOne(asset.balanceOf(staker_),          _toUint256(asset_balanceOf_staker  + asset_balanceOf_staker_change));
        _assertWithinOne(asset.balanceOf(address(rdToken)), _toUint256(asset_balanceOf_rdToken + asset_balanceOf_rdToken_change));

        assertEq(asset.allowance(staker_, address(rdToken)), _toUint256(asset_allowance_staker_rdToken + asset_allowance_staker_rdToken_change));
        assertEq(asset.nonces(staker_),                      _toUint256(asset_nonces                   + asset_nonces_change));
    }

    function _assertMintWithPermit(address staker_, uint256 stakerPrivateKey_, uint256 mintAmount_, bool fuzzed_) internal {
        uint256 maxAssets = rdToken.previewMint(mintAmount_);
        asset.mint(staker_, maxAssets);

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

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(staker_, address(rdToken), maxAssets, block.timestamp, stakerPrivateKey_);
        vm.prank(staker_);
        uint256 depositedAmount = rdToken.mintWithPermit(mintAmount_, staker_, maxAssets, block.timestamp, v, r, s);

        assertEq(depositedAmount, _toUint256(asset_balanceOf_staker) - asset.balanceOf(staker_));

        _assertWithinOne(rdToken.balanceOf(staker_), _toUint256(rdToken_balanceOf_staker + rdToken_balanceOf_staker_change));
        _assertWithinOne(rdToken.totalSupply(),      _toUint256(rdToken_totalSupply      + rdToken_totalSupply_change));
        _assertWithinOne(rdToken.freeAssets(),       _toUint256(rdToken_freeAssets       + rdToken_freeAssets_change));
        _assertWithinOne(rdToken.totalAssets(),      _toUint256(rdToken_totalAssets      + rdToken_totalAssets_change));
        _assertWithinOne(rdToken.issuanceRate(),     _toUint256(rdToken_issuanceRate     + rdToken_issuanceRate_change));

        if (!fuzzed_) {
            // TODO: Determine a way to mathematically determine inaccuracy based on inputs, so can be used in fuzz tests
            _assertWithinOne(rdToken.convertToAssets(sampleSharesToConvert), _toUint256(rdToken_convertToAssets + rdToken_convertToAssets_change));
            _assertWithinOne(rdToken.convertToShares(sampleAssetsToConvert), _toUint256(rdToken_convertToShares + rdToken_convertToShares_change));
        }

        assertEq(rdToken.lastUpdated(), _toUint256(rdToken_lastUpdated + rdToken_lastUpdated_change));

        _assertWithinOne(asset.balanceOf(staker_),          _toUint256(asset_balanceOf_staker  + asset_balanceOf_staker_change));
        _assertWithinOne(asset.balanceOf(address(rdToken)), _toUint256(asset_balanceOf_rdToken + asset_balanceOf_rdToken_change));

        assertEq(asset.allowance(staker_, address(rdToken)), _toUint256(asset_allowance_staker_rdToken + asset_allowance_staker_rdToken_change));
        assertEq(asset.nonces(staker_),                      _toUint256(asset_nonces                   + asset_nonces_change));
    }

    function _assertWithdrawCallerNotOwner(address caller_, address staker_, uint256 withdrawAmount_, bool fuzzed_) internal {
        rdToken_allowance_staker_caller = _toInt256(rdToken.allowance(staker_, caller_));
        rdToken_balanceOf_staker        = _toInt256(rdToken.balanceOf(staker_));
        rdToken_totalSupply             = _toInt256(rdToken.totalSupply());
        rdToken_freeAssets              = _toInt256(rdToken.freeAssets());
        rdToken_totalAssets             = _toInt256(rdToken.totalAssets());
        rdToken_convertToAssets         = _toInt256(rdToken.convertToAssets(sampleSharesToConvert));
        rdToken_convertToShares         = _toInt256(rdToken.convertToShares(sampleAssetsToConvert));
        rdToken_issuanceRate            = _toInt256(rdToken.issuanceRate());
        rdToken_lastUpdated             = _toInt256(rdToken.lastUpdated());

        asset_balanceOf_staker  = _toInt256(asset.balanceOf(staker_));
        asset_balanceOf_caller  = _toInt256(asset.balanceOf(staker_));
        asset_balanceOf_rdToken = _toInt256(asset.balanceOf(address(rdToken)));

        uint256 sharesBurned = Staker(caller_).rdToken_withdraw(address(rdToken), withdrawAmount_, caller_, staker_);

        assertEq(sharesBurned, _toUint256(rdToken_balanceOf_staker) - rdToken.balanceOf(staker_));  // Number of shares burned

        _assertWithinOne(rdToken.allowance(staker_, caller_), _toUint256(rdToken_allowance_staker_caller + rdToken_allowance_staker_caller_change));
        _assertWithinOne(rdToken.balanceOf(staker_),          _toUint256(rdToken_balanceOf_staker        + rdToken_balanceOf_staker_change));
        _assertWithinOne(rdToken.totalSupply(),               _toUint256(rdToken_totalSupply             + rdToken_totalSupply_change));
        _assertWithinOne(rdToken.freeAssets(),                _toUint256(rdToken_freeAssets              + rdToken_freeAssets_change));
        _assertWithinOne(rdToken.totalAssets(),               _toUint256(rdToken_totalAssets             + rdToken_totalAssets_change));
        _assertWithinOne(rdToken.issuanceRate(),              _toUint256(rdToken_issuanceRate            + rdToken_issuanceRate_change));

        // In fuzzed tests, depending on inputs these values can be different so they are left out of assertions.
        if (!fuzzed_) {
            _assertWithinOne(rdToken.convertToAssets(sampleSharesToConvert), _toUint256(rdToken_convertToAssets  + rdToken_convertToAssets_change));
            _assertWithinOne(rdToken.convertToShares(sampleAssetsToConvert), _toUint256(rdToken_convertToShares  + rdToken_convertToShares_change));
        }

        assertEq(rdToken.lastUpdated(), _toUint256(rdToken_lastUpdated + rdToken_lastUpdated_change));

        _assertWithinOne(asset.balanceOf(staker_),          _toUint256(asset_balanceOf_staker  + asset_balanceOf_staker_change));
        _assertWithinOne(asset.balanceOf(caller_),          _toUint256(asset_balanceOf_caller  + asset_balanceOf_caller_change));
        _assertWithinOne(asset.balanceOf(address(rdToken)), _toUint256(asset_balanceOf_rdToken + asset_balanceOf_rdToken_change));
    }

    function _assertRedeemCallerNotOwner(address caller_, address staker_, uint256 redeemAmount_, bool fuzzed_) internal {
        rdToken_allowance_staker_caller = _toInt256(rdToken.allowance(staker_, caller_));
        rdToken_balanceOf_staker        = _toInt256(rdToken.balanceOf(staker_));
        rdToken_totalSupply             = _toInt256(rdToken.totalSupply());
        rdToken_freeAssets              = _toInt256(rdToken.freeAssets());
        rdToken_totalAssets             = _toInt256(rdToken.totalAssets());
        rdToken_convertToAssets         = _toInt256(rdToken.convertToAssets(sampleSharesToConvert));
        rdToken_convertToShares         = _toInt256(rdToken.convertToShares(sampleAssetsToConvert));
        rdToken_issuanceRate            = _toInt256(rdToken.issuanceRate());
        rdToken_lastUpdated             = _toInt256(rdToken.lastUpdated());

        asset_balanceOf_staker  = _toInt256(asset.balanceOf(staker_));
        asset_balanceOf_caller  = _toInt256(asset.balanceOf(staker_));
        asset_balanceOf_rdToken = _toInt256(asset.balanceOf(address(rdToken)));

        uint256 fundsWithdrawn = Staker(caller_).rdToken_redeem(address(rdToken), redeemAmount_, caller_, staker_);

        assertEq(fundsWithdrawn, asset.balanceOf(caller_) - _toUint256(asset_balanceOf_caller));  // Total funds withdrawn

        _assertWithinOne(rdToken.balanceOf(staker_), _toUint256(rdToken_balanceOf_staker + rdToken_balanceOf_staker_change));
        _assertWithinOne(rdToken.totalSupply(),      _toUint256(rdToken_totalSupply      + rdToken_totalSupply_change));
        _assertWithinOne(rdToken.freeAssets(),       _toUint256(rdToken_freeAssets       + rdToken_freeAssets_change));
        _assertWithinOne(rdToken.totalAssets(),      _toUint256(rdToken_totalAssets      + rdToken_totalAssets_change));

        // In fuzzed tests, depending on inputs these values can be different so they are left out of assertions.
        if (!fuzzed_) {
            _assertWithinOne(rdToken.convertToAssets(sampleSharesToConvert), _toUint256(rdToken_convertToAssets + rdToken_convertToAssets_change));
            _assertWithinOne(rdToken.convertToShares(sampleAssetsToConvert), _toUint256(rdToken_convertToShares + rdToken_convertToShares_change));
            _assertWithinOne(rdToken.issuanceRate(),                         _toUint256(rdToken_issuanceRate    + rdToken_issuanceRate_change));
        }

        assertEq(rdToken.lastUpdated(), _toUint256(rdToken_lastUpdated + rdToken_lastUpdated_change));

        _assertWithinOne(asset.balanceOf(staker_),          _toUint256(asset_balanceOf_staker  + asset_balanceOf_staker_change));
        _assertWithinOne(asset.balanceOf(caller_),          _toUint256(asset_balanceOf_caller  + asset_balanceOf_caller_change));
        _assertWithinOne(asset.balanceOf(address(rdToken)), _toUint256(asset_balanceOf_rdToken + asset_balanceOf_rdToken_change));

        assertEq(asset.allowance(staker_, address(rdToken)), _toUint256(asset_allowance_staker_rdToken + asset_allowance_staker_rdToken_change));
    }

    function _assertWithdraw(address staker_, uint256 withdrawAmount_, bool fuzzed_) internal {
        rdToken_balanceOf_staker = _toInt256(rdToken.balanceOf(staker_));
        rdToken_totalSupply      = _toInt256(rdToken.totalSupply());
        rdToken_freeAssets       = _toInt256(rdToken.freeAssets());
        rdToken_totalAssets      = _toInt256(rdToken.totalAssets());
        rdToken_convertToAssets  = _toInt256(rdToken.convertToAssets(sampleSharesToConvert));
        rdToken_convertToShares  = _toInt256(rdToken.convertToShares(sampleAssetsToConvert));
        rdToken_issuanceRate     = _toInt256(rdToken.issuanceRate());
        rdToken_lastUpdated      = _toInt256(rdToken.lastUpdated());

        asset_balanceOf_staker  = _toInt256(asset.balanceOf(staker_));
        asset_balanceOf_caller  = _toInt256(asset.balanceOf(staker_));
        asset_balanceOf_rdToken = _toInt256(asset.balanceOf(address(rdToken)));

        uint256 sharesBurned = Staker(staker_).rdToken_withdraw(address(rdToken), withdrawAmount_);

        assertEq(sharesBurned, _toUint256(rdToken_balanceOf_staker) - rdToken.balanceOf(staker_));  // Number of shares burned

        _assertWithinOne(rdToken.balanceOf(staker_), _toUint256(rdToken_balanceOf_staker + rdToken_balanceOf_staker_change));
        _assertWithinOne(rdToken.totalSupply(),      _toUint256(rdToken_totalSupply      + rdToken_totalSupply_change));
        _assertWithinOne(rdToken.freeAssets(),       _toUint256(rdToken_freeAssets       + rdToken_freeAssets_change));
        _assertWithinOne(rdToken.totalAssets(),      _toUint256(rdToken_totalAssets      + rdToken_totalAssets_change));
        _assertWithinOne(rdToken.issuanceRate(),     _toUint256(rdToken_issuanceRate     + rdToken_issuanceRate_change));

        // In fuzzed tests, depending on inputs these values can be different so they are left out of assertions.
        if (!fuzzed_) {
            _assertWithinOne(rdToken.convertToAssets(sampleSharesToConvert), _toUint256(rdToken_convertToAssets + rdToken_convertToAssets_change));
            _assertWithinOne(rdToken.convertToShares(sampleAssetsToConvert), _toUint256(rdToken_convertToShares + rdToken_convertToShares_change));
        }

        assertEq(rdToken.lastUpdated(), _toUint256(rdToken_lastUpdated + rdToken_lastUpdated_change));

        _assertWithinOne(asset.balanceOf(staker_),          _toUint256(asset_balanceOf_staker  + asset_balanceOf_staker_change));
        _assertWithinOne(asset.balanceOf(address(rdToken)), _toUint256(asset_balanceOf_rdToken + asset_balanceOf_rdToken_change));
    }

    function _assertRedeem(address staker_, uint256 redeemAmount_, bool fuzzed_) internal {
        rdToken_balanceOf_staker = _toInt256(rdToken.balanceOf(staker_));
        rdToken_totalSupply      = _toInt256(rdToken.totalSupply());
        rdToken_freeAssets       = _toInt256(rdToken.freeAssets());
        rdToken_totalAssets      = _toInt256(rdToken.totalAssets());
        rdToken_convertToAssets  = _toInt256(rdToken.convertToAssets(sampleSharesToConvert));
        rdToken_convertToShares  = _toInt256(rdToken.convertToShares(sampleAssetsToConvert));
        rdToken_issuanceRate     = _toInt256(rdToken.issuanceRate());
        rdToken_lastUpdated      = _toInt256(rdToken.lastUpdated());

        asset_balanceOf_staker  = _toInt256(asset.balanceOf(staker_));
        asset_balanceOf_caller  = _toInt256(asset.balanceOf(staker_));
        asset_balanceOf_rdToken = _toInt256(asset.balanceOf(address(rdToken)));

        uint256 fundsWithdrawn = Staker(staker_).rdToken_redeem(address(rdToken), redeemAmount_);

        assertEq(fundsWithdrawn, asset.balanceOf(staker_) - _toUint256(asset_balanceOf_staker));  // Total funds withdrawn

        _assertWithinOne(rdToken.balanceOf(staker_), _toUint256(rdToken_balanceOf_staker + rdToken_balanceOf_staker_change));
        _assertWithinOne(rdToken.totalSupply(),      _toUint256(rdToken_totalSupply      + rdToken_totalSupply_change));
        _assertWithinOne(rdToken.freeAssets(),       _toUint256(rdToken_freeAssets       + rdToken_freeAssets_change));
        _assertWithinOne(rdToken.totalAssets(),      _toUint256(rdToken_totalAssets      + rdToken_totalAssets_change));
        _assertWithinOne(rdToken.issuanceRate(),     _toUint256(rdToken_issuanceRate     + rdToken_issuanceRate_change));

        // In fuzzed tests, depending on inputs these values can be different so they are left out of assertions.
        if (!fuzzed_) {
            _assertWithinOne(rdToken.convertToAssets(sampleSharesToConvert), _toUint256(rdToken_convertToAssets + rdToken_convertToAssets_change));
            _assertWithinOne(rdToken.convertToShares(sampleAssetsToConvert), _toUint256(rdToken_convertToShares + rdToken_convertToShares_change));
        }

        assertEq(rdToken.lastUpdated(), _toUint256(rdToken_lastUpdated + rdToken_lastUpdated_change));

        _assertWithinOne(asset.balanceOf(staker_),          _toUint256(asset_balanceOf_staker  + asset_balanceOf_staker_change));
        _assertWithinOne(asset.balanceOf(address(rdToken)), _toUint256(asset_balanceOf_rdToken + asset_balanceOf_rdToken_change));
    }

    /*********************************/
    /*** General Utility Functions ***/
    /*********************************/

    function _assertWithinOne(uint256 expected_, uint256 actual_) internal {
        assertWithinDiff(actual_, expected_, 1);
    }

    function _toInt256(uint256 unsigned_) internal pure returns (int256 signed_) {
        signed_ = int256(unsigned_);
        require(signed_ >= 0, "TO_INT256_OVERFLOW");
    }

    function _toUint256(int256 signed_) internal pure returns (uint256 unsigned_) {
        require(signed_ >= 0, "TO_UINT256_NEGATIVE");
        return uint256(signed_);
    }

}

/*************/
/*** Tests ***/
/*************/

contract AuthTests is RDTTestBase {

    Owner notOwner;
    Owner owner;

    function setUp() public override virtual {
        notOwner = new Owner();
        owner    = new Owner();
        asset    = new MockERC20("MockToken", "MT", 18);
        rdToken  = new RDT("Revenue Distribution Token", "RDT", address(owner), address(asset), 1e30);
        vm.warp(START);
    }

    function test_setPendingOwner_acl() public {
        vm.expectRevert("RDT:SPO:NOT_OWNER");
        notOwner.rdToken_setPendingOwner(address(rdToken), address(1));

        assertEq(rdToken.pendingOwner(), address(0));
        owner.rdToken_setPendingOwner(address(rdToken), address(1));
        assertEq(rdToken.pendingOwner(), address(1));
    }

    function test_acceptOwnership_acl() public {
        owner.rdToken_setPendingOwner(address(rdToken), address(notOwner));

        vm.expectRevert("RDT:AO:NOT_PO");
        owner.rdToken_acceptOwnership(address(rdToken));

        assertEq(rdToken.pendingOwner(), address(notOwner));
        assertEq(rdToken.owner(),        address(owner));

        notOwner.rdToken_acceptOwnership(address(rdToken));

        assertEq(rdToken.pendingOwner(), address(0));
        assertEq(rdToken.owner(),        address(notOwner));
    }

    function test_updateVestingSchedule_acl() public {
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

contract ConstructorTest is TestUtils {

    function test_constructor_ownerZeroAddress() public {
        MockERC20 asset = new MockERC20("MockToken", "MT", 18);

        vm.expectRevert("RDT:C:OWNER_ZERO_ADDRESS");
        RDT rdToken = new RDT("Revenue Distribution Token", "RDT", address(0), address(asset), 1e30);

        rdToken = new RDT("Revenue Distribution Token", "RDT", address(this), address(asset), 1e30);
    }

}

contract DepositFailureTests is RDTTestBase {

    Staker staker;

    function setUp() public override virtual {
        super.setUp();
        staker = new Staker();
    }

    function test_deposit_zeroReceiver() public {
        asset.mint(address(staker), 1);
        staker.erc20_approve(address(asset), address(rdToken), 1);

        vm.expectRevert("RDT:M:ZERO_RECEIVER");
        staker.rdToken_deposit(address(rdToken), 1, address(0));

        staker.rdToken_deposit(address(rdToken), 1, address(staker));
    }

    function test_deposit_zeroAssets() public {
        asset.mint(address(staker), 1);
        staker.erc20_approve(address(asset), address(rdToken), 1);

        vm.expectRevert("RDT:M:ZERO_SHARES");
        staker.rdToken_deposit(address(rdToken), 0);

        staker.rdToken_deposit(address(rdToken), 1);
    }

    function test_deposit_badApprove(uint256 depositAmount_) public {
        depositAmount_ = constrictToRange(depositAmount_, 1, 1e29);

        asset.mint(address(staker), depositAmount_);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount_ - 1);

        vm.expectRevert("RDT:M:TRANSFER_FROM");
        staker.rdToken_deposit(address(rdToken), depositAmount_);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount_);
        staker.rdToken_deposit(address(rdToken), depositAmount_);
    }

    function test_deposit_insufficientBalance(uint256 depositAmount_) public {
        depositAmount_ = constrictToRange(depositAmount_, 1, 1e29);

        asset.mint(address(staker), depositAmount_);
        staker.erc20_approve(address(asset), address(rdToken), depositAmount_ + 1);

        vm.expectRevert("RDT:M:TRANSFER_FROM");
        staker.rdToken_deposit(address(rdToken), depositAmount_ + 1);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount_);
        staker.rdToken_deposit(address(rdToken), depositAmount_);
    }

    function test_deposit_zeroShares() public {
        // Do a deposit so that totalSupply is non-zero
        asset.mint(address(this), 20e18);
        asset.approve(address(rdToken), 20e18);
        rdToken.deposit(20e18, address(this));

        _transferAndUpdateVesting(address(asset), address(rdToken), 5e18, 10 seconds);

        vm.warp(block.timestamp + 2 seconds);

        uint256 minDeposit = (rdToken.totalAssets() - 1) / rdToken.totalSupply() + 1;

        asset.mint(address(staker), minDeposit);
        staker.erc20_approve(address(asset), address(rdToken), minDeposit);

        vm.expectRevert("RDT:M:ZERO_SHARES");
        staker.rdToken_deposit(address(rdToken), minDeposit - 1);

        staker.rdToken_deposit(address(rdToken), minDeposit);
    }

}

contract DepositTests is RDTSuccessTestBase {

    function test_deposit_singleUser_preVesting() public {
        uint256 depositAmount = 1000;

        rdToken_balanceOf_staker_change = 1000;
        rdToken_totalSupply_change      = 1000;
        rdToken_freeAssets_change       = 1000;
        rdToken_totalAssets_change      = 1000;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = 10_000_000;  // First deposit updates `lastUpdated`

        asset_balanceOf_staker_change         = -1000;
        asset_balanceOf_rdToken_change        =  1000;
        asset_allowance_staker_rdToken_change = -1000;

        address staker = address(new Staker());

        _assertDeposit(staker, depositAmount, false);
    }

    function testFuzz_deposit_singleUser_preVesting(uint256 depositAmount_) public {
        depositAmount_ = constrictToRange(depositAmount_, 1, 1e29);

        rdToken_balanceOf_staker_change = _toInt256(depositAmount_);
        rdToken_totalSupply_change      = _toInt256(depositAmount_);
        rdToken_freeAssets_change       = _toInt256(depositAmount_);
        rdToken_totalAssets_change      = _toInt256(depositAmount_);
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = _toInt256(START);  // First deposit updates `lastUpdated`

        asset_balanceOf_staker_change         = - _toInt256(depositAmount_);
        asset_balanceOf_rdToken_change        =   _toInt256(depositAmount_);
        asset_allowance_staker_rdToken_change = - _toInt256(depositAmount_);

        address staker = address(new Staker());

        _assertDeposit(staker, depositAmount_, false);
    }

    function test_deposit_singleUser_midVesting() public {
        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero.
        _depositAsset(address(asset), address(setupStaker), 20e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), 10e18, 10 seconds);

        vm.warp(START + 5 seconds);  // Vest 5e18 tokens.

        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.25e18);  // 1 * (20 + 5) / 20

        uint256 depositAmount = 10e18;

        rdToken_balanceOf_staker_change = 8e18;  // 10e18 / 1.25
        rdToken_totalSupply_change      = 8e18;
        rdToken_freeAssets_change       = 15e18;  // Captures vested amount (5 + 10)
        rdToken_totalAssets_change      = 10e18;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = 5 seconds;

        asset_balanceOf_staker_change         = -10e18;
        asset_balanceOf_rdToken_change        =  10e18;
        asset_allowance_staker_rdToken_change = -10e18;

        address staker = address(new Staker());

        _assertDeposit(staker, depositAmount, false);
    }

    function testFuzz_deposit_singleUser_midVesting(uint256 initialAmount_, uint256 depositAmount_, uint256 vestingAmount_, uint256 vestingPeriod_, uint256 warpTime_) public {
        Staker setupStaker = new Staker();

        initialAmount_ = constrictToRange(initialAmount_, 1,         1e6);  // Kept smaller since its just needed to increase totalSupply
        vestingAmount_ = constrictToRange(vestingAmount_, 1,         1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 seconds, 365 days);
        warpTime_      = constrictToRange(vestingPeriod_, 0,         vestingPeriod_);

        // Do a deposit so that totalSupply is non-zero.
        _depositAsset(address(asset), address(setupStaker), initialAmount_);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + warpTime_);

        // Get minimum deposit to avoid ZERO_SHARES.
        uint256 minDeposit = _getMinDeposit(address(rdToken));
        depositAmount_     = constrictToRange(depositAmount_, minDeposit, 1e29 + 1);

        uint256 expectedShares = depositAmount_ * rdToken.totalSupply() / rdToken.totalAssets();
        uint256 vestedAmount   = rdToken.issuanceRate() * warpTime_ / 1e30;

        rdToken_balanceOf_staker_change = _toInt256(expectedShares);
        rdToken_totalSupply_change      = _toInt256(expectedShares);
        rdToken_freeAssets_change       = _toInt256(vestedAmount + depositAmount_);  // Captures vested amount
        rdToken_totalAssets_change      = _toInt256(depositAmount_);
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = _toInt256(warpTime_);

        asset_balanceOf_staker_change         = - _toInt256(depositAmount_);
        asset_balanceOf_rdToken_change        =   _toInt256(depositAmount_);
        asset_allowance_staker_rdToken_change = - _toInt256(depositAmount_);

        address staker = address(new Staker());

        _assertDeposit(staker, depositAmount_, true);
    }

    function test_deposit_singleUser_postVesting() public {
        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 20e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), 5e18, 10 seconds);  // Vest full 5e18 tokens

        vm.warp(START + 11 seconds);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.25e18);  // 1 * (20 + 5) / 20

        rdToken_balanceOf_staker_change = 8e18;  // 10e18 / 1.25
        rdToken_totalSupply_change      = 8e18;
        rdToken_freeAssets_change       = 15e18;  // Captures vested amount
        rdToken_totalAssets_change      = 10e18;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = - _toInt256(rdToken.issuanceRate());  // Gets set to zero
        rdToken_lastUpdated_change      = 11 seconds;

        asset_balanceOf_staker_change         = -10e18;
        asset_balanceOf_rdToken_change        =  10e18;
        asset_allowance_staker_rdToken_change = -10e18;

        address staker = address(new Staker());

        _assertDeposit(staker, 10e18, false);
    }

    function testFuzz_deposit_singleUser_postVesting(uint256 initialAmount_, uint256 depositAmount_, uint256 vestingAmount_, uint256 vestingPeriod_) public {
        Staker setupStaker = new Staker();

        initialAmount_ = constrictToRange(initialAmount_, 1,         1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1,         1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 seconds, 10_000 days);

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 20e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + vestingPeriod_ + 1);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        // Get minimum deposit to avoid ZERO_SHARES.
        uint256 minDeposit = _getMinDeposit(address(rdToken));
        depositAmount_     = constrictToRange(depositAmount_, minDeposit, 1e29 + 1);

        uint256 expectedShares = depositAmount_ * rdToken.totalSupply() / rdToken.totalAssets();

        rdToken_balanceOf_staker_change = _toInt256(expectedShares);
        rdToken_totalSupply_change      = _toInt256(expectedShares);
        rdToken_freeAssets_change       = _toInt256(vestingAmount_ + depositAmount_);  // Captures vested amount
        rdToken_totalAssets_change      = _toInt256(depositAmount_);
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = - _toInt256(rdToken.issuanceRate());  // Gets set to zero
        rdToken_lastUpdated_change      =   _toInt256(vestingPeriod_ + 1);

        asset_balanceOf_staker_change         = - _toInt256(depositAmount_);
        asset_balanceOf_rdToken_change        =   _toInt256(depositAmount_);
        asset_allowance_staker_rdToken_change = - _toInt256(depositAmount_);

        address staker = address(new Staker());

        _assertDeposit(staker, depositAmount_, true);
    }

    function testFuzz_deposit_multiUser_midVesting(
        uint256 initialAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_,
        bytes32 depositSeed_,
        bytes32 warpSeed_
    )
        public
    {
        initialAmount_ = constrictToRange(initialAmount_, 1,      1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1,      1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 days, 365 days);

        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 1e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        for (uint256 i = 1; i < 11; ++i) {
            uint256 depositAmount = uint256(keccak256(abi.encodePacked(depositSeed_, i)));
            uint256 warpTime      = uint256(keccak256(abi.encodePacked(warpSeed_,    i)));

            // Get minimum deposit to avoid ZERO_SHARES.
            uint256 minDeposit = _getMinDeposit(address(rdToken));
            depositAmount      = constrictToRange(depositAmount, minDeposit, 1e29 + 1);             // + 1 since we round up in min deposit.
            warpTime           = constrictToRange(warpTime,      0,          vestingPeriod_ / 10);  // Needs to be smaller than vestingPeriod_ / 10

            vm.warp(block.timestamp + warpTime);

            uint256 expectedShares = depositAmount * rdToken.totalSupply() / rdToken.totalAssets();
            uint256 vestedAmount   = rdToken.issuanceRate() * warpTime / 1e30;

            rdToken_balanceOf_staker_change = _toInt256(expectedShares);
            rdToken_totalSupply_change      = _toInt256(expectedShares);
            rdToken_freeAssets_change       = _toInt256(vestedAmount + depositAmount);  // Captures vested amount
            rdToken_totalAssets_change      = _toInt256(depositAmount);
            rdToken_convertToAssets_change  = 0;
            rdToken_convertToShares_change  = 0;
            rdToken_issuanceRate_change     = 0;
            rdToken_lastUpdated_change      = _toInt256(warpTime);

            asset_balanceOf_staker_change         = - _toInt256(depositAmount);
            asset_balanceOf_rdToken_change        =   _toInt256(depositAmount);
            asset_allowance_staker_rdToken_change = - _toInt256(depositAmount);

            address staker = address(new Staker());

            _assertDeposit(staker, depositAmount, true);
        }
    }

    function testFuzz_deposit_multiUser_postVesting(uint256 initialAmount_, uint256 vestingAmount_, uint256 vestingPeriod_, bytes32 seed_) public {
        initialAmount_ = constrictToRange(initialAmount_, 1, 1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1, 1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1, 365 days);

        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 1e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + vestingPeriod_ + 1);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        // Do another deposit to set all params to be uniform
        _depositAsset(address(asset), address(setupStaker), 1e18);

        for (uint256 i = 1; i < 11; ++i) {
            uint256 depositAmount = uint256(keccak256(abi.encodePacked(seed_, i)));

            // Get minimum deposit to avoid ZERO_SHARES.
            uint256 minDeposit = _getMinDeposit(address(rdToken));
            depositAmount      = constrictToRange(depositAmount, minDeposit, 1e29 + 1);  // + 1 since we round up in min deposit.

            uint256 expectedShares = depositAmount * rdToken.totalSupply() / rdToken.totalAssets();

            rdToken_balanceOf_staker_change = _toInt256(expectedShares);
            rdToken_totalSupply_change      = _toInt256(expectedShares);
            rdToken_freeAssets_change       = _toInt256(depositAmount);  // Captures vested amount
            rdToken_totalAssets_change      = _toInt256(depositAmount);
            rdToken_convertToAssets_change  = 0;
            rdToken_convertToShares_change  = 0;
            rdToken_issuanceRate_change     = 0;
            rdToken_lastUpdated_change      = 0;

            asset_balanceOf_staker_change         = - _toInt256(depositAmount);
            asset_balanceOf_rdToken_change        =   _toInt256(depositAmount);
            asset_allowance_staker_rdToken_change = - _toInt256(depositAmount);

            address staker = address(new Staker());

            _assertDeposit(staker, depositAmount, true);
        }
    }

}

contract DepositWithPermitFailureTests is RDTTestBase {

    address staker;
    address notStaker;

    uint256 stakerPrivateKey    = 1;
    uint256 notStakerPrivateKey = 2;

    function setUp() public override virtual {
        super.setUp();

        staker    = vm.addr(stakerPrivateKey);
        notStaker = vm.addr(notStakerPrivateKey);
    }

    function test_depositWithPermit_zeroAddress() public {
        uint256 depositAmount = 1e18;
        asset.mint(address(staker), depositAmount);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(staker, address(rdToken), depositAmount, deadline, stakerPrivateKey);

        vm.startPrank(staker);

        vm.expectRevert(bytes("ERC20:P:MALLEABLE"));
        rdToken.depositWithPermit(depositAmount, staker, deadline, 17, r, s);

        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);
    }

    function test_depositWithPermit_notStakerSignature() public {
        uint256 depositAmount = 1e18;
        asset.mint(address(staker), depositAmount);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(notStaker, address(rdToken), depositAmount, deadline, notStakerPrivateKey);

        vm.startPrank(staker);

        vm.expectRevert(bytes("ERC20:P:INVALID_SIGNATURE"));
        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);

        ( v, r, s ) = _getValidPermitSignature(staker, address(rdToken), depositAmount, deadline, stakerPrivateKey);

        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);

    }

    function test_depositWithPermit_pastDeadline() public {
        uint256 depositAmount = 1e18;
        asset.mint(address(staker), depositAmount);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(staker, address(rdToken), depositAmount, deadline, stakerPrivateKey);

        vm.startPrank(staker);

        vm.warp(deadline + 1);

        vm.expectRevert(bytes("ERC20:P:EXPIRED"));
        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);

        vm.warp(deadline);

        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);
    }

    function test_depositWithPermit_replay() public {
        uint256 depositAmount = 1e18;
        asset.mint(address(staker), depositAmount * 2);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(staker, address(rdToken), depositAmount, deadline, stakerPrivateKey);

        vm.startPrank(staker);

        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);

        vm.expectRevert(bytes("ERC20:P:INVALID_SIGNATURE"));
        rdToken.depositWithPermit(depositAmount, staker, deadline, v, r, s);
    }

}

contract DepositWithPermitTests is RDTSuccessTestBase {

    function test_depositWithPermit_singleUser_preVesting() public {
        uint256 depositAmount = 1000;

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

        _assertDepositWithPermit(staker, 1, depositAmount, false);
    }

    function testFuzz_depositWithPermit_singleUser_preVesting(uint256 depositAmount_) public {
        depositAmount_ = constrictToRange(depositAmount_, 1, 1e29);

        rdToken_balanceOf_staker_change = _toInt256(depositAmount_);
        rdToken_totalSupply_change      = _toInt256(depositAmount_);
        rdToken_freeAssets_change       = _toInt256(depositAmount_);
        rdToken_totalAssets_change      = _toInt256(depositAmount_);
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = _toInt256(START);  // First deposit updates `lastUpdated`

        asset_balanceOf_staker_change         = - _toInt256(depositAmount_);
        asset_balanceOf_rdToken_change        =   _toInt256(depositAmount_);
        asset_nonces_change                   = 1;
        asset_allowance_staker_rdToken_change = 0;

        address staker = vm.addr(1);

        _assertDepositWithPermit(staker, 1, depositAmount_, false);
    }

    function test_depositWithPermit_singleUser_midVesting() public {
        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 20e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), 10e18, 10 seconds);  // Vest full 5e18 tokens

        vm.warp(START + 5 seconds);

        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.25e18);  // 1 * (20 + 5) / 20

        uint256 depositAmount = 10e18;

        rdToken_balanceOf_staker_change = 8e18;  // 10e18 / 1.25
        rdToken_totalSupply_change      = 8e18;
        rdToken_freeAssets_change       = 15e18;  // Captures vested amount
        rdToken_totalAssets_change      = 10e18;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = 5 seconds;

        asset_balanceOf_staker_change         = -10e18;
        asset_balanceOf_rdToken_change        = 10e18;
        asset_nonces_change                   = 1;
        asset_allowance_staker_rdToken_change = 0;

        address staker = vm.addr(1);

        _assertDepositWithPermit(staker, 1, depositAmount, false);
    }

    function testFuzz_depositWithPermit_singleUser_midVesting(uint256 initialAmount_, uint256 depositAmount_, uint256 vestingAmount_, uint256 vestingPeriod_, uint256 warpTime_) public {
        Staker setupStaker = new Staker();

        initialAmount_ = constrictToRange(initialAmount_, 1,         1e6);  // Kept smaller since its just needed to increase totalSupply
        vestingAmount_ = constrictToRange(vestingAmount_, 1,         1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 seconds, 365 days);
        warpTime_      = constrictToRange(warpTime_,      1 seconds, vestingPeriod_);

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), initialAmount_);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + warpTime_);

        // Get minimum deposit to avoid ZERO_SHARES.
        uint256 minDeposit = _getMinDeposit(address(rdToken));
        depositAmount_     = constrictToRange(depositAmount_, minDeposit, 1e29 + 1);

        uint256 expectedShares = depositAmount_ * rdToken.totalSupply() / rdToken.totalAssets();
        uint256 vestedAmount   = rdToken.issuanceRate() * warpTime_ / 1e30;

        rdToken_balanceOf_staker_change = _toInt256(expectedShares);
        rdToken_totalSupply_change      = _toInt256(expectedShares);
        rdToken_freeAssets_change       = _toInt256(vestedAmount + depositAmount_);  // Captures vested amount
        rdToken_totalAssets_change      = _toInt256(depositAmount_);
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = _toInt256(warpTime_);

        asset_balanceOf_staker_change         = - _toInt256(depositAmount_);
        asset_balanceOf_rdToken_change        =   _toInt256(depositAmount_);
        asset_nonces_change                   = 1;
        asset_allowance_staker_rdToken_change = 0;

        address staker = vm.addr(1);

        _assertDepositWithPermit(staker, 1, depositAmount_, true);
    }

    function test_depositWithPermit_singleUser_postVesting() public {
        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 20e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), 5e18, 10 seconds);  // Vest full 5e18 tokens

        vm.warp(START + 11 seconds);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.25e18);  // 1 * (20 + 5) / 20

        rdToken_balanceOf_staker_change = 8e18;  // 10e18 / 1.25
        rdToken_totalSupply_change      = 8e18;
        rdToken_freeAssets_change       = 15e18;  // Captures vested amount
        rdToken_totalAssets_change      = 10e18;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = - _toInt256(rdToken.issuanceRate());  // Gets set to zero
        rdToken_lastUpdated_change      = 11 seconds;

        asset_balanceOf_staker_change         = -10e18;
        asset_balanceOf_rdToken_change        = 10e18;
        asset_nonces_change                   = 1;
        asset_allowance_staker_rdToken_change = 0;

        address staker = vm.addr(1);

        _assertDepositWithPermit(staker, 1, 10e18, false);
    }

    function testFuzz_depositWithPermit_singleUser_postVesting(uint256 initialAmount_, uint256 depositAmount_, uint256 vestingAmount_, uint256 vestingPeriod_) public {
        Staker setupStaker = new Staker();

        initialAmount_ = constrictToRange(initialAmount_, 1,         1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1,         1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 seconds, 10_000 days);

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 20e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + vestingPeriod_ + 1);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        // Get minimum deposit to avoid ZERO_SHARES.
        uint256 minDeposit = _getMinDeposit(address(rdToken));
        depositAmount_     = constrictToRange(depositAmount_, minDeposit, 1e29 + 1);

        uint256 expectedShares = depositAmount_ * rdToken.totalSupply() / rdToken.totalAssets();

        rdToken_balanceOf_staker_change = _toInt256(expectedShares);
        rdToken_totalSupply_change      = _toInt256(expectedShares);
        rdToken_freeAssets_change       = _toInt256(vestingAmount_ + depositAmount_);  // Captures vested amount
        rdToken_totalAssets_change      = _toInt256(depositAmount_);
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = - _toInt256(rdToken.issuanceRate());  // Gets set to zero
        rdToken_lastUpdated_change      =   _toInt256(vestingPeriod_ + 1);

        asset_balanceOf_staker_change         = - _toInt256(depositAmount_);
        asset_balanceOf_rdToken_change        =   _toInt256(depositAmount_);
        asset_nonces_change                   = 1;
        asset_allowance_staker_rdToken_change = 0;

        address staker = vm.addr(1);

        _assertDepositWithPermit(staker, 1, depositAmount_, true);
    }

    function testFuzz_depositWithPermit_multiUser_midVesting(
        uint256 initialAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_,
        bytes32 depositSeed_,
        bytes32 warpSeed_
    )
        public
    {
        initialAmount_ = constrictToRange(initialAmount_, 1,      1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1,      1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 days, 365 days);

        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 1e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        for (uint i = 1; i < 11; ++i) {
            uint256 depositAmount = uint256(keccak256(abi.encodePacked(depositSeed_, i)));
            uint256 warpTime      = uint256(keccak256(abi.encodePacked(warpSeed_,    i)));

            // Get minimum deposit to avoid ZERO_SHARES.
            uint256 minDeposit = _getMinDeposit(address(rdToken));
            depositAmount      = constrictToRange(depositAmount, minDeposit, 1e29 + 1);             // + 1 since we round up in min deposit.
            warpTime           = constrictToRange(warpTime,      0,          vestingPeriod_ / 10);  // Needs to be smaller than vestingPeriod_ / 10

            vm.warp(block.timestamp + warpTime);

            uint256 expectedShares = depositAmount * rdToken.totalSupply() / rdToken.totalAssets();
            uint256 vestedAmount   = rdToken.issuanceRate() * warpTime / 1e30;

            rdToken_balanceOf_staker_change = _toInt256(expectedShares);
            rdToken_totalSupply_change      = _toInt256(expectedShares);
            rdToken_freeAssets_change       = _toInt256(vestedAmount + depositAmount);  // Captures vested amount
            rdToken_totalAssets_change      = _toInt256(depositAmount);
            rdToken_convertToAssets_change  = 0;
            rdToken_convertToShares_change  = 0;
            rdToken_issuanceRate_change     = 0;
            rdToken_lastUpdated_change      = _toInt256(warpTime);

            asset_balanceOf_staker_change         = - _toInt256(depositAmount);
            asset_balanceOf_rdToken_change        =   _toInt256(depositAmount);
            asset_nonces_change                   = 1;
            asset_allowance_staker_rdToken_change = 0;

            address staker = vm.addr(i);

            _assertDepositWithPermit(staker, i, depositAmount, true);
        }
    }

    function testFuzz_depositWithPermit_multiUser_postVesting(uint256 initialAmount_, uint256 vestingAmount_, uint256 vestingPeriod_, bytes32 seed_) public {
        initialAmount_ = constrictToRange(initialAmount_, 1, 1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1, 1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1, 365 days);

        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 1e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + vestingPeriod_ + 1);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        // Do another deposit to set all params to be uniform
        _depositAsset(address(asset), address(setupStaker), 1e18);

        for (uint256 i = 1; i < 11; ++i) {
            uint256 depositAmount = uint256(keccak256(abi.encodePacked(seed_, i)));

            // Get minimum deposit to avoid ZERO_SHARES.
            uint256 minDeposit = _getMinDeposit(address(rdToken));
            depositAmount      = constrictToRange(depositAmount, minDeposit, 1e29 + 1);  // + 1 since we round up in min deposit.

            uint256 expectedShares = depositAmount * rdToken.totalSupply() / rdToken.totalAssets();

            rdToken_balanceOf_staker_change = _toInt256(expectedShares);
            rdToken_totalSupply_change      = _toInt256(expectedShares);
            rdToken_freeAssets_change       = _toInt256(depositAmount);  // Captures vested amount
            rdToken_totalAssets_change      = _toInt256(depositAmount);
            rdToken_convertToAssets_change  = 0;
            rdToken_convertToShares_change  = 0;
            rdToken_issuanceRate_change     = 0;
            rdToken_lastUpdated_change      = 0;

            asset_balanceOf_staker_change         = - _toInt256(depositAmount);
            asset_balanceOf_rdToken_change        =   _toInt256(depositAmount);
            asset_nonces_change                   = 1;
            asset_allowance_staker_rdToken_change = 0;

            address staker = vm.addr(i);

            _assertDepositWithPermit(staker, i, depositAmount, true);
        }
    }

}

contract EndToEndRevenueStreamingTests is RDTTestBase {

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

        assertEq(rdToken.totalAssets(), 1_000_000e18);  // No change

        vm.warp(START);  // Warp back after demonstrating totalAssets is not time-dependent before vesting starts

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount, vestingPeriod);

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
        assertEq(rdToken.convertToShares(sampleAssetsToConvert), 9.90099009900990099e17);  // Shares go down, as they are worth more assets.

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

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount, vestingPeriod);

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
        assertEq(rdToken.convertToAssets(sampleSharesToConvert),    sampleSharesToConvert * rdToken.totalAssets() / depositAmount);  // Using totalAssets because of rounding
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

}

contract MintFailureTests is RDTTestBase {

    Staker staker;

    function setUp() public override virtual {
        super.setUp();
        staker = new Staker();
    }

    function test_mint_zeroReceiver() public {
        asset.mint(address(staker), 1);
        staker.erc20_approve(address(asset), address(rdToken), 1);

        vm.expectRevert("RDT:M:ZERO_RECEIVER");
        staker.rdToken_mint(address(rdToken), 1, address(0));

        staker.rdToken_mint(address(rdToken), 1, address(staker));
    }

    function test_mint_zeroAmount() public {
        asset.mint(address(staker), 1);
        staker.erc20_approve(address(asset), address(rdToken), 1);

        vm.expectRevert("RDT:M:ZERO_SHARES");
        staker.rdToken_mint(address(rdToken), 0);

        staker.rdToken_mint(address(rdToken), 1);
    }

    function test_mint_badApprove(uint256 mintAmount_) public {
        mintAmount_ = constrictToRange(mintAmount_, 1, 1e29);

        uint256 depositAmount = rdToken.previewMint(mintAmount_);

        asset.mint(address(staker), depositAmount);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount - 1);

        vm.expectRevert("RDT:M:TRANSFER_FROM");
        staker.rdToken_mint(address(rdToken), mintAmount_);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);
        staker.rdToken_mint(address(rdToken), mintAmount_);
    }

    function test_mint_insufficientBalance(uint256 mintAmount_) public {
        mintAmount_ = constrictToRange(mintAmount_, 1, 1e29);

        uint256 depositAmount = rdToken.previewMint(mintAmount_);

        staker.erc20_approve(address(asset), address(rdToken), depositAmount);

        vm.expectRevert("RDT:M:TRANSFER_FROM");
        staker.rdToken_mint(address(rdToken), mintAmount_);

        asset.mint(address(staker), depositAmount);

        staker.rdToken_mint(address(rdToken), mintAmount_);
    }

}

contract MintTests is RDTSuccessTestBase {

    function test_mint_singleUser_preVesting() public {
        uint256 mintAmount = 1000;

        rdToken_balanceOf_staker_change = 1000;
        rdToken_totalSupply_change      = 1000;
        rdToken_freeAssets_change       = 1000;
        rdToken_totalAssets_change      = 1000;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = _toInt256(START);  // First deposit updates `lastUpdated`

        asset_balanceOf_staker_change         = -1000;
        asset_balanceOf_rdToken_change        =  1000;
        asset_allowance_staker_rdToken_change = -1000;

        address staker = address(new Staker());

        _assertMint(staker, mintAmount, false);
    }

    function testFuzz_mint_singleUser_preVesting(uint256 mintAmount_) public {
        mintAmount_ = constrictToRange(mintAmount_, 1, 1e29);

        rdToken_balanceOf_staker_change = _toInt256(mintAmount_);
        rdToken_totalSupply_change      = _toInt256(mintAmount_);
        rdToken_freeAssets_change       = _toInt256(mintAmount_);
        rdToken_totalAssets_change      = _toInt256(mintAmount_);
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = _toInt256(START);  // First deposit updates `lastUpdated`

        asset_balanceOf_staker_change         = - _toInt256(mintAmount_);
        asset_balanceOf_rdToken_change        =   _toInt256(mintAmount_);
        asset_allowance_staker_rdToken_change = - _toInt256(rdToken.convertToAssets(mintAmount_));

        address staker = address(new Staker());

        _assertMint(staker, mintAmount_, false);
    }

    function test_mint_singleUser_midVesting() public {
        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 20e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), 10e18, 10 seconds);

        vm.warp(START + 5 seconds);

        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.25e18);  // 1 * (20 + 5) / 20

        uint256 mintAmount = 10e18;

        rdToken_balanceOf_staker_change = 10e18;
        rdToken_totalSupply_change      = 10e18;
        rdToken_freeAssets_change       = 17.5e18;  // Captures vested amount
        rdToken_totalAssets_change      = 12.5e18;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = 5 seconds;

        asset_balanceOf_staker_change         = -12.5e18;
        asset_balanceOf_rdToken_change        =  12.5e18;
        asset_allowance_staker_rdToken_change = -12.5e18;

        address staker = address(new Staker());

        _assertMint(staker, mintAmount, false);
    }

    function testFuzz_mint_singleUser_midVesting(uint256 initialAmount_, uint256 mintAmount_, uint256 vestingAmount_, uint256 vestingPeriod_, uint256 warpTime_) public {
        Staker setupStaker = new Staker();

        initialAmount_ = constrictToRange(initialAmount_, 1,         1e6);  // Kept smaller since its just needed to increase totalSupply
        mintAmount_    = constrictToRange(mintAmount_,    1,         1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1,         1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 seconds, 365 days);
        warpTime_      = constrictToRange(warpTime_,      1 seconds, vestingPeriod_);

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), initialAmount_);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + warpTime_);

        uint256 expectedAssets = mintAmount_ * rdToken.totalAssets() / rdToken.totalSupply();
        uint256 vestedAmount   = rdToken.issuanceRate() * warpTime_ / 1e30;

        rdToken_balanceOf_staker_change = _toInt256(mintAmount_);
        rdToken_totalSupply_change      = _toInt256(mintAmount_);
        rdToken_freeAssets_change       = _toInt256(vestedAmount + expectedAssets);  // Captures vested amount
        rdToken_totalAssets_change      = _toInt256(expectedAssets);
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = _toInt256(warpTime_);

        asset_balanceOf_staker_change         = - _toInt256(expectedAssets);
        asset_balanceOf_rdToken_change        =   _toInt256(expectedAssets);
        asset_allowance_staker_rdToken_change = - _toInt256(expectedAssets);

        address staker = address(new Staker());

        _assertMint(staker, mintAmount_, true);
    }

    function test_mint_singleUser_postVesting() public {
        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 20e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), 5e18, 10 seconds);  // Vest full 5e18 tokens

        vm.warp(START + 11 seconds);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.25e18);  // 1 * (20 + 5) / 20

        uint256 mintAmount = 10e18;

        rdToken_balanceOf_staker_change = 10e18;    // 10e18 / 1.25
        rdToken_totalSupply_change      = 10e18;
        rdToken_freeAssets_change       = 17.5e18;  // Captures vested amount
        rdToken_totalAssets_change      = 12.5e18;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = - _toInt256(rdToken.issuanceRate());  // Gets set to zero
        rdToken_lastUpdated_change      = 11 seconds;

        asset_balanceOf_staker_change         = - 12.5e18;
        asset_balanceOf_rdToken_change        =   12.5e18;
        asset_allowance_staker_rdToken_change = - 12.5e18;

        address staker = address(new Staker());

        _assertMint(staker, mintAmount, false);
    }

    function testFuzz_mint_singleUser_postVesting(uint256 initialAmount_, uint256 mintAmount_, uint256 vestingAmount_) public {
        Staker setupStaker = new Staker();

        initialAmount_ = constrictToRange(initialAmount_, 1, 1e29);
        mintAmount_    = constrictToRange(mintAmount_,    1, 1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1, 1e29);

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 20e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, 10 seconds);

        vm.warp(START + 11 seconds);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        uint256 expectedAssets = mintAmount_ * rdToken.totalAssets() / rdToken.totalSupply();

        rdToken_balanceOf_staker_change = _toInt256(mintAmount_);
        rdToken_totalSupply_change      = _toInt256(mintAmount_);
        rdToken_freeAssets_change       = _toInt256(vestingAmount_ + expectedAssets);  // Captures vested amount
        rdToken_totalAssets_change      = _toInt256(expectedAssets);
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = - _toInt256(rdToken.issuanceRate());  // Gets set to zero
        rdToken_lastUpdated_change      = 11 seconds;

        asset_balanceOf_staker_change         = - _toInt256(expectedAssets);
        asset_balanceOf_rdToken_change        =   _toInt256(expectedAssets);
        asset_allowance_staker_rdToken_change = - _toInt256(expectedAssets);

        address staker = address(new Staker());

        _assertMint(staker, mintAmount_, true);
    }

    function testFuzz_mint_multiUser_midVesting(
        uint256 initialAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_,
        bytes32 mintSeed_,
        bytes32 warpSeed_
    )
        public
    {
        initialAmount_ = constrictToRange(initialAmount_, 1,      1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1,      1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 days, 365 days);

        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 1e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        for (uint256 i = 1; i < 11; ++i) {
            uint256 mintAmount = uint256(keccak256(abi.encodePacked(mintSeed_, i)));
            uint256 warpTime   = uint256(keccak256(abi.encodePacked(warpSeed_, i)));

            mintAmount = constrictToRange(mintAmount, 1, 1e29);
            warpTime   = constrictToRange(warpTime,   0, vestingPeriod_ / 10);  // Needs to be smaller than vestingPeriod_ so we can warp during for loop

            vm.warp(block.timestamp + warpTime);

            uint256 expectedAssets = mintAmount * rdToken.totalAssets() / rdToken.totalSupply();
            uint256 vestedAmount   = rdToken.issuanceRate() * warpTime / 1e30;

            rdToken_balanceOf_staker_change = _toInt256(mintAmount);
            rdToken_totalSupply_change      = _toInt256(mintAmount);
            rdToken_freeAssets_change       = _toInt256(vestedAmount + expectedAssets);  // Captures vested amount
            rdToken_totalAssets_change      = _toInt256(expectedAssets);
            rdToken_convertToAssets_change  = 0;
            rdToken_convertToShares_change  = 0;
            rdToken_issuanceRate_change     = 0;
            rdToken_lastUpdated_change      = _toInt256(warpTime);

            asset_balanceOf_staker_change         = - _toInt256(expectedAssets);
            asset_balanceOf_rdToken_change        =   _toInt256(expectedAssets);
            asset_allowance_staker_rdToken_change = - _toInt256(expectedAssets);

            address staker = address(new Staker());

            _assertMint(staker, mintAmount, true);
        }
    }

    function testFuzz_mint_multiUser_postVesting(uint256 initialAmount_, uint256 vestingAmount_, uint256 vestingPeriod_, bytes32 seed_) public {
        initialAmount_ = constrictToRange(initialAmount_, 1, 1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1, 1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1, 365 days);

        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 1e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + vestingPeriod_ + 1);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        // Do another deposit to set all params to be uniform
        _depositAsset(address(asset), address(setupStaker), 1e18);

        for (uint256 i = 1; i < 11; ++i) {
            uint256 mintAmount = uint256(keccak256(abi.encodePacked(seed_, i)));

            mintAmount = constrictToRange(mintAmount, 1, 1e29);

            uint256 expectedAssets = mintAmount * rdToken.totalAssets() / rdToken.totalSupply();

            rdToken_balanceOf_staker_change = _toInt256(mintAmount);
            rdToken_totalSupply_change      = _toInt256(mintAmount);
            rdToken_freeAssets_change       = _toInt256(expectedAssets);  // Captures vested amount
            rdToken_totalAssets_change      = _toInt256(expectedAssets);
            rdToken_convertToAssets_change  = 0;
            rdToken_convertToShares_change  = 0;
            rdToken_issuanceRate_change     = 0;
            rdToken_lastUpdated_change      = 0;

            asset_balanceOf_staker_change         = - _toInt256(expectedAssets);
            asset_balanceOf_rdToken_change        =   _toInt256(expectedAssets);
            asset_allowance_staker_rdToken_change = - _toInt256(expectedAssets);

            address staker = address(new Staker());

            _assertMint(staker, mintAmount, true);
        }
    }

}

contract MintWithPermitFailureTests is RDTTestBase {

    address staker;
    address notStaker;

    uint256 stakerPrivateKey    = 1;
    uint256 notStakerPrivateKey = 2;

    function setUp() public override virtual {
        super.setUp();

        staker    = vm.addr(stakerPrivateKey);
        notStaker = vm.addr(notStakerPrivateKey);
    }

    function test_mintWithPermit_zeroAddress() public {
        uint256 mintAmount = 1e18;
        uint256 maxAssets = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), maxAssets);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(staker, address(rdToken), maxAssets, deadline, stakerPrivateKey);

        vm.startPrank(staker);

        vm.expectRevert(bytes("ERC20:P:MALLEABLE"));
        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, 17, r, s);

        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);
    }

    function test_mintWithPermit_notStakerSignature() public {
        uint256 mintAmount = 1e18;
        uint256 maxAssets = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), maxAssets);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(notStaker, address(rdToken), maxAssets, deadline, notStakerPrivateKey);

        vm.startPrank(staker);

        vm.expectRevert(bytes("ERC20:P:INVALID_SIGNATURE"));
        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);

        ( v, r, s ) = _getValidPermitSignature(staker, address(rdToken), maxAssets, deadline, stakerPrivateKey);

        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);

    }

    function test_mintWithPermit_pastDeadline() public {
        uint256 mintAmount = 1e18;
        uint256 maxAssets = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), maxAssets);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(staker, address(rdToken), maxAssets, deadline, stakerPrivateKey);

        vm.startPrank(staker);

        vm.warp(deadline + 1);

        vm.expectRevert(bytes("ERC20:P:EXPIRED"));
        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);

        vm.warp(deadline);

        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);
    }

    function test_mintWithPermit_insufficientPermit() public {
        uint256 mintAmount = 1e18;
        uint256 maxAssets = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), maxAssets);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(staker, address(rdToken), maxAssets - 1, deadline, stakerPrivateKey);

        vm.startPrank(staker);

        vm.expectRevert(bytes("RDT:MWP:INSUFFICIENT_PERMIT"));
        rdToken.mintWithPermit(mintAmount, staker, maxAssets - 1, deadline, v, r, s);

        ( v, r, s ) = _getValidPermitSignature(staker, address(rdToken), maxAssets, deadline, stakerPrivateKey);

        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);
    }

    function test_mintWithPermit_replay() public {
        uint256 mintAmount = 1e18;
        uint256 maxAssets = rdToken.previewMint(mintAmount);

        asset.mint(address(staker), maxAssets * 2);

        ( uint8 v, bytes32 r, bytes32 s ) = _getValidPermitSignature(staker, address(rdToken), maxAssets, deadline, stakerPrivateKey);

        vm.startPrank(staker);

        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);

        vm.expectRevert(bytes("ERC20:P:INVALID_SIGNATURE"));
        rdToken.mintWithPermit(mintAmount, staker, maxAssets, deadline, v, r, s);
    }

}

contract MintWithPermitTests is RDTSuccessTestBase {

    function test_mintWithPermit_singleUser_preVesting() public {
        uint256 mintAmount = 1000;

        rdToken_balanceOf_staker_change = 1000;
        rdToken_totalSupply_change      = 1000;
        rdToken_freeAssets_change       = 1000;
        rdToken_totalAssets_change      = 1000;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = _toInt256(START);  // First deposit updates `lastUpdated`

        asset_balanceOf_staker_change         = -1000;
        asset_balanceOf_rdToken_change        = 1000;
        asset_nonces_change                   = 1;
        asset_allowance_staker_rdToken_change = 0;

        address staker = vm.addr(1);

        _assertMintWithPermit(staker, 1, mintAmount, false);
    }

    function testFuzz_mintWithPermit_singleUser_preVesting(uint256 mintAmount_) public {
        mintAmount_ = constrictToRange(mintAmount_, 1, 1e29);

        rdToken_balanceOf_staker_change = _toInt256(mintAmount_);
        rdToken_totalSupply_change      = _toInt256(mintAmount_);
        rdToken_freeAssets_change       = _toInt256(mintAmount_);
        rdToken_totalAssets_change      = _toInt256(mintAmount_);
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = _toInt256(START);  // First deposit updates `lastUpdated`

        asset_balanceOf_staker_change         = - _toInt256(mintAmount_);
        asset_balanceOf_rdToken_change        =   _toInt256(mintAmount_);
        asset_nonces_change                   = 1;
        asset_allowance_staker_rdToken_change = 0;

        address staker = vm.addr(1);

        _assertMintWithPermit(staker, 1, mintAmount_, false);
    }

    function test_mintWithPermit_singleUser_midVesting() public {
        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 20e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), 10e18, 10 seconds);  // Vest full 5e18 tokens

        vm.warp(START + 5 seconds);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.25e18);  // 1 * (20 + 5) / 20

        rdToken_balanceOf_staker_change = 10e18;
        rdToken_totalSupply_change      = 10e18;
        rdToken_freeAssets_change       = 17.5e18;  // Captures vested amount
        rdToken_totalAssets_change      = 12.5e18;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = 5 seconds;

        asset_balanceOf_staker_change         = -12.5e18;
        asset_balanceOf_rdToken_change        =  12.5e18;
        asset_nonces_change                   = 1;
        asset_allowance_staker_rdToken_change = 0;

        address staker = vm.addr(1);

        _assertMintWithPermit(staker, 1, 10e18, false);
    }

    function testFuzz_mintWithPermit_singleUser_midVesting(uint256 initialAmount_, uint256 mintAmount_, uint256 vestingAmount_, uint256 vestingPeriod_, uint256 warpTime_) public {
        Staker setupStaker = new Staker();

        initialAmount_ = constrictToRange(initialAmount_, 1,         1e6);  // Kept smaller since its just needed to increase totalSupply
        mintAmount_    = constrictToRange(mintAmount_,    1,         1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1,         1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 seconds, 365 days);
        warpTime_      = constrictToRange(warpTime_,      1 seconds, vestingPeriod_);

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), initialAmount_);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + warpTime_);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        uint256 expectedAssets = mintAmount_ * rdToken.totalAssets() / rdToken.totalSupply();
        uint256 vestedAmount   = rdToken.issuanceRate() * warpTime_ / 1e30;

        rdToken_balanceOf_staker_change = _toInt256(mintAmount_);
        rdToken_totalSupply_change      = _toInt256(mintAmount_);
        rdToken_freeAssets_change       = _toInt256(vestedAmount + expectedAssets);  // Captures vested amount
        rdToken_totalAssets_change      = _toInt256(expectedAssets);
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = _toInt256(warpTime_);

        asset_balanceOf_staker_change         = - _toInt256(expectedAssets);
        asset_balanceOf_rdToken_change        =   _toInt256(expectedAssets);
        asset_nonces_change                   = 1;
        asset_allowance_staker_rdToken_change = 0;

        address staker = vm.addr(1);

        _assertMintWithPermit(staker, 1, mintAmount_, true);
    }

    function test_mintWithPermit_singleUser_postVesting() public {
        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 20e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), 5e18, 10 seconds);  // Vest full 5e18 tokens

        vm.warp(START + 11 seconds);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        assertEq(rdToken.convertToAssets(sampleSharesToConvert), 1.25e18);  // 1 * (20 + 5) / 20

        uint256 mintAmount = 10e18;

        rdToken_balanceOf_staker_change = 10e18;    // 10e18 / 1.25
        rdToken_totalSupply_change      = 10e18;
        rdToken_freeAssets_change       = 17.5e18;  // Captures vested amount
        rdToken_totalAssets_change      = 12.5e18;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = - _toInt256(rdToken.issuanceRate());  // Gets set to zero
        rdToken_lastUpdated_change      = 11 seconds;

        asset_balanceOf_staker_change         = - 12.5e18;
        asset_balanceOf_rdToken_change        =   12.5e18;
        asset_nonces_change                   = 1;
        asset_allowance_staker_rdToken_change = 0;

        address staker = vm.addr(1);

        _assertMintWithPermit(staker, 1, mintAmount, false);
    }

    function testFuzz_mintWithPermit_singleUser_postVesting(uint256 initialAmount_, uint256 mintAmount_, uint256 vestingAmount_) public {
        Staker setupStaker = new Staker();

        initialAmount_ = constrictToRange(initialAmount_, 1, 1e29);
        mintAmount_    = constrictToRange(mintAmount_,    1, 1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1, 1e29);

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 20e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, 10 seconds);

        vm.warp(START + 11 seconds);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        mintAmount_ = constrictToRange(mintAmount_, 1, 1e29);

        uint256 expectedAssets = mintAmount_ * rdToken.totalAssets() / rdToken.totalSupply();

        rdToken_balanceOf_staker_change = _toInt256(mintAmount_);
        rdToken_totalSupply_change      = _toInt256(mintAmount_);
        rdToken_freeAssets_change       = _toInt256(vestingAmount_ + expectedAssets);  // Captures vested amount
        rdToken_totalAssets_change      = _toInt256(expectedAssets);
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = - _toInt256(rdToken.issuanceRate());  // Gets set to zero
        rdToken_lastUpdated_change      = 11 seconds;

        asset_balanceOf_staker_change         = - _toInt256(expectedAssets);
        asset_balanceOf_rdToken_change        =   _toInt256(expectedAssets);
        asset_nonces_change                   = 1;
        asset_allowance_staker_rdToken_change = 0;

        address staker = vm.addr(1);

        _assertMintWithPermit(staker, 1, mintAmount_, true);
    }

    function testFuzz_mintWithPermit_multiUser_midVesting(
        uint256 initialAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_,
        bytes32 mintSeed_,
        bytes32 warpSeed_
    )
        public
    {
        initialAmount_ = constrictToRange(initialAmount_, 1,      1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1,      1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 days, 365 days);

        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 1e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        for (uint256 i = 1; i < 11; ++i) {
            uint256 mintAmount = uint256(keccak256(abi.encodePacked(mintSeed_, i)));
            uint256 warpTime   = uint256(keccak256(abi.encodePacked(warpSeed_, i)));

            mintAmount = constrictToRange(mintAmount, 1, 1e29);
            warpTime   = constrictToRange(warpTime,   0, vestingPeriod_ / 10);  // Needs to be smaller than vestingPeriod_ so we can warp during for loop

            vm.warp(block.timestamp + warpTime);

            uint256 expectedAssets = mintAmount * rdToken.totalAssets() / rdToken.totalSupply();
            uint256 vestedAmount   = rdToken.issuanceRate() * warpTime / 1e30;

            rdToken_balanceOf_staker_change = _toInt256(mintAmount);
            rdToken_totalSupply_change      = _toInt256(mintAmount);
            rdToken_freeAssets_change       = _toInt256(vestedAmount + expectedAssets);  // Captures vested amount
            rdToken_totalAssets_change      = _toInt256(expectedAssets);
            rdToken_convertToAssets_change  = 0;
            rdToken_convertToShares_change  = 0;
            rdToken_issuanceRate_change     = 0;
            rdToken_lastUpdated_change      = _toInt256(warpTime);

            asset_balanceOf_staker_change         = - _toInt256(expectedAssets);
            asset_balanceOf_rdToken_change        =   _toInt256(expectedAssets);
            asset_nonces_change                   = 1;
            asset_allowance_staker_rdToken_change = 0;

            address staker = vm.addr(i);

            _assertMintWithPermit(staker, i, mintAmount, true);
        }
    }

    function testFuzz_mintWithPermit_multiUser_postVesting(uint256 initialAmount_, uint256 vestingAmount_, uint256 vestingPeriod_, bytes32 seed_) public {
        initialAmount_ = constrictToRange(initialAmount_, 1, 1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1, 1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1, 365 days);

        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 1e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + vestingPeriod_ + 1);  // To demonstrate `lastUpdated` and `issuanceRate` change, as well as vesting

        // Do another deposit to set all params to be uniform
        _depositAsset(address(asset), address(setupStaker), 1e18);

        for (uint256 i = 1; i < 11; ++i) {
            uint256 mintAmount = uint256(keccak256(abi.encodePacked(seed_, i)));

            mintAmount = constrictToRange(mintAmount, 1, 1e29);

            uint256 expectedAssets = mintAmount * rdToken.totalAssets() / rdToken.totalSupply();

            rdToken_balanceOf_staker_change = _toInt256(mintAmount);
            rdToken_totalSupply_change      = _toInt256(mintAmount);
            rdToken_freeAssets_change       = _toInt256(expectedAssets);  // Captures vested amount
            rdToken_totalAssets_change      = _toInt256(expectedAssets);
            rdToken_convertToAssets_change  = 0;
            rdToken_convertToShares_change  = 0;
            rdToken_issuanceRate_change     = 0;
            rdToken_lastUpdated_change      = 0;

            asset_balanceOf_staker_change         = - _toInt256(expectedAssets);
            asset_balanceOf_rdToken_change        =   _toInt256(expectedAssets);
            asset_nonces_change                   = 1;
            asset_allowance_staker_rdToken_change = 0;

            address staker = vm.addr(i);

            _assertMintWithPermit(staker, i, mintAmount, true);
        }
    }

}

contract RedeemCallerNotOwnerTests is RDTSuccessTestBase {

    Staker caller;
    Staker staker;

    function setUp() public override {
        super.setUp();
        caller = new Staker();
        staker = new Staker();
    }

    function test_redeem_callerNotOwner_singleUser_preVesting() public {
        _depositAsset(address(asset), address(staker), 1000);

        staker.erc20_approve(address(rdToken), address(caller), 1000);

        rdToken_allowance_staker_caller_change = -1000;
        rdToken_balanceOf_staker_change        = -1000;
        rdToken_totalSupply_change             = -1000;
        rdToken_freeAssets_change              = -1000;
        rdToken_totalAssets_change             = -1000;
        rdToken_convertToAssets_change         = 0;
        rdToken_convertToShares_change         = 0;
        rdToken_issuanceRate_change            = 0;
        rdToken_lastUpdated_change             = 0;

        asset_balanceOf_caller_change  = 1000;
        asset_balanceOf_staker_change  = 0;
        asset_balanceOf_rdToken_change = -1000;

        _assertRedeemCallerNotOwner(address(caller), address(staker), 1000, false);
    }

    // TODO: Fuzz approve amount.
    function testFuzz_redeem_callerNotOwner_singleUser_preVesting(uint256 depositAmount_, uint256 redeemAmount_) public {
        depositAmount_ = constrictToRange(depositAmount_, 1, 1e29);
        redeemAmount_  = constrictToRange(redeemAmount_,  1, depositAmount_);

        _depositAsset(address(asset), address(staker), depositAmount_);

        staker.erc20_approve(address(rdToken), address(caller), redeemAmount_);

        rdToken_allowance_staker_caller_change = - _toInt256(redeemAmount_);
        rdToken_balanceOf_staker_change        = - _toInt256(redeemAmount_);
        rdToken_totalSupply_change             = - _toInt256(redeemAmount_);
        rdToken_freeAssets_change              = - _toInt256(redeemAmount_);
        rdToken_totalAssets_change             = - _toInt256(redeemAmount_);
        rdToken_convertToAssets_change         = 0;
        rdToken_convertToShares_change         = 0;
        rdToken_issuanceRate_change            = 0;
        rdToken_lastUpdated_change             = 0;

        asset_balanceOf_caller_change  = _toInt256(redeemAmount_);
        asset_balanceOf_staker_change  = 0;
        asset_balanceOf_rdToken_change = - _toInt256(redeemAmount_);

        _assertRedeemCallerNotOwner(address(caller), address(staker), redeemAmount_, true);
    }

    function test_redeem_callerNotOwner_singleUser_midVesting() public {
        _depositAsset(address(asset), address(staker), 100e18);
        _transferAndUpdateVesting(address(asset), address(rdToken), 10e18, 200 seconds);

        vm.warp(START + 100 seconds);  // Vest 5e18 tokens

        staker.erc20_approve(address(rdToken), address(caller), 20e18);

        rdToken_allowance_staker_caller_change = -20e18;
        rdToken_balanceOf_staker_change        = -20e18;
        rdToken_totalSupply_change             = -20e18;
        rdToken_freeAssets_change              = -16e18;  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw (+5 - 21)
        rdToken_totalAssets_change             = -21e18;  // 20 * 1.05
        rdToken_convertToAssets_change         = 0;
        rdToken_convertToShares_change         = 0;
        rdToken_issuanceRate_change            = 0;
        rdToken_lastUpdated_change             = 100 seconds;

        asset_balanceOf_caller_change  = 21e18;
        asset_balanceOf_staker_change  = 0;
        asset_balanceOf_rdToken_change = -21e18;

        _assertRedeemCallerNotOwner(address(caller), address(staker), 20e18, false);
    }

    // TODO: Fuzz approve amount.
    function testFuzz_redeem_callerNotOwner_singleUser_midVesting(
        uint256 depositAmount_,
        uint256 redeemAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_,
        uint256 warpTime_
    ) public {
        depositAmount_ = constrictToRange(depositAmount_, 1, 1e29);
        redeemAmount_  = constrictToRange(redeemAmount_,  1, depositAmount_);
        vestingAmount_ = constrictToRange(vestingAmount_, 1, 1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1, 100 days);
        warpTime_      = constrictToRange(warpTime_,      1, vestingPeriod_);

        _depositAsset(address(asset), address(staker), depositAmount_);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + warpTime_);

        uint256 expectedWithdrawnFunds = redeemAmount_ * rdToken.totalAssets() / rdToken.totalSupply();
        uint256 vestedAmount           = rdToken.issuanceRate() * warpTime_ / 1e30;

        staker.erc20_approve(address(rdToken), address(caller), redeemAmount_);

        rdToken_allowance_staker_caller_change = - _toInt256(redeemAmount_);
        rdToken_balanceOf_staker_change        = - _toInt256(redeemAmount_);
        rdToken_totalSupply_change             = - _toInt256(redeemAmount_);
        rdToken_totalAssets_change             = - _toInt256(expectedWithdrawnFunds);
        rdToken_freeAssets_change              =   _toInt256(vestedAmount) - _toInt256(expectedWithdrawnFunds);  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw
        rdToken_convertToAssets_change         = 0;
        rdToken_convertToShares_change         = 0;
        rdToken_issuanceRate_change            = 0;
        rdToken_lastUpdated_change             = _toInt256(warpTime_);

        asset_balanceOf_caller_change  = _toInt256(expectedWithdrawnFunds);
        asset_balanceOf_staker_change  = 0;
        asset_balanceOf_rdToken_change = - _toInt256(expectedWithdrawnFunds);

        _assertRedeemCallerNotOwner(address(caller), address(staker), redeemAmount_, true);
    }

    function test_redeem_callerNotOwner_singleUser_postVesting() public {
        _depositAsset(address(asset), address(staker), 100e18);
        _transferAndUpdateVesting(address(asset), address(rdToken), 10e18, 200 seconds);

        vm.warp(START + 201 seconds);  // Vest 5e18 tokens

        staker.erc20_approve(address(rdToken), address(caller), 20e18);

        rdToken_allowance_staker_caller_change = -20e18;
        rdToken_balanceOf_staker_change        = -20e18;
        rdToken_totalSupply_change             = -20e18;
        rdToken_freeAssets_change              = -12e18;  // freeAssets gets updated to reflects 10e18 vested tokens during withdraw (+10 - 22)
        rdToken_totalAssets_change             = -22e18;  // 20 * 1.1
        rdToken_convertToAssets_change         = 0;
        rdToken_convertToShares_change         = 0;
        rdToken_issuanceRate_change            = -(0.05e18 * 1e30);  // Gets set to zero.
        rdToken_lastUpdated_change             = 201 seconds;

        asset_balanceOf_caller_change  = 22e18;
        asset_balanceOf_staker_change  = 0;
        asset_balanceOf_rdToken_change = -22e18;

        _assertRedeemCallerNotOwner(address(caller), address(staker), 20e18, false);
    }

    function testFuzz_redeem_callerNotOwner_singleUser_postVesting(
        uint256 depositAmount_,
        uint256 redeemAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_
    )
        public
    {
        depositAmount_ = constrictToRange(depositAmount_, 1, 1e29);
        redeemAmount_  = constrictToRange(redeemAmount_,  1, depositAmount_);
        vestingAmount_ = constrictToRange(vestingAmount_, 1, 1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1, 100 days);

        _depositAsset(address(asset), address(staker), depositAmount_);
        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + vestingPeriod_ + 1 seconds);

        uint256 expectedWithdrawnFunds = rdToken.previewRedeem(redeemAmount_);

        staker.erc20_approve(address(rdToken), address(caller), redeemAmount_);

        rdToken_allowance_staker_caller_change = - _toInt256(redeemAmount_);
        rdToken_balanceOf_staker_change        = - _toInt256(redeemAmount_);
        rdToken_totalSupply_change             = - _toInt256(redeemAmount_);
        rdToken_totalAssets_change             = - _toInt256(expectedWithdrawnFunds);
        rdToken_freeAssets_change              =   _toInt256(vestingAmount_) - _toInt256(expectedWithdrawnFunds);  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw
        rdToken_convertToAssets_change         = 0;
        rdToken_convertToShares_change         = 0;
        rdToken_issuanceRate_change            = 0;
        rdToken_lastUpdated_change             = _toInt256(vestingPeriod_ + 1 seconds);

        asset_balanceOf_caller_change  = _toInt256(expectedWithdrawnFunds);
        asset_balanceOf_staker_change  = 0;
        asset_balanceOf_rdToken_change = - _toInt256(expectedWithdrawnFunds);

        _assertRedeemCallerNotOwner(address(caller), address(staker), redeemAmount_, true);
    }

    function testFuzz_redeem_callerNotOwner_multiUser_midVesting(
        uint256 iterations_,
        uint256 initialAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_,
        bytes32 depositSeed_,
        bytes32 redeemSeed_,
        bytes32 warpSeed_
    )
        public
    {
        iterations_    = constrictToRange(iterations_,    10,  20);
        initialAmount_ = constrictToRange(initialAmount_, 1e6, 1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1e6, 1e29);

        uint256 initWarpTime;
        initWarpTime   = constrictToRange(initWarpTime,   1 seconds,             100 days);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 days + initWarpTime, 1e29);

        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 1e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        // Warp into middle of vestingPeriod so exchangeRate is greater than zero for all new deposits
        vm.warp(START + initWarpTime);

        Staker[] memory stakers = new Staker[](iterations_);

        for (uint256 i; i < iterations_; ++i) {
            stakers[i] = new Staker();

            uint256 depositAmount = uint256(keccak256(abi.encodePacked(depositSeed_, i)));

            // Get minimum deposit to avoid ZERO_SHARES.
            uint256 minDeposit = _getMinDeposit(address(rdToken));
            depositAmount      = constrictToRange(depositAmount, minDeposit, 1e29 + 1);  // + 1 since we round up in min deposit.

            _depositAsset(address(asset), address(stakers[i]), depositAmount);
        }

        for (uint256 i; i < iterations_; ++i) {
            caller = new Staker();

            uint256 redeemAmount = uint256(keccak256(abi.encodePacked(redeemSeed_, i)));
            uint256 warpTime     = uint256(keccak256(abi.encodePacked(warpSeed_,   i)));

            redeemAmount = constrictToRange(redeemAmount, 1, rdToken.balanceOf(address(stakers[i])));
            warpTime     = constrictToRange(warpTime,     0, (vestingPeriod_ - initWarpTime) / iterations_);

            vm.warp(block.timestamp + warpTime);

            uint256 expectedWithdrawnFunds = rdToken.previewRedeem(redeemAmount);
            uint256 vestedAmount           = rdToken.issuanceRate() * warpTime / 1e30;

            stakers[i].erc20_approve(address(rdToken), address(caller), redeemAmount);

            rdToken_allowance_staker_caller_change = - _toInt256(redeemAmount);
            rdToken_balanceOf_staker_change        = - _toInt256(redeemAmount);
            rdToken_totalSupply_change             = - _toInt256(redeemAmount);
            rdToken_totalAssets_change             = - _toInt256(expectedWithdrawnFunds);
            rdToken_freeAssets_change              =   _toInt256(vestedAmount) - _toInt256(expectedWithdrawnFunds);  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw
            rdToken_convertToAssets_change         = 0;
            rdToken_convertToShares_change         = 0;
            rdToken_issuanceRate_change            = 0;
            rdToken_lastUpdated_change             = _toInt256(warpTime);

            asset_balanceOf_caller_change  = _toInt256(expectedWithdrawnFunds);
            asset_balanceOf_staker_change  = 0;
            asset_balanceOf_rdToken_change = - _toInt256(expectedWithdrawnFunds);

            _assertRedeemCallerNotOwner(address(caller), address(stakers[i]), redeemAmount, true);
        }
    }

    // function testFuzz_redeem_callerNotOwner_multiUser_postVesting(
    //     uint256 iterations_,
    //     uint256 initialAmount_,
    //     uint256 vestingAmount_,
    //     uint256 vestingPeriod_,
    //     bytes32 depositSeed_,
    //     bytes32 redeemSeed_,
    //     bytes32 warpSeed_
    // )
    //     public
    // {
    //     initialAmount_ = constrictToRange(initialAmount_, 1e6,    1e29);
    //     vestingAmount_ = constrictToRange(vestingAmount_, 1e6,    1e29);
    //     vestingPeriod_ = constrictToRange(vestingPeriod_, 1 days, 1e29);

    //     Staker setupStaker = new Staker();

    //     // Do a deposit so that totalSupply is non-zero
    //     _depositAsset(address(asset), address(setupStaker), 1e18);

    //     _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

    //     vm.warp(START + vestingPeriod_ + 12 hours);  // Warp into vestingPeriod so exchangeRate is greater than one for all new deposits

    //     Staker[] memory stakers = new Staker[](iterations_);

    //     for (uint256 i; i < iterations_; ++i) {
    //         stakers[i] = new Staker();

    //         uint256 depositAmount = uint256(keccak256(abi.encodePacked(depositSeed_, i)));

    //         // Get minimum deposit to avoid ZERO_SHARES.
    //         uint256 minDeposit = _getMinDeposit(address(rdToken));
    //         depositAmount      = constrictToRange(depositAmount, minDeposit, 1e29 + 1);  // + 1 since we round up in min deposit.

    //         _depositAsset(address(asset), address(stakers[i]), depositAmount);
    //     }

    //     for (uint256 i; i < iterations_; ++i) {
    //         caller = new Staker();

    //         uint256 redeemAmount = uint256(keccak256(abi.encodePacked(redeemSeed_, i)));
    //         uint256 warpTime     = uint256(keccak256(abi.encodePacked(warpSeed_,   i)));

    //         redeemAmount = constrictToRange(redeemAmount, 1, rdToken.balanceOf(address(stakers[i])));
    //         warpTime     = constrictToRange(warpTime,     0, (vestingPeriod_ - 12 hours) / iterations_);

    //         vm.warp(block.timestamp + warpTime);

    //         uint256 expectedWithdrawnFunds = rdToken.previewRedeem(redeemAmount);
    //         uint256 vestedAmount           = rdToken.issuanceRate() * warpTime / 1e30;

    //         stakers[i].erc20_approve(address(rdToken), address(caller), redeemAmount);

    //         rdToken_allowance_staker_caller_change = - _toInt256(redeemAmount);
    //         rdToken_balanceOf_staker_change        = - _toInt256(redeemAmount);
    //         rdToken_totalSupply_change             = - _toInt256(redeemAmount);
    //         rdToken_totalAssets_change             = - _toInt256(expectedWithdrawnFunds);
    //         rdToken_freeAssets_change              =   _toInt256(vestedAmount) - _toInt256(expectedWithdrawnFunds);  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw
    //         rdToken_convertToAssets_change         = 0;
    //         rdToken_convertToShares_change         = 0;
    //         rdToken_issuanceRate_change            = 0;
    //         rdToken_lastUpdated_change             = _toInt256(warpTime);

    //         asset_balanceOf_caller_change  = _toInt256(expectedWithdrawnFunds);
    //         asset_balanceOf_staker_change  = 0;
    //         asset_balanceOf_rdToken_change = - _toInt256(expectedWithdrawnFunds);

    //         _assertRedeemCallerNotOwner(address(caller), address(stakers[i]), redeemAmount, true);
    //     }
    // }

}

contract RedeemFailureTests is RDTTestBase {

    Staker staker;

    function setUp() public override virtual {
        super.setUp();
        staker = new Staker();
    }

    function test_redeem_zeroShares(uint256 depositAmount_) public {
        _depositAsset(address(asset), address(staker), depositAmount_ = constrictToRange(depositAmount_, 1, 1e29));

        vm.expectRevert("RDT:B:ZERO_SHARES");
        staker.rdToken_redeem(address(rdToken), 0);

        staker.rdToken_redeem(address(rdToken), 1);
    }

    function test_redeem_burnUnderflow(uint256 depositAmount_) public {
        _depositAsset(address(asset), address(staker), depositAmount_ = constrictToRange(depositAmount_, 1, 1e29));

        vm.expectRevert(ARITHMETIC_ERROR);
        staker.rdToken_redeem(address(rdToken), depositAmount_ + 1);

        staker.rdToken_redeem(address(rdToken), depositAmount_);
    }

    function test_redeem_burnUnderflow_totalAssetsGtTotalSupply_explicitValues() public {
        uint256 depositAmount = 100e18;
        uint256 vestingAmount = 10e18;
        uint256 vestingPeriod = 10 days;
        uint256 warpTime      = 5 days;

        _depositAsset(address(asset), address(staker), depositAmount);
        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        vm.expectRevert(ARITHMETIC_ERROR);
        staker.rdToken_redeem(address(rdToken), 100e18 + 1);

        staker.rdToken_redeem(address(rdToken), 100e18);
    }

    function test_redeem_callerNotOwner_badApproval() public {
        Staker shareOwner    = new Staker();
        Staker notShareOwner = new Staker();

        uint256 depositAmount = 1e18;
        asset.mint(address(shareOwner), depositAmount);

        shareOwner.erc20_approve(address(asset), address(rdToken), depositAmount);
        shareOwner.rdToken_deposit(address(rdToken), depositAmount);

        shareOwner.erc20_approve(address(rdToken), address(notShareOwner), depositAmount - 1);
        vm.expectRevert(ARITHMETIC_ERROR);
        notShareOwner.rdToken_redeem(address(rdToken), depositAmount, address(shareOwner), address(shareOwner));

        shareOwner.erc20_approve(address(rdToken), address(notShareOwner), depositAmount);

        assertEq(rdToken.allowance(address(shareOwner), address(notShareOwner)), depositAmount);

        notShareOwner.rdToken_redeem(address(rdToken), depositAmount, address(notShareOwner), address(shareOwner));

        assertEq(rdToken.allowance(address(shareOwner), address(notShareOwner)), 0);
    }

    function test_redeem_callerNotOwner_infiniteApprovalForCaller() public {
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

}

contract RedeemRevertOnTransfers is RDTTestBase {

    MockRevertingERC20 revertingAsset;
    Staker             staker;

    function setUp() public override virtual {
        revertingAsset = new MockRevertingERC20("MockToken", "MT", 18, address(123));
        rdToken        = new RDT("Revenue Distribution Token", "RDT", address(this), address(revertingAsset), 1e30);
        staker         = new Staker();

        vm.warp(START);  // Warp to non-zero timestamp
    }

    function test_redeem_revertOnTransfer(uint256 depositAmount_, uint256 redeemAmount_) public {
        depositAmount_ = constrictToRange(depositAmount_, 1, 1e29);
        redeemAmount_  = constrictToRange(redeemAmount_,  1, depositAmount_);

        revertingAsset.mint(address(staker), depositAmount_);

        staker.erc20_approve(address(revertingAsset), address(rdToken), depositAmount_);
        staker.rdToken_deposit(address(rdToken), depositAmount_);

        vm.warp(START + 10 days);

        address revertingDestination = revertingAsset.revertingDestination();
        vm.expectRevert(bytes("RDT:B:TRANSFER"));
        staker.rdToken_redeem(address(rdToken), depositAmount_, revertingDestination, address(staker));

        staker.rdToken_redeem(address(rdToken), depositAmount_, address(1), address(staker));
    }

}

contract RedeemTests is RDTSuccessTestBase {

    function test_redeem_singleUser_preVesting() public {
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

        asset_balanceOf_staker_change  = 1000;
        asset_balanceOf_rdToken_change = -1000;

        _assertRedeem(staker, 1000, false);
    }

    function testFuzz_redeem_singleUser_preVesting(uint256 depositAmount_,uint256 redeemAmount_) public {
        depositAmount_ = constrictToRange(depositAmount_, 1, 1e29);
        redeemAmount_  = constrictToRange(redeemAmount_,  1, depositAmount_);

        address staker = address(new Staker());

        _depositAsset(address(asset), staker, depositAmount_);

        rdToken_balanceOf_staker_change = - _toInt256(redeemAmount_);
        rdToken_totalSupply_change      = - _toInt256(redeemAmount_);
        rdToken_freeAssets_change       = - _toInt256(redeemAmount_);
        rdToken_totalAssets_change      = - _toInt256(redeemAmount_);
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = 0;

        asset_balanceOf_staker_change  =   _toInt256(redeemAmount_);
        asset_balanceOf_rdToken_change = - _toInt256(redeemAmount_);

        _assertRedeem(staker, redeemAmount_, true);
    }

    function test_redeem_singleUser_midVesting() public {
        address staker = address(new Staker());

        _depositAsset(address(asset), staker, 100e18);
        _transferAndUpdateVesting(address(asset), address(rdToken), 10e18, 200 seconds);

        vm.warp(block.timestamp + 100 seconds);  // Vest 5e18 tokens

        rdToken_balanceOf_staker_change = -20e18;
        rdToken_totalSupply_change      = -20e18;
        rdToken_freeAssets_change       = -16e18;  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw (+5 - 21)
        rdToken_totalAssets_change      = -21e18;  // 20 * 10.5
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = 100 seconds;

        asset_balanceOf_staker_change  = 21e18;
        asset_balanceOf_rdToken_change = -21e18;

        _assertRedeem(staker, 20e18, false);
    }

    function testFuzz_redeem_singleUser_midVesting(
        uint256 depositAmount_,
        uint256 redeemAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_,
        uint256 warpTime_
    ) public {
        depositAmount_ = constrictToRange(depositAmount_, 1,         1e29);
        redeemAmount_  = constrictToRange(redeemAmount_,  1,         depositAmount_);
        vestingAmount_ = constrictToRange(vestingAmount_, 1,         1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 seconds, 100 days);
        warpTime_      = constrictToRange(warpTime_,      0,         vestingPeriod_);

        address staker = address(new Staker());

        _depositAsset(address(asset), staker, depositAmount_);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + warpTime_);

        uint256 expectedWithdrawnFunds = redeemAmount_ * rdToken.totalAssets() / rdToken.totalSupply();
        uint256 vestedAmount           = rdToken.issuanceRate() * warpTime_ / 1e30;

        rdToken_balanceOf_staker_change = - _toInt256(redeemAmount_);
        rdToken_totalSupply_change      = - _toInt256(redeemAmount_);
        rdToken_totalAssets_change      = - _toInt256(expectedWithdrawnFunds);
        rdToken_freeAssets_change       =   _toInt256(vestedAmount) - _toInt256(expectedWithdrawnFunds);  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = _toInt256(warpTime_);

        asset_balanceOf_staker_change  = _toInt256(expectedWithdrawnFunds);
        asset_balanceOf_rdToken_change = - _toInt256(expectedWithdrawnFunds);

        _assertRedeem(staker, redeemAmount_, true);
    }

    function test_redeem_singleUser_postVesting() public {
        address staker = address(new Staker());

        _depositAsset(address(asset), staker, 100e18);
        _transferAndUpdateVesting(address(asset), address(rdToken), 10e18, 200 seconds);

        vm.warp(START + 201 seconds);  // Vest 5e18 tokens

        rdToken_balanceOf_staker_change = -20e18;
        rdToken_totalSupply_change      = -20e18;
        rdToken_freeAssets_change       = -12e18;  // freeAssets gets updated to reflects 10e18 vested tokens during withdraw (+10 - 22)
        rdToken_totalAssets_change      = -22e18;  // 20 * 1.1
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = -(0.05e18 * 1e30);  // Gets set to zero.
        rdToken_lastUpdated_change      = 201 seconds;

        asset_balanceOf_staker_change  = 22e18;
        asset_balanceOf_rdToken_change = -22e18;

        _assertRedeem(staker, 20e18, false);
    }

    function testFuzz_redeem_singleUser_postVesting(
        uint256 depositAmount_,
        uint256 redeemAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_
    )
        public
    {
        depositAmount_ = constrictToRange(depositAmount_, 1,         1e29);
        redeemAmount_  = constrictToRange(redeemAmount_,  1,         depositAmount_);
        vestingAmount_ = constrictToRange(vestingAmount_, 1,         1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 seconds, 100 days);

        address staker = address(new Staker());

        _depositAsset(address(asset), staker, depositAmount_);
        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + vestingPeriod_ + 1 seconds);

        uint256 expectedWithdrawnFunds = rdToken.previewRedeem(redeemAmount_);

        rdToken_balanceOf_staker_change = - _toInt256(redeemAmount_);
        rdToken_totalSupply_change      = - _toInt256(redeemAmount_);
        rdToken_totalAssets_change      = - _toInt256(expectedWithdrawnFunds);
        rdToken_freeAssets_change       =   _toInt256(vestingAmount_) - _toInt256(expectedWithdrawnFunds);  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = - _toInt256(rdToken.issuanceRate());
        rdToken_lastUpdated_change      =   _toInt256(vestingPeriod_ + 1 seconds);

        asset_balanceOf_staker_change  =   _toInt256(expectedWithdrawnFunds);
        asset_balanceOf_rdToken_change = - _toInt256(expectedWithdrawnFunds);

        _assertRedeem(staker, redeemAmount_, true);
    }

    function testFuzz_redeem_multiUser_midVesting(
        uint256 iterations_,
        uint256 initialAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_,
        bytes32 depositSeed_,
        bytes32 redeemSeed_,
        bytes32 warpSeed_
    )
        public
    {
        iterations_    = constrictToRange(iterations_,    10,  20);
        initialAmount_ = constrictToRange(initialAmount_, 1e6, 1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1e6, 1e29);

        uint256 initWarpTime;
        initWarpTime   = constrictToRange(initWarpTime,   1 seconds,             100 days);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 days + initWarpTime, 1e29);

        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 1e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        // Warp into middle of vestingPeriod so exchangeRate is greater than zero for all new deposits
        vm.warp(START + initWarpTime);

        Staker[] memory stakers = new Staker[](iterations_);

        for (uint256 i; i < iterations_; ++i) {
            stakers[i] = new Staker();

            uint256 depositAmount = uint256(keccak256(abi.encodePacked(depositSeed_, i)));

            // Get minimum deposit to avoid ZERO_SHARES.
            uint256 minDeposit = _getMinDeposit(address(rdToken));
            depositAmount      = constrictToRange(depositAmount, minDeposit, 1e29 + 1);  // + 1 since we round up in min deposit.

            _depositAsset(address(asset), address(stakers[i]), depositAmount);
        }

        for (uint256 i; i < iterations_; ++i) {
            uint256 redeemAmount = uint256(keccak256(abi.encodePacked(redeemSeed_, i)));
            uint256 warpTime     = uint256(keccak256(abi.encodePacked(warpSeed_,   i)));

            redeemAmount = constrictToRange(redeemAmount, 1, rdToken.balanceOf(address(stakers[i])));
            warpTime     = constrictToRange(warpTime,     0, (vestingPeriod_ - initWarpTime) / iterations_);

            vm.warp(block.timestamp + warpTime);

            uint256 expectedWithdrawnFunds = rdToken.previewRedeem(redeemAmount);
            uint256 vestedAmount           = rdToken.issuanceRate() * warpTime / 1e30;

            rdToken_balanceOf_staker_change = - _toInt256(redeemAmount);
            rdToken_totalSupply_change      = - _toInt256(redeemAmount);
            rdToken_totalAssets_change      = - _toInt256(expectedWithdrawnFunds);
            rdToken_freeAssets_change       =   _toInt256(vestedAmount) - _toInt256(expectedWithdrawnFunds);
            rdToken_convertToAssets_change  = 0;
            rdToken_convertToShares_change  = 0;
            rdToken_issuanceRate_change     = 0;
            rdToken_lastUpdated_change      = _toInt256(warpTime);

            asset_balanceOf_staker_change  =   _toInt256(expectedWithdrawnFunds);
            asset_balanceOf_rdToken_change = - _toInt256(expectedWithdrawnFunds);

            _assertRedeem(address(stakers[i]), redeemAmount, true);
        }
    }

    function testFuzz_redeem_multiUser_postVesting(
        uint256 initialAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_,
        bytes32 depositSeed_,
        bytes32 redeemSeed_,
        bytes32 warpSeed_
    )
        public
    {
        initialAmount_ = constrictToRange(initialAmount_, 1e6,    1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1e6,    1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 days, 1e29);

        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 1e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + vestingPeriod_ + 12 hours);  // Warp into vestingPeriod so exchangeRate is greater than zero for all new deposits

        Staker[] memory stakers = new Staker[](10);

        for (uint256 i; i < 10; ++i) {
            stakers[i] = new Staker();

            uint256 depositAmount = uint256(keccak256(abi.encodePacked(depositSeed_, i)));

            // Get minimum deposit to avoid ZERO_SHARES.
            uint256 minDeposit = _getMinDeposit(address(rdToken));
            depositAmount      = constrictToRange(depositAmount, minDeposit, 1e29 + 1);  // + 1 since we round up in min deposit.

            _depositAsset(address(asset), address(stakers[i]), depositAmount);
        }

        for (uint256 i; i < 10; ++i) {
            uint256 redeemAmount = uint256(keccak256(abi.encodePacked(redeemSeed_, i)));
            uint256 warpTime     = uint256(keccak256(abi.encodePacked(warpSeed_,   i)));

            redeemAmount = constrictToRange(redeemAmount, 1, rdToken.balanceOf(address(stakers[i])));
            warpTime     = constrictToRange(warpTime,     0, (vestingPeriod_ - 12 hours) / 10);

            vm.warp(block.timestamp + warpTime);

            uint256 expectedWithdrawnFunds = rdToken.previewRedeem(redeemAmount);
            uint256 vestedAmount           = rdToken.issuanceRate() * warpTime / 1e30;

            rdToken_balanceOf_staker_change = - _toInt256(redeemAmount);
            rdToken_totalSupply_change      = - _toInt256(redeemAmount);
            rdToken_totalAssets_change      = - _toInt256(expectedWithdrawnFunds);
            rdToken_freeAssets_change       =   _toInt256(vestedAmount) - _toInt256(expectedWithdrawnFunds);  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw
            rdToken_convertToAssets_change  = 0;
            rdToken_convertToShares_change  = 0;
            rdToken_issuanceRate_change     = 0;
            rdToken_lastUpdated_change      = _toInt256(warpTime);

            asset_balanceOf_staker_change  =   _toInt256(expectedWithdrawnFunds);
            asset_balanceOf_rdToken_change = - _toInt256(expectedWithdrawnFunds);

            _assertRedeem(address(stakers[i]), redeemAmount, true);
        }
    }

}

contract UpdateVestingScheduleFailureTests is RDTTestBase {

    Staker firstStaker;

    uint256 startingAssets;

    function setUp() public override virtual {
        super.setUp();
        firstStaker = new Staker();

        // Deposit the minimum amount of the asset to allow the vesting schedule updates to occur.
        startingAssets = 1;
        asset.mint(address(firstStaker), startingAssets);
        firstStaker.erc20_approve(address(asset), address(rdToken), startingAssets);
    }

    function test_updateVestingSchedule_zeroSupply() public {
        vm.expectRevert("RDT:UVS:ZERO_SUPPLY");
        rdToken.updateVestingSchedule(100 seconds);

        firstStaker.erc20_approve(address(asset), address(rdToken), 1);
        firstStaker.rdToken_deposit(address(rdToken), 1);

        rdToken.updateVestingSchedule(100 seconds);
    }

}

contract UpdateVestingScheduleTests is RDTTestBase {

    Staker firstStaker;

    uint256 startingAssets;

    function setUp() public override virtual {
        super.setUp();
        firstStaker = new Staker();

        // Deposit the minimum amount of the asset to allow the vesting schedule updates to occur.
        startingAssets = 1;
        asset.mint(address(firstStaker), startingAssets);
        firstStaker.erc20_approve(address(asset), address(rdToken), startingAssets);
        firstStaker.rdToken_deposit(address(rdToken), startingAssets);
    }

    /************************************/
    /*** Single updateVestingSchedule ***/
    /************************************/

    function test_updateVestingSchedule_single() public {
        assertEq(rdToken.freeAssets(),          startingAssets);
        assertEq(rdToken.totalAssets(),         startingAssets);
        assertEq(rdToken.issuanceRate(),        0);
        assertEq(rdToken.lastUpdated(),         START);
        assertEq(rdToken.vestingPeriodFinish(), 0);

        assertEq(asset.balanceOf(address(rdToken)), startingAssets);

        _transferAndUpdateVesting(address(asset), address(rdToken), 1000, 100 seconds);  // 10 tokens per second

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

    function test_updateVestingSchedule_single_roundingDown() public {
        _transferAndUpdateVesting(address(asset), address(rdToken), 1000, 30 seconds);  // 33.3333... tokens per second

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

    function test_updateVestingSchedule_sameTime_shorterVesting() public {
        _transferAndUpdateVesting(address(asset), address(rdToken), 1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), START + 100 seconds);  // Always updates to latest vesting schedule

        _transferAndUpdateVesting(address(asset), address(rdToken), 1000, 20 seconds);
        assertEq(rdToken.issuanceRate(),        100e30);              // (1000 + 1000) / 20 seconds = 100 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), START + 20 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalAssets(), startingAssets);

        vm.warp(START + 20 seconds);

        assertEq(rdToken.totalAssets(), startingAssets + 2000);
    }

    function test_updateVestingSchedule_sameTime_longerVesting_higherRate() public {
        _transferAndUpdateVesting(address(asset), address(rdToken), 1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), START + 100 seconds);  // Always updates to latest vesting schedule

        _transferAndUpdateVesting(address(asset), address(rdToken), 3000, 200 seconds);
        assertEq(rdToken.issuanceRate(),        20e30);                // (3000 + 1000) / 200 seconds = 20 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), START + 200 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalAssets(), startingAssets);

        vm.warp(START + 200 seconds);

        assertEq(rdToken.totalAssets(), startingAssets + 4000);
    }

    function test_updateVestingSchedule_sameTime_longerVesting_lowerRate() public {
        _transferAndUpdateVesting(address(asset), address(rdToken), 1000, 100 seconds);
        assertEq(rdToken.issuanceRate(),        10e30);                // 1000 / 100 seconds = 10 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), START + 100 seconds);  // Always updates to latest vesting schedule

        _transferAndUpdateVesting(address(asset), address(rdToken), 1000, 500 seconds);
        assertEq(rdToken.issuanceRate(),        4e30);                 // (1000 + 1000) / 500 seconds = 4 tokens per second
        assertEq(rdToken.vestingPeriodFinish(), START + 500 seconds);  // Always updates to latest vesting schedule

        assertEq(rdToken.totalAssets(), startingAssets);

        vm.warp(START + 5000 seconds);

        assertEq(rdToken.totalAssets(), startingAssets + 2000);
    }

    /*******************************************************/
    /*** Multiple updateVestingSchedule, different times ***/
    /*******************************************************/

    function test_updateVestingSchedule_diffTime_shorterVesting() public {
        _transferAndUpdateVesting(address(asset), address(rdToken), 1000, 100 seconds);  // 10 tokens per second

        vm.warp(START + 60 seconds);

        assertEq(rdToken.issuanceRate(),        10e30);
        assertEq(rdToken.totalAssets(),         startingAssets + 600);
        assertEq(rdToken.freeAssets(),          startingAssets);
        assertEq(rdToken.vestingPeriodFinish(), START + 100 seconds);

        _transferAndUpdateVesting(address(asset), address(rdToken), 1000, 20 seconds);  // 50 tokens per second

        assertEq(rdToken.issuanceRate(),        70e30);  // (400 + 1000) / 20 seconds = 70 tokens per second
        assertEq(rdToken.totalAssets(),         startingAssets + 600);
        assertEq(rdToken.freeAssets(),          startingAssets + 600);
        assertEq(rdToken.vestingPeriodFinish(), START + 60 seconds + 20 seconds);

        vm.warp(START + 60 seconds + 20 seconds);

        assertEq(rdToken.issuanceRate(), 70e30);
        assertEq(rdToken.totalAssets(),  startingAssets + 2000);
        assertEq(rdToken.freeAssets(),   startingAssets + 600);
    }

    function test_updateVestingSchedule_diffTime_longerVesting_higherRate() public {
        _transferAndUpdateVesting(address(asset), address(rdToken), 1000, 100 seconds);  // 10 tokens per second

        vm.warp(START + 60 seconds);

        assertEq(rdToken.issuanceRate(),        10e30);
        assertEq(rdToken.totalAssets(),         startingAssets + 600);
        assertEq(rdToken.freeAssets(),          startingAssets);
        assertEq(rdToken.vestingPeriodFinish(), START + 100 seconds);

        _transferAndUpdateVesting(address(asset), address(rdToken), 3000, 200 seconds);  // 15 tokens per second

        assertEq(rdToken.issuanceRate(), 17e30);  // (400 + 3000) / 200 seconds = 17 tokens per second
        assertEq(rdToken.totalAssets(),  startingAssets + 600);
        assertEq(rdToken.freeAssets(),   startingAssets + 600);

        vm.warp(START + 60 seconds + 200 seconds);

        assertEq(rdToken.issuanceRate(), 17e30);
        assertEq(rdToken.totalAssets(),  startingAssets + 4000);
        assertEq(rdToken.freeAssets(),   startingAssets + 600);
    }

    function test_updateVestingSchedule_diffTime_longerVesting_lowerRate() public {
        _transferAndUpdateVesting(address(asset), address(rdToken), 1000, 100 seconds);  // 10 tokens per second

        vm.warp(START + 60 seconds);

        assertEq(rdToken.issuanceRate(), 10e30);
        assertEq(rdToken.totalAssets(),  startingAssets + 600);
        assertEq(rdToken.freeAssets(),   startingAssets);

        _transferAndUpdateVesting(address(asset), address(rdToken), 1000, 200 seconds);  // 5 tokens per second

        assertEq(rdToken.issuanceRate(), 7e30);  // (400 + 1000) / 200 seconds = 7 tokens per second
        assertEq(rdToken.totalAssets(),  startingAssets + 600);
        assertEq(rdToken.freeAssets(),   startingAssets + 600);

        vm.warp(START + 60 seconds + 200 seconds);

        assertEq(rdToken.issuanceRate(), 7e30);
        assertEq(rdToken.totalAssets(),  startingAssets + 2000);
        assertEq(rdToken.freeAssets(),   startingAssets + 600);
    }

}

contract WithdrawCallerNotOwnerTests is RDTSuccessTestBase {

    Staker caller;
    Staker staker;

    function setUp() public override {
        super.setUp();
        caller = new Staker();
        staker = new Staker();
    }

    function test_withdraw_callerNotOwner_singleUser_preVesting() public {
        caller = new Staker();
        staker = new Staker();

        _depositAsset(address(asset), address(staker), 1000);

        staker.erc20_approve(address(rdToken), address(caller), 1000);

        rdToken_allowance_staker_caller_change = -1000;
        rdToken_balanceOf_staker_change        = -1000;
        rdToken_totalSupply_change             = -1000;
        rdToken_freeAssets_change              = -1000;
        rdToken_totalAssets_change             = -1000;
        rdToken_convertToAssets_change         = 0;
        rdToken_convertToShares_change         = 0;
        rdToken_issuanceRate_change            = 0;
        rdToken_lastUpdated_change             = 0;

        asset_balanceOf_caller_change  = 1000;
        asset_balanceOf_staker_change  = 0;
        asset_balanceOf_rdToken_change = -1000;

        _assertWithdrawCallerNotOwner(address(caller), address(staker), 1000, false);
    }

    // TODO: Fuzz approve amount.
    function testFuzz_withdraw_callerNotOwner_singleUser_preVesting(uint256 depositAmount_, uint256 withdrawAmount_) public {
        depositAmount_  = constrictToRange(depositAmount_,  1, 1e29);
        withdrawAmount_ = constrictToRange(withdrawAmount_, 1, depositAmount_);

        _depositAsset(address(asset), address(staker), depositAmount_);

        staker.erc20_approve(address(rdToken), address(caller), withdrawAmount_);

        rdToken_allowance_staker_caller_change = - _toInt256(withdrawAmount_);
        rdToken_balanceOf_staker_change        = - _toInt256(withdrawAmount_);
        rdToken_totalSupply_change             = - _toInt256(withdrawAmount_);
        rdToken_freeAssets_change              = - _toInt256(withdrawAmount_);
        rdToken_totalAssets_change             = - _toInt256(withdrawAmount_);
        rdToken_convertToAssets_change         = 0;
        rdToken_convertToShares_change         = 0;
        rdToken_issuanceRate_change            = 0;
        rdToken_lastUpdated_change             = 0;

        asset_balanceOf_caller_change  = _toInt256(withdrawAmount_);
        asset_balanceOf_staker_change  = 0;
        asset_balanceOf_rdToken_change = - _toInt256(withdrawAmount_);

        _assertWithdrawCallerNotOwner(address(caller), address(staker), withdrawAmount_, true);
    }

    function test_withdraw_callerNotOwner_singleUser_midVesting() public {
        _depositAsset(address(asset), address(staker), 100e18);
        _transferAndUpdateVesting(address(asset), address(rdToken), 10e18, 200 seconds);

        vm.warp(START + 100 seconds);  // Vest 5e18 tokens

        staker.erc20_approve(address(rdToken), address(caller), 19.047619047619047620e18);

        rdToken_allowance_staker_caller_change = -19.047619047619047620e18;
        rdToken_balanceOf_staker_change        = -19.047619047619047620e18;  // 20 / 1.05
        rdToken_totalSupply_change             = -19.047619047619047620e18;  // 20 / 1.05
        rdToken_freeAssets_change              = -15e18;  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw
        rdToken_totalAssets_change             = -20e18;
        rdToken_convertToAssets_change         = 0;
        rdToken_convertToShares_change         = 0;
        rdToken_issuanceRate_change            = 0;
        rdToken_lastUpdated_change             = 100 seconds;

        asset_balanceOf_caller_change  = 20e18;
        asset_balanceOf_staker_change  = 0;
        asset_balanceOf_rdToken_change = -20e18;

        _assertWithdrawCallerNotOwner(address(caller), address(staker), 20e18, false);
    }

    // TODO: Fuzz approve amount.
    function testFuzz_withdraw_callerNotOwner_singleUser_midVesting(
        uint256 depositAmount_,
        uint256 withdrawAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_,
        uint256 warpTime_
    ) public {
        depositAmount_ = constrictToRange(depositAmount_, 1,         1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1,         1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 seconds, 100 days);
        warpTime_      = constrictToRange(warpTime_,      0,         vestingPeriod_);

        _depositAsset(address(asset), address(staker), depositAmount_);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + warpTime_);

        uint256 maxWithdrawAmount = depositAmount_ * rdToken.totalAssets() / rdToken.totalSupply();

        withdrawAmount_ = constrictToRange(withdrawAmount_, 1, maxWithdrawAmount);

        uint256 expectedSharesBurned = rdToken.previewWithdraw(withdrawAmount_);
        uint256 vestedAmount         = rdToken.issuanceRate() * warpTime_ / 1e30;

        staker.erc20_approve(address(rdToken), address(caller), expectedSharesBurned);

        rdToken_allowance_staker_caller_change = - _toInt256(expectedSharesBurned);
        rdToken_balanceOf_staker_change        = - _toInt256(expectedSharesBurned);
        rdToken_totalSupply_change             = - _toInt256(expectedSharesBurned);
        rdToken_totalAssets_change             = - _toInt256(withdrawAmount_);
        rdToken_freeAssets_change              =   _toInt256(vestedAmount) - _toInt256(withdrawAmount_);  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw
        rdToken_convertToAssets_change         = 0;
        rdToken_convertToShares_change         = 0;
        rdToken_issuanceRate_change            = 0;
        rdToken_lastUpdated_change             = _toInt256(warpTime_);

        asset_balanceOf_caller_change  = _toInt256(withdrawAmount_);
        asset_balanceOf_staker_change  = 0;
        asset_balanceOf_rdToken_change = - _toInt256(withdrawAmount_);

        _assertWithdrawCallerNotOwner(address(caller), address(staker), withdrawAmount_, true);
    }

    function test_withdraw_callerNotOwner_singleUser_postVesting() public {
        _depositAsset(address(asset), address(staker), 100e18);
        _transferAndUpdateVesting(address(asset), address(rdToken), 10e18, 200 seconds);

        vm.warp(START + 201 seconds);  // Vest 5e18 tokens

        staker.erc20_approve(address(rdToken), address(caller), 18.181818181818181819e18);

        rdToken_allowance_staker_caller_change = -18.181818181818181819e18;
        rdToken_balanceOf_staker_change        = -18.181818181818181819e18;  // 20 / 1.1
        rdToken_totalSupply_change             = -18.181818181818181819e18;  // 20 / 1.1
        rdToken_freeAssets_change              = -10e18;  // freeAssets gets updated to reflects 10e18 vested tokens during withdraw
        rdToken_totalAssets_change             = -20e18;
        rdToken_convertToAssets_change         = 0;
        rdToken_convertToShares_change         = 0;
        rdToken_issuanceRate_change            = -(0.05e18 * 1e30);  // Gets set to zero.
        rdToken_lastUpdated_change             = 201 seconds;

        asset_balanceOf_caller_change  = 20e18;
        asset_balanceOf_staker_change  = 0;
        asset_balanceOf_rdToken_change = -20e18;

        _assertWithdrawCallerNotOwner(address(caller), address(staker), 20e18, false);
    }


    function testFuzz_withdraw_callerNotOwner_singleUser_postVesting(
        uint256 depositAmount_,
        uint256 withdrawAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_
    )
        public
    {
        depositAmount_ = constrictToRange(depositAmount_, 1,         1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1,         1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 seconds, 100 days);

        _depositAsset(address(asset), address(staker), depositAmount_);
        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + vestingPeriod_ + 1 seconds);

        uint256 maxWithdrawAmount = depositAmount_ * rdToken.totalAssets() / rdToken.totalSupply();

        withdrawAmount_ = constrictToRange(withdrawAmount_, 1, maxWithdrawAmount);

        uint256 expectedSharesBurned = rdToken.previewWithdraw(withdrawAmount_);

        staker.erc20_approve(address(rdToken), address(caller), expectedSharesBurned);

        rdToken_allowance_staker_caller_change = - _toInt256(expectedSharesBurned);
        rdToken_balanceOf_staker_change        = - _toInt256(expectedSharesBurned);
        rdToken_totalSupply_change             = - _toInt256(expectedSharesBurned);
        rdToken_totalAssets_change             = - _toInt256(withdrawAmount_);
        rdToken_freeAssets_change              =   _toInt256(vestingAmount_) - _toInt256(withdrawAmount_);
        rdToken_convertToAssets_change         = 0;
        rdToken_convertToShares_change         = 0;
        rdToken_issuanceRate_change            = - _toInt256(rdToken.issuanceRate());
        rdToken_lastUpdated_change             =   _toInt256(vestingPeriod_ + 1 seconds);

        asset_balanceOf_caller_change  = _toInt256(withdrawAmount_);
        asset_balanceOf_staker_change  = 0;
        asset_balanceOf_rdToken_change = - _toInt256(withdrawAmount_);

        _assertWithdrawCallerNotOwner(address(caller), address(staker), withdrawAmount_, true);
    }

    function testFuzz_withdraw_callerNotOwner_multiUser_midVesting(
        uint256 iterations_,
        uint256 initialAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_,
        bytes32 depositSeed_,
        bytes32 withdrawSeed_,
        bytes32 warpSeed_
    )
        public
    {
        iterations_    = constrictToRange(iterations_,    10,  20);
        initialAmount_ = constrictToRange(initialAmount_, 1e6, 1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1e6, 1e29);

        uint256 initWarpTime;
        initWarpTime   = constrictToRange(initWarpTime,   1 seconds,             100 days);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 days + initWarpTime, 1e29);

        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 1e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        // Warp into middle of vestingPeriod so exchangeRate is greater than zero for all new deposits
        vm.warp(START + initWarpTime);

        Staker[] memory stakers = new Staker[](iterations_);

        for (uint256 i; i < iterations_; ++i) {
            stakers[i] = new Staker();

            uint256 depositAmount = uint256(keccak256(abi.encodePacked(depositSeed_, i)));

            // Get minimum deposit to avoid ZERO_SHARES.
            uint256 minDeposit = _getMinDeposit(address(rdToken));
            depositAmount      = constrictToRange(depositAmount, minDeposit, 1e29 + 1);  // + 1 since we round up in min deposit.

            _depositAsset(address(asset), address(stakers[i]), depositAmount);
        }

        for (uint256 i; i < iterations_; ++i) {
            caller = new Staker();

            uint256 withdrawAmount = uint256(keccak256(abi.encodePacked(withdrawSeed_, i)));
            uint256 warpTime       = uint256(keccak256(abi.encodePacked(warpSeed_,     i)));

            {
                uint256 maxWithdrawAmount = rdToken.balanceOf(address(stakers[i])) * rdToken.totalAssets() / rdToken.totalSupply();
                withdrawAmount = constrictToRange(withdrawAmount, 1, maxWithdrawAmount);
            }

            warpTime = constrictToRange(warpTime, 0, (vestingPeriod_ - initWarpTime) / iterations_);

            vm.warp(block.timestamp + warpTime);

            uint256 expectedSharesBurned = rdToken.previewWithdraw(withdrawAmount);
            uint256 vestedAmount         = rdToken.issuanceRate() * warpTime / 1e30;

            stakers[i].erc20_approve(address(rdToken), address(caller), expectedSharesBurned);

            rdToken_allowance_staker_caller_change = - _toInt256(expectedSharesBurned);
            rdToken_balanceOf_staker_change        = - _toInt256(expectedSharesBurned);
            rdToken_totalSupply_change             = - _toInt256(expectedSharesBurned);
            rdToken_totalAssets_change             = - _toInt256(withdrawAmount);
            rdToken_freeAssets_change              =   _toInt256(vestedAmount) - _toInt256(withdrawAmount);  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw
            rdToken_convertToAssets_change         = 0;
            rdToken_convertToShares_change         = 0;
            rdToken_issuanceRate_change            = 0;
            rdToken_lastUpdated_change             = _toInt256(warpTime);

            asset_balanceOf_caller_change  = _toInt256(withdrawAmount);
            asset_balanceOf_staker_change  = 0;
            asset_balanceOf_rdToken_change = - _toInt256(withdrawAmount);

            _assertWithdrawCallerNotOwner(address(caller), address(stakers[i]), withdrawAmount, true);
        }
    }

    function testFuzz_withdraw_callerNotOwner_multiUser_postVesting(
        uint256 initialAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_,
        bytes32 depositSeed_,
        bytes32 withdrawSeed_,
        bytes32 warpSeed_
    )
        public
    {
        initialAmount_ = constrictToRange(initialAmount_, 1e6,    1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1e6,    1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 days, 1e29);

        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 1e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + vestingPeriod_ + 12 hours);  // Warp into vestingPeriod so exchangeRate is greater than one for all new deposits

        Staker[] memory stakers = new Staker[](10);

        for (uint256 i; i < 10; ++i) {
            stakers[i] = new Staker();

            uint256 depositAmount = uint256(keccak256(abi.encodePacked(depositSeed_, i)));

            // Get minimum deposit to avoid ZERO_SHARES.
            uint256 minDeposit = _getMinDeposit(address(rdToken));
            depositAmount      = constrictToRange(depositAmount, minDeposit, 1e29 + 1);  // + 1 since we round up in min deposit.

            _depositAsset(address(asset), address(stakers[i]), depositAmount);
        }

        for (uint256 i; i < 10; ++i) {
            caller = new Staker();

            uint256 withdrawAmount = uint256(keccak256(abi.encodePacked(withdrawSeed_, i)));
            uint256 warpTime       = uint256(keccak256(abi.encodePacked(warpSeed_,     i)));

            uint256 maxWithdrawAmount = rdToken.balanceOf(address(stakers[i])) * rdToken.totalAssets() / rdToken.totalSupply();

            withdrawAmount = constrictToRange(withdrawAmount, 1, maxWithdrawAmount);
            warpTime       = constrictToRange(warpTime,       0, (vestingPeriod_ - 12 hours) / 10);

            vm.warp(block.timestamp + warpTime);

            uint256 expectedSharesBurned = rdToken.previewWithdraw(withdrawAmount);
            uint256 vestedAmount         = rdToken.issuanceRate() * warpTime / 1e30;

            stakers[i].erc20_approve(address(rdToken), address(caller), expectedSharesBurned);

            rdToken_allowance_staker_caller_change = - _toInt256(expectedSharesBurned);
            rdToken_balanceOf_staker_change        = - _toInt256(expectedSharesBurned);
            rdToken_totalSupply_change             = - _toInt256(expectedSharesBurned);
            rdToken_totalAssets_change             = - _toInt256(withdrawAmount);
            rdToken_freeAssets_change              =   _toInt256(vestedAmount) - _toInt256(withdrawAmount);  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw
            rdToken_convertToAssets_change         = 0;
            rdToken_convertToShares_change         = 0;
            rdToken_issuanceRate_change            = 0;
            rdToken_lastUpdated_change             = _toInt256(warpTime);

            asset_balanceOf_caller_change  = _toInt256(withdrawAmount);
            asset_balanceOf_staker_change  = 0;
            asset_balanceOf_rdToken_change = - _toInt256(withdrawAmount);

            _assertWithdrawCallerNotOwner(address(caller), address(stakers[i]), withdrawAmount, true);
        }
    }

}

contract WithdrawFailureTests is RDTTestBase {

    Staker staker;

    function setUp() public override virtual {
        super.setUp();
        staker = new Staker();
    }

    function test_withdraw_zeroAmount(uint256 depositAmount_) public {
        _depositAsset(address(asset), address(staker), depositAmount_ = constrictToRange(depositAmount_, 1, 1e29));

        vm.expectRevert("RDT:B:ZERO_SHARES");
        staker.rdToken_withdraw(address(rdToken), 0);

        staker.rdToken_withdraw(address(rdToken), 1);
    }

    function test_withdraw_burnUnderflow(uint256 depositAmount_) public {
        _depositAsset(address(asset), address(staker), depositAmount_ = constrictToRange(depositAmount_, 1, 1e29));

        vm.expectRevert(ARITHMETIC_ERROR);
        staker.rdToken_withdraw(address(rdToken), depositAmount_ + 1);

        staker.rdToken_withdraw(address(rdToken), depositAmount_);
    }

    function test_withdraw_burnUnderflow_totalAssetsGtTotalSupply_explicitValues() public {
        uint256 depositAmount = 100e18;
        uint256 vestingAmount = 10e18;
        uint256 vestingPeriod = 10 days;
        uint256 warpTime      = 5 days;

        _depositAsset(address(asset), address(staker), depositAmount);
        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount, vestingPeriod);

        vm.warp(block.timestamp + warpTime);

        uint256 maxWithdrawAmount = rdToken.previewRedeem(rdToken.balanceOf(address(staker)));  // TODO

        vm.expectRevert(ARITHMETIC_ERROR);
        staker.rdToken_withdraw(address(rdToken), maxWithdrawAmount + 1);

        staker.rdToken_withdraw(address(rdToken), maxWithdrawAmount);
    }

    function test_withdraw_callerNotOwner_badApproval() public {
        Staker shareOwner    = new Staker();
        Staker notShareOwner = new Staker();

        uint256 depositAmount = 1e18;
        asset.mint(address(shareOwner), depositAmount);

        shareOwner.erc20_approve(address(asset), address(rdToken), depositAmount);
        shareOwner.rdToken_deposit(address(rdToken), depositAmount);

        shareOwner.erc20_approve(address(rdToken), address(notShareOwner), depositAmount - 1);
        vm.expectRevert(ARITHMETIC_ERROR);
        notShareOwner.rdToken_withdraw(address(rdToken), depositAmount, address(shareOwner), address(shareOwner));

        shareOwner.erc20_approve(address(rdToken), address(notShareOwner), depositAmount);

        assertEq(rdToken.allowance(address(shareOwner), address(notShareOwner)), depositAmount);

        notShareOwner.rdToken_withdraw(address(rdToken), depositAmount, address(notShareOwner), address(shareOwner));

        assertEq(rdToken.allowance(address(shareOwner), address(notShareOwner)), 0);
    }

    function test_withdraw_callerNotOwner_infiniteApprovalForCaller() public {
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

    // TODO: Implement once max* functions are added as per 4626 standard
    // function test_withdraw_burnUnderflow_totalAssetsGtTotalSupply(uint256 depositAmount, uint256 vestingAmount, uint256 vestingPeriod, uint256 warpTime) public {
    //     depositAmount = constrictToRange(depositAmount, 1, 1e29);
    //     vestingAmount = constrictToRange(vestingAmount, 1, 1e29);
    //     vestingPeriod = constrictToRange(vestingPeriod, 1, 100 days);
    //     warpTime      = constrictToRange(vestingAmount, 1, vestingPeriod);

    //     _depositAsset(address(asset), address(staker), depositAmount);
    //     _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount, vestingPeriod);

    //     vm.warp(block.timestamp + warpTime);

    //     uint256 underflowWithdrawAmount = rdToken.previewRedeem(rdToken.balanceOf(address(staker)) + 1);  // TODO
    //     uint256 maxWithdrawAmount       = rdToken.previewRedeem(rdToken.balanceOf(address(staker)));  // TODO

    //     vm.expectRevert(ARITHMETIC_ERROR);
    //     staker.rdToken_withdraw(address(rdToken), underflowWithdrawAmount);

    //     staker.rdToken_withdraw(address(rdToken), maxWithdrawAmount);
    // }

}

contract WithdrawRevertOnTransfers is RDTTestBase {

    MockRevertingERC20 revertingAsset;
    Staker             staker;

    function setUp() public override virtual {
        revertingAsset = new MockRevertingERC20("MockToken", "MT", 18, address(123));
        rdToken        = new RDT("Revenue Distribution Token", "RDT", address(this), address(revertingAsset), 1e30);
        staker         = new Staker();

        vm.warp(START);  // Warp to non-zero timestamp
    }

    function test_withdraw_revertOnTransfer(uint256 depositAmount_, uint256 withdrawAmount_) public {
        depositAmount_  = constrictToRange(depositAmount_,  1, 1e29);
        withdrawAmount_ = constrictToRange(withdrawAmount_, 1, depositAmount_);

        revertingAsset.mint(address(staker), depositAmount_);

        staker.erc20_approve(address(revertingAsset), address(rdToken), depositAmount_);
        staker.rdToken_deposit(address(rdToken), depositAmount_);

        vm.warp(START + 10 days);

        address revertingDestination = revertingAsset.revertingDestination();
        vm.expectRevert(bytes("RDT:B:TRANSFER"));
        staker.rdToken_withdraw(address(rdToken), withdrawAmount_, revertingDestination, address(staker));

        staker.rdToken_withdraw(address(rdToken), withdrawAmount_, address(1), address(staker));
    }

}

contract WithdrawTests is RDTSuccessTestBase {

    function test_withdraw_singleUser_preVesting() public {
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

        asset_balanceOf_staker_change  = 1000;
        asset_balanceOf_rdToken_change = -1000;

        _assertWithdraw(staker, 1000, false);
    }

    function testFuzz_withdraw_singleUser_preVesting(uint256 depositAmount_, uint256 withdrawAmount_) public {
        depositAmount_  = constrictToRange(depositAmount_,  1, 1e29);
        withdrawAmount_ = constrictToRange(withdrawAmount_, 1, depositAmount_);

        address staker = address(new Staker());

        _depositAsset(address(asset), staker, depositAmount_);

        rdToken_balanceOf_staker_change = - _toInt256(withdrawAmount_);
        rdToken_totalSupply_change      = - _toInt256(withdrawAmount_);
        rdToken_freeAssets_change       = - _toInt256(withdrawAmount_);
        rdToken_totalAssets_change      = - _toInt256(withdrawAmount_);
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = 0;

        asset_balanceOf_staker_change  =   _toInt256(withdrawAmount_);
        asset_balanceOf_rdToken_change = - _toInt256(withdrawAmount_);

        _assertWithdraw(staker, withdrawAmount_, true);
    }

    function test_withdraw_singleUser_midVesting() public {
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

        asset_balanceOf_staker_change  = 20e18;
        asset_balanceOf_rdToken_change = -20e18;

        _assertWithdraw(staker, 20e18, false);
    }

    function testFuzz_withdraw_singleUser_midVesting(
        uint256 depositAmount_,
        uint256 withdrawAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_,
        uint256 warpTime_
    ) public {
        depositAmount_ = constrictToRange(depositAmount_, 1,         1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1,         1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 seconds, 100 days);
        warpTime_      = constrictToRange(warpTime_,      0,         vestingPeriod_);

        address staker = address(new Staker());

        _depositAsset(address(asset), staker, depositAmount_);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + warpTime_);

        uint256 maxWithdrawAmount = depositAmount_ * rdToken.totalAssets() / rdToken.totalSupply();

        withdrawAmount_ = constrictToRange(withdrawAmount_, 1, maxWithdrawAmount);

        uint256 expectedSharesBurned = rdToken.previewWithdraw(withdrawAmount_);
        uint256 vestedAmount         = rdToken.issuanceRate() * warpTime_ / 1e30;

        rdToken_balanceOf_staker_change = - _toInt256(expectedSharesBurned);
        rdToken_totalSupply_change      = - _toInt256(expectedSharesBurned);
        rdToken_totalAssets_change      = - _toInt256(withdrawAmount_);
        rdToken_freeAssets_change       =   _toInt256(vestedAmount) - _toInt256(withdrawAmount_);  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = 0;
        rdToken_lastUpdated_change      = _toInt256(warpTime_);

        asset_balanceOf_staker_change  =   _toInt256(withdrawAmount_);
        asset_balanceOf_rdToken_change = - _toInt256(withdrawAmount_);

        _assertWithdraw(staker, withdrawAmount_, true);
    }

    function test_withdraw_singleUser_postVesting() public {
        address staker = address(new Staker());

        _depositAsset(address(asset), staker, 100e18);
        _transferAndUpdateVesting(address(asset), address(rdToken), 10e18, 200 seconds);

        vm.warp(START + 201 seconds);  // Vest 5e18 tokens

        rdToken_balanceOf_staker_change = -18.181818181818181819e18;  // 20 / 1.1
        rdToken_totalSupply_change      = -18.181818181818181819e18;  // 20 / 1.1
        rdToken_freeAssets_change       = -10e18;  // freeAssets gets updated to reflects 10e18 vested tokens during withdraw
        rdToken_totalAssets_change      = -20e18;
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = -(0.05e18 * 1e30);  // Gets set to zero.
        rdToken_lastUpdated_change      = 201 seconds;

        asset_balanceOf_staker_change  = 20e18;
        asset_balanceOf_rdToken_change = -20e18;

        _assertWithdraw(staker, 20e18, false);
    }

    function testFuzz_withdraw_singleUser_postVesting(
        uint256 depositAmount_,
        uint256 withdrawAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_
    )
        public
    {
        depositAmount_ = constrictToRange(depositAmount_, 1,         1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1,         1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 seconds, 100 days);

        address staker = address(new Staker());

        _depositAsset(address(asset), staker, depositAmount_);
        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + vestingPeriod_ + 1 seconds);

        uint256 maxWithdrawAmount = depositAmount_ * rdToken.totalAssets() / rdToken.totalSupply();

        withdrawAmount_ = constrictToRange(withdrawAmount_, 1, maxWithdrawAmount);

        uint256 expectedSharesBurned = rdToken.previewWithdraw(withdrawAmount_);

        rdToken_balanceOf_staker_change = - _toInt256(expectedSharesBurned);
        rdToken_totalSupply_change      = - _toInt256(expectedSharesBurned);
        rdToken_totalAssets_change      = - _toInt256(withdrawAmount_);
        rdToken_freeAssets_change       =   _toInt256(vestingAmount_) - _toInt256(withdrawAmount_);  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw
        rdToken_convertToAssets_change  = 0;
        rdToken_convertToShares_change  = 0;
        rdToken_issuanceRate_change     = - _toInt256(rdToken.issuanceRate());
        rdToken_lastUpdated_change      =   _toInt256(vestingPeriod_ + 1 seconds);

        asset_balanceOf_staker_change  =   _toInt256(withdrawAmount_);
        asset_balanceOf_rdToken_change = - _toInt256(withdrawAmount_);

        _assertWithdraw(staker, withdrawAmount_, true);
    }

    function testFuzz_withdraw_multiUser_midVesting(
        uint256 iterations_,
        uint256 initialAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_,
        bytes32 depositSeed_,
        bytes32 withdrawSeed_,
        bytes32 warpSeed_
    )
        public
    {
        iterations_    = constrictToRange(iterations_,    10,  20);
        initialAmount_ = constrictToRange(initialAmount_, 1e6, 1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1e6, 1e29);

        uint256 initWarpTime;
        initWarpTime   = constrictToRange(initWarpTime,   1 seconds,             100 days);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 days + initWarpTime, 1e29);

        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 1e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        // Warp into middle of vestingPeriod so exchangeRate is greater than zero for all new deposits
        vm.warp(START + initWarpTime);

        Staker[] memory stakers = new Staker[](iterations_);

        for (uint256 i; i < iterations_; ++i) {
            stakers[i] = new Staker();

            uint256 depositAmount = uint256(keccak256(abi.encodePacked(depositSeed_, i)));

            // Get minimum deposit to avoid ZERO_SHARES.
            uint256 minDeposit = _getMinDeposit(address(rdToken));
            depositAmount      = constrictToRange(depositAmount, minDeposit, 1e29 + 1);  // + 1 since we round up in min deposit.

            _depositAsset(address(asset), address(stakers[i]), depositAmount);
        }

        for (uint256 i; i < iterations_; ++i) {
            uint256 withdrawAmount = uint256(keccak256(abi.encodePacked(withdrawSeed_, i)));
            uint256 warpTime       = uint256(keccak256(abi.encodePacked(warpSeed_,     i)));

            // Scoped to prevent stack too deep.
            {
                uint256 maxWithdrawAmount = rdToken.balanceOf(address(stakers[i])) * rdToken.totalAssets() / rdToken.totalSupply();
                withdrawAmount = constrictToRange(withdrawAmount, 1, maxWithdrawAmount);
            }

            warpTime = constrictToRange(warpTime, 0, (vestingPeriod_ - initWarpTime) / iterations_);

            vm.warp(block.timestamp + warpTime);

            uint256 expectedSharesBurned = rdToken.previewWithdraw(withdrawAmount);
            uint256 vestedAmount         = rdToken.issuanceRate() * warpTime / 1e30;

            rdToken_balanceOf_staker_change = - _toInt256(expectedSharesBurned);
            rdToken_totalSupply_change      = - _toInt256(expectedSharesBurned);
            rdToken_totalAssets_change      = - _toInt256(withdrawAmount);
            rdToken_freeAssets_change       =   _toInt256(vestedAmount) - _toInt256(withdrawAmount);  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw
            rdToken_convertToAssets_change  = 0;
            rdToken_convertToShares_change  = 0;
            rdToken_issuanceRate_change     = 0;
            rdToken_lastUpdated_change      = _toInt256(warpTime);

            asset_balanceOf_staker_change  =   _toInt256(withdrawAmount);
            asset_balanceOf_rdToken_change = - _toInt256(withdrawAmount);

            _assertWithdraw(address(stakers[i]), withdrawAmount, true);
        }
    }

    function testFuzz_withdraw_multiUser_postVesting(
        uint256 initialAmount_,
        uint256 vestingAmount_,
        uint256 vestingPeriod_,
        bytes32 depositSeed_,
        bytes32 withdrawSeed_,
        bytes32 warpSeed_
    )
        public
    {
        initialAmount_ = constrictToRange(initialAmount_, 1e6,    1e29);
        vestingAmount_ = constrictToRange(vestingAmount_, 1e6,    1e29);
        vestingPeriod_ = constrictToRange(vestingPeriod_, 1 days, 1e29);

        Staker setupStaker = new Staker();

        // Do a deposit so that totalSupply is non-zero
        _depositAsset(address(asset), address(setupStaker), 1e18);

        _transferAndUpdateVesting(address(asset), address(rdToken), vestingAmount_, vestingPeriod_);

        vm.warp(START + vestingPeriod_ + 12 hours);  // Warp into vestingPeriod so exchangeRate is greater than zero for all new deposits

        Staker[] memory stakers = new Staker[](10);

        for (uint256 i; i < 10; ++i) {
            stakers[i] = new Staker();

            uint256 depositAmount = uint256(keccak256(abi.encodePacked(depositSeed_, i)));

            // Get minimum deposit to avoid ZERO_SHARES.
            uint256 minDeposit = _getMinDeposit(address(rdToken));
            depositAmount      = constrictToRange(depositAmount, minDeposit, 1e29 + 1);  // + 1 since we round up in min deposit.

            _depositAsset(address(asset), address(stakers[i]), depositAmount);
        }

        for (uint256 i; i < 10; ++i) {
            uint256 withdrawAmount = uint256(keccak256(abi.encodePacked(withdrawSeed_, i)));
            uint256 warpTime       = uint256(keccak256(abi.encodePacked(warpSeed_,     i)));

            uint256 maxWithdrawAmount = rdToken.balanceOf(address(stakers[i])) * rdToken.totalAssets() / rdToken.totalSupply();

            withdrawAmount = constrictToRange(withdrawAmount, 1, maxWithdrawAmount);
            warpTime       = constrictToRange(warpTime,       0, (vestingPeriod_ - 12 hours) / 10);

            vm.warp(block.timestamp + warpTime);

            uint256 expectedSharesBurned = rdToken.previewWithdraw(withdrawAmount);
            uint256 vestedAmount         = rdToken.issuanceRate() * warpTime / 1e30;

            rdToken_balanceOf_staker_change = - _toInt256(expectedSharesBurned);
            rdToken_totalSupply_change      = - _toInt256(expectedSharesBurned);
            rdToken_totalAssets_change      = - _toInt256(withdrawAmount);
            rdToken_freeAssets_change       =   _toInt256(vestedAmount) - _toInt256(withdrawAmount);  // freeAssets gets updated to reflects 5e18 vested tokens during withdraw
            rdToken_convertToAssets_change  = 0;
            rdToken_convertToShares_change  = 0;
            rdToken_issuanceRate_change     = 0;
            rdToken_lastUpdated_change      = _toInt256(warpTime);

            asset_balanceOf_staker_change  =   _toInt256(withdrawAmount);
            asset_balanceOf_rdToken_change = - _toInt256(withdrawAmount);

            _assertWithdraw(address(stakers[i]), withdrawAmount, true);
        }
    }

}
