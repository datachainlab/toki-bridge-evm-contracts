// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../interfaces/IChainlinkPriceFeed.sol";

contract MockPriceFeed is IChainlinkPriceFeed {
    int256 public price;
    uint8 public immutable DECIMALS;

    constructor(int256 price_, uint8 decimals_) {
        DECIMALS = decimals_;
        price = price_;
    }

    function decimals() external view override returns (uint8) {
        return DECIMALS;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (uint80(0), price, uint256(0), uint256(0), uint80(0));
    }

    function setPrice(int256 price_) public {
        price = price_;
    }
}
