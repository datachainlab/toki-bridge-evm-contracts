// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "./ITransferPoolFeeCalculator.sol";
import "./IDecimalConvertible.sol";
import "./IStaticFlowRateLimiter.sol";

/**
 * @title IPool
 * @dev Interface for the Pool contract. Represents the liquidity pool, implemented using a mechanism called the Delta Algorithm.
 * The Delta Algorithm allows for efficient cross-chain transactions and liquidity management.
 * When a function that could unbalance pools is called, such as minting liquidity, transferring tokens, and withdrawing liquidity,
 * delta calculation can be triggered. It can also be forcefully triggered using callDelta.
 * Refer to the white paper for more details on the Delta Algorithm: https://www.dropbox.com/s/gf3606jedromp61/Delta-Solving.The.Bridging-Trilemma.pdf?dl=0
 *
 * IPool serves as an liquidity pool contract which mints and burns ERC20 LP tokens when liquidity is added and removed from the pool.
 * A pool ID is assigned to each pool contract, which is shared between chains.
 * Majority of the cross-chain and liquidity related functions will be called by the Bridge.
 *
 *
 * Some functions in the Pool execute cross-chain transactions.
 * In cross-chain transactions, it's important to understand the context in which the function is executed and the perspective from which it is viewed.
 * The following terms are related to cross-chain transactions:
 * - Local pool: The pool where the function is being executed.
 * - Peer pool: The pool that is connected to the local pool.
 * - Initiator: The pool that initiates the cross-chain transaction.
 * - Counterparty: The pool that receives the cross-chain transaction.
 * Local pool and Peer pool represent a first-person view, whereas Initiator and Counterparty represent an objective view.
 *
 * The Pool uses two types of units:
 * - GD (Global Decimals): Lowest common decimals units used across the unified liquidity pool. GD can not be greater than LD.
 * - LD (Local Decimals): Decimal units specific to a particular asset token.
 *
 * The Pool uses two types of tokens:
 * - Liquidity provider token (LP token): This token represents the share of liquidity provided by users and is in GD units.
 * - Asset token: This token represents the actual token associated with the Pool, such as USDC or USDT.
 *   When simply referred to as 'token' it means the asset token.
 *
 */
interface IPool is IDecimalConvertible, IStaticFlowRateLimiter {
    /**
     * @dev Struct for the peer pool.
     * In the Delta Algorithm, there is a pool for each token, and these are referred to as a unified liquidity pool.
     * Within the unified liquidity pool, each pool is connected to multiple peer pools. Each pool refers to other connected pools as peer pools.
     * For example, the USDC on ETH pool may connect to peer pools like the USDT on ETH pool or the USDC on BSC pool, among others.
     * @param chainId The chain ID of the peer pool.
     * @param id The ID of the peer pool that is unique within the chain.
     * @param weight The weight that determines the allocation amount of liquidity.
     * The larger the weight, the more balance is allocated.
     * @param balance The balance available for transfer to the peer pool in GD units.
     * @param targetBalance The target balance, representing the ideal balance in GD units.
     * If the balance is less than the targetBalance, an additional eqFee will be charged.
     * @param lastKnownBalance The last known balance of the peer pool in GD units.
     * Unlike balance, it represents the amount that can be transferred from the peer pool to this pool.
     * @param credits The amount of tokens in GD units that can be transferred to the peer pool next time,
     * reducing the cost of cross-chain transactions.
     * @param ready Indicates if the peer pool is ready for transfer.
     */
    struct PeerPoolInfo {
        uint256 chainId;
        uint256 id;
        uint256 weight;
        uint256 balance;
        uint256 targetBalance;
        uint256 lastKnownBalance;
        uint256 credits;
        bool ready;
    }

    /**
     * @dev Struct for the credit information.
     * @param credits The amount of tokens in GD units that can be transferred to the peer pool next time.
     * @param targetBalance The target balance in GD units.
     */
    struct CreditInfo {
        uint256 credits;
        uint256 targetBalance;
    }

    /**
     * @dev Emitted by transfer.
     * @param peerChainId The chain ID of the peer pool.
     * @param peerPoolId The ID of the peer pool.
     * @param from The address from which the tokens are transferred.
     * @param amountGD The amount of tokens transferred in GD units.
     * @param eqReward The equilibrium reward for the transfer.
     * @param eqFee The equilibrium fee for the transfer.
     * @param protocolFee The protocol fee for the transfer.
     * @param lpFee The liquidity provider fee for the transfer.
     */
    event Transfer(
        uint256 peerChainId,
        uint256 peerPoolId,
        address from,
        uint256 amountGD,
        uint256 eqReward,
        uint256 eqFee,
        uint256 protocolFee,
        uint256 lpFee
    );

    /**
     * @dev Emitted when tokens are received.
     * @param to The address that receives the tokens.
     * @param amountGD The amount of tokens received in GD units.
     * @param protocolFee The protocol fee for the transfer.
     * @param eqFee The equilibrium fee for the transfer.
     */
    event Recv(
        address to,
        uint256 amountGD,
        uint256 protocolFee,
        uint256 eqFee
    );

    /**
     * @dev Emitted by withdrawRemote.
     * @param peerChainId The chain ID of the peer pool.
     * @param peerPoolId The ID of the peer pool.
     * @param from The address from which the tokens are withdrawn.
     * @param amountLP The amount of LP tokens withdrawn in GD units.
     * @param amountLD The amount of asset tokens withdrawn in LD units.
     */
    event WithdrawRemote(
        uint256 peerChainId,
        uint256 peerPoolId,
        address from,
        uint256 amountLP,
        uint256 amountLD
    );

    /**
     * @dev Emitted by withdrawLocal.
     *
     * @param peerChainId The chain ID of the peer pool.
     * @param peerPoolId The ID of the peer pool.
     * @param from The address from which the tokens are withdrawn.
     * @param amountLP The amount of LP tokens withdrawn in GD units.
     * @param amountGD The amount of asset tokens withdrawn in GD units.
     * @param to The address that receives the tokens.
     */
    event WithdrawLocal(
        uint256 peerChainId,
        uint256 peerPoolId,
        address from,
        uint256 amountLP,
        uint256 amountGD,
        bytes to
    );

    /**
     * @dev Emitted by withdrawCheck.
     * @param peerChainId The chain ID of the peer pool.
     * @param peerPoolId The ID of the peer pool.
     * @param amountLP The amount of LP tokens withdrawn in GD units.
     * @param amountGD The amount of asset tokens withdrawn in GD units.
     */
    event WithdrawCheck(
        uint256 peerChainId,
        uint256 peerPoolId,
        uint256 amountLP,
        uint256 amountGD
    );

    /**
     * @dev Emitted by withdrawConfirm.
     * @param peerChainId The chain ID of the peer pool.
     * @param peerPoolId The ID of the peer pool.
     * @param to The address that receives the tokens.
     * @param amountGD The amount of tokens withdrawn in GD units.
     * @param amountMintGD The amount of tokens minted in GD units.
     */
    event WithdrawConfirm(
        uint256 peerChainId,
        uint256 peerPoolId,
        address to,
        uint256 amountGD,
        uint256 amountMintGD
    );

    /**
     * @dev Emitted by sendCredit.
     * @param peerPoolId The ID of the peer pool.
     * @param credits The amount of tokens in GD units that can be transferred to the peer pool next time.
     * @param targetBalance The target balance in GD units.
     */
    event SendCredit(
        uint256 peerPoolId,
        uint256 credits,
        uint256 targetBalance
    );

    /**
     * @dev Emitted by updateCredit.
     * @param peerChainId The chain ID of the peer pool.
     * @param peerPoolId The ID of the peer pool.
     * @param credits The amount of tokens in GD units that can be transferred to the peer pool next time.
     * @param targetBalance The target balance in GD units.
     */
    event UpdateCredit(
        uint256 peerChainId,
        uint256 peerPoolId,
        uint256 credits,
        uint256 targetBalance
    );

    /**
     * @dev Emitted by withdrawInstant.
     * @param from The address from which the tokens are withdrawn.
     * @param amountLP The amount of LP tokens withdrawn in GD units.
     * @param amountGD The amount of asset tokens withdrawn in GD units.
     * @param to The address that receives the tokens.
     */
    event WithdrawInstant(
        address from,
        uint256 amountLP,
        uint256 amountGD,
        address to
    );

    /**
     * @dev Emitted when LP tokens are minted.
     * @param to The address to which the tokens are minted.
     * @param amountLP The amount of LP tokens minted in GD units.
     * @param amountGD The amount of asset tokens minted in GD units.
     */
    event Mint(address to, uint256 amountLP, uint256 amountGD);

    /**
     * @dev Emitted when LP tokens are burned.
     * @param from The address from which the tokens are burned.
     * @param amountLP The amount of LP tokens burned in GD units.
     * @param amountGD The amount of asset tokens burned in GD units.
     */
    event Burn(address from, uint256 amountLP, uint256 amountGD);

    // ============= for admin functions =================

    /**
     * @dev Emitted by setTransferStop.
     * @param stopTransfer The stop transfer status.
     */
    event UpdateStopTransfer(bool stopTransfer);

    /**
     * @dev Emitted when a peer pool is updated.
     * @param peerChainId The chain ID of the peer pool.
     * @param peerPoolId The ID of the peer pool.
     * @param weight The weight that determines the allocation amount of liquidity.
     */
    event PeerPoolInfoUpdate(
        uint256 peerChainId,
        uint256 peerPoolId,
        uint256 weight
    );

    /**
     * @dev Emitted by setDeltaParam.
     * @param batched Indicates if the delta updates are batched. If true, the updates are processed in batch mode.
     * @param swapDeltaBP The basis points for the swap delta.
     * @param lpDeltaBP The basis points for the liquidity provider delta.
     * @param defaultSwapMode The default mode for swaps.
     * @param defaultLPMode The default mode for LP tokens.
     */
    event UpdateDeltaParam(
        bool batched,
        uint256 swapDeltaBP,
        uint256 lpDeltaBP,
        bool defaultSwapMode,
        bool defaultLPMode
    );

    /**
     * @dev Emitted by drawFee.
     * @param to The address to which the fee is transferred.
     * @param amountLD The amount of the fee drawn in LD units.
     */
    event DrawFee(address to, uint256 amountLD);

    /**
     * @dev Emitted when the maximum total deposits are set.
     * @param maxTotalDepositsLD The maximum total deposits allowed in LD units.
     */
    event SetMaxTotalDeposits(uint256 maxTotalDepositsLD);

    /**
     * @dev Mints LP tokens in exchange for depositing assert tokens.
     * Note that asset tokens are transferred by the Bridge contract, not by the Pool contract.
     * @param to The address to which the tokens are minted.
     * @param amountLD The amount of asset tokens to mint in LD units.
     * @return amountGD The amount of asset tokens minted in GD units.
     */
    function mint(
        address to,
        uint256 amountLD
    ) external returns (uint256 amountGD);

    /**
     * @dev Transfers tokens to a peer pool.
     * Note that the Bridge contract performs the transfer token. The Pool only performs delta calculations and updates its internal state.
     *
     * [Flow of a cross-chain transaction]
     * 1. transfer on the initiator <- this function
     * 2. recv on the counterparty
     *
     * @param peerChainId The chain ID of the peer pool.
     * @param peerPoolId The ID of the peer pool.
     * @param from The address from which the  tokens are transferred.
     * @param amountLD The amount of  tokens to transfer in LD units.
     * @param minAmountLD The minimum amount of  tokens to transfer in LD units.
     * Slippage check is done to ensure that the amount after adding the reward and
     * subtracting the fee is greater than or equal to the minimum amount in GD units.
     * @param newLiquidity Indicates if the transfer is new liquidity.
     * @return feeInfo The fee information for the transfer.
     */
    function transfer(
        uint256 peerChainId,
        uint256 peerPoolId,
        address from,
        uint256 amountLD,
        uint256 minAmountLD,
        bool newLiquidity
    ) external returns (ITransferPoolFeeCalculator.FeeInfo memory);

    /**
     * @dev Receives tokens from the peer pool.
     * The delta calculation is performed, and the peer pool info of the local pool is updated.
     *
     * [Flow of a cross-chain transaction]
     * 1. transfer on the initiator
     * 2. recv on the counterparty <- this function
     *
     * 1. withdrawRemote on the initiator
     * 2. recv on the counterparty <- this function
     *
     * @param peerChainId The chain id of the peer pool
     * @param peerPoolId The pool id of the peer pool
     * @param to The address to receive the tokens
     * @param feeInfo The fee information
     * @param updateDelta Whether to update the delta like totalLiquidity
     * @return amountLD The amount of tokens received, including rewards
     * @return isTransferred Whether the tokens are transferred
     */
    function recv(
        uint256 peerChainId,
        uint256 peerPoolId,
        address to,
        ITransferPoolFeeCalculator.FeeInfo memory feeInfo,
        bool updateDelta
    ) external returns (uint256 amountLD, bool isTransferred);

    /**
     * @dev Withdraws asset tokens from the peer pool, and in exchange, burn LP tokens locally.
     *
     * [Flow of a cross-chain transaction]
     * 1. withdrawRemote on the initiator <- this function
     * 2. recv on the counterparty
     *
     * @param peerChainId The chain ID of the peer pool.
     * @param peerPoolId The ID of the peer pool.
     * @param from The address from which the tokens are withdrawn.
     * @param amount The amount of LP tokens.
     */
    function withdrawRemote(
        uint256 peerChainId,
        uint256 peerPoolId,
        address from,
        uint256 amount
    ) external;

    /**
     * @dev Withdraws tokens from a peer pool locally.
     * withdrawLocal burns local LP tokens and uses the balance that the peer pool can send to the local pool to withdraw tokens in the local pool.
     *
     * [Flow of a cross-chain transaction]
     * 1. withdrawLocal on the initiator <- this function
     * 2. withdrawCheck on the counterparty
     * 3. withdrawConfirm on the initiator
     *
     * @param peerChainId The chain ID of the peer pool.
     * @param peerPoolId The ID of the peer pool.
     * @param from The address from which the tokens are withdrawn.
     * @param amount The amount of LP tokens.
     * @param to The address to receive the tokens.
     * @return amountGD The amount of asset tokens withdrawn in GD units.
     */
    function withdrawLocal(
        uint256 peerChainId,
        uint256 peerPoolId,
        address from,
        uint256 amount,
        bytes calldata to
    ) external returns (uint256 amountGD);

    /**
     * @dev This is the second step in withdrawLocal which executed on the peer pool for withdrawLocal.
     * It checks the balance, and if the balance is insufficient, it transfers tokens up to the balance.
     *
     * [Flow of a cross-chain transaction]
     * 1. withdrawLocal on the initiator
     * 2. withdrawCheck on the counterparty <- this function
     * 3. withdrawConfirm on the initiator
     *
     * @param peerChainId The chain ID of the peer pool (the initiator pool).
     * @param peerPoolId The ID of the peer pool (the initiator pool).
     * @param amountGD The amount of tokens to withdraw in GD units.
     */
    function withdrawCheck(
        uint256 peerChainId,
        uint256 peerPoolId,
        uint256 amountGD
    ) external returns (uint256 amountSwap, uint256 amountMint);

    /**
     * @dev This is the final step in withdrawLocal which executed on the local pool for withdrawLocal.
     * If the full amount cannot be withdrawn, mint LP tokens to refund the excess burned tokens.
     *
     * [Flow of a cross-chain transaction]
     * 1. withdrawLocal on the initiator
     * 2. withdrawCheck on the counterparty
     * 3. withdrawConfirm on the initiator <- this function
     *
     * @param peerChainId The chain ID of the peer pool (the counterparty pool).
     * @param peerPoolId The ID of the peer pool (the counterparty pool).
     * @param to The address to receive the tokens
     * @param amountGD The amount of tokens to withdraw, capped by `peerPoolInfo.balance`.
     * @param amountToMintGD The amount of tokens to mint when `peerPoolInfo.balance` is insufficient
     * @param updateDelta Whether to update the delta like `totalLiquidity`
     * @return isTransferred Whether the tokens are transferred
     */
    function withdrawConfirm(
        uint256 peerChainId,
        uint256 peerPoolId,
        address to,
        uint256 amountGD,
        uint256 amountToMintGD,
        bool updateDelta
    ) external returns (bool isTransferred);

    /**
     * @dev Sends credit to a peer pool.
     * Credits aims to reduce the processing costs of cross-chain transactions. It can be transferred to the peer pool next time.
     * Updates the local Peer pool info and generates a IBC packet.
     *
     * [Flow of a cross-chain transaction]
     * 1. sendCredit on the initiator <- this function
     * 2. updateCredit on the counterparty
     *
     * @param peerChainId The chain ID of the peer pool.
     * @param peerPoolId The ID of the peer pool.
     * @return creditInfo The credit information.
     */
    function sendCredit(
        uint256 peerChainId,
        uint256 peerPoolId
    ) external returns (CreditInfo memory);

    /**
     * @dev This is the 2nd step in sendCredit which executed on the peer pool for sendCredit.
     * Updates the peer pool info of the local pool (the counterparty pool) based on the received credit.
     *
     * [Flow of a cross-chain transaction]
     * 1. sendCredit on the initiator
     * 2. updateCredit on the counterparty <- this function
     *
     * @param peerChainId The chain ID of the peer pool (the initiator pool).
     * @param peerPoolId The ID of the peer pool (the initiator pool).
     * @param creditInfo The credit information.
     */
    function updateCredit(
        uint256 peerChainId,
        uint256 peerPoolId,
        CreditInfo memory creditInfo
    ) external;

    /**
     * @dev Withdraws tokens instantly.
     * Instead of using a cross-chain transaction, withdraw instantly from deltaCredit.
     * If deltaCredit is insufficient, withdraw up to deltaCredit.
     * @param from The address from which the tokens are withdrawn.
     * @param amountLP The amount of LP tokens to withdraw in GD units.
     * @param to The address to receive the tokens.
     * @return amountGD The amount of tokens withdrawn in GD units.
     */
    function withdrawInstant(
        address from,
        uint256 amountLP,
        address to
    ) external returns (uint256 amountGD);

    /**
     * @dev Calculates the delta.
     * @param fullMode Indicates if the full mode should be used.
     * If true, even if each pool has an ideal balance, all deltaCredit will be consumed and proportionally distributed to each pool.
     */
    function callDelta(bool fullMode) external;

    /**
     * @dev Sets the transfer stop status.
     * @param transferStop If true, transfer operations are restricted. However, withdrawals are not restricted.
     */
    function setTransferStop(bool transferStop) external;

    /**
     * @dev Registers a peer pool.
     * @param peerChainId The chain ID of the peer pool.
     * @param peerPoolId The ID of the peer pool.
     * @param weight The weight of the peer pool.
     */
    function registerPeerPool(
        uint256 peerChainId,
        uint256 peerPoolId,
        uint256 weight
    ) external;

    /**
     * @dev Activates a peer pool.
     * @param peerChainId The chain ID of the peer pool.
     * @param peerPoolId The ID of the peer pool.
     */
    function activatePeerPool(uint256 peerChainId, uint256 peerPoolId) external;

    /**
     * @dev Sets the weight of a peer pool.
     * When the peer pool is activated, it becomes available for transfer.
     * @param peerChainId The chain ID of the peer pool.
     * @param peerPoolId The ID of the peer pool.
     * @param weight The weight of the peer pool.
     */
    function setPeerPoolWeight(
        uint256 peerChainId,
        uint256 peerPoolId,
        uint256 weight
    ) external;

    /**
     * @dev Sets the delta parameters.
     * @param batched Indicates if the delta updates are batched.
     * @param swapDeltaBP The basis points for the swap delta.
     * @param lpDeltaBP The basis points for the liquidity provider delta.
     * @param defaultSwapMode The default mode for swaps.
     * @param defaultLPMode The default mode for LP tokens.
     */
    function setDeltaParam(
        bool batched,
        uint256 swapDeltaBP,
        uint256 lpDeltaBP,
        bool defaultSwapMode,
        bool defaultLPMode
    ) external;

    /**
     * @dev Draws a fee from the pool.
     * @param to The address to receive the fee.
     */
    function drawFee(address to) external;

    // ============== for helper ===================

    /**
     * @dev Returns the total liquidity.
     * @return The total liquidity in GD units.
     */
    function totalLiquidity() external view returns (uint256);

    /**
     * @dev Returns the asset token address.
     * @return The asset token address.
     */
    function token() external view returns (address);

    /**
     * @dev Returns the equilibrium fee pool.
     * @return The equilibrium fee pool in GD units.
     */
    function eqFeePool() external view returns (uint256);

    /**
     * @dev Returns the peer pool information.
     * @param peerChainId The chain ID of the peer pool.
     * @param peerPoolId The ID of the peer pool.
     * @return The peer pool information.
     */
    function getPeerPoolInfo(
        uint256 peerChainId,
        uint256 peerPoolId
    ) external view returns (PeerPoolInfo memory);

    /**
     * @dev Calculates the fee for a transfer.
     * @param peerChainId The chain ID of the peer pool.
     * @param peerPoolId The ID of the peer pool.
     * @param from The address from which the tokens are transferred.
     * @param amountLD The amount of tokens to transfer in LD units.
     * @return feeInfo The fee information.
     */
    function calcFee(
        uint256 peerChainId,
        uint256 peerPoolId,
        address from,
        uint256 amountLD
    ) external view returns (ITransferPoolFeeCalculator.FeeInfo memory);

    /**
     * @dev Converts LP tokens in GD units to asset tokens in LD units.
     * @param amountLP The amount of LP tokens in GD units.
     * @return The amount of asset tokens in LD units.
     */
    // solhint-disable-next-line func-name-mixedcase
    function LPToLD(uint256 amountLP) external view returns (uint256);
}
