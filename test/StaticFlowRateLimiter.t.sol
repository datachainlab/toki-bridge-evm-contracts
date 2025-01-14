// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../src/StaticFlowRateLimiter.sol";

contract MockStaticFlowRateLimiter is UUPSUpgradeable, StaticFlowRateLimiter {
    constructor(
        uint256 period,
        uint256 lockPeriod,
        uint256 limit,
        uint256 threshold
    ) StaticFlowRateLimiter(period, lockPeriod, limit, threshold) {}

    function initialize() public initializer {
        __StaticFlowRateLimiter_init(msg.sender);
    }

    // solhint-disable-next-line func-name-mixedcase
    function exposed_checkAndUpdateFlowRateLimit(
        uint256 amount
    ) public returns (bool) {
        return _checkAndUpdateFlowRateLimit(amount);
    }

    // solhint-disable-next-line func-name-mixedcase
    function exposed_cancelFlowRateLimit() public {
        _cancelFlowRateLimit();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override {}
}

contract StaticFlowRateLimiterTest is Test {
    MockStaticFlowRateLimiter public t;

    function setUp() public {
        address impl = address(new MockStaticFlowRateLimiter(10, 20, 100, 2));
        bytes memory data = abi.encodeCall(
            MockStaticFlowRateLimiter.initialize,
            ()
        );
        address proxy = address(new ERC1967Proxy(impl, data));
        t = MockStaticFlowRateLimiter(proxy);
    }

    function testSetup() public {
        assertEq(t.PERIOD(), 10);
        assertEq(t.LOCK_PERIOD(), 20);
        assertEq(t.LIMIT(), 100);
        assertEq(t.THRESHOLD(), 2);
        assertEq(t.currentPeriodEnd(), block.number + 10);
        assertEq(t.currentPeriodAmount(), 0);
    }

    function testResetFlowRateLimit() public {
        bool success = t.exposed_checkAndUpdateFlowRateLimit(50);
        assertEq(t.currentPeriodAmount(), 50);
        assertTrue(success);

        success = t.exposed_checkAndUpdateFlowRateLimit(51);
        assertEq(t.appliedLockPeriod(), true);
        assertFalse(success);

        t.resetFlowRateLimit();
        assertEq(t.currentPeriodEnd(), block.number + 10);
        assertEq(t.currentPeriodAmount(), 0);
        assertEq(t.appliedLockPeriod(), false);
    }

    function testResetFlowRateLimitRevertsWhenSenderIsNotAdmin() public {
        address notAdmin = makeAddr("notAdmin");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notAdmin,
                t.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(notAdmin);
        t.resetFlowRateLimit();
    }

    function testCheckAndUpdate() public {
        // currentPeriodAmount is updated, and the check passes.
        bool success = t.exposed_checkAndUpdateFlowRateLimit(50);
        assertEq(t.currentPeriodAmount(), 50);
        assertTrue(success);

        // Since it's below the threshold, currentPeriodAmount is not updated, but the check passes.
        success = t.exposed_checkAndUpdateFlowRateLimit(1);
        assertEq(t.currentPeriodAmount(), 50); //not updated because it's below threshold
        assertTrue(success);

        // Since it exceeds the limit, currentPeriodAmount is not updated, and the check does not pass.
        // The appliedLockPeriod is set to true, and the currentPeriodEnd is updated.
        uint256 currentPeriodEnd = t.currentPeriodEnd();
        success = t.exposed_checkAndUpdateFlowRateLimit(51);
        assertEq(t.currentPeriodAmount(), 50); // not updated because it exceeds limit
        assertEq(t.currentPeriodEnd(), currentPeriodEnd + 20);
        assertEq(t.appliedLockPeriod(), true);
        assertFalse(success);

        // lockPeriod is applied only once.
        success = t.exposed_checkAndUpdateFlowRateLimit(51);
        assertEq(t.currentPeriodEnd(), currentPeriodEnd + 20);
        assertEq(t.appliedLockPeriod(), true);
        assertFalse(success);

        vm.roll(t.currentPeriodEnd() + 10);

        // currentPeriodAmount is reset, and the check passes.
        success = t.exposed_checkAndUpdateFlowRateLimit(51);
        assertEq(t.currentPeriodAmount(), 51);
        assertEq(t.appliedLockPeriod(), false);
        assertTrue(success);
    }

    function testCancel() public {
        t.exposed_checkAndUpdateFlowRateLimit(50);
        assertEq(t.currentPeriodAmount(), 50);

        t.exposed_checkAndUpdateFlowRateLimit(50);
        assertEq(t.currentPeriodAmount(), 100);

        t.exposed_cancelFlowRateLimit();
        assertEq(t.currentPeriodAmount(), 50);
    }

    function testCancelWhenAmountIsLessThanThreshold() public {
        t.exposed_checkAndUpdateFlowRateLimit(50);
        assertEq(t.currentPeriodAmount(), 50);

        t.exposed_checkAndUpdateFlowRateLimit(1);
        assertEq(t.currentPeriodAmount(), 50);

        t.exposed_cancelFlowRateLimit();
        assertEq(t.currentPeriodAmount(), 50);
    }

    function testCancelWhenCheckFailed() public {
        t.exposed_checkAndUpdateFlowRateLimit(50);
        assertEq(t.currentPeriodAmount(), 50);

        bool ok = t.exposed_checkAndUpdateFlowRateLimit(51);
        assertEq(ok, false);
        assertEq(t.currentPeriodAmount(), 50);

        t.exposed_cancelFlowRateLimit();
        assertEq(t.currentPeriodAmount(), 50);
    }
}
