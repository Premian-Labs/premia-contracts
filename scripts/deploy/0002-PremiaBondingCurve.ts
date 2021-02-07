import { ethers } from 'hardhat';
import { PremiaBondingCurve__factory } from '../../contractsTyped';
import { BigNumberish } from 'ethers';

// This will need to be deployed after end of PBC, in order to know start price of the bonding curve which will be the final price of the PBC
async function main() {
  const [deployer] = await ethers.getSigners();

  const premia = '0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70';
  const treasury = '0xc22FAe86443aEed038A4ED887bbA8F5035FD12F0';
  const startPrice = '1919488000000000';
  const k = '1800000000';

  const premiaBondingCurve = await new PremiaBondingCurve__factory(
    deployer,
  ).deploy(premia, treasury, startPrice, k);

  console.log(
    `PremiaBondingCurve deployed at ${premiaBondingCurve.address} (Args : ${premia} / ${treasury} / ${startPrice} / ${k})`,
  );

  await premiaBondingCurve.transferOwnership(treasury);
  console.log(`PremiaBondingCurve ownership transferred to ${treasury}`);

  // ToDo after deployment :
  //  - Set premiaBondingCurve on PremiaMaker, from the multisig
  //  - Send Premia to bonding curve contract
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
