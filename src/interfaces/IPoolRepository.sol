// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./IPool.sol";

interface IPoolRepository {
    /* ========== EVENTS ========== */
    event SetPool(uint256 poolId, address pool);

    function setPool(uint256 poolId, address pool) external;

    function getPool(uint256 poolId) external view returns (IPool);
}
