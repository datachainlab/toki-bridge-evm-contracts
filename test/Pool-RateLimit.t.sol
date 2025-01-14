// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import "../src/Pool.sol";
import "../src/StaticFlowRateLimiter.sol";

import "../src/interfaces/IPool.sol";
import "../src/interfaces/IPoolRepository.sol";

import "../src/mocks/MockToken.sol";
import "../src/PoolRepository.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract MockUSD is MockToken {
    constructor(
        uint8 decimals,
        uint256 initialSupply
    ) MockToken("MockToken", "MOCK", decimals, initialSupply) {}
}

contract MockTransferPoolFeeCalculator is ITransferPoolFeeCalculator {
    uint256 public globalDecimalsConvert;

    constructor(uint256 _globalDecimalsConvert) {
        globalDecimalsConvert = _globalDecimalsConvert;
    }

    function calcFee(
        ITransferPoolFeeCalculator.SrcPoolInfo calldata /*_srcPool*/,
        IPool.PeerPoolInfo calldata /*_dstPool */,
        address /*_from */,
        uint256 _amountGD
    ) external pure returns (FeeInfo memory feeInfo) {
        feeInfo.lpFee = 0;
        feeInfo.eqFee = 0;
        feeInfo.eqReward = 0;
        feeInfo.amountGD =
            _amountGD -
            feeInfo.eqFee -
            feeInfo.protocolFee -
            feeInfo.lpFee;
    }

    function version() external pure returns (string memory) {
        return "mock";
    }

    function gd(uint256 _amount) internal view returns (uint256) {
        return _amount * globalDecimalsConvert;
    }
}

contract PoolRateLimitTest is Test {
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
    address public alice = address(0x01);
    address public bob = address(0x02);

    // for test contracts
    Pool[] public pools;
    ERC1967Proxy[] public erc1967Proxies;
    MockUSD[] public mockUSDs;
    PoolRepository public poolRepository;
    ERC1967Proxy public prProxy;

    // for test parameters
    uint256[] public chainIds = [1, 2, 111];
    uint256[] public poolIds = [1, 1, 1];
    uint8 public globalDecimals = 5;
    uint8 public localDecimals = 7;
    uint256 public globalDecimalsConvert = 10 ** uint256(globalDecimals);
    uint256 public localDecimalsConvert = 10 ** uint256(localDecimals);
    address public admin;

    uint256 public constant DEFAULT_WEIGHT = 100;
    uint256 public constant DEFAULT_MINT_AMOUNT = 1_000_000 * (10 ** 7);

    bytes4 public selectorExceedsLimit =
        bytes4(keccak256("ExceedsLimit(uint256,uint256)"));

    function setUp() public {
        admin = address(0x201);

        // setup pool repository
        {
            poolRepository = new PoolRepository();
            prProxy = new ERC1967Proxy(address(poolRepository), "");
        }

        for (uint8 i = 0; i < poolIds.length; i++) {
            vm.chainId(chainIds[i]);
            pools.push(new Pool(0, 0, ld(1000), 3));
            erc1967Proxies.push(new ERC1967Proxy(address(pools[i]), ""));

            // setup mock usd
            mockUSDs.push(
                new MockUSD(
                    localDecimals,
                    1_000_000_000 * globalDecimalsConvert
                )
            );
            mockUSDs[i].mint(
                address(this),
                1_000_000_000 * globalDecimalsConvert
            );
            mockUSDs[i].approve(
                address(erc1967Proxies[i]),
                1_000_000_000 * globalDecimalsConvert
            );

            // setup fee calculator
            MockTransferPoolFeeCalculator feeCalculator = new MockTransferPoolFeeCalculator(
                    globalDecimalsConvert
                );
            address feeCalculatorAddress = address(feeCalculator);

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
                    feeCalculatorAddress,
                    admin,
                    address(this), // actually router address, in other words `brdige`,
                    maxTotalDeposits
                )
            );
        }
    }

    // - recv() checks dstFlowRateLimiter
    function testRecvOverflowFail() public {
        setupCredited();
        address _to = address(this);
        uint256 length = poolIds.length;
        for (uint8 i = 0; i < length; i++) {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            uint8 j = (i + 1) % 3;

            uint256 amountGD = gd(1000); //pass dst rate limit
            ITransferPoolFeeCalculator.FeeInfo
                memory f = ITransferPoolFeeCalculator.FeeInfo(
                    amountGD,
                    0,
                    0,
                    0,
                    0,
                    0
                );

            p.recv(chainIds[j], poolIds[j], _to, f, true);
            assertEq(p.currentPeriodAmount(), ld(1000));

            (, bool isTransferred) = p.recv(
                chainIds[j],
                poolIds[j],
                _to,
                f,
                true
            );
            assertFalse(isTransferred);
        }
    }

    // - withdrawRemote() only burn
    function testWithdarwRemoteOverflowSuccess() public {
        setupCredited();
        address _to = address(this);
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            uint8 j = (i + 1) % 3;

            p.withdrawRemote(chainIds[j], poolIds[j], _to, gd(2000));
            assertEq(p.currentPeriodAmount(), ld(0));
        }
    }

    // - withdrawLocal() does not check flow limit
    function testWithdarwLocalOverflowSuccess() public {
        setupCredited();
        address _from = address(this);
        bytes memory _to = new bytes(20);
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);
            uint8 j = (i + 1) % 3;

            p.withdrawLocal(chainIds[j], poolIds[j], _from, gd(2000), _to);
            assertEq(p.currentPeriodAmount(), ld(0));
        }
    }

    // - withdrawCheck does not check flow limit
    function withdrawCheckOverflowSuccess() public {
        setupCredited();
        //address _from = address(this);
        //address _to = address(20);
        for (uint8 i = 0; i < poolIds.length; i++) {
            uint8 j = (i + 1) % 3;
            Pool p = proxy(j); //dst is this
            vm.chainId(chainIds[j]);

            p.withdrawCheck(chainIds[i], poolIds[i], gd(2000));
            assertEq(p.currentPeriodAmount(), ld(0));
        }
    }

    // - withdrawConfirm checks dst flow limit
    function testWithdrawConfirmOverflowFail() public {
        setupCredited();
        //address _from = address(this);
        address _to = address(20);
        for (uint8 i = 0; i < poolIds.length; i++) {
            Pool p = proxy(i); //proactor side
            vm.chainId(chainIds[i]);
            uint8 j = (i + 1) % 3;

            p.withdrawConfirm(
                chainIds[j],
                poolIds[j],
                _to,
                gd(1000),
                gd(1000),
                true
            );
            assertEq(p.currentPeriodAmount(), ld(1000));

            bool isTransferred = p.withdrawConfirm(
                chainIds[j],
                poolIds[j],
                _to,
                gd(1000),
                gd(1000),
                true
            );
            assertFalse(isTransferred);
        }
    }

    // - withdrawInstant() does not check flow limit
    function testWithdrawInstantOverflowSuccess() public {
        setupCredited();
        address _from = address(this);
        address _to = address(20);
        for (uint8 i = 0; i < poolIds.length; i++) {
            uint8 j = (i + 1) % 3;
            Pool p = proxy(i);
            vm.chainId(chainIds[i]);

            // extend deltaCredit
            p.transfer(chainIds[j], poolIds[j], _to, ld(3000), ld(0), false);

            p.withdrawInstant(_from, gd(2000), _to);
            assertEq(p.currentPeriodAmount(), ld(0));
        }
    }

    // ====================== helper functions =============================
    function setupCredited() public {
        setupMinted();
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

    function setupMinted() public {
        uint256 _mintLD = DEFAULT_MINT_AMOUNT;
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
        revert("no pool found");
    }

    // solhint-disable-next-line func-name-mixedcase
    function ld(uint256 _amount) internal view returns (uint256) {
        return _amount * localDecimalsConvert;
    }

    // solhint-disable-next-line func-name-mixedcase
    function gd(uint256 _amount) internal view returns (uint256) {
        return _amount * globalDecimalsConvert;
    }

    // solhint-disable-next-line func-name-mixedcase
    function ldToGd(uint256 _amountLD) internal view returns (uint256) {
        uint256 convertRate = 10 **
            (uint256(globalDecimals) - (uint256(localDecimals)));
        return _amountLD * convertRate;
    }
}
