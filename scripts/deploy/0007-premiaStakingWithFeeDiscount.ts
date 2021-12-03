import { ethers } from 'hardhat';
import {
  PremiaStakingProxy__factory,
  PremiaStakingWithFeeDiscount__factory,
} from '../../typechain';

async function main() {
  const [deployer] = await ethers.getSigners();

  const premia = '0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70';
  const oldFeeDiscount = '0xF5aae75D1AD6fDD62Cce66137F2674c96FEda854';
  const oldStaking = '0x16f9D564Df80376C61AC914205D3fDfF7057d610';

  const impl = await new PremiaStakingWithFeeDiscount__factory(deployer).deploy(
    premia,
    oldFeeDiscount,
    oldStaking,
  );

  console.log(
    `PremiaStakingWithFeeDiscount impl : ${impl.address} (Args: ${premia} / ${oldFeeDiscount} / ${oldStaking})`,
  );

  const proxy = await new PremiaStakingProxy__factory(deployer).deploy(
    impl.address,
  );

  console.log(
    `PremiaStakingWithFeeDiscount proxy : ${proxy.address} (Args: ${impl.address})`,
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
