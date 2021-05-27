import Dotenv from 'dotenv';
Dotenv.config();

import '@nomiclabs/hardhat-waffle';
import '@typechain/hardhat';
import 'hardhat-docgen';
import 'hardhat-gas-reporter';
import 'hardhat-spdx-license-identifier';
import 'solidity-coverage';

import './tasks/deploy.js';
import './tasks/accounts.js';

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
};
