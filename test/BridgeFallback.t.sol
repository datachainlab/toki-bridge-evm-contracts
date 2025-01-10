// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Bridge.sol";
import "../src/BridgeFallback.sol";
import "../src/interfaces/IBridge.sol";
import {Errors} from "@openzeppelin/contracts/utils/Errors.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BridgeFallbackTest is Test {
    uint256 public constant FINNEY = 10 ** 15;
    uint256 public constant ETHER = 10 ** 18;
    uint256 public constant DST_CHAIN_ID = 1;
    uint256 public constant APP_VERSION = 1;
    string public constant PORT = "toki";
    string public constant CHANNEL = "toki-1";

    address public constant ZERO = address(0);
    address public constant IBC_HANDLER = address(0x1);
    address public constant POOL_REPOSITORY = address(0x2);
    address public constant ESCROW = address(0x3);
    address public constant TOKEN_PRICE_ORACLE = address(0x4);
    address public constant FEE_OWNER = address(0x5);
    address public constant RELAYER_FEE_CALCULATOR = address(0x6);

    address public constant ALICE = address(0x101);

    IBridge public bridge;
    /// @dev bridge address is set for test fallback functions
    BridgeFallback public bridgeFallback;

    bytes32 public bridgeDefaultAdminRole;
    bytes32 public bridgeRelayerFeeOwnerRole;

    function setUp() public {
        Bridge b = new Bridge(APP_VERSION, PORT);
        bytes memory initializeData = abi.encodeCall(
            Bridge.initialize,
            Bridge.InitializeParam(
                IBC_HANDLER,
                POOL_REPOSITORY,
                ESCROW,
                TOKEN_PRICE_ORACLE,
                FEE_OWNER,
                RELAYER_FEE_CALCULATOR,
                address(new BridgeFallback(APP_VERSION, PORT)),
                address(new BridgeChannelUpgradeFallback(APP_VERSION, PORT)),
                10000,
                5000,
                2500
            )
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(b), initializeData);
        bridge = IBridge(address(proxy));

        bridgeFallback = BridgeFallback(payable(address(bridge)));
        bridgeFallback.setChainLookup(CHANNEL, DST_CHAIN_ID);

        bridgeDefaultAdminRole = b.DEFAULT_ADMIN_ROLE();
        bridgeRelayerFeeOwnerRole = b.RELAYER_FEE_OWNER_ROLE();
    }

    function testAddRevertReceivePoolFailUnauthorized() public {
        uint256 srcChainId = 1;
        uint64 sequence = 1;
        uint256 srcPoolId = 1;
        uint256 dstPoolId = 2;
        address to = address(0x10);
        ITransferPoolFeeCalculator.FeeInfo memory fee;
        uint256 refuelAmount = 1000;
        IBCUtils.ExternalInfo memory externalInfo;

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiFallbackUnauthorized.selector,
                address(this)
            )
        );
        bridgeFallback.addRevertReceivePool(
            srcChainId,
            sequence,
            srcPoolId,
            dstPoolId,
            to,
            fee,
            refuelAmount,
            externalInfo,
            0
        );
    }

    function testAddRevertReceiveTokenFailUnauthorized() public {
        uint256 srcChainId = 1;
        uint64 sequence = 1;
        string memory denom = "denom";
        uint256 amount = 1000;
        address to = address(0x10);
        uint256 refuelAmount = 1000;
        IBCUtils.ExternalInfo memory externalInfo;

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiFallbackUnauthorized.selector,
                address(this)
            )
        );
        bridgeFallback.addRevertReceiveToken(
            srcChainId,
            sequence,
            denom,
            amount,
            to,
            refuelAmount,
            externalInfo,
            0
        );
    }

    function testAddRevertRefuelFailUnauthorized() public {
        uint256 srcChainId = 1;
        uint64 sequence = 1;
        address to = address(0x10);
        uint256 refuelAmount = 1000;

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiFallbackUnauthorized.selector,
                address(this)
            )
        );
        bridgeFallback.addRevertRefuel(
            srcChainId,
            sequence,
            to,
            refuelAmount,
            0
        );
    }

    function testAddRevertRefuelAndExternalFailUnauthorized() public {
        uint256 srcChainId = 1;
        uint64 sequence = 1;
        address token = address(0x11);
        uint256 amount = 1000;
        address to = address(0x10);
        uint256 refuelAmount = 1000;
        IBCUtils.ExternalInfo memory externalInfo;

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiFallbackUnauthorized.selector,
                address(this)
            )
        );
        bridgeFallback.addRevertRefuelAndExternal(
            srcChainId,
            sequence,
            token,
            amount,
            to,
            refuelAmount,
            externalInfo,
            0
        );
    }

    function testAddRevertExternalFailUnautholized() public {
        uint256 srcChainId = 1;
        uint64 sequence = 1;
        address token = address(0x11);
        uint256 amount = 1000;
        address to = address(0x10);
        IBCUtils.ExternalInfo memory externalInfo;

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiFallbackUnauthorized.selector,
                address(this)
            )
        );
        bridgeFallback.addRevertExternal(
            srcChainId,
            sequence,
            token,
            amount,
            to,
            externalInfo,
            0
        );
    }

    function testAddRevertWithdrawConfirmFailUnauthorized() public {
        uint256 srcChainId = 1;
        uint64 sequence = 1;
        uint256 withdrawLocalPoolId = 1;
        uint256 withdrawCheckPoolId = 2;
        address to = address(0x10);
        uint256 amountGD = 1000;
        uint256 mintAmountGD = 1000;

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiFallbackUnauthorized.selector,
                address(this)
            )
        );
        bridgeFallback.addRevertWithdrawConfirm(
            srcChainId,
            sequence,
            withdrawLocalPoolId,
            withdrawCheckPoolId,
            to,
            amountGD,
            mintAmountGD,
            0
        );
    }

    function testGetChainId() public {
        uint256 actualChainId = bridgeFallback.getChainId(CHANNEL, false);
        assertEq(actualChainId, DST_CHAIN_ID);
        // getChainId is defined in BridgeBase, so this should also work
        uint256 actualChainId2 = bridge.getChainId(CHANNEL, false);
        assertEq(actualChainId2, DST_CHAIN_ID);
    }

    function testGetChainIdFailWithUnegistered() public {
        string memory unregisteredChannel = "unregistered-channel";
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiUnregisteredChainId.selector,
                unregisteredChannel
            )
        );
        bridgeFallback.getChainId(unregisteredChannel, false);
    }

    function testGetChainIdFailWithAppVersionCheck() public {
        // before channel handshake, the channel version is 0
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiInvalidAppVersion.selector,
                0,
                APP_VERSION
            )
        );
        bridgeFallback.getChainId(CHANNEL, true);
    }

    function testSetDefaultFallback() public {
        address changedFallback = address(
            new BridgeFallback(APP_VERSION, PORT)
        );

        vm.expectEmit(address(bridge));
        emit IBridgeManager.SetDefaultFallback(changedFallback);
        bridgeFallback.setDefaultFallback(changedFallback);
        assertEq(address(bridgeFallback.defaultFallback()), changedFallback);
    }

    function testSetDefaultFallbackFailWithZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "fallback_"
            )
        );
        bridgeFallback.setDefaultFallback(ZERO);
    }

    function testSetDefaultFallbackFailWithInvalidAppVersion() public {
        address changedFallback = address(
            new BridgeFallback(APP_VERSION + 1, PORT)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiInvalidAppVersion.selector,
                APP_VERSION,
                APP_VERSION + 1
            )
        );
        bridgeFallback.setDefaultFallback(changedFallback);
    }

    function testSetChannelUpgradeFallback() public {
        address changedFallback = address(
            new BridgeChannelUpgradeFallback(APP_VERSION, PORT)
        );

        vm.expectEmit(address(bridge));
        emit IBridgeManager.SetChannelUpgradeFallback(changedFallback);
        bridgeFallback.setChannelUpgradeFallback(changedFallback);
        assertEq(
            address(bridgeFallback.channelUpgradeFallback()),
            changedFallback
        );
    }

    function testSetChannelUpgradeFallbackFailWithZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "fallback_"
            )
        );
        bridgeFallback.setChannelUpgradeFallback(ZERO);
    }

    function testSetChannelUpgradeFallbackFailWithInvalidAppVersion() public {
        address changedFallback = address(
            new BridgeChannelUpgradeFallback(APP_VERSION + 1, PORT)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiInvalidAppVersion.selector,
                APP_VERSION,
                APP_VERSION + 1
            )
        );
        bridgeFallback.setChannelUpgradeFallback(changedFallback);
    }

    function testSetChainLookup() public {
        uint256 changedChainId = 2;

        vm.expectEmit(address(bridge));
        emit IBridgeManager.SetChainLookup(CHANNEL, changedChainId);
        bridgeFallback.setChainLookup(CHANNEL, changedChainId);
        assertEq(bridgeFallback.getChainId(CHANNEL, false), changedChainId);
    }

    function testSetICS04SendPacket() public {
        address ics04SendPacket = address(0x11);

        vm.expectEmit(address(bridge));
        emit IBridgeManager.SetICS04SendPacket(ics04SendPacket);
        bridgeFallback.setICS04SendPacket(ics04SendPacket);
        assertEq(bridge.ibcAddress(), ics04SendPacket);
    }

    function testSetICS04SendPacketFailWithZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "ics04SendPacket_"
            )
        );
        bridgeFallback.setICS04SendPacket(ZERO);
    }

    function testSetRefuelSrcCap() public {
        uint256 changedCap = 5000 * FINNEY;

        vm.expectEmit(address(bridge));
        emit IBridgeManager.SetRefuelSrcCap(DST_CHAIN_ID, changedCap);
        bridgeFallback.setRefuelSrcCap(CHANNEL, changedCap);
        assertEq(bridgeFallback.refuelSrcCap(DST_CHAIN_ID), changedCap);
    }

    function testSetRefuelDstCap() public {
        uint256 changedCap = 5000 * FINNEY;

        vm.expectEmit(address(bridge));
        emit IBridgeManager.SetRefuelDstCap(changedCap);
        bridgeFallback.setRefuelDstCap(changedCap);
        assertEq(bridgeFallback.refuelDstCap(), changedCap);
    }

    function testSetPoolRepository() public {
        address changedRepository = address(0x12);

        vm.expectEmit(address(bridge));
        emit IBridgeManager.SetPoolRepository(changedRepository);
        bridgeFallback.setPoolRepository(changedRepository);
        assertEq(
            address(bridgeFallback.poolRepository()),
            address(changedRepository)
        );
    }

    function testSetPoolRepositoryFailWithZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "poolRepository_"
            )
        );
        bridgeFallback.setPoolRepository(ZERO);
    }

    function testSetTokenEscrow() public {
        address changedEscrow = address(0x13);

        vm.expectEmit(address(bridge));
        emit IBridgeManager.SetTokenEscrow(changedEscrow);
        bridgeFallback.setTokenEscrow(changedEscrow);
        assertEq(address(bridgeFallback.tokenEscrow()), address(changedEscrow));
    }

    function testSetTokenEscrowFailWithZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "tokenEscrow_"
            )
        );
        bridgeFallback.setTokenEscrow(ZERO);
    }

    function testSetTokenEscrowWithZeroBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "tokenEscrow_"
            )
        );
        bridgeFallback.setTokenEscrow(ZERO);
    }

    function testDrawFailWithZeroToBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(ITokiErrors.TokiZeroAddress.selector, "to")
        );
        bridgeFallback.draw(100, ZERO);
    }

    function testDrawFailUnauthorized() public {
        vm.startPrank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                ALICE,
                bridgeDefaultAdminRole
            )
        );
        bridgeFallback.draw(100, ALICE);
        vm.stopPrank();
    }

    function testDrawFailNoEnoughAmount() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InsufficientBalance.selector,
                0,
                10000
            )
        );
        bridgeFallback.draw(10000, ALICE);
    }

    function testDraw() public {
        uint256 amount = 10000 * ETHER;

        vm.deal(address(bridge), amount);
        vm.expectEmit(address(bridge));
        emit IBridgeManager.Draw(amount, ALICE);
        bridgeFallback.draw(amount, ALICE);
        assertEq(ALICE.balance, amount);
    }

    function testSetRelayerFeeCalculator() public {
        address changedCalculator = address(0x16);
        vm.expectEmit(address(bridge));
        emit IBridgeManager.SetRelayerFeeCalculator(changedCalculator);
        vm.prank(FEE_OWNER);
        bridgeFallback.setRelayerFeeCalculator(changedCalculator);
        assertEq(
            address(bridgeFallback.relayerFeeCalculator()),
            changedCalculator
        );
    }

    function testSetRelayerFeeCalculatorFailUnauthorized() public {
        address changedCalculator = address(0x05);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                bridgeRelayerFeeOwnerRole
            )
        );
        bridgeFallback.setRelayerFeeCalculator(changedCalculator);
    }

    function testSetTokenPriceOracle() public {
        address changedOracle = address(0x14);
        vm.expectEmit(address(bridge));
        emit IBridgeManager.SetTokenPriceOracle(changedOracle);
        bridgeFallback.setTokenPriceOracle(changedOracle);
        assertEq(address(bridgeFallback.tokenPriceOracle()), changedOracle);
    }

    function testSetRetryBlocks() public {
        uint64 receiveRetryBlocks = 100;
        uint64 withdrawRetryBlocks = 200;
        uint64 externalRetryBlocks = 300;

        vm.expectEmit(address(bridge));
        emit IBridgeManager.SetRetryBlocks(
            receiveRetryBlocks,
            withdrawRetryBlocks,
            externalRetryBlocks
        );
        bridgeFallback.setRetryBlocks(
            receiveRetryBlocks,
            withdrawRetryBlocks,
            externalRetryBlocks
        );
        assertEq(bridgeFallback.receiveRetryBlocks(), receiveRetryBlocks);
        assertEq(bridgeFallback.withdrawRetryBlocks(), withdrawRetryBlocks);
        assertEq(bridgeFallback.externalRetryBlocks(), externalRetryBlocks);
    }

    function testSetPremiumBPS() public {
        uint256 changedPremiumBPS = 4000;
        vm.expectEmit(address(bridge));
        emit IBridgeManager.SetPremiumBPS(DST_CHAIN_ID, changedPremiumBPS);
        bridgeFallback.setPremiumBPS(CHANNEL, changedPremiumBPS);
        assertEq(bridgeFallback.premiumBPS(DST_CHAIN_ID), changedPremiumBPS);
    }
}
