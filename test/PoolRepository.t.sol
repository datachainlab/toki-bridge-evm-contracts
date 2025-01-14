// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/PoolRepository.sol";
import "../src/interfaces/IPoolRepository.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PoolRepositoryTest is Test {
    ERC1967Proxy public erc1967Proxy;
    PoolRepository public poolRepository;

    function setUp() public {
        poolRepository = new PoolRepository();
        erc1967Proxy = new ERC1967Proxy(address(poolRepository), "");
        proxy().initialize();
    }

    function testSetPool() public {
        proxy().grantRole(proxy().POOL_SETTER(), address(this));
        vm.expectEmit(true, true, false, true);
        emit IPoolRepository.SetPool(0, address(0x1));
        proxy().setPool(0, address(0x1));
        assertEq(address(proxy().getPool(0)), address(0x1));
        assertEq(proxy().length(), 1);

        vm.expectEmit(true, true, false, true);
        emit IPoolRepository.SetPool(1, address(0x2));
        proxy().setPool(1, address(0x2));
        assertEq(address(proxy().getPool(1)), address(0x2));
        assertEq(proxy().length(), 2);

        vm.expectEmit(true, true, false, true);
        emit IPoolRepository.SetPool(1, address(0x3));
        proxy().setPool(1, address(0x3));
        assertEq(address(proxy().getPool(1)), address(0x3));
        assertEq(proxy().length(), 2);

        vm.expectEmit(true, true, false, true);
        emit IPoolRepository.SetPool(1, address(0x0));
        proxy().setPool(1, address(0x0));
        assertEq(proxy().length(), 1);
    }

    function testSetPoolRevertsWhenPoolAlreadyExists() public {
        proxy().grantRole(proxy().POOL_SETTER(), address(this));
        proxy().setPool(1, address(0x2));

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiSamePool.selector,
                1,
                address(0x2)
            )
        );
        proxy().setPool(1, address(0x2));
    }

    function testSetPoolRevertsWhenSenderIsNotSetter() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(0x01),
                proxy().POOL_SETTER()
            )
        );
        vm.prank(address(0x01));
        proxy().setPool(0, address(0x2));
    }

    function testGetPoolRevertsWhenPoolDoesNotExist() public {
        vm.expectRevert(
            abi.encodeWithSelector(ITokiErrors.TokiNoPool.selector, 1)
        );
        address(proxy().getPool(1));
    }

    function proxy() public view returns (PoolRepository) {
        return PoolRepository(address(erc1967Proxy));
    }
}
