// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @dev StaticFlowRateLimiter limits the flow within a certain period.
 * For example, it can be used to limit the amount of ERC20 token transfers.
 */
interface IStaticFlowRateLimiter {
    /**
     * @dev Resets the flow rate limit with a privilege.
     */
    function resetFlowRateLimit() external;

    /**
     * @dev Returns the end of the current period.
     * @return The block number when the current period ends.
     */
    function currentPeriodEnd() external view returns (uint256);

    /**
     * @dev Returns the amount accumulated in the current period.
     * @return The amount accumulated in the current period.
     */
    function currentPeriodAmount() external view returns (uint256);

    /**
     * @dev Returns whether the lock period is applied.
     * @return `true` if the lock period is applied, `false` otherwise.
     */
    function appliedLockPeriod() external view returns (bool);
}
