// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import * as hre from "hardhat";
import Deployer, {BUILDER_TYPE, AutomatedGasCalculator, FixedGasCalculator, GasCalculator} from "./deployer";
import DeployReport from "./deployReport";
import fs from "fs";

export type Runner = {
  target: string,
  deployer: Deployer,
  parameters: any,
}

export async function setup(): Promise<Runner> {
  // 'hardhat run' cannot take commandline arguments, so we get it by environment variables.
  [
    "BUILDER",
    "NETWORK",
    "TARGET",
    "INPUT",
    "OUTPUT_PREFIX",
    "RPC_URL",
    "FEE_PER_GAS",
    //"PRIVATE_KEY",
  ].forEach(k0 => {
    const k = "DEPLOY_" + k0;
    console.log(`${k} = ${process.env[k]}`);
  });
  checkEnvVar("DEPLOY_BUILDER", ["hardhat"]);
  checkEnvVar("DEPLOY_INPUT", null);

  const parameters = readParameterFile(process.env["DEPLOY_INPUT"]!);

  const provider = new hre.ethers.JsonRpcProvider(process.env["DEPLOY_RPC_URL"]);
  const network = (await provider._detectNetwork());
  console.log(network.toJSON());

  // get deployer account
  const deployerAccount = (await hre.ethers.getSigners())[0];

  // get parameters

  // setup deployer
  const builder: BUILDER_TYPE = (process.env["DEPLOY_BUILDER"]! == 'hardhat')? 'hardhat': 'forge';
  const config = (builder == "hardhat") ? hre.network.config : {};

  const maxPriorityFeePerGas = process.env["DEPLOY_MAX_PRIORITY_FEE_PER_GAS"] ?? "";
  const maxFeePerGas = process.env["DEPLOY_MAX_FEE_PER_GAS"] ?? "";

  const gasCalculator: GasCalculator =
    maxPriorityFeePerGas !== "" && maxFeePerGas !== ""
      ? new FixedGasCalculator(maxPriorityFeePerGas, maxFeePerGas)
      : new AutomatedGasCalculator(hre.ethers.provider);

  const deployer = new Deployer(
    builder,
    config,
    provider,
    network,
    deployerAccount,
    gasCalculator
  );

  return {
    target: process.env["DEPLOY_TARGET"]!,
    deployer,
    parameters,
  }
}

export async function report(deployer: Deployer, parameters: any): Promise<void> {
  ////////////////////////////
  // export report
  await DeployReport.report(deployer.reportData, parameters);
  if (process.env["DEPLOY_OUTPUT_PREFIX"] != undefined) {
    {
      const file = process.env["DEPLOY_OUTPUT_PREFIX"] + ".contract.json";
      DeployReport.reportContract(deployer.reportData, file);
    }
    {
      const file = process.env["DEPLOY_OUTPUT_PREFIX"] + ".reuse.json";
      DeployReport.reportReuse(deployer.reportData, file);
    }
    {
      const file = process.env["DEPLOY_OUTPUT_PREFIX"] + ".gas.json";
      DeployReport.reportGas(deployer.reportData, file);
    }
    {
      const file = process.env["DEPLOY_OUTPUT_PREFIX"] + ".gas.txt";
      DeployReport.reportGasChart(deployer.reportData, file);
    }
  }
}

export function checkEnvVar(k: string, oneof: string[] | null) {
  const v = process.env[k];
  if (v == null) {
    throw new Error(`${k} is not set`);
  }
  if (oneof != null && !oneof.includes(v)) {
    const join = oneof.join(",");
    throw new Error(`invalid ${k}. should be one of ${join} but ${v}`);
  }
}

function parseBigInt(str: string): bigint {
  // 1.23e+2 => ['1.23e+2', '1.23', '.23', '23', 'e+2', '+2']
  if (typeof(str) != 'string') {
    throw new Error(`not a bigint string: ${str}`);
  }
  const m = str.match(/^([+-]?[0-9_]+(\.([0-9_]+))?)([eE]([+-][0-9]+))?$/);
  if (m == null) {
    throw new Error(`not a bigint: ${str}`);
  }

  let exponent = 0;
  const mantissa = BigInt(m[1].replace(/[_\.]/g, ''));

  if (m[3] != null) {
    throw new Error(`decimal found in bigint: ${str}`);
  }
  if (m[5] != null) {
    const s = m[5].replace(/_/g, '');
    exponent += parseInt(s);
  }

  if (exponent == 0) {
    return mantissa;
  } else if (0 < exponent) {
    return mantissa * (10n ** BigInt(exponent));
  } else {
    throw new Error(`negative exponent found in bigint: ${str}`);
  }
}

export function readParameterFile(path: string): any {
  const json = JSON.parse(fs.readFileSync(path, "utf-8"), (k,v) => {
    if (k.endsWith("_BN")) {
      return parseBigInt(v);
    }
    if (typeof v === 'string' && v.includes("e+")) {
      return parseBigInt(v);
    }
    return v;
  });
  return json;
}
