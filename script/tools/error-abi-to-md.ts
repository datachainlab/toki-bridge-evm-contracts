import * as fs from 'fs';
import * as path from 'path';

interface AbiItem {
  type: string;
  name: string;
  inputs?: { name: string; type: string }[];
}

interface AbiFile {
  abi: AbiItem[];
}

function isErrorUnwanted(errorName: string, unwantedPatterns: string[]): boolean {
  return unwantedPatterns.some(pattern => {
    if (pattern.endsWith('*')) {
      return errorName.startsWith(pattern.slice(0, -1));
    }
    return errorName === pattern;
  });
}

function readUnwantedPatternsFromFile(filePath: string): string[] {
  const content = fs.readFileSync(filePath, 'utf8');
  return content.split('\n')
    .map(line => line.trim())
    .filter(line => line !== '' && (line.endsWith('*') || !line.includes('*')));
}

function extractUniqueErrorInfo(abiFile: string, sort: boolean = false): AbiItem[] {
  const data: AbiFile = JSON.parse(fs.readFileSync(abiFile, 'utf8'));
  const errorMap = new Map<string, AbiItem>();

  data.abi.forEach(item => {
    if (item.type === 'error' && !errorMap.has(item.name)) {
      errorMap.set(item.name, item);
    }
  });

  let errors = Array.from(errorMap.values());

  if (sort) {
    errors.sort((a, b) => a.name.localeCompare(b.name));
  }

  return errors;
}

function formatErrorInfoMarkdownWithUnwanted(errors: AbiItem[], unwantedPatterns: string[]): string {
  let markdown = "| Error Name | Parameters | Unwanted |\n|------------|------------|----------|\n";
  errors.forEach(error => {
    const name = error.name;
    const params = error.inputs && error.inputs.length > 0
      ? error.inputs.map(param => `${param.name}: ${param.type}`).join(", ")
      : "None";
    const unwanted = isErrorUnwanted(name, unwantedPatterns) ? "✓" : "";
    markdown += `| ${name} | ${params} | ${unwanted} |\n`;
  });
  return markdown;
}

function formatErrorInfoMarkdownWithoutUnwanted(errors: AbiItem[], unwantedPatterns: string[]): string {
  let markdown = "| Error Name | Parameters |\n|------------|------------|\n";
  errors.forEach(error => {
    if (!isErrorUnwanted(error.name, unwantedPatterns)) {
      const name = error.name;
      const params = error.inputs && error.inputs.length > 0
        ? error.inputs.map(param => `${param.name}: ${param.type}`).join(", ")
        : "None";
      markdown += `| ${name} | ${params} |\n`;
    }
  });
  return markdown;
}

function printOutput(output: string): void {
  console.log(output);
}

function main(abiFile: string, sort: boolean, unwantedFile: string, includeUnwanted: boolean, formatFunc: (errors: AbiItem[], unwantedPatterns: string[]) => string, outputFunc: (output: string) => void): void {
  const errors = extractUniqueErrorInfo(abiFile, sort);
  const unwantedPatterns = readUnwantedPatternsFromFile(unwantedFile);
  const formattedOutput = formatFunc(errors, unwantedPatterns);
  outputFunc(formattedOutput);
}

// npx ts-node script/tools/error-abi-to-md.ts -a abi/merge_custom_errors.json -u unwanted-errors.txt [--sort]
if (require.main === module) {
  const args = process.argv.slice(2);
  const sortFlag = args.includes('--sort');
  const includeUnwantedFlag = args.includes('--include-unwanted');

  const abiFileIndex = args.findIndex(arg => arg === '-a' || arg === '--abi');
  const unwantedFileIndex = args.findIndex(arg => arg === '-u' || arg === '--unwanted');

  if (abiFileIndex === -1) {
    console.error("Error: ABI file must be specified using -a or --abi option.");
    process.exit(1);
  }

  if (unwantedFileIndex === -1) {
    console.error("Error: Unwanted patterns file must be specified using -u or --unwanted option.");
    process.exit(1);
  }

  const abiFile = args[abiFileIndex + 1];
  const unwantedFile = args[unwantedFileIndex + 1];

  if (!abiFile || !unwantedFile) {
    console.error("Error: Both ABI file and unwanted patterns file must be provided.");
    process.exit(1);
  }

  const formatFunc = includeUnwantedFlag ? formatErrorInfoMarkdownWithUnwanted : formatErrorInfoMarkdownWithoutUnwanted;
  main(abiFile, sortFlag, unwantedFile, includeUnwantedFlag, formatFunc, printOutput);
}
