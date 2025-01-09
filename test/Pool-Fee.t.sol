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

import {PoolTestDecimals} from "./Pool.t.sol";

contract MockUSD is MockToken {
    constructor(
        uint8 decimals,
        uint256 initialSupply
    ) MockToken("MockToken", "MOCK", decimals, initialSupply) {}
}

contract MockTransferPoolFeeCalculatorWithFee is ITransferPoolFeeCalculator {
    uint256 public eqFeeBps;
    uint256 public lpFeeBps;

    function setEqFeeBps(uint256 _eqFeeBps) external {
        eqFeeBps = _eqFeeBps;
    }

    function setLpFeeBps(uint256 _lpFeeBps) external {
        lpFeeBps = _lpFeeBps;
    }

    function calcFee(
        SrcPoolInfo memory /* calldata srcPoolInfo */,
        IPool.PeerPoolInfo calldata,
        address,
        uint256 amountGD
    ) external view returns (FeeInfo memory) {
        return
            FeeInfo({
                // this mock always returns the input amountGD, which is different from the actual fee calculation
                amountGD: amountGD,
                // extremely high setting, however this should not affect slippage
                protocolFee: amountGD / 2,
                lpFee: (amountGD * lpFeeBps) / 10000,
                eqFee: (amountGD * eqFeeBps) / 10000,
                eqReward: 0,
                lastKnownBalance: 0
            });
    }

    function version() external pure returns (string memory) {
        return "mock with high eq fee";
    }
}

contract PoolTestWithFeeCommon is PoolTestDecimals, Test {
    // assign address
    address public alice = address(0x01);
    address public admin = address(0x10);

    Pool public pool;
    MockUSD public token;
    ERC1967Proxy public proxy;
    MockTransferPoolFeeCalculatorWithFee public feeCalculator;

    uint256 public constant CHAIN_ID = 1;
    uint256 public constant PEER_CHAIN_ID = 2;
    uint256 public constant POOL_ID = 1;
    uint256 public constant PEER_POOL_ID = 1;
    uint256 public constant MAX_SLIPPAGE_BPS = 120; // 1.2%

    function setUpCommon() public {
        setUpDecimals(18, 6);
        vm.chainId(CHAIN_ID);
        pool = new Pool(100, 200, 100_000_000_000, 100_000_000);
        token = new MockUSD(6, 1_000_000);

        // calcFee() always returns with eq fee
        feeCalculator = new MockTransferPoolFeeCalculatorWithFee();

        pool.initialize(
            Pool.InitializeParam(
                "LP token",
                "LP",
                POOL_ID,
                address(token),
                globalDecimals,
                localDecimals,
                address(feeCalculator),
                admin,
                address(0x03),
                200 * 1e18
            )
        );
        vm.startPrank(admin);
        pool.registerPeerPool(PEER_CHAIN_ID, PEER_POOL_ID, 1);
        pool.activatePeerPool(PEER_CHAIN_ID, PEER_POOL_ID);
        // for transfer()
        pool.grantRole(pool.DEFAULT_ROUTER_ROLE(), address(this));
        vm.stopPrank();
    }

    function _calcMinAmountLD(
        uint256 amount,
        uint256 slippageBps
    ) internal pure returns (uint256) {
        return (amount * (10000 - slippageBps)) / 10000;
    }
}

contract PoolTestAboutEqFee is PoolTestWithFeeCommon {
    function setUp() public {
        setUpCommon();

        // update peerPoolInfo
        IPool.CreditInfo memory creditInfo = IPool.CreditInfo({
            credits: 1000 * (10 ** globalDecimals),
            targetBalance: 10000 * (10 ** globalDecimals)
        });
        pool.updateCredit(PEER_CHAIN_ID, PEER_POOL_ID, creditInfo);
    }

    function testTransferRevertsWhenHighEqFee() public {
        feeCalculator.setEqFeeBps(200); // 2%
        uint256 amountLD = 100 * (10 ** localDecimals);
        uint256 minAmountLD = _calcMinAmountLD(amountLD, MAX_SLIPPAGE_BPS);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiSlippageTooHigh.selector,
                amountLD / 10 ** (localDecimals - globalDecimals),
                0, // eqReward
                2000000, // eqFee
                minAmountLD / 10 ** (localDecimals - globalDecimals)
            )
        );
        pool.transfer(
            PEER_CHAIN_ID,
            PEER_POOL_ID,
            alice,
            amountLD,
            minAmountLD,
            true
        );
    }

    function testTransferPassWithLowEqFee() public {
        feeCalculator.setEqFeeBps(100); // 1%
        uint256 amountLD = 100 * (10 ** localDecimals);
        uint256 minAmountLD = _calcMinAmountLD(amountLD, MAX_SLIPPAGE_BPS);

        ITransferPoolFeeCalculator.FeeInfo memory feeInfo = pool.transfer(
            PEER_CHAIN_ID,
            PEER_POOL_ID,
            alice,
            amountLD,
            minAmountLD,
            true
        );

        // protocol fee and lp fee does not affect slippage
        assertLt(
            amountLD - GDToLD(feeInfo.protocolFee + feeInfo.lpFee),
            minAmountLD
        );
    }

    function testCalcFeeParameters() public {
        feeCalculator.setEqFeeBps(100); // 1%
        uint256 amountLD = 100 * (10 ** localDecimals);
        uint256 minAmountLD = _calcMinAmountLD(amountLD, MAX_SLIPPAGE_BPS);

        token.mint(address(pool), LD(3939));

        vm.expectCall(
            address(feeCalculator),
            abi.encodeWithSelector(
                feeCalculator.calcFee.selector,
                ITransferPoolFeeCalculator.SrcPoolInfo({
                    addr: address(pool),
                    id: pool.poolId(),
                    globalDecimals: globalDecimals,
                    balance: GD(3939),
                    totalLiquidity: pool.totalLiquidity(),
                    eqFeePool: pool.eqFeePool()
                })
            ),
            1
        );
        pool.transfer(
            PEER_CHAIN_ID,
            PEER_POOL_ID,
            alice,
            amountLD,
            minAmountLD,
            true
        );
    }
}

contract PoolTestAboutLastKnownBalance is PoolTestWithFeeCommon {
    function setUp() public {
        setUpCommon();

        // update peerPoolInfo
        IPool.CreditInfo memory creditInfo = IPool.CreditInfo({
            credits: 100 * (10 ** globalDecimals),
            targetBalance: 1000 * (10 ** globalDecimals)
        });
        pool.updateCredit(PEER_CHAIN_ID, PEER_POOL_ID, creditInfo);
    }

    function testTransferRevertsWhenLastKnownBalanceIsGreaterThanBalance()
        public
    {
        uint256 lpFeeBps = 100; // 1%
        feeCalculator.setLpFeeBps(lpFeeBps);
        uint256 amountLD = 1000 * (10 ** localDecimals);
        uint256 minAmountLD = _calcMinAmountLD(amountLD, MAX_SLIPPAGE_BPS);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiInsufficientPoolLiquidity.selector,
                100 * (10 ** globalDecimals), // credits were added by updateCredit()
                LDToGD((amountLD * (10000 - lpFeeBps)) / 10000)
            )
        );
        pool.transfer(
            PEER_CHAIN_ID,
            PEER_POOL_ID,
            alice,
            amountLD,
            minAmountLD,
            true
        );
    }

    function testTransferPassWithEnoughBalance() public {
        uint256 lpFeeBps = 100; // 1%
        feeCalculator.setLpFeeBps(lpFeeBps);
        uint256 amountLD = 50 * (10 ** localDecimals);
        uint256 minAmountLD = _calcMinAmountLD(amountLD, MAX_SLIPPAGE_BPS);

        ITransferPoolFeeCalculator.FeeInfo memory feeInfo = pool.transfer(
            PEER_CHAIN_ID,
            PEER_POOL_ID,
            alice,
            amountLD,
            minAmountLD,
            true
        );

        // pool updates feeInfo.lastKnownBalance though calcFee() returns 0 for lastKnownBalance
        assertEq(
            feeInfo.lastKnownBalance,
            LDToGD((amountLD * (10000 - lpFeeBps)) / 10000)
        );
    }
}
