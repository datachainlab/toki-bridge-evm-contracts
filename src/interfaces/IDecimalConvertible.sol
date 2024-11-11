// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

/**
 * @title IDecimalConvertible
 * @dev Interface for converting decimals between global and local.
 * For more details on globalDecimals and localDecimals, refer to IPool.
 */
interface IDecimalConvertible {
    /**
     * @dev Returns the global decimals, which is the smallest decimal value among connected pools.
     * @return The global decimals.
     */
    function globalDecimals() external returns (uint8);

    /**
     * @dev Returns the local decimals for the token
     * @return The local decimals for the token.
     */
    function localDecimals() external returns (uint8);

    /**
     * @dev Returns the conversion rate for the token
     * @return The conversion rate for the token.
     */
    function convertRate() external returns (uint256);
}
