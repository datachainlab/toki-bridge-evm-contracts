// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/Pool.sol";
import "../src/mocks/MockUpgradePool.sol";

contract UpgradePoolTest is Test {
    // define test fixtures
    struct FixturePool {
        uint256 poolId;
        string name;
        string symbol;
        uint8 globalDecimals;
        uint8 localDecimals;
        uint256 swapDeltaBP;
    }
    struct Fixture {
        FixturePool[] pools;
    }
    Fixture private fixture;

    // test impl
    address public _deployerAddress;
    address public _adminAddress;
    address public _dummyAddress;
    address[] public _impls;
    address[] public _proxies;
    uint256 public _maxTotalDeposits = 200 * 1e18;

    constructor() {
        fixture.pools.push(FixturePool(1, "Token1", "T1", 15, 18, 39));
        fixture.pools.push(FixturePool(2, "Token2", "T2", 15, 17, 39));
    }

    function setUp() public {
        _deployerAddress = address(0x101);
        _adminAddress = address(0x201);
        _dummyAddress = address(0x301);

        for (uint8 i = 0; i < fixture.pools.length; i++) {
            FixturePool storage fp = fixture.pools[i];

            vm.prank(_deployerAddress);

            address implAddress = address(
                new Pool(100, 200, 100_000_000_000, 100_000_000)
            );
            bytes memory initializeData = abi.encodeCall(
                Pool.initialize,
                (
                    Pool.InitializeParam(
                        fp.name,
                        fp.symbol,
                        fp.poolId,
                        _dummyAddress,
                        fp.globalDecimals,
                        fp.localDecimals,
                        _dummyAddress,
                        _adminAddress,
                        _adminAddress,
                        _maxTotalDeposits
                    )
                )
            );
            address proxyAddress = address(
                new ERC1967Proxy(implAddress, initializeData)
            );
            _impls.push(implAddress);
            _proxies.push(proxyAddress);

            vm.prank(_adminAddress);
            Pool proxy = Pool(proxyAddress);
            proxy.setDeltaParam(false, fp.swapDeltaBP, 1, false, false);
            // defined in ERC20
            assertEq(proxy.name(), fp.name, "name");
            assertEq(proxy.decimals(), fp.globalDecimals, "decimals");

            // defined in Pool
            assertEq(proxy.poolId(), fp.poolId, "poolId");
            assertEq(proxy.token(), _dummyAddress, "token");
            assertEq(proxy.swapDeltaBP(), fp.swapDeltaBP, "swapDeltaBP");
            assertEq(
                proxy.globalDecimals(),
                fp.globalDecimals,
                "globalDecimals"
            );
            assertEq(proxy.localDecimals(), fp.localDecimals, "localDecimals");

            // role
            assertTrue(
                proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), _adminAddress),
                "admin"
            );
            assertTrue(
                proxy.hasRole(proxy.DEFAULT_ROUTER_ROLE(), _adminAddress),
                "router"
            );
        }
    }

    function testSetupSuccess() public {}

    function testUpgradeFailUnauthorized() public {
        for (uint8 i = 0; i < _proxies.length; i++) {
            Pool oldPoolProxy = Pool(_proxies[i]);

            address newImpl = address(0);
            bytes memory data;

            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessControl.AccessControlUnauthorizedAccount.selector,
                    _deployerAddress,
                    Pool(_proxies[i]).DEFAULT_ADMIN_ROLE()
                )
            );
            vm.prank(_deployerAddress);
            oldPoolProxy.upgradeToAndCall(newImpl, data);
        }
    }

    function testUpgradeSuccess1() public {
        for (uint8 i = 0; i < _proxies.length; i++) {
            FixturePool storage fp = fixture.pools[i];

            Pool oldPoolProxy = Pool(_proxies[i]);

            // upgrade to v1
            uint256 imm = 13;
            string memory newUpgradeName = "testUpgradeSuccess";
            uint256 newSwapDeltaBP = oldPoolProxy.swapDeltaBP() + 1;

            address newImpl = address(new MockUpgradePoolV1(imm, 1, 1, 1, 1));
            bytes memory data = abi.encodeCall(
                MockUpgradePoolV1.upgradeToV1,
                (newUpgradeName, newSwapDeltaBP)
            );

            vm.prank(_adminAddress);
            vm.expectEmit(address(oldPoolProxy));
            emit IERC1967.Upgraded(newImpl);
            oldPoolProxy.upgradeToAndCall(newImpl, data);
            MockUpgradePoolV1 newPoolProxy = MockUpgradePoolV1(_proxies[i]);

            // impl
            assertEq(
                newImpl,
                newPoolProxy.getImplementation(),
                "new impl address"
            );
            assertNotEq(_impls[i], newImpl, "impl address should be changed");

            // new state
            assertEq(
                newPoolProxy.upgradeName(),
                newUpgradeName,
                "upgradeName should be set"
            );

            // states not changed
            /// defined in ERC20
            assertEq(
                newPoolProxy.name(),
                fp.name,
                "name should not be changed"
            );
            assertEq(
                newPoolProxy.decimals(),
                fp.globalDecimals,
                "decimals should not be changed"
            );
            /// defined in Pool
            assertEq(
                newPoolProxy.poolId(),
                fp.poolId,
                "poolId should not be changed"
            );
            assertEq(
                newPoolProxy.token(),
                _dummyAddress,
                "token should not be changed"
            );

            // role
            assertTrue(
                newPoolProxy.hasRole(
                    newPoolProxy.DEFAULT_ROUTER_ROLE(),
                    _adminAddress
                ),
                "router"
            );

            // states changed
            /// defined in Pool
            assertEq(
                newPoolProxy.swapDeltaBP(),
                newSwapDeltaBP,
                "swapDeltaBP should be changed"
            );
        }
    }

    function testUpgradeSuccessUpdateImmutable() public {
        for (uint8 i = 0; i < _proxies.length; i++) {
            FixturePool storage fp = fixture.pools[i];
            Pool v0PoolProxy = Pool(_proxies[i]);

            // upgrade to v1
            address v1Impl = address(new MockUpgradePoolV1(1, 1, 1, 1, 1));
            bytes memory v1Data = abi.encodeCall(
                MockUpgradePoolV1.upgradeToV1,
                ("v1", fp.swapDeltaBP)
            );
            vm.prank(_adminAddress);
            v0PoolProxy.upgradeToAndCall(v1Impl, v1Data);
            MockUpgradePoolV1 v1PoolProxy = MockUpgradePoolV1(
                address(v0PoolProxy)
            );
            assertEq(v1PoolProxy.upgradeName(), "v1", "upgradeName by v1");
            assertEq(v1PoolProxy.IMM(), 1, "IMM");

            // upgrade to v1.2
            address v12Impl = address(new MockUpgradePoolV1_2(12, 12, 1, 1, 1));
            bytes memory v12Data = abi.encodeCall(
                MockUpgradePoolV1_2.upgradeToV1_2,
                ("v1_2", fp.swapDeltaBP)
            );
            vm.prank(_adminAddress);
            v1PoolProxy.upgradeToAndCall(v12Impl, v12Data);
            MockUpgradePoolV1_2 v12PoolProxy = MockUpgradePoolV1_2(
                address(v1PoolProxy)
            );
            assertEq(v1PoolProxy.upgradeName(), "v1_2", "upgradeName by v1_2");
            assertEq(v12PoolProxy.IMM(), 12, "IMM by v1_2");
            assertEq(v1PoolProxy.IMM(), 12, "IMM by v1 should be newly set");
        }
    }

    function testUpgradeSuccessIncompatibleSlot() public {
        for (uint8 i = 0; i < _proxies.length; i++) {
            FixturePool storage fp = fixture.pools[i];
            Pool v0PoolProxy = Pool(_proxies[i]);

            // upgrade to v1
            address v1Impl = address(new MockUpgradePoolV1(1, 1, 1, 1, 1));
            bytes memory v1Data = abi.encodeCall(
                MockUpgradePoolV1.upgradeToV1,
                ("v1", fp.swapDeltaBP)
            );
            vm.prank(_adminAddress);
            v0PoolProxy.upgradeToAndCall(v1Impl, v1Data);
            MockUpgradePoolV1 v1PoolProxy = MockUpgradePoolV1(
                address(v0PoolProxy)
            );
            assertEq(
                v1PoolProxy.upgradeName(),
                "v1",
                "upgradeName by upgradeToV1"
            );
            assertEq(v1PoolProxy.IMM(), 1, "IMM");
            assertEq(v1PoolProxy.slot2(), "", "slot2");

            // upgrade to v2
            address v2Impl = address(new MockUpgradePoolV2(1, 1, 1, 1));
            address v2Slot = address(9999);
            bytes memory v2Data = abi.encodeCall(
                MockUpgradePoolV2.upgradeToV2,
                ("v2", v2Slot)
            );
            vm.prank(_adminAddress);
            v1PoolProxy.upgradeToAndCall(v2Impl, v2Data); // incompatible but succeeded in upgrading
            MockUpgradePoolV2 v2PoolProxy = MockUpgradePoolV2(
                address(v1PoolProxy)
            );
            assertEq(
                v2PoolProxy.upgradeName(),
                "v2",
                "upgradeName by upgradeToV2 via v2"
            );
            assertEq(
                v1PoolProxy.upgradeName(),
                "v2",
                "upgradeName by upgradeToV2 via v1"
            );
            assertEq(v2PoolProxy.slot2(), v2Slot, "slot2 by upgradeToV2");

            vm.expectRevert();
            v1PoolProxy.IMM(); // v2 has no IMM immutable

            // cause EvmError but cannot test
            // v1PoolProxy.slot2();
        }
    }
}
