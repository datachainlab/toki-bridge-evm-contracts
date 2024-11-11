import ReportData from "./reportData";
import fs from "fs";
import Chartscii, { ChartData } from "chartscii";

export default class DeployReport {
  static async report(data: ReportData, parameters: any): Promise<void> {
    console.log("Deploy Report");
    console.log("=============");
    console.log("Parameters:");
    console.log(JSON.stringify(parameters, bigIntReplacer, 2));
    console.log("=============");
    console.log("Contracts:");
    for (const [name, contract] of Object.entries(data.contracts)) {
      const address = await contract.getAddress();
      console.log(`${name}: ${address}`);
    }
  }

  static async reportContract(data: ReportData, path: string): Promise<void> {
    const obj = [];
    for (const [name, contract] of Object.entries(data.contracts)) {
      const address = await contract.getAddress();
      const tx = contract.deploymentTransaction();
      const receipt = data.transactions
        .filter((t) => t.name == name)
        .flatMap((data) => data.receipts)
        .find((receipts) => receipts.hash == tx?.hash);

      obj.push({
        name,
        address,
        hash: tx?.hash,
        height: receipt?.blockNumber,
      });
    }
    fs.writeFileSync(path, JSON.stringify(obj, null, 2));
  }

  static async reportReuse(data: ReportData, path: string): Promise<void> {
    const obj = [];
    for (const [name, address] of Object.entries(data.reuse)) {
      obj.push({
        name,
        address,
      });
    }
    if (0 < obj.length) {
      fs.writeFileSync(path, JSON.stringify(obj, null, 2));
    }
  }

  static readReportContract(path: string): any {
    const json = JSON.parse(fs.readFileSync(path, "utf-8"));
    return json;
  }

  static _sumGas(data: ReportData): {
    name: string;
    gasUsed: bigint;
    txs: { hash: string; gasUsed: bigint }[];
  }[] {
    const logs = [];
    for (const d of data.transactions) {
      let txs = [];
      let sum = 0n;
      for (const receipt of d.receipts) {
        const gasUsed = receipt.gasUsed == null ? 0n : BigInt(receipt.gasUsed);
        txs.push({ hash: receipt.hash, gasUsed });
        sum += gasUsed;
      }
      logs.push({ name: d.name, gasUsed: sum, txs });
    }
    return logs;
  }
  static reportGas(data: ReportData, path: string): void {
    const logs = this._sumGas(data);
    const replacer = (key:string, value:any) => {
      if (typeof value === "bigint") {
        return value.toString();
      }
      return value;
    };
    fs.writeFileSync(path, JSON.stringify(logs, replacer, 2));
  }

  static reportGasChart(data: ReportData, path: string): void {
    const logs = this._sumGas(data);
    const chartData: Array<ChartData> = [];
    let total = 0n;
    for (const d of logs) {
      total += d.gasUsed;
      chartData.push({
        label: `${d.name} (${d.gasUsed.toString()})`,
        value: Number(d.gasUsed),
        color: undefined,
      });
    }

    const chartscii = new Chartscii(chartData, {
      colorLabels: false,
      width: 50,
      sort: true,
      reverse: true,
    });
    fs.writeFileSync(path, chartscii.create());
    fs.appendFileSync(path, `\ntotal: ${total.toString()}\n`);
  }
}

interface BigIntJSON {
  type: "BigInt";
  value: string;
}

function isBigIntJSON(obj: unknown): obj is BigIntJSON {
  return (
    typeof obj === "object" &&
    obj !== null &&
    "type" in obj &&
    obj.type === "BigInt"
  );
}

function bigIntReplacer(val: unknown): unknown {
  if (isBigIntJSON(val)) {
    return BigInt(val.value).toString();
  }
  return val;
}
