import { spawn } from 'child_process';
import {setTimeout} from "timers/promises";
import * as fs from 'fs';
import * as lib from './lib';
import { TestUpgradePoolParameters } from '../../../script/hardhat/run-testUpgradePool';

const get_deploy_name = (mode: string, chain: lib.Chain): string => {
  return `testUpgradePool-${chain.name}-${mode}`;
}
const get_upgrade_name = (mode: string, poolId: number): string => {
  return `Pool${poolId} by ${mode}`;
}

const create_parameter_file = async(mode: string, chain: lib.Chain): Promise<string> => {
  const params: TestUpgradePoolParameters = { pools: [] };

  if (mode == 'v1' || mode == 'v1_to_v2') {
    for (let i=0; i<chain.deploy_input.pools.length; ++i) {
      const name = chain.deploy_input.pools[i].pooledToken.name;
      const poolId = chain.deploy_input.pools[i].poolId;
      const oldImplAddress = chain.deploy_output[`Pool${poolId}.Pool(impl)`];
      const proxyAddress = chain.deploy_output[`Pool${poolId}.Pool`];
      let oldImplName: string = '';
      let oldConstructorArgs: any[] = [];
      let newImplName: string = '';
      let constructorArgs: any[] = [];
      let upgradeFunc: string = '';
      let upgradeFuncArgs: any[] = [];
      if (mode == 'v1') {
        oldImplName = 'Pool';
        oldConstructorArgs = [
          chain.deploy_input.pools[i].pooledToken.flowRateLimiter.period,
          chain.deploy_input.pools[i].pooledToken.flowRateLimiter.lockPeriod,
          chain.deploy_input.pools[i].pooledToken.flowRateLimiter.limitLD_BN,
          chain.deploy_input.pools[i].pooledToken.flowRateLimiter.thresholdLD_BN,
        ];
        newImplName = 'MockUpgradePoolV1';
        constructorArgs = [
          13,
          chain.deploy_input.pools[i].pooledToken.flowRateLimiter.period,
          chain.deploy_input.pools[i].pooledToken.flowRateLimiter.lockPeriod,
          chain.deploy_input.pools[i].pooledToken.flowRateLimiter.limitLD_BN,
          chain.deploy_input.pools[i].pooledToken.flowRateLimiter.thresholdLD_BN,
        ];
        upgradeFunc = 'upgradeToV1';
        upgradeFuncArgs = [ get_upgrade_name(mode, poolId), 27 ];
      } else if (mode == 'v1_to_v2') {
        oldImplName = 'MockUpgradePoolV1';
        oldConstructorArgs = [
          13,
          chain.deploy_input.pools[i].pooledToken.flowRateLimiter.period,
          chain.deploy_input.pools[i].pooledToken.flowRateLimiter.lockPeriod,
          chain.deploy_input.pools[i].pooledToken.flowRateLimiter.limitLD_BN,
          chain.deploy_input.pools[i].pooledToken.flowRateLimiter.thresholdLD_BN,
        ]; // in production, these values are gotten from depooyed contract or deploy log
        newImplName = 'MockUpgradePoolV2';
        constructorArgs = [
          chain.deploy_input.pools[i].pooledToken.flowRateLimiter.period,
          chain.deploy_input.pools[i].pooledToken.flowRateLimiter.lockPeriod,
          chain.deploy_input.pools[i].pooledToken.flowRateLimiter.limitLD_BN,
          chain.deploy_input.pools[i].pooledToken.flowRateLimiter.thresholdLD_BN,
        ];
        upgradeFunc = 'upgradeToV2';
        upgradeFuncArgs = [ get_upgrade_name(mode, poolId), 0 ];
      }

      params.pools.push({
        poolId,
        name,
        proxyAddress,
        oldImplName,
        newImplName,
        constructorArgs,
        oldImplAddress,
        oldConstructorArgs,
        upgradeFunc, upgradeFuncArgs
      });
    }
  } else {
    throw new Error(`unknown mode: ${mode}`);
  }
  const deploy_name = get_deploy_name(mode, chain);
  const paramfile = `../contract-deploy/${deploy_name}.parameter.json`;
  fs.writeFileSync(paramfile, JSON.stringify(params, null, 2));
  console.log(JSON.stringify(params, null, 2));

  return paramfile;
}

const hardhat_run = async (paramfile: string) => {
  let output = '';
  console.log(`../hardhat-run.sh ${paramfile}...`);

  const child = spawn(
    `../hardhat-run.sh`,
    [paramfile],
    { shell: true, stdio: 'pipe' }
  );
  child.stdout.on('data', data => {
    const s = data.toString();
    output += s;
    console.log(s);
  });
  child.stderr.on('data', data => {
    const s = data.toString();
    output += s;
    console.log(s);
  });

  return new Promise((resolve, reject) => {
    child.on('exit', (code, signal) => {
      if (code === 0) {
        resolve({output, code});
      } else if (code != null) {
        reject({output, error: new Error(`exit with ${code}`), code});
      } else {
        reject({output, error: new Error(`killed by ${signal}`), signal});
      }
    });
  });
}

const testV1 = async(mode: string, chain: lib.Chain) => {
  for (let i=0; i<chain.deploy_input.pools.length; ++i) {
    const poolId = chain.deploy_input.pools[i].poolId;
    const proxyAddress = chain.deploy_output[`Pool${poolId}.Pool`];
    const proxy = lib.toki.tt.MockUpgradePoolV1__factory.connect(proxyAddress, chain.wallet);

    const actual = await proxy.upgradeName();
    const expect = get_upgrade_name(mode, poolId);
    if (actual !== expect) {
      throw new Error(`[${chain.chainId}/${i}] upgradeName mismatch: expect "${expect}" but "${actual}"`);
    }

    const impl = await proxy.getImplementation();
  }
}

const run = async (targets: string[], chains: lib.Chain[]) => {
  const mode = targets[0];

  if (['v1'].includes(mode)) {
    for (const c of chains) {
      const file = await create_parameter_file(mode, c);
      const output = '';
      await hardhat_run(file);
      await lib.setTimeout(3000);
      await testV1(mode, c);
    }
  }
  if (['v1_to_v2'].includes(mode)) {
    for (const c of chains) {
      const file = await create_parameter_file(mode, c);
      let err = null
      try {
        await hardhat_run(file);
        err = new Error("failed to detect incompatible storage layout");
      } catch (e: any) {
        if (e.code === 1 && e.output.includes("\nError: New storage layout is incompatible\n")) {
          console.log("succeeded in detecting incompatible storage layout");
          ; // pass
        } else {
          err = e.error;
        }
      }
      if (err != null) {
        throw err;
      }
    }
  }
}

const main = async (targets: string[]) => {
  const errorDecoder = lib.toki.util.newErrorDecoder();
  const chains = await lib.getChains();
  await Promise.all(chains.map(ch => lib.watchEvents(ch)));
  await run(targets, chains).catch(async(e) => {
    if (lib.ethers.isCallException(e)) {
      const r = await errorDecoder.decode(e);
      console.log("err: ", r, e);
      process.exitCode = 1;
    } else {
      console.log(e);
      process.exitCode = 1;
    }
  }).finally(async() => {
    await Promise.all(chains.map(ch => lib.unwatchEvents(ch)));
  });
}

main(process.argv.slice(2));
