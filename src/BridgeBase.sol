// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/Address.sol";
import {ShortStrings} from "@openzeppelin/contracts/utils/ShortStrings.sol";
import "@hyperledger-labs/yui-ibc-solidity/contracts/apps/commons/IBCAppBase.sol";
import "./interfaces/ITokiErrors.sol";
import "./interfaces/IBridgeRouter.sol";
import "./interfaces/IReceiveRetryable.sol";
import "./interfaces/IReceiveRetryableSelf.sol";
import "./interfaces/IBridgeManager.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IPoolRepository.sol";
import "./interfaces/ITokenPriceOracle.sol";
import "./interfaces/ITokiOuterServiceReceiver.sol";
import "./interfaces/IRelayerFeeCalculator.sol";
import "./future/interfaces/ITokenEscrow.sol";
import "./BridgeStore.sol";

// provides the basic functions for Bridge and BridgeFallback
abstract contract BridgeBase is BridgeStore {
    using Address for address;
    using ShortStrings for ShortString;

    struct ReceiveOption {
        bool updateDelta;
        uint256 lastValidHeightOrZero;
    }

    event RefuelDstCapped(
        uint256 chainId,
        uint64 sequence,
        address to,
        uint256 requestAmount,
        uint256 actualAmount
    );

    // For channel upgrade, this is called before initializing
    function appVersion() external view returns (uint256) {
        return APP_VERSION;
    }

    function getChainId(
        string memory localChannel,
        bool checksAppVersion
    ) public view returns (uint256 counterpartyChainId) {
        BridgeStorage storage $ = getBridgeStorage();
        ChannelInfo memory channelInfo = $.channelInfos[localChannel];
        counterpartyChainId = channelInfo.counterpartyChainId;
        if (counterpartyChainId == 0) {
            revert TokiUnregisteredChainId(localChannel);
        }
        if (checksAppVersion && channelInfo.appVersion != APP_VERSION) {
            revert TokiInvalidAppVersion(
                channelInfo.appVersion, // expected
                APP_VERSION // actual
            );
        }
    }

    function getPool(
        uint256 localPoolId
    ) public view returns (IPool localPool) {
        BridgeStorage storage $ = getBridgeStorage();
        localPool = IPool($.poolRepository.getPool(localPoolId));
        if (address(localPool) == address(0x0)) {
            revert TokiUnregisteredPoolId(localPoolId);
        }
    }

    function _sendWithRefund(
        uint256 dstChainId,
        string memory srcChannel,
        bytes memory message,
        address payable refundTo,
        uint8 messageType,
        uint256 dstOuterGas, // in gas
        uint256 dstRefuelAmount // in wei
    ) internal {
        _send(srcChannel, message);

        BridgeStorage storage $ = getBridgeStorage();
        IRelayerFeeCalculator.RelayerFee memory relayerFee = $
            .relayerFeeCalculator
            .calcFee(messageType, dstChainId);
        uint256 useNativeAsset = 0;
        if (dstOuterGas > 0 || dstRefuelAmount > 0) {
            uint256 riskBPS = $.premiumBPS[dstChainId];
            useNativeAsset = _calcSrcNativeAmount(
                dstOuterGas,
                dstRefuelAmount,
                relayerFee.srcTokenPrice,
                relayerFee.dstTokenPrice,
                relayerFee.dstGasPrice,
                riskBPS
            );
        }
        _refund(refundTo, relayerFee.fee, useNativeAsset);
    }

    function _refund(
        address payable refundTo,
        uint256 relayerFee,
        uint256 useNativeAsset
    ) internal {
        uint256 totalNativeFee = relayerFee + useNativeAsset;

        // assert the user has attached enough native token for this address
        if (totalNativeFee > msg.value) {
            revert TokiNotEnoughNativeFee(totalNativeFee, msg.value);
        }
        // refund if they send too much
        uint256 amount = msg.value - totalNativeFee;
        if (amount > 0) {
            (bool success, ) = refundTo.call{value: amount}("");
            if (!success) {
                revert TokiFailToRefund();
            }
        }
    }

    // Update credit and targetBalance
    // <- Receive from `sendCredit` on the src side.
    // only IBCHandler can call this function.
    function _updateCredit(
        string memory dstChannel,
        uint256 dstPoolId,
        uint256 srcPoolId,
        IPool.CreditInfo memory creditInfo
    ) internal {
        // <- Receive from `sendCredit` on the src side.
        // call `updateCredit` on pool contract.
        uint256 srcChainId = getChainId(dstChannel, true);
        IPool pool = getPool(dstPoolId);
        pool.updateCredit(srcChainId, srcPoolId, creditInfo);
    }

    // Processes remittance requests received from the src side.
    // If there are additional payloads, call the specified external callback function
    //
    // Note about slither-disable:
    //  Reentrancy is prevented as ancestor functions can only be called
    // by IBCHandler or are guarded by the nonReentrant modifier.
    // slither-disable-next-line reentrancy-benign
    // slither-disable-next-line reentrancy-events
    function _receivePool(
        string memory dstChannel,
        uint64 sequence,
        uint256 srcPoolId,
        uint256 dstPoolId,
        address to,
        ITransferPoolFeeCalculator.FeeInfo memory fee,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo memory externalInfo,
        ReceiveOption memory receiveOption
    ) internal {
        // <- Receive from `transaferPool` or `withdrawRemote` on the src side.
        // Call `updateCredit` and `recv` on pool contract.
        uint256 srcChainId = getChainId(dstChannel, true);
        IPool pool = getPool(dstPoolId);
        // first try catch the swap remote
        uint256 amountLD;
        bool isTransferred = false;
        try
            pool.recv(srcChainId, srcPoolId, to, fee, receiveOption.updateDelta)
        returns (uint256 amountLD_, bool isTransferred_) {
            amountLD = amountLD_;
            isTransferred = isTransferred_;
        } catch {
            // Set isTransferred to false.
            // Since it's already initialized as false, there's nothing to do here.
        }
        if (isTransferred) {
            _outServiceCallCore(
                dstChannel,
                srcChainId,
                sequence,
                pool.token(),
                amountLD,
                to,
                refuelAmount,
                externalInfo,
                true,
                receiveOption.lastValidHeightOrZero
            );
        } else {
            // - receive token is failed
            // ReceiveFailed -> retryReceiveOnReceive
            _asReceiveRetryableSelf().addRevertReceivePool(
                srcChainId,
                sequence,
                srcPoolId,
                dstPoolId,
                to,
                fee,
                refuelAmount,
                externalInfo,
                receiveOption.lastValidHeightOrZero
            );
        }
    }

    // Note about slither-disable:
    //  Reentrancy is prevented as ancestor functions can only be called
    // by IBCHandler or are guarded by the nonReentrant modifier.
    // slither-disable-next-line reentrancy-benign
    // slither-disable-next-line reentrancy-events
    function _receiveToken(
        string memory dstChannel,
        uint64 sequence,
        string memory denom,
        uint256 amount,
        address to,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo memory externalInfo,
        uint256 lastValidHeightOrZero
    ) internal {
        // <- Receive from `transaferToken` or `withdrawRemote` on the src side.
        // Call `receiveToken` on Escrow contract.
        uint256 srcChainId = getChainId(dstChannel, true);
        BridgeStorage storage $ = getBridgeStorage();
        try $.tokenEscrow.receiveToken(to, amount) {
            _outServiceCallCore(
                dstChannel,
                srcChainId,
                sequence,
                $.tokenEscrow.token(),
                amount,
                payable(to),
                refuelAmount,
                externalInfo,
                true,
                lastValidHeightOrZero
            );
        } catch {
            // - receive token is failed
            // ReceiveFailed -> retryReceiveOnReceive
            _asReceiveRetryableSelf().addRevertReceiveToken(
                srcChainId,
                sequence,
                denom,
                amount,
                to,
                refuelAmount,
                externalInfo,
                lastValidHeightOrZero
            );
        }
    }

    // Drawer processing based on results from dst side
    // <- Receive from `withdrawCheck` on the src side.
    //
    // Note about slither-disable:
    //  Reentrancy is prevented as ancestor functions can only be called
    // by IBCHandler or are guarded by the nonReentrant modifier.
    // slither-disable-next-line reentrancy-benign
    function _withdrawConfirm(
        string memory dstChannel,
        uint64 sequence,
        uint256 withdrawLocalPoolId, //me
        uint256 withdrawCheckPoolId,
        address to,
        uint256 amountGD,
        uint256 mintAmountGD,
        ReceiveOption memory receiveOption
    ) internal {
        // <- Receive from `withdrawCheck` on the src side.
        // call `withdrawConfirm` and `updateCredit` on pool contract.
        uint256 srcChainId = getChainId(dstChannel, true);
        IPool pool = getPool(withdrawLocalPoolId); // self
        bool isTransferred = false;
        try
            pool.withdrawConfirm(
                srcChainId, // peer
                withdrawCheckPoolId, // peer
                to,
                amountGD,
                mintAmountGD,
                receiveOption.updateDelta
            )
        returns (bool isTransferred_) {
            isTransferred = isTransferred_;
        } catch {
            // Set isTransferred to false.
            // Since it's already initialized as false, there's nothing to do here.
        }

        if (!isTransferred) {
            _asReceiveRetryableSelf().addRevertWithdrawConfirm(
                srcChainId,
                sequence,
                withdrawLocalPoolId,
                withdrawCheckPoolId,
                to,
                amountGD,
                mintAmountGD,
                receiveOption.lastValidHeightOrZero
            );
        }
    }

    // Note about slither-disable:
    //  Reentrancy is prevented as ancestor functions can only be called
    // by IBCHandler or are guarded by the nonReentrant modifier.
    // slither-disable-next-line reentrancy-benign
    function _outServiceCallCore(
        string memory dstChannel,
        uint256 srcChainId,
        uint64 sequence,
        address token,
        uint256 amount,
        address to,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo memory externalInfo,
        bool doRefuel,
        uint256 lastValidHeightOrZero
    ) internal {
        BridgeStorage storage $ = getBridgeStorage();
        // 001: dst gas on bridge is short
        // 010: external call is failed
        // 011: dst gas on bridge is short & external call is failed
        uint8 errorFlag = 0;
        // send refuelAmount from bridge to dest
        if (doRefuel) {
            uint256 actualRefuel;
            if (refuelAmount < $.refuelDstCap) {
                actualRefuel = refuelAmount;
            } else {
                actualRefuel = $.refuelDstCap;
                emit RefuelDstCapped(
                    srcChainId,
                    sequence,
                    to,
                    refuelAmount,
                    actualRefuel
                );
            }
            address payable payableTo = payable(to);
            // Note about slither-disable:
            //  Reentrancy is prevented as ancestor functions can only be called
            // by IBCHandler or are guarded by the nonReentrant modifier.
            // slither-disable-next-line arbitrary-send-eth
            (bool success, ) = payableTo.call{value: actualRefuel}("");
            if (!success) {
                errorFlag += 1;
            }
        }

        // Note that if outer address is EOA, external call is skipped and receiving process result in success.
        if (externalInfo.payload.length > 0 && to.code.length > 0) {
            try
                ITokiOuterServiceReceiver(to).onReceivePool{
                    gas: externalInfo.dstOuterGas
                }(dstChannel, token, amount, externalInfo.payload)
            {} catch {
                errorFlag += 2;
            }
        }
        if (errorFlag == 1) {
            // if dest gas on bridge is short
            // RefuelFailed -> retryRefuelOnReceive
            //_addRevertRefuel(srcChainId, sequence, to, refuelAmount);
            _asReceiveRetryableSelf().addRevertRefuel(
                srcChainId,
                sequence,
                to,
                refuelAmount,
                lastValidHeightOrZero
            );
        } else if (errorFlag == 2) {
            // if external call is failed
            // ExternalFailed -> retryOuterCallOnReceive
            _asReceiveRetryableSelf().addRevertExternal(
                srcChainId,
                sequence,
                token,
                amount,
                to,
                externalInfo,
                lastValidHeightOrZero
            );
        } else if (errorFlag == 3) {
            // both error
            _asReceiveRetryableSelf().addRevertRefuelAndExternal(
                srcChainId,
                sequence,
                token,
                amount,
                to,
                refuelAmount,
                externalInfo,
                lastValidHeightOrZero
            );
        }
    }

    function _send(string memory srcChannel, bytes memory message) internal {
        BridgeStorage storage $ = getBridgeStorage();
        // solhint-disable-next-line no-unused-vars
        uint64 _sequence = $.ics04SendPacket.sendPacket(
            PORT.toString(),
            srcChannel,
            Height.Data({revision_number: 0, revision_height: 0}),
            TIMEOUT_TIMESTAMP,
            message
        );
    }

    function _isVersionCompatible(
        string memory localChannel
    ) internal view returns (bool) {
        BridgeStorage storage $ = getBridgeStorage();
        return $.channelInfos[localChannel].appVersion == APP_VERSION;
    }

    function _asReceiveRetryableSelf()
        internal
        view
        returns (IReceiveRetryableSelf)
    {
        return IReceiveRetryableSelf(address(this));
    }

    function _calcSrcNativeAmount(
        uint256 dstGas, // [gas]
        uint256 dstTokenAmount, // [dst wei]
        uint256 srcTokenPrice,
        uint256 dstTokenPrice,
        uint256 dstGasPrice,
        uint256 riskBPS
    ) internal pure returns (uint256) {
        if (srcTokenPrice == 0) {
            revert TokiZeroValue("srcTokenPrice");
        }
        // srcWei = dstWei[dstWei] * dstPrice[usd/dstWei] / srcPrice[usd/srcWei]* riskPremium[bps]
        uint256 dstWei = dstGas * dstGasPrice + dstTokenAmount;
        return
            (dstWei * dstTokenPrice * (RISK_BPS + riskBPS)) /
            srcTokenPrice /
            RISK_BPS;
    }
}
