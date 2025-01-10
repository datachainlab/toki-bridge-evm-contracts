// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {LCPClientBase} from "lcp-solidity/contracts/LCPClientBase.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract LCPClientUpgradeable is
    LCPClientBase,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address ibcHandler,
        bool developmentMode
    ) LCPClientBase(ibcHandler, developmentMode) {
        _disableInitializers();
    }

    function initialize(bytes memory rootCACert) public initializer {
        initializeRootCACert(rootCACert);
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}
