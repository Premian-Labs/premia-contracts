import { deployV2, TokenAddresses } from '../../utils/deployV2';
import { fixedFromFloat } from '@premia/utils';
import {
  ERC20Mock__factory,
  PremiaErc20__factory,
  PremiaMakerKeeper__factory,
  ProcessExpiredKeeper__factory,
} from '../../../typechain';
import { ethers } from 'hardhat';
import { deployV1 } from '../../utils/deployV1';

async function main() {
  const [deployer] = await ethers.getSigners();
  const premia = await new PremiaErc20__factory(deployer).deploy();

  const contracts = await deployV1(
    deployer,
    deployer.address,
    true,
    true,
    premia.address,
  );

  // Kovan addresses
  const weth = '0xd0A1E359811322d97991E03f863a0C30C2cF029C';

  const eth = await new ERC20Mock__factory(deployer).deploy('ETH', 18);
  const dai = await new ERC20Mock__factory(deployer).deploy('DAI', 18);
  const wbtc = await new ERC20Mock__factory(deployer).deploy('WBTC', 8);
  const link = await new ERC20Mock__factory(deployer).deploy('LINK', 18);

  const tokens: TokenAddresses = {
    ETH: eth.address,
    DAI: dai.address,
    BTC: wbtc.address,
    LINK: link.address,
  };

  // Kovan addresses
  const oracles: TokenAddresses = {
    ETH: '0x9326BFA02ADD2366b30bacB125260Af641031331',
    DAI: '0x777A68032a88E5A84678A77Af2CD65A7b3c0775a',
    BTC: '0x6135b13325bfC4B00278B4abC5e20bbce2D6580e',
    LINK: '0x396c5E36DD0a0F5a5D33dae44368D4193f69a1F0',
  };

  const premiaDiamond = await deployV2(
    weth,
    premia.address,
    fixedFromFloat(0.01),
    contracts.premiaMaker.address,
    contracts.premiaFeeDiscount.address,
    tokens,
    oracles,
  );

  const premiaMakerKeeper = await new PremiaMakerKeeper__factory(
    deployer,
  ).deploy(contracts.premiaMaker.address, premiaDiamond);

  const processExpiredKeeper = await new ProcessExpiredKeeper__factory(
    deployer,
  ).deploy(premiaDiamond);

  console.log('PremiaMakerKeeper', premiaMakerKeeper.address);
  console.log('ProcessExpiredKeeper', processExpiredKeeper.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
