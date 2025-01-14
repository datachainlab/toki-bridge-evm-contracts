// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "forge-std/Test.sol";
import "../src/ETHVault.sol";
import "../src/interfaces/IETHVault.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract UpgradedETHVault is ETHVault {
    uint256 public testValue;

    function setTestValue(uint256 value) public {
        testValue = value;
    }
}

contract Reentrant {
    ETHVault public ethVault;
    constructor(ETHVault _ethVault) {
        ethVault = _ethVault;
    }

    receive() external payable {
        uint256 balance = ethVault.balanceOf(address(this));
        if (balance > 0 && ethVault.totalSupply() >= balance) {
            ethVault.withdraw(balance);
        }
    }

    function deposit() public payable {
        ethVault.deposit{value: msg.value}();
    }

    function withdraw(uint256 amount) public {
        ethVault.withdraw(amount);
    }
}

contract ETHVaultTest is Test {
    ETHVault public ethVault;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        ETHVault impl = new ETHVault();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        ethVault = ETHVault(payable(address(proxy)));
        ethVault.initialize();
    }

    function testInitialize() public {
        assertEq(ethVault.name(), "TOKI wrapped ETH");
        assertEq(ethVault.symbol(), "tokiETH");
    }

    function testDecimals() public {
        assertEq(ethVault.decimals(), 18);
    }

    function testDeposit() public {
        vm.deal(alice, 1 wei);

        vm.expectEmit(address(ethVault));
        emit IERC20.Transfer(address(0), alice, 1);
        vm.expectEmit(address(ethVault));
        emit IETHVault.Deposit(alice, 1);
        vm.prank(alice);
        ethVault.deposit{value: 1 wei}();

        assertEq(alice.balance, 0);
        assertEq(ethVault.balanceOf(alice), 1);
        assertEq(ethVault.totalSupply(), 1);
    }

    function testDepositRevertsWhenSenderIsZeroAddress() public {
        vm.deal(address(0), 1 wei);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InvalidReceiver.selector,
                address(0)
            )
        );
        vm.prank(address(0));
        ethVault.deposit{value: 1 wei}();
    }

    function testWithdraw() public {
        vm.deal(alice, 1 wei);
        vm.prank(alice);
        ethVault.deposit{value: 1 wei}();

        vm.expectEmit(address(ethVault));
        emit IERC20.Transfer(alice, address(0), 1);
        vm.expectEmit(address(ethVault));
        emit IETHVault.Withdraw(alice, 1);
        vm.prank(alice);
        ethVault.withdraw(1);

        assertEq(alice.balance, 1);
        assertEq(ethVault.balanceOf(alice), 0);
        assertEq(ethVault.totalSupply(), 0);
    }

    function testWithdrawPreventReentrant() public {
        vm.deal(alice, 100 wei);
        vm.prank(alice);
        ethVault.deposit{value: 100 wei}();

        Reentrant reentrant = new Reentrant(ethVault);
        reentrant.deposit{value: 10 wei}();

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiNativeTransferIsFailed.selector,
                address(reentrant),
                6 wei
            )
        );
        reentrant.withdraw(6 wei);
    }

    function testWithdrawRevertsWhenSenderIsZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InvalidSender.selector,
                address(0)
            )
        );
        vm.prank(address(0));
        ethVault.withdraw(2 wei);
    }

    function testWithdrawRevertsWhenSenderHasInsufficientBalance() public {
        vm.deal(alice, 1 wei);
        vm.prank(alice);
        ethVault.deposit{value: 1 wei}();

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(alice),
                1 wei,
                2 wei
            )
        );
        vm.prank(alice);
        ethVault.withdraw(2 wei);
    }

    function testSetNoUnwrapTo() public {
        vm.expectEmit(true, false, false, true);
        emit ETHVault.SetNoUnwrapTo(alice);
        ethVault.setNoUnwrapTo(alice);
        assertEq(ethVault.noUnwrapTo(alice), true);
    }

    function testSetNoUnwrapToRevertsWhenSenderIsNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                address(alice)
            )
        );
        vm.prank(alice);
        ethVault.setNoUnwrapTo(alice);
    }

    function testResetNoUnwrapTo() public {
        vm.expectEmit(true, false, false, true);
        emit ETHVault.SetNoUnwrapTo(alice);
        ethVault.setNoUnwrapTo(alice);
        assertEq(ethVault.noUnwrapTo(alice), true);

        vm.expectEmit(true, false, false, true);
        emit ETHVault.ResetNoUnwrapTo(alice);
        ethVault.resetNoUnwrapTo(alice);
        assertEq(ethVault.noUnwrapTo(alice), false);
    }

    function testResetNoUnwrapToRevertsWhenSenderIsNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                alice
            )
        );
        vm.prank(alice);
        ethVault.resetNoUnwrapTo(alice);
    }

    function testTransfer() public {
        vm.deal(alice, 1 wei);
        vm.prank(alice);
        ethVault.deposit{value: 1 wei}();

        vm.expectEmit(address(ethVault));
        emit IERC20.Transfer(alice, address(0), 1);
        vm.expectEmit(address(ethVault));
        emit IETHVault.TransferNative(alice, bob, 1);
        vm.prank(alice);
        ethVault.transfer(bob, 1);

        assertEq(ethVault.balanceOf(alice), 0);
        assertEq(ethVault.totalSupply(), 0);
        assertEq(bob.balance, 1);
    }

    function testTransferWithNoUnwrapTo() public {
        vm.deal(alice, 1 wei);
        vm.prank(alice);
        ethVault.deposit{value: 1 wei}();

        vm.expectEmit(true, false, false, true);
        emit ETHVault.SetNoUnwrapTo(bob);
        ethVault.setNoUnwrapTo(bob);

        vm.expectEmit(address(ethVault));
        emit IERC20.Transfer(alice, bob, 1);
        vm.prank(alice);
        ethVault.transfer(bob, 1);

        assertEq(ethVault.balanceOf(alice), 0);
        assertEq(ethVault.balanceOf(bob), 1);
        assertEq(ethVault.totalSupply(), 1);
    }

    function testTransferRevertsWhenSenderIsZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InvalidSender.selector,
                address(0)
            )
        );
        vm.prank(address(0));
        ethVault.transfer(bob, 1);
    }

    function testTransferRevertsWhenSenderHasInsufficientBalance() public {
        vm.deal(alice, 1 wei);
        vm.prank(alice);
        ethVault.deposit{value: 1 wei}();

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(alice),
                1 wei,
                2 wei
            )
        );
        vm.prank(alice);
        ethVault.transfer(bob, 2 wei);
    }

    function testTransferRevertsWhenSenderHasInsufficientBalanceWithNoUnwrapTo()
        public
    {
        vm.deal(alice, 1 wei);
        vm.prank(alice);
        ethVault.deposit{value: 1 wei}();

        vm.expectEmit(true, false, false, true);
        emit ETHVault.SetNoUnwrapTo(bob);
        ethVault.setNoUnwrapTo(bob);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(alice),
                1 wei,
                2 wei
            )
        );
        vm.prank(alice);
        ethVault.transfer(bob, 2 wei);
    }

    function testUpgradeToAndCall() public {
        ethVault.setNoUnwrapTo(alice);

        UpgradedETHVault newImpl = new UpgradedETHVault();
        ethVault.upgradeToAndCall(address(newImpl), "");

        UpgradedETHVault upgraded = UpgradedETHVault(
            payable(address(ethVault))
        );
        upgraded.setTestValue(1);
        assertEq(upgraded.testValue(), 1);
        assertEq(upgraded.noUnwrapTo(alice), true);
    }

    function testUpgradeToAndCallRevertsWhenSenderIsNotOwner() public {
        UpgradedETHVault newImpl = new UpgradedETHVault();

        address notOwner = makeAddr("NotOwner");
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                notOwner
            )
        );
        vm.prank(notOwner);
        ethVault.upgradeToAndCall(address(newImpl), "");
    }
}
