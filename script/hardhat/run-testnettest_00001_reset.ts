import * as runner from './runner';
import Deployer from "./deployer";
import DeployReport from "./deployReport";
import * as deploy from "./deploy";
import * as rundeploy from "./run-deploy";
import * as plib from "./parameters";

async function main(): Promise<number> {
  const { deployer, parameters, target } = await runner.setup();

  await deployReset(deployer, parameters as ResetParameters);

  await runner.report(deployer, parameters);
  return 0;
}

type ResetParameters = plib.MainDeployOneShotParameters & {
  reuse: [{
    name: string,
    address: string,
  }],
}

async function deployReset(deployer: Deployer, p0: ResetParameters): Promise<rundeploy.MainDeployOneshot> {
  console.log("deployReset");
  const reuses = [
    'Multicall3',
  ];
  p0.pools.forEach(p => {
    if (p.pooledToken.contractName == 'PseudoToken') {
      reuses.push(`Pool${p.poolId}.${p.pooledToken.name}`);
      reuses.push(`Pool${p.poolId}.${p.pooledToken.name}(impl)`);
    } else if (p.pooledToken.contractName == 'ETHVault') {
      reuses.push('ETHVault');
    }
  });
  for (const reuse of reuses) {
    const r = p0.reuse.find(r => r.name == reuse)
    if (r == null || r.address == null) {
      throw new Error(`reuse address of ${reuse} is not set`);
    }
    deployer.reuse.set(reuse, r.address);
  }
  const r = rundeploy.deployOneshot(deployer, p0);

  return r;
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().then((r) => {
  process.exitCode = r;
}).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
