import {ethers, receipt, getChains, Chain} from './lib';
import * as lib from './lib';
import * as fs from 'fs';

// deposit to Pool and distribute PeerPool info
const fillLiquidity = async (chains: Chain[], chIndex: number, poolIndex: number, amountGD: bigint, doDump: boolean = false) => {
  const pool = chains[chIndex].pooldata[poolIndex].pool;
  const curr = await pool.totalLiquidity();
  if (curr < amountGD) {
    const deltaGD = amountGD - curr;
    const deltaLD = await lib.toki.util.GDToLD(pool, deltaGD);
    await lib.deposit(chains, chIndex, poolIndex, deltaLD, doDump);
  }
}

const fillNativeToken = async (ch: Chain, addr: string, amountEth: bigint) => {
  const curr = await ch.provider.getBalance(addr);
  if (curr < amountEth) {
    const delta = amountEth - curr;
    const tx = {
      to: addr,
      value: ethers.parseUnits(`${delta}`, "ether"),
    };
    await receipt(ch.wallet.sendTransaction(tx));
  }
}

const fillTokiToken = async (ch: Chain, addr: string, amountLD: bigint) => {
  const curr = await ch.tokiToken.balanceOf(addr);
  if (curr < amountLD) {
    const delta = amountLD - curr;
    await receipt(ch.tokiToken.grantRole(await ch.tokiToken.MINTER_ROLE(), ch.wallet.address));
    await receipt(ch.tokiToken.mint(addr, delta));
  }
}

const fillPooledToken = async (ch: Chain, poolIndex: number, addr: string, amountLD: bigint) => {
  const curr = await ch.pooldata[poolIndex].pooledToken.balanceOf(addr);
  if (curr < amountLD) {
    const delta = amountLD - curr;
    await receipt(ch.pooldata[poolIndex].pooledToken.mint(addr, delta));
  }
}

export type Parameter = {
  chains: {
    pools: { liquidity: string }[],
  }[],
  accounts: {
    name: string,
    address: string,
    chains: {
      native_token: string,
      pooled_token: string[],
    }[],
  }[],
};

const dump = async (chains: Chain[], param: Parameter) => {
  const now = new Date();
  console.log(now.toISOString());

  for (let i=0; i<chains.length; ++i) {
    const ch = chains[i];
    console.log("networkId=", ch.network.chainId, ", chainId=", ch.chainId);

    for (let j=0; j<ch.pooldata.length; ++j) {
      const pool = ch.pooldata[j].pool;
      console.log("  poolId=", ch.pooldata[j].poolId);
      console.log("    totalLiquidity=", await pool.totalLiquidity());
    }
  }

  const dumpAccount = async(indent: string, name: string, ch: Chain, addr: string) => {
    console.log(`${indent}${name}: `);
    console.log(`${indent}  nativeToken=`, await ch.provider.getBalance(addr));
    for (let pd of ch.pooldata) {
      console.log(`${indent}  poolId=`, pd.poolId);
      console.log(`${indent}    pooledToken=`, await pd.pooledToken.balanceOf(addr));
      console.log(`${indent}    liquidityToken=`, await pd.pool.balanceOf(addr));
    }
  };
  for (let i=0; i<param.accounts.length; ++i) {
    const pa = param.accounts[i];
    console.log(`account[${i}]: name=${pa['name']}, addr=${pa['address']}:`);
    for (let ch of chains) {
      await dumpAccount('  ', `chainId=${ch.chainId}`, ch, pa.address);
    }
    console.log("\n");
  }
}

export const setup = async (chains: Chain[], param: Parameter) => {
  for (let i=0; i<param.chains.length; ++i) {
    const param_ch = param.chains[i];
    const ch = chains[i];
    console.log("networkId=", ch.network.chainId, ", chainId=", ch.chainId);
    for (let j=0; j<param_ch.pools.length; ++j) {
      const param_pool = param_ch.pools[j];
      const liq_amount = BigInt(param_pool.liquidity);
      console.log(`  fill liquidity chain[${ch.chainId}] ${liq_amount}...`);
      await fillLiquidity(chains, i, j, liq_amount, true);
    }
  }

  for (let i=0; i<param.accounts.length; ++i) {
    const param_account = param.accounts[i];
    console.log(`account[${i}]: name=${param_account['name']}, addr=${param_account['address']}:`);
    for (let j=0; j<param_account.chains.length; ++j) {
      const ch = chains[j];
      const param_ch = param_account.chains[j];
      console.log(`  fill native token ${param_ch.native_token}...`);
      await fillNativeToken(ch, param_account.address, BigInt(param_ch.native_token));

      for (let k=0; k<param_ch.pooled_token.length; ++k) {
        const param_pooled_token_amount = param_ch.pooled_token[k];
        const poolId = ch.pooldata[k].poolId;
        console.log(`    fill pool[${poolId}].token ${param_pooled_token_amount}...`);
        await fillPooledToken(ch, k, param_account.address, BigInt(param_pooled_token_amount));
      }
    }
  }
}

const main = async (filepath: string, dumponly: boolean) => {
  const param = JSON.parse(fs.readFileSync(filepath, 'utf-8')) as Parameter;
  const chains = await lib.getChains();
  if (! dumponly) {
    await setup(chains, param);
  }
  await dump(chains, param);
}

let dumponly = false;
let filepath = process.argv[2];
if (process.argv[2] == '-d') {
  dumponly = true;
  filepath = process.argv[3];
}

if (filepath == null) {
  console.log(`setup.ts [-d] <parameter file>`);
  process.exit(1);
}
main(filepath, dumponly);
