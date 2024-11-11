import { ethers, createSigner, receipt, setTimeout, Chain, PoolData } from "./lib";
import * as lib from './lib';

const getState = async (ch: Chain, pooldata: PoolData, addr: string, dump: boolean) => {
  if (! lib.isPseudoToken(pooldata.pooledToken)) {
    throw new Error("not a PseudoToken");
  }
  const now = new Date();
  const pooledTokenName = await pooldata.pooledToken.name();
  const pooledTokenBalance = await pooldata.pooledToken.balanceOf(addr);
  const liquidityTokenBalance = await pooldata.pool.balanceOf(addr);
  const deltaCredit = await pooldata.pool.deltaCredit();

  if (dump) {
    console.log(now.toISOString());
    console.log("  networkId=", ch.network.chainId, ", chainId=", ch.chainId);
    console.log(`  balance of PooledToken[${pooledTokenName}]: `, pooledTokenBalance);
    console.log(`  balance of LiquidityToken[poolId=${pooldata.poolId}]: `, liquidityTokenBalance);
    console.log(`  deltaCredit of Pool: `, deltaCredit);
  }
  console.log("\n");
  return { pooledTokenBalance, liquidityTokenBalance, deltaCredit };
}

export const testWithdrawInstant = async (chains: Chain[]) => {
  console.log("-- testWithdrawInstant -----------");
  const ch = chains[0];
  const pooldata = chains[0].pooldata[0];
  const pooledToken = pooldata.pooledToken as lib.toki.tt.PseudoToken;
  const decimals = await pooldata.pooledToken.decimals();
  const amountLD = BigInt(3900) * (BigInt(10) ** decimals);
  const amountGD = await lib.toki.util.LDToGD(pooldata.pool, amountLD);
  const withdrawLD = BigInt(1800) * (BigInt(10) ** decimals);
  const withdrawGD = await lib.toki.util.LDToGD(pooldata.pool, withdrawLD);

  const alice = createSigner(chains[0]);
  const aliceAddress = await alice.getAddress();
  const aliceToken = pooledToken.connect(alice);
  const aliceBridge = ch.bridge.connect(alice);
  await getState(ch, pooldata, aliceAddress, true);
  //lib.dumpRoles();

  console.log("\n-- mint pooled token -----------");
  await receipt(pooledToken.mint(aliceAddress, amountLD));
  await receipt(lib.fillNativeToken(ch, aliceAddress, 3));
  await getState(ch, pooldata, aliceAddress, true);

  console.log(`\n-- deposit to Chain[chainId=${ch.chainId}].Pool[poolId=${pooldata.poolId}]: amountLD=${amountLD} amountGD=${amountGD} --`);
  await receipt(aliceToken.approve(await ch.bridge.getAddress(), amountLD));
  await receipt(aliceBridge.deposit(pooldata.poolId, amountLD, aliceAddress));
  const batched = await pooldata.pool.batched();
  if (batched) {
    const defaultLPMode = await pooldata.pool.defaultLPMode();
    // Delta may not be performed during batch mode, so we perform it preemptively for e2e
    await receipt(aliceBridge.callDelta(pooldata.poolId, defaultLPMode));
  }

  const s = await getState(ch, pooldata, aliceAddress, true);
  if (s.deltaCredit < withdrawGD) {
    throw new Error(`insufficient deltaCredit: deltaCredit=${s.deltaCredit}, withdrawGD=${withdrawGD}`);
  }

  console.log(`\n-- withdrawInstant LD=${withdrawLD} GD=${withdrawGD} -----------`);
  const prev = await getState(ch, pooldata, aliceAddress, false);
  await receipt(aliceBridge.withdrawInstant(pooldata.poolId, withdrawGD, aliceAddress));

  const timeout = Date.now() + 300 * 1000; //5min
  while (true) {
    console.log(`waiting token balance >= (${prev.pooledTokenBalance} + ${withdrawLD})`);
    const curr = await getState(ch, pooldata, aliceAddress, true);
    if (withdrawLD <= curr.pooledTokenBalance - prev.pooledTokenBalance &&
      withdrawGD <= prev.liquidityTokenBalance - curr.liquidityTokenBalance)
    {
      console.log("success");
      break;
    }
    if (timeout < Date.now()) {
      throw new Error('timeout');
    }
    await setTimeout(5000);
  }
}
