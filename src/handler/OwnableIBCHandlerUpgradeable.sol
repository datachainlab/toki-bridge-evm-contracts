// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {ILightClient} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/02-client/ILightClient.sol";
import {IIBCClient} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/02-client/IIBCClient.sol";
import {IBCHandler} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/25-handler/IBCHandler.sol";
import {IIBCModuleInitializer} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/26-router/IIBCModule.sol";
import {IIBCConnection} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/03-connection/IIBCConnection.sol";
import {IIBCChannelHandshake, IIBCChannelPacketSendRecv, IIBCChannelPacketTimeout} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IIBCChannel.sol";
import {IIBCChannelUpgradeInitTryAck, IIBCChannelUpgradeConfirmOpenTimeoutCancel} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IIBCChannelUpgrade.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

contract OwnableIBCHandlerUpgradeable is
    IBCHandler,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IIBCClient ibcClient_,
        IIBCConnection ibcConnection_,
        IIBCChannelHandshake ibcChannelHandshake_,
        IIBCChannelPacketSendRecv ibcChannelPacketSendRecv_,
        IIBCChannelPacketTimeout ibcChannelPacketTimeout_,
        IIBCChannelUpgradeInitTryAck ibcChannelUpgradeInitTryAck_,
        IIBCChannelUpgradeConfirmOpenTimeoutCancel ibcChannelUpgradeConfirmOpenTimeoutCancel_
    )
        IBCHandler(
            ibcClient_,
            ibcConnection_,
            ibcChannelHandshake_,
            ibcChannelPacketSendRecv_,
            ibcChannelPacketTimeout_,
            ibcChannelUpgradeInitTryAck_,
            ibcChannelUpgradeConfirmOpenTimeoutCancel_
        )
    {}

    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
    }

    function registerClient(
        string calldata clientType,
        ILightClient client
    ) public onlyOwner {
        super._registerClient(clientType, client);
    }

    function bindPort(
        string calldata portId,
        IIBCModuleInitializer moduleAddress
    ) public onlyOwner {
        super._bindPort(portId, moduleAddress);
    }

    function setExpectedTimePerBlock(
        uint64 expectedTimePerBlock_
    ) public onlyOwner {
        super._setExpectedTimePerBlock(expectedTimePerBlock_);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}

    function _msgSender()
        internal
        view
        virtual
        override(Context, ContextUpgradeable)
        returns (address)
    {
        return ContextUpgradeable._msgSender();
    }

    function _msgData()
        internal
        view
        virtual
        override(Context, ContextUpgradeable)
        returns (bytes calldata)
    {
        return ContextUpgradeable._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        virtual
        override(Context, ContextUpgradeable)
        returns (uint256)
    {
        return ContextUpgradeable._contextSuffixLength();
    }
}
