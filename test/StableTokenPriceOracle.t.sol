// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/StableTokenPriceOracle.sol";
import "../src/mocks/MockPriceFeed.sol";

contract StableTokenPriceOracleEvents {
    event PriceUpdated(uint256 indexed poolId, uint256 price);
    event PriceDriftThresholdUpdated(uint256 priceDriftThreshold);
    event PriceDepegThresholdUpdated(uint256 priceDepegThreshold);
    event PoolStateUpdated(
        uint256 indexed poolId,
        uint256 basePrice,
        address priceFeedAddress
    );
}

contract StableTokenPriceOracleHarness is StableTokenPriceOracle {
    function exposedPriceNeedsUpdate(
        uint256 newPrice,
        uint256 currentPrice,
        uint256 basePrice
    ) external view returns (bool) {
        return _priceNeedsUpdate(newPrice, currentPrice, basePrice);
    }

    function exposedGetLatestPrice(
        uint256 poolId
    ) external view returns (uint256) {
        return _getLatestPrice(poolId);
    }

    function exposedGetPriceDeviationStatus(
        uint256 price,
        uint256 basePrice
    ) external view returns (PriceDeviationStatus) {
        return _getPriceDeviationStatus(price, basePrice);
    }
}

contract StableTokenPriceOracleTest is Test, StableTokenPriceOracleEvents {
    StableTokenPriceOracleHarness public stableTokenPriceOracle;
    MockPriceFeed public priceFeed;
    address public empty = address(0x00);

    function setUp() public {
        priceFeed = new MockPriceFeed(10000, 8);
        stableTokenPriceOracle = new StableTokenPriceOracleHarness();

        vm.expectEmit(true, true, true, true);
        emit PoolStateUpdated(0, 10000, address(priceFeed));
        stableTokenPriceOracle.setBasePriceAndFeedAddress(
            0,
            10000,
            address(priceFeed)
        );
    }

    function testSetup() public {
        assertEq(stableTokenPriceOracle.getBasePrice(0), 10000);
        assertEq(
            stableTokenPriceOracle.getPriceFeedAddress(0),
            address(priceFeed)
        );
        assertEq(stableTokenPriceOracle.exposedGetLatestPrice(0), 10000);
        assertEq(stableTokenPriceOracle.getCurrentPrice(0), 10000);
        assertEq(stableTokenPriceOracle.getCurrentPrice(1), 0);
    }

    function testSetBasePriceAndFeedAddress() public {
        vm.expectEmit(address(stableTokenPriceOracle));
        emit PoolStateUpdated(1, 20000, address(priceFeed));
        stableTokenPriceOracle.setBasePriceAndFeedAddress(
            1,
            20000,
            address(priceFeed)
        );
        assertEq(stableTokenPriceOracle.getBasePrice(1), 20000);
        assertEq(
            stableTokenPriceOracle.getPriceFeedAddress(1),
            address(priceFeed)
        );
    }

    function testSetBasePriceAndFeedAddressFailWithPriceFeedZeroAddress()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "priceFeedAddress"
            )
        );
        stableTokenPriceOracle.setBasePriceAndFeedAddress(1, 20000, empty);
    }

    function testSetBasePriceAndFeedAddressRevertsWhenSenderIsNotAdmin()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(0x01),
                stableTokenPriceOracle.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(address(0x01));
        stableTokenPriceOracle.setBasePriceAndFeedAddress(
            2,
            20000,
            address(priceFeed)
        );
    }

    function testSetBasePriceAndFeedAddressFailWithBasePriceZeroAddress()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroValue.selector,
                "base price"
            )
        );

        stableTokenPriceOracle.setBasePriceAndFeedAddress(
            1,
            0,
            address(priceFeed)
        );
    }

    function testSetPriceFeedDecimals() public {
        MockPriceFeed priceFeed0 = new MockPriceFeed(10000, 0);
        MockPriceFeed priceFeed8 = new MockPriceFeed(10000, 8);
        MockPriceFeed priceFeed18 = new MockPriceFeed(10000, 18);

        stableTokenPriceOracle.setBasePriceAndFeedAddress(
            0,
            1,
            address(priceFeed0)
        );
        stableTokenPriceOracle.setBasePriceAndFeedAddress(
            8,
            1,
            address(priceFeed8)
        );
        stableTokenPriceOracle.setBasePriceAndFeedAddress(
            18,
            1,
            address(priceFeed18)
        );

        assertEq(stableTokenPriceOracle.getPriceFeedDecimals(0), 0, "dec 0");
        assertEq(stableTokenPriceOracle.getPriceFeedDecimals(8), 8, "dec 8");
        assertEq(stableTokenPriceOracle.getPriceFeedDecimals(18), 18, "dec 18");
    }

    function testSetPriceDriftThreshold() public {
        vm.expectEmit(address(stableTokenPriceOracle));
        emit PriceDriftThresholdUpdated(10);
        stableTokenPriceOracle.setPriceDriftThreshold(10);
        assertEq(stableTokenPriceOracle.priceDriftThreshold(), 10);
    }

    function testSetPriceDriftThresholdRevertsWhenSenderIsNotAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(0x01),
                stableTokenPriceOracle.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(address(0x01));
        stableTokenPriceOracle.setPriceDriftThreshold(20);
    }

    function testSetPriceDepegThreshold() public {
        vm.expectEmit(address(stableTokenPriceOracle));
        emit PriceDepegThresholdUpdated(10);
        stableTokenPriceOracle.setPriceDepegThreshold(10);
        assertEq(stableTokenPriceOracle.priceDepegThreshold(), 10);
    }

    function testSetPriceDepegThresholdRevertsWhenSenderIsNotAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(0x01),
                stableTokenPriceOracle.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(address(0x01));
        stableTokenPriceOracle.setPriceDepegThreshold(20);
    }

    function testGetPriceFeedAddress() public {
        assertEq(
            stableTokenPriceOracle.getPriceFeedAddress(0),
            address(priceFeed)
        );
    }

    function testGetPriceFeedAddressRevertsWhenPriceFeedIsZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "priceFeedAddress"
            )
        );
        stableTokenPriceOracle.getPriceFeedAddress(1);
    }

    function testGetBasePrice() public {
        assertEq(stableTokenPriceOracle.getBasePrice(0), 10000);
    }

    function testGetBasePriceRevertsWhenBasePriceIsZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroValue.selector,
                "base price"
            )
        );
        stableTokenPriceOracle.getBasePrice(1);
    }

    function testGetCurrentPrice() public {
        assertEq(stableTokenPriceOracle.getCurrentPrice(0), 10000);
        assertEq(stableTokenPriceOracle.getCurrentPrice(1), 0);
    }

    function testGetPriceDeviationStatus() public {
        assertTrue(
            stableTokenPriceOracle.exposedGetPriceDeviationStatus(
                10050,
                10000
            ) == IStableTokenPriceOracle.PriceDeviationStatus.Normal
        );

        assertTrue(
            stableTokenPriceOracle.exposedGetPriceDeviationStatus(
                10000,
                10000
            ) == IStableTokenPriceOracle.PriceDeviationStatus.Normal
        );

        assertTrue(
            stableTokenPriceOracle.exposedGetPriceDeviationStatus(
                9990,
                10000
            ) == IStableTokenPriceOracle.PriceDeviationStatus.Normal
        );
        assertTrue(
            stableTokenPriceOracle.exposedGetPriceDeviationStatus(
                9989,
                10000
            ) == IStableTokenPriceOracle.PriceDeviationStatus.Drift
        );
        assertTrue(
            stableTokenPriceOracle.exposedGetPriceDeviationStatus(
                9850,
                10000
            ) == IStableTokenPriceOracle.PriceDeviationStatus.Drift
        );
        assertTrue(
            stableTokenPriceOracle.exposedGetPriceDeviationStatus(
                9840,
                10000
            ) == IStableTokenPriceOracle.PriceDeviationStatus.Depeg
        );
    }

    function testPriceNeedsUpdate() public {
        // currentDeviationState != newDeviationState
        assertEq(
            stableTokenPriceOracle.exposedPriceNeedsUpdate(9989, 9990, 10000),
            true
        );
        assertEq(
            stableTokenPriceOracle.exposedPriceNeedsUpdate(9990, 9989, 10000),
            true
        );
        assertEq(
            stableTokenPriceOracle.exposedPriceNeedsUpdate(9850, 9840, 10000),
            true
        );
        assertEq(
            stableTokenPriceOracle.exposedPriceNeedsUpdate(9840, 9850, 10000),
            true
        );

        vm.expectEmit(true, false, false, true);
        emit PriceDepegThresholdUpdated(10 * 1e14);
        stableTokenPriceOracle.setPriceDepegThreshold(10 * 1e14);
        assertEq(
            stableTokenPriceOracle.exposedPriceNeedsUpdate(9990, 9989, 10000),
            true
        );
        assertEq(
            stableTokenPriceOracle.exposedPriceNeedsUpdate(9989, 9990, 10000),
            true
        );

        vm.expectEmit(true, false, false, true);
        emit PriceDepegThresholdUpdated(150 * 1e14);
        stableTokenPriceOracle.setPriceDepegThreshold(150 * 1e14);

        // currentPrice == 0 && newPrice > 0
        assertEq(stableTokenPriceOracle.exposedPriceNeedsUpdate(0, 1, 1), true);

        // drift
        assertTrue(
            stableTokenPriceOracle.exposedGetPriceDeviationStatus(
                9980000 - 998,
                10000000
            ) == IStableTokenPriceOracle.PriceDeviationStatus.Drift
        );
        assertTrue(
            stableTokenPriceOracle.exposedGetPriceDeviationStatus(
                9980000,
                10000000
            ) == IStableTokenPriceOracle.PriceDeviationStatus.Drift
        );
        assertEq(
            stableTokenPriceOracle.exposedPriceNeedsUpdate(
                9980000 - 997,
                9980000,
                10000000
            ),
            false
        );
        assertEq(
            stableTokenPriceOracle.exposedPriceNeedsUpdate(
                9980000 - 998,
                9980000,
                10000000
            ),
            true
        );
        assertEq(
            stableTokenPriceOracle.exposedPriceNeedsUpdate(
                9980000,
                9980000 - 997,
                10000000
            ),
            false
        );
        assertEq(
            stableTokenPriceOracle.exposedPriceNeedsUpdate(
                9980000,
                9980000 - 998,
                10000000
            ),
            true
        );

        // Normal
        vm.expectEmit(true, false, false, true);
        emit PriceDriftThresholdUpdated(1e18);
        stableTokenPriceOracle.setPriceDriftThreshold(1e18);
        assertTrue(
            stableTokenPriceOracle.exposedGetPriceDeviationStatus(
                9990,
                10000
            ) == IStableTokenPriceOracle.PriceDeviationStatus.Normal
        );
        assertEq(
            stableTokenPriceOracle.exposedPriceNeedsUpdate(9991, 10000, 10000),
            false
        );
        assertEq(
            stableTokenPriceOracle.exposedPriceNeedsUpdate(9990, 10000, 10000),
            true
        );

        // Depeg
        vm.expectEmit(true, false, false, true);
        emit PriceDriftThresholdUpdated(0);
        stableTokenPriceOracle.setPriceDriftThreshold(0);

        vm.expectEmit(true, false, false, true);
        emit PriceDepegThresholdUpdated(0);
        stableTokenPriceOracle.setPriceDepegThreshold(0);
        assertTrue(
            stableTokenPriceOracle.exposedGetPriceDeviationStatus(
                9991,
                10000
            ) == IStableTokenPriceOracle.PriceDeviationStatus.Depeg
        );
        assertEq(
            stableTokenPriceOracle.exposedPriceNeedsUpdate(9991, 10000, 100000),
            false
        );
        assertEq(
            stableTokenPriceOracle.exposedPriceNeedsUpdate(9990, 10000, 100000),
            true
        );
    }

    function testGetLatestPrice() public {
        priceFeed.setPrice(20000);
        assertEq(stableTokenPriceOracle.exposedGetLatestPrice(0), 10000);

        priceFeed.setPrice(9990);
        assertEq(stableTokenPriceOracle.exposedGetLatestPrice(0), 9990);
    }

    function testUpdateCurrentPrice() public {
        priceFeed.setPrice(9991);
        stableTokenPriceOracle.updateCurrentPrice(0, false);
        // not updated
        assertEq(stableTokenPriceOracle.getCurrentPrice(0), 10000);

        priceFeed.setPrice(9990);
        vm.expectEmit(address(stableTokenPriceOracle));
        emit PriceUpdated(0, 9990);
        stableTokenPriceOracle.updateCurrentPrice(0, false);
        assertEq(stableTokenPriceOracle.getCurrentPrice(0), 9990);

        priceFeed.setPrice(9989);
        stableTokenPriceOracle.updateCurrentPrice(0, false);
        assertEq(stableTokenPriceOracle.getCurrentPrice(0), 9989);

        priceFeed.setPrice(9988);
        stableTokenPriceOracle.updateCurrentPrice(0, false);
        assertEq(stableTokenPriceOracle.getCurrentPrice(0), 9988);

        priceFeed.setPrice(9849);
        stableTokenPriceOracle.updateCurrentPrice(0, false);
        assertEq(stableTokenPriceOracle.getCurrentPrice(0), 9849);

        priceFeed.setPrice(9848);
        stableTokenPriceOracle.updateCurrentPrice(0, false);
        assertEq(stableTokenPriceOracle.getCurrentPrice(0), 9849);

        stableTokenPriceOracle.updateCurrentPrice(0, true);
        assertEq(stableTokenPriceOracle.getCurrentPrice(0), 9848);
    }
}
