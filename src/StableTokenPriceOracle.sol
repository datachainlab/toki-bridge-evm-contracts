// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/ITokiErrors.sol";
import "./interfaces/IChainlinkPriceFeed.sol";
import "./interfaces/IStableTokenPriceOracle.sol";

contract StableTokenPriceOracle is
    ITokiErrors,
    IStableTokenPriceOracle,
    AccessControl
{
    using Math for uint256;

    struct PriceFeedInfo {
        address priceFeedAddress;
        uint8 priceFeedDecimals;
        uint256 validityPeriodSeconds;
    }

    uint256 public constant DENOMINATOR = 1e18;
    uint256 public constant ONE_BPS = 1e14;
    uint256 public constant ONE_BPS_PRICE_CHANGE_THRESHOLD = 1 * ONE_BPS;
    uint256 public constant TEN_BPS_PRICE_CHANGE_THRESHOLD = 10 * ONE_BPS;

    mapping(uint256 => uint256) private _poolIdToCurrentPrice;
    mapping(uint256 => uint256) private _poolIdToBasePrice;
    mapping(uint256 => PriceFeedInfo) private _poolIdToPriceFeedInfo;
    uint256 public priceDriftThreshold = 10 * ONE_BPS;
    uint256 public priceDepegThreshold = 150 * ONE_BPS;

    /* ========== EVENTS ========== */
    event ValidityPeriodUpdated(
        uint256 indexed poolId,
        uint256 priceValidityPeriod
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ------------------ admin methods ------------------

    function setPriceDriftThreshold(
        uint256 priceDriftThreshold_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        priceDriftThreshold = priceDriftThreshold_;
        emit PriceDriftThresholdUpdated(priceDriftThreshold_);
    }

    function setPriceDepegThreshold(
        uint256 priceDepegThreshold_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        priceDepegThreshold = priceDepegThreshold_;
        emit PriceDepegThresholdUpdated(priceDepegThreshold_);
    }

    /**
     * Set a price feed and initial parameters for the given pool id.
     * - @param poolId target pool id
     * - @param basePrice base price
     * - @param priceFeedAddress address of PriceFeed contract.
     * - @param validityPeriodSeconds new validity period in seconds. Note that time is taken from block.timestamp and its value may be differed up to a protocol defined limit.
     */
    function setBasePriceAndFeedAddress(
        uint256 poolId,
        uint256 basePrice,
        address priceFeedAddress,
        uint256 validityPeriodSeconds
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (basePrice == 0) {
            revert TokiZeroValue("base price");
        }
        if (priceFeedAddress == address(0)) {
            revert TokiZeroAddress("priceFeedAddress");
        }
        IChainlinkPriceFeed priceFeed = IChainlinkPriceFeed(priceFeedAddress);
        uint8 decimals = priceFeed.decimals();

        _poolIdToBasePrice[poolId] = basePrice;
        _poolIdToPriceFeedInfo[poolId] = PriceFeedInfo(
            priceFeedAddress,
            decimals,
            validityPeriodSeconds
        );
        emit PoolStateUpdated(
            poolId,
            basePrice,
            priceFeedAddress,
            validityPeriodSeconds
        );
        updateCurrentPrice(poolId, false);
    }

    /**
     * Set validity period of price data in seconds for the given pool id.
     * - @param poolId target pool id
     * - @param validityPeriodSeconds new validity period in seconds. Note that time is taken from block.timestamp and its value may be differed up to a protocol defined limit.
     */
    function setValidityPeriodSeconds(
        uint256 poolId,
        uint256 validityPeriodSeconds
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _poolIdToPriceFeedInfo[poolId]
            .validityPeriodSeconds = validityPeriodSeconds;
        emit ValidityPeriodUpdated(poolId, validityPeriodSeconds);
    }

    function getCurrentPriceDeviationStatus(
        uint256 poolId
    ) external view returns (PriceDeviationStatus) {
        uint256 currentPrice = getCurrentPrice(poolId);
        uint256 basePrice = getBasePrice(poolId);
        return _getPriceDeviationStatus(currentPrice, basePrice);
    }

    function updateCurrentPrice(uint256 poolId, bool forceUpdate) public {
        (bool need, uint256 latestPrice) = priceNeedsUpdate(poolId);
        if (need || forceUpdate) {
            _poolIdToCurrentPrice[poolId] = latestPrice;
            emit PriceUpdated(poolId, latestPrice);
        }
    }

    /**
     * Return the latest price information and whether an update is required or not.
     * Note that this function may revert when price data is expired.
     */
    function priceNeedsUpdate(
        uint256 poolId
    ) public view returns (bool, uint256) {
        uint256 currentPrice = _poolIdToCurrentPrice[poolId];
        uint256 basePrice = _poolIdToBasePrice[poolId];
        uint256 latestPrice = _getLatestPrice(poolId);
        return (
            _priceNeedsUpdate(latestPrice, currentPrice, basePrice),
            latestPrice
        );
    }

    function getCurrentPrice(uint256 poolId) public view returns (uint256) {
        uint256 currentPrice = _poolIdToCurrentPrice[poolId];
        return currentPrice;
    }

    function getBasePrice(uint256 poolId) public view returns (uint256) {
        uint256 basePrice = _poolIdToBasePrice[poolId];
        if (basePrice == 0) {
            revert TokiZeroValue("base price");
        }
        return basePrice;
    }

    function getPriceFeedAddress(uint256 poolId) public view returns (address) {
        PriceFeedInfo memory info = _getPriceFeedInfo(poolId);
        return info.priceFeedAddress;
    }

    function getPriceFeedDecimals(uint256 poolId) public view returns (uint8) {
        PriceFeedInfo memory info = _getPriceFeedInfo(poolId);
        return info.priceFeedDecimals;
    }

    function getCurrentPriceAndDecimals(
        uint256 poolId
    ) public view returns (uint256 price, uint8 decimals) {
        price = _poolIdToCurrentPrice[poolId];
        decimals = getPriceFeedDecimals(poolId);
    }

    function getValidityPeriod(uint256 poolId) public view returns (uint256) {
        PriceFeedInfo memory info = _getPriceFeedInfo(poolId);
        return info.validityPeriodSeconds;
    }

    function _priceNeedsUpdate(
        uint256 newPrice,
        uint256 currentPrice,
        uint256 basePrice
    ) internal view returns (bool) {
        PriceDeviationStatus currentDeviationState = _getPriceDeviationStatus(
            currentPrice,
            basePrice
        );
        PriceDeviationStatus newDeviationState = _getPriceDeviationStatus(
            newPrice,
            basePrice
        );
        if (currentDeviationState != newDeviationState) {
            return true;
        }
        if (currentPrice == 0 && newPrice > 0) {
            return true;
        }
        uint256 diff = (_abs(newPrice, currentPrice) * DENOMINATOR) /
            currentPrice;
        uint256 threshold = newDeviationState == PriceDeviationStatus.Drift
            ? ONE_BPS_PRICE_CHANGE_THRESHOLD
            : TEN_BPS_PRICE_CHANGE_THRESHOLD;
        return diff >= threshold;
    }

    function _getPriceFeedInfo(
        uint256 poolId
    ) internal view returns (PriceFeedInfo memory) {
        PriceFeedInfo memory info = _poolIdToPriceFeedInfo[poolId];
        if (info.priceFeedAddress == address(0)) {
            revert TokiZeroAddress("priceFeedAddress");
        }
        return info;
    }

    /// @dev Returns the latest price of the pool.
    /// If the latest price is greater than base price, then return base price.
    /// @param poolId The pool id.
    function _getLatestPrice(uint256 poolId) internal view returns (uint256) {
        PriceFeedInfo memory info = _getPriceFeedInfo(poolId);
        uint256 basePrice = getBasePrice(poolId);
        // if latestPrice is greater than basePrice, then return basePrice
        IChainlinkPriceFeed priceFeed = IChainlinkPriceFeed(
            info.priceFeedAddress
        );

        (
            uint80 _roundId, // solhint-disable-line no-unused-vars
            int256 latestPrice,
            uint256 _startedAt, // solhint-disable-line no-unused-vars
            uint256 updatedAt,
            uint80 _answeredInRound // solhint-disable-line no-unused-vars
        ) = priceFeed.latestRoundData();
        if (latestPrice <= 0) {
            revert TokiPriceIsNotPositive(latestPrice);
        }
        // slither-disable-next-line timestamp
        uint256 pastUpdated = (updatedAt < block.timestamp)
            ? block.timestamp - updatedAt
            : 0;
        if (info.validityPeriodSeconds < pastUpdated) {
            revert TokiPriceIsExpired(updatedAt);
        }
        return Math.min(uint256(latestPrice), basePrice);
    }

    function _getPriceDeviationStatus(
        uint256 price,
        uint256 basePrice
    ) internal view returns (PriceDeviationStatus) {
        if (price >= basePrice) {
            return PriceDeviationStatus.Normal;
        }

        uint256 diff;
        diff = ((basePrice - price) * DENOMINATOR) / basePrice;

        if (diff <= priceDriftThreshold) {
            return PriceDeviationStatus.Normal;
        } else if (diff <= priceDepegThreshold) {
            return PriceDeviationStatus.Drift;
        } else {
            return PriceDeviationStatus.Depeg;
        }
    }

    function _abs(uint256 x, uint256 y) internal pure returns (uint256) {
        if (x > y) {
            return x - y;
        } else {
            return y - x;
        }
    }
}
