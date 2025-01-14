// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../library/IBCUtils.sol";
import "./IAppVersion.sol";
import "./IPoolRepository.sol";
import "./IRelayerFeeCalculator.sol";
import "../future/interfaces/ITokenEscrow.sol";
import "./ITokenPriceOracle.sol";

/**
 * @title IBridgeQuerier
 * @dev Interface that contains the query functions of the Bridge service.
 */
interface IBridgeQuerier {
    /**
     * @dev Calculates the source native amount for a given destination chain ID and destination native amount.
     * This calculation takes into account the risk premium.
     * @param dstChainId The destination chain ID.
     * @param dstNativeAmount The destination native amount.
     * @return The source native amount.
     */
    function calcSrcNativeAmount(
        uint256 dstChainId,
        uint256 dstNativeAmount
    ) external view returns (uint256);

    /**
     * @dev Returns the address of the bridge default fallback contract.
     * @return The address of the bridge default fallback contract.
     */
    function defaultFallback() external view returns (address);

    /**
     * @dev Returns the address of the bridge channel upgrade fallback contract.
     * @return The address of the bridge channel upgrade fallback contract.
     */
    function channelUpgradeFallback() external view returns (address);

    /**
     * @dev Returns the pool repository.
     * @return The pool repository.
     */
    function poolRepository() external view returns (IPoolRepository);

    /**
     * @dev Returns the risk premium for a given chain ID.
     * @param chainId The chain ID.
     * @return The risk premium.
     */
    function premiumBPS(uint256 chainId) external view returns (uint256);

    /**
     * @dev Returns the destination refuel cap.
     * @return The destination refuel cap.
     */
    function refuelDstCap() external view returns (uint256);

    /**
     * @dev Returns the source refuel cap for a given chain ID.
     * @param chainId The chain ID.
     * @return The source refuel cap.
     */
    function refuelSrcCap(uint256 chainId) external view returns (uint256);

    /**
     * @dev Returns the relayer fee calculator.
     * @return The relayer fee calculator.
     */
    function relayerFeeCalculator()
        external
        view
        returns (IRelayerFeeCalculator);

    /**
     * @dev Returns the revert receive data for a given chain ID and sequence.
     * The revert receive data includes lastValidHeight and appVersion, allowing the user to check the data's expiration.
     * @param chainId The chain ID.
     * @param sequence The sequence.
     * @return ABI-encoded revert receive data.
     * For decoding, the retry type must be identified. The retry type is included in the RevertReceive event.
     */
    function revertReceive(
        uint256 chainId,
        uint64 sequence
    ) external view returns (bytes memory);

    /**
     * @dev Returns the token escrow.
     * @return The token escrow.
     */
    function tokenEscrow() external view returns (ITokenEscrow);

    /**
     * @dev Returns the token price oracle.
     * @return The token price oracle.
     */
    function tokenPriceOracle() external view returns (ITokenPriceOracle);

    /**
     * @dev Returns the retry period blocks for receive operations.
     * @return The retry period blocks for receive operations.
     */
    function receiveRetryBlocks() external view returns (uint64);

    /**
     * @dev Returns the retry period blocks for withdraw operations.
     * @return The retry period blocks for withdraw operations.
     */
    function withdrawRetryBlocks() external view returns (uint64);

    /**
     * @dev Returns the retry period blocks for external operations.
     * @return The retry period blocks for external operations.
     */
    function externalRetryBlocks() external view returns (uint64);
}
