import { ethers, getChains, Chain, receipt } from "./lib";
import * as lib from './lib';

export const testErrorGetPool  = async (chain: Chain) => {
  console.log("-- testErrorGetPool -----------");

  const errorDecoder = lib.toki.util.newErrorDecoder();

  await chain.poolRepository.getPool(0xdead)
  .then(_ => {
    throw new Error('no revert');
  }).catch(async(e) => {
    if (ethers.isCallException(e)) {
      const r = await errorDecoder.decode(e);
      if (r.type === 'CustomError' && r.name === 'TokiNoPool' && r.args.length == 1 && r.args[0] == 0xdead) {
        console.log(`expected revert: TokiNoPool(${r.args[0]})`);
      } else {
        throw new Error(`unexpected revert: ${r}`);
      }
    } else {
      throw new Error(`unexpected revert: !isCallException: ${e}`);
    }
  });
}

const main = async () => {
  const chains = await getChains();
  await testErrorGetPool(chains[0]);
}
main();
