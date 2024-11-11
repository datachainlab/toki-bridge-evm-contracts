import { ethers, createSigner, receipt, setTimeout, Chain } from "./lib";
import * as lib from './lib';

type DstName = 'payable' | 'unpayable';
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
    retryRefuelCall: null | {
      sequence: bigint,
      data: null | lib.toki.util.RetryRefuelCall,
    },
  },
  dst: {
    name: string,
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
    dstBridge: {
      address: "",
      nativeToken: BigInt(0),
      refuelDstCap: BigInt(0),
      retryRefuelCall: null,
    },
    dst: {
      name: "",
      address: "",
      nativeToken: BigInt(0),
      pooledToken: BigInt(0),
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
  if (state.dstBridge.retryRefuelCall != null) {
    const x = state.dstBridge.retryRefuelCall;
    console.log(`  retryRefuelCall[${x.sequence}]: `);
    console.log(`    data = `, x.data);
  }
  console.log(`  dst.${state.dst.name}: `,
              "native=", state.dst.nativeToken,
              "pooled=", state.dst.pooledToken
             );

  console.log("\n");

  return state;
}

const getState = async (chains: Chain[], alice: ethers.Signer, dstName: DstName, seq: null|bigint): Promise<State> => {
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
    let retryRefuelCall = null;
    if (seq != null) {
      let data: null | lib.toki.util.Retry = null;
      const payload = await chains[1].bridge.revertReceive(
        chains[0].chainId, seq
      );
      if (payload != '0x') {
        data = lib.toki.util.decodeRetry(payload);
        if (! lib.toki.util.isRetryRefuelCall(data)) {
          console.log("not a RetryDstGas: ", data);
          throw new Error(`not a RetryDstGas: ${data.typename}`);
        }
      }
      retryRefuelCall = { sequence: seq, data };
    }
    return {
      address,
      nativeToken: await chains[1].provider.getBalance(address),
      refuelDstCap: BigInt(await chains[1].bridge.refuelDstCap()),
      retryRefuelCall,
    };
  })();
  ret.dst = await (async() => {
    const key = (dstName == 'payable') ? 'mockPayable': 'mockUnpayable';
    const address = await chains[1][key].getAddress();
    return {
      name: dstName,
      address,
      nativeToken: await chains[1].provider.getBalance(address),
      pooledToken: await chains[1].pooldata[1].pooledToken.balanceOf(address),
    };
  })();

  return ret as State;
}

const waitState = async (
  desc: string,
  fnGetState: () => Promise<State>,
  fnBreak: (s1:State) => boolean,
): Promise<State> => {
  const timeout = Date.now() + 300 * 1000;
  while (true) {
    console.log(`waiting ${desc}`);

    const state = await fnGetState();
    if (fnBreak(state)) {
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
  txValue: bigint,
  alice: ethers.Signer,
  aliceAddress: string,
  payableAddress: string,
  unpayableAddress: string,
  state: State,
};
const prepare = async (name: string, dstName: DstName, chains: Chain[]): Promise<Prepare> => {
  console.log(`-- ${name} -----------`);
  chains[1].eventHandlers.push({ name: /RevertReceive/ });
  chains[1].eventHandlers.push({ name: /MockUnpayableReceived/ });
  chains[1].eventHandlers.push({ name: /MockPayableReceived/ });

  if (! lib.isPseudoToken(chains[0].pooldata[0].pooledToken)) {
    throw new Error("not a PseudoToken");
  }


  const src_decimals = await chains[0].pooldata[0].pooledToken.decimals();
  const pooledTokenAmount = BigInt(390) * (BigInt(10) ** src_decimals);
  const minPooledTokenAmount = pooledTokenAmount * BigInt(988) / BigInt(1000);
  const refuelAmount = ethers.parseUnits("0.001", "ether");
  const txValue = ethers.parseUnits("0.15", "ether");

  const relayerFee = await lib.calcRelayerFee(chains[0], chains[1], lib.FUNCTION_TYPE.TransferPool);
  const srcNativeAmount = await lib.calcSrcNativeAmount(chains[0], chains[1], BigInt(0), refuelAmount);
  if (txValue < relayerFee + srcNativeAmount) {
    throw new Error(`txValue should at least be >= relayerFee + srcNativeAmount: ${txValue} < ${relayerFee} + ${srcNativeAmount}`);
  }

  const alice = lib.createSigner(chains[0]);
  const aliceAddress = await alice.getAddress();
  const payableAddress = await chains[1].mockPayable.getAddress();
  const unpayableAddress = await chains[1].mockUnpayable.getAddress();
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
  console.log("  Payable address: ", payableAddress);
  console.log("  Unpayable address: ", unpayableAddress);
  dump(await getState(chains, alice, dstName, null));
  //lib.dumpRoles();

  console.log(`  src.relayer: `,
              "native=", await chains[0].provider.getBalance(chains[0].relayerAddress),
              );
  console.log(`  dst.relayer: `,
              "native=", await chains[1].provider.getBalance(chains[1].relayerAddress),
              );

  console.log("\n---- mint -----------");
  await receipt(lib.fillNativeToken(chains[0], aliceAddress, 0.3));
  // same as refuelAmount
  await receipt(lib.fillNativeToken(chains[1], await chains[1].bridge.getAddress(), 0.001));
  await receipt(chains[0].pooldata[0].pooledToken.mint(aliceAddress, pooledTokenAmount));
  const alicePooledToken = chains[0].pooldata[0].pooledToken.connect(alice);
  await receipt(alicePooledToken.approve(await chains[0].bridge.getAddress(), pooledTokenAmount));

  const state = dump(await getState(chains, alice, dstName, null));

  return {
    srcPoolId,
    dstPoolId,
    pooledTokenAmount,
    minPooledTokenAmount,
    pooledTokenAmountDst,
    refuelAmount,
    txValue,
    alice,
    aliceAddress,
    payableAddress,
    unpayableAddress,
    state,
  };
}

type TransferPool = {
  seq: bigint,
};
const transferPool = async (chains: Chain[], pre: Prepare, dstName: DstName, refuelAmount: bigint): Promise<TransferPool> => {
  console.log("\n---- transferPool -----------");

  const extInfo = {
    payload: new Uint8Array([]),
    dstOuterGas: 0,
  };
  const channelInfo = {
    port: chains[1].channelInfo[0].portId,
    channel: chains[1].channelInfo[0].channelId,
  };

  const seq = await chains[1].ibcHandler.getNextSequenceRecv(channelInfo.port, channelInfo.channel);
  console.log("nextSequence = ", seq);

  const bridge = chains[0].bridge.connect(pre.alice);
  const from = pre.aliceAddress;
  const to = lib.encodeAddressPacked( (dstName=="payable") ? pre.payableAddress : pre.unpayableAddress);
  await receipt(bridge.transferPool(
    channelInfo.channel,
    pre.srcPoolId,
    pre.dstPoolId,
    pre.pooledTokenAmount,
    pre.minPooledTokenAmount,
    to,
    refuelAmount,
    extInfo,
    from,
    { value: pre.txValue }
  ));

  return {
    seq,
  };
}

const checkDstNativeBalance = (state0: State, state1: State, delta: bigint) => {
  const b0 = state0.dst.nativeToken;
  const b1 = state1.dst.nativeToken;
  if (b1 - b0 < delta) {
    throw new Error(`dst's native balance: ${b1} - ${b0} should >= ${delta}`);
  }
}
const checkDstPooledTokenBalance = (state0: State, state1: State, delta: bigint) => {
  const b0 = state0.dst.pooledToken;
  const b1 = state1.dst.pooledToken;
  if (b1 - b0 < delta) {
    throw new Error(`dst's PooledToken balance: ${b1} - ${b0} should >= ${delta}`);
  }
}
const checkRetryRefuelCall = (state1: State, exists: boolean) => {
  const data = state1.dstBridge.retryRefuelCall!.data;
  if (exists) {
    if (data == null) {
      throw new Error(`RetryRefuelCall is not exists`);
    } else if (! lib.toki.util.isRetryRefuelCall(data)) {
      throw new Error(`other retry is exists: ${data}`);
    }
  } else {
    if (data != null && lib.toki.util.isRetryRefuelCall(data)) {
      throw new Error(`RetryRefuelCall is exists: ${data}`);
    }
  }
}

export const testOuterCall_success = async (chains: Chain[]) => {
  const dstName = "payable";
  const pre = await prepare('testOuterCall_Success', dstName, chains);

  await receipt(chains[1].mockPayable.setReceiveFail(false));
  await receipt(chains[1].mockPayable.setFallbackFail(true)); // fallback is not called

  const state0 = await getState(chains, pre.alice, dstName, null);
  dump(state0);
  const tt = await transferPool(chains, pre, dstName, pre.refuelAmount);
  console.log("seq=", tt.seq);

  const state = await waitState(
    `${dstName}'s balance is increased`,
    async () => dump(await getState(chains, pre.alice, dstName, tt.seq)),
    (s) => (state0.dst.nativeToken < s.dst.nativeToken),
  );

  checkDstNativeBalance(state0, state, pre.refuelAmount);
  checkDstPooledTokenBalance(state0, state, pre.pooledTokenAmountDst);
  checkRetryRefuelCall(state, false);

  console.log("success");
}

export const testOuterCall_fail_revert = async (chains: Chain[]) => {
  const dstName = "payable";
  const pre = await prepare('testOuterCall_fail_revert', dstName, chains);

  await receipt(chains[1].mockPayable.setReceiveFail(true));
  await receipt(chains[1].mockPayable.setFallbackFail(true));

  const state0 = await getState(chains, pre.alice, dstName, null);
  dump(state0);
  const tt = await transferPool(chains, pre, dstName, pre.refuelAmount);
  console.log("seq=", tt.seq);

  const state = await waitState(
    `RevertDstGas is queued`,
    async () => dump(await getState(chains, pre.alice, dstName, tt.seq)),
    (s) => (s.dstBridge.retryRefuelCall!.data != null),
  );

  checkDstPooledTokenBalance(state0, state, pre.pooledTokenAmountDst);
  checkDstNativeBalance(state0, state, BigInt(0));
  checkRetryRefuelCall(state, true);

  console.log("success");
}

export const testOuterCall_fail_bridge_gas = async (chains: Chain[]) => {
  const dstName = "payable";
  const pre = await prepare('testOuterCall_fail_bridge_gas', dstName, chains);

  await receipt(chains[1].mockPayable.setReceiveFail(false));
  await receipt(chains[1].mockPayable.setFallbackFail(true));

  const dstBalance = await chains[1].provider.getBalance(await chains[1].bridge.getAddress());
  await receipt(chains[1].bridge.draw(dstBalance, chains[1].wallet.address));

  console.log("\n-- withdraw from dst.bridge -----------");
  const state0 = await getState(chains, pre.alice, dstName, null);
  dump(state0);

  const tt = await transferPool(chains, pre, dstName, pre.refuelAmount);
  const state = await waitState(
    `RevertDstGas is queued`,
    async () => dump(await getState(chains, pre.alice, dstName, tt.seq)),
    (s) => (s.dstBridge.retryRefuelCall!.data != null),
  );

  checkRetryRefuelCall(state, true);

  // recover dst.bridge's balance
  await receipt(chains[1].wallet.sendTransaction({
    to: await chains[1].bridge.getAddress(),
    value: dstBalance,
  }));

  console.log("success");
}
