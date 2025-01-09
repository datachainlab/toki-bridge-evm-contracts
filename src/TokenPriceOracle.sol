// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/ITokiErrors.sol";
import "./interfaces/IChainlinkPriceFeed.sol";
import "./interfaces/ITokenPriceOracle.sol";

contract TokenPriceOracle is ITokiErrors, AccessControl, ITokenPriceOracle {
    struct PriceFeedInfo {
        address priceFeedAddress;
        uint8 priceFeedDecimals;
    }

    // use chainId as tokenId for native token
    mapping(uint256 => uint256) private _tokenIdToPrice;
    mapping(uint256 => PriceFeedInfo) private _tokenIdToPriceFeedInfo;

    uint256 public priceChangeThresholdE18;

    /* ========== EVENTS ========== */
    event SetPriceChangeThreshold(uint256 priceChangeThreshold);

    event SetPriceFeedAddress(uint256 tokenId, address priceFeedAddress);

    constructor(uint256 priceChangeThresholdE18_) {
        priceChangeThresholdE18 = priceChangeThresholdE18_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setPriceChangeThreshold(
        uint256 priceChangeThresholdE18_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        priceChangeThresholdE18 = priceChangeThresholdE18_;
        emit SetPriceChangeThreshold(priceChangeThresholdE18);
    }

    function setPriceFeedAddress(
        uint256 tokenId,
        address priceFeedAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (priceFeedAddress == address(0)) {
            revert TokiZeroAddress("priceFeedAddress");
        }

        IChainlinkPriceFeed priceFeed = IChainlinkPriceFeed(priceFeedAddress);
        uint8 decimals = priceFeed.decimals();

        _tokenIdToPriceFeedInfo[tokenId] = PriceFeedInfo(
            priceFeedAddress,
            decimals
        );
        updatePrice(tokenId, false);
        emit SetPriceFeedAddress(tokenId, priceFeedAddress);
    }

    function getPrice(uint256 tokenId) external view returns (uint256) {
        return _tokenIdToPrice[tokenId];
    }

    function tokenIdToki() external pure returns (uint256) {
        return 0x544F4B49544F4B49544F4B49544F4B49;
    }

    function updatePrice(uint256 tokenId, bool forceUpdate) public {
        (bool need, uint256 latestPrice) = needUpdate(tokenId);
        if (need || forceUpdate) {
            _tokenIdToPrice[tokenId] = latestPrice;
            emit PriceUpdated(tokenId, latestPrice);
        }
    }

    function needUpdate(uint256 tokenId) public view returns (bool, uint256) {
        uint256 currentPrice = _tokenIdToPrice[tokenId];
        uint256 latestPrice = getLatestPrice(tokenId);
        return (needUpdate(latestPrice, currentPrice), latestPrice);
    }

    function needUpdate(
        uint256 newPrice,
        uint256 currentPrice
    ) public view returns (bool) {
        return
            (currentPrice == 0) ||
            ((_abs(newPrice, currentPrice) * 1e18) / currentPrice >
                priceChangeThresholdE18);
    }

    function getLatestPrice(uint256 tokenId) public view returns (uint256) {
        address priceFeedAddress = getPriceFeedAddress(tokenId);
        IChainlinkPriceFeed priceFeed = IChainlinkPriceFeed(priceFeedAddress);

        (
            uint80 _roundId, // solhint-disable-line no-unused-vars
            int256 price,
            uint256 _startedAt, // solhint-disable-line no-unused-vars
            uint256 _updatedAt, // solhint-disable-line no-unused-vars
            uint80 _answeredInRound // solhint-disable-line no-unused-vars
        ) = priceFeed.latestRoundData();

        if (price <= 0) {
            revert TokiPriceIsNotPositive(price);
        }
        return uint256(price);
    }

    function getPriceFeedAddress(
        uint256 tokenId
    ) public view returns (address) {
        PriceFeedInfo memory info = _tokenIdToPriceFeedInfo[tokenId];
        if (info.priceFeedAddress == address(0)) {
            revert TokiZeroAddress("priceFeedAddress");
        }
        return info.priceFeedAddress;
    }

    function getPriceFeedDecimals(uint256 tokenId) public view returns (uint8) {
        PriceFeedInfo memory info = _tokenIdToPriceFeedInfo[tokenId];
        if (info.priceFeedAddress == address(0)) {
            revert TokiZeroAddress("priceFeedAddress");
        }
        return info.priceFeedDecimals;
    }

    function getPriceAndDecimals(
        uint256 tokenId
    ) public view returns (uint256 price, uint8 decimals) {
        decimals = getPriceFeedDecimals(tokenId);
        price = _tokenIdToPrice[tokenId];
    }

    function getLatestPriceAndDecimals(
        uint256 tokenId
    ) public view returns (uint256 price, uint8 decimals) {
        decimals = getPriceFeedDecimals(tokenId);
        price = getLatestPrice(tokenId);
    }

    function _abs(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}
