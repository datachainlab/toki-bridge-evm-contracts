import {ethers, tt, util} from '../index';
import { decodeRetry } from '../util/retry';

const retryOnReceive = async(
    bridge: tt.artifacts.src.interfaces.IBridge,
    port: string,
    channel: string,
    sequence: bigint,
): Promise<void> => {
    await util.receipt(bridge.retryOnReceive(channel, sequence));
}

const getRevertReceive = async (
    bridge: tt.artifacts.src.interfaces.IBridge,
    chainId: bigint,
    sequence: bigint,
): Promise<util.Retry | null> => {
    const revertReceive = await bridge.revertReceive(chainId, sequence);
    if (revertReceive == '0x') {
        return null;
    }
    return decodeRetry(revertReceive);
};

if (process.argv[1] === __filename) {
    const main = async (
        privateKey: string,
        jsonrpcUrl: string,
        bridgeAddress: string,
        port: string,
        channel: string,
        sequence: bigint,
    ): Promise<boolean> => {
        const jsonrpcProvider = new ethers.JsonRpcProvider(jsonrpcUrl);
        const sender = new ethers.Wallet(privateKey, jsonrpcProvider);
        const bridge = await tt.IBridge__factory.connect(bridgeAddress, sender);

        const chainId = await bridge.getChainId(channel, false)
        const revertReceive = await getRevertReceive(bridge, chainId, sequence)
        if (revertReceive === null) {
            console.log("ASSERT: revertReceive is not registered");
            return false;
        }

        console.log("Retry type: " + revertReceive.typename);

        await retryOnReceive(bridge, port, channel, sequence);

        const revertReceiveAfterRetry = await getRevertReceive(bridge, chainId, sequence)
        if (revertReceiveAfterRetry !== null) {
            console.log("ASSERT: retryOnReceive failed");
            return false;
        }

        console.log("retryOnReceive success");
        return true;
    }

    const help = () => {
        console.log(`retry.ts <private key> <jsonrpc url> <bridge contract address> <port> <channel> <sequence>`)
        process.exit();
    }

    if (process.argv.length !== 6+2) {
        help();
    }

    const prikey = process.argv[2];
    const url = process.argv[3];
    const bridgeAddress = process.argv[4];
    const port = process.argv[5];
    const channel = process.argv[6];
    const sequence = BigInt(process.argv[7]);

    const errorDecoder = util.newErrorDecoder();
    main(prikey, url, bridgeAddress, port, channel, sequence).catch(async(e) => {
        if (ethers.isCallException(e)) {
            const r = await errorDecoder.decode(e);
            console.log("call exception: ", r);
        } else {
            console.log(e);
        }
    });
}
