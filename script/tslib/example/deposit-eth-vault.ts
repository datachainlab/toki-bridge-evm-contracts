import { tt, ethers, util } from '../index';
import { interfaces } from '../typechain-types/artifacts/@openzeppelin/contracts';

const depositEthVault = async(
    signer: ethers.Signer,
    tokenAddress: string,
    amountLd: bigint,
): Promise<void> => {
    const token = await tt.ETHVault__factory.connect(tokenAddress, signer);
    await util.receipt(token.deposit({value: amountLd }));
}


if (process.argv[1] === __filename) {
    const main = async (
        depositorPrivateKey: string,
        jsonrpcUrl: string,
        tokenAddress: string,
        amountLd: bigint,
    ): Promise<boolean> => {
        const jsonrpcProvider = new ethers.JsonRpcProvider(jsonrpcUrl);

        const depositor = new ethers.Wallet(depositorPrivateKey, jsonrpcProvider);
        const depositorAddress = await depositor.getAddress();

        const token = await tt.IERC20__factory.connect(tokenAddress, jsonrpcProvider);

        const getValues = async() => {
            return {
                nativeBalance: await jsonrpcProvider.getBalance(depositorAddress),
                tokenBalance: await token.balanceOf(depositorAddress),
            }
        };

        const v0 = await getValues();
        console.log("-- before: ", v0);
        if (v0.nativeBalance < amountLd) {
            console.log("ASSERT: depositor has not enough balance to deposit");
            return false;
        }

        await depositEthVault(depositor, tokenAddress, amountLd);
        const v1 = await getValues();
        console.log("-- minted: ", v1);
        if (v0.tokenBalance + amountLd != v1.tokenBalance) {
            console.log("ASSERT: token balance is not correctly increased");
            return false;
        }
        return true;
    }

    const help = () => {
        console.log(`deposit.ts <private key> <jsonrpc url> <token contract address> <amount ld>`)
        process.exit();
    }

    if (process.argv.length !== 4+2) {
        help();
    }

    const prikey = process.argv[2];
    const url = process.argv[3];
    const tokenAddress = process.argv[4];
    const amountLd = BigInt(process.argv[5]);

    const errorDecoder = util.newErrorDecoder();
    main(prikey, url, tokenAddress, amountLd).catch(async(e) => {
        if (ethers.isCallException(e)) {
            const r = await errorDecoder.decode(e);
            console.log("call exception: ", r);
        } else {
            console.log(e);
        }
    });
}



