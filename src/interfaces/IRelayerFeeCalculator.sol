// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../interfaces/IStableTokenPriceOracle.sol";

interface IRelayerFeeCalculator {
    struct RelayerFee {
        uint256 dstTokenPrice;
        uint256 dstGasPrice;
        uint256 srcTokenPrice;
        uint256 srcGasPrice; // only set in case of _TYPE_WITHDRAW
        uint256 srcFee;
        uint256 dstFee;
        uint256 fee;
    }

    function calcFee(
        uint8 messageType,
        uint256 dstChainId
    ) external view returns (RelayerFee memory relayerFee);

    function getGasPrice(
        uint256 chainId
    ) external view returns (uint256 gasPrice);

    function version() external pure returns (string memory);
}
