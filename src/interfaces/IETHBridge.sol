// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../library/IBCUtils.sol";

/**
 * @title IETHBridge
 * @dev Interface for ETHBridge that supports the cross-chain bridge of native ETH.
 */
interface IETHBridge {
    /**
     * @dev Deposits ETH into the ETH pool. The native ETH is minted as wrapped ETH and deposited into the pool.
     */
    function depositETH() external payable;

    /**
     * @dev Transfers ETH from the source chain to the destination chain.
     * The caller must send native ETH as msg.value along with the function call.
     * @param srcChannel The channel for identifying the destination chain.
     * @param amountLD The amount of native ETH in LD units to transfer.
     * LD stands for Local Decimals. For more details, please refer to IPool.
     * @param minAmountLD The minimum amount of native ETH in LD units to receive.
     * @param to The destination chain address to receive the wrapped ETH.
     * @param refuelAmount The amount of the destination chain's native asset.
     * The equivalent value of native ETH is consumed on the source.
     * @param externalInfo The payload to call the outer service on the destination chain.
     * @param refundTo The address to refund the remaining native ETH.
     */
    function transferETH(
        string calldata srcChannel,
        uint256 amountLD,
        uint256 minAmountLD,
        bytes calldata to,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo calldata externalInfo,
        address payable refundTo
    ) external payable;
}
