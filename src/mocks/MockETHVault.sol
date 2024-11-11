// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../interfaces/IETHVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Note about slither-disable:
//   Withdrawal function is omitted because this is mock contract.
// slither-disable-next-line locked-ether
contract MockETHVault is IETHVault, IERC20 {
    function deposit() external payable {}

    function withdraw(uint256) external {}

    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(
        address,
        address,
        uint256
    ) external pure returns (bool) {
        return true;
    }
}
