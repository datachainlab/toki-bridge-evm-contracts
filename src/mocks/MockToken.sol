// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint8 private immutable DECIMALS;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 initialSupply
    ) ERC20(name_, symbol_) {
        DECIMALS = decimals_;
        _mint(msg.sender, initialSupply);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }

    function decimals() public view override(ERC20) returns (uint8) {
        return DECIMALS;
    }
}
