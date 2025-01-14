// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @title IETHVault
 * @dev Interface for ETHVault that supports the deposit and withdrawal of native ETH tokens.
 */
interface IETHVault {
    /**
     * @dev Emitted when the caller deposits ETH into the vault.
     * @param from The address that deposited the ETH.
     * @param amount The amount of ETH deposited.
     */
    event Deposit(address from, uint256 amount);

    /**
     * @dev Emitted when the caller withdraws ETH from the vault.
     * @param to The address that withdrew the ETH.
     * @param amount The amount of ETH withdrawn.
     */
    event Withdraw(address to, uint256 amount);

    /**
     * @dev Emitted when the caller transfers native ETH instead of wrapped ETH.
     * @param from The address that sent the ETH.
     * @param to The address that received the ETH.
     * @param amount The amount of ETH transferred.
     */
    event TransferNative(address from, address to, uint256 amount);

    /**
     * @dev Deposits native ETH into the vault. The caller must send ETH as msg.value along with the function call.
     * The native ETH is minted as wrapped ETH.
     */
    function deposit() external payable;

    /**
     * @dev Withdraws native ETH from the vault.
     * The caller receives native ETH and the equivalent amount of wrapped ETH are burned.
     * @param amount The amount of ETH to withdraw.
     */
    function withdraw(uint256 amount) external;
}
