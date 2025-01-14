// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../interfaces/ITokiErrors.sol";

// Note about disable slither:
//   Withdrawal function is omitted because this is mock contract.
// slither-disable-start locked-ether
contract MockPayable is ITokiErrors {
    bool public fallbackFail;
    bool public receiveFail;

    event MockPayableReceived(string typ, uint256 value);

    // solhint-disable-next-line no-complex-fallback
    receive() external payable {
        if (receiveFail) {
            revert TokiMock("receive force fail");
        }
        emit MockPayableReceived("receive", msg.value);
    }

    // solhint-disable-next-line no-complex-fallback
    fallback() external payable {
        if (fallbackFail) {
            revert TokiMock("fallback force fail");
        }
        emit MockPayableReceived("fallback", msg.value);
    }

    function setFallbackFail(bool b) external {
        fallbackFail = b;
    }

    function setReceiveFail(bool b) external {
        receiveFail = b;
    }
}

// slither-disable-end locked-ether
