require('dotenv').config();

require('@nomiclabs/hardhat-waffle');
require('hardhat-docgen');
require('hardhat-gas-reporter');
require('hardhat-spdx-license-identifier');
require('solidity-coverage');

require('./tasks/deploy.js');
require('./tasks/accounts.js');

module.exports = {
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
      url: `${ process.env.KOVAN_URL }`,
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
