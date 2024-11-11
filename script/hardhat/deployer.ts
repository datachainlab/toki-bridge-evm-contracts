import fs from "fs";
import * as hre from "hardhat";
import {upgrades} from "hardhat";
import {ForceImportOptions} from "@openzeppelin/hardhat-upgrades/src/utils";
import {SignerWithAddress} from "@nomicfoundation/hardhat-ethers/signers";
import {DeployImplementationOptions, DeployProxyOptions, UpgradeProxyOptions} from "@openzeppelin/hardhat-upgrades/dist/utils";
import {
  Provider,
  BaseContract,
  Contract,
  ContractFactory,
  ContractTransactionReceipt,
  ContractTransactionResponse,
  FeeData,
  TransactionResponse,
  TransactionReceipt
} from 'ethers';
import ReportData from "./reportData";

export type BUILDER_TYPE = "hardhat" | "forge";

function retry<T>(f: (n:number) => Promise<T>, n: number, waitMillis: number): Promise<T> {
  let promise = f(0);
  for (let i = 1; i < n; ++i) {
    promise = promise.catch(() => {
      return new Promise((r) => setTimeout(r, waitMillis)).then(() => f(i));
    });
  }
  return promise;
}

export default class Deployer {
  public readonly builder: BUILDER_TYPE;
  public readonly header: string;
  public readonly config: any;
  public readonly network: any;
  public readonly provider: Provider;
  public readonly deployerAccount: SignerWithAddress;
  public readonly reportData: ReportData;
  public readonly waitMillis: number;
  // Skip to deploy contract if this map has entry. NOTE that initializing call in deploy function is not skipped.
  public reuse: Map<string, string>; // name -> address.
  public reportPrefix: string;
  public reportSuffix: string;

  private readonly gasCalculator: GasCalculator;

  constructor(
    builder: BUILDER_TYPE,
    config: any,
    provider: Provider,
    network: any,
    deployerAccount: SignerWithAddress,
    gasCalculator: GasCalculator,
    reportData?: ReportData
  ) {
    if (!["hardhat", "forge"].includes(builder)) {
      throw new Error("unknown builder: " + builder);
    }
    this.builder = builder;
    this.config = config;
    this.provider = provider;
    this.network = network;
    this.waitMillis = 3000;
    this.deployerAccount = deployerAccount;
    this.gasCalculator = gasCalculator;
    this.reuse = new Map<string, string>();
    this.reportData = reportData ?? new ReportData();
    this.reportPrefix = "";
    this.reportSuffix = "";
    this.header = `(${network.chainId})`;
  }
  newReportPrefix(pre?: string): Deployer {
    const r = new Deployer(
      this.builder,
      this.config,
      this.provider,
      this.network,
      this.deployerAccount,
      this.gasCalculator,
      this.reportData
    );
    r.reuse = new Map<string, string>();
    for (const kv of this.reuse) { r.reuse.set(kv[0], kv[1]); }
    r.reportPrefix = pre ?? "";
    return r;
  }

  reportName(name: string) {
    return (this.reportPrefix ?? "") + name;
  }

  address(): Promise<string> {
    return this.deployerAccount.getAddress();
  }

  async unwatchEvents(contract: ethers.Contract): Promise<void> {
    await contract.removeAllListeners();
  }

  async watchEvents(name: string, contract: ethers.Contract): Promise<void> {
    const head = `emit: chainId=${this.network.chainId}`;
    await contract.on("*", (ev: any) => {
      const evLog = contract.interface.parseLog(ev.log);
      if (evLog != null) {
        console.log(`${head}: ${name}: ${evLog.name}`, evLog.args);
        console.log(evLog);
      } else {
        console.log(`${head}: ${name}: unparsed event: `, ev.log);
      }
    });
  }

  async txOptions(override_?: any): Promise<any> {
    const {maxPriorityFeePerGas, maxFeePerGas} = await this.gasCalculator.calculate();

    return Object.assign(
      {},
      {
        maxPriorityFeePerGas: maxPriorityFeePerGas,
        maxFeePerGas: maxFeePerGas,
      },
      override_
    );
  }

  async receipt(
    reportName: string,
    ptxr: Promise<TransactionResponse>
  ): Promise<TransactionReceipt> {
    return this.receiptResponse(reportName, await ptxr);
  }

  async receiptResponse(
    reportName: string,
    resp: TransactionResponse
  ): Promise<TransactionReceipt> {
    await this.outputDeployerBalance();
    process.stdout.write(`${reportName}...\n`);

    const receipt: TransactionReceipt | null = await resp.wait();
    if (receipt == null) {
      throw new Error('no transaction');
    }
    this.outputTxResultLog(reportName, receipt)

    this.reportData.pushTransactions(reportName, [receipt]);
    return receipt;
  }

  // Note that hardhat's getContractFactory refuses abstract contract or interface.
  async getContractFactory(
    name: string,
    _builder?: string
  ): Promise<ContractFactory> {
    const builder = _builder ?? this.builder;
    if (builder == "hardhat") {
      return await hre.ethers.getContractFactory(name);
    } else if (builder == "forge") {
      // error in upgrades.deployProxy
      const path = `artifacts/src/${name}.sol/${name}.json`;
      const json = JSON.parse(fs.readFileSync(path, 'utf-8'));
      return new hre.ethers.ContractFactory(json.abi, json.bytecode.object);
    } else if (builder == "abi") {
      // error in upgrades.deployProxy
      const path = `abi/${name}.json`;
      const json = JSON.parse(fs.readFileSync(path, 'utf-8'));
      return new hre.ethers.ContractFactory(json.abi, json.bytecode.object);
    } else {
      throw new Error("unknown builder: " + builder);
    }
  }
  async getContractAt<T extends BaseContract>(
    name: string,
    address: string
  ): Promise<T> {
    if (this.builder == "hardhat") {
      const c = await hre.ethers.getContractAt(name, address); // hre.ethers.getContractAt returns Contract
      return c as BaseContract as T;
    } else if (this.builder == "forge") {
      const factory = await this.getContractFactory(name);
      return factory.attach(address) as T;
    } else {
      throw new Error("unknown builder: " + this.builder);
    }
  }

  async getDeployed<T extends BaseContract>(
    name: string,
    address: string
  ): Promise<T> {
    //console.log(`getDeployed(${name}, ${address})`);
    const deployed = await this.getContractAt(name, address);
    return deployed as T;
  }

  async deploy<T extends BaseContract>(
    name: string,
    args: unknown[],
    altname?: string
  ): Promise<T> {
    const reportName = this.reportName(altname ?? name);
    const txOptions = await this.txOptions();
    await this.outputDeployerBalance();
    process.stdout.write(`${this.header} deploying ${reportName}...\n`);

    return (async () => {
      const factory = await this.getContractFactory(name);
      if (this.reuse.get(reportName) != null) {
        const addr = this.reuse.get(reportName)!;
        console.log(`${reportName} is reused at ${addr}...\n`);
        this.reportData.setReuse(reportName, addr);
        return factory.attach(addr) as T;
      }
      const contract = await factory
        .connect(this.deployerAccount)
        .deploy(...args, txOptions);

      this.outputDeployStartLog(reportName, contract.deploymentTransaction());

      await contract.waitForDeployment();

      await this.reportData.setContract(reportName, contract);

      const receipt = this.reportData.getContractTransactionReceipt(reportName);
      receipt ?
        this.outputDeployResultLog(reportName, await contract.getAddress(), receipt) :
        console.log(`${reportName} is not deployed.`);

      return contract.connect(this.deployerAccount) as T;
    })().catch((e) => {
      console.log(`${reportName} failed. arguments are: `, args);
      return Promise.reject(e);
    });
  }

  async deployAbi<T extends BaseContract>(
    name: string,
    args: unknown[],
    altname?: string
  ): Promise<T> {
    const reportName = this.reportName(altname??name);
    await this.outputDeployerBalance();
    process.stdout.write(`${this.header} deploying ${reportName}...\n`);

    const txOptions = await this.txOptions();
    return (async () => {
      const factory = await this.getContractFactory(name, "abi");
      if (this.reuse.get(reportName) != null) {
        const addr = this.reuse.get(reportName)!;
        console.log(`${reportName} is reused at ${addr}...\n`);
        this.reportData.setReuse(reportName, addr);
        return factory.attach(addr) as T;
      }

      const contract = await factory
        .connect(this.deployerAccount)
        .deploy(...args, txOptions);

      this.outputDeployStartLog(reportName, contract.deploymentTransaction());

      await contract.waitForDeployment();

      await this.reportData.setContract(reportName, contract);

      const receipt = this.reportData.getContractTransactionReceipt(reportName);
      receipt ?
        this.outputDeployResultLog(reportName, await contract.getAddress(), receipt) :
        console.log(`${reportName} is not deployed.`);

      return contract.connect(this.deployerAccount) as T;
    })().catch((e) => {
      console.log(`${reportName} failed. arguments are: `, args);
      return Promise.reject(e);
    });
  }

  async deployUpgradeable<T extends BaseContract>(
    name: string,
    constructorArgs: unknown[],
    initArgs: unknown[],
    altname?: string
  ): Promise<T> {
    const reportName = this.reportName(altname ?? name);
    const reportNameImpl = `${reportName}(impl)`;
    await this.outputDeployerBalance();
    process.stdout.write(
      `${this.header} deployUpgradeable ${reportName}...\n`
    );
    if (this.reuse.get(reportNameImpl) != null && this.reuse.get(reportName) != null) {
      const implAddr = this.reuse.get(reportNameImpl)!;
      console.log(`${reportNameImpl} is reused at ${implAddr}...\n`);
      this.reportData.setReuse(reportNameImpl, implAddr);

      const proxyAddr = this.reuse.get(reportName)!;
      console.log(`${reportName} is reused at ${proxyAddr}...\n`);
      this.reportData.setReuse(reportName, proxyAddr);

      const implFactory = await this.getContractFactory(name);
      const options: ForceImportOptions = { constructorArgs };
      const proxyContract = await upgrades.forceImport(proxyAddr, implFactory, options);
      return proxyContract.connect(this.deployerAccount) as T;
    }

    return retry(
      (i: number) => {
        return (async() => {
          if (this.builder != "hardhat") {
            throw new Error("not implemented yet");
          }
          const factory = await this.getContractFactory(name)
            .then(f => f.connect(this.deployerAccount));

          let txOverrides = await this.txOptions({});

          // explicitly deploy implementation contract
          // NOTE: deployImplentaion(onchange) executes no tx and returns existing tx when same contract is already deployed.
          const implOptions: DeployImplementationOptions = {
            constructorArgs,
            txOverrides,
            redeployImplementation: 'onchange',
            getTxResponse: true
          };
          const implAddress = await this.deployImplementation(reportNameImpl, factory, implOptions);
          await this.reportData.setContract(
            `${reportNameImpl}`,
            await this.getDeployed<T>(name, implAddress)
          );

          // then deploy by deployProxy with redeployImplementation=never
          txOverrides = await this.txOptions({});

          const proxyOptions: DeployProxyOptions = {
            constructorArgs,
            txOverrides,
            initializer: "initialize",
            redeployImplementation: 'never'
          };
          const proxyContract = await upgrades.deployProxy(
            factory,
            initArgs,
            proxyOptions
          );

          this.outputDeployStartLog(reportName, proxyContract.deploymentTransaction());

          await proxyContract.waitForDeployment();
          await this.reportData.setContract(reportName, proxyContract);

          const receipt = this.reportData.getContractTransactionReceipt(reportName);
          receipt ?
            this.outputDeployResultLog(reportName, await proxyContract.getAddress(), receipt) :
            console.log(`${reportName} is not deployed.`);

          return proxyContract.connect(this.deployerAccount) as T;
        })();
      },
      5,
      this.waitMillis).catch((e) => {
        console.log(`${reportName} failed. ${e.message}. arguments are: `,
                    constructorArgs,
                    initArgs
                   );
        return Promise.reject(e);
      });
  }

  async deployImplementation(
    reportName: string,
    factory: ContractFactory,
    opts: DeployImplementationOptions
  ): Promise<string> {
    const txr_or_address = await upgrades.deployImplementation(factory, opts);
    if (typeof(txr_or_address) === 'string') {
      return txr_or_address;
    } else {
      const receipt = await this.receiptResponse(reportName, txr_or_address);
      if (receipt.contractAddress == null) {
        throw new Error('deployImplementation returns contractAddress');
      }
      return receipt.contractAddress;
    }
  }

  async upgrade<T extends BaseContract>(
    name: string,
    redeployImplementation: 'onchange'|'never'|'always',
    referenceAddress: string,
    constructorArgs: unknown[],
    call?: { fn: string; args?: unknown[] },
    altname?: string
  ): Promise<T> {
    const reportName = this.reportName(altname??name);
    process.stdout.write(`upgrading ${reportName} at ${referenceAddress} to ${name}...`);
    const txOverrides = await this.txOptions({});
    return (async() => {
      const factory = await this.getContractFactory(name);

      const validateOpts = {
        unsafeAllow: [],
        unsafeAllowRenames: false,
        unsafeSkipStorageCheck: false,
        constructorArgs,
        call,
        txOverrides,
      };

      await upgrades.validateUpgrade(
        referenceAddress,
        factory,
        validateOpts,
      );

      console.log('deploy impl ....', redeployImplementation);
      const implOptions: DeployImplementationOptions = {
        constructorArgs,
        txOverrides,
        redeployImplementation,
        getTxResponse: true
      };
      const implAddress = await this.deployImplementation(
        `${reportName}(impl)`,
        factory,
        implOptions
      );
      await this.reportData.setContract(
        `${reportName}(impl)`,
        await this.getDeployed<T>(name, implAddress)
      );

      const upgradeOpts: UpgradeProxyOptions = {
        ...validateOpts,
        redeployImplementation: 'never',
      };
      const contract = await upgrades.upgradeProxy(
        referenceAddress,
        factory,
        upgradeOpts,
      );
      await contract.waitForDeployment();
      await this.reportData.setContract(reportName, contract);
      console.log(await contract.getAddress());

      return contract.connect(this.deployerAccount) as T;
    })().catch((e) => {
      console.log(`${reportName} failed. arguments are: `, referenceAddress, constructorArgs, call);
      return Promise.reject(e);
    });
  }

  private async outputDeployerBalance() {
    console.log(
      `=====Deployer: ${hre.ethers.formatEther(await hre.ethers.provider.getBalance(this.deployerAccount))} ETH=====`,
    );
  }

  private outputDeployStartLog(
    reportName: string,
    tx: ContractTransactionResponse | null,
  ) {
    tx &&
    console.log(`${reportName}:Deploy:Start`, {
      hash: tx.hash,
      from: tx.from,
      nonce: tx.nonce,
      gasPrice: tx.gasPrice.toString(),
      maxFeePerGas: tx.maxFeePerGas?.toString(),
      maxPriorityFeePerGas: tx.maxPriorityFeePerGas?.toString(),
      chainId: tx.chainId.toString(),
    });
  }

  private outputDeployResultLog(
    reportName: string,
    address: string,
    receipt: TransactionReceipt,
  ) {
    console.log(`${reportName}:Deploy:Result`, {
      name: reportName,
      address,
      hash: receipt.hash,
      height: receipt.blockNumber,
      gasPrice: receipt.gasPrice.toString(),
      gasUsed: receipt.gasUsed.toString(),
      gasCost: `${hre.ethers.formatEther(receipt.gasPrice * receipt.gasUsed)} ETH`,
    });
  }

  private outputTxResultLog(
    reportName: string,
    receipt: TransactionReceipt,
  ) {
    console.log(`${reportName}:Tx:Result`, {
      name: reportName,
      address: receipt.to,
      hash: receipt.hash,
      height: receipt.blockNumber,
      gasPrice: receipt.gasPrice.toString(),
      gasUsed: receipt.gasUsed.toString(),
      gasCost: `${hre.ethers.formatEther(receipt.gasPrice * receipt.gasUsed)} ETH`,
    });
  }
}

export interface Gas {
  maxPriorityFeePerGas: null | bigint;
  maxFeePerGas: null | bigint;
}

export abstract class GasCalculator {
  abstract calculate(): Promise<Gas>;
}

export interface GasProvider {
  getFeeData(): Promise<FeeData>;
}

export class AutomatedGasCalculator extends GasCalculator {
  provider: GasProvider;

  constructor(provider: GasProvider) {
    super();
    this.provider = provider;
  }

  async calculate(): Promise<Gas> {
    // ethers.js formulas
    // maxPriorityFeePerGas = (priorityFee != null) ? priorityFee: BigInt("1000000000");
    // maxFeePerGas = (block.baseFeePerGas * BN_2) + maxPriorityFeePerGas;
    const { maxPriorityFeePerGas, maxFeePerGas } =
      await this.provider.getFeeData();

    return {
      maxPriorityFeePerGas,
      maxFeePerGas,
    };
  }
}

export class FixedGasCalculator extends GasCalculator {
  maxPriorityFeePerGas: bigint;
  maxFeePerGas: bigint;

  constructor(maxPriorityFeePerGas: string, maxFeePerGas: string) {
    super();
    this.maxPriorityFeePerGas = BigInt(maxPriorityFeePerGas);
    this.maxFeePerGas = BigInt(maxFeePerGas);
  }

  async calculate(): Promise<Gas> {
    return {
      maxPriorityFeePerGas: this.maxPriorityFeePerGas,
      maxFeePerGas: this.maxFeePerGas,
    };
  }
}
