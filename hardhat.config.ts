import { task } from 'hardhat/config';
import Dotenv from 'dotenv';
import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-etherscan';
import 'hardhat-contract-sizer';
import fs from 'fs';

Dotenv.config();

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task('accounts', 'Prints the list of accounts', async (args, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(await account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const ETH_TEST_KEY = process.env.ETH_TEST_PKEY;
const ALCHEMY_KEY = process.env.ALCHEMY_KEY;
const ETHERSCAN_KEY = process.env.ETHERSCAN_KEY;
const ETH_MAIN_KEY = fs.readFileSync('./.secret').toString();

export default {
  solidity: {
    compilers: [
      {
        version: '0.8.3',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: '0.7.6',
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
        version: '0.4.18',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
    overrides: {
      'contracts/PremiaOption.sol': {
        version: '0.8.2',
        settings: {
          optimizer: {
            enabled: true,
            runs: 50,
          },
        },
      },
    },
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      blockGasLimit: 180000000000,
    },

    mainnet: {
      url: `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: [ETH_MAIN_KEY],
      //gas: 120000000000,
      // blockGasLimit: 120000000000,
      gasPrice: 160000000000,
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
  },
  ...(ETHERSCAN_KEY
    ? {
        etherscan: {
          apiKey: ETHERSCAN_KEY,
        },
      }
    : {}),
};
