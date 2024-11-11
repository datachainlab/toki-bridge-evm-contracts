import { ethers } from './lib';

const signer = ethers.Wallet.createRandom();
console.log(JSON.stringify({
  address: signer.address,
  publicKey:signer.publicKey,
  privateKey: signer.privateKey,
  mnemonic: signer.mnemonic!.phrase,
}, null, 2));
