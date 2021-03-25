require('dotenv').config();

require('@nomiclabs/hardhat-waffle');
require('hardhat-dependency-compiler');
require('hardhat-docgen');
require('hardhat-gas-reporter');
require('hardhat-spdx-license-identifier');
require('solidity-coverage');

require('./tasks/deploy.js');
require('./tasks/accounts.js');

module.exports = {
  defaultNetwork: process.env.NETWORK,

  solidity: {
    version: '0.8.3',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },

  networks: {
    kovan: {
      url: 'https://kovan.infura.io/v3/'+process.env.INFURA_KEY,
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
    enabled: process.env.REPORT_GAS,
  },

  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: true,
  },
};
