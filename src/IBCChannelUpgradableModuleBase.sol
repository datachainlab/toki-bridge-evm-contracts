// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

// original: https://github.com/hyperledger-labs/yui-ibc-solidity/blob/ca7a56c85749b83d5fb35aae7cd7e0b07e655b61/contracts/apps/commons/IBCChannelUpgradableModule.sol

import {Channel, UpgradeFields, Timeout} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/Channel.sol";
import {IIBCHandler} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/25-handler/IIBCHandler.sol";
import {IIBCModuleUpgrade} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/26-router/IIBCModuleUpgrade.sol";
import {AppBase} from "@hyperledger-labs/yui-ibc-solidity/contracts/apps/commons/IBCAppBase.sol";
import {IIBCChannelUpgradableModule, IIBCChannelUpgradableModuleErrors} from "@hyperledger-labs/yui-ibc-solidity/contracts/apps/commons/IIBCChannelUpgradableModule.sol";

/* solhint-disable ordering */
// slither-disable-start unused-return
abstract contract IBCChannelUpgradableModuleBase is
    AppBase,
    IIBCModuleUpgrade,
    IIBCChannelUpgradableModule,
    IIBCChannelUpgradableModuleErrors
{
    // ------------------- Storage ------------------- //

    /// @custom:storage-location erc7201:toki.channelUpgradeableModule
    struct ChannelUpgradeableModuleStorage {
        /**
         * @dev Proposed upgrades for each channel
         */
        mapping(string portId => mapping(string channelId => UpgradeProposal)) upgradeProposals;
        /**
         * @dev Allowed transitions for each upgrade sequence
         */
        mapping(string portId => mapping(string channelId => mapping(uint64 upgradeSequence => AllowedTransition))) allowedTransitions;
    }

    // keccak256(abi.encode(uint256(keccak256("toki.channelUpgradeableModule")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 internal constant CHANNEL_UPGRADEABLE_MODULE_STORAGE_SLOT =
        0x784871d954589ac15c9f4e61a698addf130c523768e7d96ff3c2aea544434200;

    // ------------------- Modifiers ------------------- //

    /**
     * @dev Throws if the sender is not an authorized upgrader
     * @param portId Port identifier
     * @param channelId Channel identifier
     */
    modifier onlyAuthorizedUpgrader(
        string calldata portId,
        string calldata channelId
    ) {
        if (!_isAuthorizedUpgrader(portId, channelId, _msgSender())) {
            revert IBCChannelUpgradableModuleUnauthorizedUpgrader();
        }
        _;
    }

    // ------------------- Public Functions ------------------- //

    /**
     * @dev See {IIBCChannelUpgradableModule-getUpgradeProposal}
     */
    function getUpgradeProposal(
        string calldata portId,
        string calldata channelId
    ) public view virtual override returns (UpgradeProposal memory) {
        return
            getChannelUpgradeableModuleStorage().upgradeProposals[portId][
                channelId
            ];
    }

    /**
     * @dev See {IIBCChannelUpgradableModule-proposeUpgrade}
     */
    function proposeUpgrade(
        string calldata portId,
        string calldata channelId,
        UpgradeFields.Data calldata upgradeFields,
        Timeout.Data calldata timeout
    ) public virtual override onlyAuthorizedUpgrader(portId, channelId) {
        if (
            timeout.height.revision_number == 0 &&
            timeout.height.revision_height == 0 &&
            timeout.timestamp == 0
        ) {
            revert IBCChannelUpgradableModuleInvalidTimeout();
        }
        if (
            upgradeFields.ordering == Channel.Order.ORDER_NONE_UNSPECIFIED ||
            upgradeFields.connection_hops.length == 0
        ) {
            revert IBCChannelUpgradableModuleInvalidConnectionHops();
        }
        (Channel.Data memory channel, bool found) = IIBCHandler(ibcAddress())
            .getChannel(portId, channelId);
        if (!found) {
            revert IBCChannelUpgradableModuleChannelNotFound();
        }
        UpgradeProposal storage upgrade = getChannelUpgradeableModuleStorage()
            .upgradeProposals[portId][channelId];
        if (upgrade.fields.connection_hops.length != 0) {
            // re-proposal is allowed as long as it does not transition to FLUSHING state yet
            if (channel.state != Channel.State.STATE_OPEN) {
                revert IBCChannelUpgradableModuleCannotOverwriteUpgrade();
            }
        }
        upgrade.fields = upgradeFields;
        upgrade.timeout = timeout;
    }

    /**
     * @dev See {IIBCChannelUpgradableModule-allowTransitionToFlushComplete}
     */
    function allowTransitionToFlushComplete(
        string calldata portId,
        string calldata channelId,
        uint64 upgradeSequence
    ) public virtual override onlyAuthorizedUpgrader(portId, channelId) {
        ChannelUpgradeableModuleStorage
            storage $ = getChannelUpgradeableModuleStorage();
        UpgradeProposal storage upgrade = $.upgradeProposals[portId][channelId];
        if (upgrade.fields.connection_hops.length == 0) {
            revert IBCChannelUpgradableModuleUpgradeNotFound();
        }
        (, bool found) = IIBCHandler(ibcAddress()).getChannelUpgrade(
            portId,
            channelId
        );
        if (!found) {
            revert IBCChannelUpgradableModuleUpgradeNotFound();
        }
        (Channel.Data memory channel, ) = IIBCHandler(ibcAddress()).getChannel(
            portId,
            channelId
        );
        if (channel.state != Channel.State.STATE_FLUSHING) {
            revert IBCChannelUpgradableModuleChannelNotFlushingState(
                channel.state
            );
        }
        if (channel.upgrade_sequence != upgradeSequence) {
            revert IBCChannelUpgradableModuleSequenceMismatch(
                channel.upgrade_sequence
            );
        }
        $
        .allowedTransitions[portId][channelId][upgradeSequence]
            .flushComplete = true;
    }

    /**
     * @dev See {IIBCChannelUpgradableModule-removeUpgradeProposal}
     */
    function removeUpgradeProposal(
        string calldata portId,
        string calldata channelId
    ) public virtual onlyAuthorizedUpgrader(portId, channelId) {
        _removeUpgradeProposal(portId, channelId);
    }

    // ------------------- IIBCModuleUpgrade ------------------- //

    /**
     * @dev See {IIBCModuleUpgrade-isAuthorizedUpgrader}
     */
    function isAuthorizedUpgrader(
        string calldata portId,
        string calldata channelId,
        address msgSender
    ) public view virtual override returns (bool) {
        return _isAuthorizedUpgrader(portId, channelId, msgSender);
    }

    /**
     * @dev See {IIBCModuleUpgrade-canTransitionToFlushComplete}
     */
    function canTransitionToFlushComplete(
        string calldata portId,
        string calldata channelId,
        uint64 upgradeSequence,
        address
    ) public view virtual override returns (bool) {
        return
            getChannelUpgradeableModuleStorage()
            .allowedTransitions[portId][channelId][upgradeSequence]
                .flushComplete;
    }

    /**
     * @dev See {IIBCModuleUpgrade-getUpgradeTimeout}
     */
    function getUpgradeTimeout(
        string calldata portId,
        string calldata channelId
    ) public view virtual override returns (Timeout.Data memory) {
        UpgradeProposal storage proposal = getChannelUpgradeableModuleStorage()
            .upgradeProposals[portId][channelId];
        if (proposal.fields.connection_hops.length == 0) {
            revert IBCChannelUpgradableModuleUpgradeNotFound();
        }
        return proposal.timeout;
    }

    /**
     * @dev See {IIBCModuleUpgrade-onChanUpgradeInit}
     */
    function onChanUpgradeInit(
        string calldata portId,
        string calldata channelId,
        uint64,
        UpgradeFields.Data calldata proposedUpgradeFields
    ) public view virtual override onlyIBC returns (string memory version) {
        UpgradeProposal storage upgrade = getChannelUpgradeableModuleStorage()
            .upgradeProposals[portId][channelId];
        if (upgrade.fields.connection_hops.length == 0) {
            revert IBCChannelUpgradableModuleUpgradeNotFound();
        }
        if (!equals(upgrade.fields, proposedUpgradeFields)) {
            revert IBCChannelUpgradableModuleInvalidUpgrade();
        }
        return proposedUpgradeFields.version;
    }

    /**
     * @dev See {IIBCModuleUpgrade-onChanUpgradeTry}
     */
    function onChanUpgradeTry(
        string calldata portId,
        string calldata channelId,
        uint64,
        UpgradeFields.Data calldata proposedUpgradeFields
    ) public view virtual override onlyIBC returns (string memory version) {
        UpgradeProposal storage upgrade = getChannelUpgradeableModuleStorage()
            .upgradeProposals[portId][channelId];
        if (upgrade.fields.connection_hops.length == 0) {
            revert IBCChannelUpgradableModuleUpgradeNotFound();
        }
        if (!equals(upgrade.fields, proposedUpgradeFields)) {
            revert IBCChannelUpgradableModuleInvalidUpgrade();
        }
        return proposedUpgradeFields.version;
    }

    /**
     * @dev See {IIBCModuleUpgrade-onChanUpgradeAck}
     */
    function onChanUpgradeAck(
        string calldata,
        string calldata,
        uint64,
        string calldata counterpartyVersion
    ) public view virtual override onlyIBC {}

    /**
     * @dev See {IIBCModuleUpgrade-onChanUpgradeOpen}
     */
    function onChanUpgradeOpen(
        string calldata portId,
        string calldata channelId,
        uint64 upgradeSequence
    ) public virtual override onlyIBC {
        ChannelUpgradeableModuleStorage
            storage $ = getChannelUpgradeableModuleStorage();
        delete $.upgradeProposals[portId][channelId];
        delete $.allowedTransitions[portId][channelId][upgradeSequence];
    }

    /**
     * @dev See {IERC165-supportsInterface}
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            super.supportsInterface(interfaceId) ||
            interfaceId == type(IIBCModuleUpgrade).interfaceId ||
            interfaceId == type(IIBCChannelUpgradableModule).interfaceId;
    }

    // ------------------- Internal Functions ------------------- //

    /**
     * @dev Returns whether the given address is authorized to upgrade the channel
     */
    function _isAuthorizedUpgrader(
        string calldata portId,
        string calldata channelId,
        address msgSender
    ) internal view virtual returns (bool);

    /**
     * @dev Removes the proposed upgrade for the given port and channel
     */
    function _removeUpgradeProposal(
        string calldata portId,
        string calldata channelId
    ) internal {
        ChannelUpgradeableModuleStorage
            storage $ = getChannelUpgradeableModuleStorage();
        if (
            $
                .upgradeProposals[portId][channelId]
                .fields
                .connection_hops
                .length == 0
        ) {
            revert IBCChannelUpgradableModuleUpgradeNotFound();
        }
        IIBCHandler handler = IIBCHandler(ibcAddress());
        (, bool found) = handler.getChannelUpgrade(portId, channelId);
        if (found) {
            Channel.Data memory channel;
            (channel, found) = handler.getChannel(portId, channelId);
            if (!found) {
                revert IBCChannelUpgradableModuleChannelNotFound();
            }
            if (channel.state != Channel.State.STATE_OPEN) {
                revert IBCChannelUpgradableModuleCannotRemoveInProgressUpgrade();
            }
        }
        delete $.upgradeProposals[portId][channelId];
    }

    /**
     * @dev Compares two UpgradeFields structs
     */
    function equals(
        UpgradeFields.Data storage a,
        UpgradeFields.Data calldata b
    ) internal view returns (bool) {
        if (a.ordering != b.ordering) {
            return false;
        }
        if (a.connection_hops.length != b.connection_hops.length) {
            return false;
        }
        for (uint256 i = 0; i < a.connection_hops.length; i++) {
            if (
                keccak256(abi.encodePacked(a.connection_hops[i])) !=
                keccak256(abi.encodePacked(b.connection_hops[i]))
            ) {
                return false;
            }
        }
        return
            keccak256(abi.encodePacked(a.version)) ==
            keccak256(abi.encodePacked(b.version));
    }

    function getChannelUpgradeableModuleStorage()
        internal
        pure
        returns (ChannelUpgradeableModuleStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := CHANNEL_UPGRADEABLE_MODULE_STORAGE_SLOT
        }
    }
}
// slither-disable-end unused-return
/* solhint-enable ordering */
