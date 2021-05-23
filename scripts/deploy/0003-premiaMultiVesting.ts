import { ethers } from 'hardhat';
import { PremiaMultiVesting__factory } from '../../typechain';

async function main() {
  const [deployer] = await ethers.getSigners();

  const premia = '0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70';
  const treasury = '0xc22FAe86443aEed038A4ED887bbA8F5035FD12F0';

  const premiaMultiVesting = await new PremiaMultiVesting__factory(
    deployer,
  ).deploy(premia);

  console.log(
    `PremiaMultiVesting deployed at ${premiaMultiVesting.address} (Args : ${premia} )`,
  );

  await premiaMultiVesting.transferOwnership(treasury);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
