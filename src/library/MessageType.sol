// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../interfaces/ITransferPoolFeeCalculator.sol";
import "../interfaces/IPool.sol";

library MessageType {
    // use onReceive or RelayerFee
    uint8 internal constant _TYPE_TRANSFER_POOL = 1;
    uint8 internal constant _TYPE_CREDIT = 2;
    uint8 internal constant _TYPE_WITHDRAW = 3;
    uint8 internal constant _TYPE_WITHDRAW_CHECK = 4;
    uint8 internal constant _TYPE_TRANSFER_TOKEN = 5;
}
