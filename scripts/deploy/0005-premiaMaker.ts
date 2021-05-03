import { ethers } from 'hardhat';
import { PremiaMaker__factory } from '../../contractsTyped';

// This will need to be deployed after end of PBC, in order to know start price of the bonding curve which will be the final price of the PBC
async function main() {
  const [deployer] = await ethers.getSigners();

  const premia = '0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70';
  const premiaStaking = '0x16f9D564Df80376C61AC914205D3fDfF7057d610';
  const treasury = '0xc22FAe86443aEed038A4ED887bbA8F5035FD12F0';

  let uniswapRouters = [
    '0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F', // SushiSwap router
    // '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D', // Uniswap router
  ];

  const premiaMaker = await new PremiaMaker__factory(deployer).deploy(
    premia,
    premiaStaking,
    treasury,
  );

  // Badger custom swap path
  await premiaMaker.setCustomPath(
    '0x3472A5A71965499acd81997a54BBA8D852C6E53d',
    [
      '0x3472A5A71965499acd81997a54BBA8D852C6E53d', // Badger
      '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599', // Wbtc
      '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', // Weth
      premia,
    ],
  );

  console.log(
    `PremiaMaker contract deployed at ${premiaMaker.address} (Args : ${premia}, ${premiaStaking}, ${treasury})`,
  );

  await premiaMaker.addWhitelistedRouter(uniswapRouters);
  console.log('Whitelisted uniswap routers on PremiaMaker');

  await premiaMaker.transferOwnership(treasury);
  console.log(`PremiaMaker ownership transferred to ${treasury}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
