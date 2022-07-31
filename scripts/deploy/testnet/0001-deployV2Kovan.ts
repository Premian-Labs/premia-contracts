import { deployPool, deployV2, PoolToken } from '../../utils/deployV2';
import { fixedFromFloat } from '@premia/utils';
import {
  ERC20Mock__factory,
  PremiaErc20__factory,
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

  const ethToken = await new ERC20Mock__factory(deployer).deploy('ETH', 18);
  const daiToken = await new ERC20Mock__factory(deployer).deploy('DAI', 18);
  const wbtcToken = await new ERC20Mock__factory(deployer).deploy('WBTC', 8);
  const linkToken = await new ERC20Mock__factory(deployer).deploy('LINK', 18);

  const eth: PoolToken = {
    tokenAddress: ethToken.address,
    oracleAddress: '0x9326BFA02ADD2366b30bacB125260Af641031331',
    minimum: '0.05',
  };

  const dai: PoolToken = {
    tokenAddress: daiToken.address,
    oracleAddress: '0x777A68032a88E5A84678A77Af2CD65A7b3c0775a',
    minimum: '200',
  };

  const btc: PoolToken = {
    tokenAddress: wbtcToken.address,
    oracleAddress: '0x6135b13325bfC4B00278B4abC5e20bbce2D6580e',
    minimum: '0.005',
  };

  const link: PoolToken = {
    tokenAddress: linkToken.address,
    oracleAddress: '0x396c5E36DD0a0F5a5D33dae44368D4193f69a1F0',
    minimum: '5',
  };

  const { premiaDiamond, proxyManager } = await deployV2(
    weth,
    premia.address,
    fixedFromFloat(0.03),
    fixedFromFloat(0.025),
    contracts.premiaMaker.address,
    contracts.xPremia.address,
  );

  await deployPool(proxyManager, dai, eth, 100);
  await deployPool(proxyManager, dai, btc, 100);
  await deployPool(proxyManager, dai, link, 100);

  const processExpiredKeeper = await new ProcessExpiredKeeper__factory(
    deployer,
  ).deploy(premiaDiamond.address);

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
