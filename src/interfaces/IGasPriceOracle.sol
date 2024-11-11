// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface IGasPriceOracle {
    event PriceUpdated(uint256 indexed chainId, uint256 price);

    function updatePrice(uint256 chainId, uint256 price) external;

    function getPrice(uint256 chainId) external view returns (uint256);
}
