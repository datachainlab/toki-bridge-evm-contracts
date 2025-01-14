// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../PoolRepository.sol";
import "../library/IBCUtils.sol";

/**
 * @title IBridgeManager
 * @dev Interface that contains the management functions of the Bridge service.
 */
interface IBridgeManager {
    /**
     * @dev Emitted by setDefaultFallback.
     * @param defaultFallback The address of the bridge fallback.
     */
    event SetDefaultFallback(address defaultFallback);

    /**
     * @dev Emitted by setChannelUpgradeFallback.
     * @param channelUpgradeFallback The address of the channel upgrade fallback.
     */
    event SetChannelUpgradeFallback(address channelUpgradeFallback);

    /**
     * @dev Emitted by setChainLookup.
     * @param localChannel The local channel for the counterparty chain
     * @param counterpartyChainId The counterparty chain ID.
     */
    event SetChainLookup(string localChannel, uint256 counterpartyChainId);

    /**
     * @dev Emitted by setICS04SendPacket.
     * @param ics04SendPacket The address of the ICS04SendPacket.
     */
    event SetICS04SendPacket(address ics04SendPacket);

    /**
     * @dev Emitted by setRefuelSrcCap.
     * @param chainId The chain ID.
     * @param cap The refuel source cap.
     */
    event SetRefuelSrcCap(uint256 chainId, uint256 cap);

    /**
     * @dev Emitted by setRefuelDstCap.
     * @param cap The refuel destination cap.
     */
    event SetRefuelDstCap(uint256 cap);

    /**
     * @dev Emitted by setRelayerFeeCalculator.
     * @param relayerFeeCalculator The address of the relayer fee calculator.
     */
    event SetRelayerFeeCalculator(address relayerFeeCalculator);

    /**
     * @dev Emitted by setPoolRepository.
     * @param poolRepository The address of the pool repository.
     */
    event SetPoolRepository(address poolRepository);

    /**
     * @dev Emitted by setPremiumBPS.
     * @param chainId The chain ID.
     * @param riskPremiumBPS The risk premium basis points.
     */
    event SetPremiumBPS(uint256 chainId, uint256 riskPremiumBPS);

    /**
     * @dev Emitted by setTokenEscrow.
     * @param tokenEscrow The address of the token escrow.
     */
    event SetTokenEscrow(address tokenEscrow);

    /**
     * @dev Emitted by setTokenPriceOracle.
     * @param tokenPriceOracle The address of the token price oracle.
     */
    event SetTokenPriceOracle(address tokenPriceOracle);

    /**
     * @dev Emitted by setRetryBlocks.
     * @param receiveRetryBlocks  The retry period blocks for receive operations.
     * @param withdrawRetryBlocks The retry period blocks for withdraw operations.
     * @param externalRetryBlocks The retry period blocks for external operations.
     */
    event SetRetryBlocks(
        uint64 receiveRetryBlocks,
        uint64 withdrawRetryBlocks,
        uint64 externalRetryBlocks
    );

    /**
     * @dev Emitted by refill.
     * @param amount The amount of native asset.
     */
    event Refill(uint256 amount);

    /**
     * @dev Emitted by draw.
     * @param amount The amount of native asset.
     * @param to The address to draw to.
     */
    event Draw(uint256 amount, address to);

    /**
     * @dev Sets the address of the bridge default fallback.
     * @param defaultFallback The address of the bridge default fallback.
     */
    function setDefaultFallback(address defaultFallback) external;

    /**
     * @dev Sets the address of the channel upgrade fallback.
     * @param channelUpgradeFallback The address of the channel upgrade fallback.
     */
    function setChannelUpgradeFallback(address channelUpgradeFallback) external;

    /**
     * @dev Sets the channel information and chain ID.
     * @param localChannel The channel information for the counterparty chain.
     * @param counterpartyChainId The counterparty chain ID.
     */
    function setChainLookup(
        string calldata localChannel,
        uint256 counterpartyChainId
    ) external;

    /**
     * @dev Sets the address of the ICS04SendPacket.
     * @param ics04SendPacket The address of the ICS04SendPacket.
     */
    function setICS04SendPacket(address ics04SendPacket) external;

    /**
     * @dev Sets the address of the pool repository.
     * @param poolRepository The address of the pool repository.
     */
    function setPoolRepository(address poolRepository) external;

    /**
     * @dev Sets the risk premium basis points.
     * @param localChannel The channel for the counterparty chain.
     * @param riskPremiumBPS The risk premium basis points for the counterparty chain.
     */
    function setPremiumBPS(
        string calldata localChannel,
        uint256 riskPremiumBPS
    ) external;

    /**
     * @dev Sets the refuel source cap.
     * @param localChannel The local channel information for the counterparty chain.
     * @param cap The refuel source cap for the counterparty chain.
     */
    function setRefuelSrcCap(
        string calldata localChannel,
        uint256 cap
    ) external;

    /**
     * @dev Sets the refuel destination cap.
     * @param cap The refuel destination cap.
     */
    function setRefuelDstCap(uint256 cap) external;

    /**
     * @dev Sets the address of the relayer fee calculator.
     * @param relayerFeeCalculator The address of the relayer fee calculator.
     */
    function setRelayerFeeCalculator(address relayerFeeCalculator) external;

    /**
     * @dev Sets the address of the token escrow.
     * @param tokenEscrow The address of the token escrow.
     */
    function setTokenEscrow(address tokenEscrow) external;

    /**
     * @dev Sets the address of the token price oracle.
     * @param tokenPriceOracle The address of the token price oracle.
     */
    function setTokenPriceOracle(address tokenPriceOracle) external;

    /**
     * @dev Sets the retry period blocks for receive, withdraw, and external operations.
     * @param receiveBlocks  The retry period blocks for receive operations.
     * @param withdrawBlocks The retry period blocks for withdraw operations.
     * @param externalBlocks The retry period blocks for external operations.
     */
    function setRetryBlocks(
        uint64 receiveBlocks,
        uint64 withdrawBlocks,
        uint64 externalBlocks
    ) external;

    /**
     * @dev transfer native token to Bridge to work its service.
     */
    function refill() external payable;

    /**
     * @dev Draws the native asset.
     * @param amount The amount of native asset.
     * @param to The address to draw to.
     */
    function draw(uint256 amount, address to) external;
}
