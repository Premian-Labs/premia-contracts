# Openhedge Contracts

Openhedge options markets.

## Development

Install dependencies via Yarn:

```bash

yarn install

```

Compile contracts via Hardhat:

```bash

yarn compile

```

### Dotenv

Create a .env file in the root directory for storing environement variables

- MNEMONIC - Seed phrase for your deployer account
- NETWORK - local or kovan
- INFURA_KEY - Your infura api key
- REPORT_GAS - bool for if you want to report gas

### Networks

By default, Hardhat uses the Hardhat Network in-process.

To use an default network network:

```bash

yarn test

```

### Testing

Test contracts via Hardhat:

```bash

yarn test --network local

```

Generate a code coverage report using `solidity-coverage`:

```bash

yarn coverage

```

### Deployment

The contract can be deployed using the `deploy` task:

```bash

yarn deploy

```

### Documentation

A documentation site is output on contract compilation to the `docgen` directory.  It can also be generated manually:

```bash

yarn docgen

```
