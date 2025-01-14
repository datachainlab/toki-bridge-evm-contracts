// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../interfaces/ITokiErrors.sol";
import "../interfaces/IPool.sol";
import "../interfaces/ITransferPoolFeeCalculator.sol";

// solhint-disable-next-line max-states-count
contract MockPool is ITokiErrors, IPool {
    struct CallMint {
        address to;
        uint256 amountLD;
    }

    struct CallTransfer {
        uint256 dstChainId;
        uint256 dstPoolId;
        address from;
        uint256 amountLD;
        uint256 minAmountLD;
        bool newLiquidity;
    }

    struct CallRecv {
        uint256 srcChainId;
        uint256 srcPoolId;
        address to;
        ITransferPoolFeeCalculator.FeeInfo feeInfo;
    }

    struct CallWithdrawRemote {
        uint256 dstChainId;
        uint256 dstPoolId;
        address from;
        uint256 amount;
    }

    struct CallWithdrawLocal {
        uint256 dstChainId;
        uint256 dstPoolId;
        address from;
        uint256 amount;
        bytes to;
    }

    struct CallWithdrawCheck {
        uint256 srcChainId;
        uint256 srcPoolId;
        uint256 amountGD;
    }

    struct CallWithdrawConfirm {
        uint256 srcChainId;
        uint256 srcPoolId;
        address to;
        uint256 amountGD;
        uint256 amountToMintGD;
    }

    struct CallSendCredit {
        uint256 dstChainId;
        uint256 dstPoolId;
    }

    struct CallUpdateCredit {
        uint256 chainId;
        uint256 srcPoolId;
        CreditInfo creditInfo;
    }

    struct CallWithdrawInstant {
        address from;
        uint256 amountLP;
        address to;
    }

    struct CallSetTransferStop {
        bool transferStop;
    }

    struct CallRegisterPeerPool {
        uint256 peerChainId;
        uint256 peerPoolId;
        uint256 weight;
    }

    struct CallActivatePeerPool {
        uint256 peerChainId;
        uint256 peerPoolId;
    }

    struct CallSetPeerPoolWeight {
        uint256 peerChainId;
        uint256 peerPoolId;
        uint256 weight;
    }

    struct CallSetDeltaParam {
        bool batched;
        uint256 swapDeltaBP;
        uint256 lpDeltaBP;
        bool defaultSwapMode;
        bool defaultLPMode;
    }

    struct CallDrawFee {
        address to;
    }

    struct CallCallDelta {
        bool fullMode;
    }

    CallMint public callMint;
    CallTransfer public callTransfer;
    CallRecv public callRecv;
    CallWithdrawRemote public callWithdrawRemote;
    CallWithdrawLocal public callWithdrawLocal;
    CallWithdrawCheck public callWithdrawCheck;
    CallWithdrawConfirm public callWithdrawConfirm;
    CallSendCredit public callSendCredit;
    CallUpdateCredit public callUpdateCredit;
    CallWithdrawInstant public callWithdrawInstant;
    CallSetTransferStop public callSetTransferStop;
    CallRegisterPeerPool public callRegisterPeerPool;
    CallActivatePeerPool public callActivatePeerPool;
    CallSetPeerPoolWeight public callSetPeerPoolWeight;
    CallSetDeltaParam public callSetDeltaParam;
    CallDrawFee public callDrawFee;
    CallCallDelta public callCallDelta;
    bool public callResetFlowRateLimit; // resetFlowRateLimit has no parameters

    uint256 public immutable POOL_ID;
    address public immutable TOKEN;

    // for test, force fail any receive functions
    bool public forceFail;

    constructor(uint256 poolId, address token_) {
        if (token_ == address(0)) {
            revert TokiZeroAddress("token");
        }
        TOKEN = token_;
        POOL_ID = poolId;
    }

    function mint(address to, uint256 amountLD) external returns (uint256) {
        callMint = CallMint(to, amountLD);
        return amountLD;
    }

    function transfer(
        uint256 dstChainId,
        uint256 dstPoolId,
        address from,
        uint256 amountLD,
        uint256 minAmountLD,
        bool newLiquidity
    ) external returns (ITransferPoolFeeCalculator.FeeInfo memory) {
        callTransfer = CallTransfer(
            dstChainId,
            dstPoolId,
            from,
            amountLD,
            minAmountLD,
            newLiquidity
        );
        return ITransferPoolFeeCalculator.FeeInfo(amountLD, 0, 0, 0, 0, 0);
    }

    function recv(
        uint256 srcChainId,
        uint256 srcPoolId,
        address to,
        ITransferPoolFeeCalculator.FeeInfo memory feeInfo,
        bool /* updateDelta */
    ) external returns (uint256 amountLD, bool isTransferred) {
        if (!forceFail) {
            isTransferred = true;
        }
        callRecv = CallRecv(srcChainId, srcPoolId, to, feeInfo);
        amountLD = feeInfo.amountGD / this.convertRate();
    }

    function withdrawRemote(
        uint256 dstChainId,
        uint256 dstPoolId,
        address from,
        uint256 amount
    ) external {
        callWithdrawRemote = CallWithdrawRemote(
            dstChainId,
            dstPoolId,
            from,
            amount
        );
    }

    function withdrawLocal(
        uint256 dstChainId,
        uint256 dstPoolId,
        address from,
        uint256 amount,
        bytes calldata to
    ) external returns (uint256 amountGD) {
        callWithdrawLocal = CallWithdrawLocal(
            dstChainId,
            dstPoolId,
            from,
            amount,
            to
        );
        amountGD = amount;
    }

    function withdrawCheck(
        uint256 srcChainId,
        uint256 srcPoolId,
        uint256 amountGD
    ) external returns (uint256 amountSwap, uint256 amountMint) {
        if (forceFail) {
            revert TokiMock("MockPool: forced fail");
        }
        callWithdrawCheck = CallWithdrawCheck(srcChainId, srcPoolId, amountGD);
        amountSwap = amountGD;
        amountMint = amountGD;
    }

    function withdrawConfirm(
        uint256 srcChainId,
        uint256 srcPoolId,
        address to,
        uint256 amountGD,
        uint256 amountToMintGD,
        bool /* updateDelta */
    ) external returns (bool isTransferred) {
        if (!forceFail) {
            isTransferred = true;
        }
        callWithdrawConfirm = CallWithdrawConfirm(
            srcChainId,
            srcPoolId,
            to,
            amountGD,
            amountToMintGD
        );
    }

    function sendCredit(
        uint256 dstChainId,
        uint256 dstPoolId
    ) external returns (CreditInfo memory c) {
        callSendCredit = CallSendCredit(dstChainId, dstPoolId);
        c = CreditInfo(0, 0);
    }

    function updateCredit(
        uint256 chainId,
        uint256 srcPoolId,
        CreditInfo memory creditInfo
    ) external {
        callUpdateCredit = CallUpdateCredit(chainId, srcPoolId, creditInfo);
    }

    function withdrawInstant(
        address from,
        uint256 amountLP,
        address to
    ) external returns (uint256 amountGD) {
        callWithdrawInstant = CallWithdrawInstant(from, amountLP, to);
        amountGD = amountLP;
    }

    function handleRecvFailure(
        uint256 peerChainId,
        uint256 peerPoolId,
        address to,
        ITransferPoolFeeCalculator.FeeInfo memory feeInfo
    ) external {}

    /**
     * @dev Receive delta info ( and re-mint lp token ) to keep the delta consistent.
     */
    function handleWithdrawConfirmFailure(
        uint256 peerChainId,
        uint256 peerPoolId,
        address to,
        uint256 amountGD,
        uint256 amountToMintGD
    ) external {}

    function setTransferStop(bool transferStop) external {
        callSetTransferStop = CallSetTransferStop(transferStop);
    }

    function registerPeerPool(
        uint256 peerChainId,
        uint256 peerPoolId,
        uint256 weight
    ) external {
        callRegisterPeerPool = CallRegisterPeerPool(
            peerChainId,
            peerPoolId,
            weight
        );
    }

    function activatePeerPool(
        uint256 peerChainId,
        uint256 peerPoolId
    ) external {
        callActivatePeerPool = CallActivatePeerPool(peerChainId, peerPoolId);
    }

    function setPeerPoolWeight(
        uint256 peerChainId,
        uint256 peerPoolId,
        uint256 weight
    ) external {
        callSetPeerPoolWeight = CallSetPeerPoolWeight(
            peerChainId,
            peerPoolId,
            weight
        );
    }

    function setDeltaParam(
        bool batched,
        uint256 swapDeltaBP,
        uint256 lpDeltaBP,
        bool defaultSwapMode,
        bool defaultLPMode
    ) external {
        callSetDeltaParam = CallSetDeltaParam(
            batched,
            swapDeltaBP,
            lpDeltaBP,
            defaultSwapMode,
            defaultLPMode
        );
    }

    function drawFee(address to) external {
        callDrawFee = CallDrawFee(to);
    }

    function callDelta(bool fullMode) external {
        callCallDelta = CallCallDelta(fullMode);
    }

    // ======================= for test ====================
    function setForceFail(bool forceFail_) external {
        forceFail = forceFail_;
    }

    // ============== for helper ===================
    function token() external view returns (address) {
        return TOKEN;
    }

    function totalLiquidity() external pure returns (uint256) {
        return 1;
    }

    function convertRate() external pure returns (uint256) {
        return 1;
    }

    function globalDecimals() external pure returns (uint8) {
        return 1;
    }

    function localDecimals() external pure returns (uint8) {
        return 1;
    }

    function poolBalance() external pure returns (uint256) {
        return 1;
    }

    function eqFeePool() external pure returns (uint256) {
        return 1;
    }

    function getPeerPoolInfo(
        uint256 /*_peerChainId */,
        uint256 /*_peerPoolId */
    ) external pure returns (PeerPoolInfo memory) {
        return PeerPoolInfo(0, 0, 0, 0, 0, 0, 0, false);
    }

    function calcFee(
        uint256 /*_peerChainId */,
        uint256 /*_peerPoolId */,
        address /*_from */,
        uint256 amountLD
    ) external pure returns (ITransferPoolFeeCalculator.FeeInfo memory) {
        return ITransferPoolFeeCalculator.FeeInfo(amountLD, 0, 0, 0, 0, 0);
    }

    // solhint-disable-next-line func-name-mixedcase
    function LPToLD(uint256 amountLP) external pure returns (uint256) {
        return amountLP;
    }

    function resetFlowRateLimit() public {
        callResetFlowRateLimit = true;
    }

    // ============== IStaticFlowRateLimiter ===================
    function currentPeriodEnd() public view returns (uint256) {
        return 0;
    }

    function currentPeriodAmount() public view returns (uint256) {
        return 0;
    }

    function appliedLockPeriod() public view returns (bool) {
        return false;
    }
}
