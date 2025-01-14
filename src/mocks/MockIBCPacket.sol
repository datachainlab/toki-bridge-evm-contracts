// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IIBCChannel.sol";

contract MockIBCPacket is IICS04SendPacket {
    uint64 public sequence;

    event SendPacket(
        string sourcePort,
        string sourceChannel,
        Height.Data timeoutHeight,
        uint64 timeoutTimestamp,
        bytes32 dataHash
    );

    function sendPacket(
        string calldata sourcePort,
        string calldata sourceChannel,
        Height.Data calldata timeoutHeight,
        uint64 timeoutTimestamp,
        bytes calldata data
    ) external returns (uint64 sequence_) {
        sequence_ = sequence;
        sequence++;
        emit SendPacket(
            sourcePort,
            sourceChannel,
            timeoutHeight,
            timeoutTimestamp,
            keccak256(data)
        );
    }
}
