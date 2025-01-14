// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../src/mocks/MockPriceFeed.sol";
import "../src/Pool.sol";
import "../src/replaceable/TransferPoolFeeCalculator.sol";
import "../src/interfaces/IPool.sol";
import "../src/interfaces/IPoolRepository.sol";
import "../src/interfaces/IStableTokenPriceOracle.sol";
import "../src/mocks/MockToken.sol";
import "../src/PoolRepository.sol";
import "../src/TokenPriceOracle.sol";
import "../src/StableTokenPriceOracle.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract PoolTestDecimals {
    uint8 public globalDecimals;
    uint8 public localDecimals;
    uint256 public globalDecimalsConvert;
    uint256 public localDecimalsConvert;
    uint256 public convertRate;

    function setUpDecimals(uint8 ld, uint8 gd) internal {
        localDecimals = ld;
        globalDecimals = gd;
        localDecimalsConvert = 10 ** uint256(ld);
        globalDecimalsConvert = 10 ** uint256(gd);
        convertRate = 10 ** (uint256(ld) - (uint256(gd)));
    }

    // solhint-disable-next-line func-name-mixedcase
    function LD(uint256 _amount) internal view returns (uint256) {
        return _amount * localDecimalsConvert;
    }

    // solhint-disable-next-line func-name-mixedcase
    function GD(uint256 _amount) internal view returns (uint256) {
        return _amount * globalDecimalsConvert;
    }

    // solhint-disable-next-line func-name-mixedcase
    function LDToGD(uint256 _amountLD) internal view returns (uint256) {
        return _amountLD / convertRate;
    }

    // solhint-disable-next-line func-name-mixedcase
    function GDToLD(uint256 _amountGD) internal view returns (uint256) {
        return _amountGD * convertRate;
    }
}

contract MockUSD is MockToken {
    constructor(
        uint8 decimals,
        uint256 initialSupply
    ) MockToken("MockToken", "MOCK", decimals, initialSupply) {}
}

contract PoolTest is PoolTestDecimals, Test {
    struct PeerPool {
        uint256 chainId; // dest chain id
        uint256 id; // dest pool id
        uint256 weight; // The weighting that our pool has for the other pool (delta algorithm)
        uint256 balance; // The amount of tokens in the target pool
        uint256 targetBalance; // The target amount of tokens in the target pool (use to calculate eq fee)
        uint256 lastKnownBalance; // The last known balance of the target pool
        uint256 credits; // Next time, the amount of tokens that can be sent to the target pool
        bool ready; // Is target pools ready?
    }

    // assign address
    address public empty = address(0x00);
    address public alice = address(0x01);
    address public bob = address(0x02);

    // for test contracts
    Pool[] public pools;
    ERC1967Proxy[] public erc1967Proxies;
    MockUSD[] public mockUSDs;
    PoolRepository public poolRepository;
    ERC1967Proxy public prProxy;

    TokenPriceOracle public tokenPriceOracle;
    MockPriceFeed public tokenPriceFeed;
    StableTokenPriceOracle public stableTokenPriceOracle;
    MockPriceFeed public stablePriceFeed;

    // for test parameters
    uint256[] public chainIds = [1, 2, 111];
    uint256[] public poolIds = [1, 1, 1];
    uint256 public constant DUMMY_TOKENID_OF_POOL = 39393939;
    address public admin;

    uint256 public constant DEFAULT_WEIGHT = 100;
    uint256 public defaultMintAmountLd;
    uint256 public defaultMintTokenAmount;
    uint256 public withdrawLocalMintAmountLd;

    function setUp() public {
        setUpDecimals(7, 5);
        defaultMintAmountLd = LD(1_000_000);
        defaultMintTokenAmount = GD(1_000_000_000);
        withdrawLocalMintAmountLd = LD(1_000);

        admin = address(0x201);

        // setup pool repository
        {
            poolRepository = new PoolRepository();
            prProxy = new ERC1967Proxy(address(poolRepository), "");
        }
        // set oracle address
        {
            tokenPriceFeed = new MockPriceFeed(10000, 8);
            tokenPriceOracle = new TokenPriceOracle(10 * 1e14);

            MockPriceFeed expensiveTokenPriceFeed = new MockPriceFeed(1e12, 8);
            tokenPriceOracle.setPriceFeedAddress(
                DUMMY_TOKENID_OF_POOL,
                address(expensiveTokenPriceFeed),
                60 * 60 * 24
            );
        }
        // set stable oracle address
        {
            stablePriceFeed = new MockPriceFeed(10000, 8);
            stableTokenPriceOracle = new StableTokenPriceOracle();
        }

        for (uint8 i = 0; i < poolIds.length; i++) {
            vm.chainId(chainIds[i]);
            pools.push(new Pool(100, 200, 100_000_000_000, 100_000_000));
            erc1967Proxies.push(new ERC1967Proxy(address(pools[i]), ""));

            // setup mock usd
            mockUSDs.push(new MockUSD(localDecimals, defaultMintTokenAmount));
            mockUSDs[i].mint(address(this), defaultMintTokenAmount);
            mockUSDs[i].approve(
                address(erc1967Proxies[i]),
                defaultMintTokenAmount
            );

            // update oracle prices
            tokenPriceOracle.setPriceFeedAddress(
                chainIds[i],
                address(tokenPriceFeed),
                60 * 60 * 24
            );
            stableTokenPriceOracle.setBasePriceAndFeedAddress(
                poolIds[i],
                10000,
                address(stablePriceFeed),
                60 * 60 * 24
            );

            tokenPriceOracle.updatePrice(chainIds[i], true);
            stableTokenPriceOracle.updateCurrentPrice(poolIds[i], true);

            // setup fee calculator
            TransferPoolFeeCalculator feeCalculator = new TransferPoolFeeCalculator(
                    stableTokenPriceOracle
                );
            // set high price rate for avoiding from minimum protocol fee
            feeCalculator.setTokenId(poolIds[i], DUMMY_TOKENID_OF_POOL);

            // mock max total deposits
            uint256 maxTotalDeposits = 200 * 1e18;

            // initiate pool
            proxy(i).initialize(
                Pool.InitializeParam(
                    "LP token",
                    "LP",
                    poolIds[i],
                    address(mockUSDs[i]),
                    globalDecimals,
                    localDecimals,
                    address(feeCalculator),
                    admin,
                    address(this), // actually router address, in other words `brdige`,
                    maxTotalDeposits
                )
            );

            assertEq(proxy(i).poolId(), poolIds[i]);
            assertEq(proxy(i).token(), address(mockUSDs[i]));
            assertEq(proxy(i).decimals(), globalDecimals);
            assertEq(proxy(i).globalDecimals(), globalDecimals);
            assertEq(proxy(i).localDecimals(), localDecimals);
            assertEq(
                proxy(i).convertRate(),
                10 ** (localDecimals - globalDecimals)
            );
            assertEq(proxy(i).feeCalculator(), address(feeCalculator));
            assertEq(
                proxy(i).hasRole(proxy(i).DEFAULT_ADMIN_ROLE(), admin),
                true
            );
            assertEq(
                proxy(i).hasRole(proxy(i).DEFAULT_ROUTER_ROLE(), address(this)),
                true
            );
        }
    }

    function testSetTransferStopSuccess() public {
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);

            vm.startPrank(admin);
            vm.expectEmit();
            emit IPool.UpdateStopTransfer(true);
            p.setTransferStop(true);
            assertEq(p.transferStop(), true);

            vm.expectEmit();
            emit IPool.UpdateStopTransfer(false);
            p.setTransferStop(false);
            assertEq(p.transferStop(), false);
            vm.stopPrank();
        }
    }

    // - registerPeerPool() & activatePeerPool() success test
    function testRegisterPeerPoolSuccess() public {
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            for (uint8 j = 0; j < poolIds.length; j++) {
                if (i == j) {
                    continue;
                }

                vm.prank(admin);
                p.registerPeerPool(chainIds[j], poolIds[j], 100);
                uint256 index = p.peerPoolInfoIndexSeek(
                    chainIds[j],
                    poolIds[j]
                );
                IPool.PeerPoolInfo memory peerPoolInfo = p.peerPoolInfos(index);
                assertEq(peerPoolInfo.chainId, chainIds[j]);
                assertEq(peerPoolInfo.id, poolIds[j]);
                assertEq(peerPoolInfo.weight, DEFAULT_WEIGHT);
                assertEq(peerPoolInfo.balance, 0);
                assertEq(peerPoolInfo.targetBalance, 0);
                assertEq(peerPoolInfo.lastKnownBalance, 0);
                assertEq(peerPoolInfo.credits, 0);
                assertEq(peerPoolInfo.ready, false);

                vm.prank(admin);
                p.activatePeerPool(chainIds[j], poolIds[j]);
                peerPoolInfo = p.peerPoolInfos(index);
                assertEq(peerPoolInfo.ready, true);
            }
        }
    }

    // - registerPeerPool() & activatePeerPool() success test
    function testSetDeltaParam() public {
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            for (uint8 j = 0; j < poolIds.length; j++) {
                if (i == j) {
                    continue;
                }
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IAccessControl
                            .AccessControlUnauthorizedAccount
                            .selector,
                        address(this),
                        p.DEFAULT_ADMIN_ROLE()
                    )
                );
                p.setDeltaParam(
                    true,
                    200, // 2%
                    600, // 6%
                    true, //default
                    true //default
                );

                vm.prank(admin);
                p.setDeltaParam(
                    true,
                    200, // 2%
                    600, // 6%
                    true, //default
                    true //default
                );
                // check delta params
                assertEq(p.batched(), true);
                assertEq(p.swapDeltaBP(), 200);
                assertEq(p.lpDeltaBP(), 600);
                assertEq(p.defaultLPMode(), true);
                assertEq(p.defaultSwapMode(), true);
            }
        }
    }

    function testSetMaxTotalDeposits() public {
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            for (uint8 j = 0; j < poolIds.length; j++) {
                if (i == j) {
                    continue;
                }

                vm.prank(admin);
                vm.expectEmit(true, false, false, true);
                emit IPool.SetMaxTotalDeposits(1000);
                p.setMaxTotalDeposits(1000);

                assertEq(p.maxTotalDeposits(), 1000);
            }
        }
    }

    function testSetupCredited() public {
        setupCredited(defaultMintAmountLd);
        address _from = address(this);
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            assertEq(
                p.balanceOf(_from),
                LDToGD(defaultMintAmountLd),
                "balance[LP]"
            );
            assertEq(
                ERC20(p.token()).balanceOf(_from),
                2 * defaultMintTokenAmount - defaultMintAmountLd,
                "balance[token]"
            );
            assertEq(
                p.totalLiquidity(),
                LDToGD(defaultMintAmountLd),
                "initial totalLiquidity"
            );
            assertEq(p.deltaCredit(), 0, "initial deltaCredit");

            uint8 j = (i + 1) % 3;
            uint256 index = p.peerPoolInfoIndexSeek(chainIds[j], poolIds[j]);
            IPool.PeerPoolInfo memory peerPoolInfo = p.peerPoolInfos(index);
            assertEq(peerPoolInfo.weight, 100, "initial peerPool.weight");
            assertEq(
                peerPoolInfo.balance,
                LDToGD(defaultMintAmountLd / 2),
                "initial peerPool.balance"
            );
            assertEq(
                peerPoolInfo.targetBalance,
                LDToGD(defaultMintAmountLd / 2),
                "initial peerPool.targetBalance"
            );
            assertEq(
                peerPoolInfo.lastKnownBalance,
                LDToGD(defaultMintAmountLd / 2),
                "initial peerPool.lastKnownBalance"
            );
            assertEq(peerPoolInfo.credits, 0, "initial credits");
        }
    }

    function testSetPeerPoolSuccess() public {
        setupMinted(defaultMintAmountLd);
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            for (uint8 j = 0; j < poolIds.length; j++) {
                if (i == j) continue;
                uint256 index = p.peerPoolInfoIndexSeek(
                    chainIds[j],
                    poolIds[j]
                );
                IPool.PeerPoolInfo memory peerPoolInfo = p.peerPoolInfos(index);

                assertEq(peerPoolInfo.weight, 100);
                vm.prank(admin);
                p.setPeerPoolWeight(chainIds[j], poolIds[j], 200);
                peerPoolInfo = p.peerPoolInfos(index);
                assertEq(peerPoolInfo.weight, 200);
            }
        }
    }

    // - mint() success test
    function testMintSuccess() public {
        uint256 _amountLD = defaultMintAmountLd;
        address _to = address(this);

        correctRegisterPeerPool(
            chainIds[0],
            poolIds[0],
            chainIds[1],
            poolIds[1],
            100
        );
        Pool p = proxy(0);
        vm.chainId(chainIds[0]);

        uint256 retGD = p.mint(_to, _amountLD);

        assertEq(p.balanceOf(_to), LDToGD(_amountLD), "p.balanceOf(_to)"); // pass mint in LD and actually minted in GD
        assertEq(retGD, LDToGD(_amountLD), "retGD");

        // check delta parameters:
        assertEq(p.deltaCredit(), 0, "deltaCredit");
        assertEq(
            p.totalLiquidity(),
            LDToGD(defaultMintAmountLd),
            "totalLiquidity"
        ); //liq is in GD
        assertEq(p.totalWeight(), 100, "totalWeight");

        uint256 index = p.peerPoolInfoIndexSeek(chainIds[1], poolIds[1]);
        IPool.PeerPoolInfo memory peerPoolInfo = p.peerPoolInfos(index);
        assertEq(peerPoolInfo.chainId, chainIds[1], "chainId");
        assertEq(peerPoolInfo.id, poolIds[1], "poolId");
        assertEq(peerPoolInfo.weight, 100, "weight");
        assertEq(peerPoolInfo.balance, 0, "balance");
        assertEq(peerPoolInfo.targetBalance, 0, "targetBalance");
        assertEq(peerPoolInfo.lastKnownBalance, 0, "lastKnownBalance");
        assertEq(peerPoolInfo.credits, LDToGD(defaultMintAmountLd), "credits");
        assertEq(peerPoolInfo.ready, true, "ready");
    }

    function testMintFailByExceedMaxDeposit() public {
        uint256 _amountLD = defaultMintAmountLd;
        address _to = address(this);

        correctRegisterPeerPool(
            chainIds[0],
            poolIds[0],
            chainIds[1],
            poolIds[1],
            100
        );

        Pool p = proxy(0);
        vm.prank(admin);

        // Set new limits where the maxTotalDeposits should be reached after minting
        vm.expectEmit(true, false, false, true);
        emit IPool.SetMaxTotalDeposits(_amountLD + 100);
        p.setMaxTotalDeposits(_amountLD + 100);

        // First mint within the new limits should succeed
        p.mint(_to, _amountLD);
        // Check that the totalLiquidity has been updated
        assertEq(
            p.totalLiquidity(),
            LDToGD(_amountLD),
            "totalLiquidity updated"
        );

        // Second mint should fail due to maxTotalDeposits being exceeded
        uint256 nextAmountLD = 200;
        uint256 expectedTotalLiquidity = GDToLD(p.totalLiquidity()) +
            nextAmountLD;

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiExceed.selector,
                "maxTotalDeposits",
                expectedTotalLiquidity,
                p.maxTotalDeposits()
            )
        );
        p.mint(_to, nextAmountLD);

        // Check that the totalLiquidity is not changed since mint failed
        assertEq(
            p.totalLiquidity(),
            LDToGD(_amountLD),
            "totalLiquidity not changed"
        );
    }

    // - transfer() success test
    function testTransfer() public {
        setupCredited(defaultMintAmountLd);
        address _to = address(this);
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            uint8 j = (i + 1) % 3;

            uint256 _amountLD = LD(1000);
            uint256 _amountGD = LDToGD(_amountLD);
            uint256 _minAmountLD = LD(990);

            ITransferPoolFeeCalculator.FeeInfo memory f = p.transfer(
                chainIds[j],
                poolIds[j],
                _to,
                _amountLD,
                _minAmountLD,
                true
            );
            assertEq(
                f.amountGD,
                LDToGD(_amountLD) - f.lpFee - f.eqFee - f.protocolFee,
                "f.amountGD"
            );
            assertEq(f.protocolFee, GD(8700) / 10000, "f.protocolFee");
            assertEq(f.lpFee, _amountGD / 10000, "f.lpFee");
            assertEq(f.eqFee, 0, "f.eqFee");
            assertEq(f.eqReward, 0, "f.eqReward");
            assertEq(
                f.balanceDecrease,
                _amountGD - f.lpFee + f.eqReward,
                "f.balaanceDecrease"
            );

            ERC20(p.token()).transfer(address(p), _amountLD);
            p.sendCredit(chainIds[j], poolIds[j]);
            // check delta parameters:
            assertEq(p.deltaCredit(), LDToGD(_amountLD), "deltaCredit");
            assertEq(
                p.totalLiquidity(),
                LDToGD(defaultMintAmountLd),
                "totalLiquidity"
            );
            assertEq(p.totalWeight(), 200, "totalWeight");
            assertEq(p.eqFeePool(), 0, "eqFeePool");

            uint256 index = p.peerPoolInfoIndexSeek(chainIds[j], poolIds[j]);
            IPool.PeerPoolInfo memory peerPoolInfo = p.peerPoolInfos(index);
            assertEq(peerPoolInfo.weight, 100, "weight");
            assertEq(
                peerPoolInfo.balance,
                LDToGD(defaultMintAmountLd / 2) - f.balanceDecrease,
                "balance"
            );
            assertEq(
                peerPoolInfo.targetBalance,
                LDToGD(defaultMintAmountLd / 2),
                "targetBalance"
            );
            assertEq(
                peerPoolInfo.lastKnownBalance,
                LDToGD(defaultMintAmountLd / 2),
                "lastKnownBalance"
            );
            assertEq(peerPoolInfo.credits, 0, "credits");
        }
    }

    function testTransferFailWithZeroBalance() public {
        setupCredited(defaultMintAmountLd);
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            uint8 j = (i + 1) % 3;

            uint256 _amountLD = LD(1000);
            uint256 _minAmountLD = LD(990);

            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiZeroAddress.selector,
                    "from"
                )
            );

            p.transfer(
                chainIds[j],
                poolIds[j],
                empty,
                _amountLD,
                _minAmountLD,
                true
            );
        }
    }

    // - recv() success test
    function testRecv() public {
        setupCredited(defaultMintAmountLd);
        address _to = address(this);
        uint256 length = poolIds.length;
        for (uint8 i = 0; i < length; i++) {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            uint8 j = (i + 1) % 3;

            ITransferPoolFeeCalculator.FeeInfo
                memory f = ITransferPoolFeeCalculator.FeeInfo({
                    amountGD: 998_930_000,
                    protocolFee: 970_000,
                    lpFee: 30_000,
                    eqFee: 30_000,
                    eqReward: 0,
                    balanceDecrease: 999_970_000
                });

            (uint256 ret, bool isTransferred) = p.recv(
                chainIds[j],
                poolIds[j],
                _to,
                f,
                true
            );
            assertTrue(isTransferred, "isTransferred");
            assertEq(ret, GDToLD(f.amountGD + f.eqReward), "recv amount");
            // check delta parameters:
            assertEq(p.deltaCredit(), 0, "deltaCredit");
            assertEq(
                p.totalLiquidity(),
                LDToGD(defaultMintAmountLd) + f.lpFee,
                "totalLiquidity"
            );
            assertEq(p.totalWeight(), 200, "totalWeight");
            assertEq(p.eqFeePool(), 30_000, "eqFeePool");

            uint256 index = p.peerPoolInfoIndexSeek(chainIds[j], poolIds[j]);
            IPool.PeerPoolInfo memory peerPoolInfo = p.peerPoolInfos(index);
            assertEq(peerPoolInfo.weight, 100, "weight");
            assertEq(
                peerPoolInfo.balance,
                LDToGD(defaultMintAmountLd / 2),
                "balance"
            );
            assertEq(
                peerPoolInfo.targetBalance,
                LDToGD(defaultMintAmountLd / 2),
                "targetBalance"
            );
            assertEq(
                peerPoolInfo.lastKnownBalance,
                LDToGD(defaultMintAmountLd / 2) - f.balanceDecrease,
                "lastKnownBalance"
            );
            assertEq(peerPoolInfo.credits, 0, "credits");

            // LPToLD test
            assertEq(
                p.totalSupply(),
                LDToGD(defaultMintAmountLd),
                "totalSupply"
            );
            assertEq(p.LPToLD(10_000_000), 1_000_000_300, "lpToLd");
        }
    }

    function testRecvWhenFlowRateLimitIsExceeded() public {
        setupCredited(defaultMintAmountLd);
        address _to = address(this);
        Pool p = proxy(0);
        vm.chainId(chainIds[0]);

        ITransferPoolFeeCalculator.FeeInfo memory f = ITransferPoolFeeCalculator
            .FeeInfo({
                amountGD: 998_930_000,
                protocolFee: 970_000,
                lpFee: 30_000,
                eqFee: 30_000,
                eqReward: 0,
                balanceDecrease: 999_970_000
            });

        (, bool isTransferred) = p.recv(chainIds[1], poolIds[1], _to, f, true);

        assertTrue(isTransferred, "isTransferred");

        (, isTransferred) = p.recv(chainIds[1], poolIds[1], _to, f, true);

        assertFalse(isTransferred, "isTransferred");

        uint256 index = p.peerPoolInfoIndexSeek(chainIds[1], poolIds[1]);
        IPool.PeerPoolInfo memory peerPoolInfo = p.peerPoolInfos(index);
        assertEq(peerPoolInfo.weight, 100, "weight");
        assertEq(
            peerPoolInfo.balance,
            LDToGD(defaultMintAmountLd / 2),
            "balance"
        );
        assertEq(
            peerPoolInfo.targetBalance,
            LDToGD(defaultMintAmountLd / 2),
            "targetBalance"
        );
        assertEq(
            peerPoolInfo.lastKnownBalance,
            LDToGD(defaultMintAmountLd / 2) -
                f.balanceDecrease -
                // TODO why
                f.balanceDecrease,
            "lastKnownBalance"
        );
        assertEq(peerPoolInfo.credits, 0, "credits");
    }

    function testRecvWhenERC20TransferFailed() public {
        setupCredited(defaultMintAmountLd);
        address _to = address(this);
        Pool p = proxy(0);
        ITransferPoolFeeCalculator.FeeInfo memory f = ITransferPoolFeeCalculator
            .FeeInfo({
                amountGD: 998_930_000,
                protocolFee: 970_000,
                lpFee: 30_000,
                eqFee: 30_000,
                eqReward: 0,
                balanceDecrease: 999_970_000
            });

        uint256 currentBalance = IERC20(p.token()).balanceOf(address(p));
        MockToken(p.token()).burn(address(p), currentBalance);

        (, bool isTransferred) = p.recv(chainIds[1], poolIds[1], _to, f, true);

        assertFalse(isTransferred, "isTransferred");

        uint256 index = p.peerPoolInfoIndexSeek(chainIds[1], poolIds[1]);
        IPool.PeerPoolInfo memory peerPoolInfo = p.peerPoolInfos(index);
        assertEq(peerPoolInfo.weight, 100, "weight");
        assertEq(
            peerPoolInfo.balance,
            LDToGD(defaultMintAmountLd / 2),
            "balance"
        );
        assertEq(
            peerPoolInfo.targetBalance,
            LDToGD(defaultMintAmountLd / 2),
            "targetBalance"
        );
        assertEq(
            peerPoolInfo.lastKnownBalance,
            LDToGD(defaultMintAmountLd / 2) - f.balanceDecrease,
            "lastKnownBalance"
        );
        assertEq(peerPoolInfo.credits, 0, "credits");
    }

    // - withdrawRemote() success test
    function testWithdrawRemote() public {
        setupCredited(defaultMintAmountLd);
        address _to = address(this);
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            uint8 j = (i + 1) % 3;
            {
                uint256 _amountLP = GD(100);
                uint256 _minAmountLD = LD(99);
                uint256 _amountLD = p.LPToLD(_amountLP);

                // withdrawRemote is using `withdrawRemote` instead of `erc20.transfer`.
                ITransferPoolFeeCalculator.FeeInfo memory f = p.transfer(
                    chainIds[j],
                    poolIds[j],
                    _to,
                    _amountLD,
                    _minAmountLD,
                    true
                );

                assertEq(f.amountGD, 9_990_300, "f.amountGD");
                assertEq(f.protocolFee, 8700, "f.protocolFee");
                assertEq(f.lpFee, 1000, "f.lpFee");
                assertEq(f.eqFee, 0, "f.eqFee");
                assertEq(f.eqReward, 0, "f.eqReward");
                assertEq(f.balanceDecrease, 9_999_000, "f.balanceDecrease");

                // save values after transfer
                uint256 index = p.peerPoolInfoIndexSeek(
                    chainIds[j],
                    poolIds[j]
                );
                IPool.PeerPoolInfo memory peerPoolInfo0 = p.peerPoolInfos(
                    index
                );

                p.withdrawRemote(chainIds[j], poolIds[j], _to, _amountLP);
                IPool.CreditInfo memory c = p.sendCredit(
                    chainIds[j],
                    poolIds[j]
                );
                assertEq(c.credits, 0, "c.credits");
                assertEq(
                    c.targetBalance,
                    (LDToGD(defaultMintAmountLd) - _amountLP) / 2,
                    "c.targetBalance"
                );

                // check delta parameters:
                assertEq(p.deltaCredit(), _amountLP, "deltaCredit");
                assertEq(
                    p.totalLiquidity(),
                    LDToGD(defaultMintAmountLd) - _amountLP,
                    "totalLiquidity"
                );

                assertEq(p.totalWeight(), 200, "totalWeight");
                assertEq(p.eqFeePool(), 0, "eqFeePool");

                IPool.PeerPoolInfo memory peerPoolInfo = p.peerPoolInfos(index);
                assertEq(peerPoolInfo.weight, 100, "weight");
                //assertEq(balance, LDToGD(499_900_010_000), "balance");
                assertEq(
                    peerPoolInfo.balance,
                    peerPoolInfo0.balance,
                    "balance"
                );
                assertEq(
                    peerPoolInfo.targetBalance,
                    //LDToGD(500_000_000_000),
                    peerPoolInfo0.targetBalance,
                    "targetBalance"
                );
                assertEq(
                    peerPoolInfo.lastKnownBalance,
                    peerPoolInfo0.lastKnownBalance,
                    //LDToGD(500_000_000_000),
                    "lastKnownBalance"
                );
                assertEq(peerPoolInfo.credits, 0, "credits");
            }
        }
    }

    function testWithdrawRemoteFailWithZeroBalance() public {
        setupCredited(defaultMintAmountLd);
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            uint8 j = (i + 1) % 3;
            {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        ITokiErrors.TokiZeroAddress.selector,
                        "from"
                    )
                );
                p.withdrawRemote(chainIds[j], poolIds[j], empty, GD(100));
            }
        }
    }

    // - withdrawLocal -> check -> confirm() ->  success test
    function testWithdrawLocalLtOnRemote() public {
        setupCredited(defaultMintAmountLd);
        bytes memory _to = new bytes(20);
        bytes20 _b = bytes20(uint160(address(this)));
        for (uint8 i = 0; i < 20; i++) _to[i] = _b[i];

        address _from = address(this);
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            uint8 j = (i + 1) % 3;
            {
                uint256 tokenAmount0 = ERC20(p.token()).balanceOf(_from);
                uint256 _amountLD = LD(100);
                uint256 _amountLP = p.LDToLP(_amountLD);

                // withdrawLocal
                uint256 amountGD = p.withdrawLocal(
                    chainIds[j],
                    poolIds[j],
                    _from,
                    _amountLP,
                    _to
                );
                IPool.CreditInfo memory c = p.sendCredit(
                    chainIds[j],
                    poolIds[j]
                );
                // check return values
                {
                    assertEq(amountGD, _amountLP, "[1] amountGD");
                    assertEq(c.credits, 0, "[1] c.credits");
                    assertEq(
                        c.targetBalance,
                        (LDToGD(defaultMintAmountLd) - amountGD) / 2,
                        "[1] c.targetBalance"
                    );
                }

                // check balance
                {
                    assertEq(
                        p.balanceOf(_from),
                        LDToGD(defaultMintAmountLd) - _amountLP,
                        "[1] balance[LP]"
                    );
                    assertEq(
                        ERC20(p.token()).balanceOf(_from),
                        tokenAmount0,
                        "[1] balance[token]"
                    );
                }

                // check delta parameters:
                {
                    assertEq(p.deltaCredit(), 0, "[1] deltaCredit");
                    assertEq(
                        p.totalLiquidity(),
                        LDToGD(defaultMintAmountLd - _amountLD),
                        "[1] totalLiquidity"
                    );
                    assertEq(p.totalWeight(), 200, "[1] totalWeight");
                    assertEq(p.eqFeePool(), 0, "[1] eqFeePool");

                    uint256 index = p.peerPoolInfoIndexSeek(
                        chainIds[j],
                        poolIds[j]
                    );
                    IPool.PeerPoolInfo memory peerPoolInfo = p.peerPoolInfos(
                        index
                    );
                    assertEq(peerPoolInfo.weight, 100, "[1] weight");
                    assertEq(
                        peerPoolInfo.balance,
                        LDToGD(defaultMintAmountLd) / 2,
                        "[1] balance"
                    );
                    assertEq(
                        peerPoolInfo.targetBalance,
                        LDToGD(defaultMintAmountLd) / 2,
                        "[1] targetBalance"
                    );
                    assertEq(
                        peerPoolInfo.lastKnownBalance,
                        LDToGD(defaultMintAmountLd) / 2,
                        "[1] lastKnownBalance"
                    );
                    assertEq(peerPoolInfo.credits, 0, "[1] credits");
                    assertLe(
                        amountGD,
                        peerPoolInfo.balance,
                        "[1] !(_amountGD > pool.balance)"
                    ); // if condition in withdrawCheck()
                }

                uint256 amountSwap;
                uint256 amountMint;
                {
                    // withdrawCheck
                    Pool op = proxy(j);
                    vm.chainId(chainIds[j]);
                    (amountSwap, amountMint) = op.withdrawCheck(
                        chainIds[i],
                        poolIds[i],
                        amountGD
                    );
                    op.updateCredit(chainIds[i], poolIds[i], c);
                    // check return values:
                    {
                        assertEq(amountSwap, amountGD, "[2] amountSwap");
                        assertEq(amountMint, 0, "[2] amountMint");
                    }

                    // check delta parameters:
                    {
                        assertEq(op.deltaCredit(), 0, "[2] deltaCreditJ");
                        if (i > j) {
                            // final case
                            assertEq(
                                op.totalLiquidity(),
                                LDToGD(defaultMintAmountLd) - amountGD,
                                "[2] totalLiquidityJ"
                            );
                        } else {
                            assertEq(
                                op.totalLiquidity(),
                                LDToGD(defaultMintAmountLd),
                                "[2] totalLiquidityJ"
                            );
                        }
                        assertEq(op.totalWeight(), 200, "[2] totalWeightJ");
                        assertEq(op.eqFeePool(), 0, "[2] eqFeePoolJ");

                        uint256 jndex = op.peerPoolInfoIndexSeek(
                            chainIds[i],
                            poolIds[i]
                        );

                        IPool.PeerPoolInfo memory peerPoolInfoJ = op
                            .peerPoolInfos(jndex);
                        assertEq(peerPoolInfoJ.weight, 100, "[2] weight_j");
                        assertEq(
                            peerPoolInfoJ.balance,
                            LDToGD(defaultMintAmountLd) / 2 - amountGD,
                            "[2] balance_j"
                        );
                        assertEq(
                            peerPoolInfoJ.targetBalance,
                            (LDToGD(defaultMintAmountLd) - amountGD) / 2,
                            "[2] targetBalance_j"
                        );
                        assertEq(
                            peerPoolInfoJ.lastKnownBalance,
                            LDToGD(defaultMintAmountLd) / 2,
                            "[2] lastKnownBalance_j"
                        );
                        assertEq(peerPoolInfoJ.credits, 0, "[2] credits_j");
                    }
                }

                vm.chainId(chainIds[i]);
                // withdrawConfirm
                bool isTransferred = p.withdrawConfirm(
                    chainIds[j],
                    poolIds[j],
                    _from,
                    amountSwap,
                    amountMint,
                    true
                );

                // check return values:
                {
                    assertTrue(isTransferred, "[3] isTransferred");
                }

                // check balance
                {
                    assertEq(
                        p.balanceOf(_from),
                        LDToGD(defaultMintAmountLd) - _amountLP,
                        "[3] balance[LP]"
                    );
                    assertEq(
                        ERC20(p.token()).balanceOf(_from),
                        tokenAmount0 + p.LPToLD(_amountLP),
                        "[3] balance[token]"
                    );
                }

                // check delta parameters:
                {
                    assertEq(p.deltaCredit(), 0, "[3] deltaCredit");
                    assertEq(
                        p.totalLiquidity(),
                        LDToGD(defaultMintAmountLd - _amountLD),
                        "[3] totalLiquidity"
                    );
                    assertEq(p.totalWeight(), 200, "[3] totalWeight");
                    assertEq(p.eqFeePool(), 0, "[3] eqFeePool");

                    uint256 index = p.peerPoolInfoIndexSeek(
                        chainIds[j],
                        poolIds[j]
                    );
                    IPool.PeerPoolInfo memory peerPoolInfo = p.peerPoolInfos(
                        index
                    );
                    assertEq(peerPoolInfo.weight, 100, "[3] weight");
                    assertEq(
                        peerPoolInfo.balance,
                        LDToGD(defaultMintAmountLd / 2),
                        "[3] balance"
                    );
                    assertEq(
                        peerPoolInfo.targetBalance,
                        LDToGD(defaultMintAmountLd / 2),
                        "[3] targetBalance"
                    );
                    assertEq(
                        peerPoolInfo.lastKnownBalance,
                        LDToGD(defaultMintAmountLd / 2) - amountGD,
                        "[3] lastKnownBalance"
                    );
                    assertEq(peerPoolInfo.credits, 0, "[3] credits");
                }
            }
        }
    }

    // - withdrawLocal -> check(greater than peer's balance dst knows) -> confirm() ->  success test
    function testWithdrawLocalGtOnRemote() public {
        setupCredited(withdrawLocalMintAmountLd);
        bytes memory _to = new bytes(20);
        bytes20 _b = bytes20(uint160(address(this)));
        for (uint8 i = 0; i < 20; i++) _to[i] = _b[i];

        address _from = address(this);
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            uint8 j = (i + 1) % 3;
            {
                uint256 tokenAmount0 = ERC20(p.token()).balanceOf(_from);
                uint256 _amountLD = (withdrawLocalMintAmountLd / 2) + LD(100);
                uint256 _amountLP = p.LDToLP(_amountLD);

                // withdrawLocal
                uint256 amountGD = p.withdrawLocal(
                    chainIds[j],
                    poolIds[j],
                    _from,
                    _amountLP,
                    _to
                );
                IPool.CreditInfo memory c = p.sendCredit(
                    chainIds[j],
                    poolIds[j]
                );
                // check return values
                {
                    assertEq(amountGD, _amountLP, "[1] amountGD");
                    assertEq(c.credits, 0, "[1] c.credits");
                    assertEq(
                        c.targetBalance,
                        (LDToGD(withdrawLocalMintAmountLd) - amountGD) / 2,
                        "[1] c.targetBalance"
                    );
                }

                // check balance
                {
                    assertEq(
                        p.balanceOf(_from),
                        LDToGD(withdrawLocalMintAmountLd) - _amountLP,
                        "[1] balance[LP]"
                    );
                    assertEq(
                        ERC20(p.token()).balanceOf(_from),
                        tokenAmount0,
                        "[1] balance[token]"
                    );
                }

                // check delta parameters:
                {
                    assertEq(p.deltaCredit(), 0, "[1] deltaCredit");
                    assertEq(
                        p.totalLiquidity(),
                        LDToGD(withdrawLocalMintAmountLd - _amountLD),
                        "[1] totalLiquidity"
                    );
                    assertEq(p.totalWeight(), 200, "[1] totalWeight");
                    assertEq(p.eqFeePool(), 0, "[1] eqFeePool");

                    uint256 index = p.peerPoolInfoIndexSeek(
                        chainIds[j],
                        poolIds[j]
                    );
                    IPool.PeerPoolInfo memory peerPoolInfo = p.peerPoolInfos(
                        index
                    );
                    assertEq(peerPoolInfo.weight, 100, "[1] weight");
                    assertEq(
                        peerPoolInfo.balance,
                        LDToGD(withdrawLocalMintAmountLd) / 2,
                        "[1] balance"
                    );
                    assertEq(
                        peerPoolInfo.targetBalance,
                        LDToGD(withdrawLocalMintAmountLd) / 2,
                        "[1] targetBalance"
                    );
                    assertEq(
                        peerPoolInfo.lastKnownBalance,
                        LDToGD(withdrawLocalMintAmountLd) / 2,
                        "[1] lastKnownBalance"
                    );
                    assertEq(peerPoolInfo.credits, 0, "[1] credits");
                    assertGt(
                        amountGD,
                        peerPoolInfo.balance,
                        "[1] !(_amountGD > pool.balance)"
                    ); // if condition in withdrawCheck()
                }

                uint256 amountSwap;
                uint256 amountMint;
                {
                    // withdrawCheck
                    Pool op = proxy(j);
                    vm.chainId(chainIds[j]);
                    (amountSwap, amountMint) = op.withdrawCheck(
                        chainIds[i],
                        poolIds[i],
                        amountGD
                    );
                    op.updateCredit(chainIds[i], poolIds[i], c);
                    // check return values:
                    {
                        assertEq(
                            amountSwap,
                            LDToGD(withdrawLocalMintAmountLd) / 2,
                            "[2] amountSwap"
                        );
                        assertEq(
                            amountMint,
                            amountGD - LDToGD(withdrawLocalMintAmountLd / 2),
                            "[2] amountMint"
                        );
                        // abobe expression means maximum transfer equals remote balance
                        assertEq(
                            LDToGD(withdrawLocalMintAmountLd / 2),
                            amountGD - amountMint,
                            "[2] maximux transfer"
                        );
                    }

                    // check delta parameters:
                    {
                        assertEq(op.deltaCredit(), 0, "[2] deltaCredit_j");
                        if (i > j) {
                            // final case
                            assertEq(
                                op.totalLiquidity(),
                                LDToGD(withdrawLocalMintAmountLd) -
                                    LDToGD(withdrawLocalMintAmountLd / 2),
                                "[2] [>] totalLiquidity_j"
                            );
                        } else {
                            assertEq(
                                op.totalLiquidity(),
                                LDToGD(withdrawLocalMintAmountLd),
                                "[2] [<=] totalLiquidity_j"
                            );
                        }
                        assertEq(op.totalWeight(), 200, "[2] totalWeight_j");
                        assertEq(op.eqFeePool(), 0, "[2] eqFeePool_j");

                        uint256 jndex = op.peerPoolInfoIndexSeek(
                            chainIds[i],
                            poolIds[i]
                        );
                        IPool.PeerPoolInfo memory peerPoolInfoJ = op
                            .peerPoolInfos(jndex);
                        assertEq(peerPoolInfoJ.weight, 100, "[2] weightJ");
                        assertEq(peerPoolInfoJ.balance, 0, "[2] balanceJ");
                        assertEq(
                            peerPoolInfoJ.targetBalance,
                            (LDToGD(withdrawLocalMintAmountLd) - amountGD) / 2,
                            "[2] targetBalanceJ"
                        );
                        assertEq(
                            peerPoolInfoJ.lastKnownBalance,
                            LDToGD(withdrawLocalMintAmountLd / 2),
                            "[2] lastKnownBalanceJ"
                        );
                        assertEq(peerPoolInfoJ.credits, 0, "[2] creditsJ");
                    }
                }

                vm.chainId(chainIds[i]);
                // withdrawConfirm
                bool isTransferred = p.withdrawConfirm(
                    chainIds[j],
                    poolIds[j],
                    _from,
                    amountSwap,
                    amountMint,
                    true
                );

                // check return values:
                {
                    assertTrue(isTransferred, "[3] isTransferred");
                }

                // check balance
                {
                    assertEq(
                        p.balanceOf(_from),
                        LDToGD(withdrawLocalMintAmountLd) -
                            _amountLP +
                            amountMint,
                        "[3] balance[LP]"
                    );
                    assertEq(
                        ERC20(p.token()).balanceOf(_from),
                        tokenAmount0 + GDToLD(amountSwap),
                        "[3] balance[token]"
                    );
                }

                // check delta parameters:
                {
                    assertEq(p.deltaCredit(), 0, "[3] deltaCredit");
                    assertEq(
                        p.totalLiquidity(),
                        LDToGD(withdrawLocalMintAmountLd - _amountLD) +
                            amountMint,
                        "[3] totalLiquidity"
                    );
                    assertEq(p.totalWeight(), 200, "[3] totalWeight");
                    assertEq(p.eqFeePool(), 0, "[3] eqFeePool");

                    uint256 index = p.peerPoolInfoIndexSeek(
                        chainIds[j],
                        poolIds[j]
                    );
                    IPool.PeerPoolInfo memory peerPoolInfo = p.peerPoolInfos(
                        index
                    );
                    assertEq(peerPoolInfo.weight, 100, "[3] weight");
                    assertEq(
                        peerPoolInfo.balance,
                        LDToGD(withdrawLocalMintAmountLd / 2),
                        "[3] balance"
                    );
                    assertEq(
                        peerPoolInfo.targetBalance,
                        LDToGD(withdrawLocalMintAmountLd / 2),
                        "[3] targetBalance"
                    );
                    assertEq(
                        peerPoolInfo.lastKnownBalance,
                        LDToGD(withdrawLocalMintAmountLd / 2) - amountSwap,
                        "[3] lastKnownBalance"
                    );
                    assertEq(peerPoolInfo.credits, 0, "[3] credits");
                }
            }
        }
    }

    function testWithdrawConfirmWhenFlowRateLimitIsExceeded() public {
        setupCredited(defaultMintAmountLd);
        address _from = address(this);
        Pool p = proxy(0);
        vm.chainId(chainIds[0]);
        uint256 amountGD = 1_000_000_000;
        uint256 amountMint = 0;

        bool isTransferred = p.withdrawConfirm(
            chainIds[1],
            poolIds[1],
            _from,
            amountGD,
            amountMint,
            true
        );

        assertTrue(isTransferred, "isTransferred");

        isTransferred = p.withdrawConfirm(
            chainIds[1],
            poolIds[1],
            _from,
            amountGD,
            amountMint,
            true
        );

        assertFalse(isTransferred, "isTransferred");

        uint256 index = p.peerPoolInfoIndexSeek(chainIds[1], poolIds[1]);
        IPool.PeerPoolInfo memory peerPoolInfo = p.peerPoolInfos(index);
        assertEq(peerPoolInfo.weight, 100, "weight");
        assertEq(
            peerPoolInfo.balance,
            LDToGD(defaultMintAmountLd / 2),
            "balance"
        );
        assertEq(
            peerPoolInfo.targetBalance,
            LDToGD(defaultMintAmountLd / 2),
            "targetBalance"
        );
        assertEq(
            peerPoolInfo.lastKnownBalance,
            LDToGD(defaultMintAmountLd / 2) - amountGD - amountGD,
            "lastKnownBalance"
        );
        assertEq(peerPoolInfo.credits, 0, "credits");
    }

    function testWithdrawConfirmWhenERC20TransferFailed() public {
        setupCredited(defaultMintAmountLd);
        address _from = address(this);
        Pool p = proxy(0);

        uint256 amountGD = 10000;
        uint256 amountMint = 0;

        uint256 currentBalance = IERC20(p.token()).balanceOf(address(p));
        MockToken(p.token()).burn(address(p), currentBalance);

        bool isTransferred = p.withdrawConfirm(
            chainIds[1],
            poolIds[1],
            _from,
            amountGD,
            amountMint,
            true
        );

        assertFalse(isTransferred, "isTransferred");

        uint256 index = p.peerPoolInfoIndexSeek(chainIds[1], poolIds[1]);
        IPool.PeerPoolInfo memory peerPoolInfo = p.peerPoolInfos(index);
        assertEq(peerPoolInfo.weight, 100, "weight");
        assertEq(
            peerPoolInfo.balance,
            LDToGD(defaultMintAmountLd / 2),
            "balance"
        );
        assertEq(
            peerPoolInfo.targetBalance,
            LDToGD(defaultMintAmountLd / 2),
            "targetBalance"
        );
        assertEq(
            peerPoolInfo.lastKnownBalance,
            LDToGD(defaultMintAmountLd / 2) - amountGD,
            "lastKnownBalance"
        );
        assertEq(peerPoolInfo.credits, 0, "credits");
    }

    // - sendCredit() success test
    function testSendCreditAndUpdateCredit() public {
        setupMinted(defaultMintAmountLd);
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            for (uint8 j = 0; j < poolIds.length; j++) {
                if (i == j) continue;
                // sendCredit (i) -> j
                vm.chainId(chainIds[i]);
                IPool.CreditInfo memory c = p.sendCredit(
                    chainIds[j],
                    poolIds[j]
                );

                assertEq(
                    c.targetBalance,
                    LDToGD(
                        (defaultMintAmountLd * DEFAULT_WEIGHT) /
                            (DEFAULT_WEIGHT * (poolIds.length - 1))
                    ),
                    "c.targetBalance"
                );
                assertEq(
                    c.credits,
                    LDToGD(defaultMintAmountLd / 2),
                    "c.credits"
                );

                // updateCredit i -> (j)
                Pool op = proxy(j);
                vm.chainId(chainIds[j]);
                uint256 jndex = op.peerPoolInfoIndexSeek(
                    chainIds[i],
                    poolIds[i]
                );
                op.updateCredit(chainIds[i], poolIds[i], c);
                IPool.PeerPoolInfo memory peerPoolInfo = op.peerPoolInfos(
                    jndex
                );
                assertEq(peerPoolInfo.balance, c.credits);
                assertEq(peerPoolInfo.targetBalance, c.targetBalance);
            }
        }
    }

    // - withdrawInstant() success test
    function testWithdrawInstant() public {
        setupCredited(defaultMintAmountLd);
        address _from = address(this);
        address _to = alice;
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            // Amount small enough to avoid consuming deltaCredits in delta calculation
            uint256 mintLD = LD(1_000);
            correctMint(chainIds[i], poolIds[i], _to, mintLD);
            assertEq(
                p.totalLiquidity(),
                LDToGD(defaultMintAmountLd + mintLD),
                "totalLiquidity0"
            );
            assertEq(p.deltaCredit(), LDToGD(mintLD), "deltaCredit0");
            uint256 _prevBalance = mockUSDs[i].balanceOf(_to);

            uint256 _amountLP = 100 * globalDecimalsConvert;
            uint256 _amountGD = p.withdrawInstant(_from, _amountLP, _to);
            // check return values
            {
                assertEq(_amountGD, _amountLP, "amountGD");
                assertEq(
                    mockUSDs[i].balanceOf(_to),
                    _prevBalance + GDToLD(_amountLP),
                    "balance"
                );
            }

            // check delta parameters:
            {
                assertEq(
                    p.deltaCredit(),
                    LDToGD(mintLD) - _amountGD,
                    "deltaCredit1"
                );
                assertEq(
                    p.totalLiquidity(),
                    LDToGD(defaultMintAmountLd + mintLD) - _amountGD, // 1_000_900_000_000),
                    "totalLiquidity1"
                );
                assertEq(p.totalWeight(), 200, "totalWeight");
                assertEq(p.eqFeePool(), 0, "eqFeePool");

                uint8 j = (i + 1) % 3;
                uint256 index = p.peerPoolInfoIndexSeek(
                    chainIds[j],
                    poolIds[j]
                );
                IPool.PeerPoolInfo memory peerPoolInfo = p.peerPoolInfos(index);
                assertEq(peerPoolInfo.weight, 100, "weight");
                assertEq(
                    peerPoolInfo.balance,
                    LDToGD(defaultMintAmountLd / 2),
                    "balance"
                );
                assertEq(
                    peerPoolInfo.targetBalance,
                    LDToGD(defaultMintAmountLd / 2),
                    "targetBalance"
                );
                assertEq(
                    peerPoolInfo.lastKnownBalance,
                    LDToGD(defaultMintAmountLd / 2),
                    "lastKnownBalance"
                );
                assertEq(peerPoolInfo.credits, 0, "credits");
            }
        }
    }

    function testWithdrawInstantFailWithZeroBalance() public {
        setupCredited(defaultMintAmountLd);
        address _to = alice;
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        ITokiErrors.TokiZeroAddress.selector,
                        "from"
                    )
                );
                p.withdrawInstant(empty, GD(100), _to);
            }
        }
    }

    function testGetPeerPool() public {
        uint8 i = 0;
        Pool p = proxy(i);

        uint8 j = 1;
        vm.chainId(chainIds[i]);
        vm.prank(admin);
        p.registerPeerPool(chainIds[j], poolIds[j], 100);

        IPool.PeerPoolInfo memory peerPoolInfo = p.getPeerPoolInfo(
            chainIds[j],
            poolIds[j]
        );
        assertEq(peerPoolInfo.chainId, chainIds[j], "peerPoolInfo.chainId");
        assertEq(peerPoolInfo.id, poolIds[j], "peerPoolInfo.id");
        assertEq(peerPoolInfo.weight, 100, "peerPoolInfo.weight");
    }

    function testCalcFee() public {
        setupCredited(defaultMintAmountLd);

        uint8 i = 0;
        Pool p = proxy(i);
        vm.chainId(chainIds[i]);
        uint8 j = 1;

        vm.chainId(chainIds[i]);
        ITransferPoolFeeCalculator.FeeInfo memory fee = p.calcFee(
            chainIds[j],
            poolIds[j],
            address(0x5),
            1_000_000
        );
        assertEq(fee.amountGD, 9990, "fee.amountGD");
        assertEq(fee.protocolFee, 9, "fee.protocolFee");
        assertEq(fee.lpFee, 1, "fee.lpFee");
        assertEq(fee.eqFee, 0, "fee.eqFee");
        assertEq(fee.eqReward, 0, "fee.eqReward");
        assertEq(fee.balanceDecrease, 0, "fee.balanceDecrease");
    }

    function testCallDeltaInFullMode() public {
        // full mode
        setupCredited(defaultMintAmountLd);
        address _to = alice;
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            assertTrue(p.batched(), "batched");
            assertTrue(p.defaultLPMode(), "defaultLPMode");
            assertTrue(p.defaultSwapMode(), "defaultSwapMode");

            vm.chainId(chainIds[i]);
            // amount small enough to avoid consuming deltaCredits in delta calculation
            uint256 mintLD = LD(1_000);
            correctMint(chainIds[i], poolIds[i], _to, mintLD);
            assertEq(
                p.totalLiquidity(),
                LDToGD(defaultMintAmountLd + mintLD),
                "totalLiquidity0"
            );
            assertEq(p.deltaCredit(), LDToGD(mintLD), "deltaCredit0");

            // amount enough to consume deltaCredits in delta calculation
            uint256 j = (i + 1) % poolIds.length;

            // solhint-disable-next-line no-unused-vars
            ITransferPoolFeeCalculator.FeeInfo memory _feeInfo = p.transfer(
                chainIds[j],
                poolIds[j],
                _to,
                LD(50_000),
                LD(49_000),
                true
            );
            // all deltaCredits are consumed
            assertEq(p.deltaCredit(), 0, "deltaCredit1");
        }
    }

    function testCallDeltaInNonFullMode() public {
        setupCredited(defaultMintAmountLd);
        address _to = alice;
        for (uint8 i = 0; i < poolIds.length; i++) {
            // non full mode
            correctSetDefaultDelta(i, false, false);

            Pool p = proxy(i);
            assertTrue(p.batched(), "batched");
            assertFalse(p.defaultLPMode(), "defaultLPMode");
            assertFalse(p.defaultSwapMode(), "defaultSwapMode");

            vm.chainId(chainIds[i]);

            // amount small enough to avoid consuming deltaCredits in delta calculation
            uint256 mintLD = LD(1_000);
            correctMint(chainIds[i], poolIds[i], _to, mintLD);
            assertEq(
                p.totalLiquidity(),
                LDToGD(defaultMintAmountLd + mintLD),
                "totalLiquidity0"
            );
            assertEq(p.deltaCredit(), LDToGD(mintLD), "deltaCredit0");

            // amount enough to consume deltaCredits in delta calculation
            uint256 j = (i + 1) % poolIds.length;

            // solhint-disable-next-line no-unused-vars
            ITransferPoolFeeCalculator.FeeInfo memory _feeInfo = p.transfer(
                chainIds[j],
                poolIds[j],
                _to,
                LD(50_000),
                LD(49_000),
                true
            );
            // not all deltaCredits are consumed
            assertEq(p.deltaCredit(), LD(500), "deltaCredit1");
        }
    }

    // ====================== require failure cases ======================
    // - mint() failure cases
    function testMintRequireFailure() public {}

    // - transfer() failure cases
    function testTransferRequireFailurePrevious() public {
        uint8 i = 0;
        {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            uint8 j = (i + 1) % 3;
            uint256 _amountLD = 1_000 * localDecimalsConvert;
            uint256 _minAmountLD = 990 * localDecimalsConvert;
            uint256 _weight = 100;
            correctSetDefaultDelta(i, false, false);

            vm.prank(admin);
            p.setTransferStop(true);
            vm.expectRevert(
                abi.encodeWithSelector(ITokiErrors.TokiTransferIsStop.selector)
            );
            p.transfer(
                chainIds[j],
                poolIds[j],
                address(this),
                _amountLD,
                _minAmountLD,
                false
            );

            vm.prank(admin);
            p.setTransferStop(false);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiZeroAddress.selector,
                    "from"
                )
            );
            p.transfer(
                chainIds[j],
                poolIds[j],
                address(0x0),
                _amountLD,
                _minAmountLD,
                false
            );

            vm.expectRevert(
                abi.encodeWithSelector(ITokiErrors.TokiNoPeerPoolInfo.selector)
            );
            p.transfer(
                chainIds[j],
                poolIds[j],
                address(this),
                _amountLD,
                _minAmountLD,
                false
            );

            vm.prank(admin);
            p.registerPeerPool(chainIds[j], poolIds[j], _weight);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiPeerPoolIsNotReady.selector,
                    chainIds[j],
                    poolIds[j]
                )
            );
            p.transfer(
                chainIds[j],
                poolIds[j],
                address(this),
                _amountLD,
                _minAmountLD,
                false
            );
        }
    }

    function testTransferRequireFailureCore() public {
        setupCredited(defaultMintAmountLd);
        uint8 i = 0;
        {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            uint8 j = (i + 1) % 3;
            uint256 _peerBalance0 = p
                .getPeerPoolInfo(chainIds[j], poolIds[j])
                .balance;
            uint256 _amountLD = 1_000 * localDecimalsConvert;
            uint256 _minAmountLD = 990 * localDecimalsConvert;
            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiSlippageTooHigh.selector,
                    LDToGD(_amountLD),
                    0,
                    0,
                    LDToGD(_minAmountLD * 10)
                )
            );
            p.transfer(
                chainIds[j],
                poolIds[j],
                address(this),
                _amountLD,
                _minAmountLD * 10,
                false
            );

            // if convertRate is 1, fee library error occurs
            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiInsufficientPoolLiquidity.selector,
                    _peerBalance0,
                    LDToGD(defaultMintAmountLd * 10)
                )
            );
            p.transfer(
                chainIds[j],
                poolIds[j],
                address(this),
                defaultMintAmountLd * 10,
                _minAmountLD,
                false
            );
        }
    }

    function testRecvRequireFailure() public {
        setupCredited(defaultMintAmountLd);
        uint8 i = 0;
        // Revert when a chainId is invalid.
        {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiPeerPoolInfoNotFound.selector,
                    9999,
                    1
                )
            );
            p.recv(
                9999,
                1,
                address(this),
                ITransferPoolFeeCalculator.FeeInfo(0, 0, 0, 0, 0, 0),
                true
            );
        }

        // Revert when a poolId is invalid.
        {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiPeerPoolInfoNotFound.selector,
                    1,
                    9999
                )
            );
            p.recv(
                1,
                9999,
                address(this),
                ITransferPoolFeeCalculator.FeeInfo(0, 0, 0, 0, 0, 0),
                true
            );
        }
    }

    function testWithdrawRemoteFailurePrevious() public {
        uint8 i = 0;
        {
            uint8 j = 1;
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);

            // ready
            correctSetDefaultDelta(i, false, false);
            vm.startPrank(admin);
            p.registerPeerPool(chainIds[j], poolIds[j], 100);
            p.activatePeerPool(chainIds[j], poolIds[j]);
            vm.stopPrank();

            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiZeroAddress.selector,
                    "from"
                )
            );
            p.withdrawRemote(chainIds[j], poolIds[j], address(0x0), 0);

            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiZeroValue.selector,
                    "totalSupply"
                )
            );
            p.withdrawRemote(chainIds[j], poolIds[j], address(this), 100);
        }
    }

    function testWithdrawRemoteFailureCore() public {
        setupCredited(defaultMintAmountLd);
        {
            uint8 i = 0;
            uint8 j = 1;
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);

            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiExceed.selector,
                    "Pool._burnLP.amountLP",
                    100,
                    0
                )
            );
            p.withdrawRemote(chainIds[j], poolIds[j], alice, 100);
        }
    }

    function testWithdrawLocalFailurePrevious() public {
        uint8 i = 0;
        {
            uint8 j = 1;
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);

            // ready
            correctSetDefaultDelta(i, false, false);
            vm.prank(admin);
            p.registerPeerPool(chainIds[j], poolIds[j], 100);

            // Revert when a from address is zero.
            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiZeroAddress.selector,
                    "from"
                )
            );
            p.withdrawLocal(
                chainIds[j],
                poolIds[j],
                address(0x0),
                0,
                new bytes(20)
            );

            // Revert when a chainId is invalid.
            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiPeerPoolInfoNotFound.selector,
                    1,
                    9999
                )
            );
            p.withdrawLocal(1, 9999, address(this), 100, new bytes(20));

            // Revert when a poolId is invalid.
            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiPeerPoolInfoNotFound.selector,
                    9999,
                    1
                )
            );
            p.withdrawLocal(9999, 1, address(this), 100, new bytes(20));

            // Revert when a peerPool is not ready.
            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiPeerPoolIsNotReady.selector,
                    chainIds[j],
                    poolIds[j]
                )
            );
            p.withdrawLocal(
                chainIds[j],
                poolIds[j],
                address(this),
                100,
                new bytes(20)
            );
        }
    }

    function testWithdrawLocalFailWithZeroBalance() public {
        setupCredited(defaultMintAmountLd);
        bytes memory _to = new bytes(20);
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            uint8 j = (i + 1) % 3;
            {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        ITokiErrors.TokiZeroAddress.selector,
                        "from"
                    )
                );
                p.withdrawLocal(chainIds[j], poolIds[j], empty, GD(100), _to);
            }
        }
    }

    function testSendCreditFailurePrevious() public {
        uint8 i = 0;
        {
            uint8 j = 1;
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);

            // ready
            correctSetDefaultDelta(i, false, false);
            vm.prank(admin);
            p.registerPeerPool(chainIds[j], poolIds[j], 100);

            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiPeerPoolIsNotReady.selector,
                    chainIds[j],
                    poolIds[j]
                )
            );
            p.sendCredit(chainIds[j], poolIds[j]);
        }
    }

    function testSetTransferStopFailure() public {
        uint8 i = 0;
        Pool p = proxy(i);

        vm.expectRevert();
        vm.prank(address(0));
        p.setTransferStop(true);
    }

    function testRegisterPeerPoolFailure() public {
        uint8 i = 0;
        {
            uint8 j = 1;
            Pool p = proxy(i);

            // ready
            correctSetDefaultDelta(i, false, false);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessControl.AccessControlUnauthorizedAccount.selector,
                    address(this),
                    p.DEFAULT_ADMIN_ROLE()
                )
            );
            p.registerPeerPool(chainIds[j], poolIds[j], 100);

            vm.startPrank(admin);
            p.registerPeerPool(chainIds[j], poolIds[j], 100);

            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiPeerPoolIsRegistered.selector,
                    chainIds[j],
                    poolIds[j]
                )
            );
            p.registerPeerPool(chainIds[j], poolIds[j], 100);
            vm.stopPrank();
        }
    }

    function testActivatePeerPoolFailure() public {
        uint8 i = 0;
        {
            uint8 j = 1;
            Pool p = proxy(i);

            // ready
            correctSetDefaultDelta(i, false, false);
            vm.prank(admin);
            p.registerPeerPool(chainIds[j], poolIds[j], 100);

            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessControl.AccessControlUnauthorizedAccount.selector,
                    address(this),
                    p.DEFAULT_ADMIN_ROLE()
                )
            );
            p.activatePeerPool(chainIds[j], poolIds[j]);

            vm.startPrank(admin);
            p.activatePeerPool(chainIds[j], poolIds[j]);

            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiPeerPoolIsAlreadyActive.selector,
                    chainIds[j],
                    poolIds[j]
                )
            );
            p.activatePeerPool(chainIds[j], poolIds[j]);
            vm.stopPrank();
        }
    }

    function testSetDeltaParamFailure() public {
        uint8 i = 0;
        {
            Pool p = proxy(i);

            // ready
            correctSetDefaultDelta(i, false, false);

            vm.startPrank(admin);
            // passed
            p.setDeltaParam(
                true,
                2 * 1000, // 20%
                60,
                true, //default
                true //default
            );

            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiExceed.selector,
                    "swapDeltaBP",
                    2 * 10000,
                    10000
                )
            );

            p.setDeltaParam(
                true,
                2 * 10000, // 200%
                60,
                true, //default
                true //default
            );

            vm.expectRevert(
                abi.encodeWithSelector(
                    ITokiErrors.TokiExceed.selector,
                    "lpDeltaBP",
                    2 * 10000,
                    10000
                )
            );

            p.setDeltaParam(
                true,
                2 * 1000, // 20%
                2 * 10000, // 200%,
                true, //default
                true //default
            );

            vm.stopPrank();
        }
    }

    function testDrawFee() public {
        setupCredited(defaultMintAmountLd);
        uint8 j = 1;
        Pool p = proxy(0);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(ITokiErrors.TokiZeroAddress.selector, "to")
        );
        p.drawFee(address(0x0));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ITokiErrors.TokiNoFee.selector));
        p.drawFee(address(this));

        {
            address _to = address(this);
            ITransferPoolFeeCalculator.FeeInfo
                memory f = ITransferPoolFeeCalculator.FeeInfo({
                    amountGD: 998_930_000,
                    protocolFee: 970_000,
                    lpFee: 30_000,
                    eqFee: 30_000,
                    eqReward: 0,
                    balanceDecrease: 999_970_000
                });
            p.recv(chainIds[j], poolIds[j], _to, f, true);
        }

        address to = address(0x3);
        assertEq(ERC20(p.token()).balanceOf(to), 0, "before balance");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                p.DEFAULT_ADMIN_ROLE()
            )
        );
        p.drawFee(to);

        vm.prank(admin);
        vm.expectEmit();
        emit IPool.DrawFee(to, 97_000_000);
        p.drawFee(to);
        // GD -> LD
        assertEq(ERC20(p.token()).balanceOf(to), 97_000_000, "after balance");
    }

    function testDrawFeeFailWithZeroBalance() public {
        Pool p = proxy(0);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(ITokiErrors.TokiZeroAddress.selector, "to")
        );

        p.drawFee(empty);
    }

    function testGetPeerPoolFailure() public {
        uint8 i = 0;
        Pool p = proxy(i);

        uint8 j = 1;
        vm.expectRevert(
            abi.encodeWithSelector(ITokiErrors.TokiNoPeerPoolInfo.selector)
        );
        p.getPeerPoolInfo(chainIds[j], poolIds[j]);

        vm.prank(admin);
        p.registerPeerPool(chainIds[j], poolIds[j], 100);

        uint8 k = 2;
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiPeerPoolInfoNotFound.selector,
                chainIds[k],
                poolIds[k]
            )
        );
        p.getPeerPoolInfo(chainIds[k], poolIds[k]);
    }

    function testLimitPeerPool() public {
        uint256 weight = 1;

        Pool pool = _getPool(poolIds[0], chainIds[0]);
        vm.chainId(0);
        vm.startPrank(admin);

        // register peer pool up to the limit
        uint256 max = pool.MAX_PEERS();
        for (uint256 i = 0; i < max; i++) {
            pool.registerPeerPool(i, i, weight);
        }

        // failed in registering over limit
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiExceed.selector,
                "PeerPool",
                max + 1,
                max
            )
        );
        pool.registerPeerPool(max, max, weight);
    }

    // ====================== helper functions =============================
    function setupCredited(uint256 amountLd) public {
        setupMinted(amountLd);
        for (uint8 i = 0; i < poolIds.length; i++) {
            for (uint8 j = 0; j < poolIds.length; j++) {
                if (i == j) continue;
                Pool p = proxy(i);
                vm.chainId(chainIds[i]);
                IPool.CreditInfo memory c = p.sendCredit(
                    chainIds[j],
                    poolIds[j]
                );

                Pool op = proxy(j);
                vm.chainId(chainIds[j]);
                op.updateCredit(chainIds[i], poolIds[i], c);
            }
        }
    }

    function setupMinted(uint256 amountLd) public {
        uint256 _mintLD = amountLd;
        address _to = address(this);
        for (uint8 i = 0; i < poolIds.length; i++) {
            // before init mint, default full mode off
            correctSetDefaultDelta(i, false, false);
            for (uint8 j = 0; j < poolIds.length; j++) {
                if (i == j) continue;
                correctRegisterPeerPool(
                    chainIds[i],
                    poolIds[i],
                    chainIds[j],
                    poolIds[j],
                    100
                );
            }
            correctMint(chainIds[i], poolIds[i], _to, _mintLD);
            // after init mint, default full mode on
            correctSetDefaultDelta(i, true, true);
        }
    }

    function correctSetDefaultDelta(
        uint8 i,
        bool lpMode,
        bool swapMode
    ) public {
        Pool pool = proxy(i);
        vm.chainId(chainIds[i]);
        vm.prank(admin);
        pool.setDeltaParam(
            true,
            500, // 5%
            500, // 5%
            swapMode,
            lpMode
        );
    }

    function correctRegisterPeerPool(
        uint256 _myChainId,
        uint256 _myPoolId,
        uint256 _peerChainId,
        uint256 _peerPoolId,
        uint256 _weight
    ) public {
        Pool pool = _getPool(_myChainId, _myPoolId);
        vm.chainId(_myChainId);
        vm.startPrank(admin);
        pool.registerPeerPool(_peerChainId, _peerPoolId, _weight);
        pool.activatePeerPool(_peerChainId, _peerPoolId);
        vm.stopPrank();
    }

    function correctMint(
        uint256 _srcChainId,
        uint256 _srcPoolId,
        address _to,
        uint256 _amountLD
    ) public {
        Pool pool = _getPool(_srcChainId, _srcPoolId);
        vm.chainId(_srcChainId);
        pool.mint(_to, _amountLD);
        ERC20(pool.token()).transfer(address(pool), _amountLD);
    }

    function proxy(uint8 index) public view returns (Pool) {
        return Pool(address(erc1967Proxies[index]));
    }

    function _getPool(
        uint256 _srcChainId,
        uint256 _poolId
    ) internal view returns (Pool) {
        uint256 length = poolIds.length;
        for (uint8 i = 0; i < length; i++) {
            if (chainIds[i] == _srcChainId && poolIds[i] == _poolId) {
                return proxy(i);
            }
        }
        revert("pool not found");
    }
}
