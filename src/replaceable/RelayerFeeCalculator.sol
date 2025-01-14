// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/ITokiErrors.sol";
import "../interfaces/ITokenPriceOracle.sol";
import "../interfaces/IGasPriceOracle.sol";
import "../interfaces/IRelayerFeeCalculator.sol";
import "../library/MessageType.sol";
import "../library/IBCUtils.sol";

contract RelayerFeeCalculator is
    ITokiErrors,
    IRelayerFeeCalculator,
    AccessControl
{
    address public tokenPriceOracle;
    address public gasPriceOracle;
    uint256 public premiumBPS;
    uint256 public gasUsed;
    uint256 public gasPerPayloadLength;

    /* ========== EVENTS ========== */
    event SetTokenPriceOracle(address oracle);

    event SetGasPriceOracle(address oracle);

    event SetGasUsed(uint256 gasUsed);

    event SetGasPerPayloadLength(uint256 gasPerPayloadLength);

    event SetPremiumBPS(uint256 premiumBPS);

    constructor(
        address tokenPriceOracle_,
        address gasPriceOracle_,
        uint256 gasUsed_,
        uint256 gasPerPayloadLength_,
        uint256 premiumBPS_
    ) {
        if (tokenPriceOracle_ == address(0)) {
            revert TokiZeroAddress("tokenPriceOracle");
        }
        if (gasPriceOracle_ == address(0)) {
            revert TokiZeroAddress("gasPriceOracle");
        }

        tokenPriceOracle = tokenPriceOracle_;
        gasPriceOracle = gasPriceOracle_;
        gasUsed = gasUsed_;
        gasPerPayloadLength = gasPerPayloadLength_;
        premiumBPS = premiumBPS_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ---------- ONLY OWNER ----------
    function setTokenPriceOracle(
        address tokenPriceOracle_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (tokenPriceOracle_ == address(0)) {
            revert TokiZeroAddress("tokenPriceOracle");
        }
        tokenPriceOracle = tokenPriceOracle_;
        emit SetTokenPriceOracle(tokenPriceOracle);
    }

    function setGasPriceOracle(
        address gasPriceOracle_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (gasPriceOracle_ == address(0)) {
            revert TokiZeroAddress("gasPriceOracle");
        }
        gasPriceOracle = gasPriceOracle_;
        emit SetGasPriceOracle(gasPriceOracle);
    }

    function setGasUsed(
        uint256 gasUsed_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        gasUsed = gasUsed_;
        emit SetGasUsed(gasUsed);
    }

    function setGasPerPayloadLength(
        uint256 gasPerPayloadLength_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        gasPerPayloadLength = gasPerPayloadLength_;
        emit SetGasPerPayloadLength(gasPerPayloadLength);
    }

    function setPremiumBPS(
        uint256 premiumBPS_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        premiumBPS = premiumBPS_;
        emit SetPremiumBPS(premiumBPS);
    }

    // --- interface functions -----------------------
    /**
     * @dev Calculate the estimated gas cost on the destination chain for the relayer
     * @param messageType message type
     * @param dstChainId destination chain id
     * @param externalInfo external info
     * @return relayerFee fee for the relayer
     */
    function calcFee(
        uint8 messageType,
        uint256 dstChainId,
        IBCUtils.ExternalInfo memory externalInfo
    ) external view returns (RelayerFee memory relayerFee) {
        if (dstChainId == block.chainid) {
            return relayerFee;
        }
        if (messageType == MessageType._TYPE_WITHDRAW_CHECK) {
            return relayerFee;
        }

        (
            relayerFee.dstTokenPrice,
            relayerFee.dstTokenDecimals
        ) = ITokenPriceOracle(tokenPriceOracle).getPriceAndDecimals(dstChainId);
        relayerFee.dstGasPrice = IGasPriceOracle(gasPriceOracle).getPrice(
            dstChainId
        );
        (
            relayerFee.srcTokenPrice,
            relayerFee.srcTokenDecimals
        ) = ITokenPriceOracle(tokenPriceOracle).getPriceAndDecimals(
            block.chainid
        );

        if (relayerFee.srcTokenPrice == 0) {
            revert TokiZeroValue("srcTokenPrice");
        }

        // The gas fee in src chain native token is:
        //  `feeInSrcToken = dstGasFeeInDstToken * dstTokenPriceValue / srcTokenPriceValue`
        // Note that tokenPriceValue is combined mantissa and decimals:
        //  `tokenPriceValue = tokenPrice / (10 ** tokenPriceDecimals)
        // so the fee is:
        //  `feeInSrcToken = (dstGasFeeInDstToken * dstTokenPrice / srcTokenPrice) * (10 ** (srcTokenDecimals - dstTokenDecimals))`
        // We first calculating `10 ** (srcTokenDecimals - dstTokenDecimals)` part in fraction format.
        (
            uint256 decimalRatioNumerator,
            uint256 decimalRatioDenominator
        ) = (relayerFee.dstTokenDecimals < relayerFee.srcTokenDecimals)
                ? (
                    10 **
                        (relayerFee.srcTokenDecimals -
                            relayerFee.dstTokenDecimals),
                    uint256(1)
                )
                : (
                    uint256(1),
                    10 **
                        (relayerFee.dstTokenDecimals -
                            relayerFee.srcTokenDecimals)
                );
        uint256 gas = gasUsed;
        // these two message types need to calculate the gas cost based on the payload length and the dstOuterGas
        if (
            messageType == MessageType._TYPE_TRANSFER_POOL ||
            messageType == MessageType._TYPE_TRANSFER_TOKEN
        ) {
            gas +=
                gasPerPayloadLength *
                externalInfo.payload.length +
                externalInfo.dstOuterGas;
        }

        relayerFee.fee =
            (gas *
                relayerFee.dstGasPrice *
                premiumBPS *
                relayerFee.dstTokenPrice *
                decimalRatioNumerator) /
            (10000 * relayerFee.srcTokenPrice * decimalRatioDenominator);

        if (messageType == MessageType._TYPE_WITHDRAW) {
            relayerFee.srcGasPrice = IGasPriceOracle(gasPriceOracle).getPrice(
                block.chainid
            );
            relayerFee.fee =
                relayerFee.fee +
                (gas * relayerFee.srcGasPrice * premiumBPS) /
                10000;
        }
    }

    function getGasPrice(
        uint256 chainId
    ) external view returns (uint256 gasPrice) {
        gasPrice = IGasPriceOracle(gasPriceOracle).getPrice(chainId);
    }

    function version() external pure override returns (string memory) {
        return "1.0.0";
    }
}
