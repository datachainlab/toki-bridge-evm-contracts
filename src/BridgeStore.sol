// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IIBCChannel.sol";
import {ShortString} from "@openzeppelin/contracts/utils/ShortStrings.sol";
import "./interfaces/ITokiErrors.sol";
import "./interfaces/IPoolRepository.sol";
import "./future/interfaces/ITokenEscrow.sol";
import "./interfaces/ITokenPriceOracle.sol";
import "./interfaces/IRelayerFeeCalculator.sol";
import "./library/IBCUtils.sol";

abstract contract BridgeStore is ITokiErrors {
    struct ChannelInfo {
        uint256 counterpartyChainId;
        uint256 appVersion;
    }

    /// @custom:storage-location erc7201:toki.bridge
    struct BridgeStorage {
        address defaultFallback;
        address channelUpgradeFallback;
        // channelId => ChannelInfo
        mapping(string => ChannelInfo) channelInfos;
        IICS04SendPacket ics04SendPacket;
        IPoolRepository poolRepository; // repository of pools
        ITokenEscrow tokenEscrow;
        ITokenPriceOracle tokenPriceOracle; // oracle for token price
        IRelayerFeeCalculator relayerFeeCalculator;
        /**
         * retry info
         */
        mapping(uint256 => mapping(uint64 => bytes)) revertReceive; //[chainId][sequence] = payload
        // User will no longer be able to retry once expiry period is reached.
        uint64 receiveRetryBlocks;
        uint64 withdrawRetryBlocks;
        uint64 externalRetryBlocks;
        /**
         * oracle info
         */
        mapping(uint256 => uint256) premiumBPS; // [dst chain id] => bps risk premium rate for each token
        mapping(uint256 => uint256) refuelSrcCap; // [dst chain id] => capping value on src
        uint256 refuelDstCap;
    }

    bytes32 public constant IBC_HANDLER_ROLE = keccak256("IBC_HANDLER_ROLE");
    bytes32 public constant RELAYER_FEE_OWNER_ROLE =
        keccak256("RELAYER_FEE_OWNER_ROLE");
    uint64 public constant TIMEOUT_TIMESTAMP = 2 ** 64 - 1; // max uint64

    // keccak256(abi.encode(uint256(keccak256("toki.bridge")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 internal constant BRIDGE_STORAGE_SLOT =
        0x183a6125c38840424c4a85fa12bab2ab606c4b6d0e7cc73c0c06ba5300eab500;

    uint256 internal constant RISK_BPS = 10_000;

    uint256 internal constant MAX_TO_LENGTH = 1024; // 1KB
    // the maximum length of the ExternalInfo.payload that can be sent in a packet
    uint256 internal constant MAX_PAYLOAD_LENGTH = 10 * 1024; // 10KB

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 internal immutable APP_VERSION;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ShortString internal immutable PORT;

    function getBridgeStorage()
        internal
        pure
        returns (BridgeStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := BRIDGE_STORAGE_SLOT
        }
    }
}
