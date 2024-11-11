// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "./interfaces/ITokiErrors.sol";
import "./interfaces/IBridgeRouter.sol";
import "./interfaces/IETHBridge.sol";
import "./interfaces/IETHVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ETHBridge is ITokiErrors, IETHBridge {
    address public immutable ETH_VAULT;
    IBridgeStandardRouter public immutable BRIDGE;
    uint256 public immutable ETH_POOL_ID;

    constructor(address ethVault, address bridge, uint256 ethPoolId) {
        if (ethVault == address(0)) {
            revert TokiZeroAddress("ethVault");
        }
        if (bridge == address(0)) {
            revert TokiZeroAddress("bridge");
        }

        ETH_VAULT = ethVault;
        BRIDGE = IBridgeStandardRouter(bridge);
        ETH_POOL_ID = ethPoolId;
    }

    receive() external payable {}

    function depositETH() external payable {
        if (msg.value == 0) {
            revert TokiZeroAmount("msg.value");
        }

        IETHVault(ETH_VAULT).deposit{value: msg.value}();
        // ERC20Upgradeable's approve function returns true or revert.
        // solhint-disable-next-line no-unused-vars
        bool _approved = IERC20(ETH_VAULT).approve(address(BRIDGE), msg.value);

        BRIDGE.deposit(ETH_POOL_ID, msg.value, msg.sender);
    }

    function transferETH(
        string calldata srcChannel,
        uint256 amountLD,
        uint256 minAmountLD,
        bytes calldata to,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo calldata externalInfo,
        address payable refundTo
    ) external payable {
        if (msg.value < amountLD) {
            revert TokiInsufficientAmount("msg.value", msg.value, amountLD);
        }

        // Note about slither-disable:
        //   ETH_VAULT can only be set in constructor which called by authorized deployer.
        // slither-disable-next-line arbitrary-send-eth
        IETHVault(ETH_VAULT).deposit{value: amountLD}();
        // ERC20Upgradeable's approve function returns true or revert.
        // solhint-disable-next-line no-unused-vars
        bool _approved = IERC20(ETH_VAULT).approve(address(BRIDGE), amountLD);

        BRIDGE.transferPool{value: msg.value - amountLD}(
            srcChannel,
            ETH_POOL_ID,
            ETH_POOL_ID,
            amountLD,
            minAmountLD,
            to,
            refuelAmount,
            externalInfo,
            refundTo
        );
    }
}
