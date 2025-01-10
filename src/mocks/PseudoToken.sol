// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/ITokiErrors.sol";

contract PseudoToken is
    ITokiErrors,
    ERC20Upgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint8 private immutable DECIMALS;
    uint256 private _mintCap;
    mapping(address account => bool) private _uncapMinters;

    event SetMintCap(uint256 old, uint256 update);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint8 decimals_) {
        DECIMALS = decimals_;
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 mintCap_
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);

        addUncapMinter(msg.sender);
        setMintCap(mintCap_); // to emit event
    }

    function setMintCap(uint256 mintCap_) public onlyOwner {
        emit SetMintCap(_mintCap, mintCap_);
        _mintCap = mintCap_;
    }

    function addUncapMinter(address a) public onlyOwner {
        _uncapMinters[a] = true;
    }
    function removeUncapMinter(address a) public onlyOwner {
        delete _uncapMinters[a];
    }

    function mint(address account, uint256 amount) public {
        if (
            // solhint-disable-next-line avoid-tx-origin
            tx.origin != msg.sender || msg.sender.code.length != 0
        ) {
            revert TokiContractNotAllowed("msg.sender", msg.sender);
        }

        bool shouldCheckCap = !_uncapMinters[msg.sender];
        if (shouldCheckCap && (amount > _mintCap)) {
            amount = _mintCap;
        }

        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyOwner {
        _burn(account, amount);
    }

    function isUncapMinter(address a) public view returns (bool) {
        return _uncapMinters[a];
    }

    function decimals() public view override(ERC20Upgradeable) returns (uint8) {
        return DECIMALS;
    }

    function mintCap() public view returns (uint256) {
        return _mintCap;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}
