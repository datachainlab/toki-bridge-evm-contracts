import * as dlib from "./deploy";

export type FlowRateLimiter = {
  period: number,
  lockPeriod: number,
  limitLD_BN: BigInt,
  thresholdLD_BN: BigInt,
}

export type MainDeployTaoParameters = dlib.DeployTaoParameters;

export type MainDeployTokiTokenParameters = dlib.DeployTokiTokenParameters;

export type MainDeployBridgeParameters = {
  tokenPriceOracle: dlib.DeployTokenPriceOracleParameters,
  bridge: dlib.DeployBridgeParameters,
  ethBridge: dlib.DeployETHBridgeParameters,
};

export type MainDeployPoolParameters = dlib.DeployPoolParameters;

export type MainSetChannelParameters = dlib.SetChannelParameters;

export type MainSetETHVaultParameters = dlib.SetETHVaultParameters;


export interface MainDeployOneShotParameters {
  tao: dlib.DeployTaoParameters,
  tokiToken: dlib.DeployTokiTokenParameters | null,
  tokenPriceOracle: dlib.DeployTokenPriceOracleParameters,
  bridge: dlib.DeployBridgeParametersBase,
  ethBridge: dlib.DeployETHBridgeParameters,
  pools: dlib.DeployPoolParametersBase[],
  channel: dlib.SetChannelParametersBase,
}
