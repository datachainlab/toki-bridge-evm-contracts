// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "./interfaces/ITokiErrors.sol";
import "./interfaces/IPoolRepository.sol";
import "./interfaces/IPool.sol";

/**
 * @title Pool Repository
 */
contract PoolRepository is
    ITokiErrors,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    IPoolRepository
{
    bytes32 public constant POOL_SETTER = keccak256("POOL_SETTER");

    mapping(uint256 => address) private _pools;

    uint256 public length;

    function initialize() public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setPool(
        uint256 poolId,
        address pool
    ) external onlyRole(POOL_SETTER) {
        address oldPool = _pools[poolId];
        if (oldPool == pool) {
            revert TokiSamePool(poolId, oldPool);
        }
        if (oldPool == address(0) && pool != address(0)) {
            length++;
        } else if (oldPool != address(0) && pool == address(0)) {
            length--;
        }
        _pools[poolId] = pool;
        emit SetPool(poolId, pool);
    }

    function getPool(uint256 poolId) external view returns (IPool) {
        address pool = _pools[poolId];
        if (pool == address(0)) {
            revert TokiNoPool(poolId);
        }
        return IPool(pool);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
