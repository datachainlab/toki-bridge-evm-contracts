// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface ITokenPriceOracle {
    event PriceUpdated(uint256 indexed tokenId, uint256 price);

    function updatePrice(uint256 tokenId, bool forceUpdate) external;

    function getPriceFeedDecimals(
        uint256 tokenId
    ) external view returns (uint8);

    function getPrice(uint256 tokenId) external view returns (uint256);

    function getPriceAndDecimals(
        uint256 tokenId
    ) external view returns (uint256, uint8);

    function getLatestPrice(uint256 tokenId) external view returns (uint256);

    function getLatestPriceAndDecimals(
        uint256 tokenId
    ) external view returns (uint256, uint8);

    function getPriceFeedAddress(
        uint256 tokenId
    ) external view returns (address);

    function tokenIdToki() external pure returns (uint256);
}
