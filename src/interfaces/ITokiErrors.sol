// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

interface ITokiErrors {
    error TokiZeroAddress(string message);
    error TokiZeroAmount(string message);
    error TokiZeroValue(string message);

    // user error
    error TokiInsufficientAmount(string name, uint256 value, uint256 needed);
    // pool does not have enough liquidity
    error TokiInsufficientPoolLiquidity(uint256 value, uint256 needed);
    error TokiExceed(string name, uint256 value, uint256 limit);
    error TokiExceedAdd(
        string name,
        uint256 current,
        uint256 add,
        uint256 limit
    );

    // only used in PseudoToken, which is just for Testnet
    error TokiContractNotAllowed(string name, address addr);

    error TokiCannotCloseChannel();
    error TokiCannotTimeoutPacket();

    error TokiRequireOrderedChannel();
    error TokiDstOuterGasShouldBeZero();

    error TokiInvalidPacketType(uint8);
    error TokiInvalidRetryType(uint8);
    error TokiInvalidRecipientBytes();
    error TokiNoRevertReceive();
    error TokiRetryExpired(uint256 expiryBlock);
    error TokiInvalidAppVersion(uint256 expected, uint256 actual);
    error TokiNotEnoughNativeFee(uint256 value, uint256 limit);
    error TokiFailToRefund();

    error TokiNoFee();
    error TokiInvalidBalanceDeficitFeeZone();
    error TokiInvalidSafeZoneRange(uint256 min, uint256 max);
    error TokiDepeg(uint256 poolId);
    error TokiUnregisteredChainId(string channel);
    error TokiUnregisteredPoolId(uint256 poolId);

    error TokiSamePool(uint256 poolId, address pool);
    error TokiNoPool(uint256 poolId);
    error TokiPoolRecvIsFailed(uint256 poolId);
    error TokiPoolWithdrawConfirmIsFailed(uint256 poolId);
    error TokiPriceIsNotPositive(int256 value);
    error TokiPriceIsExpired(uint256 updatedAt);

    error TokiDstChainIdNotAccepted(uint256 dstChainId);

    error TokiTransferIsStop();
    error TokiTransferIsFailed(address token, address to, uint256 value);
    error TokiNativeTransferIsFailed(address to, uint256 value);
    error TokiPeerPoolIsNotReady(uint256 peerChainId, uint256 peerPoolId);
    error TokiSlippageTooHigh(
        uint256 amountGD,
        uint256 eqReward,
        uint256 eqFee,
        uint256 minAmountGD
    );
    error TokiPeerPoolIsRegistered(uint256 chainId, uint256 poolId);
    error TokiPeerPoolIsAlreadyActive(uint256 chainId, uint256 poolId);
    error TokiNoPeerPoolInfo();
    error TokiPeerPoolInfoNotFound(uint256 chainId, uint256 poolId);

    error TokiFlowRateLimitExceed(uint256 current, uint256 add, uint256 limit);

    error TokiFallbackUnauthorized(address caller);

    // used in mocks
    error TokiMock(string message);

    // channel upgrade
    error TokiInvalidProposedVersion(string version);
    error TokiChannelNotFound(string portId, string channelId);
}
