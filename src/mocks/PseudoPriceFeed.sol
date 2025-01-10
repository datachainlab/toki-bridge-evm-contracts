// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../interfaces/IChainlinkPriceFeed.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PseudoPriceFeed is IChainlinkPriceFeed, Ownable {
    int256 public price;
    uint8 public immutable DECIMALS;

    event PriceChanged(int256 newPrice);

    constructor(int256 price_, uint8 decimals_) Ownable(msg.sender) {
        price = price_;
        DECIMALS = decimals_;
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
        // slither-disable-next-line timestamp
        uint256 ts = (block.timestamp < 600)
            ? block.timestamp
            : block.timestamp - 600;
        return (uint80(0), price, ts, ts, uint80(0));
    }

    function setPrice(int256 price_) public onlyOwner {
        price = price_;
        emit PriceChanged(price);
    }
}
