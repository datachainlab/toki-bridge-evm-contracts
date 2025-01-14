// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

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
    uint256 public constant GAS_PER_PAYLOAD_LENGTH = 700;
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

            srcTokenPriceFeed = new MockPriceFeed(SRC_TOKEN_PRICE, 8);
            tokenPriceOracle.setPriceFeedAddress(
                SRC_CHAIN_ID,
                address(srcTokenPriceFeed),
                60 * 60 * 24
            );

            dstTokenPriceFeed = new MockPriceFeed(DST_TOKEN_PRICE, 8);
            tokenPriceOracle.setPriceFeedAddress(
                DST_CHAIN_ID,
                address(dstTokenPriceFeed),
                60 * 60 * 24
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
            GAS_PER_PAYLOAD_LENGTH,
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
            GAS_PER_PAYLOAD_LENGTH,
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
            GAS_PER_PAYLOAD_LENGTH,
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
        emit RelayerFeeCalculator.SetGasPerPayloadLength(100);
        relayerFeeCalculator.setGasPerPayloadLength(100);
        assertEq(
            relayerFeeCalculator.gasPerPayloadLength(),
            100,
            "setGasPerPayloadLength"
        );

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
        relayerFeeCalculator.setGasPerPayloadLength(100);

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
        IBCUtils.ExternalInfo memory emptyExternalInfo;
        vm.chainId(SRC_CHAIN_ID);
        assertEq(
            relayerFeeCalculator
                .calcFee(
                    MessageType._TYPE_TRANSFER_POOL,
                    DST_CHAIN_ID,
                    emptyExternalInfo
                )
                .fee,
            2_664_000_000,
            // GAS_USED * DST_GAS_PRICE * PREMIUM_D4 * DST_TOKEN_PRICE / (10000 * SRC_TOKEN_PRICE),
            "calcFee(TransferPool)"
        );

        assertEq(
            relayerFeeCalculator
                .calcFee(
                    MessageType._TYPE_WITHDRAW,
                    DST_CHAIN_ID,
                    emptyExternalInfo
                )
                .fee,
            2_664_000_000 + 1_200_000_000,
            // + GAS_USED * SRC_GAS_PRICE * PREMIUM_D4 * / 10000,
            "calcFee(WithdrawLocal)"
        );

        assertEq(
            relayerFeeCalculator
                .calcFee(
                    MessageType._TYPE_WITHDRAW_CHECK,
                    DST_CHAIN_ID,
                    emptyExternalInfo
                )
                .fee,
            0,
            "calcFee(WithdrawCheck)"
        );

        assertEq(
            relayerFeeCalculator
                .calcFee(
                    MessageType._TYPE_TRANSFER_TOKEN,
                    SRC_CHAIN_ID,
                    emptyExternalInfo
                )
                .fee,
            0,
            "calcFee(TransferToken(srcChain))"
        );
    }

    function testCalcFeeDecimalsSrcLtDst() public {
        uint256 _srcChainId = SRC_CHAIN_ID + 10000;
        uint256 _dstChainId = DST_CHAIN_ID + 10000;
        vm.chainId(_srcChainId);

        gasPriceOracle.updatePrice(_srcChainId, SRC_GAS_PRICE);
        gasPriceOracle.updatePrice(_dstChainId, DST_GAS_PRICE);

        // actual price value is SRC_TOKEN_PRICE * 10^-6 and DST_TOKEN_PRICE * 10^-8
        // so fee is /100 divided in src currency
        MockPriceFeed _srcFeed = new MockPriceFeed(SRC_TOKEN_PRICE, 6);
        MockPriceFeed _dstFeed = new MockPriceFeed(DST_TOKEN_PRICE, 8);

        tokenPriceOracle.setPriceFeedAddress(
            _srcChainId,
            address(_srcFeed),
            3600
        );
        tokenPriceOracle.setPriceFeedAddress(
            _dstChainId,
            address(_dstFeed),
            3600
        );

        IBCUtils.ExternalInfo memory emptyExternalInfo;
        assertEq(
            relayerFeeCalculator
                .calcFee(
                    MessageType._TYPE_TRANSFER_POOL,
                    _dstChainId,
                    emptyExternalInfo
                )
                .fee,
            2664_000_000 / 100,
            "calcFee(TransferPool) 6-8"
        );

        // withdraw local adds gas fee in src chain.
        assertEq(
            relayerFeeCalculator
                .calcFee(
                    MessageType._TYPE_WITHDRAW,
                    _dstChainId,
                    emptyExternalInfo
                )
                .fee,
            (2664_000_000 / 100) + 1200_000_000,
            "calcFee(WithdrawLocal) 6-8"
        );
    }

    function testCalcFeeDecimalsSrcGtDst() public {
        uint256 _srcChainId = SRC_CHAIN_ID + 10000;
        uint256 _dstChainId = DST_CHAIN_ID + 10000;
        vm.chainId(_srcChainId);

        gasPriceOracle.updatePrice(_srcChainId, SRC_GAS_PRICE);
        gasPriceOracle.updatePrice(_dstChainId, DST_GAS_PRICE);

        // actual price value is SRC_TOKE_PRICE * 10^-8 and DST_TOKEN_PRICE * 10^-6
        // so fee is *100 multiplied in src currency
        MockPriceFeed _srcFeed = new MockPriceFeed(SRC_TOKEN_PRICE, 8);
        MockPriceFeed _dstFeed = new MockPriceFeed(DST_TOKEN_PRICE, 6);

        tokenPriceOracle.setPriceFeedAddress(
            _srcChainId,
            address(_srcFeed),
            3600
        );

        tokenPriceOracle.setPriceFeedAddress(
            _dstChainId,
            address(_dstFeed),
            3600
        );

        IBCUtils.ExternalInfo memory emptyExternalInfo;
        assertEq(
            relayerFeeCalculator
                .calcFee(
                    MessageType._TYPE_TRANSFER_POOL,
                    _dstChainId,
                    emptyExternalInfo
                )
                .fee,
            2664_000_000 * 100,
            "calcFee(TransferPool) 8-6"
        );

        assertEq(
            relayerFeeCalculator
                .calcFee(
                    MessageType._TYPE_WITHDRAW,
                    _dstChainId,
                    emptyExternalInfo
                )
                .fee,
            (2664_000_000 * 100) + 1200_000_000,
            "calcFee(WithdrawLocal) 8-6"
        );
    }

    function testCalcFeeWithDstOuterGas() public {
        vm.chainId(SRC_CHAIN_ID);
        assertEq(
            relayerFeeCalculator
                .calcFee(
                    MessageType._TYPE_TRANSFER_POOL,
                    DST_CHAIN_ID,
                    IBCUtils.ExternalInfo({
                        payload: new bytes(0),
                        dstOuterGas: 100_000
                    })
                )
                .fee,
            5_328_000_000,
            // (GAS_USED + DST_OUTER_GAS) * DST_GAS_PRICE * PREMIUM_D4 * DST_TOKEN_PRICE / (10000 * SRC_TOKEN_PRICE),
            "payload: 0, dstOuterGas: 100_000"
        );

        assertEq(
            relayerFeeCalculator
                .calcFee(
                    MessageType._TYPE_TRANSFER_TOKEN,
                    DST_CHAIN_ID,
                    IBCUtils.ExternalInfo({
                        payload: new bytes(100),
                        dstOuterGas: 100_000
                    })
                )
                .fee,
            7_192_800_000,
            // (GAS_USED + DST_OUTER_GAS + PAYLOAD_LENGTH * GAS_PER_PAYLOAD_LENGTH) * DST_GAS_PRICE * PREMIUM_D4 * DST_TOKEN_PRICE / (10000 * SRC_TOKEN_PRICE),
            "payload: 100, dstOuterGas: 100_000"
        );
    }
}
