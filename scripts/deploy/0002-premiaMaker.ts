import { ethers } from 'hardhat';
import {
  PremiaMaker__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';

async function main() {
  const [deployer] = await ethers.getSigners();

  const premia = '0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70';
  const premiaStaking = '0xF1bB87563A122211d40d393eBf1c633c330377F9';
  const treasury = '0xc22FAe86443aEed038A4ED887bbA8F5035FD12F0';

  let uniswapRouters = [
    '0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F', // SushiSwap router
    // '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D', // Uniswap router
  ];

  const impl = await new PremiaMaker__factory(deployer).deploy(
    premia,
    premiaStaking,
    treasury,
  );

  console.log(
    `Implementation contract deployed at ${impl.address} (Args : ${premia}, ${premiaStaking}, ${treasury})`,
  );

  const proxy = await new ProxyUpgradeableOwnable__factory(deployer).deploy(
    impl.address,
  );

  const premiaMaker = PremiaMaker__factory.connect(proxy.address, deployer);
  await premiaMaker.addWhitelistedRouter(uniswapRouters);
  console.log('Whitelisted uniswap routers on PremiaMaker');

  await proxy.transferOwnership(treasury);
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
