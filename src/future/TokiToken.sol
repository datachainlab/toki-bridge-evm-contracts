// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../interfaces/ITokiErrors.sol";

contract TokiToken is
    ITokiErrors,
    ERC20PermitUpgradeable,
    ERC20CappedUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant SOFTCAP_ADMIN_ROLE =
        keccak256("SOFTCAP_ADMIN_ROLE");

    uint256 public softcap;

    /* ========== EVENTS ========== */
    event SetSoftcap(uint256 softcap);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 initialSupply,
        uint256 cap,
        uint256 softcap_,
        address admin
    ) public initializer {
        __ERC20_init("TokiToken", "TOKI");
        __ERC20Permit_init("TokiToken");
        __ERC20Capped_init(cap);
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        if (softcap_ > cap) {
            revert TokiExceed("softcap", softcap_, cap);
        }
        softcap = softcap_;
        _mint(_msgSender(), initialSupply);
    }

    function setSoftcap(
        uint256 softcap_
    ) external onlyRole(SOFTCAP_ADMIN_ROLE) {
        if (softcap_ > cap()) {
            revert TokiExceed("softcap", softcap_, cap());
        }
        if (softcap_ < totalSupply()) {
            revert TokiExceed("totalSupply", totalSupply(), softcap_);
        }
        softcap = softcap_;
        emit SetSoftcap(softcap);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (totalSupply() + amount > softcap) {
            revert TokiExceedAdd("mint.amount", totalSupply(), amount, softcap);
        }
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(to, amount);
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override(ERC20Upgradeable, ERC20CappedUpgradeable) {
        ERC20CappedUpgradeable._update(from, to, value);
    }

    function _authorizeUpgrade(
        address
    ) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
