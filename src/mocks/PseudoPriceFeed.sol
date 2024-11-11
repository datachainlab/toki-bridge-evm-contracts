// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../interfaces/IChainlinkPriceFeed.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PseudoPriceFeed is IChainlinkPriceFeed, Ownable {
    int256 public price;

    event PriceChanged(int256 newPrice);

    constructor(int256 price_) Ownable(msg.sender) {
        price = price_;
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

    function setPrice(int256 price_) public onlyOwner {
        price = price_;
        emit PriceChanged(price);
    }
}
