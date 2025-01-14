// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/Bridge.sol";
import "../src/interfaces/IBridge.sol";
import "../src/mocks/MockUpgradeBridge.sol";

interface IUUPSUpgradeable {
    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external;
}

contract UpgradeBridgeTest is Test {
    address public _deployerAddress;
    address public _adminAddress;
    address public _unauthorizedAddress;

    ERC1967Proxy public proxy;

    uint256 public constant APP_VERSION = 1;
    string public constant PORT = "toki";

    address public constant IBC_HANDLER = address(0x01);
    address public constant POOL_REPOSITORY = address(0x02);
    address public constant ESCROW = address(0x03);
    address public constant TOKEN_PRICE_ORACLE = address(0x04);
    address public constant FEE_OWNER = address(0x05);
    address public constant RELAYER_FEE_CALCULATOR = address(0x06);

    bytes32 public bridgeDefaultAdminRole;

    function setUp() public {
        _deployerAddress = address(this);
        _adminAddress = address(0x101);
        _unauthorizedAddress = address(0x102);

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

        proxy = new ERC1967Proxy(address(b), initializeData);
        // direct call is ok because DEFAULT_ADMIN_ROLE is constant
        bridgeDefaultAdminRole = b.DEFAULT_ADMIN_ROLE();

        IBridge bridge = IBridge(address(proxy));
        bridge.grantRole(bridgeDefaultAdminRole, _adminAddress);
        bridge.revokeRole(bridgeDefaultAdminRole, _deployerAddress);
    }

    function testSetupSuccess() public {}

    function testUpgradeFailUnauthorized() public {
        address newImpl = address(0x1111);
        bytes memory data;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _deployerAddress,
                bridgeDefaultAdminRole
            )
        );
        vm.prank(_deployerAddress);
        IUUPSUpgradeable(address(proxy)).upgradeToAndCall(newImpl, data);
    }

    function testUpgradeSuccess() public {
        // In this test, we use same implementation of BridgeFallback.
        BridgeFallback bf = new BridgeFallback(APP_VERSION, PORT);
        BridgeChannelUpgradeFallback cuf = new BridgeChannelUpgradeFallback(
            APP_VERSION,
            PORT
        );
        address newImpl = address(new MockUpgradeBridge(APP_VERSION, PORT));
        bytes memory data = abi.encodeCall(
            MockUpgradeBridge.upgrade,
            (address(bf), address(cuf))
        );

        vm.prank(_adminAddress);
        vm.expectEmit(address(proxy));
        emit IERC1967.Upgraded(newImpl);
        IUUPSUpgradeable(address(proxy)).upgradeToAndCall(newImpl, data);

        // impl
        assertEq(
            newImpl,
            MockUpgradeBridge(payable(address(proxy))).getImplementation(),
            "new impl address"
        );

        IBridge upgraded = IBridge(address(proxy));

        // new state
        assertEq(
            upgraded.defaultFallback(),
            address(bf),
            "defaultFallback should be updated"
        );

        assertEq(
            upgraded.channelUpgradeFallback(),
            address(cuf),
            "channelUpgradeFallback should be updated"
        );

        // states not changed
        IBridge bridge = IBridge(address(proxy));
        assertEq(
            bridge.ibcAddress(),
            IBC_HANDLER,
            "ibcHandler should not be changed"
        );

        // role
        assertTrue(
            bridge.hasRole(bridgeDefaultAdminRole, _adminAddress),
            "admin role should not be changed"
        );
    }
}
