// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

library LargeBytesGenerator {
    function generateLargeBytes(
        uint256 size
    ) internal pure returns (bytes memory) {
        bytes memory data = new bytes(size);
        for (uint256 i = 0; i < size; i++) {
            data[i] = bytes1(uint8(i % 256));
        }
        return data;
    }
}
