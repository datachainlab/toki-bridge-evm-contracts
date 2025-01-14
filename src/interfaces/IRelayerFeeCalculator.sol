// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../interfaces/IStableTokenPriceOracle.sol";
import "../library/IBCUtils.sol";

interface IRelayerFeeCalculator {
    struct RelayerFee {
        uint256 dstTokenPrice;
        uint8 dstTokenDecimals;
        uint256 dstGasPrice;
        uint256 srcTokenPrice;
        uint8 srcTokenDecimals;
        uint256 srcGasPrice; // only set in case of _TYPE_WITHDRAW
        uint256 srcFee;
        uint256 dstFee;
        uint256 fee;
    }

    function calcFee(
        uint8 messageType,
        uint256 dstChainId,
        IBCUtils.ExternalInfo memory externalInfo
    ) external view returns (RelayerFee memory relayerFee);

    function getGasPrice(
        uint256 chainId
    ) external view returns (uint256 gasPrice);

    function version() external pure returns (string memory);
}
