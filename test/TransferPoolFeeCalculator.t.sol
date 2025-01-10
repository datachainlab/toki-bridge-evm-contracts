// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/replaceable/TransferPoolFeeCalculator.sol";
import "../src/interfaces/IStableTokenPriceOracle.sol";
import "../src/interfaces/ITokenPriceOracle.sol";
import "../src/interfaces/IPoolRepository.sol";
import "../src/interfaces/IPool.sol";
import "../src/mocks/MockToken.sol";

contract MockStableTokenPriceOracle is IStableTokenPriceOracle {
    PriceDeviationStatus public priceDeviationStatus;
    mapping(uint256 => uint256) public poolIdToCurrentPrice;
    mapping(uint256 => uint8) public poolIdToDecimals;

    function setCurrentPrice(
        uint256 _poolId,
        uint256 _currentPrice,
        uint8 _decimals
    ) external {
        poolIdToCurrentPrice[_poolId] = _currentPrice;
        poolIdToDecimals[_poolId] = _decimals;
    }

    function updateCurrentPrice(
        uint256 _poolId,
        bool /*_forceUpdate*/
    ) external {
        poolIdToCurrentPrice[_poolId] += 1;
    }

    function setPriceDeviationStatus(
        PriceDeviationStatus _priceDeviationStatus
    ) external {
        priceDeviationStatus = _priceDeviationStatus;
    }

    function priceNeedsUpdate(
        uint256 _poolId
    ) external view override returns (bool, uint256 latestPrice) {
        return (false, poolIdToCurrentPrice[_poolId]);
    }

    function getCurrentPriceDeviationStatus(
        uint256
    ) external view override returns (PriceDeviationStatus) {
        return priceDeviationStatus;
    }

    function getValidityPeriod(
        uint256
    ) external pure override returns (uint256) {
        return 1;
    }

    function getCurrentPrice(
        uint256 _poolId
    ) public view override returns (uint256) {
        return poolIdToCurrentPrice[_poolId];
    }

    function getBasePrice(uint256 _poolId) public view returns (uint256) {
        return poolIdToCurrentPrice[_poolId];
    }

    function getPriceFeedDecimals(
        uint256 _poolId
    ) public view override returns (uint8) {
        return poolIdToDecimals[_poolId];
    }

    function getCurrentPriceAndDecimals(
        uint256 poolId
    ) public view override returns (uint256 price, uint8 decimals) {
        price = getCurrentPrice(poolId);
        decimals = getPriceFeedDecimals(poolId);
    }

    function getPriceFeedAddress(
        uint256
    ) public pure override returns (address) {
        return address(0x1);
    }
}

contract MockTokenPriceOracle is ITokenPriceOracle {
    mapping(uint256 => uint256) public tokenId2Price;
    uint8 public decimals;

    constructor(uint8 _decimals) {
        decimals = _decimals;
    }

    function mockSetPrice(uint256 tokenId, uint256 price) external {
        tokenId2Price[tokenId] = price;
    }

    function getValidityPeriod(
        uint256 /* tokenId */
    ) external pure override returns (uint256) {
        return 1;
    }

    function getPrice(uint256 tokenId) public view returns (uint256) {
        return tokenId2Price[tokenId];
    }

    function getLatestPrice(uint256 tokenId) public view returns (uint256) {
        return tokenId2Price[tokenId];
    }

    function getPriceFeedDecimals(
        uint256 /* tokenId */
    ) public view returns (uint8) {
        return decimals;
    }

    function getPriceAndDecimals(
        uint256 tokenId
    ) public view returns (uint256 price, uint8 decimals) {
        price = getPrice(tokenId);
        decimals = getPriceFeedDecimals(tokenId);
    }

    function getLatestPriceAndDecimals(
        uint256 tokenId
    ) public view returns (uint256 price, uint8 decimals) {
        price = getLatestPrice(tokenId);
        decimals = getPriceFeedDecimals(tokenId);
    }

    function updatePrice(
        uint256 /*tokenId*/,
        bool /*forceUpdate*/
    ) public pure {
        revert("not implemented");
    }

    function getPriceFeedAddress(
        uint256 /* tokenId */
    ) public pure returns (address) {
        return address(0x0);
    }

    function tokenIdToki() public pure returns (uint256) {
        return 0x544F4B49544F4B49544F4B49544F4B49;
    }
}

contract TransferPoolFeeCalculatorTest is Test {
    TransferPoolFeeCalculator public feeCalculator;
    MockStableTokenPriceOracle public priceOracle;
    MockTokenPriceOracle public tokenPriceOracle;

    function setUp() public {
        priceOracle = new MockStableTokenPriceOracle();
        feeCalculator = new TransferPoolFeeCalculator(priceOracle);
    }

    function testSetup() public {
        assertEq(
            address(feeCalculator.stableTokenPriceOracle()),
            address(priceOracle)
        );
    }

    function testSetWhitelist() public {
        vm.expectEmit(true, true, false, true);
        emit TransferPoolFeeCalculator.SetWhitelist(address(0x1), true);
        feeCalculator.setWhitelist(address(0x1), true);
        assertEq(feeCalculator.whitelist(address(0x1)), true);

        vm.expectEmit(true, true, false, true);
        emit TransferPoolFeeCalculator.SetWhitelist(address(0x1), false);
        feeCalculator.setWhitelist(address(0x1), false);
        assertEq(feeCalculator.whitelist(address(0x1)), false);
    }

    function testSetWhitelistRevertsWhenSenderIsNotAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(0x1),
                feeCalculator.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(address(0x1));
        feeCalculator.setWhitelist(address(0x1), true);
    }

    function testSetStableTokenPriceOracle() public {
        MockStableTokenPriceOracle newPriceOracle = new MockStableTokenPriceOracle();
        IStableTokenPriceOracle priceOracle_ = IStableTokenPriceOracle(
            newPriceOracle
        );
        vm.expectEmit(true, false, false, true);
        emit TransferPoolFeeCalculator.SetStableTokenPriceOracle(priceOracle_);
        feeCalculator.setStableTokenPriceOracle(priceOracle_);
        assertEq(
            address(feeCalculator.stableTokenPriceOracle()),
            address(newPriceOracle)
        );
    }

    function testSetStableTokenPriceOracleRevertsWhenSenderIsNotAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(0x1),
                feeCalculator.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(address(0x1));
        feeCalculator.setStableTokenPriceOracle(
            IStableTokenPriceOracle(address(0x1))
        );
    }

    function testVersion() public {
        assertEq(feeCalculator.version(), "1.0.0");
    }

    function testEqSafeZoneRange() public {
        uint256 max;
        uint256 min;

        (max, min) = feeCalculator.eqFeeSafeZoneRange(10_000);
        assertEq(max, 6_000);
        assertEq(min, 500);

        (max, min) = feeCalculator.eqFeeSafeZoneRange(43);
        assertEq(max, 25);
        assertEq(min, 2);
    }

    function testBalanceDeficitZone() public {
        assertEq(
            uint8(feeCalculator.balanceDeficitZone(600, 500, 700)),
            uint8(TransferPoolFeeCalculator.BalanceDeficitZone.NoFeeZone)
        );

        assertEq(
            uint8(feeCalculator.balanceDeficitZone(600, 500, 700)),
            uint8(TransferPoolFeeCalculator.BalanceDeficitZone.NoFeeZone)
        );
        assertEq(
            uint8(feeCalculator.balanceDeficitZone(600, 500, 600)),
            uint8(TransferPoolFeeCalculator.BalanceDeficitZone.NoFeeZone)
        );
        assertEq(
            uint8(feeCalculator.balanceDeficitZone(600, 500, 599)),
            uint8(TransferPoolFeeCalculator.BalanceDeficitZone.SafeZone)
        );
        assertEq(
            uint8(feeCalculator.balanceDeficitZone(600, 500, 500)),
            uint8(TransferPoolFeeCalculator.BalanceDeficitZone.SafeZone)
        );
    }

    function testBalanceDeficitZoneRevertsWhenZoneRangeIsInvalid() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiInvalidSafeZoneRange.selector,
                401,
                400
            )
        );
        feeCalculator.balanceDeficitZone(400, 401, 499);
    }

    function testMinimumTransactionFee() public {
        {
            // 1token=1USD stable token
            assertEq(
                25 * 1e6,
                feeCalculator.getMinimumTransactionFee(false, 0, 8),
                "stable token with decimals=8"
            );
            assertEq(
                25 * 1e16,
                feeCalculator.getMinimumTransactionFee(false, 0, 18),
                "stable token with decimals=18"
            );
        }

        {
            // set 1token=3usd. 0.25usd=0.083333token
            uint256 poolId = 39;
            uint256 tokenId = 73;

            vm.expectEmit(true, true, false, true);
            emit TransferPoolFeeCalculator.SetTokenId(poolId, tokenId);
            feeCalculator.setTokenId(poolId, tokenId);
            assertEq(
                tokenId,
                feeCalculator.poolIdToTokenId(poolId),
                "poolIdToTokenId"
            );

            assertEq(
                1e14 / 1e10,
                feeCalculator.getMinimumTransactionFee(false, poolId, 8),
                "unstable token decimals=8"
            );

            assertEq(
                0.0001e18,
                feeCalculator.getMinimumTransactionFee(false, poolId, 18),
                "unstable token with decimals=18"
            );
        }
    }

    function testSafeZoneEqFee() public {
        assertEq(
            feeCalculator.safeZoneEqFeeBps(599e18, 1000e18),
            7272727272727 // 0.0727bp
        );
        assertEq(
            feeCalculator.safeZoneEqFeeBps(500e18, 1000e18),
            727272727272727 // 7.27bp
        );
        assertEq(
            feeCalculator.safeZoneEqFeeBps(100e18, 1000e18),
            3636363636363636 // 36.36bp
        );
        assertEq(
            feeCalculator.safeZoneEqFeeBps(5e18, 1000e18),
            4327272727272727 // 43.27bp
        );
    }

    function testDangerZoneEqFeeBps() public {
        assertEq(
            feeCalculator.dangerZoneEqFeeBps(49e18, 1000e18),
            23908000000000000 // 239.08bp
        );
        assertEq(
            feeCalculator.dangerZoneEqFeeBps(40e18, 1000e18),
            203080000000000000 // 2030.8bp
        );
        assertEq(
            feeCalculator.dangerZoneEqFeeBps(40e18, 10000e18),
            919768000000000000 // 9197.68bp
        );
        assertEq(
            feeCalculator.dangerZoneEqFeeBps(1e18, 10000e18),
            997409200000000000 // 9974.09bp
        );
    }

    function testGetEqFee() public {
        _testGetEqFee(
            "testGetEqFee-10: not whitelisted, no fee zone",
            false,
            TransferPoolFeeCalculator.BalanceDeficitZone.NoFeeZone,
            600e18,
            1000e18,
            100e18,
            0
        );
        _testGetEqFee(
            "testGetEqFee-20: not whitelisted, safe zone",
            false,
            TransferPoolFeeCalculator.BalanceDeficitZone.SafeZone,
            500e18,
            1000e18,
            100e18,
            72727272727272700
        );
        _testGetEqFee(
            "testGetEqFee-30: not whitelisted, danger zone",
            false,
            TransferPoolFeeCalculator.BalanceDeficitZone.DangerZone,
            49e18,
            1000e18,
            100e18,
            2390800000000000000
        );
        _testGetEqFee(
            "testGetEqFee-40: whitelisted, no fee zone",
            true,
            TransferPoolFeeCalculator.BalanceDeficitZone.NoFeeZone,
            600e18,
            1000e18,
            100e18,
            0
        );
        _testGetEqFee(
            "testGetEqFee-50: whitelisted, safe zone",
            true,
            TransferPoolFeeCalculator.BalanceDeficitZone.SafeZone,
            500e18,
            1000e18,
            100e18,
            0
        );
        _testGetEqFee(
            "testGetEqFee-60: whitelisted, danger zone",
            true,
            TransferPoolFeeCalculator.BalanceDeficitZone.DangerZone,
            49e18,
            1000e18,
            100e18,
            0
        );
    }

    function testGetProtocolFee() public {
        uint8 globalDecimals = 18;
        _testGetProtocolFee(
            "testGetProtocolFee-10: not whitelisted, no fee zone",
            false,
            TransferPoolFeeCalculator.BalanceDeficitZone.NoFeeZone,
            1,
            1,
            1_000_000 * (10 ** globalDecimals),
            870 * (10 ** globalDecimals)
        );
        _testGetProtocolFee(
            "testGetProtocolFee-20: not whitelisted, safe zone",
            false,
            TransferPoolFeeCalculator.BalanceDeficitZone.SafeZone,
            1,
            1,
            1_000_000 * (10 ** globalDecimals),
            900 * (10 ** globalDecimals)
        );
        _testGetProtocolFee(
            "testGetProtocolFee-30: not whitelisted, danger zone",
            false,
            TransferPoolFeeCalculator.BalanceDeficitZone.DangerZone,
            1,
            1,
            1_000_000 * (10 ** globalDecimals),
            900 * (10 ** globalDecimals)
        );
        _testGetProtocolFee(
            "testGetProtocolFee-40: whitelisted, no fee zone",
            true,
            TransferPoolFeeCalculator.BalanceDeficitZone.NoFeeZone,
            1,
            1,
            1_000_000 * (10 ** globalDecimals),
            0
        );

        priceOracle.setCurrentPrice(1, 9e17, 6);
        priceOracle.setCurrentPrice(2, 11e17, 6);
        priceOracle.setPriceDeviationStatus(
            IStableTokenPriceOracle.PriceDeviationStatus.Drift
        );
        _testGetProtocolFee(
            "testGetProtocolFee-50: not whitelisted, drift",
            false,
            TransferPoolFeeCalculator.BalanceDeficitZone.SafeZone,
            1,
            2,
            1_000_000 * (10 ** globalDecimals),
            900 * (10 ** globalDecimals) + 181818181818181818181818
        );
    }

    function _testGetProtocolFee(
        string memory testCase,
        bool whitelisted,
        TransferPoolFeeCalculator.BalanceDeficitZone balanceDeficitZone,
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountGD,
        uint256 expectedProtocolFee
    ) public {
        uint256 protocolFee = feeCalculator.getProtocolFee(
            whitelisted,
            balanceDeficitZone,
            srcPoolId,
            dstPoolId,
            amountGD
        );
        assertEq(protocolFee, expectedProtocolFee, testCase);
    }

    function testGetEqReward() public {
        _testGetEqReward(
            "testGetEqReward-10: totalLiquidity = poolBalance",
            false,
            1_000_000e18,
            1_000_000e18,
            600e18,
            10_000e18,
            10e18,
            0
        );
        _testGetEqReward(
            "testGetEqReward-20: totalLiquidity < poolBalance",
            false,
            1_000_000e18,
            900_000e18,
            600e18,
            10_000e18,
            10e18,
            0
        );
        _testGetEqReward(
            "testGetEqReward-30: not whitelisted, rate = EQ_REWARD_RATE_THRESHOLD",
            false,
            1_000_000e18,
            1_100_000e18,
            60e18, // rate = 60 / 100_000 = 6bp
            10_000e18,
            10e18,
            0
        );
        _testGetEqReward(
            "testGetEqReward-40: not whitelisted, rate < EQ_REWARD_RATE_THRESHOLD",
            false,
            1_000_000e18,
            1_100_000e18,
            50e18, // rate = 50 / 100_000 = 5bp
            10_000e18,
            10,
            0
        );
        _testGetEqReward(
            "testGetEqReward-50: not whitelisted, rate > EQ_REWARD_RATE_THRESHOLD",
            false,
            1_000_000e18,
            1_100_000e18,
            70e18, // rate = 70 / 100_000 = 7bp
            10_000e18,
            10e18,
            7e18
        );
        _testGetEqReward(
            "testGetEqReward-60: whitelisted, rate < EQ_REWARD_RATE_THRESHOLD",
            true,
            1_000_000e18,
            1_100_000e18,
            50e18, // rate = 50 / 100_000 = 5bp
            10_000e18,
            10e18,
            5e18
        );
        _testGetEqReward(
            "testGetEqReward-70: whitelisted, rate = EQ_REWARD_RATE_THRESHOLD",
            true,
            1_000_000e18,
            1_100_000e18,
            60e18, // rate = 60 / 100_000 = 6bp
            10_000e18,
            10e18,
            6e18
        );
        _testGetEqReward(
            "testGetEqReward-80: exReward = protocolFee",
            true,
            1_000_000e18,
            1_100_000e18,
            60e18, // rate = 60 / 100_000 = 6bp
            10_000e18,
            6e18,
            6e18
        );
        _testGetEqReward(
            "testGetEqReward-90: exReward > protocolFee",
            true,
            1_000_000e18,
            1_100_000e18,
            60e18, // rate = 60 / 100_000 = 6bp
            10_000e18,
            5e18,
            5e18
        );
        _testGetEqReward(
            "testGetEqReward-100: exReward > eqFeePool",
            false,
            250049864496, // poolBalance
            250067396281, // totalLiquidity
            10525, // eqFeePool
            50000000, // amountGD
            250000, // protocolFee
            10525 // eqReward. calc result is 30016 but it's rounded to eqFeePool
        );
        _testGetEqReward(
            "testGetEqReward-101: exReward > eqFeePool > protocolFee",
            false,
            250049864496, // poolBalance
            250067396281, // totalLiquidity
            10525, // eqFeePool
            50000000, // amountGD
            2500, // protocolFee
            2500 // eqReward. calc result is 30016 but it's rounded to eqEqFeePool and protocolFee
        );
    }

    function testGetLpFee() public {
        _testGetLpFee(
            "testGetLpFee-10: not whitelisted, hasEqReward",
            false,
            true,
            200e18,
            68e14
        );
        _testGetLpFee(
            "testGetLpFee-20: not whitelisted, not hasEqReward",
            false,
            false,
            200e18,
            200e14
        );
        _testGetLpFee(
            "testGetLpFee-30: whitelisted, hasEqReward",
            true,
            true,
            200e18,
            0
        );
        _testGetLpFee(
            "testGetLpFee-40: whitelisted, not hasEqReward",
            true,
            false,
            200e18,
            0
        );
    }

    function testGetDriftProtocolFee() public {
        priceOracle.setCurrentPrice(1, 9e17, 6);
        priceOracle.setCurrentPrice(2, 11e17, 6);

        _testGetDriftProtocolFee(
            "testGetDriftProtocolFee-10: same PoolId",
            IStableTokenPriceOracle.PriceDeviationStatus.Drift,
            1,
            1,
            10000,
            0
        );
        _testGetDriftProtocolFee(
            "testGetDriftProtocolFee-20: normal status",
            IStableTokenPriceOracle.PriceDeviationStatus.Normal,
            1,
            2,
            10000,
            0
        );
        _testGetDriftProtocolFee(
            "testGetDriftProtocolFee-30: drift status, src pool price < dst pool price",
            IStableTokenPriceOracle.PriceDeviationStatus.Drift,
            1,
            2,
            10000,
            1818 // (10000 * (11 - 9)) / 11
        );
        _testGetDriftProtocolFee(
            "testGetDriftProtocolFee-40: drift status, src pool price > dst pool price",
            IStableTokenPriceOracle.PriceDeviationStatus.Drift,
            2,
            1,
            10000,
            0
        );
    }

    function testGetDriftProtocolFeeDecimalsSrcGtDst() public {
        priceOracle.setCurrentPrice(1, 9e18, 7);
        priceOracle.setCurrentPrice(2, 11e17, 6);

        _testGetDriftProtocolFee(
            "testGetDriftProtocolFeeDecimalsSrcGtDst",
            IStableTokenPriceOracle.PriceDeviationStatus.Drift,
            1,
            2,
            10000,
            1818 // (10000 * (11e11 - 9e11)) / 11e11 = 10000 * 2 / 11 = 1818
        );
    }

    function testGetDriftProtocolFeeDecimalsSrcLtDst() public {
        priceOracle.setCurrentPrice(1, 9e17, 6);
        priceOracle.setCurrentPrice(2, 11e18, 7);

        _testGetDriftProtocolFee(
            "testGetDriftProtocolFeeDecimalsSrcGtDst",
            IStableTokenPriceOracle.PriceDeviationStatus.Drift,
            1,
            2,
            10000,
            1818 // (10000 * (11e11 - 9e11)) / 11e11 = 10000 * 2 / 11 = 1818
        );
    }

    function testCalcFee() public {
        vm.expectEmit(true, true, false, true);
        emit TransferPoolFeeCalculator.SetTokenId(1, 3939);
        // set high price rate for avoididing from minimum protocol fee
        feeCalculator.setTokenId(1, 3939);

        ITransferPoolFeeCalculator.SrcPoolInfo
            memory srcPoolInfo = _srcPoolInfo(
                address(0x1),
                1,
                18,
                1000e18,
                1000e18,
                0
            );
        IPool.PeerPoolInfo memory dstPoolInfo = _dstPoolInfo(
            1,
            1000e18,
            1000e18
        );
        _testCalcFee(
            "testCalcFee-10: not whitelisted, no fee zone, no reward",
            srcPoolInfo,
            dstPoolInfo,
            address(0x1),
            100e18,
            ITransferPoolFeeCalculator.FeeInfo(
                100e18 - 87000000000000000 - 10000000000000000 - 0,
                87000000000000000,
                10000000000000000,
                0,
                0,
                0
            )
        );

        dstPoolInfo = _dstPoolInfo(2, 1000e18, 1000e18);
        _testCalcFee(
            "testCalcFee-20: same result as testCalcFee-10, since the fee does not change regardless of whether the pool is the same or different",
            srcPoolInfo,
            dstPoolInfo,
            address(0x1),
            100e18,
            ITransferPoolFeeCalculator.FeeInfo(
                100e18 - 87000000000000000 - 10000000000000000 - 0,
                87000000000000000,
                10000000000000000,
                0,
                0,
                0
            )
        );

        vm.expectEmit(true, true, false, true);
        emit TransferPoolFeeCalculator.SetWhitelist(address(0x1), true);
        feeCalculator.setWhitelist(address(0x1), true);
        _testCalcFee(
            "testCalcFee-30: whitelisted, no fee zone, no reward",
            srcPoolInfo,
            dstPoolInfo,
            address(0x1),
            100e18,
            ITransferPoolFeeCalculator.FeeInfo(100e18, 0, 0, 0, 0, 0)
        );

        vm.expectEmit(true, true, false, true);
        emit TransferPoolFeeCalculator.SetWhitelist(address(0x1), false);
        feeCalculator.setWhitelist(address(0x1), false);

        dstPoolInfo = _dstPoolInfo(1, 600e18, 1000e18);
        _testCalcFee(
            "testCalcFee-40: not whitelisted, safe zone, no reward",
            srcPoolInfo,
            dstPoolInfo,
            address(0x1),
            100e18,
            ITransferPoolFeeCalculator.FeeInfo(
                100e18 -
                    90000000000000000 -
                    10000000000000000 -
                    72727272727272700,
                90000000000000000,
                10000000000000000,
                72727272727272700,
                0,
                0
            )
        );

        dstPoolInfo = _dstPoolInfo(1, 149e18, 1000e18);
        _testCalcFee(
            "testCalcFee-50: not whitelisted, danger zone, no reward",
            srcPoolInfo,
            dstPoolInfo,
            address(0x1),
            100e18,
            ITransferPoolFeeCalculator.FeeInfo(
                100e18 -
                    90000000000000000 -
                    10000000000000000 -
                    2390800000000000000,
                90000000000000000,
                10000000000000000,
                2390800000000000000,
                0,
                0
            )
        );

        srcPoolInfo = _srcPoolInfo(
            address(0x1),
            1,
            18,
            900e18,
            1000e18,
            100e15
        );
        dstPoolInfo = _dstPoolInfo(1, 1000e18, 1000e18);
        _testCalcFee(
            "testCalcFee-60: not whitelisted, no fee zone, reward capped by protocol fee",
            srcPoolInfo,
            dstPoolInfo,
            address(0x1),
            100e18,
            ITransferPoolFeeCalculator.FeeInfo(
                100e18 - 87000000000000000 - 3400000000000000 - 0,
                87000000000000000,
                3400000000000000,
                0,
                87000000000000000,
                0
            )
        );

        srcPoolInfo = _srcPoolInfo(
            address(0x1),
            1,
            18,
            900e18,
            1000e18,
            700e14
        );
        _testCalcFee(
            "testCalcFee-70: not whitelisted, no fee zone, reward less than protocol fee",
            srcPoolInfo,
            dstPoolInfo,
            address(0x1),
            100e18,
            ITransferPoolFeeCalculator.FeeInfo(
                100e18 - 87000000000000000 - 3400000000000000 - 0,
                87000000000000000,
                3400000000000000,
                0,
                70000000000000000,
                0
            )
        );

        dstPoolInfo = _dstPoolInfo(2, 1000e18, 1000e18);
        priceOracle.setPriceDeviationStatus(
            IStableTokenPriceOracle.PriceDeviationStatus.Drift
        );
        priceOracle.setCurrentPrice(1, 9e17, 6);
        priceOracle.setCurrentPrice(2, 11e17, 6);
        _testCalcFee(
            "testCalcFee-80: not whitelisted, no fee zone, reward less than protocol fee, drift",
            srcPoolInfo,
            dstPoolInfo,
            address(0x1),
            100e18,
            ITransferPoolFeeCalculator.FeeInfo(
                100e18 -
                    (87000000000000000 + 18181818181818181818) -
                    3400000000000000 -
                    0,
                87000000000000000 + 18181818181818181818,
                3400000000000000,
                0,
                70000000000000000,
                0
            )
        );

        dstPoolInfo = _dstPoolInfo(1, 1000e18, 1000e18);
        _testCalcFee(
            "testCalcFee-90: not whitelisted, no fee zone, reward less than protocol fee",
            srcPoolInfo,
            dstPoolInfo,
            address(0x1),
            100e18,
            ITransferPoolFeeCalculator.FeeInfo(
                100e18 - 87000000000000000 - 3400000000000000 - 0,
                87000000000000000,
                3400000000000000,
                0,
                70000000000000000,
                0
            )
        );
    }

    function testCalcFeeMinimumTransactionFee() public {
        vm.expectEmit(true, true, false, true);
        emit TransferPoolFeeCalculator.SetTokenId(1, 3939);
        feeCalculator.setTokenId(1, 3939);
        // Set token price equal to the minimum, so the minimum fee is 1 token.
        ITransferPoolFeeCalculator.SrcPoolInfo
            memory srcPoolInfo = _srcPoolInfo(
                address(0x1),
                1,
                18,
                1000e18,
                1000e18,
                0
            );
        IPool.PeerPoolInfo memory dstPoolInfo = _dstPoolInfo(
            1,
            1000e18,
            1000e18
        );
        /**
         * protocolfee: 100e18 * 9bps - 0.3bps (PROTOCOL_SUBSIDY) = 0.087e18
         * lpfee: 100e18 * 1bps = 0.01e18
         * txFee:  = protocolFee + lpFee = 0.097e18
         * minimumFee: MINIMUM_TRANSACTION_FEE_ETH_D18 = 0.0001e18 < txFee
         */
        _testCalcFee(
            "testCalcFeeMinimumTransactionFee-10: not whitelisted, no fee zone, no reward, protocolFee + lpFee < minimum fee unenforced",
            srcPoolInfo,
            dstPoolInfo,
            address(0x1),
            100e18, // amountGD
            ITransferPoolFeeCalculator.FeeInfo(
                100e18 - 0.087e18 - 0.01e18 - 0,
                0.087e18, // protocolFee
                0.01e18, // lpFee
                0, // eqFee
                0, // eqReward
                0 // lastKnownBalance
            )
        );

        /**
         * protocolfee: 0.1e18 * 9bps - 0.3bps (PROTOCOL_SUBSIDY) = 0.000087e18
         * lpfee: 0.1e18 * 1bps = 0.00001e18
         * txFee:  = protocolFee + lpFee = 0.000097e18 < minimumFee
         * since protocol fee + lp fee < min fee, so protocol fee need to adjust to meet the min fee, which is min fee - lp fee = 0.000003e18
         */
        _testCalcFee(
            "testCalcFeeMinimumTransactionFee-20: not whitelisted, no fee zone, protocolFee + lpFee < minimum fee enforced",
            srcPoolInfo,
            dstPoolInfo,
            address(0x1),
            0.1e18,
            ITransferPoolFeeCalculator.FeeInfo(
                0.1e18 - (0.000087e18 + 0.000003e18) - 0.00001e18 - 0,
                0.000087e18 + 0.000003e18,
                0.00001e18,
                0,
                0,
                0
            )
        );

        /*
         * protocolfee: 100e18 * 9bps - 0.3bps (PROTOCOL_SUBSIDY) = 0.087e18
         * lp fee = 100e18 * 0.34bps = 0.0034e18
         * reward capped by protocol fee, so eqReward = 0.087e18
         * protocol fee + lp fee > min fee
         */
        srcPoolInfo = _srcPoolInfo(
            address(0x1),
            1,
            18,
            900e18,
            1000e18,
            700e15
        );
        dstPoolInfo = _dstPoolInfo(1, 1000e18, 1000e18);
        _testCalcFee(
            "testCalcFeeTransactionProtocolFee-30: not whitelisted, no fee zone, reward capped by protocol fee",
            srcPoolInfo,
            dstPoolInfo,
            address(0x1),
            100e18,
            ITransferPoolFeeCalculator.FeeInfo(
                100e18 - 0.087e18 - 0.0034e18 - 0,
                0.087e18,
                0.0034e18,
                0,
                0.087e18,
                0
            )
        );

        /*
         * lp fee = 0.0001e18 * 0.34bps = 0.0000000034e18
         * protocolfee: 0.0001e18 * 9bps = 0.09e18 < min fee. so adjust to min fee - lp fee = 0.0001e18 - 0.0000000034e18 = 0.0000999966e18
         */
        srcPoolInfo = _srcPoolInfo(
            address(0x1),
            1,
            18,
            900e18,
            1000e18,
            700e14
        );
        dstPoolInfo = _dstPoolInfo(1, 1000e18, 1000e18);
        _testCalcFee(
            "testCalcFeeMinimumTransactionFee-40: not whitelisted, no fee zone, has reward, insufficient amount",
            srcPoolInfo,
            dstPoolInfo,
            address(0x1),
            0.0001e18,
            ITransferPoolFeeCalculator.FeeInfo(
                0, // insufficient amount.
                0.0000999966e18, //
                0.0000000034e18,
                0,
                0.00000007e18,
                0
            )
        );

        /*
         * whitelisted
         * lp fee = 0
         * protocolfee: 0
         */
        vm.expectEmit(true, true, false, true);
        emit TransferPoolFeeCalculator.SetWhitelist(address(0x1), true);
        feeCalculator.setWhitelist(address(0x1), true);
        srcPoolInfo = _srcPoolInfo(address(0x1), 1, 18, 1000e18, 1000e18, 0);
        dstPoolInfo = _dstPoolInfo(1, 1000e18, 1000e18);
        _testCalcFee(
            "testCalcFeeMinimumTransactionFee-50: whitelisted, no fee zone, no reward",
            srcPoolInfo,
            dstPoolInfo,
            address(0x1),
            100e18, // amountGD
            ITransferPoolFeeCalculator.FeeInfo(100e18, 0, 0, 0, 0, 0)
        );
    }

    function testCalcFeeRevertsWhenStatusIsDepeg() public {
        priceOracle.setPriceDeviationStatus(
            IStableTokenPriceOracle.PriceDeviationStatus.Depeg
        );

        ITransferPoolFeeCalculator.SrcPoolInfo
            memory srcPoolInfo = _srcPoolInfo(
                address(0x1),
                1,
                18,
                900e18,
                1000e18,
                700e14
            );
        IPool.PeerPoolInfo memory dstPoolInfo = _dstPoolInfo(
            2,
            1000e18,
            1000e18
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiDepeg.selector,
                srcPoolInfo.id
            )
        );
        _testCalcFee(
            "depeg",
            srcPoolInfo,
            dstPoolInfo,
            address(0x1),
            100e18,
            ITransferPoolFeeCalculator.FeeInfo(0, 0, 0, 0, 0, 0)
        );
    }

    function testCalcFeeRevertsWhenPoolHasInsufficientBalance() public {
        ITransferPoolFeeCalculator.SrcPoolInfo
            memory srcPoolInfo = _srcPoolInfo(
                address(0x1),
                1,
                18,
                10000e18,
                10000e18,
                10000e18
            );
        IPool.PeerPoolInfo memory dstPoolInfo = _dstPoolInfo(
            2,
            9000e18,
            10000e18
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiInsufficientPoolLiquidity.selector,
                9000e18,
                10000e18
            )
        );
        _testCalcFee(
            "insufficient balance",
            srcPoolInfo,
            dstPoolInfo,
            address(0x1),
            10000e18,
            ITransferPoolFeeCalculator.FeeInfo(0, 0, 0, 0, 0, 0)
        );
    }

    function _testGetEqFee(
        string memory testCase,
        bool whitelisted,
        TransferPoolFeeCalculator.BalanceDeficitZone balanceDeficitZone,
        uint256 afterBalance,
        uint256 targetBalance,
        uint256 amountGD,
        uint256 expectedEqFee
    ) internal {
        uint256 eqFee = feeCalculator.getEqFee(
            whitelisted,
            balanceDeficitZone,
            afterBalance,
            targetBalance,
            amountGD
        );
        assertEq(eqFee, expectedEqFee, testCase);
    }

    function _testGetEqReward(
        string memory testCase,
        bool whitelisted,
        uint256 poolBalance,
        uint256 totalLiquidity,
        uint256 eqFee,
        uint256 amountGD,
        uint256 protocolFee,
        uint256 expectedEqReward
    ) internal {
        uint256 eqReward = feeCalculator.getEqReward(
            whitelisted,
            poolBalance,
            totalLiquidity,
            eqFee,
            amountGD,
            protocolFee
        );
        assertEq(eqReward, expectedEqReward, testCase);
    }

    function _testGetLpFee(
        string memory testCase,
        bool whitelisted,
        bool hasEqReward,
        uint256 amountGD,
        uint256 expectedLpFee
    ) internal {
        uint256 lpFee = feeCalculator.getLpFee(
            whitelisted,
            hasEqReward,
            amountGD
        );
        assertEq(lpFee, expectedLpFee, testCase);
    }

    function _testGetDriftProtocolFee(
        string memory testCase,
        IStableTokenPriceOracle.PriceDeviationStatus status,
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountGD,
        uint256 expectedDriftProtocolFee
    ) internal {
        priceOracle.setPriceDeviationStatus(status);
        uint256 fee = feeCalculator.getDriftProtocolFee(
            srcPoolId,
            dstPoolId,
            amountGD
        );
        assertEq(fee, expectedDriftProtocolFee, testCase);
    }

    function _testCalcFee(
        string memory testCase,
        ITransferPoolFeeCalculator.SrcPoolInfo memory srcPoolInfo,
        IPool.PeerPoolInfo memory dstPoolInfo,
        address from,
        uint256 amountGD,
        ITransferPoolFeeCalculator.FeeInfo memory expectedFeeInfo
    ) internal {
        ITransferPoolFeeCalculator.FeeInfo memory feeInfo = feeCalculator
            .calcFee(srcPoolInfo, dstPoolInfo, from, amountGD);

        assertEq(
            feeInfo.amountGD,
            expectedFeeInfo.amountGD,
            string.concat(testCase, ": amountGD")
        );

        assertEq(
            feeInfo.protocolFee,
            expectedFeeInfo.protocolFee,
            string.concat(testCase, ": protocolFee")
        );

        assertEq(
            feeInfo.lpFee,
            expectedFeeInfo.lpFee,
            string.concat(testCase, ": lpFee")
        );

        assertEq(
            feeInfo.eqFee,
            expectedFeeInfo.eqFee,
            string.concat(testCase, ": eqFee")
        );

        assertEq(
            feeInfo.eqReward,
            expectedFeeInfo.eqReward,
            string.concat(testCase, ": eqReward")
        );

        assertEq(
            feeInfo.lastKnownBalance,
            expectedFeeInfo.lastKnownBalance,
            string.concat(testCase, ": lastKnownBalance")
        );
    }

    function _srcPoolInfo(
        address addr,
        uint256 id,
        uint8 globalDecimals,
        uint256 balance,
        uint256 totalLiquidity,
        uint256 eqFeePool
    ) internal pure returns (ITransferPoolFeeCalculator.SrcPoolInfo memory) {
        return
            ITransferPoolFeeCalculator.SrcPoolInfo({
                addr: addr,
                id: id,
                globalDecimals: globalDecimals,
                balance: balance,
                totalLiquidity: totalLiquidity,
                eqFeePool: eqFeePool
            });
    }

    function _dstPoolInfo(
        uint256 id,
        uint256 balance,
        uint256 targetBalance
    ) internal pure returns (IPool.PeerPoolInfo memory) {
        return
            IPool.PeerPoolInfo({
                chainId: 1, // not used
                id: id,
                weight: 1, // not used
                balance: balance,
                targetBalance: targetBalance,
                lastKnownBalance: 0, // not used
                credits: 0, // not used
                ready: true
            });
    }
}
