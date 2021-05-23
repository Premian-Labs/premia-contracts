import { ethers } from 'hardhat';
import { PremiaErc20__factory } from '../../typechain';

async function main() {
  const [deployer] = await ethers.getSigners();

  const premia = await new PremiaErc20__factory(deployer).deploy();
  console.log(`PremiaErc20 deployed at ${premia.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
