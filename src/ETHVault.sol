// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {IETHVault} from "./interfaces/IETHVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract ETHVault is
    IETHVault,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC20Upgradeable
{
    struct ETHVaultStorage {
        mapping(address => bool) _noUnwrapTo;
    }

    // keccak256(abi.encode(uint256(keccak256("toki.storage.ETHVault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ETH_VAULT_LOCATION =
        0x5e63f22c59bdc3cd010ce3971dc932873441110bf14a3fdf3e8264631e190000;

    /* ========== EVENTS ========== */
    event SetNoUnwrapTo(address addr);

    function initialize() public initializer {
        __ERC20_init("TOKI wrapped ETH", "tokiETH");
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    receive() external payable {
        deposit();
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
        emit Withdraw(msg.sender, amount);
    }

    function setNoUnwrapTo(address addr) external onlyOwner {
        _getETHVaultStorage()._noUnwrapTo[addr] = true;
        emit SetNoUnwrapTo(addr);
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function noUnwrapTo(address addr) public view returns (bool) {
        return _getETHVaultStorage()._noUnwrapTo[addr];
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        bool isNonZeroAddresses = from != address(0) && to != address(0);
        bool isNoUnwrapTo = _getETHVaultStorage()._noUnwrapTo[to];

        // For transfer and the address is not registered in NoUnwrapTo.
        if (isNonZeroAddresses && !isNoUnwrapTo) {
            // The following is equivalent to burn.
            super._update(from, address(0), value);
            payable(to).transfer(value);
            emit TransferNative(from, to, value);
        } else {
            super._update(from, to, value);
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _getETHVaultStorage()
        private
        pure
        returns (ETHVaultStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := ETH_VAULT_LOCATION
        }
    }
}
