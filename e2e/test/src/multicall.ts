import { ethers, getChains, Chain, receipt } from "./lib";
import * as lib from './lib';

type Token = lib.PooledToken | lib.toki.tt.Pool | lib.toki.tt.TokiToken;

export const testMulticall3 = async (chains: Chain[]) => {
  console.log("-- testMulticall -----------");
  for (let ch of chains) {
    console.log("networkId=", ch.network.chainId, ", chainId=", ch.chainId);
    const accAddr = ch.wallet.address;
    console.log("account", accAddr);

    const erc20s: Token[] = [ ch.pooldata[0].pooledToken, ch.pooldata[0].pool ];
    if (ch.tokiToken != null) {
      erc20s.push(ch.tokiToken);
    }
    console.log("  direct call:");
    for (const erc20 of erc20s) {
      const a = await erc20.getAddress();
      const balance = await erc20.balanceOf(accAddr);
      console.log(`    ${a}: ${balance}`);
    }

    const calls = await Promise.all(erc20s.map(async(erc20) => {
      return {
        target: await erc20.getAddress(),
        allowFailure: false,
        callData: erc20.interface.encodeFunctionData("balanceOf", [accAddr]),
      };
    }));
    const callResults = await ch.multicall3.aggregate3.staticCallResult(calls);
    console.log("  aggregate3:");
    for (let i=0; i<callResults[0].length; ++i) {
      const aggResult = callResults[0][i];
      const funcResults = erc20s[i].interface.decodeFunctionResult("balanceOf", aggResult.returnData);
      const a = await erc20s[i].getAddress();
      console.log(`    ${a}: ${funcResults[0]}`);
    }
  }
}

const main = async () => {
  const chains = await getChains();
  await testMulticall3(chains);
}
main();
