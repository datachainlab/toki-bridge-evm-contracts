const fs = require('fs');

const ENDPOINTS = {
    "bnb": "http://localhost:8545/",
    "eth": "http://localhost:18545/",
};

function help(msg) {
    if (msg != null) { console.log(msg); }
    console.log(`node parseDebugCall.js <eth | bnb> <hash>`);
    process.exit(1);
}
if (process.argv.length < 3) { help(); }

const chain = process.argv[2];
const hash = process.argv[3];

if (!["bnb","eth"].includes(chain)) {
    help(`unknown chain: ${chain}`);
}

const loadDeploy = (chain) => {
    const path = `${__dirname}/../contract-deploy/output/deploy-${chain}-oneshot-0.contract.json`;
    const data = JSON.parse(fs.readFileSync(path, 'utf-8'));
    const ret = {};
    for (const k in data) {
        const addr = data[k].toLowerCase();
        const namearray = k.split(".");
        const contract = (namearray.length == 1) ? namearray[0]: namearray[1];
        ret[addr] = { "name": k, "contract": contract };
    }
    return ret;
}

const getAbiDecoder = (deploy) => {
    const abiDecoder = require('abi-decoder');
    const filenames = Object.values(deploy).map(d => `${d["contract"]}.json`);
    // withFileTypes=true だと途中で打ち切られる???
    const dir = `${__dirname}/../../artifacts/src`;
    fs.readdirSync(dir, {withFileTypes:false, recursive:true})
      .forEach(entname => {
          const basename = entname.split('/').pop();
          if (filenames.includes(basename)) {
              const abi = JSON.parse(fs.readFileSync(`${dir}/${entname}`, 'utf-8')).abi;
              abiDecoder.addABI(abi);
          }
      });
    return abiDecoder;
}

const callRpc = async(url, data) => {
    const res = await fetch(url, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: data,
    });
    return res.json().then(_=>_.result);
}

const getTx = async(url, hash) => {
    const data = `{"jsonrpc":"2.0","id":0,"method":"eth_getTransactionByHash","params":["${hash}"]}`;
    const tx = await callRpc(url, data);

    const data2 = `{"jsonrpc":"2.0","id":0,"method":"eth_getBlockByHash","params":["${tx.blockHash}", true]}`;
    const block = await callRpc(url, data2);

    return { tx, block };
};

const getTraceCall = async(url, hash) => {
    const data = `{"jsonrpc":"2.0","id":0,"method":"debug_traceTransaction","params":["${hash}", {"tracer":"callTracer"}]}`;
    return callRpc(url, data);
};

const printCall = (data, deploy, abiDecoder, indent) => {
    const to_addr = data["to"];
    if (to_addr in deploy) {
        const d = deploy[to_addr];
        const decoded = abiDecoder.decodeMethod(data["input"]);
        if (decoded != null) {
            const params = decoded["params"].map((o) => `${o["name"]}=${o["value"]}`);
            console.log(`${indent}- ${d["name"]}#${decoded["name"]}(${params.join(", ")})`);
        } else {
            console.log(`${indent}- ${d["name"]}#???`);
        }
    } else {
        console.log(`${indent}- ${to_addr}`);
    }
    console.log(`${indent}  gas=${data["gas"]}, gasUsed=${data["gasUsed"]}`);
    console.log(`${indent}  output=${data["output"]}`);
    if ("error" in data) { console.log(`${indent}  error=${data["error"]}`); }
    if ("calls" in data) {
        for (const c of data["calls"]) {
            printCall(c, deploy, abiDecoder, indent + "  ");
        }
    }
}
const main = async (chain, hash) => {
    const endpoint = ENDPOINTS[chain];

    const info = await getTx(endpoint, hash);
    console.log("tx: ");
    console.log(`  from=${info.tx.from}`);
    console.log(`  gas=${info.tx.gas}`);
    console.log(`  gasPrice=${info.tx.gasPrice}`);
    console.log("block: ");
    console.log(`  number=${info.block.number}`);
    console.log(`  hash=${info.block.hash}`);
    console.log(`  gasLimit=${info.block.gasLimit}`);
    console.log(`  gasUsed=${info.block.gasUsed}`);
    console.log(`  transactions=${info.block.transactions.length}`);

    const deploy = loadDeploy(chain);
    const abiDecoder = getAbiDecoder(deploy);
    const calls = await getTraceCall(endpoint, hash);
    console.log("callstack: ");
    printCall(calls, deploy, abiDecoder, "  ");
}

main(chain, hash);

