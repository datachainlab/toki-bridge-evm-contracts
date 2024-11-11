import * as runner from './runner';
import Deployer from "./deployer";
import * as deploy from "./deploy";
import {
  DeployETHBridgeParameters,
  DeployETHVaultParameters,
  DeployMulticallParameters,
  DeployPoolResult, SetETHVaultResult
} from "./deploy";
import * as plib from "./parameters";
import {
  MainDeployTaoParameters,
  MainDeployTokiTokenParameters,
  MainDeployBridgeParameters,
  MainDeployPoolParameters,
  MainSetChannelParameters,
  MainSetETHVaultParameters
} from "./parameters";

async function main(): Promise<number> {
  const { deployer, parameters, target } = await runner.setup();

  switch (target) {
    case "oneshot":
      await deployOneshot(deployer, parameters as plib.MainDeployOneShotParameters);
      break;
    case "tao":
      await deployTao(deployer, parameters as plib.MainDeployTaoParameters);
      break;
    case "bridge":
      await deployBridge(deployer, parameters as plib.MainDeployBridgeParameters);
      break;
    case "pool":
      await deployPool(deployer, parameters as plib.MainDeployPoolParameters);
      break;
    case "channel":
      await setChannel(deployer, parameters as plib.MainSetChannelParameters);
      break;
    case "ethVault":
      await setETHVault(deployer, parameters as plib.MainSetETHVaultParameters);
      break;
    default:
      console.log(`unknown target: ${target}`);
      break;
  }

  await runner.report(deployer, parameters);
  return 0;
}

export type MainDeployTaoResult = {
  taoResult: deploy.DeployTaoResult,
};
export async function deployTao(deployer: Deployer, p0: plib.MainDeployTaoParameters): Promise<MainDeployTaoResult> {
  const taoResult = await(async () => {
    const p: deploy.DeployTaoParameters = structuredClone(p0);
    return await deploy.deployTao(deployer, p);
  })();

  return {
    taoResult,
  };
}

export type MainDeployTokiTokenResult = {
  tokiTokenResult: deploy.DeployTokiTokenResult,
};
export async function deployTokiToken(deployer: Deployer, p0: plib.MainDeployTokiTokenParameters): Promise<MainDeployTokiTokenResult> {
  const tokiTokenResult = await(async () => {
    const p: deploy.DeployTokiTokenParameters = structuredClone(p0);
    return await deploy.deployTokiToken(deployer, p);
  })();

  return {
    tokiTokenResult,
  };
}

export type MainDeployBridgeResult = {
  multicallResult: deploy.DeployMulticallResult,
  poolRepositoryResult: deploy.DeployPoolRepositoryResult,
  tokenPriceOracleResult: deploy.DeployTokenPriceOracleResult,
  bridgeResult: deploy.DeployBridgeResult,
  ethVaultResult: deploy.DeployETHVaultResult | null,
  ethBridgeResult: deploy.DeployETHBridgeResult | null,
};
export async function deployBridge(deployer: Deployer, p0: plib.MainDeployBridgeParameters): Promise<MainDeployBridgeResult> {
  const multicallResult = await(async() => {
    const p: DeployMulticallParameters = {};
    return await deploy.deployMulticall(deployer, p);
  })();

  const poolRepositoryResult = await(async () => {
    const p: deploy.DeployPoolRepositoryParameters = {
    };
    return await deploy.deployPoolRepository(deployer, p);
  })();

  const tokenPriceOracleResult = await(async () => {
    const p: deploy.DeployTokenPriceOracleParameters = Object.assign(
      structuredClone(p0.tokenPriceOracle),
      {
        useTokiToken: p0.bridge.useTokiToken,
      },
    );
    return await deploy.deployTokenPriceOracle(deployer, p);
  })();

  const bridgeResult = await(async () => {
    const p: deploy.DeployBridgeParameters = Object.assign(
      structuredClone(p0.bridge),
      {
        deployed: {
          ibcHandlerAddress: p0.bridge.deployed.ibcHandlerAddress,
          poolRepositoryAddress: await poolRepositoryResult.poolRepository.getAddress(),
          tokenPriceOracleAddress: await tokenPriceOracleResult.tokenPriceOracle.getAddress(),
          stableTokenPriceOracleAddress: await tokenPriceOracleResult.stableTokenPriceOracle.getAddress(),
          gasPriceOracleAddress: await tokenPriceOracleResult.gasPriceOracle.getAddress(),
        },
      },
    );

    return await deploy.deployBridge(deployer, p);
  })();

  let ethVaultResult = null;
  let ethBridgeResult = null;
  if (p0.ethBridge !== undefined) {
    ethVaultResult = await (async () => {
      const p: DeployETHVaultParameters = {};
      return await deploy.deployETHVault(deployer, p);
    })();

    ethBridgeResult = await (async () => {
      const p: DeployETHBridgeParameters = Object.assign(
        structuredClone(p0.ethBridge),
        {
          deployed: {
            ethVault: await ethVaultResult.ethVault.getAddress(),
            bridge: await bridgeResult.bridge.getAddress(),
          }
        }
      );
      return await deploy.deployETHBridge(deployer, p);
    })();
  }

  return {
    multicallResult,
    poolRepositoryResult,
    tokenPriceOracleResult,
    bridgeResult,
    ethVaultResult,
    ethBridgeResult,
  };
}

export type MainDeployPoolResult = {
  poolResult: DeployPoolResult,
};
export async function deployPool(deployer: Deployer, p0: plib.MainDeployPoolParameters): Promise<MainDeployPoolResult> {
  const poolResult = await(async () => {
    const p: deploy.DeployPoolParameters = structuredClone(p0);
    return await deploy.deployPool(deployer, p);
  })();

  return {
    poolResult,
  }
}

export type MainSetChannelResult = {
  channelResult: deploy.SetChannelResult,
};
export async function setChannel(deployer: Deployer, p0: plib.MainSetChannelParameters): Promise<MainSetChannelResult> {
  const channelResult = await(async () => {
    const p: deploy.SetChannelParameters = structuredClone(p0);
    return await deploy.setChannel(deployer, p);
  })();

  return {
    channelResult,
  }
}

export type MainSetETHVaultResult = {
  ethVaultResult: SetETHVaultResult,
};

export async function setETHVault(deployer: Deployer, p0: plib.MainSetETHVaultParameters): Promise<MainSetETHVaultResult> {
  const ethVaultResult = await(async () => {
    const p: deploy.SetETHVaultParameters = structuredClone(p0);
    return await deploy.setETHVault(deployer, p);
  })();

  return {
    ethVaultResult,
  }
}

export type MainDeployOneshot = {
  taoResult: MainDeployTaoResult,
  bridgeResult: MainDeployBridgeResult,
  poolResult: MainDeployPoolResult[],
  channelResult: MainSetChannelResult,
  ethVaultResult: MainSetETHVaultResult | null,
  tokiTokenResult: MainDeployTokiTokenResult | null,
};

export async function deployOneshot(deployer: Deployer, p0: plib.MainDeployOneShotParameters): Promise<MainDeployOneshot> {
  const taoResult = await(async () => {
    const p: MainDeployTaoParameters = structuredClone(p0.tao);
    return await deployTao(deployer, p);
  })();

  const bridgeResult = await(async () => {
    const p: MainDeployBridgeParameters = {
      tokenPriceOracle: structuredClone(p0.tokenPriceOracle),
      bridge: Object.assign(
        structuredClone(p0.bridge),
        {
          deployed: {
            ibcHandlerAddress: await taoResult.taoResult.ownableIbcHandler.getAddress() as string,
            poolRepositoryAddress: "",
            tokiEscrowAddress: "",
            tokiTokenAddress: "",
            tokenPriceOracleAddress: "",
            gasPriceOracleAddress: "",
          },
          useTokiToken: p0.tokiToken != null,
        },
      ),
      ethBridge: structuredClone(p0.ethBridge),
    };
    return await deployBridge(deployer, p);
  })();

  const tokiTokenResult = await(async () => {
    if (p0.tokiToken == null) {
      return null;
    }
    const p: MainDeployTokiTokenParameters = Object.assign(
      structuredClone(p0.tokiToken),
      {
        deployed: {
          bridgeAddress: await bridgeResult.bridgeResult.bridge.getAddress(),
        }
      }
    );
    return await deployTokiToken(deployer, p);
  })();

  const transferPoolFeeCalculatorResult = await(async () => {
    const p: deploy.DeployTransferPoolFeeCalculatorParameters =
      {
        deployed: {
          stableTokenPriceOracleAddress: await bridgeResult.tokenPriceOracleResult.stableTokenPriceOracle.getAddress(),
          tokenPriceOracleAddress: await bridgeResult.tokenPriceOracleResult.tokenPriceOracle.getAddress(),
        }
      };
    return await deploy.deployTransferPoolFeeCalculator(deployer, p);
  })();

  // for EthVault
  let ethVaultPoolId = -1;
  // run serially to avoid from duplicated transaction error
  const poolResult: MainDeployPoolResult[] = [];
  for (let poolIdx=0; poolIdx<p0.pools.length; ++poolIdx) {
    poolResult.push(await (async() => {
      const d = deployer.newReportPrefix(`Pool${p0.pools[poolIdx].poolId}.`);
      const p: MainDeployPoolParameters = Object.assign(
        structuredClone(p0.pools[poolIdx]),
        {
          deployed: {
            bridgeAddress: await bridgeResult.bridgeResult.bridge.getAddress(),
            rewardTokenAddress: (tokiTokenResult==null)? null: await tokiTokenResult.tokiTokenResult.tokiToken.getAddress(),
            poolRepositoryAddress: await bridgeResult.poolRepositoryResult.poolRepository.getAddress(),
            ethVaultAddress: await bridgeResult.ethVaultResult?.ethVault.getAddress(),
            tokenPriceOracleAddress: await bridgeResult.tokenPriceOracleResult.tokenPriceOracle.getAddress(),
            stableTokenPriceOracleAddress: await bridgeResult.tokenPriceOracleResult.stableTokenPriceOracle.getAddress(),
            transferPoolFeeCalculatorAddress: await transferPoolFeeCalculatorResult.transferPoolFeeCalculator.getAddress(),
          },
        },
      );
      if (p0.pools[poolIdx].pooledToken.contractName == "ETHVault") {
        ethVaultPoolId = p0.pools[poolIdx].poolId;
      }
      const pool = await deployPool(d, p);
      await deploy.setPoolPeers(d, pool.poolResult.pool, p);
      return pool;
    })());
  }

  const channelResult = await(async () => {
    const p: MainSetChannelParameters = Object.assign(
      structuredClone(p0.channel),
      {
        deployed: {
          bridgeAddress: await bridgeResult.bridgeResult.bridge.getAddress(),
          tokenPriceOracleAddress: await bridgeResult.tokenPriceOracleResult.tokenPriceOracle.getAddress(),
          gasPriceOracleAddress: await bridgeResult.tokenPriceOracleResult.gasPriceOracle.getAddress(),
        },
        useTokiToken: (tokiTokenResult != null),
      },
    );
    return await setChannel(deployer, p);
  })();

  let ethVaultResult = null;
  if (bridgeResult.ethVaultResult != null) {
    ethVaultResult = await (async () => {
      const p: MainSetETHVaultParameters = Object.assign(
        {
          poolId: ethVaultPoolId,
          deployed: {
            bridgeAddress: await bridgeResult.bridgeResult.bridge.getAddress(),
            ethVaultAddress: await bridgeResult.ethVaultResult!.ethVault.getAddress(),
          },
        },
      );
      return await setETHVault(deployer, p);
    })();
  }

  {
    const p: deploy.DeployTestParameters = {
      port: p0.bridge.portId,
    };
    await deploy.deployTest(deployer, p);
  }

  return {
    taoResult,
    bridgeResult,
    poolResult,
    channelResult,
    ethVaultResult,
    tokiTokenResult,
  };
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().then((r) => {
  process.exitCode = r;
}).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
