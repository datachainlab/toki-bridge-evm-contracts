// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../interfaces/IFarming.sol";

contract MockFarming is IFarming {
    mapping(address => uint256) public tokenToRewardRate;

    function setRewardRate(address _farmingToken, uint256 rate) external {
        tokenToRewardRate[_farmingToken] = rate;
    }

    function rewardRate(
        address _farmingToken
    ) external view override returns (uint256) {
        return tokenToRewardRate[_farmingToken];
    }
}
