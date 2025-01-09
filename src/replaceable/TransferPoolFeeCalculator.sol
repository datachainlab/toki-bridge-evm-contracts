// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/ITokiErrors.sol";
import "../interfaces/ITransferPoolFeeCalculator.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IStableTokenPriceOracle.sol";

contract TransferPoolFeeCalculator is
    ITokiErrors,
    ITransferPoolFeeCalculator,
    AccessControl
{
    enum BalanceDeficitZone {
        NoFeeZone,
        SafeZone,
        DangerZone
    }

    uint256 public constant DENOMINATOR = 1e18;
    uint256 public constant EQ_REWARD_THRESHOLD = 6 * 1e14;

    uint256 public constant DELTA_1 = 6000 * 1e14;
    uint256 public constant DELTA_2 = 500 * 1e14;
    uint256 public constant LAMBDA_1 = 40 * 1e14;
    uint256 public constant LAMBDA_2 = 9954 * 1e14;

    uint256 public constant PROTOCOL_SUBSIDY = 3 * 1e13;

    uint256 public constant PROTOCOL_FEE = 9 * 1e14;
    uint256 public constant LP_FEE_WITH_EQ_REWARD = 34 * 1e12;
    uint256 public constant LP_FEE = 1 * 1e14;

    uint8 public constant PRICE_ORACLE_DECIMALS = 8;
    uint8 public constant TOKEN_DECIMALS = 18;
    uint256 public constant MINIMUM_TRANSACTION_FEE_USD_D8 = 25 * 1e6; // 0.25 USD
    uint256 public constant MINIMUM_TRANSACTION_FEE_ETH_D18 = 0.0001e18; // 0.0001 ETH

    mapping(address => bool) public whitelist;
    mapping(uint256 => uint256) public poolIdToTokenId;

    IStableTokenPriceOracle public stableTokenPriceOracle;

    /* ========== EVENTS ========== */
    event SetWhitelist(address from, bool whiteListed);

    event SetStableTokenPriceOracle(
        IStableTokenPriceOracle stableTokenPriceOracle
    );

    event SetTokenId(uint256 poolId, uint256 tokenId);

    modifier notDepeg(uint256 srcPoolId, uint256 dstPoolId) {
        if (srcPoolId != dstPoolId) {
            IStableTokenPriceOracle.PriceDeviationStatus stat = stableTokenPriceOracle
                    .getCurrentPriceDeviationStatus(srcPoolId);
            if (stat == IStableTokenPriceOracle.PriceDeviationStatus.Depeg) {
                revert TokiDepeg(srcPoolId);
            }
        }
        _;
    }

    constructor(IStableTokenPriceOracle stableTokenPriceOracle_) {
        stableTokenPriceOracle = stableTokenPriceOracle_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ---------- ONLY OWNER ----------
    function setWhitelist(
        address from,
        bool whiteListed
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelist[from] = whiteListed;
        emit SetWhitelist(from, whiteListed);
    }

    function setStableTokenPriceOracle(
        IStableTokenPriceOracle stableTokenPriceOracle_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stableTokenPriceOracle = stableTokenPriceOracle_;
        emit SetStableTokenPriceOracle(stableTokenPriceOracle);
    }

    function setTokenId(
        uint256 poolId,
        uint256 tokenId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        poolIdToTokenId[poolId] = tokenId;
        emit SetTokenId(poolId, tokenId);
    }

    // ---------- PUBLIC FUNCTIONS ----------
    function calcFee(
        SrcPoolInfo calldata srcPoolInfo,
        IPool.PeerPoolInfo calldata dstPoolInfo,
        address from,
        uint256 amountGD
    )
        external
        view
        notDepeg(srcPoolInfo.id, dstPoolInfo.id)
        returns (FeeInfo memory feeInfo)
    {
        if (dstPoolInfo.balance < amountGD) {
            revert TokiInsufficientPoolLiquidity(dstPoolInfo.balance, amountGD);
        }

        uint256 dstPoolAfterBalance = dstPoolInfo.balance - amountGD;

        bool whitelisted = whitelist[from];

        BalanceDeficitZone dstPoolBalanceDeficitZone;
        {
            (uint256 safeZoneMax, uint256 safeZoneMin) = eqFeeSafeZoneRange(
                dstPoolInfo.targetBalance
            );
            dstPoolBalanceDeficitZone = balanceDeficitZone(
                safeZoneMax,
                safeZoneMin,
                dstPoolAfterBalance
            );
        }

        feeInfo.eqFee = getEqFee(
            whitelisted,
            dstPoolBalanceDeficitZone,
            dstPoolAfterBalance,
            dstPoolInfo.targetBalance,
            amountGD
        );

        feeInfo.protocolFee = getProtocolFee(
            whitelisted,
            dstPoolBalanceDeficitZone,
            srcPoolInfo.id,
            dstPoolInfo.id,
            amountGD
        );

        feeInfo.eqReward = getEqReward(
            whitelisted,
            srcPoolInfo.balance,
            srcPoolInfo.totalLiquidity,
            srcPoolInfo.eqFeePool,
            amountGD,
            feeInfo.protocolFee
        );

        bool hasEqReward = feeInfo.eqReward > 0;
        feeInfo.lpFee = getLpFee(whitelisted, hasEqReward, amountGD);

        // Ensure the total Transaction Fee (Protocol Fee + LP Fee) is not less than the minimum
        uint256 minTransactionFee = getMinimumTransactionFee(
            whitelisted,
            srcPoolInfo.id,
            srcPoolInfo.globalDecimals
        );

        uint256 transactionFee = feeInfo.protocolFee + feeInfo.lpFee;
        if (transactionFee < minTransactionFee) {
            uint256 adjustment = minTransactionFee - transactionFee;
            feeInfo.protocolFee += adjustment;
        }

        if (amountGD <= feeInfo.eqFee + feeInfo.protocolFee + feeInfo.lpFee) {
            feeInfo.amountGD = 0;
        } else {
            feeInfo.amountGD =
                amountGD -
                feeInfo.eqFee -
                feeInfo.protocolFee -
                feeInfo.lpFee;
        }
    }

    function version() external pure override returns (string memory) {
        return "1.0.0";
    }

    function getProtocolFee(
        bool whitelisted,
        BalanceDeficitZone dstBalanceDeficitZone,
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountGD
    ) public view returns (uint256 protocolFee) {
        if (whitelisted) {
            return 0;
        }

        protocolFee = _mulBps(amountGD, PROTOCOL_FEE);
        protocolFee += getDriftProtocolFee(srcPoolId, dstPoolId, amountGD);

        if (dstBalanceDeficitZone == BalanceDeficitZone.NoFeeZone) {
            protocolFee -= _mulBps(amountGD, PROTOCOL_SUBSIDY);
        }

        return protocolFee;
    }

    function getDriftProtocolFee(
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountGD
    ) public view returns (uint256) {
        if (srcPoolId == dstPoolId) {
            return 0;
        }
        IStableTokenPriceOracle.PriceDeviationStatus srcStatus = stableTokenPriceOracle
                .getCurrentPriceDeviationStatus(srcPoolId);
        if (srcStatus == IStableTokenPriceOracle.PriceDeviationStatus.Normal) {
            return 0;
        }
        (uint256 srcPrice, uint8 srcDecimals) = stableTokenPriceOracle
            .getCurrentPriceAndDecimals(srcPoolId);
        (uint256 dstPrice, uint8 dstDecimals) = stableTokenPriceOracle
            .getCurrentPriceAndDecimals(dstPoolId);

        // Make each price is under same decimals.
        if (srcDecimals < dstDecimals) {
            srcPrice = srcPrice * (10 ** (dstDecimals - srcDecimals));
        } else {
            dstPrice = dstPrice * (10 ** (srcDecimals - dstDecimals));
        }

        if (srcPrice >= dstPrice) {
            return 0;
        }
        return (amountGD * (dstPrice - srcPrice)) / dstPrice;
    }

    // todo: by the time TOKI Token is released, it is necessary to be able to pass USD/ETH pair into TransferPoolFeeCalculator in e2e if there are multiple instances.
    function getMinimumTransactionFee(
        bool whitelisted,
        uint256 poolId,
        uint8 tokenDecimals
    ) public view returns (uint256) {
        if (whitelisted) {
            return 0;
        }

        uint256 tokenId = poolIdToTokenId[poolId];
        if (tokenId == 0) {
            // 0(=default) means USD stable token.
            // minimum fee in USD is equal to min fee in token.
            // (MIN * 10**-4) * (1 * 10**decimal)
            if (PRICE_ORACLE_DECIMALS <= tokenDecimals) {
                return
                    MINIMUM_TRANSACTION_FEE_USD_D8 *
                    (10 ** (tokenDecimals - PRICE_ORACLE_DECIMALS));
            } else {
                return
                    MINIMUM_TRANSACTION_FEE_USD_D8 /
                    (10 ** (PRICE_ORACLE_DECIMALS - tokenDecimals));
            }
        } else {
            if (TOKEN_DECIMALS < tokenDecimals) {
                return
                    MINIMUM_TRANSACTION_FEE_ETH_D18 *
                    (10 ** (tokenDecimals - TOKEN_DECIMALS));
            } else {
                return
                    MINIMUM_TRANSACTION_FEE_ETH_D18 /
                    (10 ** (TOKEN_DECIMALS - tokenDecimals));
            }
        }
    }

    function getEqReward(
        bool whitelisted,
        uint256 srcPoolBalance,
        uint256 srcTotalLiquidity,
        uint256 eqFeePool,
        uint256 amountGD,
        uint256 protocolFee
    ) public pure returns (uint256 eqReward) {
        if (srcTotalLiquidity <= srcPoolBalance) {
            return 0;
        }

        uint256 deficit = srcTotalLiquidity - srcPoolBalance;

        uint256 rateBps = (eqFeePool * DENOMINATOR) / deficit;

        if (rateBps <= EQ_REWARD_THRESHOLD && !whitelisted) {
            return 0;
        }

        eqReward = _mulBps(amountGD, rateBps);
        if (eqReward > protocolFee) {
            eqReward = protocolFee;
        }
        if (eqReward > eqFeePool) {
            eqReward = eqFeePool;
        }
    }

    function getEqFee(
        bool whitelisted,
        BalanceDeficitZone dstBalanceDeficitZone,
        uint256 dstPoolAfterBalance,
        uint256 dstPoolTargetBalance,
        uint256 amountGD
    ) public pure returns (uint256) {
        if (whitelisted) {
            return 0;
        }
        if (dstBalanceDeficitZone == BalanceDeficitZone.NoFeeZone) {
            return 0;
        } else if (dstBalanceDeficitZone == BalanceDeficitZone.SafeZone) {
            uint256 bps = safeZoneEqFeeBps(
                dstPoolAfterBalance,
                dstPoolTargetBalance
            );
            return _mulBps(amountGD, bps);
        } else if (dstBalanceDeficitZone == BalanceDeficitZone.DangerZone) {
            uint256 bps = dangerZoneEqFeeBps(
                dstPoolAfterBalance,
                dstPoolTargetBalance
            );
            return _mulBps(amountGD, bps);
        } else {
            revert TokiInvalidBalanceDeficitFeeZone();
        }
    }

    function eqFeeSafeZoneRange(
        uint256 dstPoolTargetBalance
    ) public pure returns (uint256 safeZoneMax, uint256 safeZoneMin) {
        safeZoneMax = _mulBps(dstPoolTargetBalance, DELTA_1);
        safeZoneMin = _mulBps(dstPoolTargetBalance, DELTA_2);
    }

    function balanceDeficitZone(
        uint256 safeZoneMax,
        uint256 safeZoneMin,
        uint256 dstPoolAfterBalance
    ) public pure returns (BalanceDeficitZone) {
        if (safeZoneMax < safeZoneMin) {
            revert TokiInvalidSafeZoneRange(safeZoneMin, safeZoneMax);
        }
        if (dstPoolAfterBalance >= safeZoneMax) {
            return BalanceDeficitZone.NoFeeZone;
        }
        if (dstPoolAfterBalance >= safeZoneMin) {
            return BalanceDeficitZone.SafeZone;
        }
        return BalanceDeficitZone.DangerZone;
    }

    function safeZoneEqFeeBps(
        uint256 dstPoolAfterBalance,
        uint256 dstPoolTargetBalance
    ) public pure returns (uint256) {
        return
            (LAMBDA_1 *
                (DELTA_1 *
                    dstPoolTargetBalance -
                    dstPoolAfterBalance *
                    DENOMINATOR)) /
            ((DELTA_1 - DELTA_2) * dstPoolTargetBalance);
    }

    function dangerZoneEqFeeBps(
        uint256 dstPoolAfterBalance,
        uint256 dstPoolTargetBalance
    ) public pure returns (uint256) {
        uint256 tmp = DELTA_2 * dstPoolTargetBalance;
        return
            LAMBDA_1 +
            (LAMBDA_2 * (tmp - dstPoolAfterBalance * DENOMINATOR)) /
            tmp;
    }

    function getLpFee(
        bool whitelisted,
        bool hasEqReward,
        uint256 amountGD
    ) public pure returns (uint256) {
        if (whitelisted) {
            return 0;
        }
        uint256 lpFeeBps = hasEqReward ? LP_FEE_WITH_EQ_REWARD : LP_FEE;
        return _mulBps(amountGD, lpFeeBps);
    }

    function _mulBps(
        uint256 amount,
        uint256 bps
    ) internal pure returns (uint256) {
        return (amount * bps) / DENOMINATOR;
    }
}
