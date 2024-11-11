// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../interfaces/ITokiErrors.sol";
import "../interfaces/ITokiOuterServiceReceiver.sol";
import {ShortString, ShortStrings} from "@openzeppelin/contracts/utils/ShortStrings.sol";

// Note about disable slither:
//   Withdrawal function is omitted because this is mock contract.
// slither-disable-start locked-ether
contract MockOuterService is ITokiErrors, ITokiOuterServiceReceiver {
    using ShortStrings for string;
    using ShortStrings for ShortString;

    struct ReceiveMsg {
        string port;
        string channel;
        address token;
        uint256 amount;
        bytes payload;
    }

    ShortString public immutable PORT;

    // for test, force fail any receive functions
    bool public forceFail;

    ReceiveMsg[] public receivedMsgs;

    event PoolReceived(
        string indexed port,
        string indexed channel,
        address token,
        uint256 amount,
        bytes payload
    );

    constructor(string memory port) {
        PORT = port.toShortString();
    }

    receive() external payable {}

    fallback() external payable {}

    // TODO: implement transferPool function
    // This function is called on the source chain and call the transferPool function of the Bridge contract.
    /*
    function transferPool(
        Bridge _bridge,
        [transferPool variables],
        bytes memory payload
    ) external {}
    */

    /// @dev Called by the bridge when tokens are sent to this contract on the destination chain.
    /// pushes the received message to the receivedMsgs array and emits an event.
    function onReceivePool(
        string memory dstChannel,
        address token,
        uint256 amount,
        bytes memory payload
    ) external override {
        if (forceFail) {
            revert TokiMock("onReceivePool force fail");
        }
        string memory port = PORT.toString();
        receivedMsgs.push(
            ReceiveMsg({
                port: port,
                channel: dstChannel,
                token: token,
                amount: amount,
                payload: payload
            })
        );
        emit PoolReceived(port, dstChannel, token, amount, payload);
    }

    // ======================= for test ====================
    function setForceFail(bool forceFail_) external {
        forceFail = forceFail_;
    }
}

// slither-disable-end locked-ether
