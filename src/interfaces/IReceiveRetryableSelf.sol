// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../library/IBCUtils.sol";

interface IReceiveRetryableSelf {
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
    ) external;

    function addRevertReceiveToken(
        uint256 srcChainId,
        uint64 sequence,
        string memory denom,
        uint256 amount,
        address to,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo memory externalInfo,
        uint256 lastValidHeightOrZero
    ) external;

    function addRevertRefuel(
        uint256 srcChainId,
        uint64 sequence,
        address to,
        uint256 refuelAmount,
        uint256 lastValidHeightOrZero
    ) external;

    function addRevertRefuelAndExternal(
        uint256 srcChainId,
        uint64 sequence,
        address token,
        uint256 amount,
        address to,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo memory externalInfo,
        uint256 lastValidHeightOrZero
    ) external;

    function addRevertExternal(
        uint256 srcChainId,
        uint64 sequence,
        address token,
        uint256 amount,
        address to,
        IBCUtils.ExternalInfo memory externalInfo,
        uint256 lastValidHeightOrZero
    ) external;

    function addRevertWithdrawConfirm(
        uint256 srcChainId,
        uint64 sequence,
        uint256 withdrawLocalPoolId,
        uint256 withdrawCheckPoolId,
        address to,
        uint256 amountGD,
        uint256 mintAmountGD,
        uint256 lastValidHeightOrZero
    ) external;
}
