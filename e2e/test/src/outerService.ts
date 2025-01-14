import { ethers, createSigner, receipt, setTimeout, Chain } from "./lib";
import * as lib from './lib';

type State = {
  date: Date,
  src: {
    address: string,
    nativeToken: bigint,
    pooledToken: bigint,
  },
  dstBridge: {
    address: string,
    nativeToken: bigint,
    refuelDstCap: bigint,
    retry: null | {
      sequence: bigint,
      data: null | lib.toki.util.Retry,
    },
  },
  dstOuterService: {
    address: string,
    nativeToken: bigint,
    pooledToken: bigint,
  },
};
const defaultState = (): State => {
  return {
    date: new Date(),
    src: {
      address: "",
      nativeToken: BigInt(0),
      pooledToken: BigInt(0),
    },
    dstOuterService: {
      address: "",
      nativeToken: BigInt(0),
      pooledToken: BigInt(0),
    },
    dstBridge: {
      address: "",
      nativeToken: BigInt(0),
      refuelDstCap: BigInt(0),
      retry: null,
    },
  };
};

const dump = (state: State): State => {
  console.log(state.date.toISOString());

  console.log(`  src.alice: `,
              "native=", state.src.nativeToken,
              "pooled=", state.src.pooledToken
             );
  console.log(`  dst.Bridge: `,
              "native=", state.dstBridge.nativeToken,
              "refuelDstCap=", state.dstBridge.refuelDstCap,
             );
  if (state.dstBridge.retry != null) {
    const x = state.dstBridge.retry;
    console.log(`  retry[${x.sequence}]: `);
    console.log(`    data = `, x.data);
  }
  console.log(`  dst.OuterService: `,
              "native=", state.dstOuterService.nativeToken,
              "pooled=", state.dstOuterService.pooledToken
             );

  console.log("\n");

  return state;
}

const getState = async (chains: Chain[], alice: ethers.Signer, seq: null|bigint): Promise<State> => {
  const ret = defaultState();

  ret.src = await (async() => {
    const address = await alice.getAddress();
    return {
      address,
      nativeToken: await chains[0].provider.getBalance(address),
      pooledToken: await chains[0].pooldata[0].pooledToken.balanceOf(address),
    };
  })();
  ret.dstBridge = await (async() => {
    const address = await chains[1].bridge.getAddress();
    let retry = null;
    if (seq != null) {
      let data: null | any = null;
      const payload = await chains[1].bridge.revertReceive(
        chains[0].chainId, seq
      );
      if (payload != '0x') {
        data = lib.toki.util.decodeRetry(payload);
        console.log(data);
      }
      retry = { sequence: seq, data };
    }
    return {
      address,
      nativeToken: await chains[1].provider.getBalance(address),
      refuelDstCap: BigInt(await chains[1].bridge.refuelDstCap()),
      retry,
    };
  })();
  ret.dstOuterService = await (async() => {
    const address = await chains[1].mockOuterService.getAddress();
    return {
      address,
      nativeToken: await chains[1].provider.getBalance(address),
      pooledToken: await chains[1].pooldata[1].pooledToken.balanceOf(address),
    };
  })();

  return ret as State;
}

const waitState = async (
  desc: string,
  state0: State,
  timeout_msec: number|null,
  fnGetState: () => Promise<State>,
  fnBreak: (s0:State, s1:State) => boolean,
): Promise<State> => {
  const timeout = Date.now() + (timeout_msec ?? 300) * 1000;
  while (true) {
    console.log(`waiting ${desc}`);

    const state = await fnGetState();
    if (fnBreak(state0, state)) {
      return state;
    }

    if (timeout < Date.now()) {
      throw new Error('timeout');
    }
    await setTimeout(5000);
  }
}

type Prepare = {
  srcPoolId: number,
  dstPoolId: number,
  pooledTokenAmount: bigint,
  minPooledTokenAmount: bigint,
  pooledTokenAmountDst: bigint,
  refuelAmount: bigint,
  alice: ethers.Signer,
  aliceAddress: string,
  outerAddress: string,
  dstOuterGas: bigint,
};
const prepare = async (name: string, chains: Chain[]): Promise<Prepare> => {
  console.log(`-- ${name} -----------`);
  chains[1].eventHandlers.push({ name: /RevertReceive/ });

  if (! lib.isPseudoToken(chains[0].pooldata[0].pooledToken)) {
    throw new Error("not a PseudoToken");
  }

  const src_decimals = await chains[0].pooldata[0].pooledToken.decimals();
  const pooledTokenAmount = BigInt(47) * (BigInt(10) ** src_decimals);
  const minPooledTokenAmount = pooledTokenAmount * BigInt(988) / BigInt(1000);
  const refuelAmount = ethers.parseUnits("0.02", "ether");
  const dstOuterGas = ethers.parseUnits("10", "mwei");
  const alice = lib.createSigner(chains[0]);
  const aliceAddress = await alice.getAddress();
  const outerAddress = await chains[1].mockOuterService.getAddress();
  const srcPoolId = chains[0].pooldata[0].poolId;
  const dstPoolId = chains[0].pooldata[1].poolId;
  const pooledTokenAmountDst = await (async() => {
    const feeInfo = await chains[0].pooldata[0].pool.calcFee(chains[1].chainId, dstPoolId, aliceAddress, pooledTokenAmount);
    return await lib.toki.util.GDToLD(chains[1].pooldata[1].pool, feeInfo.amountGD);
  })();

  console.log(`src: name=${chains[0].name}, networkId=${chains[0].network.chainId}, chainId=${chains[0].chainId}`);
  console.log("  alice address: ", aliceAddress);
  console.log(`dst: name=${chains[1].name}, networkId=${chains[1].network.chainId}, chainId=${chains[1].chainId}`);
  console.log("  Bridge address: ", await chains[1].bridge.getAddress());
  console.log("  OuterService address: ", outerAddress);
  dump(await getState(chains, alice, null));
  //lib.dumpRoles();

  console.log(`  src.relayer: `,
              "native=", await chains[0].provider.getBalance(chains[0].relayerAddress),
              );
  console.log(`  dst.relayer: `,
              "native=", await chains[1].provider.getBalance(chains[1].relayerAddress),
              );

  console.log("\n-- mint -----------");
  await receipt(lib.fillNativeToken(chains[0], aliceAddress, 3));
  await receipt(lib.fillBridgeNativeToken(chains[1], chains[1].bridge, 3));
  await receipt(chains[0].pooldata[0].pooledToken.mint(aliceAddress, pooledTokenAmount));
  const alicePooledToken = chains[0].pooldata[0].pooledToken.connect(alice);
  await receipt(alicePooledToken.approve(await chains[0].bridge.getAddress(), pooledTokenAmount));

  dump(await getState(chains, alice, null));

  return {
    srcPoolId,
    dstPoolId,
    pooledTokenAmount,
    minPooledTokenAmount,
    pooledTokenAmountDst,
    refuelAmount,
    alice,
    aliceAddress,
    outerAddress,
    dstOuterGas,
  };
}

type TransferPool = {
  seq: bigint,
};
type ExternalInfo = {
  payload: Uint8Array,
  dstOuterGas: bigint,
}
const transferPool = async (chains: Chain[], pre: Prepare, extInfo: ExternalInfo): Promise<TransferPool> => {
  console.log("\n-- transferPool -----------");

  const channelInfo = {
    port: chains[1].channelInfo[0].portId,
    channel: chains[1].channelInfo[0].channelId,
  };
  const seq = await chains[1].ibcHandler.getNextSequenceRecv(channelInfo.port, channelInfo.channel);
  console.log("nextSequence = ", seq);

  const bridge = chains[0].bridge.connect(pre.alice);
  const from = pre.aliceAddress;
  const to = lib.encodeAddressPacked(pre.outerAddress);
  await receipt(bridge.transferPool(
    channelInfo.channel,
    pre.srcPoolId,
    pre.dstPoolId,
    pre.pooledTokenAmount,
    pre.minPooledTokenAmount,
    to,
    pre.refuelAmount,
    extInfo,
    from,
    { value: ethers.parseUnits("2", "ether") }
  ));

  return {
    seq,
  };
}

const checkOuterServiceNativeBalance = (state0: State, state1: State, delta: bigint) => {
  const b0 = state0.dstOuterService.nativeToken;
  const b1 = state1.dstOuterService.nativeToken;
  if (b1 - b0 < delta) {
    throw new Error(`OuterService's native balance: ${b1} - ${b0} should >= ${delta}`);
  }
}

const checkOuterServicePooledTokenBalance = (state0: State, state1: State, delta: bigint) => {
  const b0 = state0.dstOuterService.pooledToken;
  const b1 = state1.dstOuterService.pooledToken;
  if (b1 - b0 < delta) {
    throw new Error(`OuterService's PooledToken balance: ${b1} - ${b0} should >= ${delta}`);
  }
}
const checkRetryExternal = (state1: State, should_exists: boolean) => {
  const data = state1.dstBridge.retry!.data;
  if (should_exists) {
    if (data == null) {
      throw new Error(`RetryExternal is not exists`);
    } if (! lib.toki.util.isRetryExternalCall(data)) {
      throw new Error(`other retry is exists: ${data.typename}`);
    }
  } else {
    if (data != null && lib.toki.util.isRetryExternalCall(data)) {
      throw new Error(`RetryExternal is exists: ${data}`);
    }
  }
}

export const testOuterService_success = async (chains: Chain[]) => {
  const pre = await prepare('testOuterService_Success', chains);

  await receipt(chains[1].mockOuterService.setForceFail(false));

  const state0 = await getState(chains, pre.alice, null);
  dump(state0);
  const tt = await transferPool(chains, pre, {
    payload: new Uint8Array([39,40,41]),
    dstOuterGas: pre.dstOuterGas,
  });
  console.log("seq=", tt.seq);

  const state = await waitState(
    "OuterSrevice's balance is increased",
    state0,
    null,
    async () => dump(await getState(chains, pre.alice, tt.seq)),
    (s0, s1) => (s0.dstOuterService.nativeToken < s1.dstOuterService.nativeToken),
  );

  checkOuterServiceNativeBalance(state0, state, pre.refuelAmount);
  checkOuterServicePooledTokenBalance(state0, state, pre.pooledTokenAmountDst);
  checkRetryExternal(state, false);

  console.log("success");
}

export const testOuterService_fail_outOfGas = async (chains: Chain[]) => {
  const pre = await prepare('testOuterService_fail_outOfGas', chains);

  await receipt(chains[1].mockOuterService.setForceFail(false));

  const state0 = await getState(chains, pre.alice, null);
  dump(state0);
  const tt = await transferPool(chains, pre, {
    payload: new Uint8Array([39,40,41]),
    dstOuterGas: ethers.parseUnits("0", "ether"),
  });
  console.log("seq=", tt.seq);

  const state = await waitState(
    "OuterSrevice's balance is increased",
    state0,
    null,
    async () => dump(await getState(chains, pre.alice, tt.seq)),
    (s0, s1) => (s0.dstOuterService.nativeToken < s1.dstOuterService.nativeToken),
  );

  checkOuterServiceNativeBalance(state0, state, pre.refuelAmount);
  checkOuterServicePooledTokenBalance(state0, state, pre.pooledTokenAmountDst);
  checkRetryExternal(state, true);

  console.log("success");
}

export const testOuterService_fail_revert = async (chains: Chain[]) => {
  const pre = await prepare('testOuterService_fail_revert', chains);

  await receipt(chains[1].mockOuterService.setForceFail(true));

  const state0 = await getState(chains, pre.alice, null);
  dump(state0);
  const tt = await transferPool(chains, pre, {
    payload: new Uint8Array([39,40,41]),
    dstOuterGas: pre.dstOuterGas,
  });

  const state = await waitState(
    "OuterSrevice's balance is increased",
    state0,
    null,
    async () => dump(await getState(chains, pre.alice, tt.seq)),
    (s0, s1) => (s0.dstOuterService.nativeToken < s1.dstOuterService.nativeToken),
  );

  checkOuterServiceNativeBalance(state0, state, pre.refuelAmount);
  checkOuterServicePooledTokenBalance(state0, state, pre.pooledTokenAmountDst);
  checkRetryExternal(state, true);

  console.log("success");
}
