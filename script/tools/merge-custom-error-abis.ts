import * as path from 'path';
import * as fs from 'fs';

interface AbiItem {
  type: string;
  name: string;
  inputs?: { name: string; type: string }[];
}

interface JsonFile {
  abi?: AbiItem[];
}

function traverseAbi(dir: string, acc: Map<string, AbiItem> = new Map()): Map<string, AbiItem> {
  const files = fs.readdirSync(dir);
  for (const file of files) {
    if (['build-info', 'merge_custom_errors.json'].includes(file)) {
      continue;
    }
    const filePath = path.join(dir, file);
    const fileStat = fs.statSync(filePath);
    if (fileStat.isDirectory()) {
      traverseAbi(filePath, acc);
    } else if (/^[a-zA-Z0-9_]+\.json$/.test(file)) {
      const json: JsonFile = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      if (json.abi != null) {
        for (const abi of json.abi) {
          if (abi.type === 'error') {
            // check duplicate
            if (!acc.has(abi.name)) {
              acc.set(abi.name, abi);
            }
          }
        }
      }
    }
  }
  return acc;
}

function main() {
  const rootdir = path.dirname(path.dirname(__dirname));

  const abiMap = new Map<string, AbiItem>();
  traverseAbi(path.join(rootdir, 'artifacts'), abiMap);
  traverseAbi(path.join(rootdir, 'abi'), abiMap);

  const json = {
    contractName: 'merge',
    abi: Array.from(abiMap.values()),
  };

  console.log(JSON.stringify(json, null, 2));
}

main();
