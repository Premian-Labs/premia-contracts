import { ethers } from 'hardhat';
import { PremiaUncutErc20Wrapper__factory } from '../../contractsTyped';

// This will need to be deployed after end of PBC, in order to know start price of the bonding curve which will be the final price of the PBC
async function main() {
  const [deployer] = await ethers.getSigners();

  const uPremia = '0x8406C6C1DB4D224C8B0cF7859c0881Ddd68D4761';
  const premiaOption = '0x5920cb60B1c62dC69467bf7c6EDFcFb3f98548c0';

  const uPremiaWrapper = await new PremiaUncutErc20Wrapper__factory(
    deployer,
  ).deploy(uPremia, premiaOption);

  console.log(
    `uPremiaWrapper deployed at ${uPremiaWrapper.address} (Args : ${uPremia} / ${premiaOption})`,
  );

  await uPremiaWrapper.transferOwnership(premiaOption);

  // ToDo after deployment :
  // - Add wrapper as uPremia minter
  // - Set wrapper as uPremia on premiaOption
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
