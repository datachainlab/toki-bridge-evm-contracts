// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

// original: https://github.com/hyperledger-labs/yui-ibc-solidity/blob/v0.3.38/tests/foundry/src/ICS04Upgrade.t.sol

import "@hyperledger-labs/yui-ibc-solidity/tests/foundry/src/helpers/IBCTestHelper.t.sol";
import {Upgrade, UpgradeFields, Timeout} from "@hyperledger-labs/yui-ibc-solidity/contracts/proto/Channel.sol";
import {LocalhostClientLib} from "@hyperledger-labs/yui-ibc-solidity/contracts/clients/09-localhost/LocalhostClient.sol";
import {LocalhostHelper} from "@hyperledger-labs/yui-ibc-solidity/contracts/clients/09-localhost/LocalhostHelper.sol";
import {IIBCChannelUpgradeBase} from "@hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IIBCChannelUpgrade.sol";
import {ICS04UpgradeTestHelper} from "@hyperledger-labs/yui-ibc-solidity/tests/foundry/src/helpers/ICS04UpgradeTestHelper.t.sol";
import {ICS04PacketEventTestHelper} from "@hyperledger-labs/yui-ibc-solidity/tests/foundry/src/helpers/ICS04PacketTestHelper.t.sol";
import {IIBCChannelUpgradableModule} from "@hyperledger-labs/yui-ibc-solidity/contracts/apps/commons/IBCChannelUpgradableModule.sol";

/* solhint-disable ordering */
contract ICS04UpgradeBase is
    ICS04UpgradeTestHelper,
    ICS04PacketEventTestHelper
{
    using LocalhostHelper for TestableIBCHandler;

    struct ChannelInfo {
        string connectionId;
        string portId;
        string channelId;
    }

    TestableIBCHandler public ibcHandler;

    // ------------------------------ Internal Functions ------------------------------ //

    struct UpgradeProposals {
        UpgradeProposal p0;
        UpgradeProposal p1;
    }

    struct UpgradeProposal {
        Channel.Order order;
        string connectionId;
        string version;
        Timeout.Data timeout;
    }

    function validProposals(
        Channel.Order order,
        string memory channel0ConnectionId,
        string memory channel1ConnectionId,
        string memory appVersion
    ) internal view returns (UpgradeProposals memory) {
        return
            UpgradeProposals({
                p0: UpgradeProposal({
                    order: order,
                    connectionId: channel0ConnectionId,
                    version: appVersion,
                    timeout: Timeout.Data({
                        height: H(getBlockNumber(1)),
                        timestamp: 0
                    })
                }),
                p1: UpgradeProposal({
                    order: order,
                    connectionId: channel1ConnectionId,
                    version: appVersion,
                    timeout: Timeout.Data({
                        height: H(getBlockNumber(1)),
                        timestamp: 0
                    })
                })
            });
    }

    struct HandshakeFlow {
        bool crossingHello;
        bool fastPath;
    }

    struct HandshakeUpgradeWithCallbacksArgs {
        ChannelInfo channel0;
        ChannelInfo channel1;
        UpgradeProposals proposals;
        HandshakeFlow flow;
        HandshakeCallbacks callbacks;
    }
    function handshakeUpgradeWithCallbacks(
        HandshakeUpgradeWithCallbacksArgs memory args
    ) internal returns (uint64 upgradeSequence) {
        Channel.Order currentOrder;
        {
            (Channel.Data memory channelData0, ) = ibcHandler.getChannel(
                args.channel0.portId,
                args.channel0.channelId
            );
            (Channel.Data memory channelData1, ) = ibcHandler.getChannel(
                args.channel1.portId,
                args.channel1.channelId
            );
            require(
                channelData0.upgrade_sequence == channelData1.upgrade_sequence,
                "upgrade sequence mismatch"
            );
            require(
                channelData0.ordering == channelData1.ordering,
                "ordering mismatch"
            );
            currentOrder = channelData0.ordering;
            upgradeSequence = channelData0.upgrade_sequence + 1;
        }

        {
            // Init@channel0: OPEN -> OPEN(INIT)
            IIBCChannelUpgradableModule(
                address(ibcHandler.getIBCModuleByPort(args.channel0.portId))
            ).proposeUpgrade(
                    args.channel0.portId,
                    args.channel0.channelId,
                    UpgradeFields.Data({
                        ordering: args.proposals.p0.order,
                        connection_hops: IBCChannelLib.buildConnectionHops(
                            args.proposals.p0.connectionId
                        ),
                        version: args.proposals.p0.version
                    }),
                    args.proposals.p0.timeout
                );
            assertEq(
                ibcHandler.channelUpgradeInit(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeInit({
                        portId: args.channel0.portId,
                        channelId: args.channel0.channelId,
                        proposedUpgradeFields: IIBCChannelUpgradableModule(
                            address(
                                ibcHandler.getIBCModuleByPort(
                                    args.channel0.portId
                                )
                            )
                        )
                            .getUpgradeProposal(
                                args.channel0.portId,
                                args.channel0.channelId
                            )
                            .fields
                    })
                ),
                upgradeSequence
            );
            ensureChannelState(
                ibcHandler,
                args.channel0,
                Channel.State.STATE_OPEN
            );
            if (!args.callbacks.openInitAndOpen.reverse) {
                if (
                    !args.callbacks.openInitAndOpen.callback(
                        ibcHandler,
                        args.channel0,
                        args.channel1
                    )
                ) {
                    return upgradeSequence;
                }
            } else {
                if (
                    !args.callbacks.openInitAndOpen.callback(
                        ibcHandler,
                        args.channel1,
                        args.channel0
                    )
                ) {
                    return upgradeSequence;
                }
            }
        }

        IIBCChannelUpgradableModule(
            address(ibcHandler.getIBCModuleByPort(args.channel1.portId))
        ).proposeUpgrade(
                args.channel1.portId,
                args.channel1.channelId,
                UpgradeFields.Data({
                    ordering: args.proposals.p1.order,
                    connection_hops: IBCChannelLib.buildConnectionHops(
                        args.proposals.p1.connectionId
                    ),
                    version: args.proposals.p1.version
                }),
                args.proposals.p1.timeout
            );

        if (args.flow.crossingHello) {
            // Init@channel1: OPEN -> OPEN(INIT)
            assertEq(
                ibcHandler.channelUpgradeInit(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeInit({
                        portId: args.channel1.portId,
                        channelId: args.channel1.channelId,
                        proposedUpgradeFields: IIBCChannelUpgradableModule(
                            address(
                                ibcHandler.getIBCModuleByPort(
                                    args.channel1.portId
                                )
                            )
                        )
                            .getUpgradeProposal(
                                args.channel1.portId,
                                args.channel1.channelId
                            )
                            .fields
                    })
                ),
                upgradeSequence
            );
        }

        {
            // Try@channel1: OPEN(INIT) -> FLUSHING
            IIBCChannelUpgradeBase.MsgChannelUpgradeTry
                memory msg_ = IIBCChannelUpgradeBase.MsgChannelUpgradeTry({
                    portId: args.channel1.portId,
                    channelId: args.channel1.channelId,
                    counterpartyUpgradeFields: IIBCChannelUpgradableModule(
                        address(
                            ibcHandler.getIBCModuleByPort(args.channel0.portId)
                        )
                    )
                        .getUpgradeProposal(
                            args.channel0.portId,
                            args.channel0.channelId
                        )
                        .fields,
                    counterpartyUpgradeSequence: upgradeSequence,
                    proposedConnectionHops: IBCChannelLib.buildConnectionHops(
                        args.proposals.p1.connectionId
                    ),
                    proofs: upgradeLocalhostProofs()
                });

            (bool ok, uint64 seq) = ibcHandler.channelUpgradeTry(msg_);
            assertTrue(ok);
            assertEq(seq, upgradeSequence);
            ensureChannelState(
                ibcHandler,
                args.channel1,
                Channel.State.STATE_FLUSHING
            );

            if (!args.callbacks.openInitAndFlushing.reverse) {
                if (
                    !args.callbacks.openInitAndFlushing.callback(
                        ibcHandler,
                        args.channel0,
                        args.channel1
                    )
                ) {
                    return upgradeSequence;
                }
            } else {
                if (
                    !args.callbacks.openInitAndFlushing.callback(
                        ibcHandler,
                        args.channel1,
                        args.channel0
                    )
                ) {
                    return upgradeSequence;
                }
            }
        }

        bool skipFlushCompleteAuthorization = false;
        {
            bool channel0SequenceMatch = ibcHandler.getNextSequenceSend(
                args.channel0.portId,
                args.channel0.channelId
            ) ==
                ibcHandler.getNextSequenceAck(
                    args.channel0.portId,
                    args.channel0.channelId
                );
            bool channel1SequenceMatch = ibcHandler.getNextSequenceSend(
                args.channel1.portId,
                args.channel1.channelId
            ) ==
                ibcHandler.getNextSequenceAck(
                    args.channel1.portId,
                    args.channel1.channelId
                );
            // If the channel is ORDERED and the all packets have been acknowledged, we can use the fast path to upgrade
            skipFlushCompleteAuthorization =
                currentOrder == Channel.Order.ORDER_ORDERED &&
                channel0SequenceMatch &&
                channel1SequenceMatch;
        }

        if (args.flow.fastPath && !skipFlushCompleteAuthorization) {
            // Ack@channel0: OPEN(INIT) -> FLUSHING
            assertTrue(
                ibcHandler.channelUpgradeAck(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeAck({
                        portId: args.channel0.portId,
                        channelId: args.channel0.channelId,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            args.channel1.portId,
                            args.channel1.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );

            ensureChannelState(
                ibcHandler,
                args.channel0,
                Channel.State.STATE_FLUSHING
            );
            assertFalse(
                ibcHandler.getCanTransitionToFlushComplete(
                    args.channel0.portId,
                    args.channel0.channelId
                )
            );
            assertFalse(
                ibcHandler.getCanTransitionToFlushComplete(
                    args.channel1.portId,
                    args.channel1.channelId
                )
            );
            IIBCChannelUpgradableModule(
                address(ibcHandler.getIBCModuleByPort(args.channel0.portId))
            ).allowTransitionToFlushComplete(
                    args.channel0.portId,
                    args.channel0.channelId,
                    upgradeSequence
                );
            assertTrue(
                ibcHandler.getCanTransitionToFlushComplete(
                    args.channel0.portId,
                    args.channel0.channelId
                )
            );
            IIBCChannelUpgradableModule(
                address(ibcHandler.getIBCModuleByPort(args.channel1.portId))
            ).allowTransitionToFlushComplete(
                    args.channel1.portId,
                    args.channel1.channelId,
                    upgradeSequence
                );
            assertTrue(
                ibcHandler.getCanTransitionToFlushComplete(
                    args.channel1.portId,
                    args.channel1.channelId
                )
            );
        }

        if (skipFlushCompleteAuthorization || args.flow.fastPath) {
            // Ack@channel0: OPEN(INIT) or FLUSHING -> FLUSHCOMPLETE
            assertTrue(
                ibcHandler.channelUpgradeAck(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeAck({
                        portId: args.channel0.portId,
                        channelId: args.channel0.channelId,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            args.channel1.portId,
                            args.channel1.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(
                ibcHandler,
                args.channel0,
                Channel.State.STATE_FLUSHCOMPLETE
            );

            // Confirm@channel1: FLUSHING -> OPEN
            assertTrue(
                ibcHandler.channelUpgradeConfirm(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeConfirm({
                        portId: args.channel1.portId,
                        channelId: args.channel1.channelId,
                        counterpartyChannelState: Channel
                            .State
                            .STATE_FLUSHCOMPLETE,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            args.channel0.portId,
                            args.channel0.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(
                ibcHandler,
                args.channel1,
                Channel.State.STATE_OPEN
            );

            // Open@channel0: FLUSHCOMPLETE -> OPEN
            ibcHandler.channelUpgradeOpen(
                IIBCChannelUpgradeBase.MsgChannelUpgradeOpen({
                    portId: args.channel0.portId,
                    channelId: args.channel0.channelId,
                    counterpartyChannelState: Channel.State.STATE_OPEN,
                    counterpartyUpgradeSequence: upgradeSequence,
                    proofChannel: LocalhostClientLib.sentinelProof(),
                    proofHeight: H(getBlockNumber())
                })
            );
            ensureChannelState(
                ibcHandler,
                args.channel0,
                Channel.State.STATE_OPEN
            );
        } else if (
            currentOrder == Channel.Order.ORDER_ORDERED &&
            ibcHandler.getNextSequenceSend(
                args.channel0.portId,
                args.channel0.channelId
            ) !=
            ibcHandler.getNextSequenceAck(
                args.channel0.portId,
                args.channel0.channelId
            )
        ) {
            // Ack@channel0: OPEN(INIT) -> FLUSHING
            assertTrue(
                ibcHandler.channelUpgradeAck(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeAck({
                        portId: args.channel0.portId,
                        channelId: args.channel0.channelId,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            args.channel1.portId,
                            args.channel1.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(
                ibcHandler,
                args.channel0,
                Channel.State.STATE_FLUSHING
            );

            assertFalse(
                ibcHandler.getCanTransitionToFlushComplete(
                    args.channel0.portId,
                    args.channel0.channelId
                )
            );
            IIBCChannelUpgradableModule(
                address(ibcHandler.getIBCModuleByPort(args.channel0.portId))
            ).allowTransitionToFlushComplete(
                    args.channel0.portId,
                    args.channel0.channelId,
                    upgradeSequence
                );
            assertTrue(
                ibcHandler.getCanTransitionToFlushComplete(
                    args.channel0.portId,
                    args.channel0.channelId
                )
            );
            // Confirm@channel0: FLUSHING -> FLUSHCOMPLETE
            assertTrue(
                ibcHandler.channelUpgradeConfirm(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeConfirm({
                        portId: args.channel0.portId,
                        channelId: args.channel0.channelId,
                        counterpartyChannelState: Channel.State.STATE_FLUSHING,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            args.channel1.portId,
                            args.channel1.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(
                ibcHandler,
                args.channel0,
                Channel.State.STATE_FLUSHCOMPLETE
            );

            // Confirm@channel1: FLUSHING -> OPEN
            assertTrue(
                ibcHandler.channelUpgradeConfirm(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeConfirm({
                        portId: args.channel1.portId,
                        channelId: args.channel1.channelId,
                        counterpartyChannelState: Channel
                            .State
                            .STATE_FLUSHCOMPLETE,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            args.channel0.portId,
                            args.channel0.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(
                ibcHandler,
                args.channel1,
                Channel.State.STATE_OPEN
            );

            // Open@channel0: FLUSHCOMPLETE -> OPEN
            ibcHandler.channelUpgradeOpen(
                IIBCChannelUpgradeBase.MsgChannelUpgradeOpen({
                    portId: args.channel0.portId,
                    channelId: args.channel0.channelId,
                    counterpartyChannelState: Channel.State.STATE_OPEN,
                    counterpartyUpgradeSequence: upgradeSequence,
                    proofChannel: LocalhostClientLib.sentinelProof(),
                    proofHeight: H(getBlockNumber())
                })
            );
            ensureChannelState(
                ibcHandler,
                args.channel0,
                Channel.State.STATE_OPEN
            );
        } else if (
            currentOrder == Channel.Order.ORDER_ORDERED &&
            ibcHandler.getNextSequenceSend(
                args.channel1.portId,
                args.channel1.channelId
            ) !=
            ibcHandler.getNextSequenceAck(
                args.channel1.portId,
                args.channel1.channelId
            )
        ) {
            // Ack@channel0: OPEN(INIT) -> FLUSHCOMPLETE
            assertTrue(
                ibcHandler.channelUpgradeAck(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeAck({
                        portId: args.channel0.portId,
                        channelId: args.channel0.channelId,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            args.channel1.portId,
                            args.channel1.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(
                ibcHandler,
                args.channel0,
                Channel.State.STATE_FLUSHCOMPLETE
            );

            assertFalse(
                ibcHandler.getCanTransitionToFlushComplete(
                    args.channel1.portId,
                    args.channel1.channelId
                )
            );
            IIBCChannelUpgradableModule(
                address(ibcHandler.getIBCModuleByPort(args.channel1.portId))
            ).allowTransitionToFlushComplete(
                    args.channel1.portId,
                    args.channel1.channelId,
                    upgradeSequence
                );
            assertTrue(
                ibcHandler.getCanTransitionToFlushComplete(
                    args.channel1.portId,
                    args.channel1.channelId
                )
            );
            // Confirm@channel1: FLUSHING -> OPEN
            assertTrue(
                ibcHandler.channelUpgradeConfirm(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeConfirm({
                        portId: args.channel1.portId,
                        channelId: args.channel1.channelId,
                        counterpartyChannelState: Channel
                            .State
                            .STATE_FLUSHCOMPLETE,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            args.channel0.portId,
                            args.channel0.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(
                ibcHandler,
                args.channel1,
                Channel.State.STATE_OPEN
            );

            // Open@channel0: FLUSHCOMPLETE -> OPEN
            ibcHandler.channelUpgradeOpen(
                IIBCChannelUpgradeBase.MsgChannelUpgradeOpen({
                    portId: args.channel0.portId,
                    channelId: args.channel0.channelId,
                    counterpartyChannelState: Channel.State.STATE_OPEN,
                    counterpartyUpgradeSequence: upgradeSequence,
                    proofChannel: LocalhostClientLib.sentinelProof(),
                    proofHeight: H(getBlockNumber())
                })
            );
            ensureChannelState(
                ibcHandler,
                args.channel0,
                Channel.State.STATE_OPEN
            );
        } else {
            // Ack@channel0: OPEN(INIT) -> FLUSHING
            assertTrue(
                ibcHandler.channelUpgradeAck(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeAck({
                        portId: args.channel0.portId,
                        channelId: args.channel0.channelId,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            args.channel1.portId,
                            args.channel1.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(
                ibcHandler,
                args.channel0,
                Channel.State.STATE_FLUSHING
            );
            if (!args.callbacks.flushingAndFlushing.reverse) {
                if (
                    !args.callbacks.flushingAndFlushing.callback(
                        ibcHandler,
                        args.channel0,
                        args.channel1
                    )
                ) {
                    return upgradeSequence;
                }
            } else {
                if (
                    !args.callbacks.flushingAndFlushing.callback(
                        ibcHandler,
                        args.channel1,
                        args.channel0
                    )
                ) {
                    return upgradeSequence;
                }
            }

            // Tx will be success but cannot transition to FLUSHCOMPLETE because `canTransitionToFlushComplete` returns false
            // Confirm@channel1: FLUSHING -> FLUSHING
            assertTrue(
                ibcHandler.channelUpgradeConfirm(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeConfirm({
                        portId: args.channel1.portId,
                        channelId: args.channel1.channelId,
                        counterpartyChannelState: Channel.State.STATE_FLUSHING,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            args.channel0.portId,
                            args.channel0.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(
                ibcHandler,
                args.channel1,
                Channel.State.STATE_FLUSHING
            );

            {
                (Channel.Data memory channel1Data, ) = ibcHandler.getChannel(
                    args.channel1.portId,
                    args.channel1.channelId
                );
                // Confirm@channel1: FLUSHING -> FLUSHCOMPLETE
                assertFalse(
                    ibcHandler.getCanTransitionToFlushComplete(
                        args.channel1.portId,
                        args.channel1.channelId
                    )
                );
                IIBCChannelUpgradableModule(
                    address(ibcHandler.getIBCModuleByPort(args.channel1.portId))
                ).allowTransitionToFlushComplete(
                        args.channel1.portId,
                        args.channel1.channelId,
                        upgradeSequence
                    );
                assertTrue(
                    ibcHandler.getCanTransitionToFlushComplete(
                        args.channel1.portId,
                        args.channel1.channelId
                    )
                );
                assertTrue(
                    ibcHandler.channelUpgradeConfirm(
                        IIBCChannelUpgradeBase.MsgChannelUpgradeConfirm({
                            portId: args.channel1.portId,
                            channelId: args.channel1.channelId,
                            counterpartyChannelState: Channel
                                .State
                                .STATE_FLUSHING,
                            counterpartyUpgrade: getCounterpartyUpgrade(
                                args.channel0.portId,
                                args.channel0.channelId
                            ),
                            proofs: upgradeLocalhostProofs()
                        })
                    )
                );
                ensureChannelState(
                    ibcHandler,
                    args.channel1,
                    Channel.State.STATE_FLUSHCOMPLETE
                );
                if (!args.callbacks.flushingAndComplete.reverse) {
                    if (
                        !args.callbacks.flushingAndComplete.callback(
                            ibcHandler,
                            args.channel0,
                            args.channel1
                        )
                    ) {
                        return upgradeSequence;
                    }
                } else {
                    if (
                        !args.callbacks.flushingAndComplete.callback(
                            ibcHandler,
                            args.channel1,
                            args.channel0
                        )
                    ) {
                        return upgradeSequence;
                    }
                }

                assertFalse(
                    ibcHandler.getCanTransitionToFlushComplete(
                        args.channel0.portId,
                        args.channel0.channelId
                    )
                );
                IIBCChannelUpgradableModule(
                    address(ibcHandler.getIBCModuleByPort(args.channel0.portId))
                ).allowTransitionToFlushComplete(
                        args.channel0.portId,
                        args.channel0.channelId,
                        upgradeSequence
                    );
                assertTrue(
                    ibcHandler.getCanTransitionToFlushComplete(
                        args.channel0.portId,
                        args.channel0.channelId
                    )
                );
                mockCallVerifyChannelState(
                    address(LocalhostHelper.getLocalhostClient(ibcHandler)),
                    args.channel1,
                    channel1Data
                );
                // Confirm@channel0: FLUSHING -> FLUSHCOMPLETE
                ibcHandler.channelUpgradeConfirm(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeConfirm({
                        portId: args.channel0.portId,
                        channelId: args.channel0.channelId,
                        counterpartyChannelState: Channel.State.STATE_FLUSHING,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            args.channel1.portId,
                            args.channel1.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                );
                vm.clearMockedCalls();
            }

            if (!args.callbacks.completeAndComplete.reverse) {
                if (
                    !args.callbacks.completeAndComplete.callback(
                        ibcHandler,
                        args.channel0,
                        args.channel1
                    )
                ) {
                    return upgradeSequence;
                }
            } else {
                if (
                    !args.callbacks.completeAndComplete.callback(
                        ibcHandler,
                        args.channel1,
                        args.channel0
                    )
                ) {
                    return upgradeSequence;
                }
            }
            // Open@channel0: FLUSHCOMPLETE -> OPEN
            ibcHandler.channelUpgradeOpen(
                IIBCChannelUpgradeBase.MsgChannelUpgradeOpen({
                    portId: args.channel0.portId,
                    channelId: args.channel0.channelId,
                    counterpartyChannelState: Channel.State.STATE_FLUSHCOMPLETE,
                    counterpartyUpgradeSequence: upgradeSequence,
                    proofChannel: LocalhostClientLib.sentinelProof(),
                    proofHeight: H(getBlockNumber())
                })
            );
            ensureChannelState(
                ibcHandler,
                args.channel0,
                Channel.State.STATE_OPEN
            );
            if (!args.callbacks.openSucAndComplete.reverse) {
                if (
                    !args.callbacks.openSucAndComplete.callback(
                        ibcHandler,
                        args.channel0,
                        args.channel1
                    )
                ) {
                    return upgradeSequence;
                }
            } else {
                if (
                    !args.callbacks.openSucAndComplete.callback(
                        ibcHandler,
                        args.channel1,
                        args.channel0
                    )
                ) {
                    return upgradeSequence;
                }
            }

            {
                (Channel.Data memory ch0, ) = ibcHandler.getChannel(
                    args.channel0.portId,
                    args.channel0.channelId
                );
                // Open@channel1: FLUSHCOMPLETE -> OPEN
                ibcHandler.channelUpgradeOpen(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeOpen({
                        portId: args.channel1.portId,
                        channelId: args.channel1.channelId,
                        counterpartyChannelState: ch0.state,
                        counterpartyUpgradeSequence: ch0.upgrade_sequence,
                        proofChannel: LocalhostClientLib.sentinelProof(),
                        proofHeight: H(getBlockNumber())
                    })
                );
            }
            ensureChannelState(
                ibcHandler,
                args.channel1,
                Channel.State.STATE_OPEN
            );
            if (!args.callbacks.openSucAndOpenSuc.reverse) {
                if (
                    !args.callbacks.openSucAndOpenSuc.callback(
                        ibcHandler,
                        args.channel0,
                        args.channel1
                    )
                ) {
                    return upgradeSequence;
                }
            } else {
                if (
                    !args.callbacks.openSucAndOpenSuc.callback(
                        ibcHandler,
                        args.channel1,
                        args.channel0
                    )
                ) {
                    return upgradeSequence;
                }
            }
        }
    }

    function createMockAppLocalhostChannel(
        Channel.Order ordering,
        string memory portId0,
        string memory portId1,
        string memory version
    ) internal returns (ChannelInfo memory, ChannelInfo memory) {
        (string memory connectionId0, string memory connectionId1) = ibcHandler
            .createLocalhostConnection();
        (string memory channelId0, string memory channelId1) = ibcHandler
            .createLocalhostChannel(
                LocalhostHelper.MsgCreateChannel({
                    connectionId0: connectionId0,
                    connectionId1: connectionId1,
                    portId0: portId0,
                    portId1: portId1,
                    ordering: ordering,
                    version: version
                })
            );
        return (
            ChannelInfo({
                connectionId: connectionId0,
                portId: portId0,
                channelId: channelId0
            }),
            ChannelInfo({
                connectionId: connectionId1,
                portId: portId1,
                channelId: channelId1
            })
        );
    }

    function ensureChannelState(
        IIBCHandler handler,
        ChannelInfo memory channel,
        Channel.State state
    ) internal {
        assertEq(
            uint8(getChannelState(handler, channel)),
            uint8(state),
            "channel state mismatch"
        );
    }

    function getChannelState(
        IIBCHandler handler,
        ChannelInfo memory channel
    ) internal view returns (Channel.State) {
        (Channel.Data memory channelData, bool found) = handler.getChannel(
            channel.portId,
            channel.channelId
        );
        require(found, "channel not found");
        return channelData.state;
    }

    function getCounterpartyUpgrade(
        string memory portId,
        string memory channelId
    ) private view returns (Upgrade.Data memory) {
        IIBCChannelUpgradableModule module = IIBCChannelUpgradableModule(
            address(ibcHandler.getIBCModuleByPort(portId))
        );
        return
            Upgrade.Data({
                fields: module.getUpgradeProposal(portId, channelId).fields,
                timeout: module.getUpgradeProposal(portId, channelId).timeout,
                next_sequence_send: ibcHandler.getNextSequenceSend(
                    portId,
                    channelId
                )
            });
    }

    function upgradeLocalhostProofs()
        private
        view
        returns (IIBCChannelUpgradeBase.ChannelUpgradeProofs memory)
    {
        return
            IIBCChannelUpgradeBase.ChannelUpgradeProofs({
                proofChannel: LocalhostClientLib.sentinelProof(),
                proofUpgrade: LocalhostClientLib.sentinelProof(),
                proofHeight: H(getBlockNumber())
            });
    }

    function mockCallVerifyChannelState(
        address client,
        ChannelInfo memory counterpartyChannelInfo,
        Channel.Data memory counterpartyChannel
    ) internal {
        vm.mockCall(
            address(client),
            abi.encodeWithSelector(
                ILightClient.verifyMembership.selector,
                LocalhostClientLib.CLIENT_ID,
                H(getBlockNumber()),
                0,
                0,
                LocalhostClientLib.sentinelProof(),
                bytes("ibc"),
                IBCCommitment.channelPath(
                    counterpartyChannelInfo.portId,
                    counterpartyChannelInfo.channelId
                ),
                Channel.encode(counterpartyChannel)
            ),
            abi.encode(true)
        );
    }

    // ------------------------------ Handshake Callbacks ------------------------------ //

    struct HandshakeCallbacks {
        HandshakeCallback openInitAndOpen;
        HandshakeCallback openInitAndFlushing;
        HandshakeCallback flushingAndFlushing;
        HandshakeCallback flushingAndComplete;
        HandshakeCallback completeAndComplete;
        HandshakeCallback openSucAndComplete;
        HandshakeCallback openSucAndOpenSuc;
    }

    struct HandshakeCallback {
        function(
            IIBCHandler,
            ChannelInfo memory,
            ChannelInfo memory
        ) returns (bool) callback;
        bool reverse;
    }

    function noopCallback(
        IIBCHandler,
        ChannelInfo memory,
        ChannelInfo memory
    ) internal pure returns (bool) {
        return true;
    }

    function emptyCallbacks()
        internal
        pure
        returns (HandshakeCallbacks memory)
    {
        return
            HandshakeCallbacks({
                openInitAndOpen: HandshakeCallback(noopCallback, false),
                openInitAndFlushing: HandshakeCallback(noopCallback, false),
                flushingAndFlushing: HandshakeCallback(noopCallback, false),
                flushingAndComplete: HandshakeCallback(noopCallback, false),
                completeAndComplete: HandshakeCallback(noopCallback, false),
                openSucAndComplete: HandshakeCallback(noopCallback, false),
                openSucAndOpenSuc: HandshakeCallback(noopCallback, false)
            });
    }
}
/* solhint-enable ordering */
