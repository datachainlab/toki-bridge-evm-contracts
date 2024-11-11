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
    bridgeAddress: string, // Bridge contract address
    poolId: number, // Pool ID
    amountLd: bigint, // Amount of deposit pooled token in local decimals
    toLiquidityAddress: string, // An address where send to liquidity token
): Promise<void> => {
    // Create token contract object which uses depositor as transaction signer
    const bridgeByDepositor = await tt.Bridge__factory.connect(bridgeAddress, depositor);

    // Run deposit and wait
    await util.receipt(bridgeByDepositor.deposit(poolId, amountLd, toLiquidityAddress));
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
        bridgeAddress: string, // address of Bridge contract
        poolId: number, // id of pool deposit to
        amountLd: bigint,
    ): Promise<boolean> => {
        // Create Wallet object of depositor
        const jsonrpcProvider = new ethers.JsonRpcProvider(jsonrpcUrl);
        const depositor = new ethers.Wallet(depositorPrivateKey, jsonrpcProvider);
        const depositorAddress = await depositor.getAddress();

        // For testing, use depositorAddress where liquidity token is sent to.
        const toLiquidityAddress = depositorAddress;

        // create typechain object to easily call contract functions in TypeScript
        const bridge = tt.Bridge__factory.connect(bridgeAddress, jsonrpcProvider)

        // get Pool contract address from bridge contract by using pool id
        const poolAddress = await bridge.getPool(poolId);
        const pool = await tt.Pool__factory.connect(poolAddress, jsonrpcProvider);

        // get pooled token contract address from Pool contract
        const tokenAddress = await pool.token();
        const token = await tt.IERC20__factory.connect(tokenAddress, jsonrpcProvider);

        // get state values for information
        const getValues = async() => {
            return {
                allowanceLd: await token.allowance(depositorAddress, bridgeAddress),
                tokenBalanceLdOfDepositor: await token.balanceOf(depositorAddress),
                tokenBalanceLdOfPool: await token.balanceOf(poolAddress),
                ltBalanceLdOfDepositor: await pool.balanceOf(toLiquidityAddress),
            }
        };

        const v0 = await getValues();
        console.log("-- before: ", v0);
        if (v0.tokenBalanceLdOfDepositor < amountLd) {
            console.log("depositor has not enough balance to deposit");
            return false;
        }

        await approve(depositor, bridgeAddress, tokenAddress, amountLd);
        const v1 = await getValues();
        console.log("-- approved: ", v1);
        console.log(`check (v1.allowanceLd >= amountLd)`, v1.allowanceLd, amountLd);
        if (v1.allowanceLd < amountLd) {
            console.log("ASSERT: missing allowance");
            return false;
        }

        await deposit(depositor, bridgeAddress, poolId, amountLd, toLiquidityAddress);
        const v2 = await getValues();
        console.log("-- deposited: ", v2);
        console.log('check (v0.tokenBalanceLdOfDepositor - v2.tokenBalanceLdOfDepositor == amountLd)', v0.tokenBalanceLdOfDepositor, v2.tokenBalanceLdOfDepositor, amountLd);
        if (v0.tokenBalanceLdOfDepositor - v2.tokenBalanceLdOfDepositor != amountLd) {
            console.log("ASSERT: token balance is not correctly decreased");
            return false;
        }
        console.log('check (v0.ltBalanceLdOfDepositor + amountLd == v2.ltBalanceLdOfDepositor)', v0.ltBalanceLdOfDepositor, amountLd, v2.ltBalanceLdOfDepositor);
        if (v0.ltBalanceLdOfDepositor + amountLd != v2.ltBalanceLdOfDepositor) {
            console.log("ASSERT: liquidity token balance is not correctly increased");
            return false;
        }
        return true;
    }

    const help = () => {
        console.log(`deposit.ts <private key> <jsonrpc url> <bridge address> <pool id> <amount ld>`)
        process.exit();
    }

    if (process.argv.length !== 5+2) {
        help();
    }

    const prikey = process.argv[2];
    const url = process.argv[3];
    const bridgeAddress = process.argv[4];
    const poolId = Number(process.argv[5]);
    const amountLd = BigInt(process.argv[6]);

    const errorDecoder = util.newErrorDecoder();
    main(prikey, url, bridgeAddress, poolId, amountLd).catch(async(e) => {
        if (ethers.isCallException(e)) {
            const r = await errorDecoder.decode(e);
            console.log("call exception: ", r);
        } else {
            console.log(e);
        }
    });
}
