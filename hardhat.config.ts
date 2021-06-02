import Dotenv from 'dotenv';

Dotenv.config();

import '@nomiclabs/hardhat-waffle';
import '@typechain/hardhat';
import 'hardhat-docgen';
import 'hardhat-gas-reporter';
import 'hardhat-spdx-license-identifier';
import 'solidity-coverage';

import './tasks/deploy';
import './tasks/accounts';

const ETH_TEST_KEY = process.env.ETH_TEST_PKEY;
const ALCHEMY_KEY = process.env.ALCHEMY_KEY;

export default {
  solidity: {
    version: '0.8.4',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },

  networks: {
    kovan: {
      url: `${process.env.KOVAN_URL}`,
      accounts: {
        mnemonic: process.env.MNEMONIC,
      },
    },

    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: [ETH_TEST_KEY],
      blockGasLimit: 120000000000,
      timeout: 300000,
    },
  },

  docgen: {
    runOnCompile: true,
    clear: true,
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
  },
};
