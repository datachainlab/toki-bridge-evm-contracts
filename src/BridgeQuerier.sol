// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "./BridgeBase.sol";
import "./interfaces/IBridgeQuerier.sol";

contract BridgeQuerier is BridgeBase, IBridgeQuerier {
    function calcSrcNativeAmount(
        uint256 dstChainId,
        uint256 dstGas,
        uint256 dstNativeAmount
    ) external view returns (uint256) {
        BridgeStorage storage $ = getBridgeStorage();
        (uint256 srcTokenPrice, uint8 srcTokenDecimals) = $
            .tokenPriceOracle
            .getLatestPriceAndDecimals(block.chainid);
        (uint256 dstTokenPrice, uint8 dstTokenDecimals) = $
            .tokenPriceOracle
            .getLatestPriceAndDecimals(dstChainId);
        uint256 dstGasPrice = $.relayerFeeCalculator.getGasPrice(dstChainId);
        uint256 riskBPS = $.premiumBPS[dstChainId];

        return
            _calcSrcNativeAmount(
                dstGas,
                dstNativeAmount,
                srcTokenPrice,
                srcTokenDecimals,
                dstTokenPrice,
                dstTokenDecimals,
                dstGasPrice,
                riskBPS
            );
    }

    function defaultFallback() external view returns (address) {
        return getBridgeStorage().defaultFallback;
    }

    function channelUpgradeFallback() external view returns (address) {
        return getBridgeStorage().channelUpgradeFallback;
    }

    function poolRepository() external view returns (IPoolRepository) {
        return getBridgeStorage().poolRepository;
    }

    function premiumBPS(uint256 chainId) external view returns (uint256) {
        return getBridgeStorage().premiumBPS[chainId];
    }

    function refuelDstCap() external view returns (uint256) {
        return getBridgeStorage().refuelDstCap;
    }

    function refuelSrcCap(uint256 chainId) external view returns (uint256) {
        return getBridgeStorage().refuelSrcCap[chainId];
    }

    function relayerFeeCalculator()
        external
        view
        returns (IRelayerFeeCalculator)
    {
        return getBridgeStorage().relayerFeeCalculator;
    }

    function revertReceive(
        uint256 chainId,
        uint64 sequence
    ) external view returns (bytes memory) {
        return getBridgeStorage().revertReceive[chainId][sequence];
    }

    function tokenEscrow() external view returns (ITokenEscrow) {
        return getBridgeStorage().tokenEscrow;
    }

    function tokenPriceOracle() external view returns (ITokenPriceOracle) {
        return getBridgeStorage().tokenPriceOracle;
    }

    function receiveRetryBlocks() external view returns (uint64) {
        return getBridgeStorage().receiveRetryBlocks;
    }

    function withdrawRetryBlocks() external view returns (uint64) {
        return getBridgeStorage().withdrawRetryBlocks;
    }

    function externalRetryBlocks() external view returns (uint64) {
        return getBridgeStorage().externalRetryBlocks;
    }
}
