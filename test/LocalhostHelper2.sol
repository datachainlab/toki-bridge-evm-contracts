// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IIBCHandler} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/25-handler/IIBCHandler.sol";
import {LocalhostClientLib} from "@hyperledger-labs/yui-ibc-solidity/contracts/clients/09-localhost/LocalhostClient.sol";
import {Height} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/Client.sol";
import {Channel} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/Channel.sol";
import {LocalhostHelper} from "@hyperledger-labs/yui-ibc-solidity/contracts/clients/09-localhost//LocalhostHelper.sol";

import "forge-std/console.sol";
import {Vm} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {IIBCChannelRecvPacket} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IIBCChannel.sol";
import {IBCTestHelper} from "@hyperledger-labs/yui-ibc-solidity/tests/foundry/src/helpers/IBCTestHelper.t.sol";
import "@hyperledger-labs/yui-ibc-solidity/tests/foundry/src/helpers/TestableIBCHandler.t.sol";
import {ICS04PacketEventTestHelper} from "@hyperledger-labs/yui-ibc-solidity/tests/foundry/src/helpers/ICS04PacketTestHelper.t.sol";

import "../src/library/MessageType.sol";
import "../src/library/IBCUtils.sol";

/**
 * extends some functions on LocalhostHelper
 */
library LocalhostHelper2 {
    function createClientConnectionChannel(
        IIBCHandler ibcHandler,
        string memory portId0,
        string memory portId1,
        Channel.Order ordering,
        string memory version
    ) public returns (string memory channelId0, string memory channelId1) {
        LocalhostHelper.registerLocalhostClient(ibcHandler);
        LocalhostHelper.createLocalhostClient(ibcHandler);

        (
            string memory connectionId0,
            string memory connectionId1
        ) = LocalhostHelper.createLocalhostConnection(
                ibcHandler,
                LocalhostHelper.defaultMsgCreateConnection()
            );

        (channelId0, channelId1) = LocalhostHelper.createLocalhostChannel(
            ibcHandler,
            LocalhostHelper.MsgCreateChannel({
                connectionId0: connectionId0,
                connectionId1: connectionId1,
                portId0: portId0,
                portId1: portId1,
                ordering: ordering,
                version: version
            })
        );
    }
}

contract LocalhostTest is IBCTestHelper, ICS04PacketEventTestHelper {
    struct ChannelInfo {
        string port;
        string channel;
    }

    TestableIBCHandler public _ibcHandler;
    address payable public _relayer = payable(address(0x72656c61786572));

    function setUp() public virtual {
        _ibcHandler = defaultIBCHandler();
    }

    function relay(
        uint8 expectFtype,
        ChannelInfo memory srcChannelInfo,
        uint256 recvChainId
    ) internal returns (Packet memory, Vm.Log[] memory) {
        return
            relay(
                expectFtype,
                srcChannelInfo,
                recvChainId,
                vm.getRecordedLogs()
            );
    }

    function relay(
        uint8 expectFtype,
        ChannelInfo memory srcChannelInfo,
        uint256 recvChainId,
        Vm.Log[] memory logs
    ) internal returns (Packet memory packet, Vm.Log[] memory newLogs) {
        (
            VmSafe.CallerMode callerMode0,
            address msgSender0,
            address txOrigin0
        ) = vm.readCallers();
        if (callerMode0 == VmSafe.CallerMode.RecurrentPrank) {
            // startPrank
            vm.stopPrank();
        } // broadcast is not support yet
        vm.startPrank(_relayer);

        packet = getLastSentPacket(
            _ibcHandler,
            srcChannelInfo.port,
            srcChannelInfo.channel,
            logs
        );
        uint8 ftype = IBCUtils.parseType(packet.data);
        assertEq(expectFtype, ftype, "should relay expected ftype");

        uint256 oldChainId = block.chainid;
        vm.chainId(recvChainId);
        _ibcHandler.recvPacket(
            IIBCChannelRecvPacket.MsgPacketRecv({
                packet: packet,
                proof: LocalhostClientLib.sentinelProof(),
                proofHeight: Height.Data(0, 0)
            })
        );
        vm.chainId(oldChainId);
        newLogs = vm.getRecordedLogs(); //getRecordLogs consumes internal log records

        // no ack is written
        /*
        WriteAcknolwedgement memory ack = getLastWrittenAcknowledgement(
            _ibcHandler,
            newLogs
        );
        if (ack.acknowledgement.length > 0) {
            _ibcHandler.acknowledgePacket(
                IIBCChannelAcknowledgePacket.MsgPacketAcknowledgement({
                    packet: packet,
                    acknowledgement: ack.acknowledgement,
                    proof: LocalhostClientLib.sentinelProof(),
                    proofHeight: Height.Data(0, 0)
                })
            );
        }
        */
        vm.stopPrank();
        if (callerMode0 == VmSafe.CallerMode.RecurrentPrank) {
            // startPrank
            vm.startPrank(msgSender0, txOrigin0);
        }
    }

    function dumpSentPackets() internal returns (Vm.Log[] memory) {
        return dumpSentPackets(vm.getRecordedLogs());
    }

    function dumpSentPackets(
        Vm.Log[] memory logs
    ) internal view returns (Vm.Log[] memory retLogs) {
        retLogs = logs;
        console.log("dumpSentPackets...len=%d", logs.length);
        for (uint256 i = logs.length; i > 0; i--) {
            if (logs[i - 1].emitter == address(_ibcHandler)) {
                (Packet memory p, bool ok) = tryDecodeSendPacketEvent(
                    logs[i - 1]
                );
                if (ok) {
                    uint8 messageType = IBCUtils.parseType(p.data);
                    if (messageType == MessageType._TYPE_TRANSFER_POOL) {
                        console.log("%d %s", i, "TRANSFER_POOL");
                    } else if (messageType == MessageType._TYPE_CREDIT) {
                        console.log("%d %s", i, "CREDIT");
                    } else if (messageType == MessageType._TYPE_WITHDRAW) {
                        console.log("%d %s", i, "WITHDRAW");
                    } else if (
                        messageType == MessageType._TYPE_WITHDRAW_CHECK
                    ) {
                        console.log("%d %s", i, "WITHDRAW_CHECK");
                    } else if (
                        messageType == MessageType._TYPE_TRANSFER_TOKEN
                    ) {
                        console.log("%d %s", i, "TRANSFER_TOKEN");
                    } else {
                        console.log("%d %s", i, "unknown type");
                    }
                } else {
                    console.log("%d %s", i, "fail to decode");
                }
            }
        }
    }
}
