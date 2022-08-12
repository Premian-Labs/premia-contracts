import { ethers } from 'hardhat';
import { ExchangeHelper__factory } from '../../typechain';

async function main() {
  const [deployer] = await ethers.getSigners();

  const exchangeHelper = await new ExchangeHelper__factory(deployer).deploy();

  console.log('Exchange Helper : ', exchangeHelper.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
