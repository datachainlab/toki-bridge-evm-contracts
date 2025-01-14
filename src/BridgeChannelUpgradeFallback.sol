// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

//import "@hyperledger-labs/yui-ibc-solidity/contracts/apps/commons/IBCChannelUpgradableModule.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import {ShortString, ShortStrings} from "@openzeppelin/contracts/utils/ShortStrings.sol";
import "./interfaces/IAppVersion.sol";
import "./VersionStringValidator.sol";
import "./BridgeStore.sol";
import "./IBCChannelUpgradableModuleBase.sol";

contract BridgeChannelUpgradeFallback is
    BridgeStore,
    IAppVersion,
    IBCChannelUpgradableModuleBase,
    VersionStringValidator,
    AccessControlUpgradeable
{
    using ShortStrings for string;
    using ShortStrings for ShortString;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint256 appVersion_, string memory port) {
        APP_VERSION = appVersion_;
        PORT = port.toShortString();
    }

    /* solhint-disable ordering */
    /**
     * @dev See {IIBCContractUpgradableModule-onChanUpgradeInit}
     */
    function onChanUpgradeInit(
        string calldata portId,
        string calldata channelId,
        uint64 upgradeSequence,
        UpgradeFields.Data calldata proposedUpgradeFields
    ) public view virtual override onlyIBC returns (string memory version) {
        version = super.onChanUpgradeInit(
            portId,
            channelId,
            upgradeSequence,
            proposedUpgradeFields
        );
        // check if the proposed new version is valid
        // solhint-disable-next-line no-unused-vars
        (bool success, uint256 _newAppVersion) = validateVersion(version);
        if (!success) {
            revert TokiInvalidProposedVersion(version);
        }
    }

    /**
     * @dev See {IIBCContractUpgradableModule-onChanUpgradeTry}
     */
    function onChanUpgradeTry(
        string calldata portId,
        string calldata channelId,
        uint64 upgradeSequence,
        UpgradeFields.Data calldata proposedUpgradeFields
    ) public view virtual override onlyIBC returns (string memory version) {
        version = super.onChanUpgradeTry(
            portId,
            channelId,
            upgradeSequence,
            proposedUpgradeFields
        );
        // check if the proposed new version is valid
        // solhint-disable-next-line no-unused-vars
        (bool success, uint256 _newAppVersion) = validateVersion(version);
        if (!success) {
            revert TokiInvalidProposedVersion(version);
        }
    }

    function onChanUpgradeOpen(
        string calldata portId,
        string calldata channelId,
        uint64 upgradeSequence
    ) public virtual override onlyIBC {
        super.onChanUpgradeOpen(portId, channelId, upgradeSequence);

        (Channel.Data memory channel, bool found) = IIBCHandler(ibcAddress())
            .getChannel(portId, channelId);
        if (!found) {
            revert TokiChannelNotFound(portId, channelId);
        }

        (bool success, uint256 version) = validateVersion(channel.version);
        if (!success) {
            revert TokiInvalidProposedVersion(channel.version);
        }

        BridgeStorage storage $ = getBridgeStorage();
        $.channelInfos[channelId].appVersion = version;
    }
    /* solhint-enable ordering */

    function ibcAddress() public view virtual override returns (address) {
        return address(getBridgeStorage().ics04SendPacket);
    }

    /**
     * @notice This contract is basically a fallback contract, so this function is not expected to be called.
     * @param interfaceId The interface identifier, as specified in ERC-165.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(AccessControlUpgradeable, IBCChannelUpgradableModuleBase)
        returns (bool)
    {
        return IBCChannelUpgradableModuleBase.supportsInterface(interfaceId);
    }

    /**
     * @dev This is for Bridge to check the version of the contract.
     */
    function appVersion() external view returns (uint256) {
        return APP_VERSION;
    }

    /**
     * @dev See {IIBCModuleUpgrade-isAuthorizedUpgrader}
     */
    function _isAuthorizedUpgrader(
        string calldata /*portId*/,
        string calldata /*channelId*/,
        address msgSender
    ) internal view virtual override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msgSender);
    }

    function _msgSender()
        internal
        view
        virtual
        override(Context, ContextUpgradeable)
        returns (address)
    {
        return super._msgSender();
    }

    function _msgData()
        internal
        view
        virtual
        override(Context, ContextUpgradeable)
        returns (bytes calldata)
    {
        return super._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        virtual
        override(Context, ContextUpgradeable)
        returns (uint256)
    {
        return super._contextSuffixLength();
    }
}
