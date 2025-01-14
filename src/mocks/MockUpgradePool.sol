// SPDX-License-Identifier: BUSL-1.1
// solhint-disable-next-line one-contract-per-file
pragma solidity 0.8.28;

import "../Pool.sol";

contract MockUpgradePoolV1 is Pool {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable IMM;
    string public upgradeName;
    string public slot2;

    // for testing
    // keccak256(abi.encode(uint256(keccak256("toki.storage.Pool")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant PARENT_POOL_LOCATION =
        0x98b6721f87b10fba9510649effb5cccfd7d04ba1bf6c44593ef8229732a7ea00;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        uint256 imm_,
        uint256 period,
        uint256 lockPeriod,
        uint256 limit,
        uint256 threshold
    ) Pool(period, lockPeriod, limit, threshold) {
        IMM = imm_;
        slot2 = "";
    }

    // should be guarded in production
    function upgradeToV1(
        string calldata upgradeName_,
        uint256 newSwapDeltaBP_
    ) public {
        upgradeName = upgradeName_;
        PoolStorage storage $ = _getParentStorage();
        $._swapDeltaBP = newSwapDeltaBP_;
    }

    // for testing
    function getImplementation() public view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    // for testing
    function _getParentStorage() internal pure returns (PoolStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := PARENT_POOL_LOCATION
        }
    }
}

// solhint-disable-next-line contract-name-camelcase
contract MockUpgradePoolV1_2 is MockUpgradePoolV1 {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        uint256 imm_,
        uint256 period,
        uint256 lockPeriod,
        uint256 limit,
        uint256 threshold
    ) MockUpgradePoolV1(imm_, period, lockPeriod, limit, threshold) {}

    // should be guarded in production
    // solhint-disable-next-line func-name-mixedcase
    function upgradeToV1_2(
        string calldata upgradeName_,
        uint256 newSwapDeltaBP_
    ) public {
        upgradeName = upgradeName_;
        PoolStorage storage $ = _getParentStorage();
        $._swapDeltaBP = newSwapDeltaBP_;
    }
}

contract MockUpgradePoolV2 is Pool {
    string public upgradeName;
    address public slot2; // incompatible with V1;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        uint256 period,
        uint256 lockPeriod,
        uint256 limit,
        uint256 threshold
    ) Pool(period, lockPeriod, limit, threshold) {}

    // should be guarded in production
    function upgradeToV2(string calldata upgradeName_, address slot2_) public {
        upgradeName = upgradeName_;
        // Note about slither-disable:
        //   Zero address is ok because this test is for testing.
        // slither-disable-next-line missing-zero-check
        slot2 = slot2_;
    }

    // for testing
    function getImplementation() public view returns (address) {
        return ERC1967Utils.getImplementation();
    }
}
