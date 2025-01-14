import { ethers, createSigner, receipt, setTimeout, Chain } from "./lib";
import * as lib from './lib';
import {toki} from './lib';

type Side<T extends lib.PooledToken> = {
  chain: Chain,
  chainId: number,
  address: string,
  bridge: toki.tt.IBridge,
  poolData: lib.PoolData,
  pool: toki.tt.Pool,
  poolId: number,
  pooledToken: T,
  signer: ethers.Signer,
  signerAddress: string,
  amountLD: bigint,
}

const createParam = async <T extends lib.PooledToken>(chain: Chain, poolIndex: number): Promise<Side<T>> => {
  const poolData = chain.pooldata[poolIndex];
  const signer = createSigner(chain);
  const signerAddress = await signer.getAddress();
  return {
    chain,
    chainId: chain.chainId,
    address: chain.wallet.address,
    bridge: chain.bridge,
    poolData,
    pool: poolData.pool,
    poolId: poolData.poolId,
    pooledToken: poolData.pooledToken,
    signer, signerAddress,
    amountLD: BigInt(0),
  } as Side<T>;
};

const dump = async <T extends lib.PooledToken, U extends lib.PooledToken>(src: Side<T>, dst: Side<U>) => {
  const now = new Date();
  console.log(now.toISOString());

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

  const dumpAccount = async (name: string, side: Side<T> | Side<U>, addr: string) => {
    console.log(`  ${name}: `,
                "nativeToken=", await side.chain.provider.getBalance(addr),
                "pooledToken=", await side.pooledToken.balanceOf(addr),
               );
  };

  for (let s of sides) {
    console.log("networkId=", s.side.chain.network.chainId, ", chainId=", s.side.chainId);

    await dumpAccount("pool ", s.side, await s.side.pool.getAddress());
    console.log("    peerPool: ",
                "balance=", s.peerPoolInfo.balance,
                "lastKnownBalance=", s.peerPoolInfo.lastKnownBalance,
                "credits=", s.peerPoolInfo.credits,
               );

    await dumpAccount("bridge", s.side, await s.side.bridge.getAddress());
    await dumpAccount("alice ", s.side, await sides[0].side.signerAddress);
    await dumpAccount("bob   ", s.side, await sides[1].side.signerAddress);
  }
  console.log("\n");
}

export const testTransferPools = async (chains: Chain[]) => {
  for (let i = 0; i <= 1; i++) {
    for (let j = i; j <= 1; j++) {
      await testTransferPool(chains, [i, j]);
      await testTransferPool([chains[1], chains[0]], [i, j]);
    }
  }
}

export const testTransferPool = async (chains: Chain[], poolIdxs: number[]) => {
  console.log("-- testTransferPool -----------");
  const src = await createParam<toki.tt.PseudoToken>(chains[0], poolIdxs[0]);
  const dst = await createParam<toki.tt.PseudoToken>(chains[1], poolIdxs[1]);
  console.log(" src: ", src.chainId, src.poolId, " dst: ", dst.chainId, dst.poolId);

  const refuelAmount = ethers.parseUnits("0.01", "ether");
  const src_decimals = await src.pooledToken.decimals();
  src.amountLD = BigInt(4700) * (BigInt(10) ** src_decimals);
  const amountGD = await lib.toki.util.LDToGD(src.pool, src.amountLD);
  const minAmountLD = src.amountLD * BigInt(988) / BigInt(1000);

  console.log("  alice: ", src.signerAddress);
  console.log("  bob:   ", dst.signerAddress);
  await dump(src, dst);
  //lib.dumpRoles();

  console.log(`-- check deposit ge ${src.amountLD}(GD=${amountGD})  -----------`);
  {
    const srcPeerPoolInfo = await src.pool.getPeerPoolInfo(dst.chainId, dst.poolId);
    console.log(`balance of (${src.chainId}, ${src.poolId}) -> (${dst.chainId}, ${dst.poolId}): `, srcPeerPoolInfo.balance);
    console.log(`amountLD=${src.amountLD}, amountGD=${amountGD}`);
    if (BigInt(srcPeerPoolInfo.balance) < amountGD) {
      throw new Error('insufficient balance: run `npm run deposit`');
    }
  }

  console.log("\n-- mint -----------");
  await receipt(lib.fillNativeToken(src.chain, src.signerAddress, 2));
  await receipt(lib.fillBridgeNativeToken(dst.chain, dst.bridge, 1));
  await receipt(src.pooledToken.mint(src.signerAddress, src.amountLD));
  await dump(src, dst);

  console.log("\n-- transferPool -----------");
  const feeInfo = await src.poolData.pool.calcFee(dst.chainId, dst.poolId, src.signerAddress, src.amountLD);
  console.log('feeInfo: ', feeInfo);
  dst.amountLD = await lib.toki.util.GDToLD(dst.pool, feeInfo.amountGD);

  const prevBobBalance = [
    await dst.pooledToken.balanceOf(dst.signerAddress),
    await dst.chain.provider.getBalance(dst.signerAddress),
  ];

  const bridge = src.bridge.connect(src.signer);
  const pooledToken = src.pooledToken.connect(src.signer);

  await receipt(pooledToken.approve(await src.bridge.getAddress(), src.amountLD));

  const extInfo = { payload: new Uint8Array(), dstOuterGas: 0 };
  const to = lib.encodeAddressPacked(dst.signerAddress);
  const channelInfo = src.chain.channelInfo.find(ci => ci.chainId === dst.chainId)!;
  await receipt(bridge.transferPool(channelInfo.channelId, src.poolId, dst.poolId, src.amountLD, minAmountLD, to, refuelAmount, extInfo, src.signerAddress, { value: ethers.parseUnits("1", "ether") }));

  const timeout = Date.now() + 300 * 1000; //5min
  while (true) {
    console.log(`waiting bob's pooledToken is ge ${prevBobBalance} + ${dst.amountLD}`);
    const currBobBalance = [
      await dst.pooledToken.balanceOf(dst.signerAddress),
      await dst.chain.provider.getBalance(dst.signerAddress),
    ];
    await dump(src, dst);
    if (dst.amountLD <= currBobBalance[0] - prevBobBalance[0]
       && refuelAmount <= currBobBalance[1] - prevBobBalance[1]) {
      console.log("success");
      break;
    }
    if (timeout < Date.now()) {
      throw new Error('timeout');
    }
    await setTimeout(5000);
  }
}

export const testTransferPoolForTokiETHFromBSCToETH = async (chains: Chain[]) => {
  console.log("-- testTransferPool for TokiETH from BSC to ETH -----------");
  const src = await createParam<toki.tt.PseudoToken>(chains[0], 2);
  const dst = await createParam<toki.tt.ETHVault>(chains[1], 2);

  src.amountLD = ethers.parseUnits("1", "ether");
  const amountGD = await lib.toki.util.LDToGD(src.pool, src.amountLD);
  const minAmountLD = src.amountLD * BigInt(988) / BigInt(1000);
  dst.amountLD = await lib.toki.util.GDToLD(dst.pool, amountGD);

  console.log("  alice: ", src.signerAddress);
  console.log("  bob:   ", dst.signerAddress);
  await dump(src, dst);

  console.log(`-- check deposit ge ${src.amountLD}(GD=${amountGD})  -----------`);
  {
    const srcPeerPoolInfo = await src.pool.getPeerPoolInfo(dst.chainId, dst.poolId);
    console.log(`balance of (${src.chainId}, ${src.poolId}) -> (${dst.chainId}, ${dst.poolId}): `, srcPeerPoolInfo.balance);
    if (BigInt(srcPeerPoolInfo.balance) < amountGD) {
      throw new Error('insufficient balance: run `npm run deposit`');
    }
  }

  console.log("\n-- mint -----------");
  await receipt(lib.fillNativeToken(src.chain, src.signerAddress, 2));
  await receipt(lib.fillBridgeNativeToken(dst.chain, dst.bridge, 1));
  await receipt(src.pooledToken.mint(src.signerAddress, src.amountLD));
  await dump(src, dst);

  console.log("\n-- transferPool -----------");
  const prevBobBalance = [
    await dst.pooledToken.balanceOf(dst.signerAddress),
    await dst.chain.provider.getBalance(dst.signerAddress),
  ];
  const channelInfo = chains[0].channelInfo.find(ci => ci.chainId === chains[1].chainId)!;
  const feeInfo = await src.poolData.pool.calcFee(dst.chainId, dst.poolId, src.signerAddress, src.amountLD);
  console.log('feeInfo: ', feeInfo);

  const bridge = src.bridge.connect(src.signer);
  const pooledToken = src.pooledToken.connect(src.signer);

  await receipt(pooledToken.approve(await src.bridge.getAddress(), src.amountLD));

  const extInfo = { payload: new Uint8Array(), dstOuterGas: 0 };
  const to = lib.encodeAddressPacked(dst.signerAddress);
  await receipt(bridge.transferPool(channelInfo.channelId, src.poolId, dst.poolId, src.amountLD, minAmountLD, to, 0, extInfo, src.signerAddress, { value: ethers.parseUnits("1", "ether") }));

  const timeout = Date.now() + 300 * 1000; //5min
  while (true) {
    console.log(`waiting bob's nativeToken is ge ${prevBobBalance} + ${dst.amountLD}`);
    const currBobBalance = [
      await dst.pooledToken.balanceOf(dst.signerAddress),
      await dst.chain.provider.getBalance(dst.signerAddress),
    ];
    await dump(src, dst);
    if (currBobBalance[0] == prevBobBalance[0]
      && currBobBalance[1] > prevBobBalance[1]) {
      console.log("success");
      break;
    }
    if (timeout < Date.now()) {
      throw new Error('timeout');
    }
    await setTimeout(5000);
  }
}

export const testTransferPoolForTokiETHFromETHToBSC = async (chains: Chain[]) => {
  console.log("-- testTransferPool for TokiETH from ETH to BSC -----------");
  const src = await createParam<toki.tt.ETHVault>(chains[1], 2);
  const dst = await createParam<toki.tt.PseudoToken>(chains[0], 2);

  src.amountLD = ethers.parseUnits("1", "ether");
  const amountGD = await lib.toki.util.LDToGD(src.pool, src.amountLD);
  const minAmountLD = src.amountLD * BigInt(988) / BigInt(1000);
  dst.amountLD = await lib.toki.util.GDToLD(dst.pool, amountGD);

  console.log("  alice: ", src.signerAddress);
  console.log("  bob:   ", dst.signerAddress);
  await dump(src, dst);

  console.log(`-- check deposit ge ${src.amountLD}(GD=${amountGD})  -----------`);
  {
    const srcPeerPoolInfo = await src.pool.getPeerPoolInfo(dst.chainId, dst.poolId);
    console.log(`balance of (${src.chainId}, ${src.poolId}) -> (${dst.chainId}, ${dst.poolId}): `, srcPeerPoolInfo.balance);
    if (BigInt(srcPeerPoolInfo.balance) < amountGD) {
      throw new Error('insufficient balance: run `npm run deposit`');
    }
  }

  console.log("\n-- mint -----------");
  await receipt(lib.fillNativeToken(src.chain, src.signerAddress, 3));
  await receipt(lib.fillBridgeNativeToken(dst.chain, dst.bridge, 1));

  await lib.depositETHVault(src.pooledToken.connect(src.signer), src.amountLD)
  await dump(src, dst);

  console.log("\n-- transferPool -----------");
  const prevBobBalance = [
    await dst.pooledToken.balanceOf(dst.signerAddress),
    await dst.chain.provider.getBalance(dst.signerAddress),
  ];
  const channelInfo = chains[0].channelInfo.find(ci => ci.chainId === chains[1].chainId)!;
  const feeInfo = await src.poolData.pool.calcFee(dst.chainId, dst.poolId, src.signerAddress, src.amountLD);
  console.log('feeInfo: ', feeInfo);

  const bridge = src.bridge.connect(src.signer);
  const pooledToken = src.pooledToken.connect(src.signer);

  await receipt(pooledToken.approve(await src.bridge.getAddress(), src.amountLD));

  const extInfo = { payload: new Uint8Array(), dstOuterGas: 0 };
  const to = lib.encodeAddressPacked(dst.signerAddress);
  await receipt(bridge.transferPool(channelInfo.channelId, src.poolId, dst.poolId, src.amountLD, minAmountLD, to, 0, extInfo, src.signerAddress, { value: ethers.parseUnits("1", "ether") }));

  const timeout = Date.now() + 300 * 1000; //5min
  while (true) {
    console.log(`waiting bob's pooledToken is ge ${prevBobBalance} + ${dst.amountLD}`);
    const currBobBalance = [
      await dst.pooledToken.balanceOf(dst.signerAddress),
      await dst.chain.provider.getBalance(dst.signerAddress),
    ];
    await dump(src, dst);
    if (currBobBalance[0] > prevBobBalance[0]
      && currBobBalance[1] == prevBobBalance[1]) {
      console.log("success");
      break;
    }
    if (timeout < Date.now()) {
      throw new Error('timeout');
    }
    await setTimeout(5000);
  }
}
