import Dotenv from 'dotenv';
import fs from 'fs';
// Hardhat plugins
import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-etherscan';
import '@typechain/hardhat';
import 'hardhat-abi-exporter';
import 'hardhat-artifactor';
import 'hardhat-contract-sizer';
import 'hardhat-dependency-compiler';
import 'hardhat-docgen';
import 'hardhat-gas-reporter';
import 'hardhat-spdx-license-identifier';
import 'solidity-coverage';
// tasks and task overrides
import './tasks/accounts';
import './tasks/typechain_generate_types';

Dotenv.config();

const FORK_MODE = process.env.FORK_MODE === 'true';
const ETH_TEST_KEY = process.env.ETH_TEST_PKEY;
const BSC_KEY = process.env.BSC_PKEY;
const ALCHEMY_KEY = process.env.ALCHEMY_KEY;
const ETHERSCAN_KEY = process.env.ETHERSCAN_KEY;
const ETH_MAIN_KEY = fs.readFileSync('./.secret').toString();

export default {
  solidity: {
    compilers: [
      {
        version: '0.8.9',
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
              blockNumber: 13717777,
            },
          }
        : {}),
    },
    mainnet: {
      url: `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: [ETH_MAIN_KEY],
      //gas: 120000000000,
      // blockGasLimit: 120000000000,
      // gasPrice: 100000000000,
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
    ropsten: {
      url: `https://eth-ropsten.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: [ETH_TEST_KEY],
      //gas: 120000000000,
      blockGasLimit: 120000000000,
      //gasPrice: 10,
      timeout: 300000,
    },
    arbitrum: {
      url: `https://arb1.arbitrum.io/rpc`,
      accounts: [ETH_MAIN_KEY],
      //gas: 120000000000,
      // blockGasLimit: 120000000000,
      //gasPrice: 10,
      timeout: 300000,
    },
    rinkebyArbitrum: {
      url: `https://rinkeby.arbitrum.io/rpc`,
      accounts: [ETH_MAIN_KEY],
      //gas: 120000000000,
      // blockGasLimit: 120000000000,
      // gasPrice: 100000000000,
      timeout: 100000,
    },
    bsc: {
      url: `https://bsc-dataseed.binance.org/`,
      accounts: [BSC_KEY],
      //gas: 120000000000,
      blockGasLimit: 120000000000,
      //gasPrice: 10,
      timeout: 300000,
    },
  },

  abiExporter: {
    path: './abi',
    clear: true,
    flat: true,
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

  etherscan: {
    apiKey: ETHERSCAN_KEY,
  },

  gasReporter: {
    enabled: process.env.REPORT_GAS === 'true',
  },

  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: true,
  },

  typechain: {
    alwaysGenerateOverloads: true,
    outDir: 'typechain',
  },

  mocha: {
    timeout: 60000,
  },
};
