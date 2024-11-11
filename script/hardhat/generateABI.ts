import * as fs from "fs";
import * as path from "path";
import { glob } from "glob";

import * as hre from "hardhat";

async function main() {
  const outputPath = path.resolve(path.join(__dirname, "../../", "out", "abi"));
  fs.existsSync(outputPath) && fs.rmSync(outputPath, { recursive: true });
  fs.mkdirSync(outputPath, { recursive: true });

  // copy ABI in ${root}/abi to ${root}/out/abi
  const abiDirPath = path.resolve(path.join(__dirname, "../../", "abi"));
  glob.glob(`${abiDirPath}/**/*.json`, (err, paths) => {
    if (err) {
      throw err;
    }

    paths.forEach((p) => {
      const file = fs.readFileSync(p, "utf-8");
      let obj;
      try {
        obj = JSON.parse(file);
      } catch (err) {
        throw err;
      }

      if (!obj.abi) {
        throw new Error(`${path.basename(p)} is invalid format`);
      }

      fs.writeFileSync(
        path.resolve(outputPath, `${path.parse(p).name}.abi`),
        JSON.stringify(obj.abi, null, 2)
      );
    });
  });

  // copy ABI is build by hardhat to ${root}/out/abi
  const names = await hre.artifacts.getAllFullyQualifiedNames();
  names
    .filter((n) => hre.artifacts.artifactExists(n))
    .forEach((artifact) => {
      const { contractName, abi } = hre.artifacts.readArtifactSync(artifact);
      if (contractName && abi) {
        const abiJson = JSON.stringify(abi, null, 2);
        // filtered empty abi = `[]`
        if (abiJson.length > 2) {
          fs.writeFileSync(
            path.resolve(path.join(outputPath, `${contractName}.abi`)),
            abiJson
          );
        }
      }
    });
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
