# Median Contracts

Median Finance options markets.

## Development

Install dependencies via Yarn:

```bash
yarn install
```

Install the Hardhat Shorthand package globally and enable autocompletion:

```bash
yarn global add hardhat-shorthand
hardhat-completion install
```

Compile contracts via Hardhat:

```bash
hh compile
```

### Environment Variables

Several commands rely on the configuration of environment variables.  These can be set per-command in the terminal, or defined in the `.env` file in the project root directory.

- MNEMONIC - Seed phrase for your deployer account
- INFURA_KEY - Your infura api key
- REPORT_GAS - bool for if you want to report gas

## Testing

To use a default network network:

```bash
hh test
```

Test contracts on specific network:

```bash
hh test --network localhost
```

Generate a code coverage report using `solidity-coverage`:

```bash
hh coverage
```

### Deployment

The contract can be deployed on the default network using the `deploy` task:

```bash
hh deploy
```

### Documentation

A documentation site is output on contract compilation to the `docgen` directory.  It can also be generated manually:

```bash
hh docgen
```
