import * as fs from "fs";
import { setTimeout } from "timers/promises";
import { Channel } from "node:diagnostics_channel";

export { setTimeout } from "timers/promises";

import * as toki from "@toki";
export * as toki from "@toki";
import { ethers } from "@toki";
export { ethers } from "@toki";

export const receipt = async (
  ptxr: Promise<ethers.TransactionResponse>
): Promise<ethers.TransactionReceipt> => {
  return ptxr
    .then((txr) => {
      return txr.wait(3);
    })
    .then((r) => {
      if (r == null) {
        return Promise.reject("wait returns null");
      } else {
        return Promise.resolve(r);
      }
    });
};

export type PooledToken = toki.tt.PseudoToken | toki.tt.ETHVault;

export type PoolData = {
  poolId: number;
  pool: toki.tt.Pool;
  pooledTokenName: string;
  pooledTokenContractName: string;
  pooledToken: PooledToken;
  peers: {
    chainId: number;
    poolId: number;
    weight: number;
  }[];
  feeCalculator: toki.tt.TransferPoolFeeCalculator;
};

export const isETHVault = (x: PooledToken): x is toki.tt.ETHVault => {
  return (x as any).noUnwrapTo !== undefined;
};

export const isPseudoToken = (x: PooledToken): x is toki.tt.PseudoToken => {
  return (x as any).mintCap !== undefined;
};

export const BNB_CHAIN_ID = 9999;
export const ETH_CHAIN_ID = 1337;

export type ChannelInfo = {
  chainId: number;
  portId: string;
  channelId: string;
};

export type ETHChain = {
  ethBridge: toki.tt.ETHBridge;
  ethVault: toki.tt.ETHVault;
};

export type Chain = {
  deploy_name: string;
  name: string;
  deploy_input: any;
  deploy_output: any;
  provider: ethers.Provider;
  chainId: number;
  relayerAddress: string;
  wallet: ethers.Wallet;
  network: ethers.Network;
  bridge: toki.tt.IBridge;
  bridgeFallback: toki.tt.BridgeFallback;
  bridgeChannelUpgradeFallback: toki.tt.BridgeChannelUpgradeFallback;
  ibcHandler: toki.tt.IIBCHandler;
  tokiToken: toki.tt.TokiToken | null;
  tokiEscrow: toki.tt.TokiEscrow | null;
  poolRepository: toki.tt.PoolRepository;
  pooldata: PoolData[];
  multicall3: toki.tt.Multicall3;
  mockOuterService: toki.tt.MockOuterService;
  mockPayable: toki.tt.MockPayable;
  mockUnpayable: toki.tt.MockUnpayable;
  deploy: any;
  channelInfo: ChannelInfo[];
  ethChain?: ETHChain;
  eventHandlers: {
    contract?: null | RegExp;
    name?: null | RegExp;
    handler?:
      | null
      | ((chain: Chain, contract: string, ev: ethers.LogDescription) => any);
  }[];
};

export const getPeerPoolInfo = async (
  myChain: Chain,
  myPoolId: number,
  peerChainId: number,
  peerPoolId: number
): Promise<toki.tt.IPool.PeerPoolInfoStruct> => {
  const pd = myChain.pooldata.find((pd) => pd.poolId == myPoolId);
  if (pd === undefined) {
    throw new Error(
      `unknown pool: chainId=${myChain.chainId}, poolId=${myPoolId}`
    );
  }
  const info = await pd.pool.getPeerPoolInfo(peerChainId, peerPoolId);
  return {
    chainId: info[0],
    id: info[1],
    weight: info[2],
    balance: info[3],
    targetBalance: info[4],
    lastKnownBalance: info[5],
    credits: info[6],
    ready: info[7],
  };
};

export const FUNCTION_TYPE = {
  TransferPool: 0,
  TransferToken: 1,
  WithdrawLocal: 2,
  SendCredit: 3,
  Other: 4,
} as const;

export const calcRelayerFee = async (
  src: Chain,
  dst: Chain,
  ftype: number
): Promise<bigint> => {
  const calc = await toki.tt.RelayerFeeCalculator__factory.connect(
    await src.bridge.relayerFeeCalculator(),
    src.wallet
  );
  const tokenPriceOracle = await toki.tt.ITokenPriceOracle__factory.connect(
    await calc.tokenPriceOracle(),
    src.wallet
  );
  const gasPriceOracle = await toki.tt.IGasPriceOracle__factory.connect(
    await calc.gasPriceOracle(),
    src.wallet
  );

  const gasUsed = await calc.gasUsed();
  const premiumBPS = await calc.premiumBPS();
  const dstTokenPrice = await tokenPriceOracle.getPrice(dst.chainId);
  const dstGasPrice = await gasPriceOracle.getPrice(dst.chainId);
  const srcTokenPrice = await tokenPriceOracle.getPrice(src.chainId);

  //console.log({gasUsed, premiumBPS, dstTokenPrice, dstGasPrice, srcTokenPrice});

  const fee = await calc.calcFee(ftype, dst.chainId);
  return fee.fee;
};

export const calcSrcNativeAmount = async (
  src: Chain,
  dst: Chain,
  gas: bigint,
  amount: bigint
): Promise<bigint> => {
  return src.bridge.calcSrcNativeAmount(dst.chainId, gas, amount);
};

export const showChain = async (chains: Chain[], chIdx: number) => {
  const myChain = chains[chIdx];
  console.log(`${myChain.name}: chainId=${myChain.network.chainId}`);
  console.log(`  bridge addr=`, await myChain.bridge.getAddress());
  for (let pdi = 0; pdi < myChain.pooldata.length; ++pdi) {
    const pd = myChain.pooldata[pdi];
    console.log(
      `  pooldata[${pdi}](poolId=${pd.poolId}) addr=`,
      await pd.pool.getAddress()
    );
    const pt_balance = await pd.pooledToken.balanceOf(pd.pool.getAddress());
    const pt_name = await pd.pooledToken.name();
    const pt_decimals = await pd.pooledToken.decimals();
    console.log(
      `    pooledToken.balance=${pt_balance}, name=${pt_name}, decimals=${pt_decimals}, addr=`,
      await pd.pooledToken.getAddress()
    );
    for (let peerChi = 0; peerChi < pd.peers.length; peerChi++) {
      const peer = pd.peers[peerChi];
      const info = await pd.pool.getPeerPoolInfo(peer.chainId, peer.poolId);
      console.log(
        `      PeerPool(${peer.chainId},${peer.poolId}): `,
        "balance=",
        info.balance,
        "credits=",
        info.credits
      );
    }
  }
};

export const createSigner = (chain: Chain): ethers.Signer => {
  return ethers.Wallet.createRandom(chain.provider);
};

export const getChain = async (
  url: string,
  prikey: string,
  deploy_name: string
): Promise<Chain> => {
  const provider = new ethers.JsonRpcProvider(url);
  // The network.chainId is from eth_chainId and it is set by genesis.json
  // Note that the net_version is different value which is given --networkid option
  const network = await provider.getNetwork();
  const wallet = new ethers.Wallet(prikey, provider);

  const params = JSON.parse(
    fs.readFileSync(`../contract-deploy/${deploy_name}.parameter.json`, "utf-8")
  );
  const deployReports: {
    name: string;
    address: string;
  }[] = JSON.parse(
    fs.readFileSync(
      `../contract-deploy/output/${deploy_name}.contract.json`,
      "utf-8"
    )
  );

  const deploy = deployReports.reduce((acc, v) => {
    acc[v.name] = v.address;
    return acc;
  }, {} as { [key: string]: string });

  const bridge = toki.tt.IBridge__factory.connect(deploy["Bridge"], wallet);
  const bridgeFallback = toki.tt.BridgeFallback__factory.connect(deploy["BridgeFallback"], wallet);
  const bridgeChannelUpgradeFallback = toki.tt.BridgeChannelUpgradeFallback__factory.connect(deploy["BridgeChannelUpgradeFallback"], wallet);
  const ibcHandler = toki.tt.IIBCHandler__factory.connect(
    deploy["OwnableIBCHandler"],
    wallet
  );
  let tokiToken = null;
  let tokiEscrow = null;
  if (deploy["TokiToken"] != null) {
    tokiToken = toki.tt.TokiToken__factory.connect(deploy["TokiToken"], wallet);
    tokiEscrow = toki.tt.TokiEscrow__factory.connect(
      deploy["TokiEscrow"],
      wallet
    );
  }
  const poolRepository = toki.tt.PoolRepository__factory.connect(
    deploy["PoolRepository"],
    wallet
  );
  const pooldata: PoolData[] = [];
  for (
    let poolParamIdx = 0;
    poolParamIdx < params["pools"].length;
    ++poolParamIdx
  ) {
    const poolId = params["pools"][poolParamIdx]["poolId"];
    const pool = toki.tt.Pool__factory.connect(
      deploy[`Pool${poolId}.Pool`],
      wallet
    );
    let pooledToken;
    const pooledTokenName =
      params["pools"][poolParamIdx]["pooledToken"]["name"];
    const pooledTokenContractName =
      params["pools"][poolParamIdx]["pooledToken"]["contractName"];
    if (pooledTokenContractName == "ETHVault") {
      pooledToken = toki.tt.ETHVault__factory.connect(
        deploy["ETHVault"],
        wallet
      );
    } else {
      pooledToken = toki.tt.PseudoToken__factory.connect(
        deploy[`Pool${poolId}.${pooledTokenName}`],
        wallet
      );
    }
    const feeCalculator = toki.tt.TransferPoolFeeCalculator__factory.connect(
      deploy["TransferPoolFeeCalculator"],
      wallet
    );

    const peers = params["pools"][poolParamIdx]["peers"].map((x: any) => ({
      chainId: parseInt(x["chainId_BN"]),
      poolId: x["poolId"],
      weight: x["weight"],
    }));
    pooldata.push({
      poolId,
      pool,
      pooledTokenName,
      pooledTokenContractName,
      pooledToken,
      peers,
      feeCalculator,
    });
  }
  const multicall3 = toki.tt.Multicall3__factory.connect(
    deploy["Multicall3"],
    wallet
  );

  const mockOuterService = toki.tt.MockOuterService__factory.connect(
    deploy["MockOuterService"],
    wallet
  );
  const mockPayable = toki.tt.MockPayable__factory.connect(
    deploy["MockPayable"],
    wallet
  );
  const mockUnpayable = toki.tt.MockUnpayable__factory.connect(
    deploy["MockUnpayable"],
    wallet
  );

  const channelInfo: ChannelInfo[] = [];
  for (let dstChain of params["channel"]["dstChains"]) {
    channelInfo.push({
      chainId: parseInt(dstChain["chainId_BN"]),
      portId: dstChain["portId"],
      channelId: dstChain["channelId"],
    });
  }

  const ethChain =
    network.chainId == BigInt(ETH_CHAIN_ID)
      ? {
          ethBridge: toki.tt.ETHBridge__factory.connect(
            deploy["ETHBridge"],
            wallet
          ),
          ethVault: toki.tt.ETHVault__factory.connect(
            deploy["ETHVault"],
            wallet
          ),
        }
      : undefined;

  return {
    deploy_name: deploy_name,
    name: deploy_name.split("-")[1],
    provider,
    deploy_input: params,
    deploy_output: deploy,
    relayerAddress: "0xa89f47c6b463f74d87572b058427da0a13ec5425",
    wallet,
    network,
    chainId: Number(network.chainId),
    deploy,
    bridge,
    bridgeFallback,
    bridgeChannelUpgradeFallback,
    ibcHandler,
    tokiEscrow,
    tokiToken,
    poolRepository,
    pooldata,
    multicall3,
    mockOuterService,
    mockPayable,
    mockUnpayable,
    channelInfo,
    ethChain,
    eventHandlers: [{ name: /Debug/ }, { name: /RevertReceive/ }],
  };
};

export const getChains = async (): Promise<Chain[]> => {
  return [
    await getChain(
      "http://localhost:8545",
      "043a3427c36481e3cce70f5e6738b5f4d1a7e87fa90aa833f4bf2d3d690d4919",
      "deploy-bnb-oneshot-0"
    ),
    await getChain(
      "http://localhost:18545",
      "e517af47112e4f501afb26e4f34eadc8b0ad8eadaf4962169fc04bc8ddbfe091",
      "deploy-eth-oneshot-0"
    ),
  ];
};

export const dumpRoles = () => {
  [
    "MINTER_ROLE",
    "BURNER_ROLE",
    "BRIDGE_ROLE",
    "IBC_HANDLER_ROLE",
    "DEFAULT_ROUTER_ROLE",
    "RELAY_FEE_OWNER_ROLE",
    "ADMIN_ROLE",
    "OPERATOR_ROLE",
  ].forEach((s) => {
    console.log(`${s}: `, ethers.keccak256(ethers.toUtf8Bytes(s)));
  });
};

// ex) addr='0x8b6D96C84A5ec08E3559e78Daea00680D00FB169'
// encodeAddressPacked returns Uint8Array of [139,109,150,200,74,94,192,142,53,89,231,141,174,160,6,128,208,15,177,105]
export const encodeAddressPacked = (addr: string): Uint8Array => {
  return ethers.getBytes(addr);
}

export type ChainPeerPool = {
  chainId: number;
  pooldata: PoolData;
  chain: Chain;
};
export const getPeerPools = async (
  chains: Chain[],
  chainIdx: number,
  poolIdx: number
): Promise<ChainPeerPool[]> => {
  const ret: ChainPeerPool[] = [];
  const chain = chains[chainIdx];
  const pooldata = chain.pooldata[poolIdx];
  for (let i = 0; i < chains.length; ++i) {
    const ch = chains[i];
    for (let pi = 0; pi < ch.pooldata.length; ++pi) {
      const dstPooldata = ch.pooldata[pi];
      const dstSeekIdx = await pooldata.pool.peerPoolInfoIndexSeek(
        ch.chainId,
        dstPooldata.poolId
      );
      const peerPool = await pooldata.pool.peerPoolInfos(dstSeekIdx);
      if (
        Number(peerPool.chainId) == ch.chainId &&
        Number(peerPool.id) == dstPooldata.poolId
      ) {
        ret.push({
          chainId: ch.chainId,
          pooldata: dstPooldata,
          chain: ch,
        });
      }
    }
  }
  return ret;
};

export const getReversePeerPoolInfos = async (
  chains: Chain[],
  chainIdx: number,
  poolIdx: number
): Promise<any[]> => {
  const ret: any[] = [];
  const chain = chains[chainIdx];
  const pooldata = chain.pooldata[poolIdx];
  const peerPools = await getPeerPools(chains, chainIdx, poolIdx);
  for (let peerPool of peerPools) {
    try {
      const peerPoolInfo = await peerPool.pooldata.pool.getPeerPoolInfo(
        chain.chainId,
        pooldata.poolId
      );
      ret.push({
        chainId: peerPool.chainId,
        poolId: peerPool.pooldata.poolId,
        peerPoolInfo,
      });
    } catch (error) {
      console.error(error);
    }
  }
  return ret;
};

export const fillNativeToken = async (
  chain: Chain,
  addr: string,
  num_eth: number
): Promise<ethers.TransactionResponse> => {
  const tx = {
    to: addr,
    value: ethers.parseUnits(`${num_eth}`, "ether"),
  };

  const goal = ethers.parseUnits(`${num_eth}`, "ether");
  const current = await chain.provider.getBalance(addr);
  if (goal <= current) {
    tx.value = ethers.parseUnits("0", "ether"); // call dummy tx to return TransactionResponse
  }
  return chain.wallet.sendTransaction(tx);
};

export const deposit = async (
  chains: Chain[],
  chIndex: number,
  poolIdx: number,
  amountLD: bigint,
  doDump: boolean = false
) => {
  const myChain = chains[chIndex];
  const myPoolData = myChain.pooldata[poolIdx];
  const amountGD = await toki.util.LDToGD(myPoolData.pool, amountLD);
  if (doDump) {
    console.log(
      `depositing to chainId=${myChain.chainId}, poolId=${myPoolData.poolId}: ld=${amountLD}, gd=${amountGD}`
    );
    console.log(
      `native token=`,
      await myChain.provider.getBalance(myChain.wallet.address)
    );
  }

  const dump = async (infos: any[]) => {
    const balance = await myPoolData.pooledToken.balanceOf(
      myPoolData.pool.getAddress()
    );
    console.log(
      `    Pool(${myChain.chainId}, ${myPoolData.poolId}): balance=${balance}`
    );
    infos.forEach((info) => {
      console.log(
        `    (${info.chainId},${info.poolId})'s PeerPool(${myChain.chainId},${myPoolData.poolId}): `,
        "balance=",
        info.peerPoolInfo.balance,
        "lastKnownBalance=",
        info.peerPoolInfo.lastKnownBalance,
        "credits=",
        info.peerPoolInfo.credits
      );
    });
  };
  const revPeerPoolInfos0 = await getReversePeerPoolInfos(
    chains,
    chIndex,
    poolIdx
  );
  if (doDump) {
    await dump(revPeerPoolInfos0);
  }
  console.log("  approve...");
  await receipt(
    myPoolData.pooledToken.approve(await myChain.bridge.getAddress(), amountLD)
  );
  console.log("  deposit...");
  await receipt(
    myChain.bridge.deposit(myPoolData.poolId, amountLD, myChain.wallet.address)
  );
  const batched = await myPoolData.pool.batched();
  if (batched) {
    const defaultLPMode = await myPoolData.pool.defaultLPMode();
    // Delta may not be performed during batch mode, so we perform it preemptively for e2e
    await receipt(myChain.bridge.callDelta(myPoolData.poolId, defaultLPMode));
  }

  // send credits to related peer pools
  const peerPools = await getPeerPools(chains, chIndex, poolIdx);
  for (let peerPool of peerPools) {
    if (peerPool.chainId == myChain.chainId) {
      const tx = await receipt(
        myChain.bridge.sendCreditInLedger(
          myPoolData.poolId,
          peerPool.pooldata.poolId
        )
      );
    } else {
      const channelInfo = myChain.channelInfo.find(
        (ci) => ci.chainId === peerPool.chainId
      )!;
      const relayerFee = await calcRelayerFee(
        myChain,
        peerPool.chain,
        FUNCTION_TYPE.SendCredit
      );
      const tx = await receipt(
        myChain.bridge.sendCredit(
          channelInfo.channelId,
          myPoolData.poolId,
          peerPool.pooldata.poolId,
          myChain.wallet.address,
          { value: relayerFee.toString() }
        )
      );
    }
  }

  const timeout = Date.now() + 300 * 1000; //5min
  while (true) {
    const revPeerPoolInfos1 = await getReversePeerPoolInfos(
      chains,
      chIndex,
      poolIdx
    );
    if (doDump) {
      await dump(revPeerPoolInfos1);
    }
    let sentSum = BigInt(0);
    for (let j = 0; j < revPeerPoolInfos0.length; ++j) {
      sentSum +=
        BigInt(revPeerPoolInfos1[j].peerPoolInfo.balance) -
        BigInt(revPeerPoolInfos0[j].peerPoolInfo.balance);
    }

    // Credits is divided by the number of Pools from amountGD.
    // Since the divided credit is rounded down, the total of the credits and amountGD will have a difference of revPeerPoolInfos0.length - 1.
    if (amountGD <= sentSum + BigInt(revPeerPoolInfos0.length) - BigInt(1)) {
      console.log("  succeed");
      break;
    }
    if (timeout < Date.now()) {
      throw new Error("timeout");
    }
    await setTimeout(3000);
  }
};

export const mintPseudoToken = async (
  pooledToken: toki.tt.PseudoToken,
  amount: bigint,
  recipient: string
) => {
  await receipt(pooledToken.mint(recipient, amount));
};

export const depositETHVault = async (
  ethVault: toki.tt.ETHVault,
  amount: bigint
) => {
  await receipt(ethVault.deposit({ value: amount }));
};

const watchContracts = (ch: Chain): Map<string, ethers.BaseContract[]> => {
  const contracts = new Map<string, ethers.BaseContract[]>();
  contracts.set("MockOuterService", [ch.mockOuterService, ch.mockOuterService]);
  contracts.set("Bridge", [ch.bridge, ch.bridge]);
  contracts.set("Bridge(BridgeFallback)", [ch.bridge, ch.bridgeFallback]);
  contracts.set("BridgeFallback", [ch.bridgeFallback, ch.bridgeFallback]);
  contracts.set("Bridge(BridgeChannelUpgradeFallback", [ch.bridge, ch.bridgeChannelUpgradeFallback]);
  contracts.set("BridgeChannelUpgradeFallback", [ch.bridgeChannelUpgradeFallback, ch.bridgeChannelUpgradeFallback]);
  contracts.set("IBCHandler", [ch.ibcHandler, ch.ibcHandler]);
  ch.pooldata.forEach((pd, i) => {
    contracts.set(`Pool[${i}, id=${pd.poolId}]`, [pd.pool, pd.pool]);
    contracts.set(`PooledToken[${i}, id=${pd.poolId}]`, [
      pd.pooledToken,
      pd.pooledToken,
    ]);
  });
  contracts.set("Payable", [ch.mockPayable, ch.mockPayable]);
  contracts.set("Unpayable", [ch.mockUnpayable, ch.mockUnpayable]);
  return contracts;
};
export const unwatchEvents = async (ch: Chain) => {
  const contracts = watchContracts(ch);
  for (const [k, v] of contracts) {
    await v[0].removeAllListeners();
  }
};
export const watchEvents = async (ch: Chain) => {
  const contracts = watchContracts(ch);
  const head = `emit: chainId=${ch.chainId}`;
  for (const [k, v] of contracts) {
    await v[0].on("*", (ev: any) => {
      const evLog = v[1].interface.parseLog(ev.log);
      if (evLog != null) {
        console.log(`${head}: ${k}: ${evLog.name}`, evLog.args);
        ch.eventHandlers.forEach((h) => {
          if (
            (h.contract == null || h.contract.test(k)) &&
            (h.name == null || h.name.test(evLog.name))
          ) {
            if (h.handler == null) {
              console.log(evLog);
            } else {
              h.handler(ch, k, evLog);
            }
          }
        });
        /*
        if (evLog.name == 'RevertReceive') {
          console.log(evLog);
          //process.exit();
        }
        if (evLog.name.includes('Debug')) {
          console.log(evLog);
          //process.exit();
        }
*/
      } else {
        console.log(`${head}: ${k}: unparsed event: `, ev.log);
      }
    });
  }
};
