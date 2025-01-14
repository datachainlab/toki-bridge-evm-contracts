// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../library/IBCUtils.sol";

/// @dev Interface of the Toki Outer Service Receiver
/// Contracts that want to do something with the tokens received from
/// the Toki Outer Service must implement this
interface ITokiOuterServiceReceiver {
    function onReceivePool(
        string memory dstChannel,
        address token,
        uint256 amount,
        bytes memory payload
    ) external;
}
