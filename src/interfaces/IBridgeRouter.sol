// SPDX-License-Identifier: BUSL-1.1
// solhint-disable-next-line one-contract-per-file
pragma solidity ^0.8.13;

import "../library/IBCUtils.sol";

/**
 * @title IBridgeStandardRouter
 * @dev Interface that contains the standard functions of the Bridge service.
 */
interface IBridgeStandardRouter {
    /**
     * @dev Deposits tokens into the specified pool to provide liquidity.
     * In exchange for depositing asset tokens, LP tokens are obtained.
     * @param poolId The ID of the pool to deposit into.
     * @param amountLD The amount of tokens to deposit in LD units.
     * @param to The address to receive the deposited tokens.
     */
    function deposit(
        uint256 poolId,
        uint256 amountLD,
        address to
    ) external payable;

    /**
     * @dev Transfers tokens from the source pool to the destination pool and makes a remittance request on the destination side.
     * Initiates cross-chain transactions. For a detailed flow, refer to IPool.
     * @param srcChannel The channel for identifying the destination chain.
     * @param srcPoolId The ID of the source pool.
     * @param dstPoolId The ID of the destination pool.
     * @param amountLD The amount of tokens to transfer in LD units.
     * @param minAmountLD The minimum amount of tokens to transfer in LD units.
     * @param to The address to receive the transferred tokens.
     * @param refuelAmount The amount of the destination chain's native asset.
     * The equivalent value of native asset is consumed on the source.
     * @param externalInfo The payload to call the outer service on the destination chain.
     * @param refundTo The address to refund the remaining native asset.
     */
    function transferPool(
        string calldata srcChannel,
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLD,
        uint256 minAmountLD,
        bytes calldata to,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo calldata externalInfo,
        address payable refundTo
    ) external payable;

    /**
     * @dev Transfers the token escrow from the source chain to the destination chain.
     * Initiates cross-chain transactions. For a detailed flow, refer to IPool.
     * @param srcChannel The channel for identifying the destination chain.
     * @param denom The denomination of tokens.
     * @param amountLD The amount of tokens to transfer in LD units.
     * @param to The address to receive the transferred tokens.
     * @param refuelAmount The amount of the destination chain's native asset.
     * The equivalent value of native asset is consumed on the source.
     * @param externalInfo The payload to call the outer service on the destination chain.
     * @param refundTo The address to refund the remaining native asset.
     */
    function transferToken(
        string calldata srcChannel,
        string calldata denom,
        uint256 amountLD,
        bytes calldata to,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo calldata externalInfo,
        address payable refundTo
    ) external payable;

    /**
     * @dev Withdraws tokens from the source pool to the destination pool, and in exchange, burn LP tokens locally.
     * Initiates cross-chain transactions. For a detailed flow, refer to IPool.
     * @param srcChannel The channel for identifying the destination chain.
     * @param srcPoolId The ID of the source pool.
     * @param dstPoolId The ID of the destination pool.
     * @param amountLP The amount of LP tokens to burn.
     * @param minAmountLD The minimum amount of tokens to withdraw in LD units.
     * @param to The address to receive the withdrawn tokens.
     * @param refundTo The address to refund the remaining native asset.
     */
    function withdrawRemote(
        string calldata srcChannel,
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLP,
        uint256 minAmountLD,
        bytes calldata to,
        address payable refundTo
    ) external payable;

    /**
     * @dev Withdraws tokens from the destination pool to the source pool.
     * withdrawLocal burns local LP tokens and uses the balance that the destination pool can send to the source pool to withdraw tokens in the source pool.
     * Initiates cross-chain transactions. For a detailed flow, refer to IPool.
     * @param srcChannel The channel for identifying the destination chain.
     * @param srcPoolId The ID of the source pool.
     * @param dstPoolId The ID of the destination pool.
     * @param amountLP The amount of LP tokens to burn.
     * @param to The address to receive the withdrawn tokens.
     * @param refundTo The address to refund the remaining native asset.
     */
    function withdrawLocal(
        string calldata srcChannel,
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLP,
        bytes calldata to,
        address payable refundTo
    ) external payable;

    /** In Ledger **/

    /**
     * @dev Transfers tokens from the source pool to the destination pool and makes a remittance request on the destination side.
     * If it has the suffix 'InLedger', it is a single transaction rather than a cross-chain transaction.
     * @param srcPoolId The ID of the source pool.
     * @param dstPoolId The ID of the destination pool.
     * @param amountLD_ The amount of tokens to transfer in LD units.
     * @param minAmountLD The minimum amount of tokens to transfer in LD units.
     * @param to The address to receive the transferred tokens.
     * @param externalInfo The payload to call the outer service on the source chain.
     */
    function transferPoolInLedger(
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLD_,
        uint256 minAmountLD,
        address to,
        IBCUtils.ExternalInfo calldata externalInfo
    ) external;

    /**
     * @dev Withdraws tokens instantly.
     * @param srcPoolId The address from which the tokens are withdrawn.
     * @param amountLP The amount of LP tokens to withdraw in GD units.
     * @param to The address to receive the tokens.
     * @return amountGD The amount of tokens withdrawn in GD units.
     */
    function withdrawInstant(
        uint256 srcPoolId,
        uint256 amountLP,
        address to
    ) external returns (uint256 amountGD);

    /**
     * @dev Withdraws tokens from the destination pool to the source pool.
     * If it has the suffix 'InLedger', it is a single transaction rather than a cross-chain transaction.
     * @param srcPoolId The ID of the source pool.
     * @param dstPoolId The ID of the destination pool.
     * @param amountLP The amount of LP tokens to burn.
     * @param to The address to receive the withdrawn tokens.
     */
    function withdrawLocalInLedger(
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLP,
        address to
    ) external;

    /**
     * @dev Withdraws tokens from the source pool to the destination pool, and in exchange, burn LP tokens locally.
     * If it has the suffix 'InLedger', it is a single transaction rather than a cross-chain transaction.
     * @param srcPoolId The ID of the source pool.
     * @param dstPoolId The ID of the destination pool.
     * @param amountLP The amount of LP tokens to burn.
     * @param minAmountLD The minimum amount of tokens to withdraw in LD units.
     * @param to The address to receive the withdrawn tokens.
     */
    function withdrawRemoteInLedger(
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLP,
        uint256 minAmountLD,
        address to
    ) external;
}

/**
 * @title IBridgeEnhancedRouter
 * @dev Interface that contains the enhanced functions of the Bridge service.
 */
interface IBridgeEnhancedRouter is IBridgeStandardRouter {
    /**
     * @dev Sends credit to the destination pool from the source pool.
     * Initiates cross-chain transactions. For a detailed flow, refer to IPool.
     * @param srcChannel The channel for identifying the destination chain.
     * @param srcPoolId The ID of the source pool.
     * @param dstPoolId The ID of the destination pool.
     * @param refundTo The address to refund the remaining native asset.
     */
    function sendCredit(
        string calldata srcChannel,
        uint256 srcPoolId,
        uint256 dstPoolId,
        address payable refundTo
    ) external payable;

    /**
     * @dev Sends credit to the destination pool from the source pool.
     * If it has the suffix 'InLedger', it is a single transaction rather than a cross-chain transaction.
     * @param srcPoolId The ID of the source pool.
     * @param dstPoolId The ID of the destination pool.
     */
    function sendCreditInLedger(uint256 srcPoolId, uint256 dstPoolId) external;
}
