import { PremiaOption__factory } from '../contractsTyped';
import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();
  const premiaOption = PremiaOption__factory.connect(
    '0xee936a8f3a602da2ea5b6a2a9ff90796dc2047c7',
    deployer,
  );

  // await premiaOption.setURI('https://rope.lol/api/RMU/{id}.json');
  const uri = await premiaOption.uri(1);
  console.log('URI', uri);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
