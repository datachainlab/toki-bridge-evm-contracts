// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {LocalhostHelper2, LocalhostTest} from "./LocalhostHelper2.sol";
import "../src/mocks/MockToken.sol";
import "../src/mocks/MockOuterService.sol";
import "../src/interfaces/IBridge.sol";
import "../src/interfaces/IPool.sol";
import "../src/interfaces/IPoolRepository.sol";
import "../src/interfaces/ITransferPoolFeeCalculator.sol";
import "../src/interfaces/IRelayerFeeCalculator.sol";
import "../src/library/MessageType.sol";
import "../src/library/IBCUtils.sol";
import "../src/PoolRepository.sol";
import "../src/Bridge.sol";
import "../src/BridgeChannelUpgradeFallback.sol";
import "../src/Pool.sol";
import "../src/future/TokiToken.sol";
import "../src/future/TokiEscrow.sol";
import "../src/TokenPriceOracle.sol";
import "../src/GasPriceOracle.sol";
import "../src/StableTokenPriceOracle.sol";
import "../src/StaticFlowRateLimiter.sol";
import "../src/replaceable/RelayerFeeCalculator.sol";
import "../src/replaceable/TransferPoolFeeCalculator.sol";
import "../src/mocks/MockPriceFeed.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IIBCChannel.sol";
import "@hyperledger-labs/yui-ibc-solidity/contracts/core/25-handler/OwnableIBCHandler.sol";
import "@hyperledger-labs/yui-ibc-solidity/contracts/proto/Channel.sol";

contract LocalhostTestSetup is LocalhostTest {
    struct ChainDef {
        uint256 chainId;
        string port;
    }
    struct PoolDef {
        uint256 poolId;
        string name;
        string symbol;
    }

    struct LocalhostChainPrice {
        TokenPriceOracle tokenPriceOracle;
        GasPriceOracle gasPriceOracle;
        MockPriceFeed srcPriceFeed;
        MockPriceFeed dstPriceFeed;
        address protocolFeeOwner;
        StableTokenPriceOracle stableTokenPriceOracle;
        RelayerFeeCalculator relayerFeeCalculator;
    }
    struct LocalhostChainPoolRepository {
        PoolRepository poolRepository;
        ERC1967Proxy poolRepositoryProxy;
        PoolRepository poolRepositoryResolve;
    }
    struct LocalhostChainPool {
        uint256 chainIndex;
        uint256 chainId;
        uint256 poolId;
        MockToken erc20;
        TransferPoolFeeCalculator feeCalculator;
        MockPriceFeed priceFeed;
        Pool pool;
    }
    struct LocalhostChainTokiToken {
        TokiToken token;
        TokiEscrow escrow;
    }
    struct LocalhostChain {
        uint256 chainId;
        ChannelInfo channelInfo; // channel on this chain, it connect to opposite chain
        IBridge bridge;
        LocalhostChainPrice price;
        LocalhostChainTokiToken token;
        LocalhostChainPoolRepository pr;
        mapping(uint256 => LocalhostChainPool) pools; // array in struct array is not available in solidity
        MockOuterService outerService;
        bytes outerServiceEncodeAddress;
    }
    mapping(uint256 => LocalhostChain) public _chains;

    uint256 public constant APP_VERSION = 1;
    string public constant VERSION = "toki-1";
    string public constant SRC_PORT = "toki";
    string public constant DST_PORT = "toki-dst";
    uint8 public constant POOL_GLOBAL_DECIMALS = 6;
    uint8 public constant POOL_LOCAL_DECIMALS = 6;
    uint256 public constant DEFAULT_CHAIN_ID = 999;

    // define as variable because constant of struct is not allowed
    /* solhint-disable var-name-mixedcase */
    ChainDef public SRC = ChainDef(111, SRC_PORT);
    ChainDef public DST = ChainDef(222, DST_PORT);
    PoolDef public POOL0 = PoolDef(0, "USD0", "USD0");
    PoolDef public POOL1 = PoolDef(1, "USD1", "USD1");
    /* solhint-enable var-name-mixedcase */

    // assign parameters
    address payable public _alice = payable(address(0x01));
    address payable public _bob = payable(address(0x02));
    address payable public _dead = payable(address(0xdead));

    function setUp() public virtual override {
        vm.chainId(DEFAULT_CHAIN_ID);
        super.setUp();

        vm.label(_alice, "Alice");
        vm.label(_bob, "Bob");

        ChainDef[2] memory chainDefs = [SRC, DST];
        PoolDef[2] memory poolDefs = [POOL0, POOL1];

        // create Bridge
        for (uint8 i = 0; i < 2; i++) {
            LocalhostChain storage t = _chains[i];
            t.chainId = chainDefs[i].chainId;
            vm.chainId(t.chainId);
            uint256 oppositeChainId = (i == 0)
                ? chainDefs[1].chainId
                : chainDefs[0].chainId;

            // serup mock outer service
            {
                t.outerService = new MockOuterService(chainDefs[i].port);
                t.outerServiceEncodeAddress = abi.encode(
                    address(t.outerService)
                );
            }

            // setup TokenPriceOracle
            {
                t.price.tokenPriceOracle = new TokenPriceOracle(10 * 1e14);
                t.price.srcPriceFeed = new MockPriceFeed(100_000, 8);
                t.price.dstPriceFeed = new MockPriceFeed(200_000, 8);
                t.price.tokenPriceOracle.setPriceFeedAddress(
                    chainDefs[0].chainId,
                    address(t.price.srcPriceFeed),
                    60 * 60 * 24
                );
                t.price.tokenPriceOracle.setPriceFeedAddress(
                    chainDefs[1].chainId,
                    address(t.price.dstPriceFeed),
                    60 * 60 * 24
                );
            }

            // setup StableTokenPriceOracle
            {
                t.price.stableTokenPriceOracle = new StableTokenPriceOracle();
            }

            // setup GasPriceOracle
            {
                t.price.gasPriceOracle = new GasPriceOracle();
                t.price.gasPriceOracle.updatePrice(chainDefs[0].chainId, 100);
                t.price.gasPriceOracle.updatePrice(chainDefs[1].chainId, 111);
            }

            // setup pool repository
            {
                t.pr.poolRepository = new PoolRepository();
                t.pr.poolRepositoryProxy = new ERC1967Proxy(
                    address(t.pr.poolRepository),
                    ""
                );
                t.pr.poolRepositoryResolve = PoolRepository(
                    address(t.pr.poolRepositoryProxy)
                );
                t.pr.poolRepositoryResolve.initialize();

                t.pr.poolRepositoryResolve.grantRole(
                    t.pr.poolRepositoryResolve.POOL_SETTER(),
                    address(this)
                );
            }

            // setup toki token
            {
                address tokiTokenImplementation = address(new TokiToken());
                t.token.token = TokiToken(
                    address(new ERC1967Proxy(tokiTokenImplementation, ""))
                );
                t.token.token.initialize(
                    10000 * (10 ** t.token.token.decimals()),
                    11000 * (10 ** t.token.token.decimals()),
                    11000 * (10 ** t.token.token.decimals()),
                    address(this)
                );
                t.token.token.grantRole(
                    t.token.token.MINTER_ROLE(),
                    address(this)
                );
                t.token.token.grantRole(
                    t.token.token.BURNER_ROLE(),
                    address(this)
                );

                address tokiEscrowImplementation = address(
                    new TokiEscrow(
                        1,
                        2,
                        5000 * (10 ** t.token.token.decimals()),
                        2
                    )
                );
                t.token.escrow = TokiEscrow(
                    address(new ERC1967Proxy(tokiEscrowImplementation, ""))
                );
                t.token.escrow.initialize(
                    t.token.token,
                    address(this),
                    address(this), //bridge role
                    t.token.token.decimals() - 3, // global decimals
                    t.token.token.decimals() // local decimals
                );

                t.token.token.grantRole(
                    t.token.token.MINTER_ROLE(),
                    address(t.token.escrow)
                );
                t.token.token.grantRole(
                    t.token.token.BURNER_ROLE(),
                    address(t.token.escrow)
                );

                t.token.escrow.setAcceptedDstChainId(oppositeChainId, true);
            }

            // setup protocolFeeOwner;
            {
                t.price.protocolFeeOwner = address(this);
                t.price.relayerFeeCalculator = new RelayerFeeCalculator(
                    address(t.price.tokenPriceOracle),
                    address(t.price.gasPriceOracle),
                    100_000, //gasUsed
                    12000 //premiumBPS
                );
            }

            // setup bridge contract
            string memory port = chainDefs[i].port;
            address bridgeAddress = address(new Bridge(APP_VERSION, port));
            bytes memory bridgeInitializeData = abi.encodeCall(
                Bridge.initialize,
                Bridge.InitializeParam(
                    address(_ibcHandler),
                    address(t.pr.poolRepositoryProxy),
                    address(t.token.escrow),
                    address(t.price.tokenPriceOracle),
                    t.price.protocolFeeOwner,
                    address(t.price.relayerFeeCalculator),
                    address(new BridgeFallback(APP_VERSION, port)),
                    address(
                        new BridgeChannelUpgradeFallback(APP_VERSION, port)
                    ),
                    10000,
                    5000,
                    2500
                )
            );
            t.bridge = IBridge(
                address(new ERC1967Proxy(bridgeAddress, bridgeInitializeData))
            );

            t.token.escrow.grantRole(
                t.token.escrow.BRIDGE_ROLE(),
                address(t.bridge)
            );
            t.token.token.approve(
                address(t.bridge),
                1 * (10 ** (t.token.token.decimals() + 10))
            );
        }

        // setup IBC
        vm.chainId(DEFAULT_CHAIN_ID);
        _ibcHandler.bindPort(SRC.port, _chains[0].bridge);
        _ibcHandler.bindPort(DST.port, _chains[1].bridge);
        (string memory channelId0, string memory channelId1) = LocalhostHelper2
            .createClientConnectionChannel(
                _ibcHandler,
                chainDefs[0].port,
                chainDefs[1].port,
                Channel.Order.ORDER_ORDERED,
                VERSION
            );
        _chains[0].channelInfo = ChannelInfo(SRC.port, channelId0);
        _chains[1].channelInfo = ChannelInfo(DST.port, channelId1);
        for (uint8 i = 0; i < 2; i++) {
            vm.chainId(_chains[i].chainId);
            IBridge _bridge = _chains[i].bridge;
            _bridge.setChainLookup(
                _chains[i].channelInfo.channel,
                _chains[i ^ 1].chainId
            );
            uint256 _chainId = _bridge.getChainId(
                _chains[i].channelInfo.channel,
                true
            );
            assertEq(_chainId, _chains[i ^ 1].chainId, "chain lookup");
            _bridge.setRefuelSrcCap(
                _chains[i].channelInfo.channel,
                1_000 * 1e18
            );
            _bridge.setRefuelDstCap(1_000 * 1e18);
        }

        // setup Pool
        for (uint8 i = 0; i < 2; i++) {
            vm.chainId(_chains[i].chainId);
            for (uint8 pi = 0; pi < 2; pi++) {
                LocalhostChainPool storage p = _chains[i].pools[pi];
                p.chainIndex = i;
                p.chainId = _chains[i].chainId;
                p.poolId = pi;

                p.erc20 = new MockToken(
                    poolDefs[pi].name,
                    poolDefs[pi].symbol,
                    13,
                    1_000_000_000_000 * 1e18
                );
                p.priceFeed = new MockPriceFeed(1_000_000, 8);
                _chains[i]
                    .price
                    .stableTokenPriceOracle
                    .setBasePriceAndFeedAddress(
                        pi,
                        1_000,
                        address(p.priceFeed),
                        60 * 60 * 24
                    );

                p.feeCalculator = new TransferPoolFeeCalculator(
                    _chains[i].price.stableTokenPriceOracle
                );

                address poolImplementation = address(
                    new Pool(100, 200, 1_000_000_000_000, 0)
                ); //_chains[i].chainId);
                p.pool = Pool(
                    address(new ERC1967Proxy(poolImplementation, ""))
                );
                uint256 _maxTotalDeposits = 200 * 1e18;
                p.pool.initialize(
                    Pool.InitializeParam(
                        poolDefs[pi].name,
                        poolDefs[pi].symbol,
                        pi, //poolId
                        address(p.erc20), //token
                        POOL_GLOBAL_DECIMALS, //gd
                        POOL_LOCAL_DECIMALS, //ld
                        address(p.feeCalculator), //feeCalculator
                        address(this), //admin
                        address(_chains[i].bridge), //router
                        _maxTotalDeposits
                    )
                );

                _chains[i].pr.poolRepositoryResolve.setPool(
                    pi,
                    address(p.pool)
                );

                p.pool.grantRole(p.pool.DEFAULT_ROUTER_ROLE(), address(this));
                p.pool.setDeltaParam(false, 10000, 10000, false, false);

                p.erc20.approve(
                    address(_chains[i].bridge),
                    1_000_000_000 * 1e18
                );
                for (uint8 peerIndex = 0; peerIndex < 2; peerIndex++) {
                    for (uint8 peerPoolId = 0; peerPoolId < 2; peerPoolId++) {
                        if (peerIndex != i || peerPoolId != pi) {
                            p.pool.registerPeerPool(
                                _chains[peerIndex].chainId,
                                peerPoolId,
                                100
                            );
                            p.pool.activatePeerPool(
                                _chains[peerIndex].chainId,
                                peerPoolId
                            );
                        }
                    }
                }
            }
        }
    }

    // helper functions to call api
    function calcTransferFee(
        uint256 srcChainIndex,
        uint256 srcPoolIndex,
        uint256 dstChainIndex,
        uint256 dstPoolIndex,
        address from,
        uint256 amountGD
    ) public view returns (ITransferPoolFeeCalculator.FeeInfo memory feeInfo) {
        LocalhostChainPool storage srcPool = _chains[srcChainIndex].pools[
            srcPoolIndex
        ];
        LocalhostChainPool storage dstPool = _chains[dstChainIndex].pools[
            dstPoolIndex
        ];
        feeInfo = srcPool.pool.calcFee(
            dstPool.chainId,
            dstPool.poolId,
            from,
            gdToLd(srcPool.pool, amountGD)
        );
    }

    function deposit(
        uint256 srcChainIndex,
        uint256 srcPoolIndex,
        uint256 dstChainIndex,
        uint256 dstPoolIndex,
        uint256 amount,
        address to
    ) internal {
        // note that caller ensure to call vm.recordLogs() before this function
        LocalhostChain storage src = _chains[srcChainIndex];
        LocalhostChainPool storage srcPool = src.pools[srcPoolIndex];
        LocalhostChain storage dst = _chains[dstChainIndex];
        LocalhostChainPool storage dstPool = src.pools[dstPoolIndex];

        vm.chainId(src.chainId);

        uint256 relayerFee = src
            .price
            .relayerFeeCalculator
            .calcFee(MessageType._TYPE_CREDIT, dst.chainId)
            .fee;

        srcPool.erc20.mint(_dead, amount);
        src.bridge.deposit(srcPool.poolId, amount, to);
        src.bridge.sendCredit{value: relayerFee}(
            src.channelInfo.channel,
            srcPool.poolId,
            dstPool.poolId,
            _dead
        );

        relay(MessageType._TYPE_CREDIT, src.channelInfo, dst.chainId);
    }

    function gdToLd(
        Pool pool,
        uint256 _amountGD
    ) internal view returns (uint256) {
        uint256 convertRate = pool.convertRate();
        return _amountGD * convertRate;
    }

    function ldToGd(
        Pool pool,
        uint256 _amountLD
    ) internal view returns (uint256) {
        uint256 convertRate = pool.convertRate();
        return _amountLD / convertRate;
    }

    function addressToBytes(address a) internal pure returns (bytes memory) {
        return abi.encodePacked(a);
    }
}
