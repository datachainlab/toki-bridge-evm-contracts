// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/TokenPriceOracle.sol";
import "../src/GasPriceOracle.sol";
import "../src/mocks/MockPriceFeed.sol";

import "../src/library/MessageType.sol";
import "../src/replaceable/RelayerFeeCalculator.sol";
import "../src/interfaces/IRelayerFeeCalculator.sol";

contract RelayerFeeCalculatorTest is Test {
    // constants defined in contract
    int256 public constant SRC_TOKEN_PRICE = 100;
    int256 public constant DST_TOKEN_PRICE = 111;
    uint256 public constant SRC_GAS_PRICE = 10000;
    uint256 public constant DST_GAS_PRICE = 20000;
    uint256 public constant GAS_USED = 100_000;
    uint256 public constant PREMIUM_D4 = 12000;

    // default parameters
    uint256 public constant SRC_CHAIN_ID = 1;
    uint256 public constant SRC_POOL_ID = 1;
    uint256 public constant DST_CHAIN_ID = 2;

    TokenPriceOracle public tokenPriceOracle;
    MockPriceFeed public srcTokenPriceFeed;
    MockPriceFeed public dstTokenPriceFeed;

    GasPriceOracle public gasPriceOracle;

    RelayerFeeCalculator public relayerFeeCalculator;

    function setUp() public {
        // setup TokenPriceOracle
        {
            tokenPriceOracle = new TokenPriceOracle(10 * 1e14);

            srcTokenPriceFeed = new MockPriceFeed(SRC_TOKEN_PRICE);
            tokenPriceOracle.setPriceFeedAddress(
                SRC_CHAIN_ID,
                address(srcTokenPriceFeed)
            );

            dstTokenPriceFeed = new MockPriceFeed(DST_TOKEN_PRICE);
            tokenPriceOracle.setPriceFeedAddress(
                DST_CHAIN_ID,
                address(dstTokenPriceFeed)
            );
        }

        // setup GasPriceOracle
        {
            gasPriceOracle = new GasPriceOracle();
            gasPriceOracle.updatePrice(SRC_CHAIN_ID, SRC_GAS_PRICE);
            gasPriceOracle.updatePrice(DST_CHAIN_ID, DST_GAS_PRICE);
        }

        vm.chainId(SRC_CHAIN_ID);
        relayerFeeCalculator = new RelayerFeeCalculator(
            address(tokenPriceOracle),
            address(gasPriceOracle),
            GAS_USED,
            PREMIUM_D4
        );
    }

    function testConstructorFailWithZeroTokenPriceOracle() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "tokenPriceOracle"
            )
        );

        new RelayerFeeCalculator(
            address(0),
            address(gasPriceOracle),
            GAS_USED,
            PREMIUM_D4
        );
    }

    function testConstructorFailWithZeroGasPriceOracle() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "gasPriceOracle"
            )
        );

        new RelayerFeeCalculator(
            address(tokenPriceOracle),
            address(0),
            GAS_USED,
            PREMIUM_D4
        );
    }

    function testVersion() public {
        assertEq(relayerFeeCalculator.version(), "1.0.0");
    }

    function testSet() public {
        vm.expectEmit(true, false, false, true);
        emit RelayerFeeCalculator.SetTokenPriceOracle(address(0x2));
        relayerFeeCalculator.setTokenPriceOracle(address(0x2));
        assertEq(
            relayerFeeCalculator.tokenPriceOracle(),
            address(0x2),
            "setTokenPriceOracle"
        );

        vm.expectEmit(true, false, false, true);
        emit RelayerFeeCalculator.SetGasPriceOracle(address(0x1));
        relayerFeeCalculator.setGasPriceOracle(address(0x1));
        assertEq(
            relayerFeeCalculator.gasPriceOracle(),
            address(0x1),
            "setGasPriceOracle"
        );

        vm.expectEmit(true, false, false, true);
        emit RelayerFeeCalculator.SetGasUsed(3939);
        relayerFeeCalculator.setGasUsed(3939);
        assertEq(relayerFeeCalculator.gasUsed(), 3939, "setGasUsed");

        vm.expectEmit(true, false, false, true);
        emit RelayerFeeCalculator.SetPremiumBPS(12345);
        relayerFeeCalculator.setPremiumBPS(12345);
        assertEq(relayerFeeCalculator.premiumBPS(), 12345, "setPremium");
    }

    function testSetOracleRevertsWhenSenderIsNotSetter() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(0x01),
                relayerFeeCalculator.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(address(0x01));
        relayerFeeCalculator.setTokenPriceOracle(address(0x2));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(0x01),
                relayerFeeCalculator.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(address(0x01));
        relayerFeeCalculator.setGasPriceOracle(address(0x1));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(0x01),
                relayerFeeCalculator.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(address(0x01));
        relayerFeeCalculator.setGasUsed(3939);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(0x01),
                relayerFeeCalculator.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(address(0x01));
        relayerFeeCalculator.setPremiumBPS(12345);
    }

    function testSetOracleRevertsWhenTokenPriceOracleIsZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "tokenPriceOracle"
            )
        );
        relayerFeeCalculator.setTokenPriceOracle(address(0x0));
    }

    function testSetOracleRevertsWhenGasPriceOracleIsZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "gasPriceOracle"
            )
        );
        relayerFeeCalculator.setGasPriceOracle(address(0x0));
    }

    function testCalcFee() public {
        vm.chainId(SRC_CHAIN_ID);
        assertEq(
            relayerFeeCalculator
                .calcFee(MessageType._TYPE_TRANSFER_POOL, DST_CHAIN_ID)
                .fee,
            2664_000_000,
            // GAS_USED * DST_GAS_PRICE * PREMIUM_D4 * DST_TOKEN_PRICE / (10000 * SRC_TOKEN_PRICE),
            "calcFee(TransferPool)"
        );

        assertEq(
            relayerFeeCalculator
                .calcFee(MessageType._TYPE_WITHDRAW, DST_CHAIN_ID)
                .fee,
            2664_000_000 + 1200_000_000,
            // + GAS_USED * SRC_GAS_PRICE * PREMIUM_D4 * / 10000,
            "calcFee(WithdrawLocal)"
        );

        assertEq(
            relayerFeeCalculator
                .calcFee(MessageType._TYPE_WITHDRAW_CHECK, DST_CHAIN_ID)
                .fee,
            0,
            "calcFee(WithdrawCheck)"
        );

        assertEq(
            relayerFeeCalculator
                .calcFee(MessageType._TYPE_TRANSFER_TOKEN, SRC_CHAIN_ID)
                .fee,
            0,
            "calcFee(TransferToken(srcChain))"
        );
    }
}
