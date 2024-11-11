# toki-bridge-evm-contracts

## Requirements

- Foundry
- Node v18.14.0
- gsed
  - for Mac: `brew install gnu-sed`

For more information on Foundry, please visit [https://book.getfoundry.sh/](https://book.getfoundry.sh/).

## Compilation

To compile the project, run the following command:

```
make setup
make build
```


## Testing

### Test using Foundry
To run tests, execute the following command:

```
make test
```

### Test using Hardhat 
To run tests, execute the following command:

```
make build-hardhat
make test-hardhat
```

## Formatting

Solidity files are automatically formatted with Prettier upon git commit. To enable this feature, run the following command:

```
npm run format
```

## ABI
## Github Actions
### Slither
Slither is a Solidity static analysis tool. Slither depends on foundry, so we maintain nightly tags for foundry.
Foundry provides persisted artifacts on a monthly basis. We want to switch to the latest nightly version as they become available.
