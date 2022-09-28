import Dotenv from 'dotenv';
// Hardhat plugins
import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-etherscan';
import '@solidstate/hardhat-4byte-uploader';
import '@solidstate/hardhat-test-short-circuit';
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
Dotenv.config({ path: './.env.secret' });

import chai from 'chai';
import chaiAlmost from 'chai-almost';
chai.use(chaiAlmost(0.01));

const {
  API_KEY_ALCHEMY,
  API_KEY_ETHERSCAN,
  API_KEY_OPTIMISM,
  API_KEY_ARBISCAN,
  API_KEY_FTMSCAN,
  PKEY_ETH_MAIN,
  PKEY_ETH_TEST,
  FORK_MODE,
  FORK_BLOCK_NUMBER,
  REPORT_GAS,
  CACHE_PATH,
} = process.env;

export default {
  solidity: {
    compilers: [
      {
        version: '0.8.17',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      // @uniswap/v2-periphery
      {
        version: '0.6.6',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      // @uniswap/v2-core
      {
        version: '0.5.16',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      // WETH
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
  paths: {
    cache: CACHE_PATH ?? './cache',
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      blockGasLimit: 180000000000,
      ...(FORK_MODE === 'true'
        ? {
            forking: {
              url: `https://eth-mainnet.alchemyapi.io/v2/${API_KEY_ALCHEMY}`,
              blockNumber: parseInt(FORK_BLOCK_NUMBER ?? '13717777'),
            },
          }
        : {}),
    },
    mainnet: {
      url: `https://eth-mainnet.alchemyapi.io/v2/${API_KEY_ALCHEMY}`,
      accounts: [PKEY_ETH_MAIN],
      //gas: 120000000000,
      // blockGasLimit: 120000000000,
      // gasPrice: 100000000000,
      timeout: 100000,
    },
    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/${API_KEY_ALCHEMY}`,
      accounts: [PKEY_ETH_TEST],
      //gas: 120000000000,
      blockGasLimit: 120000000000,
      //gasPrice: 10,
      timeout: 300000,
    },
    goerli: {
      url: `https://eth-goerli.alchemyapi.io/v2/${API_KEY_ALCHEMY}`,
      accounts: [PKEY_ETH_TEST],
      //gas: 120000000000,
      blockGasLimit: 120000000000,
      //gasPrice: 10,
      timeout: 300000,
    },
    optimism: {
      url: `https://mainnet.optimism.io`,
      accounts: [PKEY_ETH_MAIN],
      timeout: 300000,
    },
    arbitrum: {
      url: `https://arb1.arbitrum.io/rpc`,
      accounts: [PKEY_ETH_MAIN],
      //gas: 120000000000,
      // blockGasLimit: 120000000000,
      //gasPrice: 10,
      timeout: 300000,
    },
    rinkebyArbitrum: {
      url: `https://rinkeby.arbitrum.io/rpc`,
      accounts: [PKEY_ETH_TEST],
      //gas: 120000000000,
      // blockGasLimit: 120000000000,
      // gasPrice: 100000000000,
      timeout: 100000,
    },
    goerliArbitrum: {
      url: `https://goerli-rollup.arbitrum.io/rpc`,
      accounts: [PKEY_ETH_TEST],
      //gas: 120000000000,
      // blockGasLimit: 120000000000,
      // gasPrice: 100000000000,
      timeout: 100000,
    },
    fantomDev: {
      url: `https://rpc.ftm.tools/`,
      accounts: [PKEY_ETH_TEST],
      timeout: 100000,
    },
    fantom: {
      url: `https://rpc.ftm.tools/`,
      accounts: [PKEY_ETH_MAIN],
      timeout: 100000,
    },
  },

  abiExporter: {
    runOnCompile: true,
    path: './abi',
    clear: true,
    flat: true,
    except: ['@uniswap'],
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
    apiKey: {
      mainnet: API_KEY_ETHERSCAN,
      arbitrumOne: API_KEY_ARBISCAN,
      opera: API_KEY_FTMSCAN,
      optimisticEthereum: API_KEY_OPTIMISM,
    },
  },

  gasReporter: {
    enabled: REPORT_GAS === 'true',
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
