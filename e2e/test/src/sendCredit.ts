import * as lib from "./lib";
import {Chain, getPeerPools, getReversePeerPoolInfos, receipt, setTimeout} from "./lib";

const dump = async (chains: Chain[]) => {
  const now = new Date();
  console.log("\n", now.toISOString());
  for (let ch of chains) {
    console.log("networkId=", ch.network.chainId, ", chainId=", ch.chainId);
    console.log("  eth.balance=", await ch.provider.getBalance(ch.wallet.address));
    for (let pooldata of ch.pooldata) {
      console.log(`  Chain[chainId=${ch.chainId}].Pool[poolId=${pooldata.poolId}]:`);
      console.log("    pool.balance=", await pooldata.pool.balanceOf(ch.wallet.address));
      console.log("    pooled.balance=", await pooldata.pooledToken.balanceOf(ch.wallet.address));
    }
  }
}

export const testSendCredit = async (chains: Chain[]) => {
  console.log("-- testSendCredit -----------");
  const getParam = (chainIndex: number, poolIdx: number) => {
    const chain = chains[chainIndex];
    return {
      chain,
      chainId: chain.chainId,
      address: chain.wallet.address,
      bridge: chain.bridge,
      pooldata: chains[chainIndex].pooldata,
      pooledToken: chains[chainIndex].pooldata[poolIdx].pooledToken as lib.toki.tt.PseudoToken,
    };
  };
  const srcChainIndex = 0
  const srcPoolIndex = 0
  const src = getParam(srcChainIndex, srcPoolIndex);
  const srcPoolId = src.pooldata[srcPoolIndex].poolId;

  const getBalanceOfPeerPool = async (): Promise<bigint[]> => {
    const peerPoolInfo = await getReversePeerPoolInfos(chains, srcChainIndex, srcPoolIndex);
    const balances: bigint[] = [];

    for (let ppi of peerPoolInfo) {
      balances.push(ppi.peerPoolInfo.balance);
    }
    return balances;
  };

  const amountLD = BigInt(3900);
  const amountGD = await lib.toki.util.LDToGD(src.pooldata[srcPoolId].pool, amountLD);

  console.log(`\nmint on Chain[chainId=${src.chainId}].Pool[poolId=${srcPoolId}]: amountLD=${amountLD} amountGD=${amountGD}`);
  await receipt(src.pooledToken.mint(src.address, amountLD));
  await dump(chains);

  console.log(`\ndeposit to Chain[chainId=${src.chainId}].Pool[poolId=${srcPoolId}]: amountLD=${amountLD} amountGD=${amountGD}`);
  await receipt(src.pooledToken.approve(await src.bridge.getAddress(), amountLD));
  await receipt(src.bridge.deposit(srcPoolId, amountLD, src.address));
  await dump(chains);

  console.log(`\nsendCredit from Chain[chainId=${src.chainId}].Pool[poolId=${srcPoolId}]`);
  const prevBalance = await getBalanceOfPeerPool();
  const peerPools = await getPeerPools(chains, srcChainIndex, srcPoolIndex);
  for (let peerPool of peerPools) {
    console.log(`  to Chain[chainId=${peerPool.chainId}].Pool[poolId=${peerPool.pooldata.poolId}]`);
    if (src.chainId == peerPool.chainId) {
      await receipt(src.bridge.sendCreditInLedger(srcPoolId, peerPool.pooldata.poolId));
    } else {
      const channelInfo = chains[0].channelInfo.find(ci => ci.chainId === peerPool.chainId)!;
      const relayerFee = await lib.calcRelayerFee(src.chain, peerPool.chain, lib.FUNCTION_TYPE.SendCredit, new Uint8Array(), 0);
      await receipt(src.bridge.sendCredit(channelInfo.channelId, srcPoolId, peerPool.pooldata.poolId, src.address, { value: relayerFee.toString() } ));
    }
  }

  const nPeers = BigInt(prevBalance.length);
  console.log(nPeers)
  const addCredit = (amountGD / nPeers) - BigInt(1);
  const timeout = Date.now() + 300 * 1000; //5min
  while (true) {
    console.log(`\nwaiting balance of counterpart's PeerPool(${src.chainId}, ${srcPoolId}) is ge prevBalance + ${amountGD}/${nPeers}`);
    dump(chains);
    const currBalance = await getBalanceOfPeerPool();
    let allok = true;
    for (let i=0; i<prevBalance.length; ++i) {
      allok = allok && (addCredit <= currBalance[i] - prevBalance[i]);
    }
    if (allok) {
      console.log("success");
      break;
    }
    if (timeout < Date.now()) {
      throw new Error('timeout');
    }
    await setTimeout(5000);
  }
}
