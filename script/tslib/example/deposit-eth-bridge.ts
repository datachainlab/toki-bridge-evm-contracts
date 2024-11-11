import { link } from 'fs';
import { tt, ethers, util } from '../index';
import { interfaces } from '../typechain-types/artifacts/@openzeppelin/contracts';

/**
 * Do approve.
 * Note that to execute a deposit, the amount to be deposited must be approved by Bridge.
 */
export const approve = async (
    depositor: ethers.Signer, // Signer(Runner, or Wallet) object of depositor
    bridgeAddress: string, // Bridge contract address
    tokenAddress: string, // Pooled Token contract address
    amountLd: bigint, // Amount to deposit in local decimals
): Promise<bigint> => {
    const depositorAddress = await depositor.getAddress();

    // Create token contract object which uses depositor as transaction signer
    const tokenByDepositor = await tt.IERC20__factory.connect(tokenAddress, depositor);

    // get current amount of allowance to bridge. Note that using byDepositor object for ease.
    const allowanceLd = await tokenByDepositor.allowance(depositorAddress, bridgeAddress);
    console.log(`allowance=${allowanceLd}, target=${amountLd}`);

    // return if enough amount is already approved
    if (amountLd <= allowanceLd) {
        console.log(`already approved: allowance=${allowanceLd}`);
        return 0n;
    }

    // calculate insufficient amount to deposit
    const insufficientLd = amountLd - allowanceLd;
    console.log(`insufficient=${insufficientLd}`);

    // run approve and wait
    console.log(`run and waiting approve(${bridgeAddress}, ${insufficientLd})...`);
    await util.receipt(tokenByDepositor.approve(bridgeAddress, insufficientLd));

    return insufficientLd;
}

/**
 * Do deposit.
 */
export const deposit = async (
    depositor: ethers.Signer, // Signer(Runner, or Wallet) object of depositor
    ethBridgeAddress: string, // ethBridge contract address
    amount: bigint, // Amount of deposit eth in wei
): Promise<void> => {
    // Create token contract object which uses depositor as transaction signer
    const ethBridgeByDepositor = await tt.ETHBridge__factory.connect(ethBridgeAddress, depositor);

    // Run deposit and wait
    await util.receipt(ethBridgeByDepositor.depositETH({value: amount}));
}

if (process.argv[1] === __filename) {
    /**
     * Do approve and deposit.
     * check in advance: caller has sufficient token balance
     * check after fact: caller's pooled token is decreased and liquidity token is increased.
     */
    const main = async (
        depositorPrivateKey: string, // hex string(no "0x" prefix) of private key of depositor
        jsonrpcUrl: string, // http jsonrpc endpoint of ethereum(compatible) node
        ethBridgeAddress: string, // ethBridge contract address
        amount: bigint, // Amount of deposit eth in wei
    ): Promise<boolean> => {
        // Create Wallet object of depositor
        const jsonrpcProvider = new ethers.JsonRpcProvider(jsonrpcUrl);
        const depositor = new ethers.Wallet(depositorPrivateKey, jsonrpcProvider);
        const depositorAddress = await depositor.getAddress();

        // create typechain object to easily call contract functions in TypeScript
        const ethBridge = tt.ETHBridge__factory.connect(ethBridgeAddress, jsonrpcProvider)

        // get Pool contract address from bridge contract
        const bridge = tt.Bridge__factory.connect(await ethBridge.BRIDGE(), jsonrpcProvider);
        const poolAddress = await bridge.getPool(await ethBridge.ETH_POOL_ID());
        const pool = await tt.Pool__factory.connect(poolAddress, jsonrpcProvider);

        // get EthVault contract address from EthBridge contract
        const ethVault = tt.ETHVault__factory.connect(await ethBridge.ETH_VAULT(), jsonrpcProvider);

        // get state values for information
        const getValues = async() => {
            return {
//                allowanceLd: await token.allowance(depositorAddress, bridgeAddress),
                ethBalanceOfDepositor: await jsonrpcProvider.getBalance(depositorAddress),
                vaultBalanceLdOfPool: await ethVault.balanceOf(poolAddress),
                ltBalanceLdOfDepositor: await pool.balanceOf(depositorAddress),
            }
        };

        const v0 = await getValues();
        console.log("-- before: ", v0);
        if (v0.ethBalanceOfDepositor < amount) {
            console.log("depositor has not enough balance to deposit");
            return false;
        }

        await deposit(depositor, ethBridgeAddress, amount);
        const v2 = await getValues();
        console.log("-- deposited: ", v2);
        console.log('check (v0.ethBalanceOfDepositor - v2.ethBalanceOfDepositor >= amount)', v0.ethBalanceOfDepositor, v2.ethBalanceOfDepositor, amount);
        if (v0.ethBalanceOfDepositor - v2.ethBalanceOfDepositor < amount) { // may consume for gas.
            console.log("ASSERT: eth balance is not correctly decreased");
            console.log(v0.ethBalanceOfDepositor - v2.ethBalanceOfDepositor, amount);
            return false;
        }
        console.log('check (v0.ltBalanceLdOfDepositor + amount == v2.ltBalanceLdOfDepositor)', v0.ltBalanceLdOfDepositor, amount, v2.ltBalanceLdOfDepositor);
        if (v0.ltBalanceLdOfDepositor + amount != v2.ltBalanceLdOfDepositor) {
            console.log("ASSERT: liquidity token balance is not correctly increased");
            return false;
        }
        return true;
    }

    const help = () => {
        console.log(`deposit.ts <private key> <jsonrpc url> <EthBridge address> <amount wei>`)
        process.exit();
    }

    if (process.argv.length !== 4+2) {
        help();
    }

    const prikey = process.argv[2];
    const url = process.argv[3];
    const ethBridgeAddress = process.argv[4];
    const amount = BigInt(process.argv[5]);

    const errorDecoder = util.newErrorDecoder();
    main(prikey, url, ethBridgeAddress, amount).catch(async(e) => {
        if (ethers.isCallException(e)) {
            const r = await errorDecoder.decode(e);
            console.log("call exception: ", r);
        } else {
            console.log(e);
        }
    });
}
