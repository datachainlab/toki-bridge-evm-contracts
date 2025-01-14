// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@hyperledger-labs/yui-ibc-solidity/contracts/apps/commons/IBCAppBase.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import {ShortString, ShortStrings} from "@openzeppelin/contracts/utils/ShortStrings.sol";
import "./interfaces/ITokiErrors.sol";
import "./interfaces/IBridgeRouter.sol";
import "./interfaces/IReceiveRetryable.sol";
import "./interfaces/IBridgeManager.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IPoolRepository.sol";
import "./interfaces/ITokenPriceOracle.sol";
import "./interfaces/IRelayerFeeCalculator.sol";
import "./future/interfaces/ITokenEscrow.sol";
import "./BridgeQuerier.sol";
import "./BridgeManager.sol";

// BridgeFallback has functions which needs access restriction
// because of bridge fallback, anyone can call unrestricted functions
contract BridgeFallback is
    ReentrancyGuardTransientUpgradeable,
    BridgeQuerier,
    BridgeManager,
    IReceiveRetryable,
    IReceiveRetryableSelf
{
    using ShortStrings for string;
    using ShortStrings for ShortString;

    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert TokiFallbackUnauthorized(msg.sender);
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint256 appVersion_, string memory port) {
        APP_VERSION = appVersion_;
        PORT = port.toShortString();
    }

    function callDelta(uint256 srcPoolId, bool fullMode) external {
        if (fullMode) {
            _checkRole(DEFAULT_ADMIN_ROLE);
        }
        getPool(srcPoolId).callDelta(fullMode);
    }

    // Send information on credit and targetBalance to dst side pool
    // <- Send from `sendCredit` on the src side.
    // -> Receive `updateCredit` on the dst side.
    function sendCredit(
        string calldata srcChannel,
        uint256 srcPoolId,
        uint256 dstPoolId,
        address payable refundTo
    ) external payable nonReentrant {
        // call `sendCredit` on pool contract.
        // -> And call `updateCredit` on dst side.
        if (refundTo == address(0x0)) {
            revert TokiZeroAddress("refundTo");
        }
        IPool pool = getPool(srcPoolId);
        uint256 dstChainId = getChainId(srcChannel, true);
        IPool.CreditInfo memory creditInfo = pool.sendCredit(
            dstChainId,
            dstPoolId
        );

        // send IBCUtils.TYPE_CREDIT
        bytes memory message = IBCUtils.encodeCredit(
            srcPoolId,
            dstPoolId,
            creditInfo
        );
        _sendWithRefund(
            dstChainId,
            srcChannel,
            message,
            refundTo,
            MessageType._TYPE_CREDIT,
            IBCUtils.ExternalInfo("", 0),
            0
        );
    }

    function sendCreditInLedger(
        uint256 srcPoolId,
        uint256 dstPoolId
    ) external nonReentrant {
        // call `sendCredit` on pool contract.
        // -> And call `updateCredit` on dst side.

        IPool pool = getPool(srcPoolId);
        IPool.CreditInfo memory creditInfo = pool.sendCredit(
            block.chainid,
            dstPoolId
        );

        // "Receiving" half. It is same to TYPE_CREDIT case in onRecvPacket().
        IPool dstPool = getPool(dstPoolId);
        dstPool.updateCredit(block.chainid, srcPoolId, creditInfo);
    }

    /**
     * Composability
     */
    function retryOnReceive(
        string calldata dstChannel,
        uint64 sequence
    ) external nonReentrant {
        uint256 srcChainId = getChainId(dstChannel, true);
        BridgeStorage storage $ = getBridgeStorage();

        bytes memory payload = $.revertReceive[srcChainId][sequence];
        if (payload.length <= 0) {
            revert TokiNoRevertReceive();
        }

        // empty it
        $.revertReceive[srcChainId][sequence] = "";

        uint8 rtype = IBCUtils.parseType(payload);
        if (rtype == IBCUtils._TYPE_RETRY_RECEIVE_POOL) {
            IBCUtils.RetryReceivePoolPayload memory p = IBCUtils
                .decodeRetryReceivePool(payload);
            _validateRetryExpiration(p.lastValidHeight);
            ReceiveOption memory receiveOption = ReceiveOption(
                false,
                p.lastValidHeight
            );
            _receivePool(
                dstChannel,
                sequence,
                p.srcPoolId,
                p.dstPoolId,
                p.to,
                p.feeInfo,
                p.refuelAmount,
                p.externalInfo,
                receiveOption
            );
        } else if (rtype == IBCUtils._TYPE_RETRY_RECEIVE_TOKEN) {
            IBCUtils.RetryReceiveTokenPayload memory p = IBCUtils
                .decodeRetryReceiveToken(payload);
            _validateRetryExpiration(p.lastValidHeight);
            _receiveToken(
                dstChannel,
                sequence,
                p.denom,
                p.amount,
                p.to,
                p.refuelAmount,
                p.externalInfo,
                p.lastValidHeight
            );
        } else if (rtype == IBCUtils._TYPE_RETRY_WITHDRAW_CONFIRM) {
            IBCUtils.RetryWithdrawConfirmPayload memory p = IBCUtils
                .decodeRetryWithdrawConfirm(payload);
            _validateRetryExpiration(p.lastValidHeight);
            ReceiveOption memory receiveOption = ReceiveOption(
                false,
                p.lastValidHeight
            );
            _withdrawConfirm(
                dstChannel,
                sequence,
                p.withdrawLocalPoolId,
                p.withdrawCheckPoolId,
                p.to,
                p.transferAmountGD,
                p.mintAmountGD,
                receiveOption
            );
        } else if (rtype == IBCUtils._TYPE_RETRY_EXTERNAL_CALL) {
            IBCUtils.RetryExternalCallPayload memory p = IBCUtils
                .decodeRetryExternalCall(payload);
            _validateRetryExpiration(p.lastValidHeight);
            _outServiceCallCore(
                dstChannel,
                srcChainId,
                sequence,
                p.token,
                p.amount,
                p.to,
                0,
                p.externalInfo,
                false,
                p.lastValidHeight
            );
        } else if (rtype == IBCUtils._TYPE_RETRY_REFUEL_CALL) {
            IBCUtils.RetryRefuelCallPayload memory p = IBCUtils
                .decodeRetryRefuelCall(payload);
            _validateRetryExpiration(p.lastValidHeight);
            uint256 actualRefuel = (p.refuelAmount < $.refuelDstCap)
                ? p.refuelAmount
                : $.refuelDstCap;
            (bool success, ) = payable(p.to).call{value: actualRefuel}("");
            if (success) {
                if (actualRefuel != p.refuelAmount) {
                    emit RefuelDstCapped(
                        srcChainId,
                        sequence,
                        p.to,
                        p.refuelAmount,
                        actualRefuel
                    );
                }
            } else {
                this.addRevertRefuel(
                    srcChainId,
                    sequence,
                    p.to,
                    p.refuelAmount,
                    p.lastValidHeight
                );
            }
        } else if (rtype == IBCUtils._TYPE_RETRY_REFUEL_AND_EXTERNAL_CALL) {
            IBCUtils.RetryRefuelAndExternalCallPayload memory p = IBCUtils
                .decodeRetryRefuelAndExternalCall(payload);
            _validateRetryExpiration(p.lastValidHeight);
            _outServiceCallCore(
                dstChannel,
                srcChainId,
                sequence,
                p.token,
                p.amount,
                p.to,
                p.refuelAmount,
                p.externalInfo,
                true,
                p.lastValidHeight
            );
        } else {
            revert TokiInvalidRetryType(rtype);
        }
    }

    function addRevertReceivePool(
        uint256 srcChainId,
        uint64 sequence,
        uint256 srcPoolId,
        uint256 dstPoolId,
        address to,
        ITransferPoolFeeCalculator.FeeInfo memory fee,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo memory externalInfo,
        uint256 lastValidHeightOrZero
    ) external onlySelf {
        BridgeStorage storage $ = getBridgeStorage();
        uint256 lastValidHeight = lastValidHeightOrZero == 0
            ? block.number + $.receiveRetryBlocks
            : lastValidHeightOrZero;
        $.revertReceive[srcChainId][sequence] = IBCUtils.encodeRetryReceivePool(
            APP_VERSION,
            lastValidHeight,
            srcPoolId,
            dstPoolId,
            to,
            fee,
            refuelAmount,
            externalInfo
        );
        // Note about slither-disable:
        //  Reentrancy is prevented as ancestor functions can only be called
        // by IBCHandler or are guarded by the nonReentrant or onlySelf modifier.
        // slither-disable-next-line reentrancy-events
        emit RevertReceive(
            IBCUtils._TYPE_RETRY_RECEIVE_POOL,
            srcChainId,
            sequence,
            lastValidHeight
        );
    }

    function addRevertReceiveToken(
        uint256 srcChainId,
        uint64 sequence,
        string memory denom,
        uint256 amount,
        address to,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo memory externalInfo,
        uint256 lastValidHeightOrZero
    ) external onlySelf {
        BridgeStorage storage $ = getBridgeStorage();
        uint256 lastValidHeight = lastValidHeightOrZero == 0
            ? block.number + $.receiveRetryBlocks
            : lastValidHeightOrZero;

        $.revertReceive[srcChainId][sequence] = IBCUtils
            .encodeRetryReceiveToken(
                APP_VERSION,
                lastValidHeight,
                denom,
                amount,
                to,
                refuelAmount,
                externalInfo
            );
        // Note about slither-disable:
        //  Reentrancy is prevented as ancestor functions can only be called
        // by IBCHandler or are guarded by the nonReentrant or onlySelf modifier.
        // slither-disable-next-line reentrancy-events
        emit RevertReceive(
            IBCUtils._TYPE_RETRY_RECEIVE_TOKEN,
            srcChainId,
            sequence,
            lastValidHeight
        );
    }

    function addRevertRefuel(
        uint256 srcChainId,
        uint64 sequence,
        address to,
        uint256 refuelAmount,
        uint256 lastValidHeightOrZero
    ) external onlySelf {
        BridgeStorage storage $ = getBridgeStorage();
        uint256 lastValidHeight = lastValidHeightOrZero == 0
            ? block.number + $.externalRetryBlocks
            : lastValidHeightOrZero;

        $.revertReceive[srcChainId][sequence] = IBCUtils.encodeRetryRefuelCall(
            APP_VERSION,
            lastValidHeight,
            to,
            refuelAmount
        );
        // Note about slither-disable:
        //  Reentrancy is prevented as ancestor functions can only be called
        // by IBCHandler or are guarded by the nonReentrant or onlySelf modifier.
        // slither-disable-next-line reentrancy-events
        emit RevertReceive(
            IBCUtils._TYPE_RETRY_REFUEL_CALL,
            srcChainId,
            sequence,
            lastValidHeight
        );
    }

    function addRevertRefuelAndExternal(
        uint256 srcChainId,
        uint64 sequence,
        address token,
        uint256 amount,
        address to,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo memory externalInfo,
        uint256 lastValidHeightOrZero
    ) external onlySelf {
        BridgeStorage storage $ = getBridgeStorage();
        uint256 lastValidHeight = lastValidHeightOrZero == 0
            ? block.number + $.externalRetryBlocks
            : lastValidHeightOrZero;
        $.revertReceive[srcChainId][sequence] = IBCUtils
            .encodeRetryRefuelAndExternalCall(
                APP_VERSION,
                lastValidHeight,
                token,
                amount,
                to,
                refuelAmount,
                externalInfo
            );
        // Note about slither-disable:
        //  Reentrancy is prevented as ancestor functions can only be called
        // by IBCHandler or are guarded by the nonReentrant or onlySelf modifier.
        // slither-disable-next-line reentrancy-events
        emit RevertReceive(
            IBCUtils._TYPE_RETRY_REFUEL_AND_EXTERNAL_CALL,
            srcChainId,
            sequence,
            lastValidHeight
        );
    }

    function addRevertExternal(
        uint256 srcChainId,
        uint64 sequence,
        address token,
        uint256 amount,
        address to,
        IBCUtils.ExternalInfo memory externalInfo,
        uint256 lastValidHeightOrZero
    ) external onlySelf {
        BridgeStorage storage $ = getBridgeStorage();
        uint256 lastValidHeight = lastValidHeightOrZero == 0
            ? block.number + $.externalRetryBlocks
            : lastValidHeightOrZero;
        $.revertReceive[srcChainId][sequence] = IBCUtils
            .encodeRetryExternalCall(
                APP_VERSION,
                lastValidHeight,
                token,
                amount,
                to,
                externalInfo
            );
        // Note about slither-disable:
        //  Reentrancy is prevented as ancestor functions can only be called
        // by IBCHandler or are guarded by the nonReentrant or onlySelf modifier.
        // slither-disable-next-line reentrancy-events
        emit RevertReceive(
            IBCUtils._TYPE_RETRY_EXTERNAL_CALL,
            srcChainId,
            sequence,
            lastValidHeight
        );
    }

    function addRevertWithdrawConfirm(
        uint256 srcChainId,
        uint64 sequence,
        uint256 withdrawLocalPoolId,
        uint256 withdrawCheckPoolId,
        address to,
        uint256 amountGD,
        uint256 mintAmountGD,
        uint256 lastValidHeightOrZero
    ) external onlySelf {
        BridgeStorage storage $ = getBridgeStorage();
        uint256 lastValidHeight = lastValidHeightOrZero == 0
            ? block.number + $.withdrawRetryBlocks
            : lastValidHeightOrZero;
        $.revertReceive[srcChainId][sequence] = IBCUtils
            .encodeRetryWithdrawConfirm(
                APP_VERSION,
                lastValidHeight,
                withdrawLocalPoolId,
                withdrawCheckPoolId,
                to,
                amountGD,
                mintAmountGD
            );
        // Note about slither-disable:
        //  Reentrancy is prevented as ancestor functions can only be called
        // by IBCHandler or are guarded by the nonReentrant or onlySelf modifier.
        // slither-disable-next-line reentrancy-events
        emit RevertReceive(
            IBCUtils._TYPE_RETRY_WITHDRAW_CONFIRM,
            srcChainId,
            sequence,
            lastValidHeight
        );
    }

    function _validateRetryExpiration(uint256 lastValidHeight) internal view {
        if (block.number > lastValidHeight) {
            revert TokiRetryExpired(lastValidHeight);
        }
    }
}
