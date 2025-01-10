// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "./interfaces/ITokiErrors.sol";
import "./interfaces/IStaticFlowRateLimiter.sol";

abstract contract StaticFlowRateLimiter is
    IStaticFlowRateLimiter,
    ITokiErrors,
    Initializable,
    AccessControlUpgradeable
{
    /// @custom:storage-location erc7201:toki.storage.StaticFlowRateLimiter
    struct StaticFlowRateLimiterStorage {
        uint256 _currentPeriodEnd; // The block height at which the current period ends.
        uint256 _currentPeriodAmount; // The amount of flow accumulated in the current period.
        // TODO: Replace to transient storage when we update evm version to cancun or later.
        uint256 _cancellableAmount; // The amount of flow that can be cancelled.
        bool _appliedLockPeriod; // The flag to lock the flow rate limiting.
    }

    // keccak256(abi.encode(uint256(keccak256("toki.storage.StaticFlowRateLimiter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STATIC_FLOW_RATE_LIMITER_LOCATION =
        0x0ee2d9de8392a8f17ff2bb7a24b72fd27e2cf4ac5cd7fd56e5bf7bdb439eb000;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable PERIOD; // The period over which the flow is accumulated.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable LOCK_PERIOD; // Rate limiting will be applied during LOCK_PERIOD after exceeding LIMIT.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable LIMIT; // The maximum flow limit within the period.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable THRESHOLD; // The threshold for accumulating flow.

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        uint256 period,
        uint256 lockPeriod,
        uint256 limit,
        uint256 threshold
    ) {
        PERIOD = period;
        LOCK_PERIOD = lockPeriod;
        LIMIT = limit;
        THRESHOLD = threshold;
        _disableInitializers();
    }

    function resetFlowRateLimit() public onlyRole(DEFAULT_ADMIN_ROLE) {
        StaticFlowRateLimiterStorage
            storage $ = _getStaticFlowRateLimiterStorage();
        _resetFlowRateLimit($);
    }

    function currentPeriodEnd() public view returns (uint256) {
        return _getStaticFlowRateLimiterStorage()._currentPeriodEnd;
    }

    function currentPeriodAmount() public view returns (uint256) {
        return _getStaticFlowRateLimiterStorage()._currentPeriodAmount;
    }

    function appliedLockPeriod() public view returns (bool) {
        return _getStaticFlowRateLimiterStorage()._appliedLockPeriod;
    }

    function _checkAndUpdateFlowRateLimit(
        uint256 amount
    ) internal returns (bool) {
        StaticFlowRateLimiterStorage
            storage $ = _getStaticFlowRateLimiterStorage();
        _updatePeriod();

        // Disallow transfers that exceed current rate limit
        if ($._currentPeriodAmount + amount > LIMIT) {
            $._cancellableAmount = 0;

            if (!$._appliedLockPeriod) {
                $._appliedLockPeriod = true;
                $._currentPeriodEnd += LOCK_PERIOD;
            }

            return false;
        }

        if (THRESHOLD < amount) {
            // solhint-disable-next-line no-inline-assembly
            $._cancellableAmount = amount;
            $._currentPeriodAmount += amount;
        } else {
            $._cancellableAmount = 0;
        }

        return true;
    }

    function _cancelFlowRateLimit() internal {
        StaticFlowRateLimiterStorage
            storage $ = _getStaticFlowRateLimiterStorage();

        if ($._currentPeriodAmount < $._cancellableAmount) {
            $._currentPeriodAmount = 0;
        } else {
            $._currentPeriodAmount -= $._cancellableAmount;
        }

        $._cancellableAmount = 0;
    }

    // solhint-disable-next-line func-name-mixedcase
    function __StaticFlowRateLimiter_init(
        address admin
    ) internal onlyInitializing {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        __StaticFlowRateLimiter_init_unchained();
    }

    // solhint-disable-next-line func-name-mixedcase
    function __StaticFlowRateLimiter_init_unchained()
        internal
        onlyInitializing
    {
        StaticFlowRateLimiterStorage
            storage $ = _getStaticFlowRateLimiterStorage();
        $._currentPeriodEnd = block.number + PERIOD;
    }

    function _updatePeriod() private {
        StaticFlowRateLimiterStorage
            storage $ = _getStaticFlowRateLimiterStorage();

        if ($._currentPeriodEnd < block.number) {
            _resetFlowRateLimit($);
        }
    }

    function _resetFlowRateLimit(
        StaticFlowRateLimiterStorage storage $
    ) private {
        $._currentPeriodEnd = block.number + PERIOD;
        $._currentPeriodAmount = 0;
        $._appliedLockPeriod = false;
    }

    function _getStaticFlowRateLimiterStorage()
        private
        pure
        returns (StaticFlowRateLimiterStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := STATIC_FLOW_RATE_LIMITER_LOCATION
        }
    }
}
