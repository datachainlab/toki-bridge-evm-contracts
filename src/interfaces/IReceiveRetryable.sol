// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../library/IBCUtils.sol";

/**
 * @title IReceiveRetryable
 * @dev Interface that contains the retry functions of the Bridge service.
 */
interface IReceiveRetryable {
    /**
     * @dev Emitted when a revert occurs in onRecvPacket.
     * @param retryType The type of retry.
     * @param chainId The chain ID.
     * @param sequence The sequence of the IBC packet.
     * @param lastValidHeight The last valid height for the chain associated with ChainID.
     */
    event RevertReceive(
        uint8 retryType,
        uint256 chainId,
        uint64 sequence,
        uint256 lastValidHeight
    );

    /**
     * @dev Retries the operation that failed during OnRecvPacket handling.
     * If cross-chain transactions fail, the user can retry.
     * Retry is allowed until lastValidHeight. Once the expiration has passed, the assets will be lost.
     * @param dstChannel The destination channel.
     * @param sequence The sequence of the IBC packet.
     */
    function retryOnReceive(
        string calldata dstChannel,
        uint64 sequence
    ) external;
}
