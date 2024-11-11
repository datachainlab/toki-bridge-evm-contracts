import {ethers, BigNumberish, AddressLike, TransactionResponse, BytesLike} from 'ethers';
import * as tt from '../typechain-types';
import * as tt_bridge from '../typechain-types/artifacts/src/Bridge';

// copy from IBCUtils.sol
const _TYPE_RETRY_RECEIVE_POOL = 1;
const _TYPE_RETRY_WITHDRAW_CONFIRM = 2;
const _TYPE_RETRY_RECEIVE_TOKEN = 5;
const _TYPE_RETRY_EXTERNAL_CALL = 10;
const _TYPE_RETRY_REFUEL_CALL = 11;
const _TYPE_RETRY_REFUEL_AND_EXTERNAL_CALL = 12;

const make_fee_info = (a: any[]): tt.ITransferPoolFeeCalculator.FeeInfoStruct => {
    return {
        'amountGD': BigInt(a[0]),
        'protocolFee': BigInt(a[1]),
        'lpFee': BigInt(a[2]),
        'eqFee': BigInt(a[3]),
        'eqReward': BigInt(a[4]),
        'lastKnownBalance': BigInt(a[5]),
    };
}

const make_external_info = (a: any[]): tt_bridge.IBCUtils.ExternalInfoStruct => {
    return {
        'payload': a[0] as string,
        'dstOuterGas': BigInt(a[1]),
    };
}

export const RETRY_RECEIVE_POOL = 'RECEIVE_POOL';
export type RetryReceivePool = {
    typename: string,
    appVersion: bigint,
    lastValidHeight: bigint,
    srcPoolId: bigint,
    dstPoolId: bigint,
    to: string,
    feeInfo: tt.ITransferPoolFeeCalculator.FeeInfoStruct,
    refuelAmount: bigint,
    externalInfo: tt_bridge.IBCUtils.ExternalInfoStruct,
}

export const RETRY_RECEIVE_TOKEN = 'RECEIVE_TOKEN';
export type RetryReceiveToken = {
    typename: string,
    appVersion: bigint,
    lastValidHeight: bigint,
    denom: string,
    amount: bigint,
    to: string,
    refuelAmount: bigint,
    externalInfo: tt_bridge.IBCUtils.ExternalInfoStruct,
}

export const RETRY_WITHDRAW_CONFIRM = 'WITHDRAW_CONFIRM';
export type RetryWithdrawConfirm = {
    typename: string,
    appVersion: bigint,
    lastValidHeight: bigint,
    srcPoolId: bigint,
    dstPoolId: bigint,
    to: string,
    transferAmount: bigint,
    mintAmount: bigint,
}

export const RETRY_EXTERNAL_CALL= 'EXTERNAL_CALL';
export type RetryExternalCall = {
    typename: string,
    appVersion: bigint,
    lastValidHeight: bigint,
    token: string,
    amount: bigint,
    to: string,
    externalInfo: tt_bridge.IBCUtils.ExternalInfoStruct,
}

export const RETRY_REFUEL_CALL = 'REFUEL_CALL';
export type RetryRefuelCall = {
    typename: string,
    appVersion: bigint,
    lastValidHeight: bigint,
    to: string,
    refuelAmount: bigint,
}

export const RETRY_REFUEL_AND_EXTERNAL_CALL = 'REFUEL_AND_EXTERNAL_CALL';
export type RetryRefuelAndExternalCall = {
    typename: string,
    appVersion: bigint,
    lastValidHeight: bigint,
    token: string,
    amount: bigint,
    to: string,
    refuelAmount: bigint,
    externalInfo: tt_bridge.IBCUtils.ExternalInfoStruct,
}

export type Retry = RetryReceivePool | RetryReceiveToken | RetryWithdrawConfirm | RetryExternalCall | RetryRefuelCall | RetryRefuelAndExternalCall;

export const isRetryReceivePool = (r: Retry): r is RetryReceivePool => {
    return r.typename == RETRY_RECEIVE_POOL;
}
export const isRetryReceiveToken = (r: Retry): r is RetryReceiveToken => {
    return r.typename == RETRY_RECEIVE_TOKEN;
}
export const isRetryWithdrawConfirm = (r: Retry): r is RetryWithdrawConfirm => {
    return r.typename == RETRY_WITHDRAW_CONFIRM;
}
export const isRetryExternalCall = (r: Retry): r is RetryExternalCall => {
    return r.typename == RETRY_EXTERNAL_CALL;
}
export const isRetryRefuelCall = (r: Retry): r is RetryRefuelCall => {
    return r.typename == RETRY_REFUEL_CALL;
}
export const isRetryRefuelAndExternalCall = (r: Retry): r is RetryRefuelAndExternalCall => {
    return r.typename == RETRY_REFUEL_AND_EXTERNAL_CALL;
}

export const decodeRetry = (payload: string): Retry => {
  const FEE_INFO = 'tuple(uint256, uint256, uin256, uint256, uint256, uint256)';
  const EXTERNAL_INFO = 'tuple(bytes, uint256)';

  const typ = ethers.AbiCoder.defaultAbiCoder().decode([
    ethers.ParamType.from({ name: 'type', type: 'uint8' }),
  ], payload)[0];

  if (typ == _TYPE_RETRY_RECEIVE_POOL) {
    const d = ethers.AbiCoder.defaultAbiCoder().decode([
      'uint8', 'uint256', 'uint256', 'uint256', 'uint256', 'address', FEE_INFO, 'uint256', EXTERNAL_INFO,
    ], payload);
    return {
        typename: RETRY_RECEIVE_POOL,
        appVersion: BigInt(d[1]),
        lastValidHeight: BigInt(d[2]),
        srcPoolId: BigInt(d[3]),
        dstPoolId: BigInt(d[4]),
        to: d[5] as string,
        feeInfo: make_fee_info(d[6]),
        refuelAmount: BigInt(d[7]),
        externalInfo: make_external_info(d[8]),
    } as RetryReceivePool;

  } else if (typ == _TYPE_RETRY_WITHDRAW_CONFIRM) {
    const d = ethers.AbiCoder.defaultAbiCoder().decode([
      'uint8', 'uint256', 'uint256', 'uint256', 'uint256', 'address', 'uint256', 'uint256',
    ], payload);
    return {
        typename: RETRY_WITHDRAW_CONFIRM,
        appVersion: BigInt(d[1]),
        lastValidHeight: BigInt(d[2]),
        srcPoolId: BigInt(d[3]),
        dstPoolId: BigInt(d[4]),
        to: d[5] as string,
        transferAmount: BigInt(d[6]),
        mintAmount: BigInt(d[7]),
    } as RetryWithdrawConfirm;

  } else if (typ == _TYPE_RETRY_RECEIVE_TOKEN) {
    const d = ethers.AbiCoder.defaultAbiCoder().decode([
      'uint8', 'uint256', 'uint256', 'string', 'uint256', 'address', 'uint256', EXTERNAL_INFO,
    ], payload);
    return {
        typename: RETRY_RECEIVE_TOKEN,
        appVersion: BigInt(d[1]),
        lastValidHeight: BigInt(d[2]),
        denom: d[3] as string,
        amount: BigInt(d[4]),
        to: d[5] as string,
        refuelAmount: BigInt(d[6]),
        externalInfo: make_external_info(d[7]),
    } as RetryReceiveToken;

  } else if (typ == _TYPE_RETRY_EXTERNAL_CALL) {
    const d = ethers.AbiCoder.defaultAbiCoder().decode([
      'uint8', 'uint256', 'uint256', 'address', 'uint256', 'address', EXTERNAL_INFO,
    ], payload);
    return {
        typename: RETRY_EXTERNAL_CALL,
        appVersion: BigInt(d[1]),
        lastValidHeight: BigInt(d[2]),
        token: d[3] as string,
        amount: BigInt(d[4]),
        to: d[5] as string,
        externalInfo: make_external_info(d[6]),
    } as RetryExternalCall;

  } else if (typ == _TYPE_RETRY_REFUEL_CALL) {
    const d = ethers.AbiCoder.defaultAbiCoder().decode([
      'uint8', 'uint256', 'uint256', 'address', 'uint256',
    ], payload);
    return {
      'typename': RETRY_REFUEL_CALL,
      'appVersion': BigInt(d[1]),
      'lastValidHeight': BigInt(d[2]),
      'to': d[3] as string,
      'refuelAmount': BigInt(d[4]),
    } as RetryRefuelCall;

  } else if (typ == _TYPE_RETRY_REFUEL_AND_EXTERNAL_CALL) {
    const d = ethers.AbiCoder.defaultAbiCoder().decode([
      'uint8', 'uint256', 'uint256', 'address', 'uint256', 'address', 'uint256', EXTERNAL_INFO,
    ], payload);
    return {
      'typename': RETRY_REFUEL_AND_EXTERNAL_CALL,
      'appVersion': BigInt(d[1]),
      'lastValidHeight': BigInt(d[2]),
      'token': d[3] as string,
      'amount': BigInt(d[4]),
      'to': d[5] as string,
      'refuelAmount': BigInt(d[6]),
      'externalInfo': make_external_info(d[7]),
    } as RetryRefuelAndExternalCall;

  } else {
    throw new Error(`unknown retry type: ${typ}`);
  }
}
