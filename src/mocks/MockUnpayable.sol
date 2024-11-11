// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../interfaces/ITokiErrors.sol";

// Note about disable slither:
//   Withdrawal function is omitted because this is mock contract.
// slither-disable-start locked-ether
contract MockUnpayable is ITokiErrors {
    bool public fallbackFail;

    event MockUnpayableReceived(string typ, uint256 value);

    // solhint-disable-next-line no-complex-fallback, payable-fallback
    fallback() external {
        if (fallbackFail) {
            revert TokiMock("fallback force fail");
        }
        emit MockUnpayableReceived("fallback", 0);
    }

    function setFallbackFail(bool b) external {
        fallbackFail = b;
    }
}

// slither-disable-end locked-ether
