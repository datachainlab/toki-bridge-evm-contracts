// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/GasPriceOracle.sol";
import "../src/interfaces/IGasPriceOracle.sol";

contract GasPriceOracleTest is Test {
    // constants
    uint256 public constant CHAIN_ID = 111;
    address payable public alice = payable(address(0x01));

    GasPriceOracle public gasPriceOracle;

    function setUp() public {
        gasPriceOracle = new GasPriceOracle();
    }

    function testUpdatePrice() public {
        vm.expectEmit(true, true, false, true);
        emit IGasPriceOracle.PriceUpdated(CHAIN_ID, 100);
        gasPriceOracle.updatePrice(CHAIN_ID, 100);
        assertEq(gasPriceOracle.getPrice(CHAIN_ID), 100);
    }

    function testUpdatePriceRevertsWhenNotAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                gasPriceOracle.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        gasPriceOracle.updatePrice(CHAIN_ID, 100);
    }
}
