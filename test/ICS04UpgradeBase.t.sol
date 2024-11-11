// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

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

    function handshakeUpgrade(
        ChannelInfo memory channel0,
        ChannelInfo memory channel1,
        UpgradeProposals memory proposals,
        HandshakeFlow memory flow
    ) internal returns (uint64) {
        return
            handshakeUpgradeWithCallbacks(
                channel0,
                channel1,
                proposals,
                flow,
                emptyCallbacks()
            );
    }

    function handshakeUpgradeWithCallbacks(
        ChannelInfo memory channel0,
        ChannelInfo memory channel1,
        UpgradeProposals memory proposals,
        HandshakeFlow memory flow,
        HandshakeCallbacks memory callbacks
    ) internal returns (uint64 upgradeSequence) {
        Channel.Order currentOrder;
        {
            (Channel.Data memory channelData0, ) = ibcHandler.getChannel(
                channel0.portId,
                channel0.channelId
            );
            (Channel.Data memory channelData1, ) = ibcHandler.getChannel(
                channel1.portId,
                channel1.channelId
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
                address(ibcHandler.getIBCModuleByPort(channel0.portId))
            ).proposeUpgrade(
                    channel0.portId,
                    channel0.channelId,
                    UpgradeFields.Data({
                        ordering: proposals.p0.order,
                        connection_hops: IBCChannelLib.buildConnectionHops(
                            proposals.p0.connectionId
                        ),
                        version: proposals.p0.version
                    }),
                    proposals.p0.timeout
                );
            assertEq(
                ibcHandler.channelUpgradeInit(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeInit({
                        portId: channel0.portId,
                        channelId: channel0.channelId,
                        proposedUpgradeFields: IIBCChannelUpgradableModule(
                            address(
                                ibcHandler.getIBCModuleByPort(channel0.portId)
                            )
                        )
                            .getUpgradeProposal(
                                channel0.portId,
                                channel0.channelId
                            )
                            .fields
                    })
                ),
                upgradeSequence
            );
            ensureChannelState(ibcHandler, channel0, Channel.State.STATE_OPEN);
            if (!callbacks.openInitAndOpen.reverse) {
                if (
                    !callbacks.openInitAndOpen.callback(
                        ibcHandler,
                        channel0,
                        channel1
                    )
                ) {
                    return upgradeSequence;
                }
            } else {
                if (
                    !callbacks.openInitAndOpen.callback(
                        ibcHandler,
                        channel1,
                        channel0
                    )
                ) {
                    return upgradeSequence;
                }
            }
        }

        IIBCChannelUpgradableModule(
            address(ibcHandler.getIBCModuleByPort(channel1.portId))
        ).proposeUpgrade(
                channel1.portId,
                channel1.channelId,
                UpgradeFields.Data({
                    ordering: proposals.p1.order,
                    connection_hops: IBCChannelLib.buildConnectionHops(
                        proposals.p1.connectionId
                    ),
                    version: proposals.p1.version
                }),
                proposals.p1.timeout
            );

        if (flow.crossingHello) {
            // Init@channel1: OPEN -> OPEN(INIT)
            assertEq(
                ibcHandler.channelUpgradeInit(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeInit({
                        portId: channel1.portId,
                        channelId: channel1.channelId,
                        proposedUpgradeFields: IIBCChannelUpgradableModule(
                            address(
                                ibcHandler.getIBCModuleByPort(channel1.portId)
                            )
                        )
                            .getUpgradeProposal(
                                channel1.portId,
                                channel1.channelId
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
                    portId: channel1.portId,
                    channelId: channel1.channelId,
                    counterpartyUpgradeFields: IIBCChannelUpgradableModule(
                        address(ibcHandler.getIBCModuleByPort(channel0.portId))
                    )
                        .getUpgradeProposal(channel0.portId, channel0.channelId)
                        .fields,
                    counterpartyUpgradeSequence: upgradeSequence,
                    proposedConnectionHops: IBCChannelLib.buildConnectionHops(
                        proposals.p1.connectionId
                    ),
                    proofs: upgradeLocalhostProofs()
                });
            (bool ok, uint64 seq) = ibcHandler.channelUpgradeTry(msg_);
            assertTrue(ok);
            assertEq(seq, upgradeSequence);
            ensureChannelState(
                ibcHandler,
                channel1,
                Channel.State.STATE_FLUSHING
            );
            if (!callbacks.openInitAndFlushing.reverse) {
                if (
                    !callbacks.openInitAndFlushing.callback(
                        ibcHandler,
                        channel0,
                        channel1
                    )
                ) {
                    return upgradeSequence;
                }
            } else {
                if (
                    !callbacks.openInitAndFlushing.callback(
                        ibcHandler,
                        channel1,
                        channel0
                    )
                ) {
                    return upgradeSequence;
                }
            }
        }

        bool skipFlushCompleteAuthorization = false;
        {
            bool channel0SequenceMatch = ibcHandler.getNextSequenceSend(
                channel0.portId,
                channel0.channelId
            ) ==
                ibcHandler.getNextSequenceAck(
                    channel0.portId,
                    channel0.channelId
                );
            bool channel1SequenceMatch = ibcHandler.getNextSequenceSend(
                channel1.portId,
                channel1.channelId
            ) ==
                ibcHandler.getNextSequenceAck(
                    channel1.portId,
                    channel1.channelId
                );
            // If the channel is ORDERED and the all packets have been acknowledged, we can use the fast path to upgrade
            skipFlushCompleteAuthorization =
                currentOrder == Channel.Order.ORDER_ORDERED &&
                channel0SequenceMatch &&
                channel1SequenceMatch;
        }

        if (flow.fastPath && !skipFlushCompleteAuthorization) {
            // Ack@channel0: OPEN(INIT) -> FLUSHING
            assertTrue(
                ibcHandler.channelUpgradeAck(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeAck({
                        portId: channel0.portId,
                        channelId: channel0.channelId,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            channel1.portId,
                            channel1.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(
                ibcHandler,
                channel0,
                Channel.State.STATE_FLUSHING
            );
            assertFalse(
                ibcHandler.getCanTransitionToFlushComplete(
                    channel0.portId,
                    channel0.channelId
                )
            );
            assertFalse(
                ibcHandler.getCanTransitionToFlushComplete(
                    channel1.portId,
                    channel1.channelId
                )
            );
            IIBCChannelUpgradableModule(
                address(ibcHandler.getIBCModuleByPort(channel0.portId))
            ).allowTransitionToFlushComplete(
                    channel0.portId,
                    channel0.channelId,
                    upgradeSequence
                );
            assertTrue(
                ibcHandler.getCanTransitionToFlushComplete(
                    channel0.portId,
                    channel0.channelId
                )
            );
            IIBCChannelUpgradableModule(
                address(ibcHandler.getIBCModuleByPort(channel1.portId))
            ).allowTransitionToFlushComplete(
                    channel1.portId,
                    channel1.channelId,
                    upgradeSequence
                );
            assertTrue(
                ibcHandler.getCanTransitionToFlushComplete(
                    channel1.portId,
                    channel1.channelId
                )
            );
        }
        if (skipFlushCompleteAuthorization || flow.fastPath) {
            // Ack@channel0: OPEN(INIT) or FLUSHING -> FLUSHCOMPLETE
            assertTrue(
                ibcHandler.channelUpgradeAck(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeAck({
                        portId: channel0.portId,
                        channelId: channel0.channelId,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            channel1.portId,
                            channel1.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(
                ibcHandler,
                channel0,
                Channel.State.STATE_FLUSHCOMPLETE
            );

            // Confirm@channel1: FLUSHING -> OPEN
            assertTrue(
                ibcHandler.channelUpgradeConfirm(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeConfirm({
                        portId: channel1.portId,
                        channelId: channel1.channelId,
                        counterpartyChannelState: Channel
                            .State
                            .STATE_FLUSHCOMPLETE,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            channel0.portId,
                            channel0.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(ibcHandler, channel1, Channel.State.STATE_OPEN);

            // Open@channel0: FLUSHCOMPLETE -> OPEN
            ibcHandler.channelUpgradeOpen(
                IIBCChannelUpgradeBase.MsgChannelUpgradeOpen({
                    portId: channel0.portId,
                    channelId: channel0.channelId,
                    counterpartyChannelState: Channel.State.STATE_OPEN,
                    counterpartyUpgradeSequence: upgradeSequence,
                    proofChannel: LocalhostClientLib.sentinelProof(),
                    proofHeight: H(getBlockNumber())
                })
            );
            ensureChannelState(ibcHandler, channel0, Channel.State.STATE_OPEN);
        } else if (
            currentOrder == Channel.Order.ORDER_ORDERED &&
            ibcHandler.getNextSequenceSend(
                channel0.portId,
                channel0.channelId
            ) !=
            ibcHandler.getNextSequenceAck(channel0.portId, channel0.channelId)
        ) {
            // Ack@channel0: OPEN(INIT) -> FLUSHING
            assertTrue(
                ibcHandler.channelUpgradeAck(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeAck({
                        portId: channel0.portId,
                        channelId: channel0.channelId,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            channel1.portId,
                            channel1.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(
                ibcHandler,
                channel0,
                Channel.State.STATE_FLUSHING
            );

            assertFalse(
                ibcHandler.getCanTransitionToFlushComplete(
                    channel0.portId,
                    channel0.channelId
                )
            );
            IIBCChannelUpgradableModule(
                address(ibcHandler.getIBCModuleByPort(channel0.portId))
            ).allowTransitionToFlushComplete(
                    channel0.portId,
                    channel0.channelId,
                    upgradeSequence
                );
            assertTrue(
                ibcHandler.getCanTransitionToFlushComplete(
                    channel0.portId,
                    channel0.channelId
                )
            );
            // Confirm@channel0: FLUSHING -> FLUSHCOMPLETE
            assertTrue(
                ibcHandler.channelUpgradeConfirm(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeConfirm({
                        portId: channel0.portId,
                        channelId: channel0.channelId,
                        counterpartyChannelState: Channel.State.STATE_FLUSHING,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            channel1.portId,
                            channel1.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(
                ibcHandler,
                channel0,
                Channel.State.STATE_FLUSHCOMPLETE
            );

            // Confirm@channel1: FLUSHING -> OPEN
            assertTrue(
                ibcHandler.channelUpgradeConfirm(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeConfirm({
                        portId: channel1.portId,
                        channelId: channel1.channelId,
                        counterpartyChannelState: Channel
                            .State
                            .STATE_FLUSHCOMPLETE,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            channel0.portId,
                            channel0.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(ibcHandler, channel1, Channel.State.STATE_OPEN);

            // Open@channel0: FLUSHCOMPLETE -> OPEN
            ibcHandler.channelUpgradeOpen(
                IIBCChannelUpgradeBase.MsgChannelUpgradeOpen({
                    portId: channel0.portId,
                    channelId: channel0.channelId,
                    counterpartyChannelState: Channel.State.STATE_OPEN,
                    counterpartyUpgradeSequence: upgradeSequence,
                    proofChannel: LocalhostClientLib.sentinelProof(),
                    proofHeight: H(getBlockNumber())
                })
            );
            ensureChannelState(ibcHandler, channel0, Channel.State.STATE_OPEN);
        } else if (
            currentOrder == Channel.Order.ORDER_ORDERED &&
            ibcHandler.getNextSequenceSend(
                channel1.portId,
                channel1.channelId
            ) !=
            ibcHandler.getNextSequenceAck(channel1.portId, channel1.channelId)
        ) {
            // Ack@channel0: OPEN(INIT) -> FLUSHCOMPLETE
            assertTrue(
                ibcHandler.channelUpgradeAck(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeAck({
                        portId: channel0.portId,
                        channelId: channel0.channelId,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            channel1.portId,
                            channel1.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(
                ibcHandler,
                channel0,
                Channel.State.STATE_FLUSHCOMPLETE
            );

            assertFalse(
                ibcHandler.getCanTransitionToFlushComplete(
                    channel1.portId,
                    channel1.channelId
                )
            );
            IIBCChannelUpgradableModule(
                address(ibcHandler.getIBCModuleByPort(channel1.portId))
            ).allowTransitionToFlushComplete(
                    channel1.portId,
                    channel1.channelId,
                    upgradeSequence
                );
            assertTrue(
                ibcHandler.getCanTransitionToFlushComplete(
                    channel1.portId,
                    channel1.channelId
                )
            );
            // Confirm@channel1: FLUSHING -> OPEN
            assertTrue(
                ibcHandler.channelUpgradeConfirm(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeConfirm({
                        portId: channel1.portId,
                        channelId: channel1.channelId,
                        counterpartyChannelState: Channel
                            .State
                            .STATE_FLUSHCOMPLETE,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            channel0.portId,
                            channel0.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(ibcHandler, channel1, Channel.State.STATE_OPEN);

            // Open@channel0: FLUSHCOMPLETE -> OPEN
            ibcHandler.channelUpgradeOpen(
                IIBCChannelUpgradeBase.MsgChannelUpgradeOpen({
                    portId: channel0.portId,
                    channelId: channel0.channelId,
                    counterpartyChannelState: Channel.State.STATE_OPEN,
                    counterpartyUpgradeSequence: upgradeSequence,
                    proofChannel: LocalhostClientLib.sentinelProof(),
                    proofHeight: H(getBlockNumber())
                })
            );
            ensureChannelState(ibcHandler, channel0, Channel.State.STATE_OPEN);
        } else {
            // Ack@channel0: OPEN(INIT) -> FLUSHING
            assertTrue(
                ibcHandler.channelUpgradeAck(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeAck({
                        portId: channel0.portId,
                        channelId: channel0.channelId,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            channel1.portId,
                            channel1.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(
                ibcHandler,
                channel0,
                Channel.State.STATE_FLUSHING
            );
            if (!callbacks.flushingAndFlushing.reverse) {
                if (
                    !callbacks.flushingAndFlushing.callback(
                        ibcHandler,
                        channel0,
                        channel1
                    )
                ) {
                    return upgradeSequence;
                }
            } else {
                if (
                    !callbacks.flushingAndFlushing.callback(
                        ibcHandler,
                        channel1,
                        channel0
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
                        portId: channel1.portId,
                        channelId: channel1.channelId,
                        counterpartyChannelState: Channel.State.STATE_FLUSHING,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            channel0.portId,
                            channel0.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                )
            );
            ensureChannelState(
                ibcHandler,
                channel1,
                Channel.State.STATE_FLUSHING
            );

            {
                (Channel.Data memory channel1Data, ) = ibcHandler.getChannel(
                    channel1.portId,
                    channel1.channelId
                );
                // Confirm@channel1: FLUSHING -> FLUSHCOMPLETE
                assertFalse(
                    ibcHandler.getCanTransitionToFlushComplete(
                        channel1.portId,
                        channel1.channelId
                    )
                );
                IIBCChannelUpgradableModule(
                    address(ibcHandler.getIBCModuleByPort(channel1.portId))
                ).allowTransitionToFlushComplete(
                        channel1.portId,
                        channel1.channelId,
                        upgradeSequence
                    );
                assertTrue(
                    ibcHandler.getCanTransitionToFlushComplete(
                        channel1.portId,
                        channel1.channelId
                    )
                );
                assertTrue(
                    ibcHandler.channelUpgradeConfirm(
                        IIBCChannelUpgradeBase.MsgChannelUpgradeConfirm({
                            portId: channel1.portId,
                            channelId: channel1.channelId,
                            counterpartyChannelState: Channel
                                .State
                                .STATE_FLUSHING,
                            counterpartyUpgrade: getCounterpartyUpgrade(
                                channel0.portId,
                                channel0.channelId
                            ),
                            proofs: upgradeLocalhostProofs()
                        })
                    )
                );
                ensureChannelState(
                    ibcHandler,
                    channel1,
                    Channel.State.STATE_FLUSHCOMPLETE
                );
                if (!callbacks.flushingAndComplete.reverse) {
                    if (
                        !callbacks.flushingAndComplete.callback(
                            ibcHandler,
                            channel0,
                            channel1
                        )
                    ) {
                        return upgradeSequence;
                    }
                } else {
                    if (
                        !callbacks.flushingAndComplete.callback(
                            ibcHandler,
                            channel1,
                            channel0
                        )
                    ) {
                        return upgradeSequence;
                    }
                }

                assertFalse(
                    ibcHandler.getCanTransitionToFlushComplete(
                        channel0.portId,
                        channel0.channelId
                    )
                );
                IIBCChannelUpgradableModule(
                    address(ibcHandler.getIBCModuleByPort(channel0.portId))
                ).allowTransitionToFlushComplete(
                        channel0.portId,
                        channel0.channelId,
                        upgradeSequence
                    );
                assertTrue(
                    ibcHandler.getCanTransitionToFlushComplete(
                        channel0.portId,
                        channel0.channelId
                    )
                );
                mockCallVerifyChannelState(
                    address(LocalhostHelper.getLocalhostClient(ibcHandler)),
                    channel1,
                    channel1Data
                );
                // Confirm@channel0: FLUSHING -> FLUSHCOMPLETE
                ibcHandler.channelUpgradeConfirm(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeConfirm({
                        portId: channel0.portId,
                        channelId: channel0.channelId,
                        counterpartyChannelState: Channel.State.STATE_FLUSHING,
                        counterpartyUpgrade: getCounterpartyUpgrade(
                            channel1.portId,
                            channel1.channelId
                        ),
                        proofs: upgradeLocalhostProofs()
                    })
                );
                vm.clearMockedCalls();
            }

            if (!callbacks.completeAndComplete.reverse) {
                if (
                    !callbacks.completeAndComplete.callback(
                        ibcHandler,
                        channel0,
                        channel1
                    )
                ) {
                    return upgradeSequence;
                }
            } else {
                if (
                    !callbacks.completeAndComplete.callback(
                        ibcHandler,
                        channel1,
                        channel0
                    )
                ) {
                    return upgradeSequence;
                }
            }
            // Open@channel0: FLUSHCOMPLETE -> OPEN
            ibcHandler.channelUpgradeOpen(
                IIBCChannelUpgradeBase.MsgChannelUpgradeOpen({
                    portId: channel0.portId,
                    channelId: channel0.channelId,
                    counterpartyChannelState: Channel.State.STATE_FLUSHCOMPLETE,
                    counterpartyUpgradeSequence: upgradeSequence,
                    proofChannel: LocalhostClientLib.sentinelProof(),
                    proofHeight: H(getBlockNumber())
                })
            );
            ensureChannelState(ibcHandler, channel0, Channel.State.STATE_OPEN);
            if (!callbacks.openSucAndComplete.reverse) {
                if (
                    !callbacks.openSucAndComplete.callback(
                        ibcHandler,
                        channel0,
                        channel1
                    )
                ) {
                    return upgradeSequence;
                }
            } else {
                if (
                    !callbacks.openSucAndComplete.callback(
                        ibcHandler,
                        channel1,
                        channel0
                    )
                ) {
                    return upgradeSequence;
                }
            }

            {
                (Channel.Data memory ch0, ) = ibcHandler.getChannel(
                    channel0.portId,
                    channel0.channelId
                );
                // Open@channel1: FLUSHCOMPLETE -> OPEN
                ibcHandler.channelUpgradeOpen(
                    IIBCChannelUpgradeBase.MsgChannelUpgradeOpen({
                        portId: channel1.portId,
                        channelId: channel1.channelId,
                        counterpartyChannelState: ch0.state,
                        counterpartyUpgradeSequence: ch0.upgrade_sequence,
                        proofChannel: LocalhostClientLib.sentinelProof(),
                        proofHeight: H(getBlockNumber())
                    })
                );
            }
            ensureChannelState(ibcHandler, channel1, Channel.State.STATE_OPEN);
            if (!callbacks.openSucAndOpenSuc.reverse) {
                if (
                    !callbacks.openSucAndOpenSuc.callback(
                        ibcHandler,
                        channel0,
                        channel1
                    )
                ) {
                    return upgradeSequence;
                }
            } else {
                if (
                    !callbacks.openSucAndOpenSuc.callback(
                        ibcHandler,
                        channel1,
                        channel0
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
