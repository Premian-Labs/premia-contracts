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

| Key                 | Description                                                              |
| ------------------- | ------------------------------------------------------------------------ |
| `API_KEY_ALCHEMY`   | [Alchemy](https://www.alchemy.com/) API key for node connectivity        |
| `API_KEY_ETHERSCAN` | [Etherscan](https://etherscan.io//) API key for source code verification |
| `PKEY_ETH_TEST`     | private key for test/development use on testnets                         |
| `FORK_MODE`         | if `true`, the local Hardhat network will be forked from mainnet         |
| `REPORT_GAS`        | if `true`, a gas report will be generated after running tests            |

Create a `.env.secret` file with the following values defined:

| Key             | Description                                |
| --------------- | ------------------------------------------ |
| `PKEY_ETH_MAIN` | private key for production use on mainnets |

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
