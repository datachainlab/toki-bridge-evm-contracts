// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../src/ETHBridge.sol";
import "../src/ETHVault.sol";
import "../src/mocks/MockBridgeRouter.sol";
import "../src/mocks/MockETHVault.sol";
import {LCPClientUpgradeable} from "../src/clients/LCPClientUpgradeable.sol";

contract LCPClientUpgradeableTest is Test {
    LCPClientUpgradeable public t;

    function setUp() public {
        // Specify within the validity period of the root CA.
        vm.warp(2524607999);

        address impl = address(
            new LCPClientUpgradeable(makeAddr("ibcHandler"), true)
        );
        bytes memory rootCACert = vm.readFileBinary(
            "./test/testdata/simulation_rootca.der"
        );
        bytes memory data = abi.encodeCall(
            LCPClientUpgradeable.initialize,
            rootCACert
        );
        address proxy = address(new ERC1967Proxy(impl, data));
        t = LCPClientUpgradeable(proxy);
    }

    function testUpgradeToAndCall() public {
        address newImpl = address(
            new LCPClientUpgradeable(makeAddr("newIBCHandler"), true)
        );
        vm.expectEmit(address(t));
        emit IERC1967.Upgraded(newImpl);
        t.upgradeToAndCall(newImpl, "");
    }

    function testUpgradeToAndCallRevertsWhenSenderIsNotOwner() public {
        address newImpl = address(
            new LCPClientUpgradeable(makeAddr("newIBCHandler"), true)
        );

        address notOwner = makeAddr("NotOwner");
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                notOwner
            )
        );
        vm.prank(notOwner);
        t.upgradeToAndCall(newImpl, "");
    }
}
