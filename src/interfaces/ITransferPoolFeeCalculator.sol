// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../interfaces/IPool.sol";

/**
 * @title ITransferPoolFeeCalculator
 * @dev Interface for calculating fees for transferring between pools.
 */
interface ITransferPoolFeeCalculator {
    /**
     * @dev Struct for the source pool.
     * @param addr The address of the source pool.
     * @param id The ID of the source pool.
     * @param globalDecimals The global decimals used by the source pool.
     * @param balance The current balance of the source pool in GD (global decimals) units.
     * @param totalLiquidity The total liquidity of the source pool in GD units.
     * @param eqFeePool The equilibrium fee pool of the source pool in GD units.
     */
    struct SrcPoolInfo {
        address addr;
        uint256 id;
        uint8 globalDecimals;
        uint256 balance;
        uint256 totalLiquidity;
        uint256 eqFeePool;
    }

    /**
     * @dev Struct for the calculated fees.
     * @param amountGD The transferring token amount converted to global decimals, from which eqFee and protocolFee are subtracted.
     * @param protocolFee The protocol fee.
     * @param lpFee The liquidity provider fee.
     * @param eqFee The equilibrium fee.
     * @param eqReward The equilibrium reward.
     * @param balanceDecrease Balance reduction in source pool that will update destination pool's last known balance
     */
    struct FeeInfo {
        uint256 amountGD;
        uint256 protocolFee;
        uint256 lpFee;
        uint256 eqFee;
        uint256 eqReward;
        uint256 balanceDecrease;
    }

    /**
     * @dev Calculates the fees for transferring between pools.
     * @param srcPoolInfo The struct of source pool.
     * @param dstPoolInfo The struct of destination pool.
     * @param from The address that transfers the token.
     * @param amountGD The amount of the token in GD units.
     * GD stands for Global Decimals. For more details, please refer to IPool.
     * @return FeeInfo The calculated fees.
     */
    function calcFee(
        SrcPoolInfo calldata srcPoolInfo,
        IPool.PeerPoolInfo calldata dstPoolInfo,
        address from,
        uint256 amountGD
    ) external view returns (FeeInfo memory);

    /**
     * @dev Returns the version of the fee calculator.
     * @return The version string.
     */
    function version() external pure returns (string memory);
}
