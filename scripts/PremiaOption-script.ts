import { ethers } from 'hardhat';

async function main() {
  // We get the contract to deploy

  const PremiaOption = await ethers.getContractFactory('PremiaOption');
  const premiaOption = await PremiaOption.deploy('dummyURI');

  await premiaOption.deployed();

  console.log('premiaOption deployed to:', premiaOption.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
