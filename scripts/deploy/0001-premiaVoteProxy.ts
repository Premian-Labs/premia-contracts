import { ethers } from 'hardhat';
import {
  PremiaVoteProxy__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';

async function main() {
  const [deployer] = await ethers.getSigners();

  const premia = '0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70';
  const xPremia = '0xF1bB87563A122211d40d393eBf1c633c330377F9';
  const premiaFeeDiscount = '0xF1bB87563A122211d40d393eBf1c633c330377F9';

  // const premia = '0x7a8864eA3A4B855D0d359F16D38d966ce018aDb9';
  // const xPremia = '0x65191E877AE65ff9c4959b8389Dd7E7881cDAe38';
  // const premiaFeeDiscount = '0xbaBd6824CC148b509E0C5B9657D3A4C733aFdFFE';

  const impl = await new PremiaVoteProxy__factory(deployer).deploy(
    premia,
    xPremia,
    premiaFeeDiscount,
  );

  const proxy = await new ProxyUpgradeableOwnable__factory(deployer).deploy(
    impl.address,
  );

  console.log(
    `Vote proxy implementation deployed at ${impl.address} (Args : ${premia} / ${xPremia} / ${premiaFeeDiscount})`,
  );

  console.log(`Proxy deployed at ${proxy.address} (${impl.address})`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
