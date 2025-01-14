// SPDX-License-Identifier: BUSL-1.1
// solhint-disable-next-line one-contract-per-file
pragma solidity 0.8.28;

import "../Bridge.sol";

contract MockUpgradeBridge is Bridge {
    constructor(
        uint256 appVersion_,
        string memory port
    ) Bridge(appVersion_, port) {}

    // for reducing deployment gas
    function initialize(
        InitializeParam memory param
    ) public override initializer {}

    function upgrade(
        address defaultFallback_,
        address channelUpgradeFallback_
    ) public virtual reinitializer(2) {
        _checkFallbackAppVersion(defaultFallback_);
        _checkFallbackAppVersion(channelUpgradeFallback_);
        BridgeStorage storage $ = getBridgeStorage();
        $.defaultFallback = defaultFallback_;
        $.channelUpgradeFallback = channelUpgradeFallback_;
    }

    function getImplementation() public view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    function _checkFallbackAppVersion(address fallback_) internal view {
        if (fallback_ == address(0x0)) {
            revert TokiZeroAddress("fallback_");
        }
        IAppVersion iFallback = IAppVersion(fallback_);
        if (APP_VERSION != iFallback.appVersion()) {
            revert TokiInvalidAppVersion(APP_VERSION, iFallback.appVersion());
        }
    }
}

contract MockChannelUpgradeBridge is MockUpgradeBridge {
    uint64 internal immutable INITIALIZE_VERSION;

    /**
     * @param appVersion_ The version of the app.
     * @param port The port of the bridge.
     * @param initializeVersion The version for reinitialization ( >= 2 )
     */
    constructor(
        uint256 appVersion_,
        string memory port,
        uint64 initializeVersion
    ) MockUpgradeBridge(appVersion_, port) {
        INITIALIZE_VERSION = initializeVersion;
    }

    function upgrade(
        address defaultFallback_,
        address channelUpgradeFallback_,
        string[] memory channelIds
    ) public reinitializer(INITIALIZE_VERSION) {
        _checkFallbackAppVersion(defaultFallback_);
        _checkFallbackAppVersion(channelUpgradeFallback_);
        if (channelIds.length == 0) {
            revert TokiMock("no ids");
        }
        BridgeStorage storage $ = getBridgeStorage();
        for (uint256 i = 0; i < channelIds.length; i++) {
            ChannelInfo storage channel = $.channelInfos[channelIds[i]];
            if (APP_VERSION != channel.appVersion) {
                revert TokiInvalidAppVersion(APP_VERSION, channel.appVersion);
            }
        }
        $.defaultFallback = defaultFallback_;
        $.channelUpgradeFallback = channelUpgradeFallback_;
    }
}
