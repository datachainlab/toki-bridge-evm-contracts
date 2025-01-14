// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// subset of Chainlink's AggregatorV3Interface
interface IChainlinkPriceFeed {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
