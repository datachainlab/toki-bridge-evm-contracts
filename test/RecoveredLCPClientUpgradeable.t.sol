// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ILCPClientErrors} from "lcp-solidity/contracts/ILCPClientErrors.sol";
import {LCPClientBase} from "lcp-solidity/contracts/LCPClientBase.sol";
import {LCPProtoMarshaler} from "lcp-solidity/contracts/LCPProtoMarshaler.sol";
import {IbcLightclientsLcpV1ClientState} from "lcp-solidity/contracts/proto/ibc/lightclients/lcp/v1/LCP.sol";

import {LCPClientUpgradeable} from "../src/clients/LCPClientUpgradeable.sol";
import {RecoveredLCPClientUpgradeable} from "../src/clients/RecoveredLCPClientUpgradeable.sol";
import "../src/mocks/MockIBCClient.sol";

contract MockLCPClientUpgradeable is LCPClientUpgradeable {
    constructor(
        address ibcHandler,
        bool developmentMode
    ) LCPClientUpgradeable(ibcHandler, developmentMode) {}

    function updateClientState(
        string calldata clientId,
        IbcLightclientsLcpV1ClientState.Data calldata clientState_
    ) public {
        clientStorages[clientId].clientState = clientState_;
    }
}

contract RecoveredLCPClientUpgradeableTest is Test {
    MockLCPClientUpgradeable public t;
    RecoveredLCPClientUpgradeable.NewClientState public newClientState;
    RecoveredLCPClientUpgradeable.NewConsensusState public newConsensusState;

    function setUp() public {
        // Specify within the validity period of the root CA.
        vm.warp(2524607999);

        address impl = address(
            new MockLCPClientUpgradeable(makeAddr("ibcHandler"), true)
        );
        bytes memory rootCACert = vm.readFileBinary(
            "./test/testdata/simulation_rootca.der"
        );
        bytes memory data = abi.encodeCall(
            LCPClientUpgradeable.initialize,
            rootCACert
        );
        address proxy = address(new ERC1967Proxy(impl, data));
        t = MockLCPClientUpgradeable(proxy);

        IbcLightclientsLcpV1ClientState.Data memory clientState;
        clientState.mrenclave = "dummy";

        Height.Data memory initialHeight = Height.Data(1, 500);
        clientState.latest_height = initialHeight;
        t.updateClientState("client-0", clientState);

        string[] memory allowedQuoteStatuses = new string[](1);
        allowedQuoteStatuses[0] = "GROUP_OUT_OF_DATE";
        string[] memory allowedAdvisoryIds = new string[](1);
        allowedAdvisoryIds[0] = "INTEL-SA-00219";
        string memory clientId = "client-0";
        bytes
            memory mrenclave = hex"d5097b7629c003c1ff46581a46401d43f441dab919340172896ce9d50a35f0ad";
        uint64 keyExpiration = 1700000000;

        newClientState = RecoveredLCPClientUpgradeable.NewClientState(
            clientId,
            mrenclave,
            keyExpiration,
            allowedQuoteStatuses,
            allowedAdvisoryIds
        );

        Height.Data memory height = Height.Data(1, 1000);
        bytes32 stateId = 0xd0a10c3f3049a8e0e07a7b807c752caadcb305e9c9a7862257123241fdd0c19e;
        uint64 timestamp = 1750000000;
        newConsensusState = RecoveredLCPClientUpgradeable.NewConsensusState(
            height,
            LCPClientBase.ConsensusState(stateId, timestamp)
        );
    }

    function testFuzzUpgradeToAndCall(uint64 recoveredVersion) public {
        vm.assume(recoveredVersion > 1);

        MockIBCClient newIBCClient = new MockIBCClient();

        address newImpl = address(
            new RecoveredLCPClientUpgradeable(
                address(newIBCClient),
                true,
                recoveredVersion
            )
        );

        bytes memory callData = abi.encodeCall(
            RecoveredLCPClientUpgradeable.upgrade,
            (newClientState, newConsensusState)
        );

        vm.expectEmit(address(t));
        emit IERC1967.Upgraded(newImpl);
        vm.expectEmit(address(newIBCClient));
        emit MockIBCClient.UpdateClientCommitments();
        t.upgradeToAndCall(newImpl, callData);

        (bytes memory clientStateByte, bool isClientState) = t.getClientState(
            newClientState.clientId
        );
        assertTrue(isClientState);
        IbcLightclientsLcpV1ClientState.Data
            memory clientState = LCPProtoMarshaler.unmarshalClientState(
                clientStateByte
            );
        assertEq(clientState.mrenclave, newClientState.mrenclave);
        assertEq(clientState.key_expiration, newClientState.keyExpiration);
        assertEq(clientState.frozen, false);
        assertEq(clientState.allowed_quote_statuses.length, 1);
        assertEq(
            clientState.allowed_quote_statuses[0],
            newClientState.allowedQuoteStatuses[0]
        );
        assertEq(clientState.allowed_advisory_ids.length, 1);
        assertEq(
            clientState.allowed_advisory_ids[0],
            newClientState.allowedAdvisoryIds[0]
        );

        assertEq(
            clientState.latest_height.revision_number,
            newConsensusState.height.revision_number
        );
        assertEq(
            clientState.latest_height.revision_height,
            newConsensusState.height.revision_height
        );
    }

    function testUpgradeToAndCallRevertsWhenSenderIsNotOwner() public {
        address newImpl = address(
            new LCPClientUpgradeable(makeAddr("newIBCHandler"), true)
        );

        bytes memory callData = abi.encodeCall(
            RecoveredLCPClientUpgradeable.upgrade,
            (newClientState, newConsensusState)
        );

        address notOwner = makeAddr("NotOwner");
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                notOwner
            )
        );

        vm.prank(notOwner);
        t.upgradeToAndCall(newImpl, callData);
    }

    function testUpgradeWhenSenderIsOwner() public {
        MockIBCClient newIBCClient = new MockIBCClient();
        address newImpl = address(
            new RecoveredLCPClientUpgradeable(address(newIBCClient), true, 2)
        );

        vm.expectEmit(address(t));
        emit IERC1967.Upgraded(newImpl);
        t.upgradeToAndCall(newImpl, "");

        RecoveredLCPClientUpgradeable client = RecoveredLCPClientUpgradeable(
            address(t)
        );

        client.upgrade(newClientState, newConsensusState);
    }

    function testUpgradeCallRevertsWhenSenderIsNotOwner() public {
        MockIBCClient newIBCClient = new MockIBCClient();
        address newImpl = address(
            new RecoveredLCPClientUpgradeable(address(newIBCClient), true, 2)
        );

        vm.expectEmit(address(t));
        emit IERC1967.Upgraded(newImpl);
        t.upgradeToAndCall(newImpl, "");

        RecoveredLCPClientUpgradeable client = RecoveredLCPClientUpgradeable(
            address(t)
        );

        address notOwner = makeAddr("NotOwner");
        vm.prank(notOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                notOwner
            )
        );
        client.upgrade(newClientState, newConsensusState);
    }

    function testUpgradeToAndCallRevertsWhenContractHasAlreadyUpgraded()
        public
    {
        MockIBCClient newIBCClient = new MockIBCClient();

        address newImpl = address(
            new RecoveredLCPClientUpgradeable(address(newIBCClient), true, 2)
        );

        bytes memory callData = abi.encodeCall(
            RecoveredLCPClientUpgradeable.upgrade,
            (newClientState, newConsensusState)
        );

        t.upgradeToAndCall(newImpl, callData);

        vm.expectRevert(
            abi.encodeWithSelector(Initializable.InvalidInitialization.selector)
        );
        t.upgradeToAndCall(newImpl, callData);
    }

    function testUpgradeToAndCallRevertsWhenLatestHeightIsZero() public {
        // Set latestHeight to zero.
        bytes32 latestHeightSlot = bytes32(
            uint256(keccak256(abi.encodePacked("client-0", uint256(0)))) + 2
        );
        uint64 revisionNumber = 0;
        uint64 revisionHeight = 0;
        uint256 latestHeight = (uint256(revisionHeight) << 64) |
            uint256(revisionNumber);
        vm.store(address(t), latestHeightSlot, bytes32(latestHeight));

        MockIBCClient newIBCClient = new MockIBCClient();

        address newImpl = address(
            new RecoveredLCPClientUpgradeable(address(newIBCClient), true, 2)
        );

        bytes memory callData = abi.encodeCall(
            RecoveredLCPClientUpgradeable.upgrade,
            (newClientState, newConsensusState)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ILCPClientErrors
                    .LCPClientClientStateInvalidLatestHeight
                    .selector
            )
        );
        t.upgradeToAndCall(newImpl, callData);
    }

    function testUpgradeToAndCallRevertsWhenNewHeightIsLessThanLatestHeight()
        public
    {
        MockIBCClient newIBCClient = new MockIBCClient();

        address newImpl = address(
            new RecoveredLCPClientUpgradeable(address(newIBCClient), true, 2)
        );

        bytes memory callData = abi.encodeCall(
            RecoveredLCPClientUpgradeable.upgrade,
            (newClientState, newConsensusState)
        );

        t.upgradeToAndCall(newImpl, callData);

        // Upgrade to a new implementation contract at same parameters.
        // However, the upgrade fails because the latestHeight conflicts.
        newImpl = address(
            new RecoveredLCPClientUpgradeable(
                makeAddr("newIBCHandler"),
                true,
                3
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ILCPClientErrors
                    .LCPClientClientStateInvalidLatestHeight
                    .selector
            )
        );
        t.upgradeToAndCall(newImpl, callData);
    }

    function testUpgradeToAndCallRevertsWhenMrenclaveIsInvalid() public {
        address newImpl = address(
            new RecoveredLCPClientUpgradeable(
                makeAddr("newIBCHandler"),
                true,
                2
            )
        );

        newClientState.mrenclave = hex"abcdef"; // invalid length of mrenclave.

        bytes memory callData = abi.encodeCall(
            RecoveredLCPClientUpgradeable.upgrade,
            (newClientState, newConsensusState)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ILCPClientErrors
                    .LCPClientClientStateInvalidMrenclaveLength
                    .selector
            )
        );
        t.upgradeToAndCall(newImpl, callData);
    }

    function testUpgradeToAndCallRevertsWhenKeyExpirationIsInvalid() public {
        address newImpl = address(
            new RecoveredLCPClientUpgradeable(
                makeAddr("newIBCHandler"),
                true,
                2
            )
        );

        newClientState.keyExpiration = 0; // invalid keyExpiration.

        bytes memory callData = abi.encodeCall(
            RecoveredLCPClientUpgradeable.upgrade,
            (newClientState, newConsensusState)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ILCPClientErrors
                    .LCPClientClientStateInvalidKeyExpiration
                    .selector
            )
        );
        t.upgradeToAndCall(newImpl, callData);
    }

    function testUpgradeToAndCallRevertsWhenTimestampIsInvalid() public {
        address newImpl = address(
            new RecoveredLCPClientUpgradeable(
                makeAddr("newIBCHandler"),
                true,
                2
            )
        );

        newConsensusState.consensusState.timestamp = 0; // invalid timestamp.

        bytes memory callData = abi.encodeCall(
            RecoveredLCPClientUpgradeable.upgrade,
            (newClientState, newConsensusState)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ILCPClientErrors
                    .LCPClientConsensusStateInvalidTimestamp
                    .selector
            )
        );
        t.upgradeToAndCall(newImpl, callData);
    }

    function testUpgradeToAndCallRevertsWhenStateIdIsInvalid() public {
        address newImpl = address(
            new RecoveredLCPClientUpgradeable(
                makeAddr("newIBCHandler"),
                true,
                2
            )
        );

        newConsensusState.consensusState.stateId = bytes32(0); // invalid length of stateId.

        bytes memory callData = abi.encodeCall(
            RecoveredLCPClientUpgradeable.upgrade,
            (newClientState, newConsensusState)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ILCPClientErrors.LCPClientConsensusStateInvalidStateId.selector
            )
        );
        t.upgradeToAndCall(newImpl, callData);
    }

    function testUpgradeToAndCallRevertsWhenClientIsFrozen() public {
        (bytes memory clientStateByte, ) = t.getClientState("client-0");
        IbcLightclientsLcpV1ClientState.Data
            memory clientState = LCPProtoMarshaler.unmarshalClientState(
                clientStateByte
            );
        clientState.frozen = true;
        t.updateClientState("client-0", clientState);

        MockIBCClient newIBCClient = new MockIBCClient();

        address newImpl = address(
            new RecoveredLCPClientUpgradeable(address(newIBCClient), true, 2)
        );

        bytes memory callData = abi.encodeCall(
            RecoveredLCPClientUpgradeable.upgrade,
            (newClientState, newConsensusState)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ILCPClientErrors.LCPClientClientStateFrozen.selector
            )
        );
        t.upgradeToAndCall(newImpl, callData);
    }
}
