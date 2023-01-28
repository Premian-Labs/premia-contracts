import { ethers } from 'hardhat';
import { PremiaMining__factory } from '../../typechain';

async function main() {
  const [deployer] = await ethers.getSigners();

  let premiaDiamond: string;
  let premia: string;
  let vxPremia: string;

  const chainId = await deployer.getChainId();

  if (chainId === 1) {
    premiaDiamond = '0x4F273F4Efa9ECF5Dd245a338FAd9fe0BAb63B350';
    premia = '0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70';
    vxPremia = '0xF1bB87563A122211d40d393eBf1c633c330377F9';
  } else if (chainId === 42161) {
    premiaDiamond = '0x89b36CE3491f2258793C7408Bd46aac725973BA2';
    premia = '0x51fc0f6660482ea73330e414efd7808811a57fa2';
    vxPremia = '0x3992690E5405b69d50812470B0250c878bFA9322';
  } else if (chainId === 10) {
    premiaDiamond = '0x48D49466CB2EFbF05FaA5fa5E69f2984eDC8d1D7';
    premia = '0x374Ad0f47F4ca39c78E5Cc54f1C9e426FF8f231A';
    vxPremia = '0x17BAe0E202f6A22f2631B037C0660A88990d6023';
  } else if (chainId === 250) {
    premiaDiamond = '0xD9e169e31394efccd78CC0b63a8B09B4D71b705E';
    premia = '0x3028b4395F98777123C7da327010c40f3c7Cc4Ef';
    vxPremia = '0x9BCb8cE123E4bFA53C2319b12DbFB6F7B7675a30';
  } else {
    throw new Error('ChainId not implemented');
  }

  const premiaMining = await new PremiaMining__factory(deployer).deploy(
    premiaDiamond,
    premia,
    vxPremia,
  );

  console.log(
    `PremiaMining : ${premiaMining.address} ${premiaDiamond} ${premia} ${vxPremia}`,
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
