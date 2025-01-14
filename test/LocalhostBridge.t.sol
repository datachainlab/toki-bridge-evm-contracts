// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Test.sol";

import {LocalhostTestSetup} from "./LocalhostTestSetup.sol";
import {Packet} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IIBCChannel.sol";

import "../src/library/MessageType.sol";
import "../src/library/IBCUtils.sol";
import "../src/interfaces/IPool.sol";
import "../src/Bridge.sol";
import "../src/mocks/MockOuterService.sol";
import "./LargeBytesGenerator.sol";

contract LocalhostBridgeTest is LocalhostTestSetup {
    struct RecvFailureData {
        uint256 totalLiquidity;
        uint256 eqFeePool;
        uint256 feeBalance;
        uint256 lastKnownBalance;
    }

    struct WithdrawConfirmFailureData {
        uint256 lastKnownBalance;
    }

    function setUp() public override {
        super.setUp();
    }

    // ====================== success test cases(router func) =============================
    function testDepositAndCredit() public {
        vm.recordLogs();

        LocalhostChain storage src = _chains[0];
        uint256 srcPoolIndex = 0;
        uint256 srcPoolId = src.pools[srcPoolIndex].poolId;

        LocalhostChain storage dst = _chains[1];
        uint256 dstPoolId = _chains[1].pools[1].poolId;

        // initial state
        uint256[3] memory thisBalance0 = [
            src.pools[srcPoolIndex].erc20.balanceOf(address(this)),
            src.pools[srcPoolIndex].pool.balanceOf(address(this)),
            src.token.token.balanceOf(address(this))
        ];
        {
            IPool.PeerPoolInfo memory info = src
                .pools[srcPoolIndex]
                .pool
                .getPeerPoolInfo(dst.chainId, dstPoolId);
            assertEq(0, info.credits, "0-0 credits");
            assertEq(0, info.balance, "0-0 balance");

            IPool.PeerPoolInfo[][] memory rev = getReversePeerPoolInfos(
                src.chainId,
                srcPoolId
            );
            assertEq(0, rev[1][1].credits, "0-1 credits");
            assertEq(0, rev[1][1].balance, "0-1 balance");
        }

        // Mint token and then deposit all amount. Alice has 100 liquidity token.
        src.pools[srcPoolIndex].erc20.mint(address(this), 100);
        src.bridge.deposit(srcPoolId, 100, _alice);
        {
            uint256[3] memory thisBalance = [
                src.pools[srcPoolIndex].erc20.balanceOf(address(this)),
                src.pools[srcPoolIndex].pool.balanceOf(address(this)),
                src.token.token.balanceOf(address(this))
            ];
            uint256[3] memory aliceBalance = [
                src.pools[srcPoolIndex].erc20.balanceOf(_alice),
                src.pools[srcPoolIndex].pool.balanceOf(_alice),
                src.token.token.balanceOf(_alice)
            ];

            uint256 poolBalance = src.pools[srcPoolIndex].erc20.balanceOf(
                address(src.pools[srcPoolIndex].pool)
            );
            // bridge#deposit() does 1) transfer pooled token to pool, 2) mint pool token to dst
            assertEq(thisBalance0[0], thisBalance[0], "1-0 this balance"); //mint and deposit
            assertEq(100, poolBalance, "1-0 pools' erc20"); //deposit
            assertEq(100, aliceBalance[1], "1-0 alice's liquidity"); //deposit

            IPool.PeerPoolInfo memory info = src
                .pools[srcPoolIndex]
                .pool
                .getPeerPoolInfo(dst.chainId, dstPoolId);
            assertEq(33, info.credits, "1-1 credits");
            assertEq(0, info.balance, "1-1 balance");

            IPool.PeerPoolInfo[][] memory rev = getReversePeerPoolInfos(
                src.chainId,
                srcPoolId
            );
            assertEq(0, rev[1][1].credits, "1-2 credits");
            assertEq(0, rev[1][1].balance, "1-2 balance");
        }

        // Call sendCredit. Note that relaying is not performed yet.
        vm.chainId(src.chainId);
        src.bridge.sendCredit{value: 1 * 1e18}(
            src.channelInfo.channel,
            0,
            1,
            _alice
        );
        {
            IPool.PeerPoolInfo memory info = src
                .pools[srcPoolIndex]
                .pool
                .getPeerPoolInfo(dst.chainId, dstPoolId);
            assertEq(0, info.credits, "2-1 credits");
            assertEq(0, info.balance, "2-2 balance");

            IPool.PeerPoolInfo[][] memory rev = getReversePeerPoolInfos(
                src.chainId,
                srcPoolId
            );
            assertEq(0, rev[1][1].credits, "2-2 credits");
            assertEq(0, rev[1][1].balance, "2-2 balance");
        }

        // Relay sendCredit.
        relay(MessageType._TYPE_CREDIT, src.channelInfo, dst.chainId);
        {
            IPool.PeerPoolInfo memory info = src
                .pools[srcPoolIndex]
                .pool
                .getPeerPoolInfo(dst.chainId, dstPoolId);
            assertEq(0, info.credits, "3-1 credits");
            assertEq(0, info.balance, "3-1 balance");

            IPool.PeerPoolInfo[][] memory rev = getReversePeerPoolInfos(
                src.chainId,
                srcPoolId
            );
            assertEq(0, rev[1][1].credits, "3-2 credits");
            assertEq(33, rev[1][1].balance, "3-2 balance");
        }
    }

    function testTransferPool() public {
        uint8 srcChainIndex = 0;
        uint8 srcPoolIndex = 0;
        LocalhostChain storage src = _chains[srcChainIndex];
        LocalhostChainPool storage srcPool = src.pools[srcPoolIndex];
        uint256 srcDenom = 10 ** srcPool.pool.localDecimals();

        uint8 dstChainIndex = 1;
        uint8 dstPoolIndex = 1;
        LocalhostChain storage dst = _chains[dstChainIndex];
        LocalhostChainPool storage dstPool = dst.pools[dstPoolIndex];
        uint256 dstDenom = 10 ** dstPool.pool.localDecimals();

        uint256 srcAmount = 1000 * srcDenom * 2;
        uint256 dstDeposit = 1000 * dstDenom * 10;

        // 1. fill native token and pooled token
        {
            vm.deal(_alice, 1 ether);
            srcPool.erc20.mint(_alice, srcAmount);

            assertEq(
                srcAmount,
                srcPool.erc20.balanceOf(_alice),
                "1: Alice's token is filled"
            );
            assertEq(0, dstPool.erc20.balanceOf(_bob), "1: Bob has no token");
        }

        // 2. start localhost IBC testing
        vm.recordLogs();

        // 3. increase known balance of src pool about dst pool
        {
            deposit(
                dstChainIndex,
                dstPoolIndex,
                srcChainIndex,
                srcPoolIndex,
                dstDeposit,
                _dead
            );
        }

        // 4. call transferPool
        uint256 dstAmount;
        {
            ITransferPoolFeeCalculator.FeeInfo memory feeInfo = calcTransferFee(
                srcChainIndex,
                srcPoolIndex,
                dstChainIndex,
                dstPoolIndex,
                _alice,
                srcAmount
            );
            dstAmount = gdToLd(dstPool.pool, feeInfo.amountGD);
        }
        {
            vm.startPrank(_alice);

            srcPool.erc20.approve(address(src.bridge), srcAmount);
            IBCUtils.ExternalInfo memory extInfo = IBCUtils.ExternalInfo("", 0);
            vm.chainId(src.chainId);
            src.bridge.transferPool{value: 1 ether}(
                src.channelInfo.channel,
                srcPool.poolId,
                dstPool.poolId,
                srcAmount,
                0,
                addressToBytes(_bob),
                0,
                extInfo,
                _alice
            );
            vm.stopPrank();
        }

        // 5. Relay
        (Packet memory packet, ) = relay(
            MessageType._TYPE_TRANSFER_POOL,
            src.channelInfo,
            dst.chainId
        );

        // 6. retry
        {
            // check retry queue is consumed
            vm.chainId(dst.chainId);
            bytes memory payload = dst.bridge.revertReceive(
                src.chainId,
                packet.sequence
            );
            assertEq(0, payload.length, "6: no retry data");

            // check Pooled Token has been transferred
            assertEq(
                0,
                srcPool.erc20.balanceOf(_alice),
                "6: Alice's token is not change after retry"
            );
            assertEq(
                dstAmount,
                dstPool.erc20.balanceOf(_bob),
                "6: Bob received token"
            );
        }
    }

    function testWithdrawLocalInsufficientBalance() public {
        vm.recordLogs();

        LocalhostChain storage pro = _chains[0];
        uint256 proPoolIndex = 0;
        uint256 proPoolId = pro.pools[proPoolIndex].poolId;

        LocalhostChain storage rea = _chains[1];
        uint256 reaPoolId = _chains[1].pools[1].poolId;

        pro.pools[proPoolIndex].erc20.mint(address(this), 100);
        vm.chainId(pro.chainId);
        pro.bridge.deposit(proPoolId, 100, _alice);
        pro.bridge.sendCredit{value: 1 * 1e18}(
            pro.channelInfo.channel,
            0,
            1,
            _alice
        );

        relay(MessageType._TYPE_CREDIT, pro.channelInfo, rea.chainId);

        // initial state
        {
            uint256[3] memory aliceBalance = [
                pro.pools[proPoolIndex].erc20.balanceOf(_alice),
                pro.pools[proPoolIndex].pool.balanceOf(_alice),
                pro.token.token.balanceOf(_alice)
            ];
            assertEq(0, aliceBalance[0], "0: alice has no token");
            assertEq(100, aliceBalance[1], "0: alice has 100 liquidity");

            IPool.PeerPoolInfo[][] memory rev = getReversePeerPoolInfos(
                pro.chainId,
                proPoolId
            );
            assertEq(33, rev[1][1].balance, "0: (1,1)'s (0,0) balance");
        }

        // run as alice
        vm.deal(_alice, 1 ether);
        vm.startPrank(_alice);

        // Call withdrawLocal.
        vm.chainId(pro.chainId);
        pro.bridge.withdrawLocal{value: 1 * 1e18}(
            pro.channelInfo.channel,
            proPoolId,
            reaPoolId,
            100,
            addressToBytes(_alice),
            _alice
        );
        {
            uint256[3] memory aliceBalance = [
                pro.pools[proPoolIndex].erc20.balanceOf(_alice),
                pro.pools[proPoolIndex].pool.balanceOf(_alice),
                pro.token.token.balanceOf(_alice)
            ];
            assertEq(0, aliceBalance[0], "1: alice has no token");
            assertEq(0, aliceBalance[1], "1: alice has 0 liquidity");
        }

        (, Vm.Log[] memory withdrawLogs) = relay(
            MessageType._TYPE_WITHDRAW,
            pro.channelInfo,
            rea.chainId
        );

        {
            uint256[3] memory aliceBalance = [
                pro.pools[proPoolIndex].erc20.balanceOf(_alice),
                pro.pools[proPoolIndex].pool.balanceOf(_alice),
                pro.token.token.balanceOf(_alice)
            ];
            assertEq(0, aliceBalance[0], "2: alice has no token");
            assertEq(0, aliceBalance[1], "2: alice has 0 liquidity");

            IPool.PeerPoolInfo[][] memory rev = getReversePeerPoolInfos(
                pro.chainId,
                proPoolId
            );
            assertEq(
                0,
                rev[1][1].balance,
                "2: (1,1)'s (0,0) balance is decreased to 0"
            );
        }

        relay(
            MessageType._TYPE_WITHDRAW_CHECK,
            rea.channelInfo,
            pro.chainId,
            withdrawLogs
        );
        {
            uint256[3] memory aliceBalance = [
                pro.pools[proPoolIndex].erc20.balanceOf(_alice),
                pro.pools[proPoolIndex].pool.balanceOf(_alice),
                pro.token.token.balanceOf(_alice)
            ];
            assertEq(33, aliceBalance[0], "2: alice has 33 token");
            assertEq(67, aliceBalance[1], "2: alice refunded 67 liquidity");
        }

        vm.stopPrank();
    }

    // ====================== failure test cases =============================

    // Bridge allows the zero address as a recipient, but MockToken does not.
    function testTransferPoolRevertsWhenRecipientIsZeroAddress() public {
        uint8 srcChainIndex = 0;
        uint8 srcPoolIndex = 0;
        LocalhostChain storage src = _chains[srcChainIndex];
        LocalhostChainPool storage srcPool = src.pools[srcPoolIndex];
        uint256 srcDenom = 10 ** srcPool.pool.localDecimals();

        uint8 dstChainIndex = 1;
        uint8 dstPoolIndex = 1;
        LocalhostChain storage dst = _chains[dstChainIndex];
        LocalhostChainPool storage dstPool = dst.pools[dstPoolIndex];
        uint256 dstDenom = 10 ** dstPool.pool.localDecimals();

        uint256 srcAmount = 1000 * srcDenom * 2;
        uint256 dstDeposit = 1000 * dstDenom * 10;

        // 1. fill native token and pooled token
        {
            vm.deal(_alice, 1 ether);
            srcPool.erc20.mint(_alice, srcAmount);

            assertEq(
                srcAmount,
                srcPool.erc20.balanceOf(_alice),
                "1: Alice's token is filled"
            );
            assertEq(
                0,
                dstPool.erc20.balanceOf(address(0)),
                "1: address(0) has no token"
            );
        }

        // 2. start localhost IBC testing
        vm.recordLogs();

        // 3. increase known balance of src pool about dst pool
        {
            deposit(
                dstChainIndex,
                dstPoolIndex,
                srcChainIndex,
                srcPoolIndex,
                dstDeposit,
                _dead
            );
        }

        // 4. call transferPool
        uint256 dstAmount;
        {
            ITransferPoolFeeCalculator.FeeInfo memory feeInfo = calcTransferFee(
                srcChainIndex,
                srcPoolIndex,
                dstChainIndex,
                dstPoolIndex,
                _alice,
                srcAmount
            );
            dstAmount = gdToLd(dstPool.pool, feeInfo.amountGD);
        }
        {
            vm.startPrank(_alice);

            srcPool.erc20.approve(address(src.bridge), srcAmount);
            IBCUtils.ExternalInfo memory extInfo = IBCUtils.ExternalInfo("", 0);
            vm.chainId(src.chainId);
            src.bridge.transferPool{value: 1 ether}(
                src.channelInfo.channel,
                srcPool.poolId,
                dstPool.poolId,
                srcAmount,
                0,
                addressToBytes(address(0)),
                0,
                extInfo,
                _alice
            );
            vm.stopPrank();
        }

        // 5. Relay
        (Packet memory packet, ) = relay(
            MessageType._TYPE_TRANSFER_POOL,
            src.channelInfo,
            dst.chainId
        );

        // 6. check
        {
            // RetryReceiveToken is queued
            vm.chainId(dst.chainId);
            bytes memory payload = dst.bridge.revertReceive(
                src.chainId,
                packet.sequence
            );
            assertTrue(0 < payload.length, "6: retry data should be exists");

            {
                // escape from stack too deep
                IBCUtils.RetryReceivePoolPayload memory p = IBCUtils
                    .decodeRetryReceivePool(payload);
                assertEq(
                    IBCUtils._TYPE_RETRY_RECEIVE_POOL,
                    p.ftype,
                    "6: retry data is type of RECEIVE_POOL"
                );
            }
            assertEq(
                0,
                srcPool.erc20.balanceOf(_alice),
                "6: Alice's token should be consumed"
            );
            assertEq(
                0,
                dstPool.erc20.balanceOf(address(0)),
                "6: address(0) has not received token yet"
            );
        }
    }

    // dstOutGas is too low to call outer service
    function testTransferPoolRevertsWhenOutOfGas() public {
        uint8 srcChainIndex = 0;
        uint8 srcPoolIndex = 0;
        LocalhostChain storage src = _chains[srcChainIndex];
        LocalhostChainPool storage srcPool = src.pools[srcPoolIndex];
        uint256 srcDenom = 10 ** srcPool.pool.localDecimals();

        uint8 dstChainIndex = 1;
        uint8 dstPoolIndex = 1;
        LocalhostChain storage dst = _chains[dstChainIndex];
        LocalhostChainPool storage dstPool = dst.pools[dstPoolIndex];
        uint256 dstDenom = 10 ** dstPool.pool.localDecimals();

        uint256 srcAmount = 1000 * srcDenom * 2;
        uint256 dstDeposit = 1000 * dstDenom * 10;

        vm.chainId(dst.chainId);
        MockOuterService dstOuter = new MockOuterService(dst.channelInfo.port);
        dstOuter.setUsesHighGas(true);

        vm.chainId(src.chainId);

        // 1. fill native token and pooled token
        {
            vm.deal(_alice, 1 ether);
            srcPool.erc20.mint(_alice, srcAmount);

            assertEq(
                srcAmount,
                srcPool.erc20.balanceOf(_alice),
                "1: Alice's token is filled"
            );
            assertEq(0, dstPool.erc20.balanceOf(_bob), "1: Bob has no token");
        }

        // 2. start localhost IBC testing
        vm.recordLogs();

        // 3. increase known balance of src pool about dst pool
        {
            deposit(
                dstChainIndex,
                dstPoolIndex,
                srcChainIndex,
                srcPoolIndex,
                dstDeposit,
                _dead
            );
        }

        // 4. call transferPool
        uint256 dstAmount;
        {
            ITransferPoolFeeCalculator.FeeInfo memory feeInfo = calcTransferFee(
                srcChainIndex,
                srcPoolIndex,
                dstChainIndex,
                dstPoolIndex,
                _alice,
                srcAmount
            );
            dstAmount = gdToLd(dstPool.pool, feeInfo.amountGD);
        }
        {
            vm.startPrank(_alice);

            srcPool.erc20.approve(address(src.bridge), srcAmount);
            // this will cause MockOuterService to run out of gas
            IBCUtils.ExternalInfo memory extInfo = IBCUtils.ExternalInfo(
                LargeBytesGenerator.generateLargeBytes(1),
                1_000_000
            );
            vm.chainId(src.chainId);
            src.bridge.transferPool{value: 1 ether}(
                src.channelInfo.channel,
                srcPool.poolId,
                dstPool.poolId,
                srcAmount,
                0,
                addressToBytes(address(dstOuter)),
                //addressToBytes(_bob),
                0,
                extInfo,
                _alice
            );
            vm.stopPrank();
        }

        // 5. Relay
        (Packet memory packet, ) = relay(
            MessageType._TYPE_TRANSFER_POOL,
            src.channelInfo,
            dst.chainId
        );

        // 6. retry
        {
            // check retry is added
            vm.chainId(dst.chainId);
            bytes memory payload = dst.bridge.revertReceive(
                src.chainId,
                packet.sequence
            );
            assertEq(
                IBCUtils.parseType(payload),
                IBCUtils._TYPE_RETRY_EXTERNAL_CALL,
                "6: retry data should be exists"
            );

            // check Pooled Token has been transferred
            assertEq(
                0,
                srcPool.erc20.balanceOf(_alice),
                "6: Alice's token is not change after retry"
            );
            assertEq(
                dstAmount,
                dstPool.erc20.balanceOf(address(dstOuter)),
                "6: Outer received token"
            );
        }
    }

    // lastKnownBalance should be updated
    function testTransferPoolRevertsWhenRecipientIsInvalidBytes() public {
        uint8 srcChainIndex = 0;
        uint8 srcPoolIndex = 0;
        LocalhostChain storage src = _chains[srcChainIndex];
        LocalhostChainPool storage srcPool = src.pools[srcPoolIndex];
        uint256 srcDenom = 10 ** srcPool.pool.localDecimals();

        uint8 dstChainIndex = 1;
        uint8 dstPoolIndex = 1;
        LocalhostChain storage dst = _chains[dstChainIndex];
        LocalhostChainPool storage dstPool = dst.pools[dstPoolIndex];
        uint256 dstDenom = 10 ** dstPool.pool.localDecimals();

        uint256 srcAmount = 1000 * srcDenom * 2;
        uint256 dstDeposit = 1000 * dstDenom * 10;

        // 1. fill native token and pooled token
        {
            vm.deal(_alice, 1 ether);
            srcPool.erc20.mint(_alice, srcAmount);

            assertEq(
                srcAmount,
                srcPool.erc20.balanceOf(_alice),
                "1: Alice's token is filled"
            );
            assertEq(
                0,
                dstPool.erc20.balanceOf(address(0)),
                "1: address(0) has no token"
            );
        }

        // 2. start localhost IBC testing
        vm.recordLogs();

        // 3. increase known balance of src pool about dst pool
        {
            deposit(
                dstChainIndex,
                dstPoolIndex,
                srcChainIndex,
                srcPoolIndex,
                dstDeposit,
                _dead
            );
        }

        // 4. call transferPool
        RecvFailureData memory expected;
        {
            ITransferPoolFeeCalculator.FeeInfo memory feeInfo = calcTransferFee(
                srcChainIndex,
                srcPoolIndex,
                dstChainIndex,
                dstPoolIndex,
                _alice,
                srcAmount
            );
            assertGt(feeInfo.lpFee, 0, "4: lpFee should be positive");
            assertGt(
                feeInfo.protocolFee,
                0,
                "4: protocolFee should be positive"
            );
            expected.totalLiquidity =
                dstPool.pool.totalLiquidity() +
                feeInfo.lpFee;
            expected.eqFeePool = dstPool.pool.eqFeePool() + feeInfo.eqFee;
            expected.feeBalance =
                dstPool.pool.feeBalance() +
                feeInfo.protocolFee;
            expected.lastKnownBalance =
                dstPool
                    .pool
                    .getPeerPoolInfo(srcPool.chainId, srcPool.poolId)
                    .lastKnownBalance -
                (ldToGd(srcPool.pool, srcAmount) -
                    feeInfo.lpFee +
                    feeInfo.eqReward);
        }
        {
            vm.startPrank(_alice);

            srcPool.erc20.approve(address(src.bridge), srcAmount);
            IBCUtils.ExternalInfo memory extInfo = IBCUtils.ExternalInfo("", 0);
            vm.chainId(src.chainId);
            src.bridge.transferPool{value: 1 ether}(
                src.channelInfo.channel,
                srcPool.poolId,
                dstPool.poolId,
                srcAmount,
                0,
                new bytes(1), // invalid
                0,
                extInfo,
                _alice
            );
            vm.stopPrank();
        }

        // 5. Relay and check
        {
            // this indicates that an unrecoverable error occurred
            vm.expectEmit(address(dst.bridge));
            emit Bridge.Unrecoverable(src.chainId, 1);
            (Packet memory packet, ) = relay(
                MessageType._TYPE_TRANSFER_POOL,
                src.channelInfo,
                dst.chainId
            );

            vm.chainId(dst.chainId);
            {
                bytes memory payload = dst.bridge.revertReceive(
                    src.chainId,
                    packet.sequence
                );
                assertEq(
                    0,
                    payload.length,
                    "6: retry data should not be exists"
                );
            }
        }

        // 6. handleRecvFailure check
        assertEq(
            expected.lastKnownBalance,
            dstPool
                .pool
                .getPeerPoolInfo(srcPool.chainId, srcPool.poolId)
                .lastKnownBalance,
            "6: dst pool's last known balance should be updated"
        );
        assertEq(
            expected.totalLiquidity,
            dstPool.pool.totalLiquidity(),
            "6: dst pool's total liquidity"
        );
        assertEq(
            expected.eqFeePool,
            dstPool.pool.eqFeePool(),
            "6: dst pool's eq fee pool"
        );
        assertEq(
            expected.feeBalance,
            dstPool.pool.feeBalance(),
            "6: dst pool's fee balance"
        );
    }

    function testWithdrawLocalRevertsWhenRecipientIsZeroAddress() public {
        vm.recordLogs();

        LocalhostChain storage pro = _chains[0];
        uint256 proPoolIndex = 0;
        uint256 proPoolId = pro.pools[proPoolIndex].poolId;

        LocalhostChain storage rea = _chains[1];
        uint256 reaPoolId = _chains[1].pools[1].poolId;

        pro.pools[proPoolIndex].erc20.mint(address(this), 100);
        vm.chainId(pro.chainId);
        pro.bridge.deposit(proPoolId, 100, _alice);
        pro.bridge.sendCredit{value: 1 * 1e18}(
            pro.channelInfo.channel,
            0,
            1,
            _alice
        );

        relay(MessageType._TYPE_CREDIT, pro.channelInfo, rea.chainId);

        // initial state
        {
            uint256[3] memory aliceBalance = [
                pro.pools[proPoolIndex].erc20.balanceOf(_alice),
                pro.pools[proPoolIndex].pool.balanceOf(_alice),
                pro.token.token.balanceOf(_alice)
            ];
            assertEq(0, aliceBalance[0], "0: alice has no token");
            assertEq(100, aliceBalance[1], "0: alice has 100 liquidity");

            IPool.PeerPoolInfo[][] memory rev = getReversePeerPoolInfos(
                pro.chainId,
                proPoolId
            );
            assertEq(33, rev[1][1].balance, "0: (1,1)'s (0,0) balance");
        }

        // run as alice
        vm.deal(_alice, 1 ether);
        vm.startPrank(_alice);

        // Call withdrawLocal.
        WithdrawConfirmFailureData memory expected;
        {
            expected.lastKnownBalance =
                pro
                    .pools[proPoolIndex]
                    .pool
                    .getPeerPoolInfo(rea.chainId, reaPoolId)
                    .lastKnownBalance -
                33;
        }
        vm.chainId(pro.chainId);
        pro.bridge.withdrawLocal{value: 1 * 1e18}(
            pro.channelInfo.channel,
            proPoolId,
            reaPoolId,
            100,
            IBCUtils.encodeAddress(address(0)),
            _alice
        );
        {
            uint256[3] memory aliceBalance = [
                pro.pools[proPoolIndex].erc20.balanceOf(_alice),
                pro.pools[proPoolIndex].pool.balanceOf(_alice),
                pro.token.token.balanceOf(_alice)
            ];
            assertEq(0, aliceBalance[0], "1: alice has no token");
            assertEq(0, aliceBalance[1], "1: alice has 0 liquidity");
        }

        (, Vm.Log[] memory withdrawLogs) = relay(
            MessageType._TYPE_WITHDRAW,
            pro.channelInfo,
            rea.chainId
        );

        {
            uint256[3] memory aliceBalance = [
                pro.pools[proPoolIndex].erc20.balanceOf(_alice),
                pro.pools[proPoolIndex].pool.balanceOf(_alice),
                pro.token.token.balanceOf(_alice)
            ];
            assertEq(0, aliceBalance[0], "2: alice has no token");
            assertEq(0, aliceBalance[1], "2: alice has 0 liquidity");

            IPool.PeerPoolInfo[][] memory rev = getReversePeerPoolInfos(
                pro.chainId,
                proPoolId
            );
            assertEq(
                0,
                rev[1][1].balance,
                "2: (1,1)'s (0,0) balance is decreased to 0"
            );
        }

        {
            (Packet memory packet, ) = relay(
                MessageType._TYPE_WITHDRAW_CHECK,
                rea.channelInfo,
                pro.chainId,
                withdrawLogs
            );

            vm.chainId(pro.chainId);
            {
                bytes memory payload = pro.bridge.revertReceive(
                    rea.chainId,
                    packet.sequence
                );
                assertGt(payload.length, 0, "3: retry data should be exists");
            }
        }

        {
            uint256[3] memory aliceBalance = [
                pro.pools[proPoolIndex].erc20.balanceOf(_alice),
                pro.pools[proPoolIndex].pool.balanceOf(_alice),
                pro.token.token.balanceOf(_alice)
            ];
            // not re-minted because recipient is zero address
            assertEq(0, aliceBalance[0], "4: alice has 0 token");
            // refunded token is burned
            assertEq(0, aliceBalance[1], "4: alice refunded 0 liquidity");
        }
        {
            uint256 lastKnownBalance = pro
                .pools[proPoolIndex]
                .pool
                .getPeerPoolInfo(rea.chainId, reaPoolId)
                .lastKnownBalance;
            assertEq(
                expected.lastKnownBalance,
                lastKnownBalance,
                "4: last known balance should be updated"
            );
        }

        vm.stopPrank();
    }

    function getReversePeerPoolInfos(
        uint256 chainId,
        uint256 poolId
    ) internal view returns (IPool.PeerPoolInfo[][] memory) {
        IPool.PeerPoolInfo[][] memory ret = new IPool.PeerPoolInfo[][](2);
        for (uint8 i = 0; i < 2; i++) {
            IPool.PeerPoolInfo[] memory tmp = new IPool.PeerPoolInfo[](2);
            for (uint8 pi = 0; pi < 2; pi++) {
                if (_chains[i].chainId != chainId || pi != poolId) {
                    tmp[pi] = _chains[i].pools[pi].pool.getPeerPoolInfo(
                        chainId,
                        poolId
                    );
                }
            }
            ret[i] = tmp;
        }
        return ret;
    }
}
