import {ethers, BigNumberish, AddressLike, TransactionResponse, BytesLike} from 'ethers';
import * as tt from './typechain-types';

export * from './util/retry';
export * from './util/error';

export const LDToGD = async (pool: tt.Pool, amountLD: bigint): Promise<bigint> => {
  return amountLD / (await pool.convertRate());
}

export const GDToLD = async (pool: tt.Pool, amountGD: bigint): Promise<bigint> => {
  return amountGD * (await pool.convertRate());
}

export const receipt = async (ptxr: Promise<ethers.TransactionResponse>): Promise<ethers.TransactionReceipt> => {
  return ptxr.then(txr => {
    return txr.wait(3);
  }).then(r => {
    if (r == null) {
      return Promise.reject("wait returns null");
    } else {
      return Promise.resolve(r);
    }
  });
}

