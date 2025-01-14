// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IIBCModule} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/26-router/IIBCModule.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import "./IAppVersion.sol";
import "./IBridgeRouter.sol";
import "./IBridgeManager.sol";
import "./IBridgeQuerier.sol";
import {IReceiveRetryable} from "./IReceiveRetryable.sol";

/**
 * @title IBridge
 * @dev Interface for the bridge contract that integrates with IBC and is useful for interacting with the bridge contract.
 * IBridge is the main interface which users wanting to add liquidity to a pool, or to bridge tokens from one chain to another, will interact with.
 * For flows that require cross-chain transactions, the IBC handler will also be calling this interface on the destination chain.
 */
interface IBridge is
    IIBCModule,
    IBridgeEnhancedRouter,
    IBridgeManager,
    IAppVersion,
    IBridgeQuerier,
    IReceiveRetryable,
    IAccessControl
{
    /**
     * @dev Calculates the delta for a given source pool.
     * @param srcPoolId The ID of the source pool.
     * @param fullMode Indicates if the full mode should be used.
     */
    function callDelta(uint256 srcPoolId, bool fullMode) external;

    /**
     * @dev Returns the chain ID for a given channel info.
     * @param localChannel The local channel for the counterparty chain.
     * @param checksAppVersion Indicates if the app version should be checked with channel version.
     * @return counterpartyChainId The counterparty chain ID.
     */
    function getChainId(
        string memory localChannel,
        bool checksAppVersion
    ) external view returns (uint256 counterpartyChainId);

    /**
     * @dev Returns the pool for a given pool ID.
     * @param localPoolId The ID of the local pool.
     * @return The local pool.
     */
    function getPool(uint256 localPoolId) external view returns (IPool);

    /**
     * @dev Returns the IBCHandler address.
     * IBCHandler provides an interface for enabling cross-chain transactions using IBC.
     * @return The IBCHandler address.
     */
    function ibcAddress() external view returns (address);
}
