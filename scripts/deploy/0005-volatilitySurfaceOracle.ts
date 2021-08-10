import { ethers } from 'hardhat';
import {
  VolatilitySurfaceOracle__factory,
  VolatilitySurfaceOracleProxy__factory,
} from '../../typechain';

async function main() {
  const [deployer] = await ethers.getSigners();

  const implementation = await new VolatilitySurfaceOracle__factory(
    deployer,
  ).deploy();

  console.log(
    `VolatilitySurfaceOracle implementation deployed at ${implementation.address}`,
  );

  const proxy = await new VolatilitySurfaceOracleProxy__factory(
    deployer,
  ).deploy(implementation.address);

  console.log(
    `VolatilitySurfaceOracle proxy deployed at ${proxy.address} (Args : ${implementation.address} )`,
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
