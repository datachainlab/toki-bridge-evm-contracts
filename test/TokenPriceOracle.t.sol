// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/TokenPriceOracle.sol";
import "../src/mocks/MockPriceFeed.sol";

contract TokenPriceOracleTest is Test {
    TokenPriceOracle public tokenPriceOracle;
    MockPriceFeed public priceFeed;
    address public empty = address(0x00);

    function setUp() public {
        priceFeed = new MockPriceFeed(10000, 8);
        tokenPriceOracle = new TokenPriceOracle(10 * 1e14);
        tokenPriceOracle.setPriceFeedAddress(
            0,
            address(priceFeed),
            60 * 60 * 24
        );
    }

    function testSetup() public {
        assertEq(tokenPriceOracle.getPriceFeedAddress(0), address(priceFeed));
        assertEq(tokenPriceOracle.getLatestPrice(0), 10000);
        assertEq(tokenPriceOracle.getPrice(0), 10000);
    }

    function testSetPriceChangeThreshold() public {
        assertEq(tokenPriceOracle.priceChangeThresholdE18(), 10 * 1e14);
        vm.expectEmit(true, false, false, true);
        emit TokenPriceOracle.SetPriceChangeThreshold(100 * 1e14);
        tokenPriceOracle.setPriceChangeThreshold(100 * 1e14);
        assertEq(tokenPriceOracle.priceChangeThresholdE18(), 100 * 1e14);
    }

    function testSetPriceChangeThresholdRevertsWhenSenderIsNotAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(0x01),
                tokenPriceOracle.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(address(0x01));
        tokenPriceOracle.setPriceChangeThreshold(20 * 1e14);
    }

    function testSetPriceFeedAddress() public {
        vm.expectEmit(true, true, false, true);
        emit TokenPriceOracle.SetPriceFeedAddress(1, address(priceFeed));
        emit TokenPriceOracle.SetValidityPeriod(1, 60 * 60 * 24);
        tokenPriceOracle.setPriceFeedAddress(
            1,
            address(priceFeed),
            60 * 60 * 24
        );
        assertEq(tokenPriceOracle.getPriceFeedAddress(1), address(priceFeed));
        assertEq(tokenPriceOracle.getValidityPeriod(1), 60 * 60 * 24);
    }

    function testPriceFeedDecimals() public {
        MockPriceFeed priceFeed0 = new MockPriceFeed(10000, 0);
        MockPriceFeed priceFeed8 = new MockPriceFeed(10000, 8);
        MockPriceFeed priceFeed18 = new MockPriceFeed(10000, 18);

        tokenPriceOracle.setPriceFeedAddress(0, address(priceFeed0), 3600);
        tokenPriceOracle.setPriceFeedAddress(8, address(priceFeed8), 3600);
        tokenPriceOracle.setPriceFeedAddress(18, address(priceFeed18), 3600);

        assertEq(tokenPriceOracle.getPriceFeedDecimals(0), 0, "dec 0");
        assertEq(tokenPriceOracle.getPriceFeedDecimals(8), 8, "dec 8");
        assertEq(tokenPriceOracle.getPriceFeedDecimals(18), 18, "dec 18");
    }

    function testSetPriceFeedAddressFailWithPriceFeedZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "priceFeedAddress"
            )
        );
        tokenPriceOracle.setPriceFeedAddress(1, empty, 60 * 60 * 24);
    }

    function testSetPriceFeedAddressRevertsWhenSenderIsNotAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(0x01),
                tokenPriceOracle.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(address(0x01));
        tokenPriceOracle.setPriceFeedAddress(
            2,
            address(priceFeed),
            60 * 60 * 24
        );
    }

    function testSetValidityPeriod() public {
        vm.expectEmit(true, true, false, true);
        emit TokenPriceOracle.SetValidityPeriod(0, 3939);
        tokenPriceOracle.setValidityPeriod(0, 3939);
        assertEq(tokenPriceOracle.getValidityPeriod(0), 3939);
    }

    function testSetValidityPeriodRevertsWhenSenderIsNotAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(0x01),
                tokenPriceOracle.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(address(0x01));
        tokenPriceOracle.setValidityPeriod(0, 3939);
    }

    function testGetLatestPrice() public {
        priceFeed.setPrice(20000);
        assertEq(tokenPriceOracle.getLatestPrice(0), 20000);

        priceFeed.setPrice(9990);
        assertEq(tokenPriceOracle.getLatestPrice(0), 9990);
    }

    function testGetLatestPriceRevertsWhenPriceIsNotPositive() public {
        priceFeed.setPrice(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiPriceIsNotPositive.selector,
                0
            )
        );
        tokenPriceOracle.getLatestPrice(0);

        priceFeed.setPrice(-1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiPriceIsNotPositive.selector,
                -1
            )
        );
        tokenPriceOracle.getLatestPrice(0);
    }

    function testGetLatestPriceRevertsWhenValidityPeriodExpired() public {
        // note that MockPriceFeed always returns 0 as updatedAt
        tokenPriceOracle.setValidityPeriod(0, 100);

        skip(1000);
        rewind(block.timestamp - 100);
        assertEq(block.timestamp, 100);
        tokenPriceOracle.getLatestPrice(0); // pass

        skip(1000);
        rewind(block.timestamp - 101);
        assertEq(block.timestamp, 101);
        vm.expectRevert(
            abi.encodeWithSelector(ITokiErrors.TokiPriceIsExpired.selector, 0)
        );
        tokenPriceOracle.getLatestPrice(0);
    }

    function testNeedUpdate() public {
        assertEq(tokenPriceOracle.needUpdate(10000, 10000), false);
        assertEq(tokenPriceOracle.needUpdate(9990, 10000), false);
        assertEq(tokenPriceOracle.needUpdate(9989, 10000), true);
        assertEq(tokenPriceOracle.needUpdate(10010, 10000), false);
        assertEq(tokenPriceOracle.needUpdate(10011, 10000), true);
        assertEq(tokenPriceOracle.needUpdate(0, 10000), true);
        assertEq(tokenPriceOracle.needUpdate(0, 0), true);
    }

    function testUpdatePrice() public {
        priceFeed.setPrice(9990);
        tokenPriceOracle.updatePrice(0, false);
        assertEq(tokenPriceOracle.getPrice(0), 10000);

        priceFeed.setPrice(9989);
        tokenPriceOracle.updatePrice(0, false);
        assertEq(tokenPriceOracle.getPrice(0), 9989);

        priceFeed.setPrice(10000);
        tokenPriceOracle.updatePrice(0, false);
        assertEq(tokenPriceOracle.getPrice(0), 10000);

        priceFeed.setPrice(10010);
        tokenPriceOracle.updatePrice(0, false);
        assertEq(tokenPriceOracle.getPrice(0), 10000);

        priceFeed.setPrice(10011);
        tokenPriceOracle.updatePrice(0, false);
        assertEq(tokenPriceOracle.getPrice(0), 10011);

        priceFeed.setPrice(10000);
        tokenPriceOracle.updatePrice(0, false);
        assertEq(tokenPriceOracle.getPrice(0), 10000);

        priceFeed.setPrice(10010);
        tokenPriceOracle.updatePrice(0, true);
        assertEq(tokenPriceOracle.getPrice(0), 10010);

        tokenPriceOracle.setPriceChangeThreshold(100 * 1e14);
        priceFeed.setPrice(10000);
        tokenPriceOracle.updatePrice(0, true);
        priceFeed.setPrice(10100);
        tokenPriceOracle.updatePrice(0, false);
        assertEq(tokenPriceOracle.getPrice(0), 10000);
        priceFeed.setPrice(10101);
        tokenPriceOracle.updatePrice(0, false);
        assertEq(tokenPriceOracle.getPrice(0), 10101);
    }
}
