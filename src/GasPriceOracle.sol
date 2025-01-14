// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IGasPriceOracle.sol";

contract GasPriceOracle is AccessControl, IGasPriceOracle {
    mapping(uint256 => uint256) private _chainIdToPrice;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function getPrice(uint256 chainId) external view returns (uint256) {
        return _chainIdToPrice[chainId];
    }

    function updatePrice(
        uint256 chainId,
        uint256 price
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _chainIdToPrice[chainId] = price;
        emit PriceUpdated(chainId, price);
    }
}
