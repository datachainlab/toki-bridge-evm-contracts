import { HardhatUserConfig } from "hardhat/config";
import "hardhat-contract-sizer";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";

const DEFAULT_COMPILER_SETTINGS = {
  version: "0.8.24",
  settings: {
    evmVersion: "cancun",
    viaIR: true,
    optimizer: {
      enabled: true,
      runs: 1_000_000,
    },
  },
}

const changeRuns = (runs: number): object => {
  const ret = structuredClone(DEFAULT_COMPILER_SETTINGS);
  ret.settings.optimizer.runs = runs;
  return ret;
}

const config: HardhatUserConfig = {
  solidity: {
    compilers: [ DEFAULT_COMPILER_SETTINGS ],
    overrides: {
      // set large number as possible for bytecode not to exceed 24576 bytes bytecode
      "src/Pool.sol": changeRuns(400),
      "src/mocks/MockUpgradePool.sol": changeRuns(100),
      "src/Bridge.sol": changeRuns(1000),
      "src/mocks/MockUpgradeBridge.sol": changeRuns(100),
      "src/clients/RecoveredLCPClientUpgradeable.sol": changeRuns(3200),
    },
  },
  typechain: {
    target: "ethers-v6",
    outDir: "script/tslib/typechain-types",
    externalArtifacts: ['abi/*.json']
  },
  networks: {
    hardhat: {
      // Set the timestamp of the localnet for time-based testing.
      initialDate: "2020-01-01T00:00:00Z",
    },
  },
  paths: {
    sources: "./src",
    cache: "./cache_hardhat",
  },
};

if (process.env.DEPLOY_RPC_URL != null) {
  if (process.env.DEPLOY_PRIVATE_KEY == null) {
    throw new Error("should set DEPLOY_PRIVATE_KEY");
  }
  const cfg = {
    url: process.env.DEPLOY_RPC_URL,
    accounts: [process.env.DEPLOY_PRIVATE_KEY],
  };
  config.networks!["envvar"] = cfg;
}

export default config;
