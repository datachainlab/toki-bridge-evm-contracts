import * as lib from './lib';
import {Chain, ethers, getChains} from './lib';
import {testSendCredit} from './sendCredit';
import * as transferToken from './transferToken';
import {
  testTransferPools,
  testTransferPoolForTokiETHFromBSCToETH,
  testTransferPoolForTokiETHFromETHToBSC,
} from './transferPool';
import {testWithdrawInstant} from './withdrawInstant';
import {testWithdrawRemote} from './withdrawRemote';
import {testWithdrawLocal} from './withdrawLocal';
import * as outerService from './outerService';
import * as outerCall from './outerCall';

const dump = async (chains: Chain[]) => {
  const now = new Date();
  console.log("\n", now.toISOString());
  for (let i=0; i<2; ++i) {
    const ch = chains[i];
    const peer = chains[i ^ 1];
    console.log(`chains[${i}]: `, "chainId=", ch.network.chainId);
  }
}

const setup = async (): Promise<Chain[]> => {
  const chains = await getChains();
  await dump(chains);
  return chains;
}

const run = async (targets: string[], chains: Chain[]) => {
  if (targets.includes("deposit")) {
    for (const [chainIndex, chain] of chains.entries()){
      for (const [poolIndex, pool] of chain.pooldata.entries()){
        let amount;
        if (pool.pooledTokenContractName == "ETHVault" && chain.ethChain !== undefined) {
          amount = ethers.parseUnits("100", "ether");
          // Unlike other ERC20s, ETHVault mints tokens in exchange for Ether.
          console.log("ethValut.deposit: ", amount);
          console.log(`from addr=`, chain.wallet.address);
          console.log(`native token=`, await chain.provider.getBalance(chain.wallet.address));
          await lib.depositETHVault(chain.ethChain.ethVault, amount);
        } else if (pool.pooledTokenName == "Ethereum Token") { // WETH on BSC
          const pt = pool.pooledToken as lib.toki.tt.PseudoToken;
          amount = ethers.parseUnits("100", "ether");
          await lib.mintPseudoToken(pt, amount, chain.wallet.address);
        } else {
          const pt = pool.pooledToken as lib.toki.tt.PseudoToken;
          const decimals = await pool.pooledToken.decimals();
          amount = BigInt(100000) * (BigInt(10) ** decimals);
          await lib.mintPseudoToken(pt, amount, chain.wallet.address);
        }
        await lib.deposit(chains, chainIndex, poolIndex, amount, true);
      }
    }
  }
  if (targets.includes("show")) {
    for (let chi=0; chi < chains.length; ++chi) {
      await lib.showChain(chains, chi);
    }
  }
  if (targets.includes("all") || targets.includes("sendCredit")) {
    await testSendCredit(chains);
  }
  if (targets.includes("all") || targets.includes("transferToken")) {
    await transferToken.testTransferToken(chains);
  }
  if (targets.includes("all") || targets.includes("transferTokenFailTokiTokenCap")) {
    await transferToken.testTransferToken_fail_tokiTokenCap(chains);
  }
  if (targets.includes("all") || targets.includes("transferPool")) {
    await testTransferPools(chains);
    await testTransferPoolForTokiETHFromBSCToETH(chains);
    await testTransferPoolForTokiETHFromETHToBSC(chains);
  }
  if (targets.includes("all") || targets.includes("withdrawInstant")) {
    await testWithdrawInstant(chains);
  }
  if (targets.includes("all") || targets.includes("withdrawRemote")) {
    await testWithdrawRemote(chains);
  }
  if (targets.includes("all") || targets.includes("withdrawLocal")) {
    await testWithdrawLocal(chains);
  }
  if (targets.includes("all") || targets.includes("outerServiceSuccess")) {
    await outerService.testOuterService_success(chains);
  }
  if (targets.includes("all") || targets.includes("outerServiceFailGas")) {
    await outerService.testOuterService_fail_outOfGas(chains);
  }
  if (targets.includes("all") || targets.includes("outerServiceFailRevert")) {
    await outerService.testOuterService_fail_revert(chains);
  }
  if (targets.includes("all") || targets.includes("outerCallSuccess")) {
    await outerCall.testOuterCall_success(chains);
  }
  if (targets.includes("all") || targets.includes("outerCallFailRevert")) {
    await outerCall.testOuterCall_fail_revert(chains);
  }
  if (targets.includes("all") || targets.includes("outerCallFailBridgeGas")) {
    await outerCall.testOuterCall_fail_bridge_gas(chains);
  }
}

const main = async (targets: string[]) => {
  const errorDecoder = lib.toki.util.newErrorDecoder();
  const chains = await setup();
  await Promise.all(chains.map(ch => lib.watchEvents(ch)));
  await run(targets, chains).catch(async(e) => {
    process.exitCode = 1;
    if (ethers.isCallException(e)) {
      const r = await errorDecoder.decode(e);
      console.log("err: ", r, e);
    } else {
      console.log(e);
    }
  }).finally(async() => {
    await Promise.all(chains.map(ch => lib.unwatchEvents(ch)));
  });
}


main(process.argv.slice(2));
