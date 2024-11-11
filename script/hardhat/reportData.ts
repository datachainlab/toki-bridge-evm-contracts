import { BaseContract, TransactionReceipt } from "ethers";

type TransactionData = {
  name: string;
  receipts: TransactionReceipt[];
};
type TransactionIndex = {
  blockNumber: number;
  txIndex: null | string;
};

export default class ReportData {
  public readonly contracts: Record<string, BaseContract>;
  public readonly reuse: Record<string, string>;
  public readonly transactions: TransactionData[];

  constructor() {
    this.contracts = {};
    this.reuse = {};
    this.transactions = [];
  }

  async setContract(name: string, contract: BaseContract): Promise<void> {
    this.contracts[name] = contract;

    const ptx = contract.deploymentTransaction();
    const tx  = (ptx == null) ? null : await ptx.wait();
    const txs = (tx == null) ? [] : [tx];
    this.pushTransactions(name, txs);
  }

  async setReuse(name: string, address: string): Promise<void> {
    this.reuse[name] = address;
  }

  getContractTransactionReceipt(name: string): TransactionReceipt | undefined  {
    const tx =  this.transactions.find(t => t.name === name);
    return tx && tx.receipts.length > 0 ? tx?.receipts[0] : undefined
  }

  pushTransactions(name: string, receipts: TransactionReceipt[]): void {
    this.transactions.push({ name, receipts });
  }
}
