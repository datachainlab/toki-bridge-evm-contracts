// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../interfaces/IBridgeRouter.sol";

// Note about slither-disable:
//   Withdrawal function is omitted because this is mock contract.
// slither-disable-next-line locked-ether
contract MockBridgeRouter is IBridgeEnhancedRouter {
    function callDelta(uint256, bool) external {}

    function deposit(uint256, uint256, address) external payable {}

    function transferPool(
        string calldata,
        uint256,
        uint256,
        uint256,
        uint256,
        bytes calldata,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo calldata,
        address payable
    ) external payable {}

    function transferToken(
        string calldata,
        string calldata,
        uint256,
        bytes calldata,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo calldata,
        address payable
    ) external payable {}

    // After transfer, LPToken is burned and credit is sent.
    function withdrawRemote(
        string calldata,
        uint256,
        uint256,
        uint256,
        uint256,
        bytes calldata,
        address payable
    ) external payable {}

    // withdraw on the src side.(need to check the balance on the dst side and the amount of transfer and mint)
    function withdrawLocal(
        string calldata,
        uint256,
        uint256,
        uint256,
        bytes calldata,
        address payable
    ) external payable {}

    // Send information on credit and targetBalance to dst side pool
    function sendCredit(
        string calldata,
        uint256,
        uint256,
        address payable
    ) external payable {}

    /** In Ledger **/

    function transferPoolInLedger(
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLD_,
        uint256 minAmountLD,
        address to,
        IBCUtils.ExternalInfo calldata externalInfo
    ) external {}

    function withdrawLocalInLedger(
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLP,
        address to
    ) external {}

    function withdrawRemoteInLedger(
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLP,
        uint256 minAmountLD,
        address to
    ) external {}

    function sendCreditInLedger(
        uint256 srcPoolId,
        uint256 dstPoolId
    ) external {}

    // Withdraw by POOL alone. Withdrawal amount may be a restricted amount.
    function withdrawInstant(
        uint256 /*srcPoolId*/,
        uint256 /*amountLP*/,
        address /*to*/
    ) external pure returns (uint256 amountGD) {
        return 0;
    }
}
