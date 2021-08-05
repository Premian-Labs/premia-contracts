import Dotenv from 'dotenv';
import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-etherscan';
import '@typechain/hardhat';
import 'hardhat-abi-exporter';
import 'hardhat-artifactor';
import 'hardhat-dependency-compiler';
import 'hardhat-docgen';
import 'hardhat-gas-reporter';
import 'hardhat-spdx-license-identifier';
import 'solidity-coverage';
import 'hardhat-contract-sizer';
import fs from 'fs';

import './tasks/accounts';
import './tasks/typechain_generate_types';

Dotenv.config();

const FORK_MODE = process.env.FORK_MODE === 'true';
const ETH_TEST_KEY = process.env.ETH_TEST_PKEY;
const ALCHEMY_KEY = process.env.ALCHEMY_KEY;
const ETHERSCAN_KEY = process.env.ETHERSCAN_KEY;
const ETH_MAIN_KEY = fs.readFileSync('./.secret').toString();

export default {
  solidity: {
    compilers: [
      {
        version: '0.8.6',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: '0.6.12',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: '0.6.6',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: '0.5.16',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: '0.4.18',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      blockGasLimit: 180000000000,
      ...(FORK_MODE
        ? {
            forking: {
              url: `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_KEY}`,
              blockNumber: 12739250,
            },
          }
        : {}),
    },

    mainnet: {
      url: `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: [ETH_MAIN_KEY],
      //gas: 120000000000,
      // blockGasLimit: 120000000000,
      gasPrice: 100000000000,
      timeout: 100000,
    },
    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: [ETH_TEST_KEY],
      //gas: 120000000000,
      blockGasLimit: 120000000000,
      //gasPrice: 10,
      timeout: 300000,
    },
    kovan: {
      url: `https://eth-kovan.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: [ETH_TEST_KEY],
      //gas: 120000000000,
      blockGasLimit: 120000000000,
      //gasPrice: 10,
      timeout: 300000,
    },
  },

  dependencyCompiler: {
    paths: [
      '@uniswap/v2-core/contracts/UniswapV2Factory.sol',
      '@uniswap/v2-core/contracts/UniswapV2Pair.sol',
      '@uniswap/v2-periphery/contracts/UniswapV2Router02.sol',
    ],
  },

  docgen: {
    runOnCompile: false,
    clear: true,
  },

  gasReporter: {
    enabled: process.env.REPORT_GAS === 'true',
  },

  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: true,
  },

  abiExporter: {
    path: './abi',
    clear: true,
    flat: true,
  },

  typechain: {
    alwaysGenerateOverloads: true,
  },

  ...(ETHERSCAN_KEY
    ? {
        etherscan: {
          apiKey: ETHERSCAN_KEY,
        },
      }
    : {}),

  mocha: {
    timeout: 60000,
  },
};
