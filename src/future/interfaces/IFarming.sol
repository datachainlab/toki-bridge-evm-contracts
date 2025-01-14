// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IFarming {
    function rewardRate(address farmingToken) external view returns (uint256);
}
