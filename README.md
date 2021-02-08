# Openhedge Contracts

Openhedge options markets.

## Development

Install dependencies via Yarn:

```bash
yarn install
```

Compile contracts via Hardhat:

```bash
yarn run hardhat compile
```

### Networks

By default, Hardhat uses the Hardhat Network in-process.

To use an external network via URL, set the `URL` environment variable and append commands with `--network generic`:

```bash
URL="[NODE_URL]" yarn run hardhat test --network generic
```

### Testing

Test contracts via Hardhat:

```bash
yarn run hardhat test
```

Activate gas usage reporting by setting the `REPORT_GAS` environment variable to `"true"`:

```bash
REPORT_GAS=true yarn run hardhat test
```

Generate a code coverage report using `solidity-coverage`:

```bash
yarn run hardhat coverage
```

### Documentation

A documentation site is output on contract compilation to the `docgen` directory.  It can also be generated manually:

```bash
yarn run hardhat docgen
```
