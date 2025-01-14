// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IIBCClient} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/02-client/IIBCClient.sol";
import {IIBCConnection} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/03-connection/IIBCConnection.sol";
import {IIBCChannelHandshake, IIBCChannelPacketSendRecv, IIBCChannelPacketTimeout} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IIBCChannel.sol";
import {IIBCChannelUpgradeInitTryAck, IIBCChannelUpgradeConfirmOpenTimeoutCancel} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IIBCChannelUpgrade.sol";

import "../src/handler/OwnableIBCHandlerUpgradeable.sol";

contract MockOwnableIBCHandlerUpgradeable is OwnableIBCHandlerUpgradeable {
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
        OwnableIBCHandlerUpgradeable(
            ibcClient_,
            ibcConnection_,
            ibcChannelHandshake_,
            ibcChannelPacketSendRecv_,
            ibcChannelPacketTimeout_,
            ibcChannelUpgradeInitTryAck_,
            ibcChannelUpgradeConfirmOpenTimeoutCancel_
        )
    {}

    // for upgrading test
    function getIBCClient() public view returns (address) {
        return ibcClient;
    }
}

contract OwnableIBCHandlerUpgradeableTest is Test {
    OwnableIBCHandlerUpgradeable public t;

    function setUp() public {
        address impl = address(
            new OwnableIBCHandlerUpgradeable(
                IIBCClient(makeAddr("ibcClient")),
                IIBCConnection(makeAddr("ibcConnection")),
                IIBCChannelHandshake(makeAddr("ibcChannelHandshake")),
                IIBCChannelPacketSendRecv(makeAddr("ibcChannelPacketSendRecv")),
                IIBCChannelPacketTimeout(makeAddr("ibcChannelPacketTimeout")),
                IIBCChannelUpgradeInitTryAck(
                    makeAddr("ibcChannelUpgradeInitTryAck")
                ),
                IIBCChannelUpgradeConfirmOpenTimeoutCancel(
                    makeAddr("ibcChannelUpgradeConfirmOpenTimeoutCancel")
                )
            )
        );
        bytes memory data = abi.encodeCall(
            OwnableIBCHandlerUpgradeable.initialize,
            ()
        );
        address proxy = address(new ERC1967Proxy(impl, data));
        t = OwnableIBCHandlerUpgradeable(proxy);
    }

    function testUpgradeToAndCall() public {
        t.setExpectedTimePerBlock(1);
        assertEq(t.getExpectedTimePerBlock(), 1);

        address newImpl = address(
            new MockOwnableIBCHandlerUpgradeable(
                IIBCClient(makeAddr("newIbcClient")),
                IIBCConnection(makeAddr("newIbcConnection")),
                IIBCChannelHandshake(makeAddr("newIbcChannelHandshake")),
                IIBCChannelPacketSendRecv(
                    makeAddr("newIbcChannelPacketSendRecv")
                ),
                IIBCChannelPacketTimeout(
                    makeAddr("newIbcChannelPacketTimeout")
                ),
                IIBCChannelUpgradeInitTryAck(
                    makeAddr("ibcChannelUpgradeInitTryAck")
                ),
                IIBCChannelUpgradeConfirmOpenTimeoutCancel(
                    makeAddr("ibcChannelUpgradeConfirmOpenTimeoutCancel")
                )
            )
        );
        vm.expectEmit(address(t));
        emit IERC1967.Upgraded(newImpl);
        t.upgradeToAndCall(newImpl, "");

        MockOwnableIBCHandlerUpgradeable newT = MockOwnableIBCHandlerUpgradeable(
                address(t)
            );
        // After upgrading, it can still remain storage variables.
        assertEq(newT.getExpectedTimePerBlock(), 1);
        // However, it should be able to access newly set address.
        assertEq(newT.getIBCClient(), makeAddr("newIbcClient"));
    }

    function testUpgradeToAndCallRevertsWhenSenderIsNotOwner() public {
        address newImpl = address(
            new OwnableIBCHandlerUpgradeable(
                IIBCClient(makeAddr("newIbcClient")),
                IIBCConnection(makeAddr("newIbcConnection")),
                IIBCChannelHandshake(makeAddr("newIbcChannelHandshake")),
                IIBCChannelPacketSendRecv(
                    makeAddr("newIbcChannelPacketSendRecv")
                ),
                IIBCChannelPacketTimeout(
                    makeAddr("newIbcChannelPacketTimeout")
                ),
                IIBCChannelUpgradeInitTryAck(
                    makeAddr("ibcChannelUpgradeInitTryAck")
                ),
                IIBCChannelUpgradeConfirmOpenTimeoutCancel(
                    makeAddr("ibcChannelUpgradeConfirmOpenTimeoutCancel")
                )
            )
        );

        address notOwner = makeAddr("notOwner");
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                notOwner
            )
        );
        vm.prank(notOwner);
        t.upgradeToAndCall(newImpl, "");
    }
}
