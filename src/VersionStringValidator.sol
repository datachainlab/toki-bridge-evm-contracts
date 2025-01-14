// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

contract VersionStringValidator {
    bytes32 public constant PREFIX_HASH = keccak256("toki-");
    uint256 public constant PREFIX_LENGTH = 5; // "toki-"

    function validateVersion(
        string memory input
    ) public pure returns (bool, uint256) {
        bytes memory inputBytes = bytes(input);

        // at least one digit is required
        if (inputBytes.length <= PREFIX_LENGTH) {
            return (false, 0);
        }

        bytes memory prefix = new bytes(PREFIX_LENGTH);
        for (uint256 i = 0; i < PREFIX_LENGTH; i++) {
            prefix[i] = inputBytes[i];
        }

        if (keccak256(prefix) != PREFIX_HASH) {
            return (false, 0);
        }

        uint256 result = 0;
        for (uint256 i = PREFIX_LENGTH; i < inputBytes.length; i++) {
            bytes1 char = inputBytes[i];
            if (!_isDigit(char)) {
                return (false, 0);
            }
            result = result * 10 + uint8(char) - uint8(bytes1("0"));
        }

        return (true, result);
    }

    function _isDigit(bytes1 b) internal pure returns (bool) {
        return b >= bytes1("0") && b <= bytes1("9");
    }

    function _stringToUint(
        string memory str
    ) internal pure returns (bool success, uint256 result) {
        bytes memory b = bytes(str);
        if (b.length == 0) return (false, 0);

        result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            if (!_isDigit(b[i])) {
                return (false, 0);
            }
            result = result * 10 + uint8(b[i]) - uint8(bytes1("0"));
        }
        return (true, result);
    }
}
