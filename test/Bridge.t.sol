// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/mocks/MockPool.sol";
import "../src/mocks/MockIBCPacket.sol";
import "../src/mocks/MockToken.sol";
import "../src/future/interfaces/ITokenEscrow.sol";
import "../src/mocks/MockOuterService.sol";
import "../src/interfaces/IBridge.sol";
import "../src/interfaces/ITokiErrors.sol";
import "../src/interfaces/IPool.sol";
import "../src/interfaces/IPoolRepository.sol";
import "../src/interfaces/ITransferPoolFeeCalculator.sol";
import "../src/interfaces/IRelayerFeeCalculator.sol";
import "../src/interfaces/IBridgeManager.sol";
import "../src/library/IBCUtils.sol";
import "../src/PoolRepository.sol";
import "../src/Bridge.sol";
import "../src/BridgeChannelUpgradeFallback.sol";
import "../src/TokenPriceOracle.sol";
import "../src/GasPriceOracle.sol";
import "../src/replaceable/RelayerFeeCalculator.sol";
import "../src/mocks/MockPriceFeed.sol";
import "../src/mocks/MockUpgradeBridge.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IIBCChannel.sol";
import "@hyperledger-labs/yui-ibc-solidity/contracts/core/25-handler/OwnableIBCHandler.sol";
import {IIBCModule, IIBCModuleInitializer} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/26-router/IIBCModule.sol";
import "@hyperledger-labs/yui-ibc-solidity/contracts/proto/Channel.sol";
import "../src/mocks/MockPayable.sol";

contract Reentrant is ITokiOuterServiceReceiver {
    struct Result {
        bool success;
        bytes data;
    }
    Result public _result;
    address public _addr;
    bytes public _data;

    function onReceivePool(
        string calldata,
        address,
        uint256,
        bytes memory
    ) external override {
        /* solhint-disable-next-line avoid-low-level-calls */
        (bool success, bytes memory data) = _addr.call(_data);
        if (!success) {
            /* solhint-disable-next-line no-inline-assembly */
            assembly {
                let len := mload(data)
                let ptr := add(data, 0x20)
                revert(ptr, len)
            }
        }
    }

    function setCall(address addr, bytes memory data) public {
        _addr = addr;
        _data = data;
    }
}

contract BridgeTest is Test {
    // constants
    uint256 public constant DENOMI = 10 ** 18;
    string public constant PORT = "toki";
    uint256 public constant APP_VERSION = 0; // without handshake
    uint256 public constant SRC_CHAIN_ID = 111;
    string public constant SRC_CHANNEL = "channel-1";
    uint256 public constant DST_CHAIN_ID = 222;
    string public constant DST_CHANNEL = "channel-2";
    uint256 public constant INVALID_CHAIN_ID = 333;

    uint8 internal constant TYPE_TRANSFER_POOL = 1;
    uint8 internal constant TYPE_CREDIT = 2;
    uint8 internal constant TYPE_WITHDRAW = 3;
    uint8 internal constant TYPE_WITHDRAW_CHECK = 4;
    uint8 internal constant TYPE_TRANSFER_TOKEN = 5;

    uint8 internal constant UNRECOVERABLE_ABI_DECODE_FAILED = 0;

    uint64 public bridgeTimeoutTimestamp;
    bytes32 public bridgeDefaultAdminRole;

    // assign parameters
    address payable public empty = payable(address(0x00));
    address payable public alice = payable(address(0x01));
    address payable public bob = payable(address(0x02));
    address payable public relayer = payable(address(0x03));
    bytes public bbob;

    // for test contracts
    IBridge public bridge;
    MockToken public erc20;
    MockPool[] public pools;
    MockIBCPacket public ibcPacket;
    TokenPriceOracle public tokenPriceOracle;
    GasPriceOracle public gasPriceOracle;
    MockPriceFeed public srcPriceFeed;
    MockPriceFeed public dstPriceFeed;
    RelayerFeeCalculator public relayerFeeCalculator;

    MockOuterService public outerService;
    bytes public bouter;

    ERC1967Proxy public prProxy;
    PoolRepository public poolRepository;

    ITokenEscrow public escrow;

    /* ========== EVENTS ========== */
    // for assertion that MockIBCPacket.sendPacket is called with expected arguments in test cases
    event SendPacket(
        string portOnSrc,
        string srcChannel,
        Height.Data timeoutHeight,
        uint64 timeoutTimestamp,
        bytes32 dataHash
    );

    function setUp() public {
        bbob = abi.encodePacked(bob);

        // serup mock outer service
        {
            outerService = new MockOuterService(PORT);
            bouter = abi.encodePacked(address(outerService));
        }

        // setup erc20
        {
            erc20 = new MockToken(
                "MockToken",
                "MOCK",
                13,
                1_000_000_000_000 * DENOMI
            );
        }

        // setup ibcPacket
        {
            ibcPacket = new MockIBCPacket();
        }

        // setup TokenPriceOracle
        {
            tokenPriceOracle = new TokenPriceOracle(10 * 1e14);
            srcPriceFeed = new MockPriceFeed(100_000, 8);
            dstPriceFeed = new MockPriceFeed(200_000, 8);
            tokenPriceOracle.setPriceFeedAddress(
                SRC_CHAIN_ID,
                address(srcPriceFeed)
            );
            tokenPriceOracle.setPriceFeedAddress(
                DST_CHAIN_ID,
                address(dstPriceFeed)
            );
        }

        // setup GasPriceOracle
        {
            gasPriceOracle = new GasPriceOracle();
            gasPriceOracle.updatePrice(SRC_CHAIN_ID, 100);
            gasPriceOracle.updatePrice(DST_CHAIN_ID, 111);
        }

        // setup pool repository
        {
            poolRepository = new PoolRepository();
            prProxy = new ERC1967Proxy(address(poolRepository), "");
            pr().initialize();
        }

        // setup toki escrow
        {
            escrow = ITokenEscrow(address(0x0));
        }

        // setup relayerFeeCalculator;
        {
            relayerFeeCalculator = new RelayerFeeCalculator(
                address(tokenPriceOracle),
                address(gasPriceOracle),
                100_000,
                12000
            );
        }

        // setup bridge contract
        Bridge b = new Bridge(APP_VERSION, PORT);
        bytes memory initializeData = abi.encodeCall(
            Bridge.initialize,
            Bridge.InitializeParam(
                address(ibcPacket),
                address(prProxy),
                address(escrow),
                address(tokenPriceOracle),
                address(this),
                address(relayerFeeCalculator),
                address(new BridgeFallback(APP_VERSION, PORT)),
                address(new BridgeChannelUpgradeFallback(APP_VERSION, PORT)),
                10000,
                5000,
                2500
            )
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(b), initializeData);
        bridge = IBridge(address(proxy));
        bridge.grantRole(b.IBC_HANDLER_ROLE(), address(this));
        bridgeTimeoutTimestamp = b.TIMEOUT_TIMESTAMP();
        bridgeDefaultAdminRole = b.DEFAULT_ADMIN_ROLE();

        pr().grantRole(pr().POOL_SETTER(), address(this));

        for (uint8 i = 0; i < 3; i++) {
            pools.push(new MockPool(i, address(erc20)));
            pr().setPool(i, address(pools[i]));
        }

        vm.expectEmit(address(bridge));
        emit IBridgeManager.SetChainLookup(SRC_CHANNEL, DST_CHAIN_ID);
        bridge.setChainLookup(SRC_CHANNEL, DST_CHAIN_ID);

        vm.expectEmit();
        emit IBridgeManager.SetChainLookup(DST_CHANNEL, SRC_CHAIN_ID);
        bridge.setChainLookup(DST_CHANNEL, SRC_CHAIN_ID);

        vm.expectEmit();
        emit IBridgeManager.SetRefuelSrcCap(DST_CHAIN_ID, 1_000 * DENOMI);
        bridge.setRefuelSrcCap(SRC_CHANNEL, 1_000 * DENOMI);

        vm.expectEmit();
        emit IBridgeManager.SetRefuelSrcCap(SRC_CHAIN_ID, 1_000 * DENOMI);
        bridge.setRefuelSrcCap(DST_CHANNEL, 1_000 * DENOMI);

        vm.expectEmit();
        emit IBridgeManager.SetRefuelDstCap(1_000 * DENOMI);
        bridge.setRefuelDstCap(1_000 * DENOMI);

        // inf approve
        erc20.approve(address(bridge), 1_000_000_000 * DENOMI);
    }

    // ====================== success test cases(router func) =============================
    function testDeposit() public {
        bridge.deposit(0, 100, alice);

        // check pool[0] has 100 balance of mockToken
        assertEq(erc20.balanceOf(address(pools[0])), 100);
        (address _to, uint256 _amount) = pools[0].callMint();
        assertEq(_to, alice);
        assertEq(_amount, 100);
    }

    function testTransferPool() public {
        vm.chainId(SRC_CHAIN_ID);
        // ibcPacket.sendPacket check
        {
            vm.expectEmit(address(ibcPacket));
            emit SendPacket(
                PORT,
                SRC_CHANNEL,
                Height.Data(0, 0),
                bridgeTimeoutTimestamp,
                keccak256(
                    IBCUtils.encodeTransferPool(
                        0,
                        1,
                        ITransferPoolFeeCalculator.FeeInfo(100, 0, 0, 0, 0, 0),
                        IPool.CreditInfo(0, 0),
                        bbob,
                        0,
                        IBCUtils.ExternalInfo("", 0)
                    )
                )
            );
        }

        bridge.transferPool{value: 1 * DENOMI}(
            SRC_CHANNEL,
            0,
            1,
            100,
            0,
            bbob,
            0,
            IBCUtils.ExternalInfo("", 0),
            alice
        );

        // pool.transfer check
        {
            (
                uint256 _dstChainId,
                uint256 _dstPoolId,
                address _from,
                uint256 _amountLD,
                uint256 _minAmountLD,
                bool _newLiquidity
            ) = pools[0].callTransfer();
            assertEq(_dstChainId, DST_CHAIN_ID);
            assertEq(_dstPoolId, 1);
            assertEq(_from, address(this));
            assertEq(_amountLD, 100);
            assertEq(_minAmountLD, 0);
            assertEq(_newLiquidity, true);
        }
        // balance check
        {
            assertEq(erc20.balanceOf(address(pools[0])), 100);
        }
        // pool.sendCredit check
        {
            (uint256 _dstChainId, uint256 _dstPoolId) = pools[0]
                .callSendCredit();
            assertEq(_dstChainId, DST_CHAIN_ID);
            assertEq(_dstPoolId, 1);
        }
    }

    function testTransferPoolFailWithZeroRefundToBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "refundTo"
            )
        );

        bridge.transferPool{value: 1 * DENOMI}(
            SRC_CHANNEL,
            0,
            1,
            100,
            0,
            bbob,
            0,
            IBCUtils.ExternalInfo("", 0),
            empty
        );
    }

    function testTransferPoolFailWithZeroAmountLDBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAmount.selector,
                "amountLD"
            )
        );

        bridge.transferPool{value: 1 * DENOMI}(
            SRC_CHANNEL,
            0,
            1,
            0,
            0,
            bbob,
            0,
            IBCUtils.ExternalInfo("", 0),
            alice
        );
    }

    function testTransferPoolFailRefuelSrcCap() public {
        vm.chainId(SRC_CHAIN_ID);
        bridge.setRefuelSrcCap(SRC_CHANNEL, 999);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiExceed.selector,
                "refuelAmount",
                1000,
                999
            )
        );
        bridge.transferPool{value: 1 * DENOMI}(
            SRC_CHANNEL,
            0,
            1,
            100,
            0,
            bbob,
            1000,
            IBCUtils.ExternalInfo("", 0),
            alice
        );

        vm.expectEmit(true, true, false, true);
        emit IBridgeManager.SetRefuelSrcCap(DST_CHAIN_ID, 1 * DENOMI);
        bridge.setRefuelSrcCap(SRC_CHANNEL, 1 * DENOMI);
        bridge.transferPool{value: 1 * DENOMI}(
            SRC_CHANNEL,
            0,
            1,
            100,
            0,
            bbob,
            1000,
            IBCUtils.ExternalInfo("", 0),
            alice
        );
    }

    function testTransferPoolFailWithoutEnoughNativeFee() public {
        vm.chainId(SRC_CHAIN_ID);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiNotEnoughNativeFee.selector,
                2.664e7,
                1
            )
        );

        bridge.transferPool{value: 1}(
            SRC_CHANNEL,
            0,
            1,
            100,
            0,
            bbob,
            0,
            IBCUtils.ExternalInfo("", 0),
            alice
        );
    }

    function testTransferPoolFailToRefund() public {
        // setup mock payable for refund error testing
        MockPayable mockPayable = new MockPayable();
        mockPayable.setFallbackFail(true);
        mockPayable.setReceiveFail(true);

        vm.chainId(SRC_CHAIN_ID);
        vm.expectRevert(
            abi.encodeWithSelector(ITokiErrors.TokiFailToRefund.selector)
        );

        bridge.transferPool{value: 1 * DENOMI}(
            SRC_CHANNEL,
            0,
            1,
            100,
            0,
            bbob,
            0,
            IBCUtils.ExternalInfo("", 0),
            payable(address(mockPayable))
        );
    }

    function testTransferPoolInLedger() public {
        vm.chainId(SRC_CHAIN_ID);
        bridge.transferPoolInLedger(
            0,
            1,
            100,
            0,
            bob,
            IBCUtils.ExternalInfo("", 0)
        );

        // pool.transfer check
        {
            (
                uint256 _dstChainId,
                uint256 _dstPoolId,
                address _from,
                uint256 _amountLD,
                uint256 _minAmountLD,
                bool _newLiquidity
            ) = pools[0].callTransfer();
            assertEq(_dstChainId, SRC_CHAIN_ID, "callTransfer: chainId");
            assertEq(_dstPoolId, 1, "callTransfer: dstPoolId");
            assertEq(_from, address(this), "callTransfer: from");
            assertEq(_amountLD, 100, "callTransfer: amountLD");
            assertEq(_minAmountLD, 0, "callTransfer: minAmountLD");
            assertEq(_newLiquidity, true, "callTransfer: newLiquidity");
        }
        // balance check
        {
            assertEq(erc20.balanceOf(address(pools[0])), 100, "balance");
        }
        // pool.sendCredit check
        {
            (uint256 _dstChainId, uint256 _dstPoolId) = pools[0]
                .callSendCredit();
            assertEq(_dstChainId, SRC_CHAIN_ID, "callSendCredit: chainId");
            assertEq(_dstPoolId, 1, "callSendCredit: dstPoolId");
        }

        // dstPool.updateCredit check
        {
            (
                uint256 _chainId,
                uint256 _srcPoolId,
                IPool.CreditInfo memory _c
            ) = pools[1].callUpdateCredit();
            assertEq(_chainId, SRC_CHAIN_ID, "callUpdateCredit: chainId");
            assertEq(_srcPoolId, 0, "callUpdateCredit: srcPoolId");
            assertEq(
                abi.encode(_c),
                abi.encode(IPool.CreditInfo(0, 0)),
                "callUpdateCredit: creditInfo"
            );
        }

        // dstPool.recv check
        {
            (
                uint256 _srcChainId,
                uint256 _srcPoolId,
                address _to,
                ITransferPoolFeeCalculator.FeeInfo memory _fee
            ) = pools[1].callRecv();
            assertEq(_srcChainId, SRC_CHAIN_ID, "callRecv: SRC_CHAIN_ID");
            assertEq(_srcPoolId, 0, "callRecv: srcPoolId");
            assertEq(_to, bob, "callRecv: to");
            assertEq(_fee.amountGD, 100, "callRecv: fee.amountGD");
            assertEq(_fee.protocolFee, 0, "callRecv: fee.protocolFee");
            assertEq(_fee.lpFee, 0, "callRecv: fee.lpFee");
            assertEq(_fee.eqFee, 0, "callRecv: fee.eqFee");
            assertEq(_fee.eqReward, 0, "callRecv: fee.eqReward");
            assertEq(
                _fee.lastKnownBalance,
                0,
                "callRecv: fee.lastKnownBalance"
            );
        }
    }

    function testTransferPoolInLedgerReentrant() public {
        vm.chainId(SRC_CHAIN_ID);
        Reentrant reentrant = new Reentrant();
        reentrant.setCall(
            address(bridge),
            abi.encodeWithSelector(
                Bridge.transferPoolInLedger.selector,
                0,
                1,
                100,
                0,
                address(reentrant),
                IBCUtils.ExternalInfo("payload", 0)
            )
        );

        vm.chainId(SRC_CHAIN_ID);
        vm.expectRevert(
            abi.encodeWithSelector(
                ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector
            )
        );
        bridge.transferPoolInLedger(
            0,
            1,
            100,
            0,
            address(reentrant),
            IBCUtils.ExternalInfo("payload", 0)
        );
    }

    function testTransferPoolInLedgerFailWithZeroAmountLDBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAmount.selector,
                "amountLD"
            )
        );

        vm.chainId(SRC_CHAIN_ID);
        bridge.transferPoolInLedger(
            0,
            1,
            0,
            0,
            bob,
            IBCUtils.ExternalInfo("", 0)
        );
    }

    function testTransferPoolInLedgerFailsWithNonZeroDstOuterGas() public {
        vm.chainId(DST_CHAIN_ID);

        uint256 srcPoolId = 0;
        uint256 dstPoolId = 1;
        uint256 amountLD = 1000;
        uint256 minAmountLD = 900;
        address to = address(this);

        // Create an ExternalInfo with non-zero dstOuterGas
        IBCUtils.ExternalInfo memory externalInfo = IBCUtils.ExternalInfo({
            payload: "test payload",
            dstOuterGas: 50000 // Set a non-zero value
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiDstOuterGasShouldBeZero.selector
            )
        );

        bridge.transferPoolInLedger(
            srcPoolId,
            dstPoolId,
            amountLD,
            minAmountLD,
            to,
            externalInfo
        );
    }

    function testWithdrawRemote() public {
        vm.chainId(SRC_CHAIN_ID);
        // ibcPacket.sendPacket check
        {
            vm.expectEmit(address(ibcPacket));
            emit SendPacket(
                PORT,
                SRC_CHANNEL,
                Height.Data(0, 0),
                bridgeTimeoutTimestamp,
                keccak256(
                    IBCUtils.encodeTransferPool(
                        0,
                        1,
                        ITransferPoolFeeCalculator.FeeInfo(200, 0, 0, 0, 0, 0),
                        IPool.CreditInfo(0, 0),
                        bbob,
                        0,
                        IBCUtils.ExternalInfo("", 0)
                    )
                )
            );
        }

        bridge.withdrawRemote{value: 10_000 * DENOMI}(
            SRC_CHANNEL,
            0,
            1,
            200,
            1,
            bbob,
            alice
        );

        // pool.transfer check
        {
            (
                uint256 _dstChainId,
                uint256 _dstPoolId,
                address _from,
                uint256 _amountLD,
                uint256 _minAmountLD,
                bool _newLiquidity
            ) = pools[0].callTransfer();
            assertEq(_dstChainId, DST_CHAIN_ID);
            assertEq(_dstPoolId, 1);
            assertEq(_from, address(this));
            assertEq(_amountLD, 200);
            assertEq(_minAmountLD, 1);
            assertEq(_newLiquidity, false);
        }
        // pool.withrdawRemote check
        {
            (
                uint256 _dstChainId,
                uint256 _dstPoolId,
                address _from,
                uint256 _amount
            ) = pools[0].callWithdrawRemote();
            assertEq(_dstChainId, DST_CHAIN_ID);
            assertEq(_dstPoolId, 1);
            assertEq(_from, address(this));
            assertEq(_amount, 200);
        }
        // pool.sendCredit check
        {
            (uint256 _dstChainId, uint256 _dstPoolId) = pools[0]
                .callSendCredit();
            assertEq(_dstChainId, DST_CHAIN_ID);
            assertEq(_dstPoolId, 1);
        }
    }

    function testWithdrawRemoteFailWithZeroRefundToBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "refundTo"
            )
        );

        bridge.withdrawRemote{value: 10_000 * DENOMI}(
            SRC_CHANNEL,
            0,
            1,
            200,
            1,
            bbob,
            empty
        );
    }

    function testWithdrawRemoteFailWithZeroAmountLPBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAmount.selector,
                "amountLP"
            )
        );

        bridge.withdrawRemote{value: 10_000 * DENOMI}(
            SRC_CHANNEL,
            0,
            1,
            0,
            1,
            bbob,
            alice
        );
    }

    function testWithdrawRemoteInLedger() public {
        vm.chainId(SRC_CHAIN_ID);
        bridge.deposit(0, 100, alice);
        bridge.withdrawRemoteInLedger(0, 1, 200, 1, bob);

        // pool.transfer check
        {
            (
                uint256 _dstChainId,
                uint256 _dstPoolId,
                address _from,
                uint256 _amountLD,
                uint256 _minAmountLD,
                bool _newLiquidity
            ) = pools[0].callTransfer();
            assertEq(_dstChainId, SRC_CHAIN_ID, "transfer: DST_CHAIN_ID");
            assertEq(_dstPoolId, 1, "transfer: dstPoolId");
            assertEq(_from, address(this), "transfer: from");
            assertEq(_amountLD, 200, "transfer: amountLD");
            assertEq(_minAmountLD, 1, "transfer: minAmountLD");
            assertEq(_newLiquidity, false, "transfer: newLiquidity");
        }
        // pool.withrdawRemote check
        {
            (
                uint256 _dstChainId,
                uint256 _dstPoolId,
                address _from,
                uint256 _amount
            ) = pools[0].callWithdrawRemote();
            assertEq(_dstChainId, SRC_CHAIN_ID, "withdrawRemote: DST_CHAIN_ID");
            assertEq(_dstPoolId, 1, "withdrawRemote: dstPoolId");
            assertEq(_from, address(this), "withdrawRemote: from");
            assertEq(_amount, 200, "withdrawRemote: amount");
        }
        // pool.sendCredit check
        {
            (uint256 _dstChainId, uint256 _dstPoolId) = pools[0]
                .callSendCredit();
            assertEq(_dstChainId, SRC_CHAIN_ID, "sendCredit: DST_CHAIN_ID");
            assertEq(_dstPoolId, 1, "sendCredit: dstPoolId");
        }
    }

    function testWithdrawRemoteInLedgerFailWithZeroAmountLPBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAmount.selector,
                "amountLP"
            )
        );
        bridge.withdrawRemoteInLedger(0, 1, 0, 1, bob);
    }

    function testWithdrawLocal() public {
        vm.chainId(SRC_CHAIN_ID);
        // ibcPacket.sendPacket check
        {
            vm.expectEmit(address(ibcPacket));
            emit SendPacket(
                PORT,
                SRC_CHANNEL,
                Height.Data(0, 0),
                bridgeTimeoutTimestamp,
                keccak256(
                    IBCUtils.encodeWithdraw(
                        0,
                        1,
                        300,
                        IPool.CreditInfo(0, 0),
                        bbob
                    )
                )
            );
        }

        bridge.withdrawLocal{value: 1 * DENOMI}(
            SRC_CHANNEL,
            0,
            1,
            300,
            bbob,
            alice
        );

        // pool.withdrawLocal check
        {
            (
                uint256 _dstChainId,
                uint256 _dstPoolId,
                address _from,
                uint256 _amount,
                bytes memory _to
            ) = pools[0].callWithdrawLocal();
            assertEq(_dstChainId, DST_CHAIN_ID);
            assertEq(_dstPoolId, 1);
            assertEq(_from, address(this));
            assertEq(_amount, 300);
            assertEq(_to, bbob);
        }
        // pool.sendCredit check
        {
            (uint256 _dstChainId, uint256 _dstPoolId) = pools[0]
                .callSendCredit();
            assertEq(_dstChainId, DST_CHAIN_ID);
            assertEq(_dstPoolId, 1);
        }
    }

    function testWithdrawLocalFailWithZeroRefundToBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "refundTo"
            )
        );

        bridge.withdrawLocal{value: 1 * DENOMI}(
            SRC_CHANNEL,
            0,
            1,
            300,
            bbob,
            empty
        );
    }

    function testWithdrawLocalFailWithZeroAmountLPBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAmount.selector,
                "amountLP"
            )
        );

        bridge.withdrawLocal{value: 1 * DENOMI}(
            SRC_CHANNEL,
            0,
            1,
            0,
            bbob,
            alice
        );
    }

    function testWithdrawLocalInLedger() public {
        vm.chainId(SRC_CHAIN_ID);
        bridge.withdrawLocalInLedger(0, 1, 300, bob);

        // --- step1. send withdraw ------------------
        // pool.withdrawLocal check
        {
            (
                uint256 _dstChainId,
                uint256 _dstPoolId,
                address _from,
                uint256 _amount,
                bytes memory _to
            ) = pools[0].callWithdrawLocal();
            assertEq(
                _dstChainId,
                SRC_CHAIN_ID,
                "1: withdrawLocal: DST_CHAIN_ID"
            );
            assertEq(_dstPoolId, 1, "1: withdrawLocal: dstPoolId");
            assertEq(_from, address(this), "1: withdrawLocal: from");
            assertEq(_amount, 300, "1: withdrawLocal: amount");
            assertEq(_to, bbob, "1: withdrawLocal: to");
        }
        // pool.sendCredit check
        {
            (uint256 _dstChainId, uint256 _dstPoolId) = pools[0]
                .callSendCredit();
            assertEq(_dstChainId, SRC_CHAIN_ID, "1: sendCredit: DST_CHAIN_ID");
            assertEq(_dstPoolId, 1, "1: sendCredit: dstPoolId");
        }

        // --- step2. recv withdraw and send withdrawCheck------------------
        {
            (
                uint256 _chainId,
                uint256 _srcPoolId,
                IPool.CreditInfo memory _c
            ) = pools[1].callUpdateCredit();
            assertEq(_chainId, SRC_CHAIN_ID, "2: updateCredit: chainId");
            assertEq(_srcPoolId, 0, "2: updateCredit: srcPoolId");
            assertEq(
                abi.encode(_c),
                abi.encode(IPool.CreditInfo(0, 0)),
                "2. updateCredit: creditInfo"
            );
        }
        {
            (
                uint256 _srcChainId,
                uint256 _srcPoolId,
                uint256 _amountGD
            ) = pools[1].callWithdrawCheck();
            assertEq(_srcChainId, SRC_CHAIN_ID, "2: withdrawCheck: chainId");
            assertEq(_srcPoolId, 0, "2: withdrawCheck: srcPoolId");
            assertEq(_amountGD, 300, "2: withdrawCheck: amountGD");
        }
        {
            (uint256 _dstChainId, uint256 _dstPoolId) = pools[1]
                .callSendCredit();
            assertEq(_dstChainId, SRC_CHAIN_ID, "2: sendCredit: DST_CHAIN_ID");
            assertEq(_dstPoolId, 0, "2: sendCredit: dstPoolId");
        }

        // --- step3. recv withdrawCheck ------------------
        {
            (
                uint256 _chainId,
                uint256 _srcPoolId,
                IPool.CreditInfo memory _c
            ) = pools[0].callUpdateCredit();
            assertEq(_chainId, SRC_CHAIN_ID, "3: updateCredit: chainId");
            assertEq(_srcPoolId, 1, "3: updateCredit: srcPoolId");
            assertEq(
                abi.encode(_c),
                abi.encode(IPool.CreditInfo(0, 0)),
                "3. updateCredit: creditInfo"
            );
        }
        {
            (
                uint256 _srcChainId,
                uint256 _srcPoolId,
                address _to,
                uint256 _amountGD,
                uint256 _amountToMintGD
            ) = pools[0].callWithdrawConfirm();
            assertEq(_srcChainId, SRC_CHAIN_ID, "3: withdrawConfirm: chainId");
            assertEq(_srcPoolId, 1, "3: withdrawConfirm: srcPoolId");
            assertEq(_to, bob, "3: withdrawConfirm: to");
            assertEq(_amountGD, 300, "3: withdrawConfirm: amountGD");
            assertEq(
                _amountToMintGD,
                300,
                "3: withdrawConfirm: amountToMintGD"
            );
        }
    }

    function testWithdrawLocalInLedgerFailWithZeroAmountLPBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAmount.selector,
                "amountLP"
            )
        );

        vm.chainId(SRC_CHAIN_ID);
        bridge.withdrawLocalInLedger(0, 1, 0, bob);
    }

    function testSendCredit() public {
        vm.chainId(SRC_CHAIN_ID);
        // ibcPacket.sendPacket check
        {
            vm.expectEmit(address(ibcPacket));
            emit SendPacket(
                PORT,
                SRC_CHANNEL,
                Height.Data(0, 0),
                bridgeTimeoutTimestamp,
                keccak256(IBCUtils.encodeCredit(0, 1, IPool.CreditInfo(0, 0)))
            );
        }

        bridge.sendCredit{value: 1 * DENOMI}(SRC_CHANNEL, 0, 1, alice);
        // pool.sendCredit check
        {
            (uint256 _dstChainId, uint256 _dstPoolId) = pools[0]
                .callSendCredit();
            assertEq(_dstChainId, DST_CHAIN_ID);
            assertEq(_dstPoolId, 1);
        }
    }

    function testSendCreditFailWithZeroRefundToBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "refundTo"
            )
        );

        bridge.sendCredit{value: 1 * DENOMI}(SRC_CHANNEL, 0, 1, empty);
    }

    function testSendCreditFailWithInvalidAppVersion() public {
        /* upgrade bridge with new version */
        address newBridgeImpl = address(
            new MockUpgradeBridge(APP_VERSION + 1, PORT)
        );
        bytes memory initialData = abi.encodeCall(
            MockUpgradeBridge.upgrade,
            (
                address(new BridgeFallback(APP_VERSION + 1, PORT)),
                address(new BridgeChannelUpgradeFallback(APP_VERSION + 1, PORT))
            )
        );
        UUPSUpgradeable(address(bridge)).upgradeToAndCall(
            newBridgeImpl,
            initialData
        );

        /* ibcPacket.sendPacket reverts */
        vm.chainId(SRC_CHAIN_ID);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiInvalidAppVersion.selector,
                APP_VERSION,
                APP_VERSION + 1
            )
        );
        bridge.sendCredit{value: 1 * DENOMI}(SRC_CHANNEL, 0, 1, alice);
    }

    function testSendCreditInLedger() public {
        vm.chainId(SRC_CHAIN_ID);
        uint256 chainId = SRC_CHAIN_ID;
        bridge.sendCreditInLedger(0, 1);
        // pool.sendCredit check
        {
            (uint256 _dstChainId, uint256 _dstPoolId) = pools[0]
                .callSendCredit();
            assertEq(_dstChainId, chainId);
            assertEq(_dstPoolId, 1);
        }

        // pool.updateCredit check
        {
            (
                uint256 _srcChainId,
                uint256 _srcPoolId,
                IPool.CreditInfo memory creditInfo
            ) = pools[1].callUpdateCredit();
            assertEq(_srcChainId, chainId);
            assertEq(_srcPoolId, 0);
            assertEq(0, creditInfo.credits);
            assertEq(0, creditInfo.targetBalance);
        }
    }

    function testWithdrawInstant() public {
        vm.chainId(SRC_CHAIN_ID);
        uint256 ret = bridge.withdrawInstant(0, 500, alice);
        assertEq(ret, 500);

        // pool.withdrawInstant check
        {
            (address _from, uint256 _amountLP, address _to) = pools[0]
                .callWithdrawInstant();
            assertEq(_from, address(this));
            assertEq(_amountLP, 500);
            assertEq(_to, alice);
        }
    }

    function testWithdrawInstantFailWithZeroAmountLPBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAmount.selector,
                "amountLP"
            )
        );

        vm.chainId(SRC_CHAIN_ID);
        bridge.withdrawInstant(0, 0, alice);
    }

    function testCallDelta() public {
        vm.chainId(SRC_CHAIN_ID);
        bridge.callDelta(0, true);
        // pool.callDelta check
        {
            bool _isAdd = pools[0].callCallDelta();
            assertEq(_isAdd, true);
        }
    }

    function testCallDeltaNotFullModeByNormalUser() public {
        vm.chainId(SRC_CHAIN_ID);
        vm.startPrank(alice);
        bridge.callDelta(0, false);
        // pool.callDelta check
        {
            bool _isAdd = pools[0].callCallDelta();
            assertEq(_isAdd, false);
        }
    }

    function testCallDeltaFullModeByNormalUser() public {
        vm.chainId(SRC_CHAIN_ID);
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                bridgeDefaultAdminRole
            )
        );
        bridge.callDelta(0, true);
    }

    function testCalcSrcNativeAmount() public {
        vm.chainId(SRC_CHAIN_ID);

        // clarify setup parameters
        assertEq(100_000, tokenPriceOracle.getLatestPrice(SRC_CHAIN_ID));
        assertEq(200_000, tokenPriceOracle.getLatestPrice(DST_CHAIN_ID));
        assertEq(100, gasPriceOracle.getPrice(SRC_CHAIN_ID));
        assertEq(111, gasPriceOracle.getPrice(DST_CHAIN_ID));
        assertEq(0, bridge.premiumBPS(DST_CHAIN_ID));

        // (100 * 111 + 20000) * 200_000 / 100_000 = 31100 * 2 = 62200
        uint256 ret = bridge.calcSrcNativeAmount(DST_CHAIN_ID, 100, 20000);
        assertEq(ret, 62200);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiZeroAddress.selector,
                "priceFeedAddress"
            )
        );
        bridge.calcSrcNativeAmount(INVALID_CHAIN_ID, 100, 0);
    }

    function testGetPool() public {
        for (uint8 i = 0; i < 3; i++) {
            IPool pool = bridge.getPool(i);
            assertEq(address(pool), address(pools[i]));
        }
    }

    // TransferPool
    function testOnRecvPacketTransferPool() public {
        vm.chainId(DST_CHAIN_ID);
        // make transfer pool payload
        bytes memory payload = IBCUtils.encodeTransferPool(
            0,
            1,
            ITransferPoolFeeCalculator.FeeInfo(0, 0, 0, 0, 0, 0),
            IPool.CreditInfo(600, 60),
            bbob,
            500,
            IBCUtils.ExternalInfo("", 5_000)
        );
        // build packet data
        Packet memory packet = _buildPacketData(payload);

        // call onRecvPacket
        bytes memory acknowledge = bridge.onRecvPacket(packet, relayer);
        assertEq(acknowledge.length, 0);

        // pool.updateCredit check
        {
            (
                uint256 _chainId,
                uint256 _srcPoolId,
                IPool.CreditInfo memory _c
            ) = pools[1].callUpdateCredit();
            assertEq(_chainId, SRC_CHAIN_ID);
            assertEq(_srcPoolId, 0);
            assertEq(abi.encode(_c), abi.encode(IPool.CreditInfo(600, 60)));
        }

        // pool.recv check
        {
            (
                uint256 _srcChainId,
                uint256 _srcPoolId,
                address _to,
                ITransferPoolFeeCalculator.FeeInfo memory _fee
            ) = pools[1].callRecv();
            assertEq(_srcChainId, SRC_CHAIN_ID);
            assertEq(_srcPoolId, 0);
            assertEq(_to, bob, "bob");
            assertEq(
                abi.encode(_fee),
                abi.encode(ITransferPoolFeeCalculator.FeeInfo(0, 0, 0, 0, 0, 0))
            );
        }
    }

    // Credit
    function testOnRecvPacketCredit() public {
        vm.chainId(DST_CHAIN_ID);
        // make credit payload
        bytes memory payload = IBCUtils.encodeCredit(
            0,
            1,
            IPool.CreditInfo(900, 90)
        );
        // build packet data
        Packet memory packet = _buildPacketData(payload);

        // call onRecvPacket
        bytes memory acknowledge = bridge.onRecvPacket(packet, relayer);
        assertEq(acknowledge.length, 0);

        // pool.updateCredit check
        {
            (
                uint256 _chainId,
                uint256 _srcPoolId,
                IPool.CreditInfo memory _c
            ) = pools[1].callUpdateCredit();
            assertEq(_chainId, SRC_CHAIN_ID);
            assertEq(_srcPoolId, 0);
            assertEq(abi.encode(_c), abi.encode(IPool.CreditInfo(900, 90)));
        }
    }

    function testOnRecvPacketCreditFailWithInvalidAppVersion() public {
        /* upgrade bridge with new version */
        address newBridgeImpl = address(
            new MockUpgradeBridge(APP_VERSION + 1, PORT)
        );
        bytes memory initialData = abi.encodeCall(
            MockUpgradeBridge.upgrade,
            (
                address(new BridgeFallback(APP_VERSION + 1, PORT)),
                address(new BridgeChannelUpgradeFallback(APP_VERSION + 1, PORT))
            )
        );
        UUPSUpgradeable(address(bridge)).upgradeToAndCall(
            newBridgeImpl,
            initialData
        );

        vm.chainId(DST_CHAIN_ID);
        // make credit payload
        bytes memory payload = IBCUtils.encodeCredit(
            0,
            1,
            IPool.CreditInfo(900, 90)
        );
        // build packet data
        Packet memory packet = _buildPacketData(payload);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiInvalidAppVersion.selector,
                APP_VERSION,
                APP_VERSION + 1
            )
        );
        // call onRecvPacket
        // solhint-disable-next-line no-unused-vars
        bytes memory _acknowledge = bridge.onRecvPacket(packet, relayer);
    }

    // Withdraw
    function testOnRecvPacketWithdraw() public {
        vm.chainId(DST_CHAIN_ID);
        // make withdraw payload
        bytes memory payload = IBCUtils.encodeWithdraw(
            0,
            1,
            500,
            IPool.CreditInfo(200, 20),
            bbob
        );
        // build packet data
        Packet memory packet = _buildPacketData(payload);

        // ibcPacket.sendPacket check TYPE: WITHDRAW_CONFIRM
        {
            vm.expectEmit(address(ibcPacket));
            emit SendPacket(
                PORT,
                DST_CHANNEL,
                Height.Data(0, 0),
                bridgeTimeoutTimestamp,
                keccak256(
                    IBCUtils.encodeWithdrawCheck(
                        0,
                        1,
                        500,
                        500,
                        IPool.CreditInfo(0, 0),
                        bbob
                    )
                )
            );
        }

        // call onRecvPacket
        bytes memory acknowledge = bridge.onRecvPacket(packet, relayer);
        assertEq(acknowledge.length, 0);

        // pool.updateCredit check
        {
            (
                uint256 _chainId,
                uint256 _srcPoolId,
                IPool.CreditInfo memory _c
            ) = pools[1].callUpdateCredit();
            assertEq(_chainId, SRC_CHAIN_ID);
            assertEq(_srcPoolId, 0);
            assertEq(abi.encode(_c), abi.encode(IPool.CreditInfo(200, 20)));
        }

        // pool.withdrawCheck check
        {
            (
                uint256 _srcChainId,
                uint256 _srcPoolId,
                uint256 _amountGD
            ) = pools[1].callWithdrawCheck();
            assertEq(_srcChainId, SRC_CHAIN_ID);
            assertEq(_srcPoolId, 0);
            assertEq(_amountGD, 500);
        }

        //pool.sendCredit() check
        {
            (uint256 _dstChainId, uint256 _dstPoolId) = pools[1]
                .callSendCredit();
            assertEq(_dstChainId, SRC_CHAIN_ID);
            assertEq(_dstPoolId, 0);
        }
    }

    // WithdrawCheck
    function testOnRecvPacketWithdrawCheck() public {
        vm.chainId(SRC_CHAIN_ID);
        // make withdraw check payload
        bytes memory payload = IBCUtils.encodeWithdrawCheck(
            0,
            1,
            900,
            800,
            IPool.CreditInfo(300, 30),
            bbob
        );
        // build packet data
        Packet memory packet = _buildPacketData(payload);

        // call onRecvPacket
        bytes memory acknowledge = bridge.onRecvPacket(packet, relayer);
        assertEq(acknowledge.length, 0);

        // pool.updateCredit check
        {
            (
                uint256 _peerChainId,
                uint256 _peerPoolId,
                IPool.CreditInfo memory _c
            ) = pools[0].callUpdateCredit();
            assertEq(_peerChainId, SRC_CHAIN_ID);
            assertEq(_peerPoolId, 1);
            assertEq(abi.encode(_c), abi.encode(IPool.CreditInfo(300, 30)));
        }

        // pool.withdrawConfirm check
        {
            (
                uint256 _peerChainId,
                uint256 _peerPoolId,
                address _to,
                uint256 _amountGD,
                uint256 _amountToMintGD
            ) = pools[0].callWithdrawConfirm();
            assertEq(_peerChainId, SRC_CHAIN_ID);
            assertEq(_peerPoolId, 1);
            assertEq(_to, bob);
            assertEq(_amountGD, 900);
            assertEq(_amountToMintGD, 800);
        }
    }

    // ====================== success test case(retry) =============================
    function testRetryOnReceiveReceivePool() public {
        vm.chainId(DST_CHAIN_ID);
        // make transfer pool payload
        bytes memory payload = IBCUtils.encodeTransferPool(
            0,
            1,
            ITransferPoolFeeCalculator.FeeInfo(0, 0, 0, 0, 0, 0),
            IPool.CreditInfo(600, 60),
            bbob,
            0,
            IBCUtils.ExternalInfo("", 0)
        );
        // build packet data
        Packet memory packet = _buildPacketData(payload);

        // set force fail: transferPool
        pools[1].setForceFail(true);

        vm.expectEmit(address(bridge));
        emit IReceiveRetryable.RevertReceive(
            IBCUtils._TYPE_RETRY_RECEIVE_POOL,
            SRC_CHAIN_ID,
            1,
            10001
        );
        // call onRecvPacket
        bridge.onRecvPacket(packet, relayer);
        {
            // revert receive check
            bytes memory ret = bridge.revertReceive(SRC_CHAIN_ID, 1);
            assertEq(
                ret,
                IBCUtils.encodeRetryReceivePool(
                    APP_VERSION,
                    10001,
                    0,
                    1,
                    bob,
                    ITransferPoolFeeCalculator.FeeInfo(0, 0, 0, 0, 0, 0),
                    0,
                    IBCUtils.ExternalInfo("", 0)
                ),
                "revertReceive"
            );
        }

        // set force fail false: transferPool
        pools[1].setForceFail(false);

        // retry on receive
        bridge.retryOnReceive(DST_CHANNEL, 1);
        // pool.recv check
        {
            (
                uint256 _srcChainId,
                uint256 _srcPoolId,
                address _to,
                ITransferPoolFeeCalculator.FeeInfo memory _fee
            ) = pools[1].callRecv();
            assertEq(_srcChainId, SRC_CHAIN_ID, "srcChainId");
            assertEq(_srcPoolId, 0, "srcPoolId");
            assertEq(_to, bob, "to");
            assertEq(
                abi.encode(_fee),
                abi.encode(
                    ITransferPoolFeeCalculator.FeeInfo(0, 0, 0, 0, 0, 0)
                ),
                "fee"
            );
        }
    }

    function testRetryOnReceiveWithdrawConfirm() public {
        vm.chainId(SRC_CHAIN_ID);
        // make transfer pool payload
        bytes memory payload = IBCUtils.encodeWithdrawCheck(
            0,
            1,
            1000,
            500,
            IPool.CreditInfo(600, 60),
            bbob
        );
        // build packet data
        Packet memory packet = _buildPacketData(payload);

        // set force fail: WithdrawConfirm
        pools[0].setForceFail(true);

        vm.expectEmit(address(bridge));
        emit IReceiveRetryable.RevertReceive(
            IBCUtils._TYPE_RETRY_WITHDRAW_CONFIRM,
            SRC_CHAIN_ID,
            1,
            5001
        );
        // call onRecvPacket
        bridge.onRecvPacket(packet, relayer);
        {
            // revert receive check
            bytes memory ret = bridge.revertReceive(SRC_CHAIN_ID, 1);
            assertEq(
                ret,
                IBCUtils.encodeRetryWithdrawConfirm(
                    APP_VERSION,
                    5001,
                    0,
                    1,
                    bob,
                    1000,
                    500
                )
            );
        }

        // set force fail false: transferPool
        pools[0].setForceFail(false);

        // retry on receive
        bridge.retryOnReceive(DST_CHANNEL, 1);
        // pool.withdrawConfirm check
        {
            (
                uint256 _srcChainId,
                uint256 _srcPoolId,
                address _to,
                uint256 _amountGD,
                uint256 _amountToMintGD
            ) = pools[0].callWithdrawConfirm();
            assertEq(_srcChainId, SRC_CHAIN_ID);
            assertEq(_srcPoolId, 1);
            assertEq(_to, bob);
            assertEq(_amountGD, 1000);
            assertEq(_amountToMintGD, 500);
        }
    }

    function testRetryOnReceivePost() public {
        vm.chainId(DST_CHAIN_ID);
        // set force fail out service
        outerService.setForceFail(true);

        // make transfer pool payload
        bytes memory payload = IBCUtils.encodeTransferPool(
            0,
            1,
            ITransferPoolFeeCalculator.FeeInfo(900, 0, 0, 0, 0, 0), // 1st arg: f.amount
            IPool.CreditInfo(600, 60),
            bouter,
            500,
            IBCUtils.ExternalInfo("payload", 1_000 * DENOMI)
        );
        // build packet data
        Packet memory packet = _buildPacketData(payload);

        vm.expectEmit(address(bridge));
        emit IReceiveRetryable.RevertReceive(
            IBCUtils._TYPE_RETRY_REFUEL_AND_EXTERNAL_CALL,
            SRC_CHAIN_ID,
            1,
            2501
        );
        // call onRecvPacket
        bridge.onRecvPacket(packet, relayer);

        {
            // revert receive check
            bytes memory ret = bridge.revertReceive(SRC_CHAIN_ID, 1);
            assertEq(
                ret,
                IBCUtils.encodeRetryRefuelAndExternalCall(
                    APP_VERSION,
                    2501,
                    address(erc20),
                    900,
                    address(outerService),
                    500,
                    IBCUtils.ExternalInfo("payload", 1_000 * DENOMI)
                )
            );
        }

        // set force fail false out service & set bridge balance 2000
        outerService.setForceFail(false);
        payable(address(bridge)).call{value: 2_000}("");

        // retry on post
        bridge.retryOnReceive(DST_CHANNEL, 1);
        // outerService.call check
        {
            (
                string memory _port,
                string memory _channel,
                address _token,
                uint256 _amount,
                bytes memory _payload
            ) = outerService.receivedMsgs(0);
            assertEq(_port, PORT);
            assertEq(_channel, DST_CHANNEL);
            assertEq(_token, address(erc20));
            assertEq(_amount, 900);
            assertEq(_payload, "payload");
        }
        // bridge & outer balance
        {
            assertEq(address(bridge).balance, 1_500);
            assertEq(address(outerService).balance, 500);
        }
    }

    function testRetryOnReceiveExternalCall() public {
        vm.chainId(DST_CHAIN_ID);
        // set force fail out service but set bridge balance 2000(for send)
        outerService.setForceFail(true);
        payable(address(bridge)).call{value: 2_000}("");

        // make transfer pool payload
        bytes memory payload = IBCUtils.encodeTransferPool(
            0,
            1,
            ITransferPoolFeeCalculator.FeeInfo(900, 0, 0, 0, 0, 0), // 1st arg: f.amount
            IPool.CreditInfo(600, 60),
            bouter,
            500,
            IBCUtils.ExternalInfo("payload", 1_000 * DENOMI)
        );
        // build packet data
        Packet memory packet = _buildPacketData(payload);

        vm.expectEmit(address(bridge));
        emit IReceiveRetryable.RevertReceive(
            IBCUtils._TYPE_RETRY_EXTERNAL_CALL,
            SRC_CHAIN_ID,
            1,
            2501
        );
        // call onRecvPacket
        bridge.onRecvPacket(packet, relayer);

        {
            // revert receive check
            bytes memory ret = bridge.revertReceive(SRC_CHAIN_ID, 1);
            assertEq(
                ret,
                IBCUtils.encodeRetryExternalCall(
                    APP_VERSION,
                    2501,
                    address(erc20),
                    900,
                    address(outerService),
                    IBCUtils.ExternalInfo("payload", 1_000 * DENOMI)
                )
            );
        }
        // bridge & outer balance
        {
            assertEq(address(bridge).balance, 1_500);
            assertEq(address(outerService).balance, 500);
        }

        // set force fail false out service & set bridge balance 2000
        outerService.setForceFail(false);

        // retry on post
        bridge.retryOnReceive(DST_CHANNEL, 1);
        // outerService.call check
        {
            (
                string memory _port,
                string memory _channel,
                address _token,
                uint256 _amount,
                bytes memory _payload
            ) = outerService.receivedMsgs(0);
            assertEq(_port, PORT);
            assertEq(_channel, DST_CHANNEL);
            assertEq(_token, address(erc20));
            assertEq(_amount, 900);
            assertEq(_payload, "payload");
        }

        // bridge & outer balance
        {
            assertEq(address(bridge).balance, 1_500);
            assertEq(address(outerService).balance, 500);
        }
    }

    function testRetryOnReceiveReceivePoolDstGasCall() public {
        vm.chainId(DST_CHAIN_ID);
        // make transfer pool payload
        bytes memory payload = IBCUtils.encodeTransferPool(
            0,
            1,
            ITransferPoolFeeCalculator.FeeInfo(900, 0, 0, 0, 0, 0), // 1st arg: f.amount
            IPool.CreditInfo(600, 60),
            bouter,
            500,
            IBCUtils.ExternalInfo("payload", 1_000 * DENOMI)
        );
        // build packet data
        Packet memory packet = _buildPacketData(payload);

        vm.expectEmit(address(bridge));
        emit IReceiveRetryable.RevertReceive(
            IBCUtils._TYPE_RETRY_REFUEL_CALL,
            SRC_CHAIN_ID,
            1,
            2501
        );
        // call onRecvPacket
        bridge.onRecvPacket(packet, relayer);

        {
            // revert receive check
            bytes memory ret = bridge.revertReceive(SRC_CHAIN_ID, 1);
            assertEq(
                ret,
                IBCUtils.encodeRetryRefuelCall(
                    APP_VERSION,
                    2501,
                    address(outerService),
                    500
                )
            );
        }
        // outerService.call check
        {
            (
                string memory _port,
                string memory _channel,
                address _token,
                uint256 _amount,
                bytes memory _payload
            ) = outerService.receivedMsgs(0);
            assertEq(_port, PORT);
            assertEq(_channel, DST_CHANNEL);
            assertEq(_token, address(erc20));
            assertEq(_amount, 900);
            assertEq(_payload, "payload");
        }
        // bridge & outer balance
        {
            assertEq(address(outerService).balance, 0);
        }

        // retry on post (fail)
        bridge.retryOnReceive(DST_CHANNEL, 1);
        // bridge & outer balance
        {
            assertEq(address(bridge).balance, 0);
            assertEq(address(outerService).balance, 0);
        }

        // set bridge balance 2000
        payable(address(bridge)).call{value: 2_000}("");

        // retry on post
        bridge.retryOnReceive(DST_CHANNEL, 1);
        // bridge & outer balance
        {
            assertEq(address(bridge).balance, 1_500);
            assertEq(address(outerService).balance, 500);
        }
    }

    function testRetryOnReceiveReceivePoolRefuelDstCap() public {
        vm.chainId(DST_CHAIN_ID);
        // make transfer pool payload
        bytes memory payload = IBCUtils.encodeTransferPool(
            0,
            1,
            ITransferPoolFeeCalculator.FeeInfo(900, 0, 0, 0, 0, 0), // 1st arg: f.amount
            IPool.CreditInfo(600, 60),
            bouter,
            500,
            IBCUtils.ExternalInfo("payload", 1_000 * DENOMI)
        );
        // build packet data
        Packet memory packet = _buildPacketData(payload);

        // set bridge balance 2000
        payable(address(bridge)).call{value: 2_000}("");

        vm.expectEmit(true, false, false, true);
        emit IBridgeManager.SetRefuelDstCap(39);
        bridge.setRefuelDstCap(39);
        vm.expectEmit(address(bridge));
        emit BridgeBase.RefuelDstCapped(
            SRC_CHAIN_ID,
            1,
            address(outerService),
            500,
            39
        );
        // call onRecvPacket
        bridge.onRecvPacket(packet, relayer);
        {
            assertEq(address(bridge).balance, 2_000 - 39);
            assertEq(address(outerService).balance, 39);
        }
    }

    // User may encounter abnormal situations multiple times, as follows:
    // 1. onRecvPacket: Fail with TYPE_RETRY_RECEIVE_POOL.
    // 2. retryOnReceive: Pass TYPE_RETRY_RECEIVE_POOL but fail with _TYPE_RETRY_EXTERNAL_CALL.
    // 3. retryOnReceive: Pass _TYPE_RETRY_EXTERNAL_CALL.
    //
    // The important point is that lastValidHeight must not updated, and the initial value is applied continuously.
    function testRetryOnReceiveMultipleRetries() public {
        vm.chainId(DST_CHAIN_ID);
        bytes memory payload = IBCUtils.encodeTransferPool(
            0,
            1,
            ITransferPoolFeeCalculator.FeeInfo(900, 0, 0, 0, 0, 0),
            IPool.CreditInfo(600, 60),
            bouter,
            0,
            IBCUtils.ExternalInfo("payload", 1_000 * DENOMI)
        );
        Packet memory packet = _buildPacketData(payload);

        pools[1].setForceFail(true);
        outerService.setForceFail(true);

        vm.expectEmit(address(bridge));
        emit IReceiveRetryable.RevertReceive(
            IBCUtils._TYPE_RETRY_RECEIVE_POOL,
            SRC_CHAIN_ID,
            1,
            10001
        );
        bridge.onRecvPacket(packet, relayer);
        {
            bytes memory ret = bridge.revertReceive(SRC_CHAIN_ID, 1);
            assertEq(
                ret,
                IBCUtils.encodeRetryReceivePool(
                    APP_VERSION,
                    10001,
                    0,
                    1,
                    address(outerService),
                    ITransferPoolFeeCalculator.FeeInfo(900, 0, 0, 0, 0, 0),
                    0,
                    IBCUtils.ExternalInfo("payload", 1_000 * DENOMI)
                )
            );
        }

        pools[1].setForceFail(false);

        vm.expectEmit(address(bridge));
        emit IReceiveRetryable.RevertReceive(
            IBCUtils._TYPE_RETRY_EXTERNAL_CALL,
            SRC_CHAIN_ID,
            1,
            10001
        );
        bridge.retryOnReceive(DST_CHANNEL, 1);
        {
            bytes memory ret = bridge.revertReceive(SRC_CHAIN_ID, 1);
            assertEq(
                ret,
                IBCUtils.encodeRetryExternalCall(
                    APP_VERSION,
                    10001,
                    address(erc20),
                    900,
                    address(outerService),
                    IBCUtils.ExternalInfo("payload", 1_000 * DENOMI)
                )
            );
        }

        outerService.setForceFail(false);

        bridge.retryOnReceive(DST_CHANNEL, 1);
        {
            (
                string memory _port,
                string memory _channel,
                address _token,
                uint256 _amount,
                bytes memory _payload
            ) = outerService.receivedMsgs(0);
            assertEq(_port, PORT);
            assertEq(_channel, DST_CHANNEL);
            assertEq(_token, address(erc20));
            assertEq(_amount, 900);
            assertEq(_payload, "payload");
        }
        //        {
        //            assertEq(address(bridge).balance, 1_500);
        //            assertEq(address(outerService).balance, 500);
        //        }
    }

    function testOnRecvFailWithInvalidMessageType() public {
        vm.chainId(DST_CHAIN_ID);
        bytes memory payload = abi.encode(uint8(255));
        Packet memory packet = _buildPacketData(payload);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiInvalidPacketType.selector,
                uint8(255)
            )
        );

        bridge.onRecvPacket(packet, relayer);
    }

    function testRetryOnReceiveFailWithoutValidPayload() public {
        vm.chainId(DST_CHAIN_ID);

        vm.expectRevert(
            abi.encodeWithSelector(ITokiErrors.TokiNoRevertReceive.selector)
        );

        bridge.retryOnReceive(DST_CHANNEL, 666);
    }

    function testRetryOnReceiveRevertsWhenPacketHasExpired() public {
        vm.chainId(DST_CHAIN_ID);
        bytes memory payload = IBCUtils.encodeTransferPool(
            0,
            1,
            ITransferPoolFeeCalculator.FeeInfo(0, 0, 0, 0, 0, 0),
            IPool.CreditInfo(600, 60),
            bbob,
            0,
            IBCUtils.ExternalInfo("", 0)
        );
        Packet memory packet = _buildPacketData(payload);

        pools[1].setForceFail(true);

        vm.expectEmit(address(bridge));
        emit IReceiveRetryable.RevertReceive(
            IBCUtils._TYPE_RETRY_RECEIVE_POOL,
            SRC_CHAIN_ID,
            1,
            10001
        );
        bridge.onRecvPacket(packet, relayer);
        {
            bytes memory ret = bridge.revertReceive(SRC_CHAIN_ID, 1);
            assertEq(
                ret,
                IBCUtils.encodeRetryReceivePool(
                    APP_VERSION,
                    10001,
                    0,
                    1,
                    bob,
                    ITransferPoolFeeCalculator.FeeInfo(0, 0, 0, 0, 0, 0),
                    0,
                    IBCUtils.ExternalInfo("", 0)
                )
            );
        }

        // Advance blocks beyond lastValidHeight, and then the packet expires.
        vm.roll(10002);
        vm.expectRevert(
            abi.encodeWithSelector(ITokiErrors.TokiRetryExpired.selector, 10001)
        );
        bridge.retryOnReceive(DST_CHANNEL, 1);
    }

    function testRetryOnReceiveRevertsWhenAppVersionHasBecomeOutdated() public {
        vm.chainId(DST_CHAIN_ID);
        bytes memory payload = IBCUtils.encodeTransferPool(
            0,
            1,
            ITransferPoolFeeCalculator.FeeInfo(0, 0, 0, 0, 0, 0),
            IPool.CreditInfo(600, 60),
            bbob,
            0,
            IBCUtils.ExternalInfo("", 0)
        );
        Packet memory packet = _buildPacketData(payload);

        pools[1].setForceFail(true);

        vm.expectEmit(address(bridge));
        emit IReceiveRetryable.RevertReceive(
            IBCUtils._TYPE_RETRY_RECEIVE_POOL,
            SRC_CHAIN_ID,
            1,
            10001
        );
        bridge.onRecvPacket(packet, relayer);
        {
            bytes memory ret = bridge.revertReceive(SRC_CHAIN_ID, 1);
            assertEq(
                ret,
                IBCUtils.encodeRetryReceivePool(
                    APP_VERSION,
                    10001,
                    0,
                    1,
                    bob,
                    ITransferPoolFeeCalculator.FeeInfo(0, 0, 0, 0, 0, 0),
                    0,
                    IBCUtils.ExternalInfo("", 0)
                )
            );
        }

        // Update the appVersion, and then the packet loses compatibility.
        Bridge b = Bridge(payable(address(bridge)));
        uint256 nextAppVersion = b.appVersion() + 1;
        Bridge nb = new MockUpgradeBridge(nextAppVersion, PORT);
        BridgeFallback nbf = new BridgeFallback(nextAppVersion, PORT);
        BridgeChannelUpgradeFallback cuf = new BridgeChannelUpgradeFallback(
            nextAppVersion,
            PORT
        );
        bytes memory initializeData = abi.encodeCall(
            MockUpgradeBridge.upgrade,
            (address(nbf), address(cuf))
        );
        b.upgradeToAndCall(address(nb), initializeData);
        assertEq(b.appVersion(), nextAppVersion);
        assertEq(nbf.appVersion(), nextAppVersion);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiInvalidAppVersion.selector,
                APP_VERSION,
                nextAppVersion
            )
        );
        bridge.retryOnReceive(DST_CHANNEL, 1);
    }

    // ====================== success test case(unrecoverable) =============================
    function testOnRecvPacketForTransferPoolWithUnrecoverable() public {
        vm.chainId(DST_CHAIN_ID);
        bytes[] memory invalidAddresses = new bytes[](2);
        // an invalid address format.
        invalidAddresses[0] = hex"00";
        // abi encoded as 32 bytes
        invalidAddresses[
            1
        ] = hex"0000000000000000000000000000000000000000000000000000000000000001";

        for (uint256 i = 0; i < invalidAddresses.length; i++) {
            // make transfer pool payload
            bytes memory payload = IBCUtils.encodeTransferPool(
                0,
                1,
                ITransferPoolFeeCalculator.FeeInfo(0, 0, 0, 0, 0, 0),
                IPool.CreditInfo(600, 60),
                invalidAddresses[i],
                0,
                IBCUtils.ExternalInfo("", 0)
            );
            // build packet data
            Packet memory packet = _buildPacketData(payload);

            // call onRecvPacket with Unrecoverable
            vm.expectEmit(address(bridge));
            emit Bridge.Unrecoverable(SRC_CHAIN_ID, 1);
            bytes memory acknowledge = bridge.onRecvPacket(packet, relayer);

            assertEq(acknowledge.length, 0);

            // Even if the recipient address is invalid, updateCredit will execute.
            {
                (
                    uint256 _chainId,
                    uint256 _srcPoolId,
                    IPool.CreditInfo memory _c
                ) = pools[1].callUpdateCredit();
                assertEq(_chainId, SRC_CHAIN_ID);
                assertEq(_srcPoolId, 0);
                assertEq(abi.encode(_c), abi.encode(IPool.CreditInfo(600, 60)));
            }

            // If the recipient address is invalid, a pool.recv will also fail.
            {
                (
                    uint256 _srcChainId /* uint256 _srcPoolId */ /* address _to */ /* ITransferPoolFeeCalculator.FeeInfo memory _fee */,
                    ,
                    ,

                ) = pools[1].callRecv();
                assertNotEq(_srcChainId, SRC_CHAIN_ID);
            }
        }
    }

    function testOnRecvPacketForWithdrawCheckWithUnrecoverable() public {
        vm.chainId(SRC_CHAIN_ID);
        bytes[] memory invalidAddresses = new bytes[](2);

        // an invalid address format.
        invalidAddresses[0] = hex"00";
        // abi encoded as 32 bytes
        invalidAddresses[
            1
        ] = hex"0000000000000000000000000000000000000000000000000000000000000001";

        for (uint256 i = 0; i < invalidAddresses.length; i++) {
            // make withdraw check payload
            bytes memory payload = IBCUtils.encodeWithdrawCheck(
                0,
                1,
                900,
                800,
                IPool.CreditInfo(300, 30),
                invalidAddresses[i]
            );
            // build packet data
            Packet memory packet = _buildPacketData(payload);

            // call onRecvPacket with Unrecoverable
            vm.expectEmit(address(bridge));
            emit Bridge.Unrecoverable(SRC_CHAIN_ID, 1);
            bytes memory acknowledge = bridge.onRecvPacket(packet, relayer);

            assertEq(acknowledge.length, 0);

            // Even if the recipient address is invalid, updateCredit will execute.
            {
                (
                    uint256 _peerChainId,
                    uint256 _peerPoolId,
                    IPool.CreditInfo memory _c
                ) = pools[0].callUpdateCredit();
                assertEq(_peerChainId, SRC_CHAIN_ID);
                assertEq(_peerPoolId, 1);
                assertEq(abi.encode(_c), abi.encode(IPool.CreditInfo(300, 30)));
            }

            // If the recipient address is invalid, a pool.withdrawConfirm will also fail.
            {
                (
                    uint256 _peerChainId /* uint256 _peerPoolId */ /* address _to */ /* uint256 _amountGD */ /* uint256 _amountToMintGD */,
                    ,
                    ,
                    ,

                ) = pools[0].callWithdrawConfirm();
                assertNotEq(_peerChainId, SRC_CHAIN_ID);
            }
        }
    }

    // ====================== helper functions =============================
    function testOnChanCloseInit() public {
        IIBCModule.MsgOnChanCloseInit memory m = IIBCModule.MsgOnChanCloseInit({
            portId: PORT,
            channelId: SRC_CHANNEL
        });
        vm.expectRevert(
            abi.encodeWithSelector(ITokiErrors.TokiCannotCloseChannel.selector)
        );
        bridge.onChanCloseInit(m);
    }

    function testOnChanOpenInitFailWithoutOrder() public {
        ChannelCounterparty.Data memory counterparty = ChannelCounterparty
            .Data({port_id: PORT, channel_id: SRC_CHANNEL});

        IIBCModuleInitializer.MsgOnChanOpenInit memory m = IIBCModuleInitializer
            .MsgOnChanOpenInit({
                order: Channel.Order.ORDER_UNORDERED,
                connectionHops: new string[](0),
                portId: PORT,
                channelId: SRC_CHANNEL,
                counterparty: counterparty,
                version: ""
            });

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiRequireOrderedChannel.selector
            )
        );

        bridge.onChanOpenInit(m);
    }

    function testOnChanOpenTryFailWithoutOrder() public {
        ChannelCounterparty.Data memory counterparty = ChannelCounterparty
            .Data({port_id: PORT, channel_id: SRC_CHANNEL});

        IIBCModuleInitializer.MsgOnChanOpenTry memory m = IIBCModuleInitializer
            .MsgOnChanOpenTry({
                order: Channel.Order.ORDER_UNORDERED,
                connectionHops: new string[](0),
                portId: PORT,
                channelId: SRC_CHANNEL,
                counterparty: counterparty,
                counterpartyVersion: ""
            });

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiRequireOrderedChannel.selector
            )
        );

        bridge.onChanOpenTry(m);
    }

    function testOnTimeoutPacketFail() public {
        bytes memory payload = IBCUtils.encodeTransferToken(
            "tokiToken",
            100,
            bouter,
            5_000,
            IBCUtils.ExternalInfo("call", 1_000 * DENOMI)
        );

        // build packet data
        Packet memory packet = _buildPacketData(payload);
        vm.expectRevert(
            abi.encodeWithSelector(ITokiErrors.TokiCannotTimeoutPacket.selector)
        );

        bridge.onTimeoutPacket(packet, alice);
    }

    function pr() public view returns (PoolRepository) {
        return PoolRepository(address(prProxy));
    }

    function toBytes32(
        string memory source
    ) public pure returns (bytes32 result) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            result := mload(add(source, 32))
        }
    }

    function _buildPacketData(
        bytes memory data
    ) internal pure returns (Packet memory) {
        return
            Packet({
                sequence: 1,
                sourcePort: PORT,
                sourceChannel: SRC_CHANNEL,
                destinationPort: PORT,
                destinationChannel: DST_CHANNEL,
                data: data,
                timeoutHeight: Height.Data({
                    revision_number: 0,
                    revision_height: 0
                }),
                timeoutTimestamp: 2 ** 64 - 1
            });
    }
}
