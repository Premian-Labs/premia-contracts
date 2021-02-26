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

Activate gas usage reporting by setting the `REPORT_GAS` environment variable to `"true"`:

```bash
REPORT_GAS=true yarn run hardhat test
```

Generate a code coverage report using `solidity-coverage`:

```bash
yarn run hardhat coverage
```

### Deployment

The contract can be deployed using the `deploy` task:

```bash
yarn deploy
```

### Documentation

A documentation site is output on contract compilation to the `docgen` directory.  It can also be generated manually:

```bash
yarn run hardhat docgen
```
