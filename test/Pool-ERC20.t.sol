// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/Pool.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/mocks/MockToken.sol";

contract PoolHarness is Pool {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        uint256 period,
        uint256 lockPeriod,
        uint256 limit,
        uint256 threshold
    ) Pool(period, lockPeriod, limit, threshold) {}

    // solhint-disable-next-line func-name-mixedcase
    function exposed_safeTransferWithRevert(
        address token_,
        address to,
        uint256 value
    ) public {
        _safeTransferWithRevert(token_, to, value);
    }

    // solhint-disable-next-line func-name-mixedcase
    function exposed_safeTransfer(
        address token_,
        address to,
        uint256 value
    ) public returns (bool) {
        return _safeTransfer(token_, to, value);
    }
}

contract MockTransfer {
    bool public success;
    bool public canRevert;

    function transfer(
        address /* _to */,
        uint256 /* _value */
    ) public returns (bool) {
        if (canRevert) {
            require(success, "canRevert");
        }
        return success;
    }

    function setSuccess(bool success_) public {
        success = success_;
    }

    function setCanRevert(bool canRevert_) public {
        canRevert = canRevert_;
    }
}

contract MockTransferWithoutReturn {
    bool public success;

    function transfer(address /* _to */, uint256 /* _value */) public {
        require(success, "canRevert");
    }

    function setSuccess(bool success_) public {
        success = success_;
    }
}

contract PoolERC20Test is Test {
    PoolHarness public t;

    function setUp() public {
        PoolHarness poolImpl = new PoolHarness(
            100,
            200,
            100_000_000_000,
            100_000_000
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(poolImpl), "");

        t = PoolHarness(address(proxy));
    }

    function testSafeTransfer() public {
        MockTransfer mock = new MockTransfer();
        mock.setSuccess(true);
        mock.setCanRevert(true);
        bool result = t.exposed_safeTransfer(address(mock), address(this), 100);
        assertTrue(result);

        mock.setSuccess(false);
        mock.setCanRevert(true);
        result = t.exposed_safeTransfer(address(mock), address(this), 100);
        assertFalse(result);

        mock.setSuccess(false);
        mock.setCanRevert(false);
        result = t.exposed_safeTransfer(address(mock), address(this), 100);
        assertFalse(result);

        MockTransferWithoutReturn mockWithoutReturn = new MockTransferWithoutReturn();
        mockWithoutReturn.setSuccess(true);
        result = t.exposed_safeTransfer(
            address(mockWithoutReturn),
            address(this),
            100
        );
        assertTrue(result);

        mockWithoutReturn.setSuccess(false);
        result = t.exposed_safeTransfer(
            address(mockWithoutReturn),
            address(this),
            100
        );
        assertFalse(result);
    }

    function testSafeTransferWithRevert() public {
        MockTransfer mock = new MockTransfer();
        mock.setSuccess(true);
        mock.setCanRevert(true);
        t.exposed_safeTransferWithRevert(address(mock), address(this), 100);

        mock.setSuccess(false);
        mock.setCanRevert(true);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiTransferIsFailed.selector,
                address(mock),
                address(this),
                100
            )
        );
        t.exposed_safeTransferWithRevert(address(mock), address(this), 100);

        mock.setSuccess(false);
        mock.setCanRevert(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiTransferIsFailed.selector,
                address(mock),
                address(this),
                100
            )
        );
        t.exposed_safeTransferWithRevert(address(mock), address(this), 100);

        MockTransferWithoutReturn mockWithoutReturn = new MockTransferWithoutReturn();
        mockWithoutReturn.setSuccess(true);
        t.exposed_safeTransferWithRevert(
            address(mockWithoutReturn),
            address(this),
            100
        );

        mockWithoutReturn.setSuccess(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiTransferIsFailed.selector,
                address(mockWithoutReturn),
                address(this),
                100
            )
        );
        t.exposed_safeTransferWithRevert(
            address(mockWithoutReturn),
            address(this),
            100
        );
    }
}
