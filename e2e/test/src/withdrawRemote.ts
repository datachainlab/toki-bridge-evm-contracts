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
    poolId: poolData.poolId,
    pooledToken: poolData.pooledToken as lib.toki.tt.PseudoToken,
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
const getState = async (chains: Chain[], src: Side, dst: Side, dump: boolean): Promise<State[]> => {
  const now = new Date();

  const sides = [
    {
      side: src,
      peerPoolInfo: await src.pool.getPeerPoolInfo(dst.chainId, dst.poolId),
    },
    {
      side: dst,
      peerPoolInfo: await dst.pool.getPeerPoolInfo(src.chainId, src.poolId),
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

      console.log("  PeerPoolInfo:");
      console.log("    balance=", s.peerPoolInfo.balance);
      console.log("    lastKnownBalance=", s.peerPoolInfo.lastKnownBalance);
      console.log("    credits=", s.peerPoolInfo.credits);
    }
  }
  console.log("\n");
  return ret;
}

export const testWithdrawRemote = async (chains: Chain[]) => {
  console.log("== testWithdrawRemote =============");
  const src = await createParam(chains[0], 0);
  const dst = await createParam(chains[1], 1);

  const src_decimals = await src.pooledToken.decimals();
  const amountLD = BigInt(4700) * (BigInt(10) ** src_decimals);
  const amountGD = await lib.toki.util.LDToGD(src.pool, amountLD);
  src.amountLD = amountLD * BigInt(2); // actual LP balance is balance * (supply / liquidity)

  console.log("  src account: ", src.signerAddress);
  console.log("  dst account:   ", dst.signerAddress);
  await getState(chains, src, dst, true);
  //lib.dumpRoles();

  console.log(`-- check dst pool has enough tokens -----------`);
  {
    const srcPeerPoolInfo = await src.pool.getPeerPoolInfo(dst.chainId, dst.poolId);
    console.log(`balance of (${src.chainId}, ${src.poolId}) -> (${dst.chainId}, ${dst.poolId}): `, srcPeerPoolInfo.balance);
    if (BigInt(srcPeerPoolInfo.balance) < amountGD) {
      throw new Error('insufficient balance: run `npm run deposit`');
    }
  }

  console.log("\n-- mint enough tokens to src account -----------");
  await receipt(lib.fillNativeToken(src.chain, src.signerAddress, 5));
  await receipt(lib.fillBridgeNativeToken(dst.chain, dst.bridge, 1));
  await receipt(src.pooledToken.mint(src.signerAddress, src.amountLD));
  await getState(chains, src, dst, true);

  console.log("\n-- src account to deposit and get LP token -----------");
  await receipt(src.signerPooledToken.approve(await src.bridge.getAddress(), src.amountLD));
  await receipt(src.signerBridge.deposit(src.poolData.poolId, src.amountLD, src.signerAddress));
  const batched = await src.poolData.pool.batched();
  if (batched) {
    const defaultLPMode = await src.poolData.pool.defaultLPMode();
    // Delta may not be performed during batch mode, so we perform it preemptively for e2e
    await receipt(src.signerBridge.callDelta(src.poolData.poolId, defaultLPMode));
  }
  await getState(chains, src, dst, true);

  console.log("\n-- withdrawRemote -----------");
  const feeInfo = await src.poolData.pool.calcFee(dst.chainId, dst.poolId, src.signerAddress, amountLD);
  console.log('feeInfo: ', feeInfo);
  dst.amountLD = await lib.toki.util.GDToLD(dst.pool, feeInfo.amountGD);

  const prev = await getState(chains, src, dst, false);
  const channelInfo = chains[0].channelInfo.find(ci => ci.chainId === chains[1].chainId)!;
  const to = lib.encodeAddressPacked(dst.signerAddress);
  await receipt(src.signerBridge.withdrawRemote(channelInfo.channelId, src.poolId, dst.poolId, amountGD, 10, to, src.signerAddress, { value: ethers.parseUnits("1", "ether") }));

  const timeout = Date.now() + 300 * 1000; //5min
  while (true) {
    console.log("waiting");
    //dump(chains, src, dst);
    const curr = await getState(chains, src, dst, true);

    const check = (s: string, b: boolean) => {
      console.log(`${s}...${b}`);
      return b;
    }
    let pass = true;
    pass &&= check(`dst token balance is ge ${prev[1].pooled} + ${dst.amountLD}`,
                   curr[1].pooled >= prev[1].pooled + dst.amountLD);
    pass &&= check(`src LP token balance is le ${prev[0].liquid} + ${amountGD}`,
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
