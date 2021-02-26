require('@nomiclabs/hardhat-waffle');
require('hardhat-dependency-compiler');
require('hardhat-docgen');
require('hardhat-gas-reporter');
require('hardhat-spdx-license-identifier');
require('solidity-coverage');
require('dotenv').config();

require('./tasks/deploy.js');
require('./tasks/accounts.js');
const defaultNetwork = "generic";

module.exports = {
  defaultNetwork,
  solidity: {
    version: '0.8.1',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },

  networks: {
    generic: {
      // set URL for external network
      url: process.env.URL,
      accounts: {
        mnemonic: process.env.MNEMONIC,
      },
    },
  },

  dependencyCompiler: {
    paths: [
      '@solidstate/contracts/access/SafeOwnable.sol',
      '@solidstate/contracts/proxy/diamond/DiamondCuttable.sol',
      '@solidstate/contracts/proxy/diamond/DiamondLoupe.sol',
    ],
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
