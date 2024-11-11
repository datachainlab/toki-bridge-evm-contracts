// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "../src/mocks/PseudoToken.sol";

contract MultiMintInConstructor is Test {
    constructor(PseudoToken token, address to) {
        // msg.sender.code.length is zero when msg.sender is constructing contract
        token.mint(to, 100);
        token.mint(to, 100);
    }
}
contract Create2 {
    function deploy(bytes32 salt, PseudoToken token, address to) public {
        new MultiMintInConstructor{salt: salt}(token, to);
    }
    function calcAddress(
        bytes32 salt,
        PseudoToken token,
        address to
    ) public view returns (address) {
        bytes memory creationCode = type(MultiMintInConstructor).creationCode;
        bytes memory initCode = abi.encodePacked(
            creationCode,
            abi.encode(token, to)
        );
        bytes memory bytecode = abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(initCode)
        );
        address addr = address(uint160(uint(keccak256(bytecode))));
        return addr;
    }
}

contract PseudoTokenTest is Test {
    address public alice = address(0x01);
    address public bob = address(0x02);
    address public owner = address(0x99);

    uint8 public constant DECIMALS = 7;
    uint256 public constant INITIAL_SUPPLY = 7000;
    uint256 public constant MINT_CAP = 11000;
    PseudoToken public token;

    function setUp() public {
        vm.startPrank(owner, owner);

        PseudoToken impl = new PseudoToken(DECIMALS);
        bytes memory data = abi.encodeCall(
            PseudoToken.initialize,
            ("mock", "MOCK", MINT_CAP)
        );
        address proxy = address(new ERC1967Proxy(address(impl), data));
        token = PseudoToken(proxy);

        token.mint(owner, INITIAL_SUPPLY);
        vm.stopPrank();
    }

    function testSetup() public {
        assertEq(token.owner(), owner, "owner");
        assertEq(token.name(), "mock", "name");
        assertEq(token.symbol(), "MOCK", "symbol");
        assertEq(token.mintCap(), MINT_CAP, "mintCap");
        assertEq(token.decimals(), DECIMALS, "decimals");
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY, "initialSupply");
        assertEq(token.isUncapMinter(owner), true, "isUncapMinter(this)");
        assertEq(token.isUncapMinter(alice), false, "isUncapMinter(alice)");
    }

    function testSetMintCap() public {
        vm.prank(owner);
        token.setMintCap(MINT_CAP + 3939);
        assertEq(token.mintCap(), MINT_CAP + 3939, "setMintCap");
    }

    function testAddAndRemoveUncapMinter() public {
        vm.prank(owner);
        token.addUncapMinter(alice);
        assertEq(token.isUncapMinter(alice), true, "added");

        vm.prank(owner);
        token.removeUncapMinter(alice);
        assertEq(token.isUncapMinter(alice), false, "removed");
    }

    function testSetMintCapWhenSenderIsNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                address(bob)
            )
        );
        vm.prank(bob);
        token.setMintCap(MINT_CAP + 3939);
    }

    function testAddUncapMinterWhenSenderIsNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                address(bob)
            )
        );
        vm.prank(bob);
        token.addUncapMinter(alice);
    }

    function testRemoveUncapMinterWhenSenderIsNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                address(bob)
            )
        );
        vm.prank(bob);
        token.removeUncapMinter(alice);
    }

    function testMintByUncapMinter() public {
        assertEq(token.isUncapMinter(owner), true);
        uint256 supply0 = token.totalSupply();
        uint256 balance0 = token.balanceOf(alice);

        vm.prank(owner, owner);
        token.mint(alice, MINT_CAP + 1);
        assertEq(token.totalSupply(), supply0 + MINT_CAP + 1, "totalSupply");
        assertEq(token.balanceOf(alice), balance0 + MINT_CAP + 1, "balance");
    }

    function testMintByCapMinter() public {
        assertEq(token.isUncapMinter(alice), false, "isUncapMinter");
        uint256 balance0 = token.balanceOf(alice);

        vm.prank(alice, alice);
        token.mint(alice, MINT_CAP + 1);
        assertEq(token.balanceOf(alice), balance0 + MINT_CAP, "balance");
    }

    function testMintAndGrantUncapMinter() public {
        vm.prank(owner);
        token.addUncapMinter(alice);
        assertEq(token.isUncapMinter(alice), true, "added");

        uint256 balance0 = token.balanceOf(alice);
        vm.prank(alice, alice);
        token.mint(alice, MINT_CAP + 1);
        assertEq(token.balanceOf(alice), balance0 + MINT_CAP + 1);

        uint256 balance1 = token.balanceOf(alice);
        vm.prank(owner);
        token.removeUncapMinter(alice);
        assertEq(token.isUncapMinter(alice), false, "removed");
        vm.prank(alice, alice);
        token.mint(alice, MINT_CAP + 1);
        assertEq(token.balanceOf(alice), balance1 + MINT_CAP);
    }

    function testBurn() public {
        uint256 supply0 = token.totalSupply();
        uint256 balance0 = token.balanceOf(owner);

        vm.prank(owner);
        token.burn(owner, 1000);
        assertEq(token.totalSupply(), supply0 - 1000, "totalSuppply");
        assertEq(token.balanceOf(owner), balance0 - 1000, "balance");
    }

    function testBurnRevertsWhenSenderIsNotBurner() public {
        vm.prank(owner, owner);
        token.mint(alice, 3000);
        uint256 balance0 = token.balanceOf(alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                address(alice)
            )
        );
        vm.prank(alice);
        token.burn(alice, 2000);
        assertEq(token.balanceOf(alice), balance0, "balance");
    }

    function testMintRevertsWhenCalledByContract() public {
        vm.prank(address(this), alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiContractNotAllowed.selector,
                "msg.sender",
                address(this)
            )
        );
        token.mint(alice, 100);

        // In case of msg.sender == tx.origin and msg.sender is contract. This is not occurred but test it.
        vm.prank(address(this), address(this));
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiContractNotAllowed.selector,
                "msg.sender",
                address(this)
            )
        );
        token.mint(alice, 100);
    }

    function testMintRevertsWhenCalledByConstructor() public {
        bytes32 salt = bytes32(uint256(39));

        Create2 c2 = new Create2();
        address addr = c2.calcAddress(salt, token, alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokiErrors.TokiContractNotAllowed.selector,
                "msg.sender",
                addr
            )
        );
        c2.deploy(salt, token, alice);
    }
}
