import * as hre from "hardhat";
import Deployer from "./deployer";
import {
  Bridge,
  IBridge,
  BridgeFallback,
  BridgeChannelUpgradeFallback,
  ETHBridge,
  PseudoPriceFeed,
  PseudoToken,
  Pool,
  PoolRepository,
  StableTokenPriceOracle,
  GasPriceOracle,
  TransferPoolFeeCalculator,
  RelayerFeeCalculator,
  ETHVault, TokenPriceOracle, TokiEscrow,
  MockOuterService, MockPayable, MockUnpayable,
  TokiToken,
  Multicall3,
  IIBCHandler,
  OwnableIBCHandler,
  IBCClient,
  IBCConnectionSelfStateNoValidation,
  IBCChannelHandshake,
  IBCChannelPacketSendRecv,
  IBCChannelPacketTimeout,
  IBCChannelUpgradeInitTryAck,
  IBCChannelUpgradeConfirmOpenTimeoutCancel,
  ILightClient,
} from "../tslib/typechain-types";

import {MainDeployPoolParameters, MainSetETHVaultParameters} from "./parameters";

// -- Multicall -----------------------------
export type DeployMulticallParameters = {
};
export type DeployMulticallResult = {
  multicall3: Multicall3,
};
export async function deployMulticall(deployer: Deployer, p: DeployMulticallParameters): Promise<DeployMulticallResult> {
  const multicall3 = await deployer.deployAbi<Multicall3>("Multicall3", []);

  return {
    multicall3,
  };
}

// -- PoolRepository -----------------------------
export type DeployPoolRepositoryParameters = {
};
export type DeployPoolRepositoryResult = {
  poolRepository: PoolRepository,
};
export async function deployPoolRepository(deployer: Deployer, p: DeployPoolRepositoryParameters): Promise<DeployPoolRepositoryResult> {
  const poolRepository = await deployer.deployUpgradeable<PoolRepository>("PoolRepository", [], []);
  return {
    poolRepository,
  };
}

// -- TAO -----------------------------
export type DeployTaoParameters = {
  deployed: null | {
    ownableIbcHandler: string,
  },
};
export type DeployTaoResult = {
  ownableIbcHandler: OwnableIBCHandler,
};
export async function deployTao(deployer: Deployer, p: DeployTaoParameters): Promise<DeployTaoResult> {
  if (p.deployed != null) {
    console.log("deployTao: deployed results are given. skip.");
    const ownableIbcHandler = await deployer.getDeployed<OwnableIBCHandler>("OwnableIBCHandler", p.deployed.ownableIbcHandler);
    return {
      ownableIbcHandler,
    };
  }

  const ibcClient = await deployer.deploy<IBCClient>("IBCClient", []);
  const ibcConnection = await deployer.deploy<IBCConnectionSelfStateNoValidation>("IBCConnectionSelfStateNoValidation", []);
  const ibcChannelHandshake = await deployer.deploy<IBCChannelHandshake>("IBCChannelHandshake", []);
  const ibcChannelPacketSendRecv = await deployer.deploy<IBCChannelPacketSendRecv>("IBCChannelPacketSendRecv", []);
  const ibcChannelPacketTimeout = await deployer.deploy<IBCChannelPacketTimeout>("IBCChannelPacketTimeout", []);
  const ibcChannelUpgradeInitTryAck = await deployer.deploy<IBCChannelUpgradeInitTryAck>("IBCChannelUpgradeInitTryAck", []);
  const IBCChannelUpgradeConfirmOpenTimeoutCancel = await deployer.deploy<IBCChannelUpgradeConfirmOpenTimeoutCancel>("IBCChannelUpgradeConfirmOpenTimeoutCancel", []);

  const ownableIbcHandler = await deployer.deploy<OwnableIBCHandler>(
    "OwnableIBCHandler", [
      await ibcClient.getAddress(),
      await ibcConnection.getAddress(),
      await ibcChannelHandshake.getAddress(),
      await ibcChannelPacketSendRecv.getAddress(),
      await ibcChannelPacketTimeout.getAddress(),
      await ibcChannelUpgradeInitTryAck.getAddress(),
      await IBCChannelUpgradeConfirmOpenTimeoutCancel.getAddress(),
    ]);

  const mockLightClient = await deployer.deploy<ILightClient>("MockClient", [await ownableIbcHandler.getAddress()]);

  await deployer.receipt(
    "OwnableIBCHandler.registerClient",
    ownableIbcHandler.registerClient(
      "mock-client",
      await mockLightClient.getAddress(),
      await deployer.txOptions()
    )
  );

  return {
    ownableIbcHandler,
  };
}

// -- Toki Token -----------------------------
export type DeployTokiTokenParametersBase = {
  globalDecimals: number,
  initialSupply_BN: bigint;
  cap_BN: bigint;
  softcap_BN: bigint;
  flowRateLimiter: FlowRateLimiterParameters,
  bridgeApprove_BN: bigint,
  priceFeed: DeployPriceFeedParameters,
};
export type DeployTokiTokenParameters = DeployTokiTokenParametersBase & {
  deployed: {
    bridgeAddress: string,
  }
};
export type DeployTokiTokenResult = {
  tokiEscrow: TokiEscrow,
  tokiToken: TokiToken,
};
export async function deployTokiToken(
  deployer: Deployer,
  p: DeployTokiTokenParameters,
): Promise<DeployTokiTokenResult> {
  const tokiToken = await deployer.deployUpgradeable<TokiToken>("TokiToken", [], [
    p.initialSupply_BN,
    p.cap_BN,
    p.softcap_BN,
    await deployer.address(),
  ]);

  const tokiEscrow = await deployer.deployUpgradeable<TokiEscrow>(
    "TokiEscrow",
    [
      p.flowRateLimiter.period,
      p.flowRateLimiter.lockPeriod,
      p.flowRateLimiter.limitLD_BN,
      p.flowRateLimiter.thresholdLD_BN,
    ],
    [
      await tokiToken.getAddress(),
      await deployer.address(),
      await deployer.address(), //bridge role
      p.globalDecimals,
      await tokiToken.decimals(),
  ]);

  await deployer.receipt("TokiToken.grantRole", tokiToken.grantRole(await tokiToken.MINTER_ROLE(), await tokiEscrow.getAddress(), await deployer.txOptions()));
  await deployer.receipt("TokiToken.grantRole", tokiToken.grantRole(await tokiToken.BURNER_ROLE(), await tokiEscrow.getAddress(), await deployer.txOptions()));

  const bridge = await deployer.getDeployed<IBridge>("IBridge", p.deployed.bridgeAddress);
  await deployer.receipt("Bridge.setTokenEscrow", bridge.setTokenEscrow(await tokiEscrow.getAddress(), await deployer.txOptions()));

  await deployer.receipt("TokiEscrow.grantRole", tokiEscrow.grantRole(await tokiEscrow.BRIDGE_ROLE(), p.deployed.bridgeAddress, await deployer.txOptions()));
  await deployer.receipt("TokiToken.approve", tokiToken.approve(p.deployed.bridgeAddress, p.bridgeApprove_BN, await deployer.txOptions()));

  return {
    tokiEscrow,
    tokiToken,
  } as DeployTokiTokenResult;
}

// -- NativeTokenPriceOracle -----------------------------
export type DeployTokenPriceOracleParametersBase = {
  priceChangeThresholdE18_BN: bigint,
};
export type DeployTokenPriceOracleParameters = DeployTokenPriceOracleParametersBase & {
  useTokiToken: boolean,
  tokiTokenPriceFeed: DeployPriceFeedParameters | undefined,
  validityPeriodSec: number,
}
export type DeployTokenPriceOracleResult = {
  tokenPriceOracle: TokenPriceOracle,
  stableTokenPriceOracle: StableTokenPriceOracle,
  gasPriceOracle: GasPriceOracle,
}
export async function deployTokenPriceOracle(
  deployer: Deployer,
  p: DeployTokenPriceOracleParameters,
): Promise<DeployTokenPriceOracleResult> {
  // setup tokenPriceOracle
  const tokenPriceOracle = await deployer.deploy<TokenPriceOracle>("TokenPriceOracle", [
    p.priceChangeThresholdE18_BN,
  ]);

  if (p.useTokiToken) {
    if (p.tokiTokenPriceFeed == undefined) {
      throw new Error("tokiTokenPriceFeed is required when useTokiToken is true");
    }
    const tokiTokenPriceFeedAddress = await deployPriceFeed(deployer, p.tokiTokenPriceFeed, "TokiTokenPseudoPriceFeed");
    await deployer.receipt(
      "TokenPriceOracle.setPriceFeedAddress",
      tokenPriceOracle.setPriceFeedAddress(
        await tokenPriceOracle.tokenIdToki(),
        tokiTokenPriceFeedAddress,
        BigInt(p.validityPeriodSec),
        await deployer.txOptions()
      ));
  }

  // NOTE: price feeds are set in deployPool()
  const stableTokenPriceOracle = await deployer.deploy<StableTokenPriceOracle>("StableTokenPriceOracle", []);

  // NOTE: prices are set in setChannel()
  const gasPriceOracle = await deployer.deploy<GasPriceOracle>("GasPriceOracle", []);

  return {
    tokenPriceOracle,
    stableTokenPriceOracle,
    gasPriceOracle,
  };
}

//-- Bridge -----------------------------
export type DeployBridgeParametersBase = {
  appVersion: number,
  portId: string,
  nativeTokenPriceFeed: DeployPriceFeedParameters,
  nativeTokenPriceFeedValidityPeriodSec: number,
  relayerFeeGasUsed_BN: bigint,
  relayerFeeGasPerPayloadLength_BN: bigint,
  relayerFeePremiumBPS_BN: bigint,
  receiveRetryBlock: number,
  withdrawRetryBlock: number,
  externalRetryBlock: number,
};
export type DeployBridgeParameters = DeployBridgeParametersBase & {
  deployed: {
    ibcHandlerAddress: string,
    poolRepositoryAddress: string,
    tokiEscrowAddress: string,
    tokiTokenAddress: string,
    tokenPriceOracleAddress: string,
    gasPriceOracleAddress: string
  },
  useTokiToken: boolean,
};
export type DeployBridgeResult = {
  bridge: Bridge,
  bridgeFallback: BridgeFallback,
  bridgeChannelUpgradeFallback: BridgeChannelUpgradeFallback,
}

export async function deployBridge(
  deployer: Deployer,
  p: DeployBridgeParameters,
): Promise<DeployBridgeResult> {
  const poolRepository = await deployer.getDeployed<PoolRepository>("PoolRepository", p.deployed.poolRepositoryAddress);
  const ibcHandler = await deployer.getDeployed<IIBCHandler>("IIBCHandler", p.deployed.ibcHandlerAddress);

  // set price oracle (peer chain's price oracle is created in setChannel())
  const tokenPriceOracle = await deployer.getDeployed<TokenPriceOracle>("TokenPriceOracle", p.deployed.tokenPriceOracleAddress);
  const tokenPriceFeedAddress = await deployPriceFeed(deployer, p.nativeTokenPriceFeed, "NativeTokenPseudoPriceFeed");

  await deployer.receipt("TokenPriceOracle.setPriceFeedAddress", tokenPriceOracle.setPriceFeedAddress(deployer.network.chainId, tokenPriceFeedAddress, BigInt(p.nativeTokenPriceFeedValidityPeriodSec), await deployer.txOptions()));

  const gasPriceOracle = await deployer.getDeployed<GasPriceOracle>("GasPriceOracle", p.deployed.gasPriceOracleAddress);
  // setup protocolFeeOwner;
  const relayerFeeCalculator = await deployer.deploy<RelayerFeeCalculator>("RelayerFeeCalculator", [
    await tokenPriceOracle.getAddress(),
    await gasPriceOracle.getAddress(),
    p.relayerFeeGasUsed_BN,
    p.relayerFeeGasPerPayloadLength_BN,
    p.relayerFeePremiumBPS_BN,
  ]);

  const bridgeFallback = await deployer.deploy<BridgeFallback>("BridgeFallback", [p.appVersion, p.portId]);
  const bridgeChannelUpgradeFallback = await deployer.deploy<BridgeChannelUpgradeFallback>("BridgeChannelUpgradeFallback", [p.appVersion, p.portId]);
  const bridge = await deployer.deployUpgradeable<Bridge>(
    "Bridge",
    [
      p.appVersion,
      p.portId,
    ],
    [
      {
        ibcHandler: p.deployed.ibcHandlerAddress,
        poolRepository: p.deployed.poolRepositoryAddress,
        tokenEscrow: hre.ethers.ZeroAddress, // tokiEscrowAddress
        tokenPriceOracle: p.deployed.tokenPriceOracleAddress,
        relayerFeeOwner: await deployer.address(),
        relayerFeeCalculator: await relayerFeeCalculator.getAddress(),
        bridgeFallback: await bridgeFallback.getAddress(),
        bridgeChannelUpgradeFallback: await bridgeChannelUpgradeFallback.getAddress(),
        receiveRetryBlocks: p.receiveRetryBlock,
        withdrawRetryBlocks: p.withdrawRetryBlock,
        externalRetryBlocks: p.externalRetryBlock,
      }
    ]);

  await deployer.receipt("IBCHandler.bindPort", ibcHandler.bindPort(p.portId, await bridge.getAddress(), await deployer.txOptions()));
  await deployer.receipt("PoolRepository.grantRole", poolRepository.grantRole(await poolRepository.POOL_SETTER(), await deployer.address(), await deployer.txOptions()));

  return {
    bridge,
    bridgeFallback,
    bridgeChannelUpgradeFallback
  };
}

// -- ETHVault -----------------------------
export type DeployETHVaultParameters = {
};
export type DeployETHVaultResult = {
  ethVault: ETHVault,
};
export async function deployETHVault(deployer: Deployer, p: DeployETHVaultParameters): Promise<DeployETHVaultResult> {
  const ethVault = await deployer.deployUpgradeable<ETHVault>("ETHVault", [], []);

  return {
    ethVault,
  };
}

// -- ETHBridge -----------------------------
export type DeployETHBridgeParameters = {
  ethPoolId: number,
  deployed: {
    ethVault: string,
    bridge: string,
  },
};
export type DeployETHBridgeResult = {
  ethBridge: ETHBridge,
};
export async function deployETHBridge(deployer: Deployer, p: DeployETHBridgeParameters): Promise<DeployETHBridgeResult> {
  const ethBridge = await deployer.deploy<ETHBridge>("ETHBridge", [p.deployed.ethVault, p.deployed.bridge, p.ethPoolId]);

  return {
    ethBridge,
  };
}

// -- Pool -----------------------------
export type DeployPoolParametersBase = {
  poolId: number,
  deltaParam: {
    batched: boolean,
    defaultSwapMode: boolean,
    defaultLPMode: boolean,
    swapDeltaBP_BN: bigint,
    lpDeltaBP_BN: bigint,
  },
  pooledToken: {
    contractName: string,
    tokenIdInTokenPriceOracle_BN: bigint | null,
    name: string,
    symbol: string,
    address: string, // unimplemented yet
    localDecimals: number,
    globalDecimals: number,
    mintCap_BN: bigint,
    basePrice_BN: bigint,
    priceFeed: DeployPriceFeedParameters,
    priceFeedValidityPeriodSec: number,
    flowRateLimiter: FlowRateLimiterParameters,
  },
  liquidityToken: {
    name: string,
    symbol: string,
  },
  peers: [
    {
      chainId_BN: bigint,
      poolId: number,
      weight: number,
    }
  ],
  maxTotalDepositsLD_BN: BigInt,
}
export type DeployPoolParameters = DeployPoolParametersBase & {
  deployed: {
    poolRepositoryAddress: string,
    bridgeAddress: string,
    rewardTokenAddress: string | null,
    ethVaultAddress: string | null | undefined,
    stableTokenPriceOracleAddress: string,
    tokenPriceOracleAddress: string,
    transferPoolFeeCalculatorAddress: string,
  },
};
export type DeployPoolResult = {
  pool: Pool,
};
export async function deployPool(deployer: Deployer, p: DeployPoolParameters): Promise<DeployPoolResult> {

  const poolRepository = await deployer.getDeployed<PoolRepository>("PoolRepository", p.deployed.poolRepositoryAddress);

  let tokenAddress;
  let decimals;
  if (p.pooledToken.contractName == "ETHVault") {
    tokenAddress = p.deployed.ethVaultAddress;
    if (tokenAddress == null) {
      throw new Error("contractName is ETHVault but ethValutAddress is null");
    }
    const ethVault = await deployer.getDeployed<ETHVault>("ETHVault", tokenAddress!);
    decimals = await ethVault.decimals();
  } else {
    const token = await deployer.deployUpgradeable<PseudoToken>("PseudoToken", [p.pooledToken.localDecimals], [p.pooledToken.name, p.pooledToken.symbol, p.pooledToken.mintCap_BN], p.pooledToken.name);
    decimals = await token.decimals();
    tokenAddress = await token.getAddress();
  }

  // setup fee calculator
  const tokenPriceFeedAddress = await deployPriceFeed(deployer, p.pooledToken.priceFeed);
  if (p.pooledToken.tokenIdInTokenPriceOracle_BN == null) {
    const stableTokenPriceOracle = await deployer.getDeployed<StableTokenPriceOracle>("StableTokenPriceOracle", p.deployed.stableTokenPriceOracleAddress);
    await deployer.receipt("StableTokenPriceOracle.setBasePriceAndFeedAddress", stableTokenPriceOracle.setBasePriceAndFeedAddress(p.poolId, p.pooledToken.basePrice_BN, tokenPriceFeedAddress, BigInt(p.pooledToken.priceFeedValidityPeriodSec), await deployer.txOptions()));
  } else { // non-stable token
    const tokenPriceOracle = await deployer.getDeployed<TokenPriceOracle>("TokenPriceOracle", p.deployed.tokenPriceOracleAddress);
    await deployer.receipt("TokenPriceOracle.setPriceFeedAddress", tokenPriceOracle.setPriceFeedAddress(p.pooledToken.tokenIdInTokenPriceOracle_BN, tokenPriceFeedAddress, BigInt(p.pooledToken.priceFeedValidityPeriodSec), await deployer.txOptions()));

    const transferPoolFeeCalculator = await deployer.getDeployed<TransferPoolFeeCalculator>("TransferPoolFeeCalculator", p.deployed.transferPoolFeeCalculatorAddress);
    await deployer.receipt("TransferPoolFeeCalculator.setTokenId", transferPoolFeeCalculator.setTokenId(p.poolId, p.pooledToken.tokenIdInTokenPriceOracle_BN, await deployer.txOptions()));
  }

  const pool = await deployer.deployUpgradeable<Pool>(
    "Pool",
    [
      p.pooledToken.flowRateLimiter.period,
      p.pooledToken.flowRateLimiter.lockPeriod,
      p.pooledToken.flowRateLimiter.limitLD_BN,
      p.pooledToken.flowRateLimiter.thresholdLD_BN,
    ],
    [{
      name: p.liquidityToken.name,
      symbol: p.liquidityToken.symbol,
      poolId: p.poolId,
      token: tokenAddress,
      globalDecimals: p.pooledToken.globalDecimals,
      localDecimals: decimals,
      feeCalculator: p.deployed.transferPoolFeeCalculatorAddress,
      admin: await deployer.address(), //address admin,
      router: p.deployed.bridgeAddress, //address router,
      maxTotalDeposits: p.maxTotalDepositsLD_BN
    }]);

  await deployer.receipt("Pool.setDepositLimits", pool.setMaxTotalDeposits(p.maxTotalDepositsLD_BN, await deployer.txOptions()));
  await deployer.receipt("PoolRepository.setPool", poolRepository.setPool(p.poolId, await pool.getAddress(), await deployer.txOptions()));

  await deployer.receipt(
    "Pool.setDeltaParam",
    pool.setDeltaParam(
      p.deltaParam.batched,
      p.deltaParam.swapDeltaBP_BN,
      p.deltaParam.lpDeltaBP_BN,
      p.deltaParam.defaultSwapMode,
      p.deltaParam.defaultLPMode,
      await deployer.txOptions()
    ));

  return {
    pool,
  };
}

export async function setPoolPeers(deployer: Deployer, pool: Pool, p: MainDeployPoolParameters): Promise<void> {
  for (const peer of p.peers) {
    await deployer.receipt("Pool.registerPeerPool", pool.registerPeerPool(peer.chainId_BN, peer.poolId, peer.weight, await deployer.txOptions()));
    await deployer.receipt("Pool.activatePeerPool", pool.activatePeerPool(peer.chainId_BN, peer.poolId, await deployer.txOptions()));
  }
}


//-- Channel -----------------------------
export type SetChannelParametersBase = {
  poolIds: number[],
  dstChains: [
    {
      chainId_BN: bigint,
      portId: string,
      channelId: string,
      refuelSrcCap_BN: bigint,
      initialGasPrice_BN: bigint,
      nativeTokenPriceFeed: DeployPriceFeedParameters
      nativeTokenPseudoInitialPrice_BN: bigint,
      nativeTokenPriceFeedValidityPeriodSec: number,
    }
  ]
  refuelDstCap_BN: bigint,
};
export type SetChannelParameters = SetChannelParametersBase & {
  deployed: {
    bridgeAddress: string,
    tokenPriceOracleAddress: string,
    gasPriceOracleAddress: string,
  },
  useTokiToken: boolean,
};
export type SetChannelResult = {};
export async function setChannel(
  deployer: Deployer,
  p: SetChannelParameters,
): Promise<SetChannelResult> {
  const bridge = await deployer.getDeployed<IBridge>("IBridge", p.deployed.bridgeAddress);

  // deploy NativeTokenPriceFeed
  const tokenPriceOracle = await deployer.getDeployed<TokenPriceOracle>("TokenPriceOracle", p.deployed.tokenPriceOracleAddress);

  const gasPriceOracle = await deployer.getDeployed<GasPriceOracle>("GasPriceOracle", p.deployed.gasPriceOracleAddress);
  let tokiEscrow: TokiEscrow | null = null;
  if (p.useTokiToken) {
    tokiEscrow = await deployer.getDeployed<TokiEscrow>("TokiEscrow", await bridge.tokenEscrow());
  }

  await deployer.receipt("Bridge.setRefuelDstCap", bridge.setRefuelDstCap(p.refuelDstCap_BN, await deployer.txOptions()));
  // configure various contracts for each chain.
  for (const dstChain of p.dstChains) {
    const tokenPriceFeedAddress = await deployPriceFeed(deployer, dstChain.nativeTokenPriceFeed);
    const channelInfo = { port: dstChain.portId, channel: dstChain.channelId };
    await deployer.receipt("Bridge.setChainLookup", bridge.setChainLookup(channelInfo.channel, dstChain.chainId_BN, await deployer.txOptions()));
    await deployer.receipt("Bridge.setRefuelSrcCap", bridge.setRefuelSrcCap(channelInfo.channel, dstChain.refuelSrcCap_BN, await deployer.txOptions()));
    await deployer.receipt("TokenPriceOracle.setPriceFeedAddress", tokenPriceOracle.setPriceFeedAddress(dstChain.chainId_BN, tokenPriceFeedAddress, BigInt(dstChain.nativeTokenPriceFeedValidityPeriodSec), await deployer.txOptions()));
    await deployer.receipt("GasPriceOracle.updatePrice", gasPriceOracle.updatePrice(dstChain.chainId_BN, dstChain.initialGasPrice_BN, await deployer.txOptions()));
    if (tokiEscrow != null) {
      await deployer.receipt("TokiEscrow.setAcceptedDstChainId", tokiEscrow.setAcceptedDstChainId(dstChain.chainId_BN, true, await deployer.txOptions()));
    }
  }

  return {
  };
}

//-- ETHVault -----------------------------
export type SetETHVaultParameters = {
  poolId: number,
  deployed: {
    bridgeAddress: string,
    ethVaultAddress: string,
  },
};
export type SetETHVaultResult = {};
export async function setETHVault(
  deployer: Deployer,
  p: SetETHVaultParameters,
): Promise<SetETHVaultResult> {
  const ethVault = await deployer.getDeployed<ETHVault>("ETHVault", p.deployed.ethVaultAddress);
  const bridge = await deployer.getDeployed<Bridge>("Bridge", p.deployed.bridgeAddress);
  const pool = await bridge.getPool(p.poolId);
  console.log(`setETHVault: pool=${pool}, ethVault=${ethVault}`);
  await deployer.receipt("EthVault.setNoUnwrapTo", ethVault.setNoUnwrapTo(pool, await deployer.txOptions()));

  return {};
}

//-- StaticFlowRateLimiter -----------------------------
export type FlowRateLimiterParameters = {
  limitLD_BN: bigint,
  thresholdLD_BN: bigint,
  period: number,
  lockPeriod: number,
};

//-- TransferPoolFeeCalculator -----------------------------
export type DeployTransferPoolFeeCalculatorParameters = {
  deployed: {
    stableTokenPriceOracleAddress: string
  },
};
export type DeployTransferPoolFeeCalculatorResult = {
  transferPoolFeeCalculator: TransferPoolFeeCalculator,
};
export async function deployTransferPoolFeeCalculator(
  deployer: Deployer,
  p: DeployTransferPoolFeeCalculatorParameters,
): Promise<DeployTransferPoolFeeCalculatorResult> {
  const stableTokenPriceOracle = await deployer.getDeployed<StableTokenPriceOracle>("StableTokenPriceOracle", p.deployed.stableTokenPriceOracleAddress);
  const feeCalculator = await deployer.deploy<TransferPoolFeeCalculator>("TransferPoolFeeCalculator", [
    await stableTokenPriceOracle.getAddress()
  ]);
  return {
    transferPoolFeeCalculator: feeCalculator,
  };
}

// -- PriceFeed -----------------------------
export type UsePriceFeedParameters = {
  address: string,
}
export type DeployPseudoPriceFeedParameters = {
  initialPseudoPrice_BN: bigint,
  decimals: number,
}

export type DeployPriceFeedParameters = UsePriceFeedParameters | DeployPseudoPriceFeedParameters
export type DeployPriceFeedResult = {
  address: string,
}
export async function deployPriceFeed(deployer: Deployer, p: DeployPriceFeedParameters, altname?: string | undefined): Promise<string> {
  if ("address" in p) {
    if (!hre.ethers.isAddress(p.address)) {
      throw new Error(`deployPriceFeed: invalid address ${p.address}`);
    }
    console.log(`deployPriceFeed is skipped: address ${p.address} is given.`);
    return p.address;
  } else {
    const feed = await deployer.deploy<PseudoPriceFeed>("PseudoPriceFeed", [p.initialPseudoPrice_BN, p.decimals], altname);
    return await feed.getAddress();
  }
}

// -- for testing -----------------------------
export type DeployTestParameters = {
  port: string,
};
export type DeployTestResult = {
  mockOuterService: MockOuterService,
  mockPayable: MockPayable,
  mockUnpayable: MockUnpayable,
};
export async function deployTest(deployer: Deployer, p: DeployTestParameters): Promise<DeployTestResult> {
  const mockOuterService = await deployer.deploy<MockOuterService>("MockOuterService", [p.port], "MockOuterService");
  const mockPayable = await deployer.deploy<MockPayable>("MockPayable", [], "MockPayable");
  const mockUnpayable = await deployer.deploy<MockUnpayable>("MockUnpayable", [], "MockUnpayable");

  return {
    mockOuterService,
    mockPayable,
    mockUnpayable,
  } as DeployTestResult;
}
