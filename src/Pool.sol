// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardTransientUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import "./DecimalConvertibleUpgradeable.sol";
import "./interfaces/ITokiErrors.sol";
import "./interfaces/IPool.sol";
import "./interfaces/ITransferPoolFeeCalculator.sol";
import "./StaticFlowRateLimiter.sol";

contract Pool is
    ITokiErrors,
    IPool,
    ERC20PermitUpgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    DecimalConvertibleUpgradeable,
    ReentrancyGuardTransientUpgradeable,
    StaticFlowRateLimiter
{
    using SafeERC20 for IERC20;

    struct InitializeParam {
        string name;
        string symbol;
        uint256 poolId;
        address token;
        uint8 globalDecimals;
        uint8 localDecimals;
        address feeCalculator;
        address admin;
        address router;
        uint256 maxTotalDeposits; // The maximum deposits that each pool will hold in LD-unit
    }

    /// @custom:storage-location erc7201:toki.storage.Pool
    struct PoolStorage {
        address _feeCalculator;
        // Delta algorithm parameters
        PeerPoolInfo[] _peerPoolInfos; // list of connected chains pool.
        // seek for peerPools by chainId => poolId => index
        mapping(uint256 => mapping(uint256 => uint256)) _peerPoolInfoIndexSeek;
        uint256 _totalLiquidity; // assets deposited.
        // total weight for pools. When calculate proportion of weight, peerPoolInfos[i].weight / totalWeight.
        uint256 _totalWeight;
        uint256 _deltaCredit; // Needs optimization
        bool _batched; // flag indicates whether or not batch processing is performed.
        bool _defaultSwapMode; // flag indicates whether or not the default mode for swap
        bool _defaultLPMode; // flag indicates whether or not the default mode for lp
        uint256 _feeBalance; // fee balance in Global Decimal format.
        uint256 _eqFeePool; // pool rewards in Global Decimal format.
        uint256 _swapDeltaBP; // activate the delta of the swap at the basis point of the pool credit.
        uint256 _lpDeltaBP; // basis points of pooled credit to allow for delta in liquidity events
        uint256 _poolId; // shared id between chains to represent same pool.
        address _token; // the local token for the pool
        // Tip about decimals
        // - amountLP: liquidity provider token (that means this contract) in global decimals units.
        // - amountGD: decimals of shared asset token. eg) 6 decimals, lcm(USDT_eth.decimals(), USDT_bsc.decimals(), ...)
        // - amountLD: decimals of local asset token. eg) 18 decimals(USDT_eth)

        bool _transferStop; // flag to stop transfer in extreme cases
        uint256 _maxTotalDeposits; // The maximum deposits that each pool will hold by LD-unit
    }

    // The maximum number of peer pool.
    // This limitation prevents _deltaSourceUpdate from exceeding the block gas limit.
    // The amount of gas for _deltaSourceUpdate increases by about 20k as peer increases.
    uint256 public constant MAX_PEERS = 100;

    // keccak256(abi.encode(uint256(keccak256("toki.storage.Pool")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant POOL_LOCATION =
        0x98b6721f87b10fba9510649effb5cccfd7d04ba1bf6c44593ef8229732a7ea00;

    bytes32 public constant DEFAULT_ROUTER_ROLE =
        keccak256("DEFAULT_ROUTER_ROLE");

    uint256 public constant BPS_DENOMINATOR = 10000; // basic point denominator

    event SetDstFlowRateLimiter(address dstFlowRateLimiter);

    modifier checkMaxTotalDeposits(uint256 amountAssetLD) {
        PoolStorage storage $ = _getPoolStorage();
        uint256 totalDepositsLD = _GDToLD($._totalLiquidity) + amountAssetLD;
        // Check that the total liquidity does not exceed the maximum total deposits
        if (totalDepositsLD > $._maxTotalDeposits) {
            revert TokiExceed(
                "maxTotalDeposits",
                totalDepositsLD,
                $._maxTotalDeposits
            );
        }

        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        uint256 period,
        uint256 lockPeriod,
        uint256 limit,
        uint256 threshold
    ) StaticFlowRateLimiter(period, lockPeriod, limit, threshold) {}

    // ========================== public functions ===============================
    function initialize(InitializeParam calldata p) public initializer {
        __ERC20_init(p.name, p.symbol);
        __ERC20Permit_init(p.name);
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __DecimalConvertible_init(p.globalDecimals, p.localDecimals);
        __ReentrancyGuardTransient_init();
        __StaticFlowRateLimiter_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, p.admin);
        _grantRole(DEFAULT_ROUTER_ROLE, p.router);

        PoolStorage storage $ = _getPoolStorage();
        $._poolId = p.poolId;

        if (p.token == address(0x0)) {
            revert TokiZeroAddress("token");
        }
        if (p.feeCalculator == address(0x0)) {
            revert TokiZeroAddress("feeCalculator");
        }
        $._token = p.token;
        $._feeCalculator = p.feeCalculator;
        $._maxTotalDeposits = p.maxTotalDeposits;
    }

    // ========================== external functions ===================================
    // for deposit
    function mint(
        address to,
        uint256 amountLD
    ) external nonReentrant onlyRole(DEFAULT_ROUTER_ROLE) returns (uint256) {
        return _mintLPbyLDWithLimitCheck(to, amountLD, true);
    }

    function callDelta(bool fullMode) external onlyRole(DEFAULT_ROUTER_ROLE) {
        _deltaSourceUpdate(fullMode);
    }

    //-----------------------------------------------------------------------------------
    // Admin functions
    //-----------------------------------------------------------------------------------
    function setTransferStop(
        bool transferStop_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        PoolStorage storage $ = _getPoolStorage();
        $._transferStop = transferStop_;
        emit IPool.UpdateStopTransfer($._transferStop);
    }

    function registerPeerPool(
        uint256 peerChainId,
        uint256 peerPoolId,
        uint256 weight
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        PoolStorage storage $ = _getPoolStorage();
        uint256 length = $._peerPoolInfos.length;
        if (MAX_PEERS <= length) {
            revert TokiExceed("PeerPool", length + 1, MAX_PEERS);
        }
        for (uint256 i = 0; i < length; ++i) {
            PeerPoolInfo memory peerPoolInfo = $._peerPoolInfos[i];
            bool exists = peerPoolInfo.chainId == peerChainId &&
                peerPoolInfo.id == peerPoolId;
            if (exists) {
                revert TokiPeerPoolIsRegistered(peerChainId, peerPoolId);
            }
        }
        $._totalWeight = $._totalWeight + weight;
        $._peerPoolInfoIndexSeek[peerChainId][peerPoolId] = $
            ._peerPoolInfos
            .length;
        $._peerPoolInfos.push(
            PeerPoolInfo(peerChainId, peerPoolId, weight, 0, 0, 0, 0, false)
        );
        emit PeerPoolInfoUpdate(peerChainId, peerPoolId, weight);
    }

    function activatePeerPool(
        uint256 peerChainId,
        uint256 peerPoolId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        PeerPoolInfo storage p = _getAndCheckPeerPoolInfo(
            peerChainId,
            peerPoolId
        );
        if (p.ready) {
            revert TokiPeerPoolIsAlreadyActive(peerChainId, peerPoolId);
        }
        p.ready = true;
    }

    function setFeeCalculator(
        address _feeCalculator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        PoolStorage storage $ = _getPoolStorage();
        $._feeCalculator = _feeCalculator;
    }

    function setPeerPoolWeight(
        uint256 peerChainId,
        uint256 peerPoolId,
        uint256 weight
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        PoolStorage storage $ = _getPoolStorage();
        PeerPoolInfo storage p = _getAndCheckPeerPoolInfo(
            peerChainId,
            peerPoolId
        );
        $._totalWeight = $._totalWeight - p.weight + weight;
        p.weight = weight;
        emit PeerPoolInfoUpdate(peerChainId, peerPoolId, weight);
    }

    function setDeltaParam(
        bool batched_,
        uint256 swapDeltaBP_,
        uint256 lpDeltaBP_,
        bool defaultSwapMode_,
        bool defaultLPMode_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        PoolStorage storage $ = _getPoolStorage();
        if (swapDeltaBP_ > BPS_DENOMINATOR) {
            revert TokiExceed("swapDeltaBP", swapDeltaBP_, BPS_DENOMINATOR);
        }
        if (lpDeltaBP_ > BPS_DENOMINATOR) {
            revert TokiExceed("lpDeltaBP", lpDeltaBP_, BPS_DENOMINATOR);
        }
        $._batched = batched_;
        $._swapDeltaBP = swapDeltaBP_;
        $._lpDeltaBP = lpDeltaBP_;
        $._defaultSwapMode = defaultSwapMode_;
        $._defaultLPMode = defaultLPMode_;
        emit UpdateDeltaParam(
            batched_,
            swapDeltaBP_,
            lpDeltaBP_,
            defaultSwapMode_,
            defaultLPMode_
        );
    }

    function drawFee(address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        PoolStorage storage $ = _getPoolStorage();
        if (to == address(0x0)) {
            revert TokiZeroAddress("to");
        }
        if ($._feeBalance == 0) {
            revert TokiNoFee();
        }
        uint256 amountLD = _GDToLD($._feeBalance);
        $._feeBalance = 0;
        emit DrawFee(to, amountLD);
        _safeTransferWithRevert($._token, to, amountLD);
    }

    function setMaxTotalDeposits(
        uint256 newMaxTotalDeposits
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        PoolStorage storage $ = _getPoolStorage();
        emit SetMaxTotalDeposits(newMaxTotalDeposits);
        $._maxTotalDeposits = newMaxTotalDeposits;
    }

    // solhint-disable-next-line func-name-mixedcase
    function LPToLD(uint256 amountLP) external view returns (uint256) {
        return _GDToLD(_LPToGD(amountLP));
    }

    // solhint-disable-next-line func-name-mixedcase
    function LDToLP(uint256 _amountLD) external view returns (uint256) {
        return _GDToLP(_LDToGD(_amountLD));
    }

    function getPeerPoolInfo(
        uint256 peerChainId,
        uint256 peerPoolId
    ) external view returns (PeerPoolInfo memory) {
        return _getAndCheckPeerPoolInfo(peerChainId, peerPoolId);
    }

    function calcFee(
        uint256 peerChainId,
        uint256 peerPoolId,
        address from,
        uint256 amountLD
    )
        external
        view
        returns (ITransferPoolFeeCalculator.FeeInfo memory feeInfo)
    {
        PoolStorage storage $ = _getPoolStorage();
        PeerPoolInfo storage peerPoolInfo = _getAndCheckPeerPoolInfo(
            peerChainId,
            peerPoolId
        );
        uint256 amountGD = _LDToGD(amountLD);

        ITransferPoolFeeCalculator.SrcPoolInfo
            memory myPoolInfo = ITransferPoolFeeCalculator.SrcPoolInfo({
                addr: address(this),
                id: $._poolId,
                globalDecimals: globalDecimals(),
                balance: tokenBalanceOfThisPoolInGD(),
                totalLiquidity: $._totalLiquidity,
                eqFeePool: $._eqFeePool
            });

        // fee calculate
        return
            ITransferPoolFeeCalculator($._feeCalculator).calcFee(
                myPoolInfo,
                peerPoolInfo,
                from,
                amountGD
            );
    }

    function transfer(
        uint256 peerChainId,
        uint256 peerPoolId,
        address from,
        uint256 amountLD,
        uint256 minAmountLD,
        bool newLiquidity
    )
        public
        nonReentrant
        onlyRole(DEFAULT_ROUTER_ROLE)
        returns (ITransferPoolFeeCalculator.FeeInfo memory feeInfo)
    {
        PoolStorage storage $ = _getPoolStorage();
        if ($._transferStop) {
            revert TokiTransferIsStop();
        }
        if (from == address(0x0)) {
            revert TokiZeroAddress("from");
        }
        PeerPoolInfo storage peerPoolInfo = _getAndCheckPeerPoolInfo(
            peerChainId,
            peerPoolId
        );
        if (peerPoolInfo.ready != true) {
            revert TokiPeerPoolIsNotReady(peerChainId, peerPoolId);
        }

        uint256 amountGD = _LDToGD(amountLD);
        uint256 minAmountGD = _LDToGD(minAmountLD);

        ITransferPoolFeeCalculator.SrcPoolInfo
            memory myPoolInfo = ITransferPoolFeeCalculator.SrcPoolInfo({
                addr: address(this),
                id: $._poolId,
                globalDecimals: globalDecimals(),
                balance: tokenBalanceOfThisPoolInGD(),
                totalLiquidity: $._totalLiquidity,
                eqFeePool: $._eqFeePool
            });

        // fee calculate
        feeInfo = ITransferPoolFeeCalculator($._feeCalculator).calcFee(
            myPoolInfo,
            peerPoolInfo,
            from,
            amountGD
        );

        // Note about slither-disable:
        //   no need to check amountGD is less than 0 because it is unsigned.
        // slither-disable-next-line incorrect-equality
        if (0 == feeInfo.amountGD) {
            // Although the calculation of 'needed' is somewhat specific,
            // it remains stable as long as the fee structure doesn't change.
            revert TokiInsufficientAmount(
                "amountLD",
                amountLD,
                feeInfo.eqFee + feeInfo.protocolFee + feeInfo.lpFee + 1
            );
        }
        //Slippage check uses eq fee and eq reward. We don't use predictable protocol fee and LP fee.
        if (amountGD + feeInfo.eqReward - feeInfo.eqFee < minAmountGD) {
            revert TokiSlippageTooHigh(
                amountGD,
                feeInfo.eqReward,
                feeInfo.eqFee,
                minAmountGD
            );
        }

        if (feeInfo.eqReward > 0) {
            $._eqFeePool -= feeInfo.eqReward;
        }
        feeInfo.balanceDecrease = amountGD - feeInfo.lpFee + feeInfo.eqReward;

        // delta algorithm 1-5 lines
        if (peerPoolInfo.balance < feeInfo.balanceDecrease) {
            revert TokiInsufficientPoolLiquidity(
                peerPoolInfo.balance,
                feeInfo.balanceDecrease
            );
        }
        peerPoolInfo.balance = peerPoolInfo.balance - feeInfo.balanceDecrease;

        if (newLiquidity) {
            $._deltaCredit = $._deltaCredit + amountGD + feeInfo.eqReward;
        } else if (feeInfo.eqReward > 0) {
            $._deltaCredit = $._deltaCredit + feeInfo.eqReward;
        }

        // delta algportm 6-16 lines
        if (
            !$._batched ||
            $._deltaCredit >=
            ($._totalLiquidity * $._swapDeltaBP) / BPS_DENOMINATOR
        ) {
            _deltaSourceUpdate($._defaultSwapMode);
        }

        // delta algorithm 17-20 lines -> sendCredit

        emit Transfer(
            peerChainId,
            peerPoolId,
            from,
            feeInfo.amountGD,
            feeInfo.eqReward,
            feeInfo.eqFee,
            feeInfo.protocolFee,
            feeInfo.lpFee
        );
    }

    function recv(
        uint256 peerChainId,
        uint256 peerPoolId,
        address to,
        ITransferPoolFeeCalculator.FeeInfo memory feeInfo,
        bool updateDelta
    )
        public
        nonReentrant
        onlyRole(DEFAULT_ROUTER_ROLE)
        returns (uint256 amountLD, bool isTransferred)
    {
        PoolStorage storage $ = _getPoolStorage();
        if (updateDelta) {
            _recvFees($, feeInfo);
            // delta algorithm 21-24 lines -> updateCredit
            _decreaseLastKnownBalance(
                peerChainId,
                peerPoolId,
                feeInfo.balanceDecrease
            );
        }

        // user receives the amount + the srcReward
        amountLD = _GDToLD(feeInfo.amountGD + feeInfo.eqReward);
        bool passed = true;
        if (peerChainId != block.chainid) {
            passed = _checkAndUpdateFlowRateLimit(amountLD);
        }

        if (passed && _safeTransfer($._token, to, amountLD)) {
            isTransferred = true;

            emit Recv(
                to,
                feeInfo.amountGD + feeInfo.eqReward,
                feeInfo.protocolFee,
                feeInfo.eqFee
            );
        } else {
            _cancelFlowRateLimit();
        }
    }

    function withdrawRemote(
        uint256 peerChainId,
        uint256 peerPoolId,
        address from,
        uint256 amountLP
    ) public nonReentrant onlyRole(DEFAULT_ROUTER_ROLE) {
        PoolStorage storage $ = _getPoolStorage();
        if (from == address(0x0)) {
            revert TokiZeroAddress("from");
        }
        // 1. burn lp token on local
        uint256 amountGD = _burnLP(from, amountLP);
        // 2. run delta common function
        if (
            !$._batched ||
            $._deltaCredit >
            ($._totalLiquidity * $._lpDeltaBP) / BPS_DENOMINATOR
        ) {
            _deltaSourceUpdate($._defaultLPMode);
        }
        uint256 amountLD = _GDToLD(amountGD);
        // 3. emit withdrawRemote event
        emit WithdrawRemote(peerChainId, peerPoolId, from, amountLP, amountLD);
    }

    function withdrawLocal(
        uint256 peerChainId,
        uint256 peerPoolId,
        address from,
        uint256 amountLP,
        bytes calldata to
    )
        public
        nonReentrant
        onlyRole(DEFAULT_ROUTER_ROLE)
        returns (uint256 amountGD)
    {
        PoolStorage storage $ = _getPoolStorage();
        if (from == address(0x0)) {
            revert TokiZeroAddress("from");
        }
        // 1. burn lp token on local
        if (_getAndCheckPeerPoolInfo(peerChainId, peerPoolId).ready != true) {
            revert TokiPeerPoolIsNotReady(peerChainId, peerPoolId);
        }
        amountGD = _burnLP(from, amountLP);

        // 2. run delta common function
        if (
            !$._batched ||
            $._deltaCredit >
            ($._totalLiquidity * $._lpDeltaBP) / BPS_DENOMINATOR
        ) {
            _deltaSourceUpdate(false);
        }

        // 3. emit withdrawLocal event
        emit WithdrawLocal(
            peerChainId,
            peerPoolId,
            from,
            amountLP,
            amountGD,
            to
        );
    }

    function withdrawCheck(
        uint256 peerChainId,
        uint256 peerPoolId,
        uint256 amountGD
    )
        public
        nonReentrant
        onlyRole(DEFAULT_ROUTER_ROLE)
        returns (uint256 amountSwap, uint256 amountMint)
    {
        PeerPoolInfo storage peerPoolInfo = _getAndCheckPeerPoolInfo(
            peerChainId,
            peerPoolId
        );
        if (amountGD > peerPoolInfo.balance) {
            amountMint = amountGD - peerPoolInfo.balance;
            amountSwap = peerPoolInfo.balance;
            peerPoolInfo.balance = 0;
        } else {
            peerPoolInfo.balance = peerPoolInfo.balance - amountGD;
            amountSwap = amountGD;
            amountMint = 0;
        }
        emit WithdrawCheck(peerChainId, peerPoolId, amountSwap, amountMint);
    }

    /**
     * @dev even when updateDelta is true, lp token will not be re-minted if to is zero address.
     */
    function withdrawConfirm(
        uint256 peerChainId,
        uint256 peerPoolId,
        address to,
        uint256 amountGD,
        uint256 amountToMintGD,
        bool updateDelta
    )
        public
        nonReentrant
        onlyRole(DEFAULT_ROUTER_ROLE)
        returns (bool isTransferred)
    {
        if (updateDelta) {
            // 1. mint lp token on local if possible
            if (amountToMintGD > 0 && to != address(0x0)) {
                _mintLPbyLD(to, _GDToLD(amountToMintGD), false);
            }
            // 2. update last known balance
            _decreaseLastKnownBalance(peerChainId, peerPoolId, amountGD);
        }

        // 3. transfer asset token to _to
        uint256 amountLD = _GDToLD(amountGD);
        bool passed = true;
        if (peerChainId != block.chainid) {
            passed = _checkAndUpdateFlowRateLimit(amountLD);
        }

        PoolStorage storage $ = _getPoolStorage();
        if (passed && _safeTransfer($._token, to, amountLD)) {
            isTransferred = true;

            emit WithdrawConfirm(
                peerChainId,
                peerPoolId,
                to,
                amountGD,
                amountToMintGD
            );
        } else {
            _cancelFlowRateLimit();
        }
    }

    function sendCredit(
        uint256 peerChainId,
        uint256 peerPoolId
    )
        public
        nonReentrant
        onlyRole(DEFAULT_ROUTER_ROLE)
        returns (CreditInfo memory creditInfo)
    {
        PoolStorage storage $ = _getPoolStorage();
        PeerPoolInfo storage peerPoolInfo = _getAndCheckPeerPoolInfo(
            peerChainId,
            peerPoolId
        );
        if (peerPoolInfo.ready != true) {
            revert TokiPeerPoolIsNotReady(peerChainId, peerPoolId);
        }

        creditInfo.targetBalance =
            ($._totalLiquidity * peerPoolInfo.weight) /
            $._totalWeight;
        creditInfo.credits = peerPoolInfo.credits;
        // delta algorithm 17-20 lines
        peerPoolInfo.lastKnownBalance =
            peerPoolInfo.lastKnownBalance +
            peerPoolInfo.credits;
        peerPoolInfo.credits = 0;
        emit SendCredit(
            peerPoolId,
            creditInfo.credits,
            creditInfo.targetBalance
        );
    }

    function updateCredit(
        uint256 peerChainId,
        uint256 peerPoolId,
        CreditInfo memory creditInfo
    ) public nonReentrant onlyRole(DEFAULT_ROUTER_ROLE) {
        PeerPoolInfo storage peerPoolInfo = _getAndCheckPeerPoolInfo(
            peerChainId,
            peerPoolId
        );
        peerPoolInfo.balance = peerPoolInfo.balance + creditInfo.credits;
        if (peerPoolInfo.targetBalance != creditInfo.targetBalance) {
            peerPoolInfo.targetBalance = creditInfo.targetBalance;
        }
        emit UpdateCredit(
            peerChainId,
            peerPoolId,
            creditInfo.credits,
            creditInfo.targetBalance
        );
    }

    function withdrawInstant(
        address from,
        uint256 amountLP,
        address to
    )
        public
        nonReentrant
        onlyRole(DEFAULT_ROUTER_ROLE)
        returns (uint256 amountGD)
    {
        PoolStorage storage $ = _getPoolStorage();
        if (from == address(0x0)) {
            revert TokiZeroAddress("from");
        }
        uint256 deltaCredit_ = $._deltaCredit; // sload optimization.
        uint256 capAmountLP = _GDToLP(deltaCredit_);

        if (amountLP > capAmountLP) amountLP = capAmountLP;

        amountGD = _burnLP(from, amountLP);
        $._deltaCredit = deltaCredit_ - amountGD;
        uint256 amountLD = _GDToLD(amountGD);
        _safeTransferWithRevert($._token, to, amountLD);
        emit WithdrawInstant(from, amountLP, amountGD, to);
    }

    /**
     * @dev Receives delta info and fees from the peer pool to keep the delta consistent.
     */
    function handleRecvFailure(
        uint256 peerChainId,
        uint256 peerPoolId,
        address /* to */,
        ITransferPoolFeeCalculator.FeeInfo memory feeInfo
    ) public nonReentrant onlyRole(DEFAULT_ROUTER_ROLE) {
        PoolStorage storage $ = _getPoolStorage();
        _recvFees($, feeInfo);
        _decreaseLastKnownBalance(
            peerChainId,
            peerPoolId,
            feeInfo.balanceDecrease
        );
    }

    /**
     * @dev Receive delta info ( and re-mint lp token ) to keep the delta consistent.
     */
    function handleWithdrawConfirmFailure(
        uint256 peerChainId,
        uint256 peerPoolId,
        address to,
        uint256 amountGD,
        uint256 amountToMintGD
    ) public nonReentrant onlyRole(DEFAULT_ROUTER_ROLE) {
        // 1. mint lp token on local if possible
        if (amountToMintGD > 0 && to != address(0x0)) {
            _mintLPbyLD(to, _GDToLD(amountToMintGD), false);
        }
        // 2. update last known balance
        _decreaseLastKnownBalance(peerChainId, peerPoolId, amountGD);
    }

    // ========================== view functions ===================================

    function feeCalculator() public view returns (address) {
        return _getPoolStorage()._feeCalculator;
    }

    function peerPoolInfos(
        uint256 index
    ) public view returns (PeerPoolInfo memory) {
        return _getPoolStorage()._peerPoolInfos[index];
    }

    function peerPoolInfoIndexSeek(
        uint256 peerChainId,
        uint256 peerPoolId
    ) public view returns (uint256) {
        return
            _getPoolStorage()._peerPoolInfoIndexSeek[peerChainId][peerPoolId];
    }

    function totalLiquidity() public view returns (uint256) {
        return _getPoolStorage()._totalLiquidity;
    }

    function totalWeight() public view returns (uint256) {
        return _getPoolStorage()._totalWeight;
    }

    function deltaCredit() public view returns (uint256) {
        return _getPoolStorage()._deltaCredit;
    }

    function batched() public view returns (bool) {
        return _getPoolStorage()._batched;
    }

    function defaultSwapMode() public view returns (bool) {
        return _getPoolStorage()._defaultSwapMode;
    }

    function defaultLPMode() public view returns (bool) {
        return _getPoolStorage()._defaultLPMode;
    }

    function feeBalance() public view returns (uint256) {
        return _getPoolStorage()._feeBalance;
    }

    function eqFeePool() public view returns (uint256) {
        return _getPoolStorage()._eqFeePool;
    }

    function swapDeltaBP() public view returns (uint256) {
        return _getPoolStorage()._swapDeltaBP;
    }

    function lpDeltaBP() public view returns (uint256) {
        return _getPoolStorage()._lpDeltaBP;
    }

    function poolId() public view returns (uint256) {
        return _getPoolStorage()._poolId;
    }

    function token() public view returns (address) {
        return _getPoolStorage()._token;
    }

    function transferStop() public view returns (bool) {
        return _getPoolStorage()._transferStop;
    }

    function maxTotalDeposits() public view returns (uint256) {
        return _getPoolStorage()._maxTotalDeposits;
    }

    // ========================== override functions ===============================
    function decimals() public view virtual override returns (uint8) {
        return globalDecimals();
    }

    // ========================== internal functions ===============================
    //-----------------------------------------------------------------------------------
    // heavily used functions
    //-----------------------------------------------------------------------------------
    function _safeTransferWithRevert(
        address token_,
        address to,
        uint256 value
    ) internal {
        if (!_safeTransfer(token_, to, value)) {
            revert TokiTransferIsFailed(token_, to, value);
        }
    }

    function _safeTransfer(
        address token_,
        address to,
        uint256 value
    ) internal returns (bool) {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = token_.call(
            abi.encodeCall(IERC20(token_).transfer, (to, value))
        );
        if (success && returndata.length != 0) {
            return abi.decode(returndata, (bool));
        }
        return success;
    }

    function _mintLPbyLD(
        address to,
        uint256 amountLD,
        bool creditDelta
    ) internal returns (uint256 amountAssetGD) {
        PoolStorage storage $ = _getPoolStorage();
        if ($._totalWeight == 0) {
            revert TokiZeroValue("totalWeight");
        }
        amountAssetGD = _LDToGD(amountLD);

        if (creditDelta) {
            $._deltaCredit = $._deltaCredit + amountAssetGD;
        }

        uint256 amountLPTokens = amountAssetGD;
        if (totalSupply() != 0) {
            amountLPTokens =
                (amountAssetGD * totalSupply()) /
                $._totalLiquidity;
        }
        $._totalLiquidity = $._totalLiquidity + amountAssetGD;

        _mint(to, amountLPTokens);
        emit Mint(to, amountLPTokens, amountAssetGD);

        if (
            !$._batched ||
            $._deltaCredit >
            ($._totalLiquidity * $._lpDeltaBP) / BPS_DENOMINATOR
        ) {
            _deltaSourceUpdate($._defaultLPMode);
        }
    }

    function _mintLPbyLDWithLimitCheck(
        address to,
        uint256 amountLD,
        bool creditDelta
    ) internal checkMaxTotalDeposits(amountLD) returns (uint256 amountAssetGD) {
        return _mintLPbyLD(to, amountLD, creditDelta);
    }

    function _burnLP(
        address from,
        uint256 amountLP
    ) internal returns (uint256) {
        PoolStorage storage $ = _getPoolStorage();
        if (totalSupply() == 0) {
            revert TokiZeroValue("totalSupply");
        }
        uint256 balance = balanceOf(from);
        if (balance < amountLP) {
            revert TokiExceed("Pool._burnLP.amountLP", amountLP, balance);
        }

        uint256 amountGD = (amountLP * $._totalLiquidity) / totalSupply();

        $._totalLiquidity = $._totalLiquidity - amountGD;

        _burn(from, amountLP);
        emit Burn(from, amountLP, amountGD);
        return amountGD;
    }

    /**
     * @dev  _deltaSourceUpdate implements the delta algorithm, and balances liquidity across peer pools on different chains is only done
     * if there's positive deltaCredit and totalWeight.
     *
     * The following steps are done when deltaSourceUpdate is done:
     * 1: Difference Calculation
     * The difference between the ideal balance (balLiq) and current balance (currLiq) for each peer pool is calculated.
     * The sum of the total difference (totalDiff) is also calculated.
     * 2 : Credit Distribution
     * Handles three scenarios based on the relationship between totalDiff and deltaCredit:
     * - Scenario 1: If totalDiff is 0:
     * In fullMode, distributes excess credits proportionally based on weights. Otherwise, nothing is done.
     * - Scenario 2: If deltaCredit is lesser than totalDiff:
     * Calculates the differences based on available deltaCredit, and distributes credits proportionally to the normalized differences.
     * Updates the credits for each peer pool based on the calculated distribution.
     * - Scenario 3: If deltaCredit is greater than or equal to totalDiff:
     * In fullMode, distributes all differences plus excess credits proportionally. Otherwise, it distributes only the calculated differences.
     * Updates the credits for each peer pool based on the calculated distribution.
     * 3. Delta Credit Update:
     * Reduces deltaCredit by the total amount spent.
     */
    function _deltaSourceUpdate(bool fullMode) internal {
        PoolStorage storage $ = _getPoolStorage();
        if ($._deltaCredit > 0 && $._totalWeight > 0) {
            uint256 peerPoolInfosLength = $._peerPoolInfos.length;
            uint256[] memory diff = new uint256[](peerPoolInfosLength);
            uint256 totalDiff = 0;

            // delta algorithm 6-9 lines
            for (uint256 i = 0; i < peerPoolInfosLength; ++i) {
                PeerPoolInfo storage peerPoolInfo = $._peerPoolInfos[i];
                // (totalLiquidity * (weight/totalWeight)) - (lastKnownBalance+credits)
                uint256 balLiq = ($._totalLiquidity * peerPoolInfo.weight) /
                    $._totalWeight;
                uint256 currLiq = peerPoolInfo.lastKnownBalance +
                    peerPoolInfo.credits;
                // max(0, lp_s * w_{s,x} − (lkb_{x,s} + c_{s,x}))
                if (balLiq > currLiq) {
                    diff[i] = balLiq - currLiq;
                    totalDiff = totalDiff + diff[i];
                }
            }
            // Indicates how much deltacredit is spent.
            uint256 spent = 0;

            if (totalDiff == 0) {
                // If fullMode delta will use excess credits
                if (fullMode && $._deltaCredit > 0) {
                    for (uint256 i = 0; i < peerPoolInfosLength; ++i) {
                        PeerPoolInfo storage peerPoolInfo = $._peerPoolInfos[i];
                        // same as delta algorithm 10-12 lines: diff_{s,x} <- min(Total,t) * diff_{s,x} / totalDiff
                        uint256 amtToCredit = ($._deltaCredit *
                            peerPoolInfo.weight) / $._totalWeight;
                        spent = spent + amtToCredit;
                        peerPoolInfo.credits =
                            peerPoolInfo.credits +
                            amtToCredit;
                    }
                } // else do nth
            } else if ($._deltaCredit < totalDiff) {
                // deltaCredit < totalDiff , fullMode or not, normalize the diff by deltaCredit
                for (uint256 i = 0; i < peerPoolInfosLength; ++i) {
                    if (diff[i] > 0) {
                        PeerPoolInfo storage peerPoolInfo = $._peerPoolInfos[i];
                        // delta algorithm 10-12 lines: diff_{s,x} <- min(Total,t) * diff_{s,x} / totalDiff
                        diff[i] = (diff[i] * $._deltaCredit) / totalDiff;
                        // delta algorithm 13-16 lines:
                        spent = spent + diff[i];
                        peerPoolInfo.credits = peerPoolInfo.credits + diff[i];
                    }
                }
            } else {
                // totalDiff <= deltaCredit
                // delta algorithm 13-16 lines:
                if (fullMode) {
                    uint256 excessCredit = $._deltaCredit - totalDiff;
                    for (uint256 i = 0; i < peerPoolInfosLength; ++i) {
                        PeerPoolInfo storage peerPoolInfo = $._peerPoolInfos[i];
                        // credits = credits + diff[i] + exceedCredit * (weight / totalWeight)
                        uint256 amtToCredit = diff[i] +
                            (excessCredit * peerPoolInfo.weight) /
                            $._totalWeight;
                        spent = spent + amtToCredit;
                        peerPoolInfo.credits =
                            peerPoolInfo.credits +
                            amtToCredit;
                    }
                } else {
                    // totaldiff <= deltaCredit but not running fullMode
                    // A diff in peerPool, credit it as is and do not use all deltaCredit.
                    for (uint256 i = 0; i < peerPoolInfosLength; ++i) {
                        if (diff[i] > 0) {
                            PeerPoolInfo storage peerPoolInfo = $
                                ._peerPoolInfos[i];
                            spent = spent + diff[i];
                            peerPoolInfo.credits =
                                peerPoolInfo.credits +
                                diff[i];
                        }
                    }
                }
            }

            // deltaCredit spent.
            $._deltaCredit = $._deltaCredit - spent;
        }
    }

    function _decreaseLastKnownBalance(
        uint256 peerChainId,
        uint256 peerPoolId,
        uint256 amountGD
    ) internal {
        PeerPoolInfo storage peerPoolInfo = _getAndCheckPeerPoolInfo(
            peerChainId,
            peerPoolId
        );
        peerPoolInfo.lastKnownBalance =
            peerPoolInfo.lastKnownBalance -
            amountGD;
    }

    function _recvFees(
        PoolStorage storage $,
        ITransferPoolFeeCalculator.FeeInfo memory feeInfo
    ) internal {
        $._totalLiquidity += feeInfo.lpFee;
        $._eqFeePool += feeInfo.eqFee;
        $._feeBalance += feeInfo.protocolFee;
    }

    function _authorizeUpgrade(
        address
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    //-----------------------------------------------------------------------------------
    // Helper functions
    //-----------------------------------------------------------------------------------
    function _getAndCheckPeerPoolInfo(
        uint256 peerChainId,
        uint256 peerPoolId
    ) internal view returns (PeerPoolInfo storage peerPoolInfo) {
        PoolStorage storage $ = _getPoolStorage();
        if ($._peerPoolInfos.length == 0) {
            revert TokiNoPeerPoolInfo();
        }
        peerPoolInfo = $._peerPoolInfos[
            $._peerPoolInfoIndexSeek[peerChainId][peerPoolId]
        ];
        if (
            peerPoolInfo.chainId != peerChainId || peerPoolInfo.id != peerPoolId
        ) {
            revert TokiPeerPoolInfoNotFound(peerChainId, peerPoolId);
        }
    }

    // solhint-disable-next-line func-name-mixedcase
    function _LPToGD(uint256 amountLP) internal view returns (uint256) {
        PoolStorage storage $ = _getPoolStorage();
        if (totalSupply() == 0) {
            revert TokiZeroValue("totalSupply");
        }
        return (amountLP * $._totalLiquidity) / totalSupply();
    }

    // solhint-disable-next-line func-name-mixedcase
    function _GDToLP(uint256 amountGD) internal view returns (uint256) {
        PoolStorage storage $ = _getPoolStorage();
        if ($._totalLiquidity == 0) {
            revert TokiZeroValue("totalLiquidity");
        }
        return (amountGD * totalSupply()) / $._totalLiquidity;
    }

    function tokenBalanceOfThisPoolInGD() internal view returns (uint256) {
        PoolStorage storage $ = _getPoolStorage();
        return _LDToGD(IERC20($._token).balanceOf(address(this)));
    }

    function _getPoolStorage() private pure returns (PoolStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := POOL_LOCATION
        }
    }
}
