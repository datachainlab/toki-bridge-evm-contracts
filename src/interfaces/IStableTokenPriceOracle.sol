// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface IStableTokenPriceOracle {
    enum PriceDeviationStatus {
        Normal,
        Drift,
        Depeg
    }

    event PriceUpdated(uint256 indexed poolId, uint256 price);

    event PriceDriftThresholdUpdated(uint256 priceDriftThreshold);

    event PriceDepegThresholdUpdated(uint256 priceDepegThreshold);

    event PoolStateUpdated(
        uint256 indexed poolId,
        uint256 basePrice,
        address priceFeedAddress
    );

    function updateCurrentPrice(uint256 poolId, bool forceUpdate) external;

    function priceNeedsUpdate(
        uint256 poolId
    ) external view returns (bool, uint256 latestPrice);

    function getCurrentPrice(uint256 poolId) external view returns (uint256);

    function getBasePrice(uint256 poolId) external view returns (uint256);

    function getCurrentPriceDeviationStatus(
        uint256 poolId
    ) external view returns (PriceDeviationStatus);

    function getPriceFeedAddress(
        uint256 poolId
    ) external view returns (address);

    function getPriceFeedDecimals(uint256 poolId) external view returns (uint8);

    function getCurrentPriceAndDecimals(
        uint256 poolId
    ) external view returns (uint256, uint8);
}
