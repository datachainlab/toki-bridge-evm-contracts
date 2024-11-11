// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/ETHBridge.sol";
import "../src/ETHVault.sol";
import "../src/mocks/MockBridgeRouter.sol";
import "../src/mocks/MockETHVault.sol";

contract ETHBridgeTest is Test {
    string public constant CHANNEL = "channel-0";

    ETHBridge public ethBridge;
    MockETHVault public mockVault;
    MockBridgeRouter public mockBridge;

    uint256 public poolId = 100;

    address public empty = address(0x00);
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        mockBridge = new MockBridgeRouter();
        mockVault = new MockETHVault();
        ethBridge = new ETHBridge(
            address(mockVault),
            address(mockBridge),
            poolId
        );
    }

    function testConstructor() public {
        assertEq(ethBridge.ETH_VAULT(), address(mockVault));
        assertEq(address(ethBridge.BRIDGE()), address(mockBridge));
        assertEq(ethBridge.ETH_POOL_ID(), poolId);
    }

    function testConstructorFailWithZeroEthVaultBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "ethVault"
            )
        );
        new ETHBridge(empty, address(mockBridge), poolId);
    }

    function testConstructorFailWithZeroBridgeBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "bridge"
            )
        );
        new ETHBridge(address(mockVault), empty, poolId);
    }

    function testDepositETH() public {
        vm.expectCall(
            address(mockVault),
            abi.encodeWithSelector(mockVault.deposit.selector)
        );
        vm.expectCall(
            address(mockVault),
            abi.encodeCall(mockVault.approve, (address(mockBridge), 1))
        );
        vm.expectCall(
            address(mockBridge),
            abi.encodeCall(mockBridge.deposit, (poolId, 1, alice))
        );

        vm.deal(alice, 1 wei);
        vm.prank(alice);
        ethBridge.depositETH{value: 1 wei}();
    }

    function testDepositETHRevertsWhenMsgValueIsZero() public {
        vm.deal(alice, 1 wei);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAmount.selector,
                "msg.value"
            )
        );
        ethBridge.depositETH{value: 0 wei}();
    }

    function testTransferETH() public {
        uint256 amountLD = 2;
        uint256 minAmountLD = 1;
        uint256 refuelAmount = 0;
        IBCUtils.ExternalInfo memory externalInfo = IBCUtils.ExternalInfo(
            "",
            0
        );

        vm.expectCall(
            address(mockVault),
            abi.encodeWithSelector(mockVault.deposit.selector)
        );
        vm.expectCall(
            address(mockVault),
            abi.encodeCall(mockVault.approve, (address(mockBridge), 2))
        );
        vm.expectCall(
            address(mockBridge),
            1 wei, // msg.value
            abi.encodeCall(
                mockBridge.transferPool,
                (
                    CHANNEL,
                    poolId,
                    poolId,
                    amountLD,
                    minAmountLD,
                    abi.encode(bob),
                    refuelAmount,
                    externalInfo,
                    payable(alice)
                )
            )
        );

        vm.deal(alice, 3 wei);
        vm.prank(alice);
        ethBridge.transferETH{value: 3 wei}(
            CHANNEL,
            amountLD,
            minAmountLD,
            abi.encode(bob),
            refuelAmount,
            externalInfo,
            payable(alice)
        );
    }

    function testTransferETHRevertsWhenMsgValueIsZero() public {
        uint256 amountLD = 2;
        uint256 minAmountLD = 1;
        IBCUtils.ExternalInfo memory externalInfo = IBCUtils.ExternalInfo(
            "",
            0
        );

        vm.deal(alice, 1 wei);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiInsufficientAmount.selector,
                "msg.value",
                0,
                amountLD
            )
        );

        ethBridge.transferETH{value: 0}(
            CHANNEL,
            amountLD,
            minAmountLD,
            abi.encode(bob),
            0,
            externalInfo,
            payable(alice)
        );
    }
}
