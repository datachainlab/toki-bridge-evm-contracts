// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/VersionStringValidator.sol";

contract VersionStringValidatorTest is Test {
    VersionStringValidator public validator;

    function setUp() public {
        validator = new VersionStringValidator();
    }

    function testValidCases() public {
        (bool success1, uint256 value1) = validator.validateVersion("toki-123");
        assertTrue(success1);
        assertEq(value1, 123);

        (bool success2, uint256 value2) = validator.validateVersion("toki-001");
        assertTrue(success2);
        assertEq(value2, 1);
    }

    function testInvalidCases() public {
        (bool success1, ) = validator.validateVersion("test-123");
        assertFalse(success1);

        (bool success2, ) = validator.validateVersion("test-123");
        assertFalse(success2);

        (bool success3, ) = validator.validateVersion("toki-abc");
        assertFalse(success3);

        (bool success4, ) = validator.validateVersion("toki-a1");
        assertFalse(success4);

        (bool success5, ) = validator.validateVersion("toki1");
        assertFalse(success5);
    }
}
