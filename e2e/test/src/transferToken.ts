import { ethers, createSigner, receipt, setTimeout, Chain } from "./lib";
import * as lib from './lib';

const dump = async (chains: Chain[], alice: ethers.Signer, bob: ethers.Signer) => {
  const now = new Date();
  console.log(now.toISOString());
  for (let i=0; i<2; ++i) {
    const ch = chains[i];
    const peer = chains[i ^ 1];
    console.log("networkId=", ch.network.chainId, ", chainId=", ch.chainId);

    const dumpAccount = async(name: string, addr: string) => {
      console.log(`  ${name}: `,
                  "native=", await chains[i].provider.getBalance(addr),
                  "toki=", await chains[i].tokiToken!.balanceOf(addr)
                 );
    };
    await dumpAccount("bridge", await ch.bridge.getAddress());
    await dumpAccount("alice ", await alice.getAddress());
    await dumpAccount("bob   ", await bob.getAddress());
  }
  console.log("\n");
}

export const testTransferToken = async (chains: Chain[]) => {
  console.log("-- testTransferToken -----------");
  if (chains[0].tokiToken == null) {
    console.log("TokiToken is not deployed");
    return;
  }
  const amount = BigInt(3900);
  const refuelAmount = BigInt(39);
  const alice = createSigner(chains[0]);
  const bob = createSigner(chains[1]);
  const aliceAddress = await alice.getAddress();
  const bobAddress = await bob.getAddress();
  console.log("  alice: ", aliceAddress);
  console.log("  bob:   ", bobAddress);
  await dump(chains, alice, bob);
  //lib.dumpRoles();

  console.log("\n-- mint -----------");
  await receipt(chains[0].tokiToken!.grantRole(await chains[0].tokiToken!.MINTER_ROLE(), chains[0].wallet.address));
  await receipt(chains[0].tokiToken!.mint(alice, amount));
  await receipt(lib.fillNativeToken(chains[0], aliceAddress, 3));
  await receipt(lib.fillBridgeNativeToken(chains[1], chains[1].bridge, 1));
  await dump(chains, alice, bob);

  console.log("\n-- transferToken -----------");
  const prevBobBalance = [
    await chains[1].tokiToken!.balanceOf(bobAddress),
    await chains[1].provider.getBalance(bobAddress),
  ];
  const channelInfo = chains[0].channelInfo.find(ci => ci.chainId === chains[1].chainId)!;

  const extInfo = { payload: new Uint8Array(), dstOuterGas: 0 };
  const bridge = chains[0].bridge.connect(alice);
  const to = lib.encodeAddressPacked(bobAddress);
  await receipt(bridge.transferToken(channelInfo.channelId, "denom", amount, to, refuelAmount, extInfo, await alice.getAddress(), { value: ethers.parseUnits("1", "ether") }));

  const timeout = Date.now() + 300 * 1000; //5min
  while (true) {
    console.log(`waiting bob's TokiToken is ge ${prevBobBalance} + ${amount}`);
    const currBobBalance = [
      await chains[1].tokiToken!.balanceOf(bobAddress),
      await chains[1].provider.getBalance(bobAddress),
    ];
    await dump(chains, alice, bob);
    if (amount <= currBobBalance[0] - prevBobBalance[0]
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

export const testTransferToken_fail_tokiTokenCap = async (chains: Chain[]) => {
  console.log("-- testTransferToken_fail_tokiTokenCap -----------");
  if (chains[0].tokiToken == null) {
    console.log("TokiToken is not deployed");
    return;
  }
  const amount = BigInt(3900);
  const refuelAmount = BigInt(39);
  const alice = createSigner(chains[0]);
  const bob = createSigner(chains[1]);
  const aliceAddress = await alice.getAddress();
  const bobAddress = await bob.getAddress();
  console.log("  alice: ", aliceAddress);
  console.log("  bob:   ", bobAddress);
  await dump(chains, alice, bob);
  //lib.dumpRoles();

  console.log("\n-- mint -----------");
  await receipt(chains[0].tokiToken!.grantRole(await chains[0].tokiToken!.MINTER_ROLE(), chains[0].wallet.address));
  await receipt(chains[0].tokiToken!.mint(alice, amount));
  await receipt(lib.fillNativeToken(chains[0], aliceAddress, 3));
  await receipt(lib.fillBridgeNativeToken(chains[1], chains[1].bridge, 1));
  await dump(chains, alice, bob);

  console.log("\n-- softcap -----------");
  await receipt(chains[1].tokiToken!.grantRole(await chains[1].tokiToken!.SOFTCAP_ADMIN_ROLE(), chains[1].wallet.address));
  const totalSupply = await chains[1].tokiToken!.totalSupply();
  const softcap0 = await chains[1].tokiToken!.softcap();
  await chains[1].tokiToken!.setSoftcap(totalSupply + amount - BigInt(1));
  console.log("dst.TokiToken.totalSupply: ", totalSupply);
  console.log("dst.TokiToken.softcap:     ", await chains[1].tokiToken!.softcap());
  console.log("delta:                     ", await chains[1].tokiToken!.softcap() - totalSupply);

  console.log("\n-- transferToken -----------");
  const channelInfo = chains[0].channelInfo.find(ci => ci.chainId === chains[1].chainId)!;
  const seq = await chains[1].ibcHandler.getNextSequenceRecv(channelInfo.portId, channelInfo.channelId);
  const getRevert = async () => {
    // note that currently softcat revert is not caught
    return await chains[1].bridge.revertReceive(
      chains[0].chainId, seq
    );
  };
  const prevBobBalance = [
    await chains[1].tokiToken!.balanceOf(bobAddress),
    await chains[1].provider.getBalance(bobAddress),
  ];

  const extInfo = { payload: new Uint8Array(), dstOuterGas: 0 };
  const bridge = chains[0].bridge.connect(alice);
  const to = lib.encodeAddressPacked(bobAddress);
  await receipt(bridge.transferToken(channelInfo.channelId, "denom", amount, to, refuelAmount, extInfo, await alice.getAddress(), { value: ethers.parseUnits("1", "ether") }));

  const timeout = Date.now() + 300 * 1000; //5min
  while (true) {
    console.log(`waiting revert is queued`);
    dump(chains, alice, bob);
    const revertPayload = await getRevert();
    if (revertPayload.length > 2) {
      break;
    }
    if (timeout < Date.now()) {
      throw new Error('timeout');
    }
    await setTimeout(5000);
  }

  const revertPayload = await getRevert();
  if (revertPayload == '0x') {
    throw new Error('not queued');
  }
  const currBobBalance = [
    await chains[1].tokiToken!.balanceOf(bobAddress),
    await chains[1].provider.getBalance(bobAddress),
  ];
  if (currBobBalance[0] != prevBobBalance[0]) {
    throw new Error('TokiToken balance is changed');
  }
  if (currBobBalance[1] != prevBobBalance[1]) {
    throw new Error('native token balance is changed');
  }

  await chains[1].tokiToken!.setSoftcap(softcap0);

  console.log("success");
}
