// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/interfaces/IBridge.sol";
import "../src/interfaces/ITokiErrors.sol";
import "../src/Bridge.sol";
import "../src/mocks/MockUpgradeBridge.sol";
import "../src/BridgeChannelUpgradeFallback.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IBCChannelLib.sol";
import {LocalhostHelper} from "@hyperledger-labs/yui-ibc-solidity/contracts/clients/09-localhost/LocalhostHelper.sol";
import "@hyperledger-labs/yui-ibc-solidity/contracts/proto/Channel.sol";
import {ICS04UpgradeBase} from "./ICS04UpgradeBase.t.sol";
import {TestableIBCHandler} from "@hyperledger-labs/yui-ibc-solidity/tests/foundry/src/helpers/TestableIBCHandler.t.sol";

contract BridgeChannelUpgradeFallbackTest is ICS04UpgradeBase {
    using LocalhostHelper for TestableIBCHandler;

    string public constant PORT = "toki";
    string public constant PORT_COUNTERPARTY = "toki-counterparty";
    uint256 public constant APP_VERSION_1 = 1;
    uint256 public constant APP_VERSION_2 = 2;

    address public constant POOL_REPOSITORY = address(0x2);
    address public constant ESCROW = address(0x3);
    address public constant TOKEN_PRICE_ORACLE = address(0x4);
    address public constant FEE_OWNER = address(0x5);
    address public constant RELAYER_FEE_CALCULATOR = address(0x6);
    address public constant BRIDGE_FALLBACK = address(0x7);

    address public constant ALICE = address(0x101);

    uint256 public constant DST_CHAIN_ID = 123;

    address public proxy;
    address public proxyCounterparty;
    BridgeChannelUpgradeFallback public channelUpgradeFallback;
    BridgeChannelUpgradeFallback public channelUpgradeFallbackCounterparty;
    bytes32 public bridgeDefaultAdminRole;

    function setUp() public {
        ibcHandler = defaultIBCHandler();

        Bridge bridge = new Bridge(APP_VERSION_1, PORT);
        bridgeDefaultAdminRole = bridge.DEFAULT_ADMIN_ROLE();

        bytes memory initializeData = _bridgeInitializeData(APP_VERSION_1);
        proxy = address(new ERC1967Proxy(address(bridge), initializeData));
        channelUpgradeFallback = BridgeChannelUpgradeFallback(proxy);
        {
            IBridge iBridge = IBridge(proxy);
            iBridge.grantRole(bridge.IBC_HANDLER_ROLE(), address(this));
            ibcHandler.bindPort(PORT, iBridge);
        }

        proxyCounterparty = address(
            new ERC1967Proxy(address(bridge), initializeData)
        );
        channelUpgradeFallbackCounterparty = BridgeChannelUpgradeFallback(
            proxyCounterparty
        );
        {
            IBridge iBridge = IBridge(proxyCounterparty);
            iBridge.grantRole(bridge.IBC_HANDLER_ROLE(), address(this));
            ibcHandler.bindPort(PORT_COUNTERPARTY, iBridge);
        }

        ibcHandler.registerLocalhostClient();
        ibcHandler.createLocalhostClient();
    }

    function testChannelUpgrade() public {
        _testChannelUpgrade(APP_VERSION_2, HandshakeFlow(false, false));
    }

    function testChannelUpgradeCrossingHello() public {
        _testChannelUpgrade(APP_VERSION_2, HandshakeFlow(true, false));
    }

    function testChannelUpgradeFastPath() public {
        _testChannelUpgrade(APP_VERSION_2, HandshakeFlow(false, true));
    }

    function testChannelUpgradeCrossingHelloFastPath() public {
        _testChannelUpgrade(APP_VERSION_2, HandshakeFlow(true, true));
    }

    function testProposeUpgradeFailWithNotFoundChannel() public {
        string memory version = mockVersion(APP_VERSION_2);
        vm.expectRevert();
        channelUpgradeFallback.proposeUpgrade(
            PORT,
            "channel-0",
            UpgradeFields.Data({
                ordering: Channel.Order.ORDER_ORDERED,
                connection_hops: IBCChannelLib.buildConnectionHops(
                    "connection-0"
                ),
                version: version
            }),
            Timeout.Data({
                height: Height.Data({revision_number: 1, revision_height: 10}),
                timestamp: 0
            })
        );
    }

    function testProposeUpgrade() public {
        (ChannelInfo memory channel0, ) = _createMockAppLocalhostChannel(
            Channel.Order.ORDER_ORDERED,
            mockVersion(APP_VERSION_1)
        );

        string memory version = mockVersion(APP_VERSION_2);
        channelUpgradeFallback.proposeUpgrade(
            channel0.portId,
            channel0.channelId,
            UpgradeFields.Data({
                ordering: Channel.Order.ORDER_ORDERED,
                connection_hops: IBCChannelLib.buildConnectionHops(
                    "connection-0"
                ),
                version: version
            }),
            Timeout.Data({
                height: Height.Data({revision_number: 1, revision_height: 10}),
                timestamp: 0
            })
        );

        assertEq(
            abi.encode(
                UpgradeFields.Data({
                    ordering: Channel.Order.ORDER_ORDERED,
                    connection_hops: IBCChannelLib.buildConnectionHops(
                        "connection-0"
                    ),
                    version: version
                })
            ),
            abi.encode(
                channelUpgradeFallback
                    .getUpgradeProposal(channel0.portId, channel0.channelId)
                    .fields
            )
        );
        assertEq(
            abi.encode(
                Timeout.Data({
                    height: Height.Data({
                        revision_number: 1,
                        revision_height: 10
                    }),
                    timestamp: 0
                })
            ),
            abi.encode(
                channelUpgradeFallback
                    .getUpgradeProposal(channel0.portId, channel0.channelId)
                    .timeout
            )
        );
    }

    function testProposeUpgradeRepropose() public {
        (ChannelInfo memory channel0, ) = _createMockAppLocalhostChannel(
            Channel.Order.ORDER_ORDERED,
            mockVersion(APP_VERSION_1)
        );

        channelUpgradeFallback.proposeUpgrade(
            channel0.portId,
            channel0.channelId,
            UpgradeFields.Data({
                ordering: Channel.Order.ORDER_ORDERED,
                connection_hops: IBCChannelLib.buildConnectionHops(
                    "connection-0"
                ),
                version: mockVersion(APP_VERSION_2)
            }),
            Timeout.Data({
                height: Height.Data({revision_number: 1, revision_height: 10}),
                timestamp: 0
            })
        );
        channelUpgradeFallback.proposeUpgrade(
            channel0.portId,
            channel0.channelId,
            UpgradeFields.Data({
                ordering: Channel.Order.ORDER_ORDERED,
                connection_hops: IBCChannelLib.buildConnectionHops(
                    "connection-0"
                ),
                version: mockVersion(APP_VERSION_2 + 1)
            }),
            Timeout.Data({
                height: Height.Data({revision_number: 1, revision_height: 20}),
                timestamp: 0
            })
        );

        assertEq(
            abi.encode(
                UpgradeFields.Data({
                    ordering: Channel.Order.ORDER_ORDERED,
                    connection_hops: IBCChannelLib.buildConnectionHops(
                        "connection-0"
                    ),
                    version: mockVersion(APP_VERSION_2 + 1)
                })
            ),
            abi.encode(
                channelUpgradeFallback
                    .getUpgradeProposal(channel0.portId, channel0.channelId)
                    .fields
            )
        );
        assertEq(
            abi.encode(
                Timeout.Data({
                    height: Height.Data({
                        revision_number: 1,
                        revision_height: 20
                    }),
                    timestamp: 0
                })
            ),
            abi.encode(
                channelUpgradeFallback
                    .getUpgradeProposal(channel0.portId, channel0.channelId)
                    .timeout
            )
        );
    }

    function testRemoveProposalFailNotFound() public {
        (ChannelInfo memory channel0, ) = _createMockAppLocalhostChannel(
            Channel.Order.ORDER_ORDERED,
            mockVersion(APP_VERSION_1)
        );
        vm.expectRevert(
            IIBCChannelUpgradableModuleErrors
                .IBCChannelUpgradableModuleUpgradeNotFound
                .selector
        );
        channelUpgradeFallback.removeUpgradeProposal(
            channel0.portId,
            channel0.channelId
        );
    }

    function testRemoveProposalFailUnauthorized() public {
        (ChannelInfo memory channel0, ) = _createMockAppLocalhostChannel(
            Channel.Order.ORDER_ORDERED,
            mockVersion(APP_VERSION_1)
        );

        string memory version = mockVersion(APP_VERSION_2);
        channelUpgradeFallback.proposeUpgrade(
            channel0.portId,
            channel0.channelId,
            UpgradeFields.Data({
                ordering: Channel.Order.ORDER_ORDERED,
                connection_hops: IBCChannelLib.buildConnectionHops(
                    "connection-0"
                ),
                version: version
            }),
            Timeout.Data({
                height: Height.Data({revision_number: 1, revision_height: 10}),
                timestamp: 0
            })
        );

        vm.expectRevert(
            IIBCChannelUpgradableModuleErrors
                .IBCChannelUpgradableModuleUnauthorizedUpgrader
                .selector
        );
        vm.prank(ALICE);
        channelUpgradeFallback.removeUpgradeProposal(
            channel0.portId,
            channel0.channelId
        );
    }

    function testRemoveProposal() public {
        (ChannelInfo memory channel0, ) = _createMockAppLocalhostChannel(
            Channel.Order.ORDER_ORDERED,
            mockVersion(APP_VERSION_1)
        );

        string memory version = mockVersion(APP_VERSION_2);
        channelUpgradeFallback.proposeUpgrade(
            channel0.portId,
            channel0.channelId,
            UpgradeFields.Data({
                ordering: Channel.Order.ORDER_ORDERED,
                connection_hops: IBCChannelLib.buildConnectionHops(
                    "connection-0"
                ),
                version: version
            }),
            Timeout.Data({
                height: Height.Data({revision_number: 1, revision_height: 10}),
                timestamp: 0
            })
        );

        channelUpgradeFallback.removeUpgradeProposal(
            channel0.portId,
            channel0.channelId
        );
        IIBCChannelUpgradableModule.UpgradeProposal
            memory upgrade = channelUpgradeFallback.getUpgradeProposal(
                channel0.portId,
                channel0.channelId
            );
        assertEq(upgrade.fields.connection_hops.length, 0);
    }

    function _testChannelUpgrade(
        uint256 nextAppVersion,
        HandshakeFlow memory flow
    ) internal {
        (
            ChannelInfo memory channelA,
            ChannelInfo memory channelB
        ) = _createMockAppLocalhostChannel(
                Channel.Order.ORDER_ORDERED,
                mockVersion(APP_VERSION_1)
            );

        ChannelInfo memory channel0;
        ChannelInfo memory channel1;
        {
            Channel.Order proposedOrder;
            (channel0, channel1) = (channelA, channelB);
            proposedOrder = Channel.Order.ORDER_ORDERED;

            {
                string memory nextVersion = mockVersion(nextAppVersion);

                (
                    string memory newConnectionId0,
                    string memory newConnectionId1
                ) = ibcHandler.createLocalhostConnection();
                handshakeUpgrade(
                    channel0,
                    channel1,
                    validProposals(
                        proposedOrder,
                        newConnectionId0,
                        newConnectionId1,
                        nextVersion
                    ),
                    flow
                );
                (Channel.Data memory channelData0, ) = ibcHandler.getChannel(
                    channel0.portId,
                    channel0.channelId
                );
                (Channel.Data memory channelData1, ) = ibcHandler.getChannel(
                    channel1.portId,
                    channel1.channelId
                );
                assertEq(
                    channelData0.connection_hops[0],
                    newConnectionId0,
                    "connection hop mismatch"
                );
                assertEq(
                    channelData1.connection_hops[0],
                    newConnectionId1,
                    "connection hop mismatch"
                );
                assertEq(
                    uint8(channelData0.ordering),
                    uint8(proposedOrder),
                    "ordering mismatch"
                );
                assertEq(
                    uint8(channelData1.ordering),
                    uint8(proposedOrder),
                    "ordering mismatch"
                );
                assertEq(channelData0.version, nextVersion, "version mismatch");
                assertEq(channelData1.version, nextVersion, "version mismatch");
            }
        }

        /* Upgrade App */

        {
            address newBridgeImpl = address(
                new MockChannelUpgradeBridge(nextAppVersion + 1, PORT, 2)
            );

            {
                bytes memory initialData = _mockBridgeInitializeData(
                    nextAppVersion + 1,
                    channel0.channelId
                );
                vm.expectRevert(
                    abi.encodeWithSelector(
                        ITokiErrors.TokiInvalidAppVersion.selector,
                        nextAppVersion + 1,
                        nextAppVersion
                    )
                );
                UUPSUpgradeable(proxy).upgradeToAndCall(
                    newBridgeImpl,
                    initialData
                );
            }
            {
                bytes memory initialData = _mockBridgeInitializeData(
                    nextAppVersion + 1,
                    channel1.channelId
                );
                vm.expectRevert(
                    abi.encodeWithSelector(
                        ITokiErrors.TokiInvalidAppVersion.selector,
                        nextAppVersion + 1,
                        nextAppVersion
                    )
                );
                UUPSUpgradeable(proxyCounterparty).upgradeToAndCall(
                    newBridgeImpl,
                    initialData
                );
            }
        }

        address newBridgeImpl = address(
            new MockChannelUpgradeBridge(nextAppVersion, PORT, 2)
        );
        UUPSUpgradeable(proxy).upgradeToAndCall(
            newBridgeImpl,
            _mockBridgeInitializeData(nextAppVersion, channel0.channelId)
        );
        UUPSUpgradeable(proxyCounterparty).upgradeToAndCall(
            newBridgeImpl,
            _mockBridgeInitializeData(nextAppVersion, channel1.channelId)
        );
        assertEq(
            IAppVersion(proxy).appVersion(),
            nextAppVersion,
            "app version mismatch"
        );
        assertEq(
            IAppVersion(proxyCounterparty).appVersion(),
            nextAppVersion,
            "counterparty app version mismatch"
        );
    }

    function _bridgeInitializeData(
        uint256 appVersion
    ) internal returns (bytes memory) {
        return
            abi.encodeCall(
                Bridge.initialize,
                Bridge.InitializeParam(
                    address(ibcHandler),
                    POOL_REPOSITORY,
                    ESCROW,
                    TOKEN_PRICE_ORACLE,
                    FEE_OWNER,
                    RELAYER_FEE_CALCULATOR,
                    address(new BridgeFallback(appVersion, PORT)),
                    address(new BridgeChannelUpgradeFallback(appVersion, PORT)),
                    10000,
                    5000,
                    2500
                )
            );
    }

    function _mockBridgeInitializeData(
        uint256 appVersion,
        string memory channel
    ) internal returns (bytes memory) {
        string[] memory channelIds = new string[](1);
        channelIds[0] = channel;
        return
            abi.encodeCall(
                MockChannelUpgradeBridge.upgrade,
                (
                    address(new BridgeFallback(appVersion, PORT)),
                    address(new BridgeChannelUpgradeFallback(appVersion, PORT)),
                    channelIds
                )
            );
    }

    function _createMockAppLocalhostChannel(
        Channel.Order ordering,
        string memory version
    ) internal returns (ChannelInfo memory, ChannelInfo memory) {
        return
            createMockAppLocalhostChannel(
                ordering,
                PORT,
                PORT_COUNTERPARTY,
                version
            );
    }

    function mockVersion(uint256 version) private pure returns (string memory) {
        return string(abi.encodePacked("toki-", Strings.toString(version)));
    }
}
