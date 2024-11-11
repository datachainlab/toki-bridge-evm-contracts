import { tt, ethers, util } from '../index';
import { interfaces } from '../typechain-types/artifacts/@openzeppelin/contracts';

const mintPseudoToken = async(
    signer: ethers.Signer,
    tokenAddress: string,
    mintToAddress: string,
    amountLd: bigint,
): Promise<void> => {
    const pseudoToken = await tt.PseudoToken__factory.connect(tokenAddress, signer);
    await util.receipt(pseudoToken.mint(mintToAddress, amountLd));
}


if (process.argv[1] === __filename) {
    const main = async (
        minterPrivateKey: string,
        jsonrpcUrl: string,
        tokenAddress: string,
        amountLd: bigint,
    ): Promise<boolean> => {
        const jsonrpcProvider = new ethers.JsonRpcProvider(jsonrpcUrl);

        const minter = new ethers.Wallet(minterPrivateKey, jsonrpcProvider);
        const mintToAddress = await minter.getAddress();

        const token = await tt.IERC20__factory.connect(tokenAddress, jsonrpcProvider);

        const getValues = async() => {
            return {
                balance: await token.balanceOf(mintToAddress),
            }
        };

        const v0 = await getValues();
        console.log("-- before: ", v0);

        await mintPseudoToken(minter, tokenAddress, mintToAddress, amountLd);
        const v1 = await getValues();
        console.log("-- minted: ", v1);
        if (v0.balance + amountLd != v1.balance) {
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



