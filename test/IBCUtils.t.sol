// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/library/IBCUtils.sol";
import "../src/library/MessageType.sol";
import "../src/interfaces/ITransferPoolFeeCalculator.sol";
import "../src/interfaces/IPool.sol";

contract IBCUtilsTest is Test {
    uint256 public constant SRC_POOL_ID = 1;
    uint256 public constant DST_POOL_ID = 2;

    function setUp() public {}

    function testEncodeDecodeTransferPool() public {
        ITransferPoolFeeCalculator.FeeInfo
            memory feeInfo = ITransferPoolFeeCalculator.FeeInfo(
                100,
                1,
                2,
                3,
                1,
                100
            );
        IPool.CreditInfo memory creditInfo = IPool.CreditInfo(1, 200);
        bytes memory to = abi.encodePacked(address(0x1));
        uint256 refuelAmount = 100;
        IBCUtils.ExternalInfo memory externalInfo = IBCUtils.ExternalInfo(
            bytes("testpayload"),
            10000
        );

        bytes memory payload = IBCUtils.encodeTransferPool(
            SRC_POOL_ID,
            DST_POOL_ID,
            feeInfo,
            creditInfo,
            to,
            refuelAmount,
            externalInfo
        );
        IBCUtils.TransferPoolPayload memory p = IBCUtils.decodeTransferPool(
            payload
        );

        assertEq(p.ftype, MessageType._TYPE_TRANSFER_POOL);
        assertEq(p.srcPoolId, SRC_POOL_ID);
        assertEq(p.dstPoolId, DST_POOL_ID);
        _assertFeeInfo(p.feeInfo, feeInfo);
        _assertCreditInfo(p.creditInfo, creditInfo);
        assertEq(p.to, to);
        assertEq(p.refuelAmount, refuelAmount);
        _assertExternalInfo(p.externalInfo, externalInfo);
    }

    function testEncodeDecodeCredit() public {
        IPool.CreditInfo memory creditInfo = IPool.CreditInfo(1, 200);
        bytes memory payload = IBCUtils.encodeCredit(
            SRC_POOL_ID,
            DST_POOL_ID,
            creditInfo
        );
        IBCUtils.SendCreditPayload memory p = IBCUtils.decodeCredit(payload);
        assertEq(p.ftype, MessageType._TYPE_CREDIT);
        assertEq(p.srcPoolId, SRC_POOL_ID);
        assertEq(p.dstPoolId, DST_POOL_ID);
        _assertCreditInfo(p.creditInfo, creditInfo);
    }

    function testEncodeDecodeWithdraw() public {
        uint256 amountGD = 100;
        IPool.CreditInfo memory creditInfo = IPool.CreditInfo(1, 200);
        bytes memory to = abi.encodePacked(address(0x1));
        bytes memory payload = IBCUtils.encodeWithdraw(
            SRC_POOL_ID,
            DST_POOL_ID,
            amountGD,
            creditInfo,
            to
        );
        IBCUtils.WithdrawPayload memory p = IBCUtils.decodeWithdraw(payload);
        assertEq(p.ftype, MessageType._TYPE_WITHDRAW);
        assertEq(p.withdrawLocalPoolId, SRC_POOL_ID);
        assertEq(p.withdrawCheckPoolId, DST_POOL_ID);
        assertEq(p.amountGD, amountGD);
        _assertCreditInfo(p.creditInfo, creditInfo);
        assertEq(p.to, to);
    }

    function testEncodeDecodeWithdrawCheck() public {
        uint256 transferAmount = 100;
        uint256 mintAmount = 200;
        IPool.CreditInfo memory creditInfo = IPool.CreditInfo(1, 200);
        bytes memory to = abi.encodePacked(address(0x1));
        bytes memory payload = IBCUtils.encodeWithdrawCheck(
            SRC_POOL_ID,
            DST_POOL_ID,
            transferAmount,
            mintAmount,
            creditInfo,
            to
        );
        IBCUtils.WithdrawCheckPayload memory p = IBCUtils.decodeWithdrawCheck(
            payload
        );
        assertEq(p.ftype, MessageType._TYPE_WITHDRAW_CHECK);
        assertEq(p.withdrawLocalPoolId, SRC_POOL_ID);
        assertEq(p.withdrawCheckPoolId, DST_POOL_ID);
        assertEq(p.transferAmountGD, transferAmount);
        assertEq(p.mintAmountGD, mintAmount);
        _assertCreditInfo(p.creditInfo, creditInfo);
        assertEq(p.to, to);
    }

    function testEncodeDecodeTransferToken() public {
        string memory denom = "testdenom";
        uint256 amount = 100;
        bytes memory to = abi.encodePacked(address(0x1));
        uint256 refuelAmount = 100;
        IBCUtils.ExternalInfo memory externalInfo = IBCUtils.ExternalInfo(
            bytes("testpayload"),
            10000
        );
        bytes memory payload = IBCUtils.encodeTransferToken(
            denom,
            amount,
            to,
            refuelAmount,
            externalInfo
        );
        IBCUtils.TransferTokenPayload memory p = IBCUtils.decodeTransferToken(
            payload
        );
        assertEq(p.ftype, MessageType._TYPE_TRANSFER_TOKEN);
        assertEq(p.denom, denom);
        assertEq(p.amount, amount);
        assertEq(p.to, to);
        assertEq(p.refuelAmount, refuelAmount);
        _assertExternalInfo(p.externalInfo, externalInfo);
    }

    function testEncodeDecodeRetryReceivePool() public {
        ITransferPoolFeeCalculator.FeeInfo
            memory feeInfo = ITransferPoolFeeCalculator.FeeInfo(
                100,
                1,
                2,
                3,
                1,
                100
            );

        address to = address(0x1);
        uint256 refuelAmount = 100;
        IBCUtils.ExternalInfo memory externalInfo = IBCUtils.ExternalInfo(
            bytes("testpayload"),
            10000
        );
        bytes memory payload = IBCUtils.encodeRetryReceivePool(
            1,
            10000,
            SRC_POOL_ID,
            DST_POOL_ID,
            to,
            feeInfo,
            refuelAmount,
            externalInfo
        );
        IBCUtils.RetryReceivePoolPayload memory p = IBCUtils
            .decodeRetryReceivePool(payload);

        assertEq(p.ftype, IBCUtils._TYPE_RETRY_RECEIVE_POOL);
        assertEq(p.appVersion, 1);
        assertEq(p.lastValidHeight, 10000);
        assertEq(p.srcPoolId, SRC_POOL_ID);
        assertEq(p.dstPoolId, DST_POOL_ID);
        assertEq(p.to, to);
        _assertFeeInfo(p.feeInfo, feeInfo);
        assertEq(p.refuelAmount, refuelAmount);
        _assertExternalInfo(p.externalInfo, externalInfo);
    }

    function testEncodeDecodeRetryReceiveToken() public {
        string memory denom = "testdenom";
        uint256 amount = 100;
        address to = address(0x1);
        uint256 refuelAmount = 100;
        IBCUtils.ExternalInfo memory externalInfo = IBCUtils.ExternalInfo(
            bytes("testpayload"),
            10000
        );
        bytes memory payload = IBCUtils.encodeRetryReceiveToken(
            1,
            10000,
            denom,
            amount,
            to,
            refuelAmount,
            externalInfo
        );
        IBCUtils.RetryReceiveTokenPayload memory p = IBCUtils
            .decodeRetryReceiveToken(payload);
        assertEq(p.ftype, IBCUtils._TYPE_RETRY_RECEIVE_TOKEN);
        assertEq(p.appVersion, 1);
        assertEq(p.lastValidHeight, 10000);
        assertEq(p.denom, denom);
        assertEq(p.amount, amount);
        assertEq(p.to, to);
        assertEq(p.refuelAmount, refuelAmount);
        _assertExternalInfo(p.externalInfo, externalInfo);
    }

    function testEncodeDecodeRetryWithdrawConfirm() public {
        uint256 amount = 100;
        uint256 mintAmount = 200;
        address to = address(0x1);
        bytes memory payload = IBCUtils.encodeRetryWithdrawConfirm(
            1,
            5000,
            SRC_POOL_ID,
            DST_POOL_ID,
            to,
            amount,
            mintAmount
        );
        IBCUtils.RetryWithdrawConfirmPayload memory p = IBCUtils
            .decodeRetryWithdrawConfirm(payload);
        assertEq(p.ftype, IBCUtils._TYPE_RETRY_WITHDRAW_CONFIRM);
        assertEq(p.appVersion, 1);
        assertEq(p.lastValidHeight, 5000);
        assertEq(p.withdrawLocalPoolId, SRC_POOL_ID);
        assertEq(p.withdrawCheckPoolId, DST_POOL_ID);
        assertEq(p.to, to);
        assertEq(p.transferAmountGD, amount);
        assertEq(p.mintAmountGD, mintAmount);
    }

    function testEncodeDecodeRetryExternalCall() public {
        address token = address(0x1);
        uint256 amount = 100;
        address to = address(0x2);
        IBCUtils.ExternalInfo memory externalInfo = IBCUtils.ExternalInfo(
            bytes("testpayload"),
            10000
        );
        bytes memory payload = IBCUtils.encodeRetryExternalCall(
            1,
            2500,
            token,
            amount,
            to,
            externalInfo
        );
        IBCUtils.RetryExternalCallPayload memory p = IBCUtils
            .decodeRetryExternalCall(payload);
        assertEq(p.ftype, IBCUtils._TYPE_RETRY_EXTERNAL_CALL);
        assertEq(p.appVersion, 1);
        assertEq(p.lastValidHeight, 2500);
        assertEq(p.token, token);
        assertEq(p.amount, amount);
        assertEq(p.to, to);
        _assertExternalInfo(p.externalInfo, externalInfo);
    }

    function testEncodeDecodeRetryRefuelCall() public {
        address to = address(0x1);
        uint256 amount = 100;
        uint256 appVersion = 1;
        uint256 lastValidHeight = 2500;
        bytes memory payload = IBCUtils.encodeRetryRefuelCall(
            appVersion,
            lastValidHeight,
            to,
            amount
        );
        IBCUtils.RetryRefuelCallPayload memory p = IBCUtils
            .decodeRetryRefuelCall(payload);
        assertEq(p.ftype, IBCUtils._TYPE_RETRY_REFUEL_CALL);
        assertEq(p.appVersion, appVersion);
        assertEq(p.lastValidHeight, lastValidHeight);
        assertEq(p.to, to);
        assertEq(p.refuelAmount, amount);
    }

    function testEncodeDecodeRetryRefuenAndExternalCall() public {
        address token = address(0x1);
        uint256 amount = 100;
        address to = address(0x2);
        uint256 refuelAmount = 100;
        IBCUtils.ExternalInfo memory externalInfo = IBCUtils.ExternalInfo(
            bytes("testpayload"),
            10000
        );
        bytes memory payload = IBCUtils.encodeRetryRefuelAndExternalCall(
            1,
            2500,
            token,
            amount,
            to,
            refuelAmount,
            externalInfo
        );
        IBCUtils.RetryRefuelAndExternalCallPayload memory p = IBCUtils
            .decodeRetryRefuelAndExternalCall(payload);
        assertEq(p.ftype, IBCUtils._TYPE_RETRY_REFUEL_AND_EXTERNAL_CALL);
        assertEq(p.appVersion, 1);
        assertEq(p.lastValidHeight, 2500);
        assertEq(p.token, token);
        assertEq(p.amount, amount);
        assertEq(p.to, to);
        assertEq(p.refuelAmount, refuelAmount);
        _assertExternalInfo(p.externalInfo, externalInfo);
    }

    function testEncodeDecodeAddress() public {
        address testAddr = address(0x1234567890123456789012345678901234567890);

        // Test encoding
        bytes memory encoded = IBCUtils.encodeAddress(testAddr);
        assertEq(encoded.length, 20, "Encoded address should be 20 bytes long");

        // Test decoding
        (address decoded, bool success) = IBCUtils.decodeAddress(encoded);
        assertTrue(success, "Decoding should be successful");
        assertEq(decoded, testAddr, "Decoded address should match original");
    }

    function testDecodeInvalidLength() public {
        bytes memory invalidData = abi.encodePacked(uint256(1234)); // 32 bytes long

        (address decoded, bool success) = IBCUtils.decodeAddress(invalidData);
        assertFalse(success, "Decoding should fail for invalid length");
        assertEq(
            decoded,
            address(0),
            "Decoded address should be zero for failed decoding"
        );
    }

    function testFuzzEncodeDecodeAddress(address fuzzAddr) public {
        bytes memory encoded = IBCUtils.encodeAddress(fuzzAddr);
        (address decoded, bool success) = IBCUtils.decodeAddress(encoded);

        assertTrue(
            success,
            "Decoding should always succeed for valid encoded addresses"
        );
        assertEq(
            decoded,
            fuzzAddr,
            "Decoded address should match original for all addresses"
        );
    }

    function _assertFeeInfo(
        ITransferPoolFeeCalculator.FeeInfo memory a,
        ITransferPoolFeeCalculator.FeeInfo memory b
    ) internal pure {
        assertEq(a.amountGD, b.amountGD);
        assertEq(a.protocolFee, b.protocolFee);
        assertEq(a.lpFee, b.lpFee);
        assertEq(a.eqFee, b.eqFee);
        assertEq(a.eqReward, b.eqReward);
        assertEq(a.balanceDecrease, b.balanceDecrease);
    }

    function _assertCreditInfo(
        IPool.CreditInfo memory a,
        IPool.CreditInfo memory b
    ) internal pure {
        assertEq(a.credits, b.credits);
        assertEq(a.targetBalance, b.targetBalance);
    }

    function _assertExternalInfo(
        IBCUtils.ExternalInfo memory a,
        IBCUtils.ExternalInfo memory b
    ) internal pure {
        assertEq(a.payload, b.payload);
        assertEq(a.dstOuterGas, b.dstOuterGas);
    }
}
