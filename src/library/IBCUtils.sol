// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../interfaces/ITokiErrors.sol";
import "../interfaces/ITransferPoolFeeCalculator.sol";
import "../interfaces/IPool.sol";
import "./MessageType.sol";

library IBCUtils {
    struct ExternalInfo {
        bytes payload;
        uint256 dstOuterGas;
    }

    struct SendCreditPayload {
        uint8 ftype;
        uint256 srcPoolId;
        uint256 dstPoolId;
        IPool.CreditInfo creditInfo;
    }

    struct TransferPoolPayload {
        uint8 ftype;
        uint256 srcPoolId;
        uint256 dstPoolId;
        ITransferPoolFeeCalculator.FeeInfo feeInfo;
        IPool.CreditInfo creditInfo;
        bytes to;
        uint256 refuelAmount;
        ExternalInfo externalInfo;
    }

    struct TransferTokenPayload {
        uint8 ftype;
        string denom;
        uint256 amount;
        bytes to;
        uint256 refuelAmount;
        ExternalInfo externalInfo;
    }

    struct WithdrawCheckPayload {
        uint8 ftype;
        uint256 withdrawLocalPoolId;
        uint256 withdrawCheckPoolId;
        uint256 transferAmountGD;
        uint256 mintAmountGD;
        IPool.CreditInfo creditInfo;
        bytes to;
    }

    struct WithdrawPayload {
        uint8 ftype;
        uint256 withdrawLocalPoolId;
        uint256 withdrawCheckPoolId;
        uint256 amountGD;
        IPool.CreditInfo creditInfo;
        bytes to;
    }

    struct RetryReceivePoolPayload {
        uint8 ftype;
        uint256 appVersion;
        uint256 lastValidHeight;
        uint256 srcPoolId;
        uint256 dstPoolId;
        address to;
        ITransferPoolFeeCalculator.FeeInfo feeInfo;
        uint256 refuelAmount;
        ExternalInfo externalInfo;
    }

    struct RetryReceiveTokenPayload {
        uint8 ftype;
        uint256 appVersion;
        uint256 lastValidHeight;
        string denom;
        uint256 amount;
        address to;
        uint256 refuelAmount;
        ExternalInfo externalInfo;
    }

    struct RetryExternalCallPayload {
        uint8 ftype;
        uint256 appVersion;
        uint256 lastValidHeight;
        address token;
        uint256 amount;
        address to;
        ExternalInfo externalInfo;
    }

    struct RetryRefuelCallPayload {
        uint8 ftype;
        uint256 appVersion;
        uint256 lastValidHeight;
        address to;
        uint256 refuelAmount;
    }

    struct RetryRefuelAndExternalCallPayload {
        uint8 ftype;
        uint256 appVersion;
        uint256 lastValidHeight;
        address token;
        uint256 amount;
        address to;
        uint256 refuelAmount;
        ExternalInfo externalInfo;
    }

    struct RetryWithdrawConfirmPayload {
        uint8 ftype;
        uint256 appVersion;
        uint256 lastValidHeight;
        uint256 withdrawLocalPoolId;
        uint256 withdrawCheckPoolId;
        address to;
        uint256 transferAmountGD;
        uint256 mintAmountGD;
    }

    uint8 internal constant _TYPE_RETRY_RECEIVE_POOL = 1;
    uint8 internal constant _TYPE_RETRY_WITHDRAW_CONFIRM = 2;
    uint8 internal constant _TYPE_RETRY_RECEIVE_TOKEN = 5;
    uint8 internal constant _TYPE_RETRY_EXTERNAL_CALL = 10;
    uint8 internal constant _TYPE_RETRY_REFUEL_CALL = 11;
    uint8 internal constant _TYPE_RETRY_REFUEL_AND_EXTERNAL_CALL = 12;

    error SafeTransferFromFailed(bool success, bytes data);

    /**
     * internal helper function(with external call)
     */
    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, value)
        );
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
            revert SafeTransferFromFailed(success, data);
        }
    }

    function parseType(
        bytes memory payload
    ) internal pure returns (uint8 ftype) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            ftype := mload(add(payload, 32))
        }
    }

    function encodeTransferPool(
        uint256 srcPoolId,
        uint256 dstPoolId,
        ITransferPoolFeeCalculator.FeeInfo memory feeInfo,
        IPool.CreditInfo memory creditInfo,
        bytes memory to,
        uint256 refuelAmount,
        ExternalInfo memory externalInfo
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                MessageType._TYPE_TRANSFER_POOL,
                srcPoolId,
                dstPoolId,
                feeInfo,
                creditInfo,
                to,
                refuelAmount,
                externalInfo
            );
    }

    function decodeTransferPool(
        bytes memory payload
    ) internal pure returns (TransferPoolPayload memory) {
        (
            uint8 ftype,
            uint256 srcPoolId,
            uint256 dstPoolId,
            ITransferPoolFeeCalculator.FeeInfo memory feeInfo,
            IPool.CreditInfo memory creditInfo,
            bytes memory to,
            uint256 refuelAmount,
            ExternalInfo memory externalInfo
        ) = abi.decode(
                payload,
                (
                    uint8,
                    uint256,
                    uint256,
                    ITransferPoolFeeCalculator.FeeInfo,
                    IPool.CreditInfo,
                    bytes,
                    uint256,
                    ExternalInfo
                )
            );
        TransferPoolPayload memory p = TransferPoolPayload(
            ftype,
            srcPoolId,
            dstPoolId,
            feeInfo,
            creditInfo,
            to,
            refuelAmount,
            externalInfo
        );
        return p;
    }

    function encodeCredit(
        uint256 srcPoolId,
        uint256 dstPoolId,
        IPool.CreditInfo memory creditInfo
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                MessageType._TYPE_CREDIT,
                srcPoolId,
                dstPoolId,
                creditInfo
            );
    }

    function decodeCredit(
        bytes memory payload
    ) internal pure returns (SendCreditPayload memory) {
        (
            uint8 ftype,
            uint256 srcPoolId,
            uint256 dstPoolId,
            IPool.CreditInfo memory creditInfo
        ) = abi.decode(payload, (uint8, uint256, uint256, IPool.CreditInfo));
        SendCreditPayload memory p = SendCreditPayload(
            ftype,
            srcPoolId,
            dstPoolId,
            creditInfo
        );
        return p;
    }

    function encodeWithdraw(
        uint256 withdrawLocalPoolId,
        uint256 withdrawCheckPoolId,
        uint256 amountGD,
        IPool.CreditInfo memory creditInfo,
        bytes memory to
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                MessageType._TYPE_WITHDRAW,
                withdrawLocalPoolId,
                withdrawCheckPoolId,
                amountGD,
                creditInfo,
                to
            );
    }

    function decodeWithdraw(
        bytes memory payload
    ) internal pure returns (WithdrawPayload memory) {
        (
            uint8 ftype,
            uint256 withdrawLocalPoolId,
            uint256 withdrawCheckPoolId,
            uint256 amountGD,
            IPool.CreditInfo memory creditInfo,
            bytes memory to
        ) = abi.decode(
                payload,
                (uint8, uint256, uint256, uint256, IPool.CreditInfo, bytes)
            );
        WithdrawPayload memory p = WithdrawPayload(
            ftype,
            withdrawLocalPoolId,
            withdrawCheckPoolId,
            amountGD,
            creditInfo,
            to
        );
        return p;
    }

    function encodeWithdrawCheck(
        uint256 withdrawLocalPoolId,
        uint256 withdrawCheckPoolId,
        uint256 transferAmount,
        uint256 mintAmount,
        IPool.CreditInfo memory creditInfo,
        bytes memory to
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                MessageType._TYPE_WITHDRAW_CHECK,
                withdrawLocalPoolId,
                withdrawCheckPoolId,
                transferAmount,
                mintAmount,
                creditInfo,
                to
            );
    }

    function decodeWithdrawCheck(
        bytes memory payload
    ) internal pure returns (WithdrawCheckPayload memory) {
        (
            uint8 ftype,
            uint256 withdrawLocalPoolId,
            uint256 withdrawCheckPoolId,
            uint256 transferAmount,
            uint256 mintAmount,
            IPool.CreditInfo memory creditInfo,
            bytes memory to
        ) = abi.decode(
                payload,
                (
                    uint8,
                    uint256,
                    uint256,
                    uint256,
                    uint256,
                    IPool.CreditInfo,
                    bytes
                )
            );
        WithdrawCheckPayload memory p = WithdrawCheckPayload(
            ftype,
            withdrawLocalPoolId,
            withdrawCheckPoolId,
            transferAmount,
            mintAmount,
            creditInfo,
            to
        );
        return p;
    }

    function encodeTransferToken(
        string memory denom,
        uint256 amount,
        bytes memory to,
        uint256 refuelAmount,
        ExternalInfo memory externalInfo
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                MessageType._TYPE_TRANSFER_TOKEN,
                denom,
                amount,
                to,
                refuelAmount,
                externalInfo
            );
    }

    function decodeTransferToken(
        bytes memory payload
    ) internal pure returns (TransferTokenPayload memory) {
        (
            uint8 ftype,
            string memory denom,
            uint256 amount,
            bytes memory to,
            uint256 refuelAmount,
            ExternalInfo memory externalInfo
        ) = abi.decode(
                payload,
                (uint8, string, uint256, bytes, uint256, ExternalInfo)
            );
        TransferTokenPayload memory p = TransferTokenPayload(
            ftype,
            denom,
            amount,
            to,
            refuelAmount,
            externalInfo
        );
        return p;
    }

    function encodeRetryReceivePool(
        uint256 appVersion,
        uint256 lastValidHeight,
        uint256 srcPoolId,
        uint256 dstPoolId,
        address to,
        ITransferPoolFeeCalculator.FeeInfo memory feeInfo,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo memory externalInfo
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                _TYPE_RETRY_RECEIVE_POOL,
                appVersion,
                lastValidHeight,
                srcPoolId,
                dstPoolId,
                to,
                feeInfo,
                refuelAmount,
                externalInfo
            );
    }

    function decodeRetryReceivePool(
        bytes memory payload
    ) internal pure returns (RetryReceivePoolPayload memory) {
        (
            uint8 ftype,
            uint256 appVersion,
            uint256 lastValidHeight,
            uint256 srcPoolId,
            uint256 dstPoolId,
            address to,
            ITransferPoolFeeCalculator.FeeInfo memory feeInfo,
            uint256 refuelAmount,
            IBCUtils.ExternalInfo memory externalInfo
        ) = abi.decode(
                payload,
                (
                    uint8,
                    uint256, // appVersion
                    uint256, // lastValidHeight
                    uint256, // srcPoolId
                    uint256, // dstPoolId
                    address, // to
                    ITransferPoolFeeCalculator.FeeInfo, // feeInfo
                    uint256, // refuelAmount
                    IBCUtils.ExternalInfo // externalInfo
                )
            );
        RetryReceivePoolPayload memory p = RetryReceivePoolPayload(
            ftype,
            appVersion,
            lastValidHeight,
            srcPoolId,
            dstPoolId,
            to,
            feeInfo,
            refuelAmount,
            externalInfo
        );
        return p;
    }

    function encodeRetryReceiveToken(
        uint256 appVersion,
        uint256 lastValidHeight,
        string memory denom,
        uint256 amount,
        address to,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo memory externalInfo
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                _TYPE_RETRY_RECEIVE_TOKEN,
                appVersion,
                lastValidHeight,
                denom,
                amount,
                to,
                refuelAmount,
                externalInfo
            );
    }

    function decodeRetryReceiveToken(
        bytes memory payload
    ) internal pure returns (RetryReceiveTokenPayload memory) {
        (
            uint8 ftype,
            uint256 appVersion,
            uint256 lastValidHeight,
            string memory denom,
            uint256 amount,
            address to,
            uint256 refuelAmount,
            IBCUtils.ExternalInfo memory externalInfo
        ) = abi.decode(
                payload,
                (
                    uint8,
                    uint256,
                    uint256,
                    string,
                    uint256,
                    address,
                    uint256,
                    IBCUtils.ExternalInfo
                )
            );
        RetryReceiveTokenPayload memory p = RetryReceiveTokenPayload(
            ftype,
            appVersion,
            lastValidHeight,
            denom,
            amount,
            to,
            refuelAmount,
            externalInfo
        );
        return p;
    }

    function encodeRetryWithdrawConfirm(
        uint256 appVersion,
        uint256 lastValidHeight,
        uint256 srcPoolId,
        uint256 dstPoolId,
        address to,
        uint256 transferAmount,
        uint256 mintAmount
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                _TYPE_RETRY_WITHDRAW_CONFIRM,
                appVersion,
                lastValidHeight,
                srcPoolId,
                dstPoolId,
                to,
                transferAmount,
                mintAmount
            );
    }

    function decodeRetryWithdrawConfirm(
        bytes memory payload
    ) internal pure returns (RetryWithdrawConfirmPayload memory) {
        (
            uint8 ftype,
            uint256 appVersion,
            uint256 lastValidHeight,
            uint256 srcPoolId,
            uint256 dstPoolId,
            address to,
            uint256 transferAmount,
            uint256 mintAmount
        ) = abi.decode(
                payload,
                (
                    uint8,
                    uint256,
                    uint256,
                    uint256,
                    uint256,
                    address,
                    uint256,
                    uint256
                )
            );
        RetryWithdrawConfirmPayload memory p = RetryWithdrawConfirmPayload(
            ftype,
            appVersion,
            lastValidHeight,
            srcPoolId,
            dstPoolId,
            to,
            transferAmount,
            mintAmount
        );
        return p;
    }

    function encodeRetryExternalCall(
        uint256 appVersion,
        uint256 lastValidHeight,
        address token,
        uint256 amount,
        address to,
        IBCUtils.ExternalInfo memory externalInfo
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                _TYPE_RETRY_EXTERNAL_CALL,
                appVersion,
                lastValidHeight,
                token,
                amount,
                to,
                externalInfo
            );
    }

    function decodeRetryExternalCall(
        bytes memory payload
    ) internal pure returns (RetryExternalCallPayload memory) {
        (
            uint8 ftype,
            uint256 appVersion,
            uint256 lastValidHeight,
            address token,
            uint256 amount,
            address to,
            IBCUtils.ExternalInfo memory externalInfo
        ) = abi.decode(
                payload,
                (
                    uint8,
                    uint256,
                    uint256,
                    address,
                    uint256,
                    address,
                    IBCUtils.ExternalInfo
                )
            );
        RetryExternalCallPayload memory p = RetryExternalCallPayload(
            ftype,
            appVersion,
            lastValidHeight,
            token,
            amount,
            to,
            externalInfo
        );
        return p;
    }

    function encodeRetryRefuelCall(
        uint256 appVersion,
        uint256 lastValidHeight,
        address to,
        uint256 refuelAmount
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                _TYPE_RETRY_REFUEL_CALL,
                appVersion,
                lastValidHeight,
                to,
                refuelAmount
            );
    }

    function decodeRetryRefuelCall(
        bytes memory payload
    ) internal pure returns (RetryRefuelCallPayload memory) {
        (
            uint8 ftype,
            uint256 appVersion,
            uint256 lastValidHeight,
            address to,
            uint256 refuelAmount
        ) = abi.decode(payload, (uint8, uint256, uint256, address, uint256));
        RetryRefuelCallPayload memory p = RetryRefuelCallPayload(
            ftype,
            appVersion,
            lastValidHeight,
            to,
            refuelAmount
        );
        return p;
    }

    function encodeRetryRefuelAndExternalCall(
        uint256 appVersion,
        uint256 lastValidHeight,
        address token,
        uint256 amount,
        address to,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo memory externalInfo
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                _TYPE_RETRY_REFUEL_AND_EXTERNAL_CALL,
                appVersion,
                lastValidHeight,
                token,
                amount,
                to,
                refuelAmount,
                externalInfo
            );
    }

    function decodeRetryRefuelAndExternalCall(
        bytes memory payload
    ) internal pure returns (RetryRefuelAndExternalCallPayload memory) {
        (
            uint8 ftype,
            uint256 appVersion,
            uint256 lastValidHeight,
            address token,
            uint256 amount,
            address to,
            uint256 refuelAmount,
            IBCUtils.ExternalInfo memory externalInfo
        ) = abi.decode(
                payload,
                (
                    uint8,
                    uint256,
                    uint256,
                    address,
                    uint256,
                    address,
                    uint256,
                    IBCUtils.ExternalInfo
                )
            );
        RetryRefuelAndExternalCallPayload
            memory p = RetryRefuelAndExternalCallPayload(
                ftype,
                appVersion,
                lastValidHeight,
                token,
                amount,
                to,
                refuelAmount,
                externalInfo
            );
        return p;
    }

    function decodeAddress(
        bytes memory data
    ) internal pure returns (address addr, bool success) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            success := eq(mload(data), 20)
            addr := mload(add(data, 20))
        }
    }

    function encodeAddress(address addr) internal pure returns (bytes memory) {
        return abi.encodePacked(addr);
    }
}
