import { ethers } from 'hardhat';
import { PremiaVoteProxy__factory } from '../../typechain';

// This will need to be deployed after end of PBC, in order to know start price of the bonding curve which will be the final price of the PBC
async function main() {
  const [deployer] = await ethers.getSigners();

  const premia = '0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70';
  const xPremia = '0x16f9D564Df80376C61AC914205D3fDfF7057d610';
  const premiaFeeDiscount = '0xF5aae75D1AD6fDD62Cce66137F2674c96FEda854';

  // const premia = '0x7a8864eA3A4B855D0d359F16D38d966ce018aDb9';
  // const xPremia = '0x65191E877AE65ff9c4959b8389Dd7E7881cDAe38';
  // const premiaFeeDiscount = '0xbaBd6824CC148b509E0C5B9657D3A4C733aFdFFE';

  const premiaVoteProxy = await new PremiaVoteProxy__factory(deployer).deploy(
    premia,
    xPremia,
    premiaFeeDiscount,
  );

  console.log(
    `Vote proxy deployed at ${premiaVoteProxy.address} (Args : ${premia} / ${xPremia} / ${premiaFeeDiscount})`,
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
