// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {ShortString, ShortStrings} from "@openzeppelin/contracts/utils/ShortStrings.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import "@hyperledger-labs/yui-ibc-solidity/contracts/core/26-router/IIBCModule.sol";

import "./interfaces/IBridgeRouter.sol";
import "./interfaces/IReceiveRetryable.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IPoolRepository.sol";
import "./interfaces/ITokenPriceOracle.sol";
import "./interfaces/IRelayerFeeCalculator.sol";
import "./future/interfaces/ITokenEscrow.sol";

import "./BridgeBase.sol";
import "./BridgeFallback.sol";
import "./BridgeChannelUpgradeFallback.sol";
import "./IBCChannelUpgradableModuleBase.sol";

contract Bridge is
    AccessControlUpgradeable,
    ReentrancyGuardTransientUpgradeable,
    IBCAppBase, // inherit Context
    BridgeBase,
    IBridgeStandardRouter,
    UUPSUpgradeable
{
    using ShortStrings for string;
    using ShortStrings for ShortString;

    struct InitializeParam {
        address ibcHandler; // role IBC_HANDLER_ROLE
        address poolRepository;
        address tokenEscrow;
        address tokenPriceOracle;
        address relayerFeeOwner;
        address relayerFeeCalculator;
        address bridgeFallback;
        address bridgeChannelUpgradeFallback;
        uint64 receiveRetryBlocks;
        uint64 withdrawRetryBlocks;
        uint64 externalRetryBlocks;
    }

    // Processes remittance requests received from the src side.
    // If there are additional payloads, call the specified external callback function
    // <- Send from `transafer` or `withdrawRemote` on the src side.
    // -> Receive `receiveIBC` on dst side.
    struct SendTransferPoolParam {
        uint256 dstChainId;
        string srcChannel;
        uint256 srcPoolId;
        uint256 dstPoolId;
        ITransferPoolFeeCalculator.FeeInfo feeInfo;
        IPool.CreditInfo creditInfo;
        bytes to;
        uint256 refuelAmount;
        IBCUtils.ExternalInfo externalInfo;
        address payable refundTo;
    }

    event Unrecoverable(uint256 chainId, uint64 sequence);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint256 appVersion_, string memory port) {
        APP_VERSION = appVersion_;
        PORT = port.toShortString();
        _disableInitializers();
    }

    function initialize(
        InitializeParam memory param
    ) public virtual initializer {
        __AccessControl_init();
        __ReentrancyGuardTransient_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(IBC_HANDLER_ROLE, param.ibcHandler);
        _grantRole(RELAYER_FEE_OWNER_ROLE, param.relayerFeeOwner);

        BridgeStorage storage $ = getBridgeStorage();
        $.ics04SendPacket = IICS04SendPacket(param.ibcHandler);
        $.poolRepository = IPoolRepository(param.poolRepository);
        $.tokenEscrow = ITokenEscrow(param.tokenEscrow);
        $.tokenPriceOracle = ITokenPriceOracle(param.tokenPriceOracle);
        $.relayerFeeCalculator = IRelayerFeeCalculator(
            param.relayerFeeCalculator
        );
        BridgeFallback bridgeFallback = BridgeFallback(
            payable(param.bridgeFallback)
        );
        if (APP_VERSION != bridgeFallback.appVersion()) {
            revert TokiInvalidAppVersion(
                APP_VERSION,
                bridgeFallback.appVersion()
            );
        }
        $.defaultFallback = param.bridgeFallback;

        BridgeChannelUpgradeFallback bridgeChannelUpgradeFallback = BridgeChannelUpgradeFallback(
                payable(param.bridgeChannelUpgradeFallback)
            );
        if (APP_VERSION != bridgeChannelUpgradeFallback.appVersion()) {
            revert TokiInvalidAppVersion(
                APP_VERSION,
                bridgeChannelUpgradeFallback.appVersion()
            );
        }
        $.channelUpgradeFallback = param.bridgeChannelUpgradeFallback;

        $.receiveRetryBlocks = param.receiveRetryBlocks;
        $.withdrawRetryBlocks = param.withdrawRetryBlocks;
        $.externalRetryBlocks = param.externalRetryBlocks;
    }

    /* solhint-disable no-complex-fallback */
    /**
     * @dev To avoid Bridge deployment size limits and reduce user gas costs:
     * - Move infrequent admin/exception functions to BridgeFallback
     * - Call these via fallback mechanism
     */
    fallback() external payable {
        address fallback_ = _isChannelUpgradeSelector(msg.sig)
            ? getBridgeStorage().channelUpgradeFallback
            : getBridgeStorage().defaultFallback;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(
                gas(),
                fallback_,
                0,
                calldatasize(),
                0,
                0
            )
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /* solhint-enable no-complex-fallback */

    /**
     *  Bridge main functions
     */
    function deposit(
        uint256 poolId,
        uint256 amountLD,
        address to
    ) external nonReentrant {
        IPool pool = getPool(poolId);
        uint256 convertRate = pool.convertRate();
        amountLD = _roundDownToConvertRate(amountLD, convertRate);
        IBCUtils.safeTransferFrom(
            pool.token(),
            msg.sender,
            address(pool),
            amountLD
        );
        // solhint-disable-next-line no-unused-vars
        uint256 _amountAssetGD = pool.mint(to, amountLD);
    }

    // Deposit the token in the corresponding pool and make a remittance request on the dst side
    // Call `transfer` and `sendCredit` on pool contract.
    // -> And call `receivePool` on dst side.
    function transferPool(
        string memory srcChannel,
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLD,
        uint256 minAmountLD,
        bytes calldata to,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo calldata externalInfo,
        address payable refundTo
    ) external payable nonReentrant {
        if (amountLD == 0) {
            revert TokiZeroAmount("amountLD");
        }
        if (refundTo == address(0x0)) {
            revert TokiZeroAddress("refundTo");
        }
        _validateToLength(to);
        _validatePayloadLength(externalInfo.payload);

        uint256 dstChainId = getChainId(srcChannel, true);

        {
            BridgeStorage storage $ = getBridgeStorage();
            if ($.refuelSrcCap[dstChainId] < refuelAmount) {
                revert TokiExceed(
                    "refuelAmount",
                    refuelAmount,
                    $.refuelSrcCap[dstChainId]
                );
            }
        }
        {
            (
                ITransferPoolFeeCalculator.FeeInfo memory feeInfo,
                IPool.CreditInfo memory creditInfo
            ) = _preTransferPool(
                    dstChainId,
                    srcPoolId,
                    dstPoolId,
                    amountLD,
                    minAmountLD
                );
            SendTransferPoolParam memory p = SendTransferPoolParam(
                dstChainId,
                srcChannel,
                srcPoolId,
                dstPoolId,
                feeInfo,
                creditInfo,
                to,
                refuelAmount,
                externalInfo,
                refundTo
            );
            _sendTransferPool(p);
        }
    }

    function transferPoolInLedger(
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLD_,
        uint256 minAmountLD,
        address to,
        IBCUtils.ExternalInfo calldata externalInfo
    ) external nonReentrant {
        if (amountLD_ == 0) {
            revert TokiZeroAmount("amountLD");
        }

        (
            ITransferPoolFeeCalculator.FeeInfo memory feeInfo,
            IPool.CreditInfo memory creditInfo
        ) = _preTransferPool(
                block.chainid,
                srcPoolId,
                dstPoolId,
                amountLD_,
                minAmountLD
            );

        // "Receiving" half. It is same to TYPE_TRANSFER_POOL case in onRecvPacket().
        _receivePoolInLedger(
            srcPoolId,
            dstPoolId,
            to,
            feeInfo,
            creditInfo,
            externalInfo
        );
    }

    function transferToken(
        string calldata srcChannel,
        string calldata denom,
        uint256 amountLD,
        bytes calldata to,
        uint256 refuelAmount,
        IBCUtils.ExternalInfo calldata externalInfo,
        address payable refundTo
    ) external payable nonReentrant {
        // Call `transferToken` on Escrow contract.
        // -> And call `receiveToken` on dst side.
        if (amountLD == 0) {
            revert TokiZeroAmount("amountLD");
        }
        if (refundTo == address(0x0)) {
            revert TokiZeroAddress("refundTo");
        }
        _validateToLength(to);
        _validatePayloadLength(externalInfo.payload);

        uint256 dstChainId = getChainId(srcChannel, true);

        BridgeStorage storage $ = getBridgeStorage();
        if ($.refuelSrcCap[dstChainId] < refuelAmount) {
            revert TokiExceed(
                "refuelAmount",
                refuelAmount,
                $.refuelSrcCap[dstChainId]
            );
        }
        if (address($.tokenEscrow) == address(0x0)) {
            revert TokiZeroAddress("tokenEscrow");
        }
        uint256 amountGD = $.tokenEscrow.transferToken(
            dstChainId,
            msg.sender,
            amountLD
        );

        bytes memory message = IBCUtils.encodeTransferToken(
            denom,
            amountGD, // mint amount
            to, // to account
            refuelAmount,
            externalInfo // for composability
        );

        _sendWithRefund(
            dstChainId,
            srcChannel,
            message,
            refundTo,
            MessageType._TYPE_TRANSFER_TOKEN,
            externalInfo,
            refuelAmount
        );
    }

    // After transfer, LPToken is burned and credit is sent.
    function withdrawRemote(
        string calldata srcChannel,
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLP,
        uint256 minAmountLD,
        bytes calldata to,
        address payable refundTo
    ) external payable nonReentrant {
        if (amountLP == 0) {
            revert TokiZeroAmount("amountLP");
        }
        if (refundTo == address(0x0)) {
            revert TokiZeroAddress("refundTo");
        }
        _validateToLength(to);

        // call `withdrawRemote` and `sendCredit` on pool contract.
        // -> And call `receiveIBC` on dst side.
        uint256 dstChainId = getChainId(srcChannel, true);

        (
            ITransferPoolFeeCalculator.FeeInfo memory feeInfo,
            IPool.CreditInfo memory creditInfo
        ) = _preWithdrawRemote(
                dstChainId,
                srcPoolId,
                dstPoolId,
                amountLP,
                minAmountLD
            );
        SendTransferPoolParam memory p = SendTransferPoolParam(
            dstChainId,
            srcChannel,
            srcPoolId,
            dstPoolId,
            feeInfo,
            creditInfo,
            to,
            0,
            IBCUtils.ExternalInfo("", 0),
            refundTo
        );

        _sendTransferPool(p);
    }

    // After transfer, LPToken is burned and credit is sent.
    function withdrawRemoteInLedger(
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLP,
        uint256 minAmountLD,
        address to
    ) external nonReentrant {
        if (amountLP == 0) {
            revert TokiZeroAmount("amountLP");
        }

        (
            ITransferPoolFeeCalculator.FeeInfo memory feeInfo,
            IPool.CreditInfo memory creditInfo
        ) = _preWithdrawRemote(
                block.chainid,
                srcPoolId,
                dstPoolId,
                amountLP,
                minAmountLD
            );

        // "Receiving" half. It is same to TYPE_TRANSFER_POOL case in onRecvPacket().
        _receivePoolInLedger(
            srcPoolId,
            dstPoolId,
            to,
            feeInfo,
            creditInfo,
            IBCUtils.ExternalInfo("", 0)
        );
    }

    // withdraw on the src side.(need to check the balance on the dst side and the amount of transfer and mint)
    function withdrawLocal(
        string calldata srcChannel,
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLP,
        bytes calldata to,
        address payable refundTo
    ) external payable nonReentrant {
        if (amountLP == 0) {
            revert TokiZeroAmount("amountLP");
        }
        if (refundTo == address(0x0)) {
            revert TokiZeroAddress("refundTo");
        }
        // to address must be 20 bytes because withdraw confirm is called on the src side.
        if (to.length != 20) {
            revert TokiInvalidRecipientBytes();
        }

        // call `withdrawLocal` and `sendCredit` on pool contract.
        // -> And call `withdrawCheck` on dst side.
        uint256 dstChainId = getChainId(srcChannel, true);

        (
            uint256 amountGD,
            IPool.CreditInfo memory creditInfo
        ) = _preWithdrawLocal(dstChainId, srcPoolId, dstPoolId, amountLP, to);

        // sent IBCUtils.TYPE_WITHDRAW
        bytes memory message = IBCUtils.encodeWithdraw(
            srcPoolId, // withdrawLocalPoolId
            dstPoolId, // withdrawCheckPoolId
            amountGD,
            creditInfo,
            to
        );
        _sendWithRefund(
            dstChainId,
            srcChannel,
            message,
            refundTo,
            MessageType._TYPE_WITHDRAW,
            IBCUtils.ExternalInfo("", 0),
            0
        );
    }

    function withdrawLocalInLedger(
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLP,
        address to
    ) external nonReentrant {
        if (amountLP == 0) {
            revert TokiZeroAmount("amountLP");
        }

        bytes memory bytesTo = IBCUtils.encodeAddress(to);
        (
            uint256 amountGD,
            IPool.CreditInfo memory creditInfo
        ) = _preWithdrawLocal(
                block.chainid,
                srcPoolId,
                dstPoolId,
                amountLP,
                bytesTo
            );

        // "Receiving" half. See TYPE_WITHDRAW and TYPE_WITHDRAW_CHECK case in onRecvPacket().
        _receiveWithdrawLocalInLedger(
            srcPoolId,
            dstPoolId,
            to,
            amountGD,
            creditInfo
        );
    }

    // Withdraw by POOL alone. Withdrawal amount may be a restricted amount.
    function withdrawInstant(
        uint256 srcPoolId,
        uint256 amountLP,
        address to
    ) external nonReentrant returns (uint256 amountGD) {
        // call `withdrawInstant` on pool contract.
        if (amountLP == 0) {
            revert TokiZeroAmount("amountLP");
        }

        IPool pool = getPool(srcPoolId);
        amountGD = pool.withdrawInstant(msg.sender, amountLP, to);
    }

    // Decode payloads by BridgePacketData type and route to target processing in target pool
    // Only IBCHandler can call this function
    function onRecvPacket(
        Packet calldata packet,
        address /* relayer */
    )
        external
        override
        onlyRole(IBC_HANDLER_ROLE)
        nonReentrant
        returns (bytes memory acknowledgement)
    {
        uint8 messageType = IBCUtils.parseType(packet.data);
        if (messageType == MessageType._TYPE_TRANSFER_POOL) {
            IBCUtils.TransferPoolPayload memory p = IBCUtils.decodeTransferPool(
                packet.data
            );
            _updateCredit(
                packet.destinationChannel,
                p.dstPoolId,
                p.srcPoolId,
                p.creditInfo
            );

            (address recipient, bool success) = IBCUtils.decodeAddress(p.to);
            if (success) {
                _receivePool(
                    packet.destinationChannel,
                    packet.sequence,
                    p.srcPoolId,
                    p.dstPoolId,
                    recipient,
                    p.feeInfo,
                    p.refuelAmount,
                    p.externalInfo,
                    ReceiveOption(true, 0)
                );
            } else {
                _handlePoolRecvFailure(
                    packet.destinationChannel,
                    p.srcPoolId,
                    p.dstPoolId,
                    p.feeInfo
                );
                emit Unrecoverable(
                    getChainId(packet.destinationChannel, false),
                    packet.sequence
                );
            }
        } else if (messageType == MessageType._TYPE_CREDIT) {
            IBCUtils.SendCreditPayload memory p = IBCUtils.decodeCredit(
                packet.data
            );
            _updateCredit(
                packet.destinationChannel,
                p.dstPoolId,
                p.srcPoolId,
                p.creditInfo
            );
        } else if (messageType == MessageType._TYPE_WITHDRAW) {
            IBCUtils.WithdrawPayload memory p = IBCUtils.decodeWithdraw(
                packet.data
            );
            _updateCredit(
                packet.destinationChannel,
                p.withdrawCheckPoolId,
                p.withdrawLocalPoolId,
                p.creditInfo
            );

            _withdrawCheck(
                packet.destinationChannel,
                p.withdrawLocalPoolId,
                p.withdrawCheckPoolId,
                p.amountGD,
                p.to
            );
        } else if (messageType == MessageType._TYPE_WITHDRAW_CHECK) {
            IBCUtils.WithdrawCheckPayload memory p = IBCUtils
                .decodeWithdrawCheck(packet.data);
            _updateCredit(
                packet.destinationChannel,
                p.withdrawLocalPoolId, // self
                p.withdrawCheckPoolId, // peer
                p.creditInfo
            );

            // p.to length is validated in withdrawLocal, so most cases should be successful.
            (address recipient, bool success) = IBCUtils.decodeAddress(p.to);
            if (success) {
                _withdrawConfirm(
                    packet.destinationChannel,
                    packet.sequence,
                    p.withdrawLocalPoolId,
                    p.withdrawCheckPoolId,
                    recipient,
                    p.transferAmountGD,
                    p.mintAmountGD,
                    ReceiveOption(true, 0)
                );
            } else {
                _handlePoolWithdrawConfirmFailure(
                    packet.destinationChannel,
                    p.withdrawLocalPoolId,
                    p.withdrawCheckPoolId,
                    p.transferAmountGD,
                    p.mintAmountGD
                );
                emit Unrecoverable(
                    getChainId(packet.destinationChannel, false),
                    packet.sequence
                );
            }
        } else if (messageType == MessageType._TYPE_TRANSFER_TOKEN) {
            IBCUtils.TransferTokenPayload memory p = IBCUtils
                .decodeTransferToken(packet.data);
            (address recipient, bool success) = IBCUtils.decodeAddress(p.to);
            if (success) {
                _receiveToken(
                    packet.destinationChannel,
                    packet.sequence,
                    p.denom,
                    p.amount,
                    recipient,
                    p.refuelAmount,
                    p.externalInfo,
                    0
                );
            } else {
                // for now, we don't have a failure handle case for token transfer

                emit Unrecoverable(
                    getChainId(packet.destinationChannel, false),
                    packet.sequence
                );
            }
        } else {
            revert TokiInvalidPacketType(messageType);
        }

        acknowledgement = new bytes(0);
    }

    // solhint-disable ordering
    function onChanOpenInit(
        IIBCModuleInitializer.MsgOnChanOpenInit calldata msg_
    )
        external
        view
        override
        onlyRole(IBC_HANDLER_ROLE)
        returns (address, string memory version)
    {
        if (msg_.order != Channel.Order.ORDER_ORDERED) {
            revert TokiRequireOrderedChannel();
        }
        bytes memory versionBytes = bytes(msg_.version);
        version = _version();
        if (
            versionBytes.length != 0 &&
            keccak256(versionBytes) != keccak256(bytes(version))
        ) {
            revert TokiInvalidProposedVersion(msg_.version);
        }
        return (address(this), version);
    }

    function onChanOpenTry(
        IIBCModuleInitializer.MsgOnChanOpenTry calldata msg_
    )
        external
        view
        override
        onlyRole(IBC_HANDLER_ROLE)
        returns (address, string memory)
    {
        if (msg_.order != Channel.Order.ORDER_ORDERED) {
            revert TokiRequireOrderedChannel();
        }
        if (
            keccak256(bytes(msg_.counterpartyVersion)) !=
            keccak256(bytes(_version()))
        ) {
            revert TokiInvalidProposedVersion(msg_.counterpartyVersion);
        }
        return (address(this), msg_.counterpartyVersion);
    }

    function onChanOpenAck(
        IIBCModule.MsgOnChanOpenAck calldata msg_
    ) external override onlyRole(IBC_HANDLER_ROLE) {
        if (
            keccak256(bytes(msg_.counterpartyVersion)) !=
            keccak256(bytes(_version()))
        ) {
            revert TokiInvalidProposedVersion(msg_.counterpartyVersion);
        }

        BridgeStorage storage $ = getBridgeStorage();
        // APP_VERSION is checked at OnChanOpenInit()
        $.channelInfos[msg_.channelId].appVersion = APP_VERSION;
    }

    function onChanOpenConfirm(
        IIBCModule.MsgOnChanOpenConfirm calldata msg_
    ) external override onlyRole(IBC_HANDLER_ROLE) {
        BridgeStorage storage $ = getBridgeStorage();
        // APP_VERSION is checked at OnChanOpenAck()
        $.channelInfos[msg_.channelId].appVersion = APP_VERSION;
    }
    // solhint-enable ordering

    // solhint-disable-next-line no-unused-vars
    function onChanCloseInit(
        IIBCModule.MsgOnChanCloseInit calldata /* msg_ */
    ) external pure override {
        revert TokiCannotCloseChannel();
    }

    function onTimeoutPacket(Packet calldata, address) external pure override {
        revert TokiCannotTimeoutPacket();
    }

    /**
     * IBCAppBase
     */

    function ibcAddress() public view override returns (address) {
        BridgeStorage storage $ = getBridgeStorage();
        return address($.ics04SendPacket);
    }

    // currently, we use this just for yui-ibc-solidity
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(IBCAppBase, AccessControlUpgradeable)
        returns (bool)
    {
        return
            IBCAppBase.supportsInterface(interfaceId) ||
            interfaceId == type(IIBCModuleUpgrade).interfaceId ||
            interfaceId == type(IIBCChannelUpgradableModule).interfaceId;
    }

    function _outServiceCallCoreInLedger(
        address token,
        uint256 amount,
        address to,
        IBCUtils.ExternalInfo memory externalInfo
    ) internal {
        // In local ledger call, user can decide gas amount of outer call.
        if (0 < externalInfo.dstOuterGas) {
            revert TokiDstOuterGasShouldBeZero();
        }

        if (externalInfo.payload.length > 0) {
            ITokiOuterServiceReceiver(to).onReceivePool(
                "",
                token,
                amount,
                externalInfo.payload
            );
        }
    }

    function _receivePoolInLedger(
        uint256 srcPoolId,
        uint256 dstPoolId,
        address to,
        ITransferPoolFeeCalculator.FeeInfo memory feeInfo,
        IPool.CreditInfo memory creditInfo,
        IBCUtils.ExternalInfo memory externalInfo
    ) internal {
        IPool dstPool = getPool(dstPoolId);

        // _updateCredit
        dstPool.updateCredit(block.chainid, srcPoolId, creditInfo);

        // _receivePool
        (uint256 recvAmountLD, bool isTransferred) = dstPool.recv(
            block.chainid,
            srcPoolId,
            to,
            feeInfo,
            true
        );

        if (!isTransferred) {
            revert TokiPoolRecvIsFailed(dstPoolId);
        }
        _outServiceCallCoreInLedger(
            dstPool.token(),
            recvAmountLD,
            to,
            externalInfo
        );
    }

    function _receiveWithdrawLocalInLedger(
        uint256 withdrawLocalPoolId,
        uint256 withdrawCheckPoolId,
        address to,
        uint256 amountGD,
        IPool.CreditInfo memory creditInfo
    ) internal {
        IPool withdrawCheckPool = getPool(withdrawCheckPoolId);
        IPool withdrawLocalPool = getPool(withdrawLocalPoolId);

        // TYPE_WITHDRAW
        withdrawCheckPool.updateCredit(
            block.chainid,
            withdrawLocalPoolId,
            creditInfo
        );

        // solhint-disable-next-line no-unused-vars
        (uint256 _amountSwap, uint256 mintAmountGD) = withdrawCheckPool
            .withdrawCheck(block.chainid, withdrawLocalPoolId, amountGD);
        IPool.CreditInfo memory checkedCreditInfo = withdrawCheckPool
            .sendCredit(block.chainid, withdrawLocalPoolId);

        // TYPE_WITHDRAW_CHECK
        withdrawLocalPool.updateCredit(
            block.chainid,
            withdrawCheckPoolId,
            checkedCreditInfo
        );

        bool isTransferred = withdrawLocalPool.withdrawConfirm(
            block.chainid,
            withdrawCheckPoolId,
            to,
            amountGD,
            mintAmountGD,
            true
        );

        if (!isTransferred) {
            revert TokiPoolWithdrawConfirmIsFailed(withdrawLocalPoolId);
        }
    }

    function _sendTransferPool(SendTransferPoolParam memory p) internal {
        // send IBCUtils.TYPE_TRANSFER_POOL
        bytes memory message = IBCUtils.encodeTransferPool(
            p.srcPoolId,
            p.dstPoolId,
            p.feeInfo,
            p.creditInfo,
            p.to,
            p.refuelAmount,
            p.externalInfo // for composability
        );

        _sendWithRefund(
            p.dstChainId,
            p.srcChannel,
            message,
            p.refundTo,
            MessageType._TYPE_TRANSFER_POOL,
            p.externalInfo,
            p.refuelAmount
        );
    }

    function _preTransferPool(
        uint256 dstChainId,
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLD,
        uint256 minAmountLD
    )
        internal
        returns (
            ITransferPoolFeeCalculator.FeeInfo memory retFeeInfo,
            IPool.CreditInfo memory retCreditInfo
        )
    {
        IPool srcPool = getPool(srcPoolId);
        uint256 convertRate = srcPool.convertRate();
        amountLD = _roundDownToConvertRate(amountLD, convertRate);

        retFeeInfo = srcPool.transfer(
            dstChainId,
            dstPoolId,
            msg.sender,
            amountLD,
            minAmountLD,
            true
        );
        IBCUtils.safeTransferFrom(
            srcPool.token(),
            msg.sender,
            address(srcPool),
            amountLD
        );
        retCreditInfo = srcPool.sendCredit(dstChainId, dstPoolId);
    }

    function _preWithdrawLocal(
        uint256 dstChainId,
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLP,
        bytes memory to
    )
        internal
        returns (uint256 retAmountGD, IPool.CreditInfo memory retCreditInfo)
    {
        IPool srcPool = getPool(srcPoolId);
        retAmountGD = srcPool.withdrawLocal(
            dstChainId,
            dstPoolId,
            msg.sender,
            amountLP,
            to
        );
        retCreditInfo = srcPool.sendCredit(dstChainId, dstPoolId);
    }

    // After transfer, LPToken is burned and credit is sent.
    function _preWithdrawRemote(
        uint256 dstChainId,
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 amountLP,
        uint256 minAmountLD
    )
        internal
        returns (
            ITransferPoolFeeCalculator.FeeInfo memory retFeeInfo,
            IPool.CreditInfo memory retCreditInfo
        )
    {
        IPool srcPool = getPool(srcPoolId);
        uint256 amountLD = srcPool.LPToLD(amountLP);

        retFeeInfo = srcPool.transfer(
            dstChainId,
            dstPoolId,
            msg.sender,
            amountLD,
            minAmountLD,
            false
        );
        srcPool.withdrawRemote(dstChainId, dstPoolId, msg.sender, amountLP);
        retCreditInfo = srcPool.sendCredit(dstChainId, dstPoolId);
    }

    // On the dst side, check the balance for src, transfer, and return the amount of mint.
    // <- Receive from `withdrawLocal` on the src side.
    // -> And call `withdrawConfirm` on dst side.
    // only IBCHandler can call this function.
    function _withdrawCheck(
        string memory dstChannel,
        uint256 withdrawLocalPoolId,
        uint256 withdrawCheckPoolId, // me
        uint256 amountGD,
        bytes memory to // src(counterparty)
    ) internal {
        // <- Receive from `withdrawLocal` on the src side.
        // call `withdrawCheck` and `updateCredit` on pool contract.
        // -> And call `withdrawConfirm` on dst side.
        uint256 srcChainId = getChainId(dstChannel, true);
        IPool pool = getPool(withdrawCheckPoolId);
        // first try catch the swap remote
        (uint256 amountSwapGD, uint256 amountMintGD) = pool.withdrawCheck(
            srcChainId,
            withdrawLocalPoolId,
            amountGD
        );
        IPool.CreditInfo memory creditInfo = pool.sendCredit(
            srcChainId,
            withdrawLocalPoolId
        );
        // send IBCUtils.TYPE_WITHDRAW_CHECK
        bytes memory message = IBCUtils.encodeWithdrawCheck(
            withdrawLocalPoolId,
            withdrawCheckPoolId,
            amountSwapGD,
            amountMintGD,
            creditInfo,
            to
        );
        _send(dstChannel, message);
    }

    function _handlePoolRecvFailure(
        string memory dstChannel,
        uint256 srcPoolId,
        uint256 dstPoolId,
        ITransferPoolFeeCalculator.FeeInfo memory fee
    ) internal {
        uint256 srcChainId = getChainId(dstChannel, true);
        IPool pool = getPool(dstPoolId);
        pool.handleRecvFailure(srcChainId, srcPoolId, address(0), fee);
    }

    function _handlePoolWithdrawConfirmFailure(
        string memory dstChannel,
        uint256 withdrawLocalPoolId,
        uint256 withdrawCheckPoolId,
        uint256 amountGD,
        uint256 mintAmountGD
    ) internal {
        uint256 srcChainId = getChainId(dstChannel, true);
        IPool pool = getPool(withdrawLocalPoolId); // self
        pool.handleWithdrawConfirmFailure(
            srcChainId,
            withdrawCheckPoolId,
            address(0),
            amountGD,
            mintAmountGD
        );
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function _contextSuffixLength()
        internal
        view
        override(Context, ContextUpgradeable)
        returns (uint256)
    {
        return ContextUpgradeable._contextSuffixLength();
    }

    function _msgData()
        internal
        view
        override(Context, ContextUpgradeable)
        returns (bytes calldata)
    {
        return ContextUpgradeable._msgData();
    }

    function _msgSender()
        internal
        view
        override(Context, ContextUpgradeable)
        returns (address)
    {
        return ContextUpgradeable._msgSender();
    }

    function _version() internal view returns (string memory) {
        return string(abi.encodePacked("toki-", Strings.toString(APP_VERSION)));
    }

    function _roundDownToConvertRate(
        uint256 amount,
        uint256 convertRate
    ) internal pure returns (uint256) {
        // Note about slither-disable:
        //   It's ok because the aim of this statement is to round amountLD.
        // slither-disable-next-line divide-before-multiply
        return (amount / convertRate) * convertRate;
    }

    function _validateToLength(bytes calldata to) internal pure {
        if (to.length == 0) {
            revert TokiInvalidRecipientBytes();
        }
        if (to.length > MAX_TO_LENGTH) {
            revert TokiExceed("to", to.length, MAX_TO_LENGTH);
        }
    }

    function _validatePayloadLength(bytes calldata payload) internal pure {
        if (payload.length > MAX_PAYLOAD_LENGTH) {
            revert TokiExceed("payload", payload.length, MAX_PAYLOAD_LENGTH);
        }
    }

    function _isChannelUpgradeSelector(
        bytes4 selector
    ) internal pure returns (bool) {
        if (
            selector ==
            IBCChannelUpgradableModuleBase.getUpgradeProposal.selector ||
            selector ==
            IBCChannelUpgradableModuleBase.proposeUpgrade.selector ||
            selector ==
            IBCChannelUpgradableModuleBase
                .allowTransitionToFlushComplete
                .selector ||
            selector ==
            IBCChannelUpgradableModuleBase.removeUpgradeProposal.selector ||
            selector ==
            IBCChannelUpgradableModuleBase.isAuthorizedUpgrader.selector ||
            selector ==
            IBCChannelUpgradableModuleBase
                .canTransitionToFlushComplete
                .selector ||
            selector ==
            IBCChannelUpgradableModuleBase.getUpgradeTimeout.selector ||
            selector ==
            IBCChannelUpgradableModuleBase.onChanUpgradeInit.selector ||
            selector ==
            IBCChannelUpgradableModuleBase.onChanUpgradeTry.selector ||
            selector ==
            IBCChannelUpgradableModuleBase.onChanUpgradeAck.selector ||
            selector ==
            IBCChannelUpgradableModuleBase.onChanUpgradeOpen.selector
        ) {
            return true;
        }
        return false;
    }
}
