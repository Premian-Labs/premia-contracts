# Premia - Next-Generation Options AMM

https://premia.finance

## Deployments

| Network          |                                      |
| ---------------- | ------------------------------------ |
| Ethereum Mainnet | [📜](./docs/deployments/ETHEREUM.md) |
| Arbitrum Mainnet | [📜](./docs/deployments/ARBITRUM.md) |

## Development

Install dependencies via Yarn:

```bash
yarn install
```

Setup Husky to format code on commit:

```bash
yarn prepare
```

Create a `.env` file with the following values defined:

| Key             | Description                                                       |
| --------------- | ----------------------------------------------------------------- |
| `FORK_MODE`     | if `true`, tests will be run against a mainnet fork               |
| `ALCHEMY_KEY`   | [Alchemy](https://www.alchemy.com/) API key for node connectivity |
| `ETH_TEST_PKEY` | private key for use on Rinkeby testnet                            |
| `BSC_PKEY`      | private key for use on Binance Smart Chain                        |

Create a `.secret` file containing a private key for production use.

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

## Licensing

The primary license for Premia contracts is the Business Source License 1.1 (`BUSL-1.1`), see [`LICENSE`](./LICENSE).

### Exceptions

- Interfaces are licensed under `LGPL-3.0-or-later` (as indicated in their SPDX headers), see [`LICENSE_LGPL`](./LICENSE_LGPL)
- All files in `contracts/test` remain unlicensed.
