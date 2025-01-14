// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../interfaces/IDecimalConvertible.sol";

interface ITokenEscrow is IDecimalConvertible {
    function transferToken(
        uint256 dstChainId,
        address from,
        uint256 amountLD
    ) external returns (uint256 amountGD);

    function receiveToken(address to, uint256 amountGD) external;

    function token() external view returns (address);
}
