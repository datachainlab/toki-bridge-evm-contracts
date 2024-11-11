// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "@hyperledger-labs/yui-ibc-solidity/contracts/apps/commons/IBCAppBase.sol";

import "./interfaces/ITokiErrors.sol";
import "./interfaces/IBridgeRouter.sol";
import "./interfaces/IReceiveRetryable.sol";
import "./interfaces/IBridgeManager.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IPoolRepository.sol";
import "./interfaces/ITokenPriceOracle.sol";
import "./interfaces/IRelayerFeeCalculator.sol";
import "./future/interfaces/ITokenEscrow.sol";
import "./interfaces/IAppVersion.sol";
import "./BridgeBase.sol";

abstract contract BridgeManager is
    AccessControlUpgradeable,
    IBridgeManager,
    BridgeBase
{
    // draw is for rebalancing the native token balance.
    // native token held in the contract is mainly used for the refueling.
    function draw(
        uint256 amount,
        address to
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0x0)) {
            revert TokiZeroAddress("to");
        }
        emit Draw(amount, to);
        Address.sendValue(payable(to), amount);
    }

    function setDefaultFallback(
        address defaultFallback_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _checkFallbackAppVersion(defaultFallback_);
        BridgeStorage storage $ = getBridgeStorage();
        $.defaultFallback = defaultFallback_;
        emit SetDefaultFallback(defaultFallback_);
    }

    function setChannelUpgradeFallback(
        address channelUpgradeFallback_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _checkFallbackAppVersion(channelUpgradeFallback_);
        BridgeStorage storage $ = getBridgeStorage();
        $.channelUpgradeFallback = channelUpgradeFallback_;
        emit SetChannelUpgradeFallback(channelUpgradeFallback_);
    }

    // Set the amount of gas for Bridge according to the partner ledger (Channel)
    // and dst side processing type (see BridgePacketData#type).
    function setChainLookup(
        string calldata localChannel,
        uint256 counterpartyChainId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        BridgeStorage storage $ = getBridgeStorage();
        $.channelInfos[localChannel].counterpartyChainId = counterpartyChainId;
        emit SetChainLookup(localChannel, counterpartyChainId);
    }

    function setICS04SendPacket(
        address ics04SendPacket_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (ics04SendPacket_ == address(0x0)) {
            revert TokiZeroAddress("ics04SendPacket_");
        }
        BridgeStorage storage $ = getBridgeStorage();
        $.ics04SendPacket = IICS04SendPacket(ics04SendPacket_);
        emit SetICS04SendPacket(ics04SendPacket_);
    }

    function setPoolRepository(
        address poolRepository_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (poolRepository_ == address(0x0)) {
            revert TokiZeroAddress("poolRepository_");
        }
        BridgeStorage storage $ = getBridgeStorage();
        $.poolRepository = IPoolRepository(poolRepository_);
        emit SetPoolRepository(poolRepository_);
    }

    function setPremiumBPS(
        string calldata localChannel,
        uint256 premiumBps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        BridgeStorage storage $ = getBridgeStorage();
        uint256 chainId_ = getChainId(localChannel, false);
        $.premiumBPS[chainId_] = premiumBps;
        emit SetPremiumBPS(chainId_, premiumBps);
    }

    function setRefuelSrcCap(
        string calldata localChannel,
        uint256 cap
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        BridgeStorage storage $ = getBridgeStorage();
        uint256 chainId_ = getChainId(localChannel, false);
        $.refuelSrcCap[chainId_] = cap;
        emit SetRefuelSrcCap(chainId_, cap);
    }

    function setRefuelDstCap(
        uint256 cap
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        BridgeStorage storage $ = getBridgeStorage();
        $.refuelDstCap = cap;
        emit SetRefuelDstCap(cap);
    }

    function setRelayerFeeCalculator(
        address relayerFeeCalculator_
    ) external onlyRole(RELAYER_FEE_OWNER_ROLE) {
        if (relayerFeeCalculator_ == address(0x0)) {
            revert TokiZeroAddress("relayerFeeCalculator_");
        }
        BridgeStorage storage $ = getBridgeStorage();
        $.relayerFeeCalculator = IRelayerFeeCalculator(relayerFeeCalculator_);
        emit SetRelayerFeeCalculator(relayerFeeCalculator_);
    }

    function setTokenEscrow(
        address tokenEscrow_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (tokenEscrow_ == address(0x0)) {
            revert TokiZeroAddress("tokenEscrow_");
        }
        BridgeStorage storage $ = getBridgeStorage();
        $.tokenEscrow = ITokenEscrow(tokenEscrow_);
        emit SetTokenEscrow(tokenEscrow_);
    }

    function setTokenPriceOracle(
        address tokenPriceOracle_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (tokenPriceOracle_ == address(0x0)) {
            revert TokiZeroAddress("tokenPriceOracle_");
        }
        BridgeStorage storage $ = getBridgeStorage();
        $.tokenPriceOracle = ITokenPriceOracle(tokenPriceOracle_);
        emit SetTokenPriceOracle(tokenPriceOracle_);
    }

    function setRetryBlocks(
        uint64 receiveBlocks,
        uint64 withdrawBlocks,
        uint64 externalBlocks
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        BridgeStorage storage $ = getBridgeStorage();
        $.receiveRetryBlocks = receiveBlocks;
        $.withdrawRetryBlocks = withdrawBlocks;
        $.externalRetryBlocks = externalBlocks;
        emit SetRetryBlocks(receiveBlocks, withdrawBlocks, externalBlocks);
    }

    function _checkFallbackAppVersion(address fallback_) internal view {
        if (fallback_ == address(0x0)) {
            revert TokiZeroAddress("fallback_");
        }
        IAppVersion iFallback = IAppVersion(fallback_);
        if (APP_VERSION != iFallback.appVersion()) {
            revert TokiInvalidAppVersion(APP_VERSION, iFallback.appVersion());
        }
    }
}
