import { ethers, createSigner, receipt, setTimeout, Chain } from "./lib";
import * as lib from './lib';

type Side = {
  chain: Chain,
  chainId: number,
  walletAddress: string,
  bridge: lib.toki.tt.IBridge,
  signerBridge: lib.toki.tt.IBridge,
  poolData: lib.PoolData,
  pool: lib.toki.tt.Pool,
  poolIndex: number,
  poolId: number,
  pooledToken: lib.toki.tt.PseudoToken,
  signerPooledToken: lib.toki.tt.PseudoToken,
  signer: ethers.Signer,
  signerAddress: string,
  amountLD: bigint,
}

const createParam = async (chain: Chain, poolIndex: number): Promise<Side> => {
  const poolData = chain.pooldata[poolIndex];
  if (! lib.isPseudoToken(poolData.pooledToken)) {
    throw new Error("not a PseudoToken");
  }
  const signer = createSigner(chain);
  const signerAddress = await signer.getAddress();
  return {
    chain,
    chainId: chain.chainId,
    walletAddress: chain.wallet.address,
    bridge: chain.bridge,
    signerBridge: chain.bridge.connect(signer),
    poolData,
    pool: poolData.pool,
    poolIndex: poolIndex,
    poolId: poolData.poolId,
    pooledToken: poolData.pooledToken,
    signerPooledToken: poolData.pooledToken.connect(signer),
    signer, signerAddress,
    amountLD: BigInt(0),
  };
};

type State = {
  native: bigint,
  pooled: bigint,
  liquid: bigint,
}
const getState = async (chains: Chain[], proact: Side, react: Side, dump: boolean): Promise<State[]> => {
  const now = new Date();

  const sides = [
    {
      side: proact,
      peerPoolInfo: await proact.pool.getPeerPoolInfo(react.chainId, react.poolId),
    },
    {
      side: react,
      peerPoolInfo: await react.pool.getPeerPoolInfo(proact.chainId, proact.poolId),
    },
  ];

  const ret = [];
  for (let s of sides) {
    ret.push({
      pooled: await s.side.pooledToken.balanceOf(s.side.signerAddress) as bigint,
      liquid: await s.side.pool.balanceOf(s.side.signerAddress) as bigint,
      native: await s.side.chain.provider.getBalance(s.side.signerAddress),
    } as State);
  }

  if (dump) {
    console.log(now.toISOString());

    for (let i=0; i<sides.length; ++i) {
      const s = sides[i];
      console.log("networkId=", s.side.chain.network.chainId, ", chainId=", s.side.chainId);

      console.log("  account's holdings:");
      console.log("    nativeToken=", await ret[i].native);
      console.log("    pooledToken=", await ret[i].pooled);
      console.log("    LiquidToken=", await ret[i].liquid);

      console.log(`  PeerPoolInfo(id=${s.peerPoolInfo.id}):`);
      console.log("    balance=", s.peerPoolInfo.balance);
      console.log("    lastKnownBalance=", s.peerPoolInfo.lastKnownBalance);
      console.log("    targetBalance=", s.peerPoolInfo.targetBalance);
      console.log("    credits=", s.peerPoolInfo.credits);
    }
  }
  console.log("\n");
  return ret;
}

export const testWithdrawLocal = async (chains: Chain[]) => {
  console.log("== testWithdrawLocal =============");
  const proact = await createParam(chains[0], 0);
  const react = await createParam(chains[1], 1);

  const decimals = await proact.pooledToken.decimals();
  const amountLD = BigInt(4700) * (BigInt(10) ** decimals);
  const amountGD = await lib.toki.util.LDToGD(proact.pool, amountLD);
  proact.amountLD = amountLD * BigInt(2); // actual LP balance is balance * (supply / liquidity)
  react.amountLD = await lib.toki.util.GDToLD(react.pool, amountGD);

  console.log("  proact account: ", proact.signerAddress);
  console.log("  react account:   ", react.signerAddress);
  await getState(chains, proact, react, true);
  //lib.dumpRoles();

  console.log("\n-- mint enough tokens to proact account -----------");
  await receipt(lib.fillNativeToken(proact.chain, proact.signerAddress, 5));
  await receipt(lib.fillNativeToken(react.chain, await react.bridge.getAddress(), 1));
  await receipt(proact.pooledToken.mint(proact.signerAddress, proact.amountLD));
  await getState(chains, proact, react, true);

  console.log("\n-- proact account to deposit and get LP token -----------");
  await receipt(proact.signerPooledToken.approve(await proact.bridge.getAddress(), proact.amountLD));
  await receipt(proact.signerBridge.deposit(proact.poolData.poolId, proact.amountLD, proact.signerAddress));
  const batched = await proact.poolData.pool.batched();
  if (batched) {
    const defaultLPMode = await proact.poolData.pool.defaultLPMode();
    // Delta may not be performed during batch mode, so we perform it preemptively for e2e
    await receipt(proact.signerBridge.callDelta(proact.poolData.poolId, defaultLPMode));
  }

  await getState(chains, proact, react, true);

  console.log("\n-- withdrawLocal -----------");
  const prev = await getState(chains, proact, react, false);
  const channelInfo = chains[0].channelInfo.find(ci => ci.chainId === chains[1].chainId)!;
  const to = proact.signerAddress;
  await receipt(proact.signerBridge.withdrawLocal(channelInfo.channelId, proact.poolId, react.poolId, amountGD, to, proact.signerAddress, { value: ethers.parseUnits("1", "ether") }));

  const timeout = Date.now() + 300 * 1000; //5min
  while (true) {
    console.log("waiting");
    //dump(chains, proact, react);
    const curr = await getState(chains, proact, react, true);

    const check = (s: string, b: boolean) => {
      console.log(`${s}...${b}`);
      return b;
    }
    let pass = true;
    pass &&= check(`proactor's balance of PooledToken is ge ${prev[0].pooled} + ${react.amountLD}`,
                   curr[0].pooled >= prev[0].pooled + react.amountLD);
    pass &&= check(`proactor's balance of LP token s le ${prev[0].liquid} + ${amountGD}`,
                   curr[0].liquid <= prev[0].liquid - amountGD);
    if (pass) {
      console.log("success");
      break;
    }
    if (timeout < Date.now()) {
      throw new Error('timeout');
    }
    await setTimeout(5000);
  }
}
