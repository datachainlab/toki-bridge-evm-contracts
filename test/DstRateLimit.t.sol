// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Test.sol";

import {Packet} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IIBCChannel.sol";
import {LocalhostTestSetup} from "./LocalhostTestSetup.sol";

import "../src/Bridge.sol";
import "../src/library/MessageType.sol";
import "../src/library/IBCUtils.sol";
import "../src/interfaces/IBridge.sol";
import "../src/interfaces/IRelayerFeeCalculator.sol";
import "../src/StaticFlowRateLimiter.sol";
import "../src/Pool.sol";

contract FlowRateLimitUpgradeablePool is Pool {
    // for testing
    // keccak256(abi.encode(uint256(keccak256("toki.storage.StaticFlowRateLimiter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PARENT_STATIC_FLOW_RATE_LIMITER_LOCATION =
        0x0ee2d9de8392a8f17ff2bb7a24b72fd27e2cf4ac5cd7fd56e5bf7bdb439eb000;

    constructor(
        uint256 period,
        uint256 lockPeriod,
        uint256 limit,
        uint256 threshold
    ) Pool(period, lockPeriod, limit, threshold) {}

    // for testing
    function _getParentStorage()
        internal
        pure
        returns (StaticFlowRateLimiter.StaticFlowRateLimiterStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := PARENT_STATIC_FLOW_RATE_LIMITER_LOCATION
        }
    }
}

contract DstRateLimitTest is LocalhostTestSetup {
    // indices for _chains
    uint8 public constant SRC_CHAIN_INDEX = 0;
    uint8 public constant DST_CHAIN_INDEX = 1;

    uint8 public constant SRC_POOL_INDEX = 0;
    uint8 public constant DST_POOL_INDEX = 1;

    function setUp() public override {
        super.setUp();
    }

    function testTransferPoolFailRateLimit() public {
        LocalhostChain storage src = _chains[SRC_CHAIN_INDEX];
        LocalhostChainPool storage srcPool = src.pools[SRC_POOL_INDEX];
        uint256 srcDenom = 10 ** srcPool.pool.localDecimals();

        LocalhostChain storage dst = _chains[DST_CHAIN_INDEX];
        LocalhostChainPool storage dstPool = dst.pools[DST_POOL_INDEX];
        uint256 dstDenom = 10 ** dstPool.pool.localDecimals();

        uint256 srcAmount = 1000 * srcDenom * 2; //enough amount exceeds rate limit + transfer fee
        uint256 dstDeposit = 1000 * dstDenom * 10;
        uint256 dstLimit = 1000 * dstDenom; // below actual amount. actual amount is (srcAmount - fee).

        // 1. set lower limit on dst chain
        {
            address newImpl = address(
                new FlowRateLimitUpgradeablePool(1, 2, dstLimit - 1, 2)
            );
            dstPool.pool.upgradeToAndCall(newImpl, "");
        }

        // 2. fill native token and pooled token
        {
            vm.deal(_alice, 1 ether);
            srcPool.erc20.mint(_alice, srcAmount);

            assertEq(
                srcAmount,
                srcPool.erc20.balanceOf(_alice),
                "2: Alice's token is filled"
            );
            vm.chainId(dst.chainId);
            assertEq(0, dstPool.erc20.balanceOf(_bob), "2: Bob has no token");
        }

        // 3. start localhost IBC testing
        vm.recordLogs();

        // 3.1. increase known balance of src pool about dst pool
        {
            deposit(
                DST_CHAIN_INDEX,
                DST_POOL_INDEX,
                SRC_CHAIN_INDEX,
                SRC_POOL_INDEX,
                dstDeposit,
                _dead
            );
        }

        // 4. call transferPool with amount exceeds dst flow limit
        uint256 dstAmount;
        {
            ITransferPoolFeeCalculator.FeeInfo memory feeInfo = calcTransferFee(
                SRC_CHAIN_INDEX,
                SRC_POOL_INDEX,
                DST_CHAIN_INDEX,
                DST_POOL_INDEX,
                _alice,
                srcAmount
            );
            dstAmount = gdToLd(dstPool.pool, feeInfo.amountGD);
        }
        {
            vm.startPrank(_alice);

            srcPool.erc20.approve(address(src.bridge), srcAmount);
            vm.chainId(src.chainId);
            // avoid stack too deep
            src.bridge.transferPool{value: 1 ether}(
                src.channelInfo.channel,
                srcPool.poolId,
                dstPool.poolId,
                srcAmount,
                0,
                addressToBytes(_bob),
                0,
                IBCUtils.ExternalInfo("", 0),
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
                dstPool.erc20.balanceOf(_bob),
                "6: Bob has not received token yet"
            );
        }

        // 7. set enough limit on dst chain
        {
            address newImpl = address(
                new FlowRateLimitUpgradeablePool(1, 2, dstAmount, 2)
            );
            dstPool.pool.upgradeToAndCall(newImpl, "");
        }

        // 8. retry
        vm.chainId(dst.chainId);
        vm.prank(_alice); // Maybe retry is called by Alice
        dst.bridge.retryOnReceive(dst.channelInfo.channel, packet.sequence);
        {
            // check retry queue is consumed
            vm.chainId(dst.chainId);
            bytes memory payload = dst.bridge.revertReceive(
                src.chainId,
                packet.sequence
            );
            assertEq(0, payload.length, "8: no retry data");

            // check Pooled Token has been transferred
            assertEq(
                0,
                srcPool.erc20.balanceOf(_alice),
                "8: Alice's token is not change after retry"
            );
            assertEq(
                dstAmount,
                dstPool.erc20.balanceOf(_bob),
                "8: Bob received token"
            );
        }
    }

    function testWithdrawRemoteFailRateLimit() public {
        LocalhostChain storage src = _chains[SRC_CHAIN_INDEX];
        LocalhostChainPool storage srcPool = src.pools[SRC_POOL_INDEX];
        uint256 srcDenom = 10 ** srcPool.pool.localDecimals();

        LocalhostChain storage dst = _chains[DST_CHAIN_INDEX];
        LocalhostChainPool storage dstPool = dst.pools[DST_POOL_INDEX];
        uint256 dstDenom = 10 ** dstPool.pool.localDecimals();

        uint256 srcAmount = 1000 * srcDenom * 2; //enough amount exceeds rate limit + transfer fee
        uint256 dstDeposit = 1000 * dstDenom * 10;
        uint256 dstLimit = 1000 * dstDenom; // below actual amount. actual amount is (srcAmount - fee).

        // 1. set lower limit on dst chain
        {
            address newImpl = address(
                new FlowRateLimitUpgradeablePool(1, 2, dstLimit - 1, 2)
            );
            dstPool.pool.upgradeToAndCall(newImpl, "");
        }

        // 2. start localhost IBC testing
        vm.recordLogs();

        // 2.1. increase known balance of src pool about dst pool
        {
            deposit(
                DST_CHAIN_INDEX,
                DST_POOL_INDEX,
                SRC_CHAIN_INDEX,
                SRC_POOL_INDEX,
                dstDeposit,
                _dead
            );
        }

        // 3. fill native token and liquidity token
        {
            vm.deal(_alice, 1 ether);
            deposit(
                SRC_CHAIN_INDEX,
                SRC_POOL_INDEX,
                DST_CHAIN_INDEX,
                DST_POOL_INDEX,
                srcAmount,
                _alice
            );

            assertEq(
                srcAmount,
                srcPool.pool.balanceOf(_alice),
                "3: Alice's liquidity token is filled"
            );
            assertEq(0, dstPool.erc20.balanceOf(_bob), "3: Bob has no token");
        }

        // 4. call transferPool with amount exceeds dst flow limit
        uint256 dstAmount;
        {
            ITransferPoolFeeCalculator.FeeInfo memory feeInfo = calcTransferFee(
                SRC_CHAIN_INDEX,
                SRC_POOL_INDEX,
                DST_CHAIN_INDEX,
                DST_POOL_INDEX,
                _alice,
                srcAmount
            );
            dstAmount = gdToLd(dstPool.pool, feeInfo.amountGD);
        }
        {
            vm.startPrank(_alice);

            vm.chainId(src.chainId);
            src.bridge.withdrawRemote{value: 1 ether}(
                src.channelInfo.channel,
                srcPool.poolId,
                dstPool.poolId,
                srcAmount,
                0,
                addressToBytes(_bob),
                _alice
            );
            vm.stopPrank();
        }

        // 5. Relay
        (Packet memory packet, ) = relay(
            MessageType._TYPE_TRANSFER_POOL,
            src.channelInfo,
            dst.chainId
        ); // withdrawRemote sends TRANSFER_POOL

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
                srcPool.pool.balanceOf(_alice),
                "6: Alice's liquidity token should be consumed"
            );
            assertEq(
                0,
                dstPool.erc20.balanceOf(_bob),
                "6: Bob has not received token yet"
            );
        }

        // 7. set enough limit on dst chain
        {
            address newImpl = address(
                new FlowRateLimitUpgradeablePool(1, 2, dstAmount, 2)
            );
            dstPool.pool.upgradeToAndCall(newImpl, "");
        }

        // 8. retry
        vm.chainId(dst.chainId);
        vm.prank(_alice); // Maybe retry is called by Alice
        dst.bridge.retryOnReceive(dst.channelInfo.channel, packet.sequence);
        {
            // check retry queue is consumed
            vm.chainId(dst.chainId);
            bytes memory payload = dst.bridge.revertReceive(
                src.chainId,
                packet.sequence
            );
            assertEq(0, payload.length, "8: no retry data");

            // check Pooled Token has been transferred
            assertEq(
                0,
                srcPool.pool.balanceOf(_alice),
                "8: Alice's liquidity token is not change after retry"
            );
            assertEq(
                dstAmount,
                dstPool.erc20.balanceOf(_bob),
                "8: Bob received token"
            );
        }
    }

    function testWithdrawLocalFailRateLimit() public {
        uint8 proChainIndex = 0;
        uint8 proPoolIndex = 0;
        LocalhostChain storage pro = _chains[proChainIndex];
        LocalhostChainPool storage proPool = pro.pools[proPoolIndex];
        uint256 proDenom = 10 ** proPool.pool.localDecimals();

        uint8 reaChainIndex = 1;
        uint8 reaPoolIndex = 1;
        LocalhostChain storage rea = _chains[reaChainIndex];
        LocalhostChainPool storage reaPool = rea.pools[reaPoolIndex];

        uint256 srcAmount = 1000 * proDenom * 2; //enough amount exceeds rate limit + transfer fee
        uint256 srcDeposit = 1000 * proDenom * 10;
        uint256 failLimit = 100 * proDenom; // below actual amount. actual amount is (srcAmount - fee).
        uint256 dstAmount = srcAmount; // in withdrawLocal, no transfer fee is charged

        // 1. set lower limit on proactor chain
        {
            address newImpl = address(
                new FlowRateLimitUpgradeablePool(1, 2, failLimit, 2)
            );
            proPool.pool.upgradeToAndCall(newImpl, "");
        }

        // 2. start localhost IBC testing
        vm.recordLogs();

        // 2.1. increase known balance of each other
        {
            // reactor's knowledge is used to cap withdraw amount
            deposit(
                proChainIndex,
                proPoolIndex,
                reaChainIndex,
                reaPoolIndex,
                srcDeposit,
                _dead
            );
            // proactor's knowledge is used in calculating fee
            deposit(
                reaChainIndex,
                reaPoolIndex,
                proChainIndex,
                proPoolIndex,
                srcDeposit,
                _dead
            );
        }

        // 3. fill native token and liquidity token
        {
            vm.deal(_alice, 1 ether);
            deposit(
                proChainIndex,
                proPoolIndex,
                reaChainIndex,
                reaPoolIndex,
                srcAmount,
                _alice
            );

            assertEq(
                srcAmount,
                proPool.pool.balanceOf(_alice),
                "3: Alice's liquidity token is filled"
            );
            assertEq(0, proPool.erc20.balanceOf(_bob), "3: Bob has no token");
        }

        // 4. call withdrawLocal with amount exceeds dst flow limit
        {
            vm.startPrank(_alice);

            vm.chainId(pro.chainId);
            pro.bridge.withdrawLocal{value: 1 ether}(
                pro.channelInfo.channel,
                proPool.poolId,
                reaPool.poolId,
                srcAmount,
                addressToBytes(_bob),
                _alice
            );
            vm.stopPrank();
        }

        // 5. Relay
        (, Vm.Log[] memory withdrawLogs) = relay(
            MessageType._TYPE_WITHDRAW,
            pro.channelInfo,
            rea.chainId
        );
        (Packet memory packet2, ) = relay(
            MessageType._TYPE_WITHDRAW_CHECK,
            rea.channelInfo,
            pro.chainId,
            withdrawLogs
        );

        // 6. check
        {
            // RetryReceiveToken is queued
            vm.chainId(pro.chainId);
            bytes memory payload = pro.bridge.revertReceive(
                rea.chainId,
                packet2.sequence
            );
            assertTrue(0 < payload.length, "6: retry data should be exists");

            {
                // escape from stack too deep
                IBCUtils.RetryWithdrawConfirmPayload memory p = IBCUtils
                    .decodeRetryWithdrawConfirm(payload);
                assertEq(
                    IBCUtils._TYPE_RETRY_WITHDRAW_CONFIRM,
                    p.ftype,
                    "6: retry data is type of WITHDRAW_CONFIRM"
                );
            }
            assertEq(
                0,
                proPool.pool.balanceOf(_alice),
                "6: Alice's liquidity token should be consumed"
            );
            assertEq(
                0,
                proPool.erc20.balanceOf(_bob),
                "6: Bob has not received token yet"
            );
        }

        // 7. set enough limit on proactor chain
        {
            address newImpl = address(
                new FlowRateLimitUpgradeablePool(1, 2, dstAmount, 2)
            );
            proPool.pool.upgradeToAndCall(newImpl, "");
        }

        // 8. retry
        vm.chainId(pro.chainId);
        vm.prank(_alice); // Maybe retry is called by Alice
        pro.bridge.retryOnReceive(pro.channelInfo.channel, packet2.sequence);
        {
            // check retry queue is consumed
            vm.chainId(pro.chainId);
            bytes memory payload = pro.bridge.revertReceive(
                rea.chainId,
                packet2.sequence
            );
            assertEq(0, payload.length, "8: no retry data");

            // check Pooled Token has been transferred
            assertEq(
                0,
                proPool.pool.balanceOf(_alice),
                "8: Alice's liquidity token is not change after retry"
            );
            assertEq(
                dstAmount,
                proPool.erc20.balanceOf(_bob),
                "8: Bob received token"
            );
        }
    }
}
