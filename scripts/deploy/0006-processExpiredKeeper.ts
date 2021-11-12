import { ethers } from 'hardhat';
import { ProcessExpiredKeeper__factory } from '../../typechain';

async function main() {
  const [deployer] = await ethers.getSigners();

  const keeper = await new ProcessExpiredKeeper__factory(deployer).deploy(
    '0x4F273F4Efa9ECF5Dd245a338FAd9fe0BAb63B350',
  );

  console.log(`Keeper deployed deployed at ${keeper.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
