// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "./LCPClientUpgradeable.sol";
import {IbcLightclientsLcpV1ClientState} from "lcp-solidity/contracts/proto/ibc/lightclients/lcp/v1/LCP.sol";
import {AVRValidator} from "lcp-solidity/contracts/AVRValidator.sol";
import {Height} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/Client.sol";
import {IBCHeight} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/02-client/IBCHeight.sol";
import {IIBCClient} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/02-client/IIBCClient.sol";

contract RecoveredLCPClientUpgradeable is LCPClientUpgradeable {
    struct NewClientState {
        string clientId;
        bytes mrenclave;
        uint64 keyExpiration;
        string[] allowedQuoteStatuses;
        string[] allowedAdvisoryIds;
    }

    struct NewConsensusState {
        Height.Data height;
        ConsensusState consensusState;
    }

    // A unique version is assigned to the implementation contract.
    // To ensure the initialization process is only allowed once, it is checked by the reinitializer modifier.
    uint64 public immutable RECOVERED_VERSION;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address ibcHandler,
        bool developmentMode,
        uint64 recoveredVersion
    ) LCPClientUpgradeable(ibcHandler, developmentMode) {
        RECOVERED_VERSION = recoveredVersion;
    }

    /**
     * @dev `upgrade` should only be called once through UUPSUpgradeable.upgradeToAndCall.
     *
     * WARNING: If not called from upgradeToAndCall, be aware that anyone could call the upgrade function.
     */
    function upgrade(
        NewClientState memory newClientState,
        NewConsensusState memory newConsensusState
    ) external reinitializer(RECOVERED_VERSION) {
        ClientStorage storage clientStorage = clientStorages[
            newClientState.clientId
        ];
        IbcLightclientsLcpV1ClientState.Data storage clientState = clientStorage
            .clientState;

        if (clientState.frozen) {
            revert LCPClientClientStateFrozen();
        }

        Height.Data memory latestHeight = Height.Data(
            clientState.latest_height.revision_number,
            clientState.latest_height.revision_height
        );
        if (
            IBCHeight.isZero(latestHeight) ||
            IBCHeight.gte(latestHeight, newConsensusState.height)
        ) {
            revert LCPClientClientStateInvalidLatestHeight();
        }

        // Validate ClientState
        if (newClientState.mrenclave.length != 32) {
            revert LCPClientClientStateInvalidMrenclaveLength();
        }
        if (newClientState.keyExpiration == 0) {
            revert LCPClientClientStateInvalidKeyExpiration();
        }

        // Validate ConsensusState
        if (newConsensusState.consensusState.timestamp == 0) {
            revert LCPClientConsensusStateInvalidTimestamp();
        }

        // A stateId with zero length or zero value is invalid.
        if (newConsensusState.consensusState.stateId == bytes32(0)) {
            revert LCPClientConsensusStateInvalidStateId();
        }

        // Upgrade ClientState
        clientState.mrenclave = newClientState.mrenclave;
        clientState.key_expiration = newClientState.keyExpiration;

        // Delete & insert clientStorage.allowedStatuses
        // The first and second for loops remove old values from allowedStatuses.
        // The third and fourth for loops insert new values.
        for (
            uint256 i = 0;
            i < clientState.allowed_quote_statuses.length;
            i++
        ) {
            delete clientStorage.allowedStatuses.allowedQuoteStatuses[
                clientState.allowed_quote_statuses[i]
            ];
        }
        for (uint256 i = 0; i < clientState.allowed_advisory_ids.length; i++) {
            delete clientStorage.allowedStatuses.allowedAdvisories[
                clientState.allowed_advisory_ids[i]
            ];
        }

        clientState.allowed_quote_statuses = newClientState
            .allowedQuoteStatuses;
        clientState.allowed_advisory_ids = newClientState.allowedAdvisoryIds;

        for (
            uint256 i = 0;
            i < clientState.allowed_quote_statuses.length;
            i++
        ) {
            clientStorage.allowedStatuses.allowedQuoteStatuses[
                clientState.allowed_quote_statuses[i]
            ] = AVRValidator.FLAG_ALLOWED;
        }
        for (uint256 i = 0; i < clientState.allowed_advisory_ids.length; i++) {
            clientStorage.allowedStatuses.allowedAdvisories[
                clientState.allowed_advisory_ids[i]
            ] = AVRValidator.FLAG_ALLOWED;
        }

        // Upgrade ConsensusState and latestHeight of ClientState
        clientState.latest_height.revision_number = newConsensusState
            .height
            .revision_number;
        clientState.latest_height.revision_height = newConsensusState
            .height
            .revision_height;
        uint128 height = IBCHeight.toUint128(newConsensusState.height);
        clientStorage.consensusStates[height] = newConsensusState
            .consensusState;

        // Update commitments
        Height.Data[] memory heights = new Height.Data[](1);
        heights[0] = newConsensusState.height;
        IIBCClient(ibcHandler).updateClientCommitments(
            newClientState.clientId,
            heights
        );
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}
