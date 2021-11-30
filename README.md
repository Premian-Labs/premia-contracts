# Premia - Next-Generation Options AMM

https://premia.finance

## Deployments

| Contract                                      | Address                                      |                                                                               |                                                                                                                                                                  |
| --------------------------------------------- | -------------------------------------------- | ----------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Premia Core**                               |                                              |                                                                               |                                                                                                                                                                  |
| PREMIA Token                                  | `0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70` | [🔗](https://etherscan.io/token/0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70)   | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/9ce2929e84ce2d6899dfcbffaf62ac7f2f4e2bf4/contracts/PremiaErc20.sol)                          |
| xPREMIA Token `PremiaStakingProxy`            | `0xF1bB87563A122211d40d393eBf1c633c330377F9` | [🔗](https://etherscan.io/token/0xF1bB87563A122211d40d393eBf1c633c330377F9)   | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/60d2175447e9acb79d7b0da3329665eba739302c/contracts/staking/PremiaStakingProxy.sol)           |
| `PremiaStakingWithFeeDiscount` implementation | `0x5068219091050bE4EfEc7c392aD68F0560C722D9` | [🔗](https://etherscan.io/address/0x5068219091050bE4EfEc7c392aD68F0560C722D9) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/60d2175447e9acb79d7b0da3329665eba739302c/contracts/staking/PremiaStakingWithFeeDiscount.sol) |
| `Premia` diamond proxy                        | `0x4F273F4Efa9ECF5Dd245a338FAd9fe0BAb63B350` | [🔗](https://etherscan.io/address/0x4F273F4Efa9ECF5Dd245a338FAd9fe0BAb63B350) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/642fd1ba54fc9d0e86d990f79e6b889c1e6fd96e/contracts/core/Premia.sol)                          |
| `ProxyManager` implementation                 | `0x4F273F4Efa9ECF5Dd245a338FAd9fe0BAb63B350` | [🔗](https://etherscan.io/address/0x7bf2392bd078C8353069CffeAcc67c094079be23) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/642fd1ba54fc9d0e86d990f79e6b889c1e6fd96e/contracts/core/ProxyManager.sol)                    |
| **Pool Proxies**                              |                                              |                                                                               |                                                                                                                                                                  |
| `PoolProxy` - WETH / DAI                      | `0xa4492fcDa2520cB68657d220f4D4aE3116359C10` | [🔗](https://etherscan.io/address/0xa4492fcDa2520cB68657d220f4D4aE3116359C10) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/642fd1ba54fc9d0e86d990f79e6b889c1e6fd96e/contracts/pool/PoolProxy.sol)                       |
| `PoolProxy` - WBTC / DAI                      | `0x1B63334f7bfDf0D753AB3101EB6d02B278db8852` | [🔗](https://etherscan.io/address/0x1B63334f7bfDf0D753AB3101EB6d02B278db8852) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/642fd1ba54fc9d0e86d990f79e6b889c1e6fd96e/contracts/pool/PoolProxy.sol)                       |
| `PoolProxy` - LINK / DAI                      | `0xFDD2FC2c73032AE1501eF4B19E499F2708F34657` | [🔗](https://etherscan.io/address/0xFDD2FC2c73032AE1501eF4B19E499F2708F34657) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/642fd1ba54fc9d0e86d990f79e6b889c1e6fd96e/contracts/pool/PoolProxy.sol)                       |
| **Pool Architecture**                         |                                              |                                                                               |                                                                                                                                                                  |
| Pool diamond proxy                            | `0x48D49466CB2EFbF05FaA5fa5E69f2984eDC8d1D7` | [🔗](https://etherscan.io/address/0x48D49466CB2EFbF05FaA5fa5E69f2984eDC8d1D7) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/642fd1ba54fc9d0e86d990f79e6b889c1e6fd96e/contracts/core/Premia.sol)                          |
| `PoolWrite` implementation                    | `0x89b36CE3491f2258793C7408Bd46aac725973BA2` | [🔗](https://etherscan.io/address/0x89b36CE3491f2258793C7408Bd46aac725973BA2) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/642fd1ba54fc9d0e86d990f79e6b889c1e6fd96e/contracts/pool/PoolWrite.sol)                       |
| `PoolIO` implementation                       | `0xf61F5830E14CD418893B216C7bfd356C200f1b40` | [🔗](https://etherscan.io/address/0xf61F5830E14CD418893B216C7bfd356C200f1b40) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/642fd1ba54fc9d0e86d990f79e6b889c1e6fd96e/contracts/pool/PoolIO.sol)                          |
| `PoolView` implementation                     | `0x14AC2DA11C2CF07eA4c64C83BE108b8F11e48F20` | [🔗](https://etherscan.io/address/0x14AC2DA11C2CF07eA4c64C83BE108b8F11e48F20) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/dfde531a3a73496cbab5b3648061324eaa2bc7fc/contracts/pool/PoolView.sol)                        |
| `PoolExercise` implementation                 | `0x657b70FE0B8d49e5af63b2f874E403a291358165` | [🔗](https://etherscan.io/address/0x657b70FE0B8d49e5af63b2f874E403a291358165) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/642fd1ba54fc9d0e86d990f79e6b889c1e6fd96e/contracts/pool/PoolExercise.sol)                    |
| `PoolSettings` implementation                 | `0x9d22C080fdE848f47B0c7654483715f27e44E433` | [🔗](https://etherscan.io/address/0x9d22C080fdE848f47B0c7654483715f27e44E433) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/642fd1ba54fc9d0e86d990f79e6b889c1e6fd96e/contracts/pool/PoolSettings.sol)                    |
| IVOL Oracle `ProxyUpgradeableOwnable`         | `0x3A87bB29b984d672664Aa1dD2d19D2e8b24f0f2A` | [🔗](https://etherscan.io/address/0x3A87bB29b984d672664Aa1dD2d19D2e8b24f0f2A) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/642fd1ba54fc9d0e86d990f79e6b889c1e6fd96e/contracts/ProxyUpgradeableOwnable.sol)              |
| `VolatilitySurfaceOracle` implementation      | `0x089E3422F23A57fD07ae68a4ffB7268B3bd78Fa2` | [🔗](https://etherscan.io/address/0x089E3422F23A57fD07ae68a4ffB7268B3bd78Fa2) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/642fd1ba54fc9d0e86d990f79e6b889c1e6fd96e/contracts/oracle/VolatilitySurfaceOracle.sol)       |
| **Periphery**                                 |                                              |                                                                               |                                                                                                                                                                  |
| `PremiaMiningProxy`                           | `0x9aBB27581c2E46A114F8C367355851e0580e9703` | [🔗](https://etherscan.io/address/0x9aBB27581c2E46A114F8C367355851e0580e9703) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/642fd1ba54fc9d0e86d990f79e6b889c1e6fd96e/contracts/mining/PremiaMiningProxy.sol)             |
| `PremiaMining` implementation                 | `0x1b890F72B21233CB38666Fb81161C4bBE15F1f5D` | [🔗](https://etherscan.io/address/0x1b890F72B21233CB38666Fb81161C4bBE15F1f5D) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/fc0ad1cd230ad1302744b86f4e2dd90273bb51e7/contracts/mining/PremiaMining.sol)                  |
| Mining `PremiaDevFund`                        | `0x81d6F46981B4fE4A6FafADDa716eE561A17761aE` | [🔗](https://etherscan.io/address/0x81d6F46981B4fE4A6FafADDa716eE561A17761aE) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/9ce2929e84ce2d6899dfcbffaf62ac7f2f4e2bf4/contracts/PremiaDevFund.sol)                        |
| PremiaMaker `ProxyUpgradeableOwnable`         | `0xC4B2C51f969e0713E799De73b7f130Fb7Bb604CF` | [🔗](https://etherscan.io/address/0xC4B2C51f969e0713E799De73b7f130Fb7Bb604CF) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/642fd1ba54fc9d0e86d990f79e6b889c1e6fd96e/contracts/ProxyUpgradeableOwnable.sol)              |
| `PremiaMaker` implementation                  | `0x170d3d92d3E33c7F9a58a27bd082736408cd2c28` | [🔗](https://etherscan.io/address/0xF92b8AD7a62437142C4bf87D91e2bE0Fe1F44e9f) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/642fd1ba54fc9d0e86d990f79e6b889c1e6fd96e/contracts/PremiaMaker.sol)                          |
| `PremiaFeeDiscount`                           | `0xF5aae75D1AD6fDD62Cce66137F2674c96FEda854` | [🔗](https://etherscan.io/address/0xF5aae75D1AD6fDD62Cce66137F2674c96FEda854) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/9ce2929e84ce2d6899dfcbffaf62ac7f2f4e2bf4/contracts/PremiaFeeDiscount.sol)                    |
| **Miscellaneous**                             |                                              |                                                                               |                                                                                                                                                                  |
| Premia Deployer (EOA)                         | `0xC7f8D87734aB2cbf70030aC8aa82abfe3e8126cb` | [🔗](https://etherscan.io/address/0xC7f8D87734aB2cbf70030aC8aa82abfe3e8126cb) |                                                                                                                                                                  |
| `PremiaDevFund`                               | `0xE43147dAa592C3f88402C6E2b932DB9d97bc1C7f` | [🔗](https://etherscan.io/address/0xE43147dAa592C3f88402C6E2b932DB9d97bc1C7f) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/9ce2929e84ce2d6899dfcbffaf62ac7f2f4e2bf4/contracts/PremiaDevFund.sol)                        |
| `PremiaVesting`                               | `0x3a00BC08F4Ee12568231dB85D077864275a495b3` | [🔗](https://etherscan.io/address/0x3a00BC08F4Ee12568231dB85D077864275a495b3) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/9ce2929e84ce2d6899dfcbffaf62ac7f2f4e2bf4/contracts/PremiaVesting.sol)                        |
| `PremiaVesting`                               | `0xdF69C895E7490d90b14A278Add8Aa4eC844a696a` | [🔗](https://etherscan.io/address/0xdF69C895E7490d90b14A278Add8Aa4eC844a696a) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/9ce2929e84ce2d6899dfcbffaf62ac7f2f4e2bf4/contracts/PremiaVesting.sol)                        |
| `PremiaVesting`                               | `0xD3C8Ce2793c60c9e8464FC08Ec7691613057c43C` | [🔗](https://etherscan.io/address/0xD3C8Ce2793c60c9e8464FC08Ec7691613057c43C) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/9ce2929e84ce2d6899dfcbffaf62ac7f2f4e2bf4/contracts/PremiaVesting.sol)                        |
| `PremiaVesting`                               | `0x1ede971F31f7630baE9f14d349273621A5145381` | [🔗](https://etherscan.io/address/0x1ede971F31f7630baE9f14d349273621A5145381) | [📁](https://github.com/PremiaFinance/premia-contracts-private/blob/9ce2929e84ce2d6899dfcbffaf62ac7f2f4e2bf4/contracts/PremiaVesting.sol)                        |

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
| `ETH_MAIN_KEY`  | private key for use on Ethereum mainnet                           |
| `BSC_PKEY`      | private key for use on Binance Smart Chain                        |

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
