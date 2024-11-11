// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../../interfaces/ITokiErrors.sol";
import "../interfaces/ITokenEscrow.sol";

contract MockEscrow is ITokiErrors, ITokenEscrow {
    struct CallTransferToken {
        uint256 dstChainId;
        address from;
        uint256 amountLD;
    }

    struct CallReceiveToken {
        address to;
        uint256 amountGD;
    }

    CallTransferToken public callTransferToken;
    CallReceiveToken public callReceiveToken;

    address public immutable TOKEN;
    uint8 public immutable LOCAL_DECIMALS;
    uint8 public immutable GLOBAL_DECIMALS;
    uint256 public immutable CONVERT_RATE;

    constructor(address token_, uint8 localDecimals_, uint8 globalDecimals_) {
        if (token_ == address(0)) {
            revert TokiZeroAddress("token");
        }
        TOKEN = token_;
        LOCAL_DECIMALS = localDecimals_;
        GLOBAL_DECIMALS = globalDecimals_;
        CONVERT_RATE =
            10 ** ((uint256(localDecimals_) - uint256(globalDecimals_)));
    }

    function transferToken(
        uint256 dstChainId,
        address from,
        uint256 amountLD
    ) external returns (uint256 amountGD) {
        callTransferToken = CallTransferToken(dstChainId, from, amountLD);
        amountGD = amountLD;
    }

    function receiveToken(address to, uint256 amountGD) external {
        callReceiveToken = CallReceiveToken(to, amountGD);
    }

    // IDecimalConvertible
    function globalDecimals() external view returns (uint8) {
        return LOCAL_DECIMALS;
    }

    function localDecimals() external view returns (uint8) {
        return GLOBAL_DECIMALS;
    }

    function convertRate() external view returns (uint256) {
        return CONVERT_RATE;
    }

    function token() external view returns (address) {
        return TOKEN;
    }
}
