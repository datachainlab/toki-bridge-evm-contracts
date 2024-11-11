import * as runner from './runner';
import Deployer from "./deployer";
import DeployReport from "./deployReport";
import * as deploy from "./deploy";
import { upgrades } from "hardhat";
import { ethers } from 'ethers';
import { ForceImportOptions, UpgradeOptions } from "@openzeppelin/hardhat-upgrades/src/utils";

export type TestUpgradePoolParameters = {
  pools: {
    poolId: number,
    name: string,
    proxyAddress: string,
    oldImplName: string,
    newImplName: string,
    constructorArgs: any[],
    oldImplAddress: string,
    oldConstructorArgs: any[],
    upgradeFunc: string,
    upgradeFuncArgs: any[],
  }[],
};

const testUpgradePool = async <T extends ethers.BaseContract>(deployer: Deployer, p: TestUpgradePoolParameters): Promise<void> => {
  for (let i=0; i<p.pools.length; ++i) {
    const oldImplContractFactory = await deployer.getContractFactory(p.pools[i].oldImplName);

    // forceImport() accept only ForceImportOptions but implicitly convert to UpgradeOptions and uses constructorArgs property.
    const opts: ForceImportOptions & UpgradeOptions = { kind: 'uups', constructorArgs: p.pools[i].oldConstructorArgs };
    await upgrades.forceImport(p.pools[i].proxyAddress, oldImplContractFactory, opts);

    const upgraded = await deployer.upgrade<T>(
      p.pools[i].newImplName,
      (i==0)? 'always' : 'onchange',
      p.pools[i].proxyAddress,
      p.pools[i].constructorArgs,
      { fn: p.pools[i].upgradeFunc, args: p.pools[i].upgradeFuncArgs },
      `Pool${p.pools[i].poolId}.${p.pools[i].newImplName}`
    );
  }
}

async function main(): Promise<number> {
  const { deployer, parameters, target } = await runner.setup();

  await testUpgradePool<ethers.BaseContract>(deployer, parameters as TestUpgradePoolParameters);
  await runner.report(deployer, parameters);
  return 0;
}

main().then((r) => {
  process.exitCode = r;
}).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
